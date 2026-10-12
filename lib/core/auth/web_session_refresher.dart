import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../runtime/runtime_provider.dart';
import 'web_session_controller.dart';
import 'web_session_platform.dart';

/// The raw markers a page exposed to the probe script, before any verdict
/// mapping. A page showing neither a username nor a CSRF token is almost
/// always a WAF/interstitial challenge (PerimeterX, AWS WAF): it redirects
/// once its JavaScript has solved, so the probe must stay alive and observe
/// the follow-up navigation instead of treating the first load stop as the
/// final answer.
final class WebSessionProbeObservation {
  const WebSessionProbeObservation({
    required this.pageUsername,
    required this.csrf,
  });

  /// The rendered `@publicSession.user.username`, or `null` when the page
  /// exposed no user marker at all (challenge, incomplete load, parser gap).
  final String? pageUsername;

  /// The page's `__CSRF_TOKEN__`, empty when absent.
  final String csrf;

  /// Pages that carry at least one DeviantArt session marker are final
  /// observations; marker-less pages are expected to be replaced by a
  /// challenge redirect.
  bool get hasSessionMarkers => pageUsername != null || csrf.isNotEmpty;
}

/// What a real (headless WebView) load of the DeviantArt home page reported.
///
/// This is the authoritative session probe: it carries the same cookie store,
/// user agent and TLS stack as the login WebView, so a WAF challenge served to
/// a bare Dio request does not apply here.
enum WebSessionProbeOutcome {
  /// The page rendered a signed-in username.
  confirmed,

  /// The page rendered but reported no signed-in user.
  anonymous,

  /// The page never produced a usable answer (navigation failed, challenge,
  /// timeout). Not a logged-out signal.
  unavailable,
}

final class WebSessionProbeResult {
  const WebSessionProbeResult.confirmed({
    required this.csrf,
    required this.username,
  }) : outcome = WebSessionProbeOutcome.confirmed;

  const WebSessionProbeResult.anonymous({this.csrf = ''})
    : outcome = WebSessionProbeOutcome.anonymous,
      username = '';

  const WebSessionProbeResult.unavailable({this.csrf = ''})
    : outcome = WebSessionProbeOutcome.unavailable,
      username = '';

  final WebSessionProbeOutcome outcome;
  final String csrf;
  final String username;

  bool get succeeded => outcome == WebSessionProbeOutcome.confirmed;
}

/// Maps one real-browser page observation onto a probe verdict.
///
/// Only explicit evidence decides between the three outcomes:
/// - a rendered username → confirmed;
/// - the page itself reporting `anonymous` → anonymous;
/// - anything unresolvable (missing `__INITIAL_STATE__`, missing
///   `@publicSession`, challenge page, incomplete load) → unavailable.
/// "Could not parse a username" must never become "the user is logged out".
WebSessionProbeResult webSessionProbeResultFromPage({
  required String? pageUsername,
  required String csrf,
}) {
  if (pageUsername == null || pageUsername.isEmpty) {
    return WebSessionProbeResult.unavailable(csrf: csrf);
  }
  if (pageUsername == 'anonymous') {
    return WebSessionProbeResult.anonymous(csrf: csrf);
  }
  return WebSessionProbeResult.confirmed(csrf: csrf, username: pageUsername);
}

/// Loads a public page in a hidden browser so website-only metadata adapters
/// can obtain the anonymous CSRF/cookies expected by DeviantArt. It never asks
/// the user to log in and is not part of App authentication.
final webSessionRefresherProvider = Provider<WebSessionRefresher>((ref) {
  final refresher = WebSessionRefresher(ref);
  ref.onDispose(() => unawaited(refresher._dispose()));
  return refresher;
});

/// The real-browser probe used to arbitrate session-state answers. Injectable
/// so tests can stub the headless WebView without platform channels.
final webSessionProbeProvider =
    Provider<Future<WebSessionProbeResult> Function()>(
      (ref) => ref.watch(webSessionRefresherProvider).refresh,
    );

final class WebSessionRefresher {
  WebSessionRefresher(this._ref);

  final Ref _ref;
  HeadlessInAppWebView? _headless;
  bool _running = false;
  Timer? _timeout;
  Completer<WebSessionProbeResult>? _completion;
  int _inconclusiveStops = 0;

  /// Marker-less load stops tolerated while waiting for a WAF challenge to
  /// redirect. Bounded so a static block page still reports within the probe
  /// deadline instead of waiting for the full timeout every time.
  static const int _maxInconclusiveStops = 3;

  /// Loads `www.deviantart.com` headlessly and reports what the real browser
  /// saw: a CSRF token plus whether the page rendered a signed-in username.
  /// Concurrent callers share the same operation, and the returned future does
  /// not complete until the page reports a result or the safety timeout fires.
  Future<WebSessionProbeResult> refresh() {
    final active = _completion;
    if (_running && active != null) {
      return active.future;
    }
    _running = true;
    _inconclusiveStops = 0;
    final completion = Completer<WebSessionProbeResult>();
    _completion = completion;
    // Include proxy setup and browser startup in the deadline. Neither may
    // keep the shared probe occupied indefinitely.
    _timeout = Timer(const Duration(seconds: 20), () {
      unawaited(_dispose(null, completion));
    });
    unawaited(_startProbe(completion));
    return completion.future;
  }

