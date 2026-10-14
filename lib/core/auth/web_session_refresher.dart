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
import 'session_state.dart' show webSessionProvider;
import 'web_session_diagnostics.dart';

enum WebSessionProbeOutcome { confirmed, anonymous, unavailable }

final class WebSessionProbeResult {
  const WebSessionProbeResult.confirmed({
    required this.csrf,
    required this.username,
    this.credentialFingerprint,
  }) : outcome = WebSessionProbeOutcome.confirmed,
       blocked = false;
  const WebSessionProbeResult.anonymous({
    this.csrf = '',
    this.credentialFingerprint,
  }) : outcome = WebSessionProbeOutcome.anonymous,
       username = '',
       blocked = false;
  const WebSessionProbeResult.unavailable({
    this.csrf = '',
    this.credentialFingerprint,
    this.blocked = false,
  }) : outcome = WebSessionProbeOutcome.unavailable,
       username = '';
  final WebSessionProbeOutcome outcome;
  final String csrf;
  final String username;
  final String? credentialFingerprint;

  /// The page was DeviantArt's explicit WAF lockout. This is not a credential
  /// question: it must not be retained as a healthy lease or shown as a generic
  /// "temporarily unavailable", because the only recovery is user action
  /// (wait, refresh once, or switch network/proxy node).
  final bool blocked;

  bool get succeeded => outcome == WebSessionProbeOutcome.confirmed;
}

WebSessionProbeResult webSessionProbeResultFromPage({
  required String? pageUsername,
  required String csrf,
  String? credentialFingerprint,
}) {
  final username = pageUsername?.trim();
  if (username == null || username.isEmpty) {
    return WebSessionProbeResult.unavailable(csrf: csrf);
  }
  if (username == 'anonymous') {
    return WebSessionProbeResult.anonymous(
      csrf: csrf,
      credentialFingerprint: credentialFingerprint,
    );
  }
  return WebSessionProbeResult.confirmed(
    csrf: csrf,
    username: username,
    credentialFingerprint: credentialFingerprint,
  );
}

/// What a probe transaction should do with one identity-bearing page sample.
enum WebSessionProbeSampleDecision {
  /// The sample decides the transaction.
  complete,

  /// A first anonymous sample: arm one corroborating reload.
  corroborateAnonymous,

  /// An anonymous sample that did not come from a new navigation (the reload
  /// has not landed / the same stale document was re-read). The transaction
  /// keeps waiting; its deadline resolves `unavailable`.
  wait,
}

/// A first anonymous sample is weak evidence: a redirect intermediate state,
/// an anonymous shell before session cookies re-attach, or a challenge
/// variant can all render `isLoggedIn: false` while the Cookie session is
/// alive. The first anonymous sample arms one corroborating reload instead of
/// completing the probe. Completion then requires the anonymous verdict to be
/// delivered under a strictly newer COMMITTED-document generation than the
/// arming sample — `corroborationPending` proves nothing about whether a new
/// page loaded, and neither does an invalidation-sequence bump: an SPA
/// history event or a rotated CSRF re-reads the same document and is not
/// independent negative evidence (review R1, 2026-10-14). A confirmed sample
/// always completes immediately, so a live session is never delayed
/// (invariant 2 stays intact).
WebSessionProbeSampleDecision webSessionProbeSampleDecision(
  WebSessionProbeResult result, {
  required bool corroborationPending,
  int evidenceDocument = 0,
  int armedDocument = 0,
}) {
  if (result.outcome == WebSessionProbeOutcome.anonymous) {
    if (!corroborationPending) {
      return WebSessionProbeSampleDecision.corroborateAnonymous;
    }
    if (evidenceDocument <= armedDocument) {
      return WebSessionProbeSampleDecision.wait;
    }
  }
  return WebSessionProbeSampleDecision.complete;
}

final webSessionRefresherProvider = Provider<WebSessionRefresher>((ref) {
  final host = WebSessionRefresher(ref);
  ref.onDispose(
    () => unawaited(host._dispose(null, null, 'provider_disposed')),
  );
  return host;
});

