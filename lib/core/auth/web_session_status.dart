import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diagnostics/app_logger.dart';
import '../data/web_session.dart';
import '../runtime/runtime_provider.dart';
import 'session_state.dart';
import 'web_session_controller.dart';
import 'web_session_diagnostics.dart';
import 'web_session_refresher.dart';
import 'web_session_verdict.dart';
import 'web_session_verifier.dart';

export 'session_state.dart' show webSessionProvider;

/// Startup readiness only: "the persisted Web Session bootstrap/restore phase
/// has completed enough for Home to render". This must never be read as
/// "web session healthy" — the health verdict lives exclusively in
/// [webSessionStatusProvider] and is produced by the verification chain.
final webSessionReadyProvider = StateProvider<bool>((ref) => false);

/// Single source of truth for the DeviantArt web session.
enum WebSessionStatusState {
  unknown,
  healthy,
  anonymous,

  /// A confirmed WebView session exists but a bare HTTP probe could not
  /// confirm it (WAF/challenge/transient answer). Not a logged-out signal.
  unverified,
  stale,
  locked,
  unavailable,
}

final class WebSessionStatus {
  const WebSessionStatus({
    this.state = WebSessionStatusState.unknown,
    this.serverUsername = '',
    this.lastCheckedAt,
    this.cooldownUntil,
  });

  final WebSessionStatusState state;
  final String serverUsername;
  final DateTime? lastCheckedAt;
  final DateTime? cooldownUntil;

  bool get isHealthy => state == WebSessionStatusState.healthy;

  bool get needsLogin =>
      state == WebSessionStatusState.anonymous ||
      state == WebSessionStatusState.stale ||
      state == WebSessionStatusState.locked;

  bool get isLocked => state == WebSessionStatusState.locked;

  bool get inCooldown {
    final until = cooldownUntil;
    return until != null && DateTime.now().isBefore(until);
  }
}

final webSessionStatusProvider =
    StateNotifierProvider<WebSessionStatusController, WebSessionStatus>(
      (ref) => WebSessionStatusController(ref),
    );

/// Confirms the signed-in identity against the DeviantArt home page with the
/// current Cookie header, instead of trusting the local snapshot alone.
final webSessionVerifierProvider = Provider<WebSessionVerifier>((ref) {
  final dio = ref.watch(runtimeProvider).dio;
  if (dio == null) {
    throw StateError('runtime dio is not available');
  }
  return WebSessionVerifier(dio);
});

/// The authoritative real-browser probe used to arbitrate a bare HTTP
/// verifier answer that contradicts a confirmed WebView session. Injectable
/// so tests can stub the headless WebView without platform channels.
final webSessionProbeProvider =
    Provider<Future<WebSessionProbeResult> Function()>(
      (ref) => ref.watch(webSessionRefresherProvider).refresh,
    );
WebSessionStatusState emptyLiveCookieStatus({
  required int persistedCookieCount,
}) => persistedCookieCount == 0
    ? WebSessionStatusState.anonymous
    : WebSessionStatusState.unavailable;

final class WebSessionStatusController extends StateNotifier<WebSessionStatus> {
  WebSessionStatusController(this._ref) : super(const WebSessionStatus());

  final Ref _ref;

