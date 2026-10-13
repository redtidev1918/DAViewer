import 'dart:async';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diagnostics/app_logger.dart';
import '../runtime/runtime_provider.dart';
import 'browser_session_observer.dart';
import 'web_session_controller.dart';
import 'web_session_platform.dart';

enum WebSessionProbeOutcome { confirmed, anonymous, unavailable }

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

WebSessionProbeResult webSessionProbeResultFromPage({
  required String? pageUsername,
  required String csrf,
}) {
  final username = pageUsername?.trim();
  if (username == null || username.isEmpty) {
    return WebSessionProbeResult.unavailable(csrf: csrf);
  }
  if (username == 'anonymous') {
    return WebSessionProbeResult.anonymous(csrf: csrf);
  }
  return WebSessionProbeResult.confirmed(csrf: csrf, username: username);
}

final webSessionRefresherProvider = Provider<WebSessionRefresher>((ref) {
  final host = WebSessionRefresher(ref);
  ref.onDispose(
    () => unawaited(host._dispose(null, null, 'provider_disposed')),
  );
  return host;
});

final webSessionProbeProvider =
    Provider<Future<WebSessionProbeResult> Function()>(
      (ref) => ref.watch(webSessionRefresherProvider).refresh,
    );

/// Bounded browser host; the status controller owns identity decisions. The
/// visible host uses the same observer and native cookie store.
final class WebSessionRefresher {
  WebSessionRefresher(this._ref);
  final Ref _ref;
  HeadlessInAppWebView? _headless;
  BrowserSessionObserver? _observer;
  Timer? _timeout;
  Completer<WebSessionProbeResult>? _completion;
  int _sequence = 0;
  String recoveryId = 'metadata';
  String _activeRecoveryId = 'metadata';
  int _activeIdentityEpoch = 0;

  Future<WebSessionProbeResult> refresh() {
    final active = _completion;
    if (active != null) return active.future;
    final completion = Completer<WebSessionProbeResult>();
    _completion = completion;
    _sequence++;
    _activeRecoveryId = recoveryId;
    _activeIdentityEpoch = _ref
        .read(webSessionControllerProvider.notifier)
        .identityEpoch;
    _log('created');
    // Original total budget includes proxy/startup; events never extend it.
    _timeout = Timer(const Duration(seconds: 20), () {
      unawaited(_dispose(null, completion, 'deadline'));
    });
    unawaited(_startProbe(completion));
    return completion.future;
  }

  bool _current(Completer<WebSessionProbeResult> completion) =>
      identical(_completion, completion) &&
      _ref.mounted &&
      _activeIdentityEpoch ==
          _ref.read(webSessionControllerProvider.notifier).identityEpoch;

  void _log(String event) => AppLogger.instance.info(
    'web-session',
    'browser probe=$_sequence recoveryId=$_activeRecoveryId host=headless $event',
  );

  Future<void> _startProbe(Completer<WebSessionProbeResult> completion) async {
    final identityEpoch = _activeIdentityEpoch;
    try {
      await _ref.read(webSessionControllerProvider.notifier).cookieMutations;
      if (!_current(completion)) return;
      final runtime = _ref.read(runtimeProvider);
      final environment = await runtime.webViewProxyManager?.prepare();
      if (!_current(completion)) return;
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
        onWebViewCreated: (controller) {
          if (!_current(completion)) return;
          _observer = BrowserSessionObserver(
            read: () => readBrowserSessionEvidence(
              getUrl: () async => (await controller.getUrl())?.uriValue,
              evaluate: () => controller.evaluateJavascript(
                source: browserSessionEvidenceScript,
              ),
              getHtml: controller.getHtml,
            ),
            onEvidence: (evidence) {
              if (!_current(completion)) return;
              _log(
                'classification=${evidence.classification} identitySource=${evidence.identitySource} csrfPresent=${evidence.csrf.isNotEmpty}',
              );
              if (evidence.csrf.isNotEmpty) {
                unawaited(
                  _ref
                      .read(webSessionControllerProvider.notifier)
                      .updateCsrf(evidence.csrf, expectedEpoch: identityEpoch)
                      .catchError((Object error) {
                        if (!_current(completion)) return;
                        _log(
                          'metadata_save_failed errorType=${error.runtimeType}',
                        );
                      }),
                );
              }
              if (evidence.blocked) {
                unawaited(_dispose(null, completion, 'blocked'));
              } else if (!evidence.challenge && evidence.hasIdentity) {
                unawaited(
                  _dispose(
                    webSessionProbeResultFromPage(
                      pageUsername: evidence.username,
                      csrf: evidence.csrf,
                    ),
                    completion,
                    evidence.classification,
                  ),
                );
              }
            },
            onDeadline: () =>
                unawaited(_dispose(null, completion, 'page_unstable')),
          )..start();
        },
        onLoadStart: (controller, url) {
          if (!_current(completion)) return;
          _observer?.navigationStarted(loading: true);
          _log('event=load_start');
        },
        onLoadStop: (controller, url) {
          if (!_current(completion)) return;
          _log('event=load_stop');
          _observer?.navigationCommitted();
          unawaited(_observer?.sample());
        },
        onUpdateVisitedHistory: (controller, url, isReload) {
          if (!_current(completion)) return;
          _observer?.navigationStarted();
          _log('event=history');
          unawaited(_observer?.sample());
        },
        onReceivedError: (controller, request, error) {
          if (request.isForMainFrame != true) return;
          unawaited(_dispose(null, completion, 'main_frame_error'));
        },
      );
      _headless = headless;
      await headless.run();
    } on Object catch (error) {
      if (_current(completion)) {
        _log('startup_failed errorType=${error.runtimeType}');
      }
      await _dispose(null, completion, 'startup_error');
    }
  }

  /// Stop hidden observation before interactive navigation takes over. Cookie
  /// store continuity is maintained without copying credentials between hosts.
  Future<void> yieldToVisible() => _dispose(null, null, 'visible_handoff');

  /// A new account must never join a browser belonging to the old account.
  Future<void> accountChanged() => _dispose(null, null, 'account_changed');

  Future<void> _dispose([
    WebSessionProbeResult? result,
    Completer<WebSessionProbeResult>? expected,
    String? completionReason,
  ]) async {
    if (expected != null && !identical(_completion, expected)) return;
    if (_completion != null) {
      _log('completed reason=${completionReason ?? 'closed'}');
    }
    _timeout?.cancel();
    _timeout = null;
    _observer?.dispose();
    _observer = null;
    final headless = _headless;
    _headless = null;
    final completion = _completion;
    _completion = null;
    if (completion != null && !completion.isCompleted) {
      completion.complete(result ?? const WebSessionProbeResult.unavailable());
    }
    if (headless != null) {
      try {
        await headless.dispose();
      } on Object {
        // Callers are released even if a platform teardown fails.
      }
    }
  }
}
