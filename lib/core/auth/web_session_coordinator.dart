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
    shouldVerify: () =>
        // Deliberate gate: a device that never logged in must not receive a
        // "refresh your Cookie" prompt for ordinary public traffic. The cost is
        // a narrow edge case — local logged-in flag lost while the server
        // session is still alive; signing in again is the intended recovery.
        ref.mounted &&
        ref.read(webSessionControllerProvider).isLoggedIn == true &&
        !ref.read(webSessionStatusProvider).needsLogin,
    verify: (forced, source) =>
        forced ? status.recheckAfterWebSignal(source) : status.check(),
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

/// Coordinates triggers only. The verifier remains the sole verdict writer.
/// Periodic checks cover dead cookies whose endpoints still answer HTTP 200.
final class WebSessionCoordinator {
  WebSessionCoordinator({
    required this.shouldVerify,
    required this.verify,
    this.dio,
    this.interval = const Duration(minutes: 1),
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
    _startTimer();
  }

  final Dio? dio;
  final bool Function() shouldVerify;
  final Future<void> Function(bool forced, String source) verify;
  final Duration interval;
  late final Interceptor _interceptor;
  Timer? _timer;
  bool _disposed = false;

  void pause() {
    _timer?.cancel();
    _timer = null;
  }

  void resume() {
    if (_disposed) return;
    _startTimer();
    // Returning to the foreground is an explicit "check now" moment: a cached
    // healthy verdict must not hide a Cookie that died while we were away.
    _request(true, 'app-resume');
  }

  void dispose() {
    _disposed = true;
    pause();
    dio?.interceptors.remove(_interceptor);
  }

  void _startTimer() {
    if (_timer != null || _disposed) return;
    _timer = Timer.periodic(interval, (_) => _request(false, 'periodic'));
  }

  void _request(bool forced, String source) {
    if (_disposed || !shouldVerify()) return;
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
