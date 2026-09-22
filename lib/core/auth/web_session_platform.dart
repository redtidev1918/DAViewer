import 'package:dakit_web/dakit_web.dart';

/// The User-Agent for embedded DeviantArt WebViews (visible login and the
/// headless CSRF browser). Android must present its real WebView UA: a desktop
/// Chrome UA from Android makes PerimeterX treat the WebView as an emulated
/// browser and server-side loop `/users/login` into a challenge lock. Desktop
/// keeps the desktop UA so deviantart.com serves its full login page.
String? webLoginUserAgent({required bool isAndroid}) =>
    isAndroid ? null : webUserAgent;
