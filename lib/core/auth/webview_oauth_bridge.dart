import 'dart:async';

import 'package:dakit_core/dakit_core.dart';

import '../network/desktop_uri_launcher.dart';
import '../diagnostics/app_logger.dart';

/// Routes every DAKit OAuth transaction through the embedded WebView so a
/// single login establishes both the deviantart.com web Cookie/CSRF session and
/// the OAuth account — the user signs in once on the DeviantArt login page and
/// gets both, regardless of which provider (DeviantArt / Google / Apple) they
/// pick on that page.
///
/// The system browser is only a fallback for the rare case where no WebView
/// listener is subscribed (the login screen is not open).
final class WebViewOAuthBridge implements ExternalUriLauncher {
  WebViewOAuthBridge({ExternalUriLauncher? fallback})
    : _fallback = fallback ?? const DesktopUriLauncher();

  final ExternalUriLauncher _fallback;
  final StreamController<Uri> _launchController =
      StreamController<Uri>.broadcast();
  final StreamController<Uri> _callbackController =
      StreamController<Uri>.broadcast();

  /// Authorize URLs that should be loaded in the login WebView.
  Stream<Uri> get launchRequests => _launchController.stream;

  /// OAuth callbacks captured from the login WebView.
  CallbackUriSource get callbacks =>
      _StreamCallbackSource(_callbackController.stream);

  void addCallback(Uri uri) {
    if (uri.scheme != 'dakit' || uri.host != 'oauth') return;
    AppLogger.instance.info(
      'oauthBridge',
      'callback received path=${uri.path} listener=${_callbackController.hasListener}',
    );
    _callbackController.add(uri);
  }

  @override
  Future<void> launch(Uri uri) async {
    // The WebLoginScreen subscribes in initState right after its route is
    // pushed, so give it a short grace period before falling back to the
    // system browser. Falling back too eagerly would leave the embedded web
    // session out of sync with the OAuth account.
    for (var i = 0; i < 25 && !_launchController.hasListener; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (_launchController.hasListener) {
      AppLogger.instance.info(
        'oauthBridge',
        'authorize dispatched target=embedded listener=true path=${uri.path}',
      );
      _launchController.add(uri);
    } else {
      AppLogger.instance.warning(
        'oauthBridge',
        'authorize dispatched target=system listener=false path=${uri.path}',
      );
      await _fallback.launch(uri);
    }
  }

  Future<void> dispose() async {
    await _launchController.close();
    await _callbackController.close();
  }
}

final class _StreamCallbackSource implements CallbackUriSource {
  const _StreamCallbackSource(this._stream);

  final Stream<Uri> _stream;

  @override
  Stream<Uri> get uris => _stream;
}
