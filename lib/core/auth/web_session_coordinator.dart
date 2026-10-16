import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diagnostics/app_logger.dart';
import '../runtime/runtime_provider.dart';
import 'web_session_controller.dart';
import 'web_session_status.dart';

final webSessionCoordinatorProvider = Provider<WebSessionCoordinator>((ref) {
  final status = ref.read(webSessionStatusProvider.notifier);
  final dio = ref.read(runtimeProvider).dio;
  if (dio == null) {
    // Production builds always obtain the runtime from AppRuntime.create(),
    // which wires the shared Dio. A null Dio only happens with the synchronous
    // AppRuntime.fromEnvironment() test constructor: log instead of silently
    // losing every web-session signal.
    AppLogger.instance.warning(
      'auth',
      'web session coordinator attached without a Dio; web signals disabled',
    );
  }
  final coordinator = WebSessionCoordinator(
    dio: dio,
    now: () => ref.read(webSessionClockProvider)(),
    currentStatus: () => ref.read(webSessionStatusProvider),
    lastSuccessAt: () => status.lastSuccessAt,
    shouldVerify: () =>
        // Deliberate gate: a device that never logged in must not receive a
        // "refresh your Cookie" prompt for ordinary public traffic. The cost is
        // a narrow edge case — local logged-in flag lost while the server
        // session is still alive; signing in again is the intended recovery.
        ref.mounted &&
        ref.read(webSessionControllerProvider).isLoggedIn == true &&
        !ref.read(webSessionStatusProvider).needsLogin,
    verify: (forced, source) => forced
        ? status.recheckAfterWebSignal(source)
        : status.check(source: source),
  );
  // Every verdict transition (and only those) re-arms the lease schedule;
  // the coordinator itself re-arms after each verification attempt so an
  // inconclusive "keep" answer cannot leave the schedule dead.
  ref.listen(
    webSessionStatusProvider,
    (_, next) => coordinator.onStatusChanged(next),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

/// Single policy home for verification scheduling thresholds. They are
/// scheduling hints only — never identity trust durations.
final class WebSessionScheduling {
  /// A cold start verifies only when the persisted last success is older than
  /// this (or absent); feed and signal driven checks cover fresher sessions.
  static const Duration startupInterval = Duration(hours: 24);

  /// Returning to the foreground re-verifies only when the last success is
  /// older than this (or absent); other resumes only re-arm the lease timer.
  static const Duration resumeInterval = Duration(hours: 6);
}

/// Coordinates triggers only. The verifier remains the sole verdict writer.
/// Instead of polling, a single one-shot task re-verifies when the healthy
/// lease or the transient backoff expires; terminal states (anonymous,
/// stale, locked, unknown) never schedule autonomously — events drive them.
final class WebSessionCoordinator {
  WebSessionCoordinator({
    required this.shouldVerify,
    required this.verify,
    required this.now,
    required this.currentStatus,
    required this.lastSuccessAt,
    this.dio,
    this.resumeInterval = WebSessionScheduling.resumeInterval,
  }) {
    _interceptor = InterceptorsWrapper(
      onResponse: (response, handler) {
        final signal = webSessionResponseSignal(response);
        if (signal != null) _request(true, signal);
        handler.next(response);
      },
      onError: (error, handler) {
        final response = error.response;
        final signal = response == null
            ? null
            : webSessionResponseSignal(response);
        if (signal != null) _request(true, signal);
        handler.next(error);
      },
    );
    dio?.interceptors.add(_interceptor);
    _arm();
  }

  final Dio? dio;
  final bool Function() shouldVerify;
  final Future<void> Function(bool forced, String source) verify;
  final DateTime Function() now;
  final WebSessionStatus Function() currentStatus;
  final DateTime? Function() lastSuccessAt;
  final Duration resumeInterval;
  late final Interceptor _interceptor;
  Timer? _scheduled;
  DateTime? _lastRequestAt;
  bool _paused = false;
  bool _disposed = false;

  /// A forced verdict observed while paused. Dropping it would lose the only
  /// evidence that the session was rejected, and the time-based resume check
  /// cannot replace it, so it is replayed on the next resume.
  String? _pendingForcedSource;

  void onStatusChanged(WebSessionStatus status) => _armFrom(status);

  void pause() {
    _paused = true;
    _scheduled?.cancel();
    _scheduled = null;
  }

  void resume() {
    if (_disposed) return;
    _paused = false;
    final pending = _pendingForcedSource;
    _pendingForcedSource = null;
    if (pending != null) {
      // The verdict observed while paused is the reason to check at all, and it
      // outranks the time-based resume window.
      _request(true, pending);
    } else {
      final lastSuccess = lastSuccessAt();
      if (lastSuccess == null ||
          now().difference(lastSuccess) > resumeInterval) {
        // Non-forced: the healthy cache has long expired at this distance and
        // transient backoff must still apply after a recent failure.
        _request(false, 'app-resume');
      }
    }
    _arm();
  }

  void dispose() {
    _disposed = true;
    _scheduled?.cancel();
    _scheduled = null;
    dio?.interceptors.remove(_interceptor);
  }

  void _arm() => _armFrom(currentStatus());

  void _armFrom(WebSessionStatus status) {
    if (_disposed || _paused) return;
    _scheduled?.cancel();
    _scheduled = null;
    final due = _nextDue(status);
    if (due == null) return;
    var delay = due.difference(now());
    if (delay <= Duration.zero) {
      // An attempt that ends without publishing a new verdict (an
      // inconclusive "keep") leaves the old due date at or before now;
      // retrying at full speed would busy-loop, so a due-now arm waits for the
      // floor exactly like a past-due one.
      final sinceRequest = _lastRequestAt == null
          ? null
          : now().difference(_lastRequestAt!);
      const floor = Duration(seconds: 10);
      delay = sinceRequest != null && sinceRequest < floor
          ? floor - sinceRequest
          : Duration.zero;
    }
    // Timer.zero keeps the request off the listener's synchronous stack.
    _scheduled = Timer(delay, () {
      _scheduled = null;
      _request(false, 'lease-expired');
    });
  }

  DateTime? _nextDue(WebSessionStatus status) {
    final checkedAt = status.lastCheckedAt;
    if (status.isHealthy && checkedAt != null) {
      return checkedAt.add(WebSessionStatusController.cacheDuration);
    }
    // A transient state retries once when its backoff expires; terminal
    // states carry no cooldown and never schedule autonomously.
    final cooldown = status.cooldownUntil;
    if (cooldown != null) return cooldown;
    return null;
  }

  void _request(bool forced, String source) {
    if (_disposed) return;
    if (_paused) {
      if (forced) _pendingForcedSource = source;
      return;
    }
    if (!shouldVerify()) return;
    _lastRequestAt = now();
    unawaited(_verify(forced, source));
  }

  Future<void> _verify(bool forced, String source) async {
    try {
      await verify(forced, source);
    } on Object catch (error) {
      AppLogger.instance.warning(
        'auth',
        'web verification trigger failed source=$source',
        error,
      );
    } finally {
      // An inconclusive answer keeps the old state object (no listener
      // fires); re-arming here is what keeps long foreground stays covered.
      _arm();
    }
  }
}

/// Reject CDN, verifier-home, and OAuth traffic. They must never feed an
/// authentication signal back into the verification chain: an image 403 is a
/// content restriction, the home probe is the verdict chain observing its own
/// echo, and an OAuth rejection is about the API token, not the Cookie.
String? webSessionResponseSignal(Response<Object?> response) {
  final uri = response.requestOptions.uri;
  if (uri.host != 'www.deviantart.com' && uri.host != 'deviantart.com') {
    return null;
  }
  if (uri.path == '/' || uri.path.startsWith('/oauth')) {
    return null;
  }
  final target = response.realUri;
  final targetIsWeb =
      target.host == 'www.deviantart.com' || target.host == 'deviantart.com';
  if (targetIsWeb && target.path.startsWith('/users/login')) {
    return 'web-login-redirect';
  }
  if (response.statusCode == 401 || response.statusCode == 403) {
    return 'web-http-${response.statusCode}';
  }
  if (_containsMatureLoginReason(response.data, 0)) {
    return 'web-mature-loggedout';
  }
  return null;
}

bool _containsMatureLoginReason(Object? data, int depth) {
  if (depth > 6) {
    return false;
  }
  if (data is Map) {
    final reasons = data['blockReasons'] ?? data['block_reasons'];
    if (reasons is List && reasons.contains('mature_loggedout')) {
      return true;
    }
    return data.values.any(
      (value) => _containsMatureLoginReason(value, depth + 1),
    );
  }
  if (data is List) {
    return data.any((value) => _containsMatureLoginReason(value, depth + 1));
  }
  return false;
}