/// Bind page identity to the exact native credential set observed during its
/// sampling transaction. A later read must not retroactively authenticate a
/// different set. Changing/unreadable credentials remain inconclusive.
Future<BrowserSessionEvidence> readBrowserEvidenceWithCredentials({
  required Future<String> Function() cookieHeader,
  required Future<BrowserSessionEvidence> Function() readPage,
}) async {
  final before = await cookieHeader();
  final page = await readPage();
  final after = await cookieHeader();
  // An explicit server-side block or human-verification challenge makes no
  // identity claim about the credential set, so a credential rotation during
  // the read must not mask it. Folding these into an empty sample classified a
  // WAF lockout as `page_uninitialized` and hid the actionable state behind a
  // stale `retained=healthy_lease`, which is how the 2026-10-14 Android run
  // kept retrying a blocked network with no user-visible explanation.
  if (page.blocked || page.challenge) {
    return BrowserSessionEvidence(
      blocked: page.blocked,
      challenge: page.challenge,
      initialized: page.initialized,
      loggedIn: page.loggedIn,
      username: page.username,
      csrf: page.csrf,
      parseFailed: page.parseFailed,
      identitySource: page.identitySource,
      credentialFingerprint: cookieHeaderFingerprint(after),
    );
  }
  final explicitlyAnonymous =
      page.initialized &&
      (page.loggedIn == false || page.username == 'anonymous');
  if (before != after || (before.isEmpty && !explicitlyAnonymous)) {
    return const BrowserSessionEvidence();
  }
  return BrowserSessionEvidence(
    username: page.username,
    loggedIn: page.loggedIn,
    csrf: page.csrf,
    initialized: page.initialized,
    blocked: page.blocked,
    challenge: page.challenge,
    parseFailed: page.parseFailed,
    identitySource: page.identitySource,
    credentialFingerprint: cookieHeaderFingerprint(before),
  );
}

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
  InAppWebViewController? _probeController;
  BrowserSessionObserver? _observer;
  Timer? _timeout;
  Completer<WebSessionProbeResult>? _completion;
  int _sequence = 0;
  String recoveryId = 'metadata';
  String _activeRecoveryId = 'metadata';
  int _activeIdentityEpoch = 0;

  /// A single anonymous page sample is weak evidence: a redirect intermediate
  /// state, an anonymous shell before session cookies re-attach, or a challenge
  /// variant can all render `isLoggedIn: false` while the Cookie session is
  /// alive. The first anonymous sample therefore only arms one corroborating
  /// reload; the verdict completes on an anonymous sample delivered under a
  /// NEW committed main-frame document (see `_corroborateAnonymous` and
  /// `_anonymousArmedDocument`).
  bool _anonymousCorroborationPending = false;

  /// The committed-document generation the arming anonymous sample was read
  /// under. A corroborating anonymous sample must arrive under a strictly
  /// greater generation — the reload actually committed a new main frame.
  /// SPA history events and CSRF rotations advance the invalidation sequence
  /// only and never count (review R1, 2026-10-14).
  int _anonymousArmedDocument = 0;

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
          _probeController = controller;
          _observer = BrowserSessionObserver(
            read: () => readBrowserEvidenceWithCredentials(
              cookieHeader: _ref.read(webSessionProvider).cookieHeader,
              readPage: () => readBrowserSessionEvidence(
                getUrl: () async => (await controller.getUrl())?.uriValue,
                evaluate: () => controller.evaluateJavascript(
                  source: browserSessionEvidenceScript,
                ),
                getHtml: controller.getHtml,
              ),
            ),
            onEvidence: (evidence, epoch) {
              if (!_current(completion)) return;
              _log(
                'classification=${evidence.classification} identitySource=${evidence.identitySource} csrfPresent=${evidence.csrf.isNotEmpty} navSeq=${epoch.invalidation} docSeq=${epoch.committedDocument}',
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
                unawaited(
                  _dispose(
                    const WebSessionProbeResult.unavailable(blocked: true),
                    completion,
                    'blocked',
                  ),
                );
              } else if (!evidence.challenge &&
                  (evidence.hasIdentity ||
                      (evidence.initialized && evidence.loggedIn == false))) {
                final result = webSessionProbeResultFromPage(
                  pageUsername:
                      evidence.initialized && evidence.loggedIn == false
                      ? 'anonymous'
                      : evidence.username,
                  csrf: evidence.csrf,
                  credentialFingerprint: evidence.credentialFingerprint,
                );
                switch (webSessionProbeSampleDecision(
                  result,
                  corroborationPending: _anonymousCorroborationPending,
                  evidenceDocument: epoch.committedDocument,
                  armedDocument: _anonymousArmedDocument,
                )) {
                  case WebSessionProbeSampleDecision.corroborateAnonymous:
                    _anonymousCorroborationPending = true;
                    _anonymousArmedDocument = epoch.committedDocument;
                    _log(
                      'anonymous_sample_unconfirmed event=reload_for_corroboration docSeq=${epoch.committedDocument}',
                    );
                    unawaited(_corroborateAnonymous(completion));
                  case WebSessionProbeSampleDecision.wait:
                    // No committed main-frame document has arrived since the
                    // arming sample: an SPA history event or a rotated CSRF
                    // re-read the same document. Keep waiting; the deadline
                    // resolves unavailable — never a logged-out verdict.
                    _log(
                      'anonymous_sample_same_document event=ignored navSeq=${epoch.invalidation} docSeq=${epoch.committedDocument}',
                    );
                  case WebSessionProbeSampleDecision.complete:
                    unawaited(
                      _dispose(result, completion, evidence.classification),
                    );
                }
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

  /// Reloads the page once so a second, independent page load can corroborate
  /// (or refute) a first anonymous sample. The observer keeps running across
  /// the reload: a signed-in sample completes `confirmed` immediately, a second
  /// anonymous sample completes `anonymous`, and anything else falls to the
  /// original transaction deadline as `unavailable` — never a logged-out
  /// verdict from missing evidence.
  Future<void> _corroborateAnonymous(
    Completer<WebSessionProbeResult> completion,
  ) async {
    try {
      await _probeController?.reload();
    } on Object {
      if (_current(completion)) {
        _log('anonymous_corroboration_reload_failed');
      }
      // Without a navigation the observer's deduplicated sampler may stay
      // silent; the transaction deadline then resolves `unavailable`, which
      // is the required inconclusive outcome.
    }
  }

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
    _probeController = null;
    _anonymousCorroborationPending = false;
    _anonymousArmedDocument = 0;
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
