import 'package:dio/dio.dart';

import 'package:dakit_web/dakit_web.dart';

import '../diagnostics/app_logger.dart';
import 'web_session_diagnostics.dart';

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
  static const String _marker = 'window.__INITIAL_STATE__ = JSON.parse(';

  Future<WebSessionVerification> verify({required String cookieHeader}) async {
    AppLogger.instance.info(
      'auth',
      'web session verifier request cookieCount='
          '${cookieHeaderCount(cookieHeader)} cookieFingerprint='
          '${cookieHeaderFingerprint(cookieHeader)}',
    );
    try {
      final response = await _dio
          .get<String>(
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
          )
          .timeout(const Duration(seconds: 10));
      final status = response.statusCode ?? 0;
      if (status != 200) {
        AppLogger.instance.info(
          'auth',
          'web session verifier response status=$status '
              'classification=${WebSessionVerificationState.unavailable.name}',
        );
        return const WebSessionVerification.unavailable();
      }
      final html = response.data ?? '';
      if (!html.contains(_marker)) {
        AppLogger.instance.info(
          'auth',
          'web session verifier response status=$status '
              'classification=${WebSessionVerificationState.unavailable.name}',
        );
        return const WebSessionVerification.unavailable();
      }
      final username = pageUsernameFromInitialState(html);
      final result = username == 'anonymous'
          ? const WebSessionVerification.anonymous()
          : username == null || username.isEmpty
          ? const WebSessionVerification.unavailable()
          : WebSessionVerification.signedIn(username);
      AppLogger.instance.info(
        'auth',
        'web session verifier response status=$status '
            'classification=${result.state.name}',
      );
      return result;
    } on Object {
      return const WebSessionVerification.unavailable();
    }
  }

  Future<String> username({required String cookieHeader}) async {
    return (await verify(cookieHeader: cookieHeader)).username;
  }

  /// Parses the username DeviantArt itself rendered for this cookie session.
  static String usernameFromInitialState(String html) {
    final username = pageUsernameFromInitialState(html);
    return username == 'anonymous' ? '' : username ?? '';
  }

  /// Null means absent or unparseable evidence; only the literal anonymous
  /// identity is a server statement that the session is signed out.
  static String? pageUsernameFromInitialState(String html) {
    try {
      final state = jsonParseAssignment(
        html,
        marker: _marker,
        missingMessage: 'Missing session initializer.',
      );
      final session = state['@publicSession'];
      if (session is! Map) return null;
      final user = session['user'];
      if (user is! Map) return null;
      final username = user['username'];
      if (username is! String) return null;
      return username.trim();
    } on FormatException {
      return null;
    }
  }
}
