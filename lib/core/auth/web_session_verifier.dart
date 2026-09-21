import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:dakit_web/dakit_web.dart';

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

  Future<String> username({required String cookieHeader}) async {
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
    if (status == 202 || status >= 400) return '';
    return usernameFromInitialState(response.data ?? '');
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