  Future<void> _startProbe(Completer<WebSessionProbeResult> completion) async {
    try {
      final runtime = _ref.read(runtimeProvider);
      final environment = await runtime.webViewProxyManager?.prepare();
      if (!identical(_completion, completion) || !_ref.mounted) return;
      final headless = HeadlessInAppWebView(
        webViewEnvironment: environment,
        initialSize: const Size(480, 800),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          userAgent: webLoginUserAgent(isAndroid: Platform.isAndroid),
        ),
        initialUrlRequest: URLRequest(
          url: WebUri('https://www.deviantart.com/'),
        ),
        onLoadStop: (controller, url) async {
          if (!identical(_completion, completion)) return;
          if (url == null || url.host != 'www.deviantart.com') return;
          final observation = await _observe(controller, completion);
          if (!identical(_completion, completion) || !_ref.mounted) return;
          final result = webSessionProbeResultFromPage(
            pageUsername: observation.pageUsername?.trim(),
            csrf: observation.csrf,
          );
          // Logging context only: the local identity must never impersonate the
          // page observation (see REG-010).
          final localUsername = _ref.read(webSessionControllerProvider).username;
          debugPrint(
            '[web-session] probe outcome=${result.outcome.name} '
            'csrf=${observation.csrf.length} '
            'pageUsername=${observation.pageUsername == null
                ? 'missing'
                : observation.pageUsername!.isEmpty
                ? '-'
                : observation.pageUsername} '
            'localUsername=${localUsername.isEmpty ? '-' : localUsername}',
          );
          if (result.outcome != WebSessionProbeOutcome.unavailable) {
            await _dispose(result, completion);
            return;
          }
          _inconclusiveStops += 1;
          if (!observation.hasSessionMarkers &&
              _inconclusiveStops < _maxInconclusiveStops) {
            // A WAF challenge first renders a marker-less interstitial and
            // redirects after solving. Disposing on this stop made every
            // challenged cold start report "unavailable" for a valid session
            // (the first load stop carries no __INITIAL_STATE__ or CSRF at
            // all); wait for the redirect's own load stop, bounded by the
            // probe timeout and the inconclusive-stop cap.
            debugPrint(
              '[web-session] probe page has no session markers (challenge?); '
              'waiting for redirect stop=$_inconclusiveStops/$_maxInconclusiveStops',
            );
            return;
          }
          await _dispose(result, completion);
        },
        onReceivedError: (controller, request, error) async {
          // Images, fonts and other optional resources do not determine
          // whether the main page can report the signed-in identity.
          if (request.isForMainFrame != true) return;
          await _dispose(const WebSessionProbeResult.unavailable(), completion);
        },
      );
      _headless = headless;
      await headless.run();
    } on Object catch (error, stack) {
      debugPrint('[web-session] headless refresh failed: $error');
      debugPrintStack(stackTrace: stack);
      await _dispose(null, completion);
    }
  }

  /// Reads the page's session markers without mapping them onto a verdict.
  /// Also rotates the live CSRF when the page exposed one (the probe is a pure
  /// observer: it never writes an identity or a session verdict, REG-010).
  Future<WebSessionProbeObservation> _observe(
    InAppWebViewController controller,
    Completer<WebSessionProbeResult> completion,
  ) async {
    try {
      final raw = await controller.evaluateJavascript(source: _probeScript);
      if (!identical(_completion, completion) || !_ref.mounted) {
        return const WebSessionProbeObservation(pageUsername: null, csrf: '');
      }
      if (raw is! String || raw.isEmpty) {
        return const WebSessionProbeObservation(pageUsername: null, csrf: '');
      }
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final csrf = (data['csrf'] as String?) ?? '';
      // `username` is null when the page structure did not expose it (WAF,
      // challenge, incomplete load) and 'anonymous' only when the page itself
      // explicitly reported a signed-out session. The two must never merge.
      final pageUsername = (data['username'] as String?)?.trim();
      // A public browser session is sufficient for numeric-id and website
      // metadata fallbacks. This probe is a pure observer: it rotates the CSRF
      // for website adapters and returns its observation. It never writes an
      // identity or a session verdict (REG-010) — the verification layer
      // consumes the returned evidence instead.
      if (csrf.isNotEmpty &&
          identical(_completion, completion) &&
          _ref.mounted) {
        // Live CSRF updates before persistence; storage cannot delay identity.
        unawaited(
          _ref
              .read(webSessionControllerProvider.notifier)
              .updateCsrf(csrf)
              .catchError((Object error) {
                debugPrint(
                  '[web-session] probe metadata save failed: ${error.runtimeType}',
                );
              }),
        );
      }
      return WebSessionProbeObservation(pageUsername: pageUsername, csrf: csrf);
    } on Object catch (error) {
      debugPrint('[web-session] headless report failed: $error');
      return const WebSessionProbeObservation(pageUsername: null, csrf: '');
    }
  }

  Future<void> _dispose([
    WebSessionProbeResult? result,
    Completer<WebSessionProbeResult>? expected,
  ]) async {
    if (expected != null && !identical(_completion, expected)) return;
    _timeout?.cancel();
    _timeout = null;
    final headless = _headless;
    _headless = null;
    final completion = _completion;
    _completion = null;
    _running = false;
    if (completion != null && !completion.isCompleted) {
      completion.complete(result ?? const WebSessionProbeResult.unavailable());
    }
    if (headless != null) {
      try {
        await headless.dispose();
      } on Object {
        // Best effort.
      }
    }
  }

  /// Reads the page session without optional chaining so older Android
  /// WebViews never fail on syntax.
  static const String _probeScript = '''
(function() {
  var state = window.__INITIAL_STATE__ || {};
  var session = state['@publicSession'] || {};
  var user = session.user || {};
  return JSON.stringify({
    csrf: window.__CSRF_TOKEN__ || '',
    username: typeof user.username === 'string' ? user.username : null
  });
})()
''';
}