  static const Duration _cacheDuration = Duration(minutes: 5);
  static const List<Duration> _backoff = <Duration>[
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 10),
  ];

  DateTime? _lastSuccess;
  int _failures = 0;
  int _generation = 0;
  Future<void>? _activeCheck;

  /// Restores a persisted server-confirmed session snapshot, never during a
  /// backoff period. The next feed request is the acceptance gate: expired
  /// cookies surface as a feed error instead of forcing a WAF probe.
  Future<void> check({bool force = false}) async {
    final active = _activeCheck;
    if (active != null) return active;
    final last = _lastSuccess;
    if (!force &&
        last != null &&
        state.isHealthy &&
        DateTime.now().difference(last) < _cacheDuration) {
      return;
    }
    if (!force && state.inCooldown) return;

    final generation = _generation;
    late final Future<void> tracked;
    tracked = _performCheck(force: force, generation: generation).whenComplete(
      () {
        if (identical(_activeCheck, tracked)) _activeCheck = null;
      },
    );
    _activeCheck = tracked;
    return tracked;
  }

  bool _isCurrent(int generation) => generation == _generation;

  /// The only entry point that turns evidence into a verdict. Everything the
  /// controller (or a future coordinator) learns about the session must pass
  /// through here, so generation protection and transition logging can never
  /// be bypassed. Returns the resolved decision; an escalated decision asks
  /// the caller to collect real-browser evidence and apply it in turn.
  WebSessionVerdictDecision applyVerification(WebSessionEvidence evidence) {
    if (evidence.generation != _generation) {
      AppLogger.instance.info(
        'auth',
        'verification result discarded: source=${evidence.source.name} '
            'outcome=${evidence.outcome.name} '
            'generation=${evidence.generation} '
            'currentGeneration=$_generation reason=stale',
      );
      return const WebSessionVerdictDecision.keep();
    }
    final claimed = _ref.read(webSessionControllerProvider);
    final decision = resolveWebSessionVerdict(
      current: state.state,
      evidence: evidence,
      claimedUsername: claimed.username,
      claimedSignedIn: claimed.isLoggedIn == true,
    );
    final escalated = decision.escalateToRealBrowser;
    final nextState = decision.nextState;
    if (nextState == null && !escalated) {
      return const WebSessionVerdictDecision.keep();
    }
    if (nextState != null) {
      switch (nextState) {
        case WebSessionStatusState.healthy:
          _lastSuccess = DateTime.now();
          _failures = 0;
          final next = WebSessionStatus(
            state: nextState,
            serverUsername: decision.serverUsername,
            lastCheckedAt: DateTime.now(),
          );
          _logTransition(next, evidence.source.name);
          state = next;
        case WebSessionStatusState.unavailable:
        case WebSessionStatusState.unverified:
          // Transient answers back off; they are never logged-out signals.
          _setTransient(nextState, evidence.source.name);
        case WebSessionStatusState.anonymous:
        case WebSessionStatusState.locked:
        case WebSessionStatusState.unknown:
        case WebSessionStatusState.stale:
          _failures = 0;
          final next = WebSessionStatus(state: nextState);
          _logTransition(next, evidence.source.name);
          state = next;
      }
    }
    return decision;
  }

  Future<void> _performCheck({
    required bool force,
    required int generation,
  }) async {
    try {
      // Restore the persisted snapshot if the live WebView store lost it
      // (for example after an app update), before asking the server.
      await _ref
          .read(webSessionControllerProvider.notifier)
          .restorePersistedCookies();
      if (!_isCurrent(generation)) return;
      final webSession = _ref.read(webSessionProvider);
      final cookies = await webSession.cookies();
      if (cookies.isEmpty) {
        // A claimed signed-in session with a persisted snapshot means the live
        // read/restore failed or is not ready. That is unavailable, not proof
        // that the user is signed out. A genuinely logged-out account has no
        // persisted cookie snapshot at all.
        final persisted = await _ref
            .read(webSessionControllerProvider.notifier)
            .persistedCookies();
        if (!_isCurrent(generation)) return;
        _setEmptyLiveCookieState(persistedCount: persisted.length);
        return;
      }
      final controllerState = _ref.read(webSessionControllerProvider);
      final claimedUsername = controllerState.username.trim();
      if (controllerState.isLoggedIn != true || claimedUsername.isEmpty) {
        if (!_isCurrent(generation)) return;
        applyVerification(
          WebSessionEvidence(
            source: WebSessionEvidenceSource.localState,
            outcome: WebSessionProbeOutcome.anonymous,
            generation: generation,
          ),
        );
        return;
      }
      final cookieHeader = WebSession.cookieHeaderFrom(cookies);
      if (cookieHeader.isEmpty) {
        final empty = await webSession.snapshot(source: 'check-empty-cookie');
        AppLogger.instance.warning('auth', empty.logLine());
        if (!_isCurrent(generation)) return;
        applyVerification(
          WebSessionEvidence(
            source: WebSessionEvidenceSource.localState,
            outcome: WebSessionProbeOutcome.anonymous,
            generation: generation,
          ),
        );
        return;
      }
      final before = await webSession.snapshot(source: 'check-before-verify');
      AppLogger.instance.info('auth', before.logLine());
      // The persisted snapshot only exists because a previous session was
      // confirmed during an actual WebView login. The home page answer decides
      // whether that session is still who the server thinks it is, but a bare
      // HTTP probe is not a real browser: an anonymous/unavailable answer must
      // never downgrade a WebView-confirmed session.
      final verification = await _ref
          .read(webSessionVerifierProvider)
          .verify(cookieHeader: cookieHeader);
      // A newer login/lockout superseded this check; never let a stale answer
      // overwrite the newer session state.
      if (!_isCurrent(generation)) return;
      var decision = applyVerification(
        WebSessionEvidence(
          source: WebSessionEvidenceSource.bareProbe,
          outcome: switch (verification.state) {
            WebSessionVerificationState.signedIn =>
              WebSessionProbeOutcome.confirmed,
            WebSessionVerificationState.anonymous =>
              WebSessionProbeOutcome.anonymous,
            WebSessionVerificationState.unavailable =>
              WebSessionProbeOutcome.unavailable,
          },
          username: verification.username,
          generation: generation,
        ),
      );
      if (decision.escalateToRealBrowser) {
        final after = await webSession.snapshot(
          source: 'check-after-anonymous',
        );
        AppLogger.instance.warning(
          'auth',
          'web session probe unconfirmed (anonymous): '
              'claimed=$claimedUsername '
              'cookieCount=${cookieHeaderCount(cookieHeader)} '
              'cookieFingerprint=${cookieHeaderFingerprint(cookieHeader)} '
              '${after.logLine()}',
        );
        // A bare anonymous answer never decides logged-out by itself: collect
        // real-browser evidence and apply it as a separate observation.
        final probe = await _ref.read(webSessionProbeProvider)();
        if (!_isCurrent(generation)) return;
        decision = applyVerification(
          WebSessionEvidence(
            source: WebSessionEvidenceSource.realBrowserProbe,
            outcome: probe.outcome,
            username: probe.username,
            generation: generation,
          ),
        );
      }
      if (decision.nextState == WebSessionStatusState.healthy) {
        // Persist only a server-confirmed live cookie set. An unconfirmed
        // health check must never overwrite the snapshot: a degraded live
        // store during a WAF challenge can still carry a matching
        // `userinfo` cookie while the auth cookies are mid-rotation, and
        // re-persisting that set would make the next cold start restore dead
        // credentials (forced re-login).
        await _ref
            .read(webSessionControllerProvider.notifier)
            .ensurePersistentSnapshot(capturedCookies: cookies);
      }
    } on Object {
      if (_isCurrent(generation)) _setUnavailable(source: 'check-error');
    }
  }

  /// Called by the login WebView when DeviantArt reports its WAF lockout.
  /// All automatic retries must stop while this state is active.
  void markLocked() {
    _generation++;
    _failures = 0;
    const next = WebSessionStatus(state: WebSessionStatusState.locked);
    _logTransition(next, 'web-login-challenge');
    state = next;
  }

  void markHealthy({required String serverUsername}) {
    _generation++;
    _lastSuccess = DateTime.now();
    _failures = 0;
    final next = WebSessionStatus(
      state: WebSessionStatusState.healthy,
      serverUsername: serverUsername,
      lastCheckedAt: DateTime.now(),
    );
    _logTransition(next, 'web-login');
    state = next;
  }

  void _setEmptyLiveCookieState({required int persistedCount}) {
    if (persistedCount == 0) {
      _setAnonymous(source: 'cookie-store');
    } else {
      _setUnavailable(source: 'cookie-store');
    }
  }

  /// Every mutation logs old → new with its source, so a production log can
  /// answer "which async path turned healthy into anonymous" (REG-010).
  void _logTransition(WebSessionStatus next, String source) {
    final claimed = _ref.read(webSessionControllerProvider).username;
    final cooldown = next.cooldownUntil;
    AppLogger.instance.info(
      'auth',
      'web session state: ${state.state.name} -> ${next.state.name} '
          'source=$source generation=$_generation '
          'claimed=${claimed.isEmpty ? '-' : claimed} '
          'server=${next.serverUsername.isEmpty ? '-' : next.serverUsername}'
          '${cooldown == null ? '' : ' cooldown=$cooldown'}',
    );
  }

  void _setAnonymous({required String source}) {
    _failures = 0;
    const next = WebSessionStatus(state: WebSessionStatusState.anonymous);
    _logTransition(next, source);
    state = next;
  }

  void _setUnavailable({required String source}) =>
      _setTransient(WebSessionStatusState.unavailable, source);

  void _setTransient(WebSessionStatusState state, String source) {
    _failures += 1;
    final index = (_failures - 1).clamp(0, _backoff.length - 1);
    final next = WebSessionStatus(
      state: state,
      cooldownUntil: DateTime.now().add(_backoff[index]),
    );
    _logTransition(next, source);
    this.state = next;
  }
}
