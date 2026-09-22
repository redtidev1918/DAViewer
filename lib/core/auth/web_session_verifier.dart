import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:dakit_web/dakit_web.dart';

/// What the DeviantArt home page said about the Cookie header.
enum WebSessionVerificationState { signedIn, anonymous, unavailable }

final class WebSessionVerification {
  const WebSessionVerification.signedIn(this.username)
    : state = WebSessionVerificationState.signedIn;

  const WebSessionVerification.anonymous()
    : state = WebSessionVerificationState.anonymous,
      username = '';

  const WebSessionVerification.unavailable()
    : state = WebSessionVerificationState.unavailable,
      username = '';

  final WebSessionVerificationState state;
  final String username;

  bool get isSignedIn => state == WebSessionVerificationState.signedIn;
  bool get isAnonymous => state == WebSessionVerificationState.anonymous;
}

/// Confirms the DeviantArt web login with the server, not with the local
/// cookie store.
///
/// The home page's `__INITIAL_STATE__` exposes
/// `@publicSession.user.username`; an anonymous page reports `anonymous`.
/// A stale local `userinfo` cookie might still exist, but the server answer is
/// what decides whether the personalized web session is usable.
final class WebSessionVerifier {
  const WebSessionVerifier(this._dio);

  final Dio _dio;

  static final Uri _home = Uri.parse('https://www.deviantart.com/');
  static const String _marker = 'window.__INITIAL_STATE__ = JSON.parse("';

  Future<WebSessionVerification> verify({required String cookieHeader}) async {
    try {
      final response = await _dio.get<String>(
        _home.toString(),
        options: Options(
          responseType: ResponseType.plain,
          headers: <String, dynamic>{
            'Accept': 'text/html,application/xhtml+xml',
            if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
            'User-Agent': webUserAgent,
          },
          validateStatus: (_) => true,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status != 200) {
        return const WebSessionVerification.unavailable();
      }
      final html = response.data ?? '';
      if (!html.contains(_marker)) {
        return const WebSessionVerification.unavailable();
      }
      final username = usernameFromInitialState(html);
      return username.isEmpty
          ? const WebSessionVerification.anonymous()
          : WebSessionVerification.signedIn(username);
    } on Object {
      return const WebSessionVerification.unavailable();
    }
  }

  Future<String> username({required String cookieHeader}) async {
    return (await verify(cookieHeader: cookieHeader)).username;
  }

  /// Parses the username DeviantArt itself rendered for this cookie session.
  static String usernameFromInitialState(String html) {
    final start = html.indexOf(_marker);
    if (start < 0) return '';
    final quoteStart = start + _marker.length;
    final quoteEnd = html.indexOf('");', quoteStart);
    if (quoteEnd < 0) return '';
    final escaped = html.substring(quoteStart, quoteEnd);
    try {
      final inner = jsonDecode('"$escaped"') as String;
      final state = jsonDecode(inner);
      if (state is! Map) return '';
      final session = state['@publicSession'];
      if (session is! Map) return '';
      final user = session['user'];
      if (user is! Map) return '';
      final username = user['username'];
      if (username is! String || username == 'anonymous') return '';
      return username.trim();
    } on FormatException {
      return '';
    }
  }
}
