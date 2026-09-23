import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../runtime/runtime_provider.dart';
import 'session_state.dart';
import 'web_session_controller.dart';
import 'web_session_platform.dart';

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

  const WebSessionProbeResult.unavailable()
    : outcome = WebSessionProbeOutcome.unavailable,
      csrf = '',
      username = '';

  final WebSessionProbeOutcome outcome;
  final String csrf;
  final String username;

  bool get succeeded => outcome == WebSessionProbeOutcome.confirmed;
}

/// Loads a public page in a hidden browser so website-only metadata adapters
/// can obtain the anonymous CSRF/cookies expected by DeviantArt. It never asks
/// the user to log in and is not part of App authentication.
final webSessionRefresherProvider = Provider<WebSessionRefresher>(
  (ref) => WebSessionRefresher(ref),
);

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

  /// Loads `www.deviantart.com` headlessly and reports what the real browser
  /// saw: a CSRF token plus whether the page rendered a signed-in username.
  /// Concurrent callers share the same operation, and the returned future does
  /// not complete until the page reports a result or the safety timeout fires.
  Future<WebSessionProbeResult> refresh() async {
    final active = _completion;
    if (_running && active != null) {
      return active.future;
    }
    _running = true;
    final completion = Completer<WebSessionProbeResult>();
    _completion = completion;
    try {
      final runtime = _ref.read(runtimeProvider);
      final environment = await runtime.webViewProxyManager?.prepare();
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
          if (url == null || url.host != 'www.deviantart.com') return;
          final result = await _report(controller);
          await _dispose(result);
        },
        onReceivedError: (controller, request, error) async {
          await _dispose(const WebSessionProbeResult.unavailable());
        },
      );
      _headless = headless;
      await headless.run();
      // Safety net in case navigation never completes.
      if (_running) {
        _timeout = Timer(const Duration(seconds: 20), () {
          if (_running) unawaited(_dispose());
        });
      }
    } on Object catch (error, stack) {
      debugPrint('[web-session] headless refresh failed: $error');
      debugPrintStack(stackTrace: stack);
      await _dispose();
    }
    return completion.future;
  }

  Future<WebSessionProbeResult> _report(
    InAppWebViewController controller,
  ) async {
    try {
      final raw = await controller.evaluateJavascript(source: _probeScript);
      if (raw is! String || raw.isEmpty) {
        return const WebSessionProbeResult.unavailable();
      }
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final csrf = (data['csrf'] as String?) ?? '';
      final pageUsername = ((data['username'] as String?) ?? '').trim();
      // A public browser session is sufficient for numeric-id and website
      // metadata fallbacks. It is intentionally not treated as another user
      // login; the official OAuth session remains the only app identity.
      if (csrf.isEmpty) {
        return const WebSessionProbeResult.unavailable();
      }
      final localUsername =
          (await _ref.read(webSessionProvider).readData())?.username ?? '';
      final reportedUsername = pageUsername.isEmpty
          ? localUsername
          : pageUsername;
      debugPrint(
        '[web-session] cold-start csrf=${csrf.length} '
        'pageUsername=${pageUsername.isEmpty ? '-' : pageUsername} '
        'localUsername=${localUsername.isEmpty ? '-' : localUsername}',
      );
      await _ref
          .read(webSessionControllerProvider.notifier)
          .reportRefresh(csrf: csrf, username: reportedUsername);
      final signedInUsername = pageUsername == 'anonymous' ? '' : pageUsername;
      return signedInUsername.isEmpty
          ? WebSessionProbeResult.anonymous(csrf: csrf)
          : WebSessionProbeResult.confirmed(
              csrf: csrf,
              username: signedInUsername,
            );
    } on Object catch (error) {
      debugPrint('[web-session] headless report failed: $error');
      return const WebSessionProbeResult.unavailable();
    }
  }

  Future<void> _dispose([WebSessionProbeResult? result]) async {
    _timeout?.cancel();
    _timeout = null;
    final headless = _headless;
    _headless = null;
    if (headless != null) {
      try {
        await headless.dispose();
      } on Object {
        // Best effort.
      }
    }
    final completion = _completion;
    _completion = null;
    _running = false;
    if (completion != null && !completion.isCompleted) {
      completion.complete(result ?? const WebSessionProbeResult.unavailable());
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
    username: user.username || ''
  });
})()
''';
}
