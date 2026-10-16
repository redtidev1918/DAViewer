import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../diagnostics/app_logger.dart';
import '../data/web_session.dart';
import '../runtime/runtime_provider.dart';
import 'session_state.dart';
import 'login_observation.dart';
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
final webSessionClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

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

/// Content restrictions trigger verification, not an immediate logout verdict.
final webSessionRestrictionCheckProvider = Provider<Future<void> Function()>(
  (ref) => ref
      .read(webSessionStatusProvider.notifier)
      .recheckAfterContentRestriction,
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
  bool claimedSignedIn = false,
}) => persistedCookieCount == 0 && !claimedSignedIn
    ? WebSessionStatusState.anonymous
    : WebSessionStatusState.unavailable;

final class WebSessionStatusController extends StateNotifier<WebSessionStatus> {
  WebSessionStatusController(this._ref) : super(const WebSessionStatus()) {
    _ref.listen(
      webSessionControllerProvider.select(
        (web) => (web.isLoggedIn, web.username.trim().toLowerCase()),
      ),
      (previous, next) {
        if (previous == next) return;
        _accountEpoch++;
        _generation++;
        _activeCheck = null;
        unawaited(_ref.read(webSessionRefresherProvider).accountChanged());
        _lastSuccess = null;
        _lastRestrictionCheck = null;
        _verifiedCredentialFingerprint = null;
        _observation.bind(next.$2);
        if (mounted) state = const WebSessionStatus();
        final epoch = _accountEpoch;
        if (next.$1 == true && next.$2.isNotEmpty) {
          scheduleMicrotask(() {
            if (mounted && _ref.mounted && epoch == _accountEpoch) {
              unawaited(check());
            }
          });
        }
      },
    );
  }

  final Ref _ref;
  DateTime _now() => _ref.read(webSessionClockProvider)();
  LoginObservationController get _observation =>
      _ref.read(loginObservationProvider(LoginChannel.web).notifier);
  DateTime? _lastManualCheck;

  Future<void> checkLoginStatus() async {
    if (_interactive || state.isLocked) return;
    if (_activeCheck != null) return _activeCheck;
    final now = _now();
    if (_lastManualCheck != null &&
        now.difference(_lastManualCheck!) < const Duration(seconds: 30)) {
      return;
    }
    _lastManualCheck = now;
    await check(force: true, source: 'manual-status');
  }

