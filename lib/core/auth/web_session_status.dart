import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'session_state.dart';
import 'web_session_controller.dart';

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
      state == WebSessionStatusState.unavailable ||
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
  bool _checking = false;

  /// Restores a persisted server-confirmed session snapshot, never during a
  /// backoff period. The next feed request is the acceptance gate: expired
  /// cookies surface as a feed error instead of forcing a WAF probe.
  Future<void> check({bool force = false}) async {
    if (_checking) return;
    final last = _lastSuccess;
    if (!force &&
        last != null &&
        state.isHealthy &&
        DateTime.now().difference(last) < _cacheDuration) {
      return;
    }
    if (!force && state.inCooldown) return;

    _checking = true;
    try {
      // Restore the persisted snapshot if the live WebView store lost it
      // (for example after an app update), before asking the server.
      await _ref
          .read(webSessionControllerProvider.notifier)
          .restorePersistedCookies();
      final webSession = _ref.read(webSessionProvider);
      final cookies = await webSession.cookies();
      if (cookies.isEmpty) {
        _setAnonymous();
        return;
      }
      // The persisted snapshot only exists because a previous session was
      // confirmed during an actual WebView login. Re-verifying it with a
      // separate HTTP request is exactly what makes the WAF report anonymous
      // on cold start. The authoritative acceptance happens on the next rfy
      // request: if the cookie expired, that fetch fails and surfaces error.
      final controllerState = _ref.read(webSessionControllerProvider);
      if (controllerState.isLoggedIn != true ||
          controllerState.username.trim().isEmpty) {
        _setAnonymous();
        return;
      }
      _lastSuccess = DateTime.now();
      _failures = 0;
      state = WebSessionStatus(
        state: WebSessionStatusState.healthy,
        serverUsername: controllerState.username,
        lastCheckedAt: DateTime.now(),
      );
    } on Object {
      _setUnavailable();
    } finally {
      _checking = false;
    }
  }

  /// Called by the login WebView when DeviantArt reports its WAF lockout.
  /// All automatic retries must stop while this state is active.
  void markLocked() {
    _failures = 0;
    state = const WebSessionStatus(state: WebSessionStatusState.locked);
  }

  void markHealthy({required String serverUsername}) {
    _lastSuccess = DateTime.now();
    _failures = 0;
    state = WebSessionStatus(
      state: WebSessionStatusState.healthy,
      serverUsername: serverUsername,
      lastCheckedAt: DateTime.now(),
    );
  }

  void _setAnonymous() {
    _failures = 0;
    state = const WebSessionStatus(state: WebSessionStatusState.anonymous);
  }

  void _setUnavailable() {
    _failures += 1;
    final index = (_failures - 1).clamp(0, _backoff.length - 1);
    state = WebSessionStatus(
      state: WebSessionStatusState.unavailable,
      cooldownUntil: DateTime.now().add(_backoff[index]),
    );
  }
}
