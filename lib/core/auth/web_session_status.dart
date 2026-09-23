import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diagnostics/app_logger.dart';
import '../data/web_session.dart';
import '../runtime/runtime_provider.dart';
import 'session_state.dart';
import 'web_session_controller.dart';
import 'web_session_diagnostics.dart';
import 'web_session_refresher.dart';
import 'web_session_verifier.dart';

export 'session_state.dart' show webSessionProvider;

/// Set by the splash screen after the persisted Web Session snapshot has been
/// restored. Personalized/data providers that depend on the web identity wait
/// for this flag so a cold-start identity restore cannot recreate them twice
/// (unknown → restored) and emit a duplicate initial request.
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
        _setAnonymous();
        return;
      }
      final cookieHeader = WebSession.cookieHeaderFrom(cookies);
      if (cookieHeader.isEmpty) {
        final empty = await webSession.snapshot(source: 'check-empty-cookie');
        AppLogger.instance.warning('auth', empty.logLine());
        if (!_isCurrent(generation)) return;
        _setAnonymous();
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
      switch (verification.state) {
        case WebSessionVerificationState.signedIn:
          if (verification.username.trim().toLowerCase() !=
              claimedUsername.toLowerCase()) {
            final after = await webSession.snapshot(
              source: 'check-after-anonymous',
            );
            AppLogger.instance.warning(
              'auth',
              'server rejected web session: claimed=$claimedUsername '
                  'server=${verification.username} '
                  'cookieCount=${cookieHeaderCount(cookieHeader)} '
                  'cookieFingerprint=${cookieHeaderFingerprint(cookieHeader)} '
                  '${after.logLine()}',
            );
            _setAnonymous();
            return;
          }
          _lastSuccess = DateTime.now();
          _failures = 0;
          state = WebSessionStatus(
            state: WebSessionStatusState.healthy,
            serverUsername: verification.username,
            lastCheckedAt: DateTime.now(),
          );
          // Persist only a server-confirmed live cookie set. An unconfirmed
          // health check must never overwrite the snapshot: a degraded live
          // store during a WAF challenge can still carry a matching
          // `userinfo` cookie while the auth cookies are mid-rotation, and
          // re-persisting that set would make the next cold start restore dead
          // credentials (forced re-login).
          await _ref
              .read(webSessionControllerProvider.notifier)
              .ensurePersistentSnapshot(capturedCookies: cookies);
        case WebSessionVerificationState.anonymous:
          // A bare HTTP probe reporting anonymous is not proof the WebView is
          // signed out (PerimeterX can serve an anonymous page for a valid
          // session). Arbitrate with the real headless browser before deciding:
          // it carries the same cookie store and request stack as the login
          // WebView, so only its answer is authoritative about logged-out.
          if (controllerState.isLoggedIn == true &&
              claimedUsername.isNotEmpty) {
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
            final probe = await _ref.read(webSessionProbeProvider)();
            if (!_isCurrent(generation)) return;
            switch (probe.outcome) {
              case WebSessionProbeOutcome.confirmed:
                if (probe.username.trim().toLowerCase() !=
                    claimedUsername.toLowerCase()) {
                  _setAnonymous();
                  return;
                }
                // The real browser confirms the same account: the bare probe
                // was a WAF false negative after all.
                _lastSuccess = DateTime.now();
                _failures = 0;
                state = WebSessionStatus(
                  state: WebSessionStatusState.healthy,
                  serverUsername: probe.username,
                  lastCheckedAt: DateTime.now(),
                );
                await _ref
                    .read(webSessionControllerProvider.notifier)
                    .ensurePersistentSnapshot(capturedCookies: cookies);
              case WebSessionProbeOutcome.anonymous:
                // The real browser also reports logged out: the web Cookie
                // really is dead. Surface the login reminder instead of
                // silently serving generic content.
                _setAnonymous();
              case WebSessionProbeOutcome.unavailable:
                // The real browser could not answer either (challenge,
                // network). Stay non-committal; never a logged-out signal.
                _setUnverified();
            }
          } else {
            _setAnonymous();
          }
        case WebSessionVerificationState.unavailable:
          _setUnavailable();
      }
    } on Object {
      if (_isCurrent(generation)) _setUnavailable();
    }
  }

  /// Called by the login WebView when DeviantArt reports its WAF lockout.
  /// All automatic retries must stop while this state is active.
  void markLocked() {
    _generation++;
    _failures = 0;
    state = const WebSessionStatus(state: WebSessionStatusState.locked);
  }

  void markHealthy({required String serverUsername}) {
    _generation++;
    _lastSuccess = DateTime.now();
    _failures = 0;
    state = WebSessionStatus(
      state: WebSessionStatusState.healthy,
      serverUsername: serverUsername,
      lastCheckedAt: DateTime.now(),
    );
  }

  void _setEmptyLiveCookieState({required int persistedCount}) {
    if (persistedCount == 0) {
      _setAnonymous();
    } else {
      _setUnavailable();
    }
  }

  void _setAnonymous() {
    _failures = 0;
    state = const WebSessionStatus(state: WebSessionStatusState.anonymous);
  }

  /// A confirmed WebView session that a bare HTTP probe could not confirm.
  /// Kept out of [WebSessionStatus.needsLogin] so a WAF false-negative never
  /// sends the user back into the login challenge loop.
  void _setUnverified() => _setTransient(WebSessionStatusState.unverified);

  void _setUnavailable() => _setTransient(WebSessionStatusState.unavailable);

  void _setTransient(WebSessionStatusState state) {
    _failures += 1;
    final index = (_failures - 1).clamp(0, _backoff.length - 1);
    this.state = WebSessionStatus(
      state: state,
      cooldownUntil: DateTime.now().add(_backoff[index]),
    );
  }
}
