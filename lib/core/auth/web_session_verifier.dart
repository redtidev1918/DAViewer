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
/// The home page's `__INITIAL_STATE__` exposes the session under the
/// redux-style key `@@publicSession` (verified against the production home
/// page; a single-@ spelling is tolerated as legacy): `isLoggedIn` states
/// whether the cookie session is signed in, and `user.username` names the
/// account (an anonymous page reports `anonymous`). A stale local `userinfo`
/// cookie might still exist, but the server answer is what decides whether
/// the personalized web session is usable.
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
              'classification=${WebSessionVerificationState.unavailable.name} '
              '${_responseForensics(response)}',
        );
        return const WebSessionVerification.unavailable();
      }
      final html = response.data ?? '';
      if (!html.contains(_marker)) {
        AppLogger.instance.info(
          'auth',
          'web session verifier response status=$status '
              'classification=${WebSessionVerificationState.unavailable.name} '
              '${_responseForensics(response)}',
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
    } on Object catch (error) {
      // The type (never the message: Dio messages embed URLs) separates
      // transport timeouts from connection failures in device captures.
      final dioType = error is DioException
          ? ' dioType=${error.type.name}'
          : '';
      AppLogger.instance.info(
        'auth',
        'web session verifier error errorType=${error.runtimeType}$dioType',
      );
      return const WebSessionVerification.unavailable();
    }
  }

  /// Non-credential forensics for captures where the server rejects the web
  /// session: structural facts plus the two PerimeterX markers already
  /// verified in `browserSessionEvidenceScript` — media type, body size,
  /// redirect count, final host (never path or query, which can carry
  /// tokens), and whether the identity initializer rendered at all. New body
  /// markers must come from a captured document first; nothing speculative.
  static String _responseForensics(Response<String> response) {
    final contentType =
        response.headers.value(Headers.contentTypeHeader)?.trim() ?? 'unknown';
    final body = response.data ?? '';
    final finalHost = response.realUri.host;
    return 'contentType=$contentType '
        'contentLength=${body.length} '
        'redirects=${response.redirects.length} '
        'finalHost=${finalHost.isEmpty ? 'unknown' : finalHost} '
        'pxBlocked=${body.contains('Max challenge attempts exceeded')} '
        'pxChallenge=${body.contains('#px-captcha') || body.contains('challenge-container')} '
        'initialState=${body.contains(_marker)}';
  }

  Future<String> username({required String cookieHeader}) async {
    return (await verify(cookieHeader: cookieHeader)).username;
  }

  /// Parses the username DeviantArt itself rendered for this cookie session.
  static String usernameFromInitialState(String html) {
    final username = pageUsernameFromInitialState(html);
    return username == 'anonymous' ? '' : username ?? '';
  }

  /// Null means absent or unparseable evidence. Only a server statement —
  /// the literal `anonymous` identity or an explicit `isLoggedIn: false` —
  /// says the session is signed out; `isLoggedIn: true` without a username
  /// stays unverified (null) instead of guessing.
  static String? pageUsernameFromInitialState(String html) {
    try {
      final state = jsonParseAssignment(
        html,
        marker: _marker,
        missingMessage: 'Missing session initializer.',
      );
      final session = state['@@publicSession'] ?? state['@publicSession'];
      if (session is! Map) return null;
      final user = session['user'];
      final username = user is Map && user['username'] is String
          ? (user['username'] as String).trim()
          : null;
      if (session['isLoggedIn'] == false) return 'anonymous';
      return username;
    } on FormatException {
      return null;
    }
  }
}