  /// How long a server-confirmed healthy verdict satisfies non-forced
  /// checks. Single definition shared with the coordinator's scheduling.
  static const Duration cacheDuration = Duration(minutes: 5);
  static const List<Duration> _backoff = <Duration>[
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 10),
  ];

  DateTime? _lastSuccess;
  DateTime? get lastSuccessAt => _lastSuccess;
  DateTime? _lastRestrictionCheck;
  int _failures = 0;
  int _generation = 0;
  Future<void>? _activeCheck;
  int _accountEpoch = 0;
  int _recoverySequence = 0;
  String _recoveryId = 'none';
  int get accountEpoch => _accountEpoch;
  String get recoveryId => _recoveryId;
  int _credentialRevision = 0;
  String? _credentialFingerprint;
  int get credentialRevision => _credentialRevision;

  /// The cookie-header fingerprint the last server-confirmed healthy verdict
  /// was issued under. A credential rotation is *verified* when the live
  /// header still matches this fingerprint: the verdict chain (bare probe or
  /// real-browser probe) accepted exactly those credentials. Feed responses
  /// fetched before such a rotation may be adopted; an unverified rotation
  /// (restore, unexpected store change) keeps the conservative rejection.
  String? _verifiedCredentialFingerprint;
  String? get verifiedCredentialFingerprint => _verifiedCredentialFingerprint;

  int observeCredentials({required String cookieHeader, required String csrf}) {
    final fingerprint = cookieHeaderFingerprint('$cookieHeader\u0000$csrf');
    if (fingerprint != _credentialFingerprint) {
      _credentialFingerprint = fingerprint;
      _credentialRevision++;
    }
    return _credentialRevision;
  }

  bool _interactive = false;

  void beginInteractiveRecovery() {
    _interactive = true;
    _generation++;
    // The generation bump aborts any in-flight check at its next gate
    // without a verdict; close its observation instead of leaving the UI in
    // a permanent "checking" state until the next login event.
    if (_ref.read(loginObservationProvider(LoginChannel.web)).checking) {
      _observation.finish(LoginCheckResult.unknown);
    }
    _activeCheck = null;
    _recoveryId = 'recovery-${++_recoverySequence}';
    state = const WebSessionStatus(state: WebSessionStatusState.unverified);
    AppLogger.instance.info(
      'auth',
      'recovery interactive recoveryId=$_recoveryId accountEpoch=$_accountEpoch',
    );
  }

  void endInteractiveRecovery() => _interactive = false;

  /// Explicit login/lockout supersedes recommendation requests too.
  int get generation => _generation;

  /// Bypass the healthy cache when a content response is suspicious, while
  /// coalescing restricted cards and respecting challenge/network cooldowns.
  Future<void> recheckAfterContentRestriction() =>
      recheckAfterWebSignal('content-restriction');

  Future<void> recheckAfterWebSignal(String source) async {
    if (state.isLocked || state.inCooldown || state.needsLogin) return;
    final active = _activeCheck;
    if (active != null) {
      AppLogger.instance.info(
        'auth',
        'recovery joined recoveryId=$_recoveryId accountEpoch=$_accountEpoch',
      );
      return active;
    }
    final now = _now();
    final previous = _lastRestrictionCheck;
    if (previous != null &&
        now.difference(previous) < const Duration(seconds: 30)) {
      return;
    }
    _lastRestrictionCheck = now;
    AppLogger.instance.info(
      'auth',
      'web verification requested source=$source',
    );
    await check(force: !source.startsWith('media-'), source: source);
  }

  /// Verifies the web session through the HTTP and real-browser evidence chain.
  /// Normal checks reuse recent success and respect transient backoff.
  Future<void> check({
    bool force = false,
    bool browser = false,
    String source = 'session-check',
  }) async {
    if (_interactive) return;
    final active = _activeCheck;
    if (active != null) return active;
    final last = _lastSuccess;
    if (!force &&
        last != null &&
        state.isHealthy &&
        _now().difference(last) < cacheDuration) {
      return;
    }
    if (!force && state.inCooldown) return;

    _observation.begin(_ref.read(webSessionControllerProvider).username);

    final generation = _generation;
    _recoveryId = 'recovery-${++_recoverySequence}';
    final recoveryId = _recoveryId;
    final epoch = _accountEpoch;
    AppLogger.instance.info(
      'auth',
      'recovery created eventId=$_recoveryId recoveryId=$_recoveryId accountEpoch=$_accountEpoch sessionGeneration=$generation credentialRevision=$_credentialRevision triggerSource=$source force=$force',
    );
    late final Future<void> tracked;
    tracked =
        _performCheck(
          force: force,
          generation: generation,
          recoveryId: recoveryId,
          accountEpoch: epoch,
          browser: browser,
        ).whenComplete(() {
          if (identical(_activeCheck, tracked)) _activeCheck = null;
        });
    _activeCheck = tracked;
    return tracked;
  }

  bool _isCurrent(int generation) =>
      mounted && _ref.mounted && generation == _generation;

  Future<bool> _probeCredentialsCurrent(
    WebSessionProbeResult probe,
    int generation,
  ) async {
    final observed = probe.credentialFingerprint;
    if (observed == null) return _isCurrent(generation);
    final live = await _ref.read(webSessionProvider).cookieHeader();
    if (!_isCurrent(generation)) return false;
    if ((live.isNotEmpty ||
            probe.outcome == WebSessionProbeOutcome.anonymous) &&
        cookieHeaderFingerprint(live) == observed) {
      return true;
    }
    _setTransient(
      WebSessionStatusState.unverified,
      'browser-credentials-superseded',
    );
    return false;
  }

  /// The only entry point that turns evidence into a verdict. Everything the
  /// controller (or a future coordinator) learns about the session must pass
  /// through here, so generation protection and transition logging can never
  /// be bypassed. Returns the resolved decision; an escalated decision asks
  /// the caller to collect real-browser evidence and apply it in turn.
  WebSessionVerdictDecision applyVerification(WebSessionEvidence evidence) {
    if (!_isCurrent(evidence.generation)) {
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
          _observation.finish(LoginCheckResult.authenticated);
          _lastSuccess = _now();
          _failures = 0;
          final next = WebSessionStatus(
            state: nextState,
            serverUsername: decision.serverUsername,
            lastCheckedAt: _now(),
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
          _observation.finish(
            nextState == WebSessionStatusState.unknown
                ? LoginCheckResult.unknown
                : nextState == WebSessionStatusState.locked
                ? LoginCheckResult.challenge
                : LoginCheckResult.unauthenticated,
            reason: nextState == WebSessionStatusState.locked
                ? 'challenge'
                : 'unauthenticated',
          );
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
    required String recoveryId,
    required int accountEpoch,
    bool browser = false,
  }) async {
    try {
      if (browser) {
        // A transport-context refresh observes the live browser store, without
        // waiting on optional persistence or re-injecting saved credentials.
        _ref.read(webSessionRefresherProvider).recoveryId = recoveryId;
        final probe = await _ref.read(webSessionProbeProvider)();
        if (!_isCurrent(generation)) return;
        if (probe.blocked) {
          // DeviantArt served its explicit WAF lockout. That is a statement
          // about this network, not a stale-credential question, so it is
          // checked before credential currency and must not be swallowed by a
          // previous healthy lease or reported as a generic "temporarily
          // unavailable": surface the actionable state and stop the retry
          // loop. Recovering needs user action (wait, refresh once, or switch
          // network/proxy node).
          AppLogger.instance.warning(
            'auth',
            'recovery blocked recoveryId=$recoveryId '
                'classification=challenge_lockout',
          );
          markLocked();
          return;
        }
        if (!await _probeCredentialsCurrent(probe, generation)) return;
        final last = _lastSuccess;
        if (probe.outcome == WebSessionProbeOutcome.unavailable &&
            state.isHealthy &&
            last != null &&
            _now().difference(last) < cacheDuration) {
          AppLogger.instance.info(
            'auth',
            'recovery inconclusive recoveryId=$recoveryId retained=healthy_lease',
          );
          return;
        }
        final browserDecision = applyVerification(
          WebSessionEvidence(
            source: WebSessionEvidenceSource.realBrowserProbe,
            outcome: probe.outcome,
            username: probe.username,
            generation: generation,
          ),
        );
        if (browserDecision.nextState == WebSessionStatusState.healthy) {
          _verifiedCredentialFingerprint = probe.credentialFingerprint;
        }
        return;
      }
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
      final verificationCredentialRevision = _credentialRevision;
      final verificationCsrf = _ref.read(webSessionControllerProvider).csrf;
      String? verifiedFingerprint = cookieHeaderFingerprint(cookieHeader);
      // The persisted snapshot only exists because a previous session was
      // confirmed during an actual WebView login. The home page answer decides
      // whether that session is still who the server thinks it is, but a bare
      // HTTP probe is not a real browser: an anonymous/unavailable answer must
      // never downgrade a WebView-confirmed session.
      final verification = browser
          ? const WebSessionVerification.unavailable()
          : await _ref
                .read(webSessionVerifierProvider)
                .verify(cookieHeader: cookieHeader);
      // A newer login/lockout superseded this check; never let a stale answer
      // overwrite the newer session state.
      if (!_isCurrent(generation)) return;
      final currentHeader = await webSession.cookieHeader();
      if (!_isCurrent(generation)) return;
      if (verificationCredentialRevision != _credentialRevision ||
          verificationCsrf != _ref.read(webSessionControllerProvider).csrf ||
          currentHeader != cookieHeader) {
        AppLogger.instance.info(
          'auth',
          'recovery discarded recoveryId=$recoveryId accountEpoch=$accountEpoch '
              'sessionGeneration=$generation credentialRevision=$_credentialRevision '
              'evidenceSource=bareProbe decisionReason=credentials_superseded',
        );
        _setTransient(
          WebSessionStatusState.unverified,
          'credentials-superseded',
        );
        return;
      }
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
      var confirmedCookies = cookies;
      if (decision.escalateToRealBrowser) {
        _ref.read(webSessionRefresherProvider).recoveryId = recoveryId;
        final after = await webSession.snapshot(
          source: 'check-after-unconfirmed',
        );
        AppLogger.instance.warning(
          'auth',
          'web session probe unconfirmed (${verification.state.name}): '
              'claimed=$claimedUsername '
              'cookieCount=${cookieHeaderCount(cookieHeader)} '
              'cookieFingerprint=${cookieHeaderFingerprint(cookieHeader)} '
              '${after.logLine()}',
        );
        // A bare unconfirmed answer never decides logged-out by itself: collect
        // real-browser evidence and apply it as a separate observation.
        final probe = await _ref.read(webSessionProbeProvider)();
        if (!_isCurrent(generation)) return;
        if (!await _probeCredentialsCurrent(probe, generation)) return;
        verifiedFingerprint = probe.credentialFingerprint;
        decision = applyVerification(
          WebSessionEvidence(
            source: WebSessionEvidenceSource.realBrowserProbe,
            outcome: probe.outcome,
            username: probe.username,
            generation: generation,
          ),
        );
        if (decision.nextState == WebSessionStatusState.healthy) {
          // The browser may rotate auth cookies during navigation. Persist its
          // current set rather than the stale pre-navigation HTTP snapshot.
          confirmedCookies = await webSession.cookies();
          if (!_isCurrent(generation)) return;
        }
      }
      if (decision.nextState == WebSessionStatusState.healthy) {
        // Record the credential set this healthy verdict was issued under:
        // for the plain path `confirmedCookies` equals the verified header
        // (the credentials-superseded guard above rejected any rotation),
        // for the escalated path it is the post-probe store the probe itself
        // authenticated. Feed-side rotation adoption keys off this value.
        _verifiedCredentialFingerprint = verifiedFingerprint;
        // Snapshot collection is another asynchronous read. A rotation after
        // the verdict must not persist an unverified replacement credential set.
        if (verifiedFingerprint == null ||
            cookieHeaderFingerprint(
                  WebSession.cookieHeaderFrom(confirmedCookies),
                ) !=
                verifiedFingerprint) {
          AppLogger.instance.info(
            'auth',
            'confirmed snapshot skipped reason=credentials_superseded',
          );
          return;
        }
        // Persist only a server-confirmed live cookie set. An unconfirmed
        // health check must never overwrite the snapshot: a degraded live
        // store during a WAF challenge can still carry a matching
        // `userinfo` cookie while the auth cookies are mid-rotation, and
        // re-persisting that set would make the next cold start restore dead
        // credentials (forced re-login).
        try {
          await _ref
              .read(webSessionControllerProvider.notifier)
              .ensurePersistentSnapshot(capturedCookies: confirmedCookies);
        } on Object catch (error) {
          AppLogger.instance.warning(
            'auth',
            'confirmed session snapshot save failed errorType=${error.runtimeType}',
          );
        }
      }
    } on Object {
      if (_isCurrent(generation)) _setUnavailable(source: 'check-error');
    } finally {
      if (_isCurrent(generation) &&
          _ref.read(loginObservationProvider(LoginChannel.web)).checking) {
        _observation.finish(
          LoginCheckResult.unavailable,
          reason: 'unavailable',
        );
      }
      AppLogger.instance.info(
        'auth',
        'recovery completed recoveryId=$recoveryId accountEpoch=$accountEpoch sessionGeneration=$generation current=$_generation state=${mounted ? state.state.name : 'disposed'}',
      );
    }
  }

  /// Called by the login WebView when DeviantArt reports its WAF lockout.
  /// All automatic retries must stop while this state is active.
  void markLocked() {
    _observation.finish(LoginCheckResult.challenge, reason: 'challenge');
    _generation++;
    _failures = 0;
    const next = WebSessionStatus(state: WebSessionStatusState.locked);
    _logTransition(next, 'web-login-challenge');
    state = next;
  }

  void markHealthy({required String serverUsername}) {
    _observation.begin(serverUsername);
    _generation++;
    _lastSuccess = _now();
    _lastRestrictionCheck = null;
    _failures = 0;
    applyVerification(
      WebSessionEvidence(
        source: WebSessionEvidenceSource.webLogin,
        outcome: WebSessionProbeOutcome.confirmed,
        username: serverUsername,
        generation: _generation,
      ),
    );
  }

  void _setEmptyLiveCookieState({required int persistedCount}) {
    final claimed = _ref.read(webSessionControllerProvider).isLoggedIn == true;
    if (emptyLiveCookieStatus(
          persistedCookieCount: persistedCount,
          claimedSignedIn: claimed,
        ) ==
        WebSessionStatusState.anonymous) {
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
          'source=$source generation=$_generation recoveryId=$_recoveryId accountEpoch=$_accountEpoch '
          'claimed=${claimed.isEmpty ? '-' : claimed} '
          'server=${next.serverUsername.isEmpty ? '-' : next.serverUsername}'
          '${cooldown == null ? '' : ' cooldown=$cooldown'}',
    );
  }

  void _setAnonymous({required String source}) {
    _observation.finish(
      LoginCheckResult.unauthenticated,
      reason: 'unauthenticated',
    );
    _failures = 0;
    const next = WebSessionStatus(state: WebSessionStatusState.anonymous);
    _logTransition(next, source);
    state = next;
  }

  void _setUnavailable({required String source}) =>
      _setTransient(WebSessionStatusState.unavailable, source);

  void _setTransient(WebSessionStatusState state, String source) {
    _observation.finish(LoginCheckResult.unavailable, reason: 'unavailable');
    final last = _lastSuccess;
    if (this.state.isHealthy &&
        last != null &&
        _now().difference(last) < cacheDuration) {
      AppLogger.instance.info(
        'auth',
        'recovery inconclusive recoveryId=$_recoveryId accountEpoch=$_accountEpoch '
            'sessionGeneration=$_generation credentialRevision=$_credentialRevision '
            'evidenceSource=$source decisionReason=retained_unexpired_lease',
      );
      // Do not renew the lease: persistent inconclusive evidence eventually
      // becomes unverified, while an authoritative logout takes effect now.
      return;
    }
    _failures += 1;
    final index = (_failures - 1).clamp(0, _backoff.length - 1);
    final next = WebSessionStatus(
      state: state,
      cooldownUntil: _now().add(_backoff[index]),
    );
    _logTransition(next, source);
    this.state = next;
  }
}
