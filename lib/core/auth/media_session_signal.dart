import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'web_session_controller.dart';
import 'web_session_status.dart';

/// Bridges media stacks that do not use the shared Dio into the web-session
/// trigger layer.
///
/// [CachedNetworkImage], `Image.network` and `VideoPlayerController` each own
/// their own HTTP client, so a 401/403 from an image or video never reaches the
/// Dio interceptor. A rejected mature/paid host URL is still only a *signal*:
/// the verdict chain re-verifies the session server-side before deciding that
/// the Cookie expired, and a genuinely paid asset never prompts for login.
///
/// The status controller already coalesces concurrent calls and throttles the
/// 30-second restriction window, so this reporter stays stateless.
///
/// Injected like [webSessionProbeProvider], so widget tests can record the
/// signal without standing up the platform-dependent verification chain.
final webSessionSignalReporterProvider = Provider<void Function(String source)>(
  (ref) =>
      (source) => unawaited(
        ref
            .read(webSessionStatusProvider.notifier)
            .recheckAfterWebSignal(source),
      ),
);

final class MediaSessionSignal {
  const MediaSessionSignal._();

  static final RegExp _httpStatusPattern = RegExp(r'\b(401|403)\b');

  /// Forwards [error] to the verdict chain when it looks like an
  /// authentication rejection. Network failures, timeouts and 404s are ignored.
  static void report(BuildContext context, Object error, String source) {
    if (!isAuthRejection(error)) return;
    ProviderContainer container;
    try {
      container = ProviderScope.containerOf(context, listen: false);
    } on Object {
      return;
    }
    final status = container.read(webSessionStatusProvider);
    if (status.needsLogin || status.isLocked || status.inCooldown) return;
    if (container.read(webSessionControllerProvider).isLoggedIn != true) {
      return;
    }
    container.read(webSessionSignalReporterProvider)(source);
  }

  /// True when [error] carries an HTTP 401 or 403 status from one of the
  /// non-Dio media stacks. Formatting is defensive: the video player and
  /// platform channels surface status codes only inside their error text.
  static bool isAuthRejection(Object error) {
    if (error is HttpExceptionWithStatus) {
      return error.statusCode == 401 || error.statusCode == 403;
    }
    return _httpStatusPattern.hasMatch(error.toString());
  }
}
