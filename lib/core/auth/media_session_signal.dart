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

  static final RegExp _httpStatusPattern = RegExp(
    r'\b(?:status(?:code)?|response(?: code)?|http(?: error)?)[\s:=]*(401|403)\b',
    caseSensitive: false,
  );
  static final RegExp _urlPattern = RegExp(
    r'''https?://[^\s'"<>]+''',
    caseSensitive: false,
  );

  /// The site hosts whose 401/403 may feed the global web-session verdict
  /// chain. Resource hosts (wixmp.com, deviantart.net media subdomains)
  /// answer for themselves and are deliberately absent.
  static const Set<String> _siteHosts = <String>{
    'deviantart.com',
    'www.deviantart.com',
  };

  /// Forwards [error] to the verdict chain only when it is an authentication
  /// rejection attributable to the DeviantArt site itself. Network failures,
  /// timeouts and 404s are ignored; so are CDN/media-host 403s (wixmp signed
  /// URL expiry, paid-content blur proxies) and errors whose text carries no
  /// attributable URL — one expired thumbnail must never start a global
  /// session re-verification.
  static void report(BuildContext context, Object error, String source) {
    if (!isWebSessionAuthRejection(error)) return;
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

  /// An auth rejection that names a DeviantArt site host. The URL is extracted
  /// from the error text and parsed with [Uri] before comparing `uri.host` —
  /// a raw string comparison misattributes root domains, explicit ports and
  /// mixed-case hosts. Unattributable errors prove nothing about the session.
  static bool isWebSessionAuthRejection(Object error) {
    if (!isAuthRejection(error)) return false;
    final uri = _urlOf(error);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;
    return _siteHosts.contains(host) || host.endsWith('.deviantart.com');
  }

  static Uri? _urlOf(Object error) {
    // `uri` is inherited from dart:io HttpException; matching the concrete
    // cache-manager type avoids a direct dart:io import in this file.
    if (error is HttpExceptionWithStatus) {
      return error.uri;
    }
    final match = _urlPattern.firstMatch(error.toString());
    if (match == null) return null;
    final text = match.group(0)!.replaceFirst(RegExp(r'[),.;\]}]+$'), '');
    return Uri.tryParse(text);
  }
}
