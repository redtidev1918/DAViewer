import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../runtime/runtime_provider.dart';
import 'session_state.dart';
import 'web_session_controller.dart';
import 'web_session_verifier.dart';

export 'session_state.dart' show webSessionProvider;

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

  /// Runs the server-side verification at most once per cache window and
  /// never during a backoff period. UI rebuilds and feed fetches must call
  /// this method; they must not construct their own [WebSessionVerifier].
  Future<void> check() async {
    if (_checking) return;
    final last = _lastSuccess;
    if (last != null &&
        state.isHealthy &&
        DateTime.now().difference(last) < _cacheDuration) {
      return;
    }
    if (state.inCooldown) return;

    _checking = true;
    try {
      final runtime = _ref.read(runtimeProvider);
      final dio = runtime.dio;
      if (dio == null) {
        _setUnavailable();
        return;
      }
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
      final cookieHeader = cookies.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('; ');
      final serverUsername = await WebSessionVerifier(dio)
          .username(cookieHeader: cookieHeader);
      if (serverUsername.isEmpty) {
        _setAnonymous();
        return;
      }
      final expected = _ref.read(webSessionControllerProvider).username;
      if (expected.trim().isNotEmpty &&
          serverUsername.toLowerCase() != expected.trim().toLowerCase()) {
        _setStale(serverUsername);
        return;
      }
      _lastSuccess = DateTime.now();
      _failures = 0;
      state = WebSessionStatus(
        state: WebSessionStatusState.healthy,
        serverUsername: serverUsername,
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

  void _setStale(String serverUsername) {
    _failures = 0;
    state = WebSessionStatus(
      state: WebSessionStatusState.stale,
      serverUsername: serverUsername,
    );
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
