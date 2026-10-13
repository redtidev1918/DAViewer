import 'dart:typed_data';

import 'package:daviewer/core/auth/web_session_verifier.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

final class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.status, {this.html = 'challenge'});

  final int status;
  final String html;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    html,
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>['text/html'],
    },
  );
}

void main() {
  test('shared SDK decoder accepts JavaScript escapes in session initializer', () {
    const html =
        r'''<script>window.__INITIAL_STATE__ = JSON.parse("{\"@@publicSession\":{\"isLoggedIn\":true,\"user\":{\"username\":\"artist\"}},\"title\":\"artist\'s work\"}");</script>''';
    expect(WebSessionVerifier.pageUsernameFromInitialState(html), 'artist');
  });
  test('single-quoted initializer keeps explicit anonymous distinct from missing', () {
    const html =
        r'''<script>window.__INITIAL_STATE__ = JSON.parse('{"@@publicSession":{"isLoggedIn":false,"user":{"username":"anonymous"}}}');</script>''';
    expect(WebSessionVerifier.pageUsernameFromInitialState(html), 'anonymous');
    expect(WebSessionVerifier.pageUsernameFromInitialState('<html/>'), isNull);
  });
  test('legacy single-@ spelling still parses for older page variants', () {
    const html =
        r'''<script>window.__INITIAL_STATE__ = JSON.parse("{\"@publicSession\":{\"user\":{\"username\":\"artist\"}}}");</script>''';
    expect(WebSessionVerifier.pageUsernameFromInitialState(html), 'artist');
  });
  group('isLoggedIn regression (production key @@publicSession)', () {
    test('isLoggedIn=false without a username is a signed-out statement', () {
      const html =
          r'''<script>window.__INITIAL_STATE__ = JSON.parse("{\"@@publicSession\":{\"isLoggedIn\":false}}");</script>''';
      expect(
        WebSessionVerifier.pageUsernameFromInitialState(html),
        'anonymous',
      );
    });
    test('isLoggedIn=true without a username stays unverified', () {
      const html =
          r'''<script>window.__INITIAL_STATE__ = JSON.parse("{\"@@publicSession\":{\"isLoggedIn\":true}}");</script>''';
      expect(WebSessionVerifier.pageUsernameFromInitialState(html), isNull);
    });
    test('verify maps isLoggedIn=false (no username) to anonymous', () async {
      final dio = Dio()
        ..httpClientAdapter = _StatusAdapter(
          200,
          html: '<script>window.__INITIAL_STATE__ = JSON.parse("{\\"@@publicSession\\":{\\"isLoggedIn\\":false}}");</script>',
        );
      final result = await WebSessionVerifier(dio)
          .verify(cookieHeader: 'userinfo=saved');
      expect(result.state, WebSessionVerificationState.anonymous);
    });
    test(
      'verify maps isLoggedIn=true without username to unavailable',
      () async {
        final dio = Dio()
          ..httpClientAdapter = _StatusAdapter(
            200,
            html: '<script>window.__INITIAL_STATE__ = JSON.parse("{\\"@@publicSession\\":{\\"isLoggedIn\\":true}}");</script>',
          );
        final result = await WebSessionVerifier(dio)
            .verify(cookieHeader: 'userinfo=saved');
        expect(result.state, WebSessionVerificationState.unavailable);
      },
    );
  });
  for (final fixture in [
    'window.__INITIAL_STATE__ = JSON.parse("broken");',
    'window.__INITIAL_STATE__ = JSON.parse("{}");',
    'window.__INITIAL_STATE__ = JSON.parse("{\\"@@publicSession\\":{}}");',
  ]) {
    test(
      'HTTP 200 with incomplete or malformed state is inconclusive: $fixture',
      () async {
        final dio = Dio()
          ..httpClientAdapter = _StatusAdapter(200, html: fixture);
        final result = await WebSessionVerifier(dio)
            .verify(cookieHeader: 'userinfo=saved');
        expect(result.state, WebSessionVerificationState.unavailable);
      },
    );
  }
  test('literal anonymous identity is a server statement', () async {
    final dio = Dio()
      ..httpClientAdapter = _StatusAdapter(
        200,
        html: '<script>window.__INITIAL_STATE__ = JSON.parse("{\\"@@publicSession\\":{\\"isLoggedIn\\":false,\\"user\\":{\\"username\\":\\"anonymous\\"}}}");</script>',
      );
    final result = await WebSessionVerifier(dio)
        .verify(cookieHeader: 'userinfo=saved');
    expect(result.state, WebSessionVerificationState.anonymous);
  });
  group('WebSessionVerifier.usernameFromInitialState', () {
    test('reads the server-rendered logged-in username', () {
      const html =
          '<script>window.__INITIAL_STATE__ = JSON.parse("{\\"@@publicSession\\":{\\"isLoggedIn\\":true,\\"user\\":{\\"username\\":\\"artist\\"}}}");</script>';

      expect(WebSessionVerifier.usernameFromInitialState(html), 'artist');
    });

    test('treats anonymous as unavailable', () {
      const html =
          '<script>window.__INITIAL_STATE__ = JSON.parse("{\\"@@publicSession\\":{\\"isLoggedIn\\":false,\\"user\\":{\\"username\\":\\"anonymous\\"}}}");</script>';

      expect(WebSessionVerifier.usernameFromInitialState(html), '');
    });

    test('returns empty when the state marker is missing', () {
      expect(WebSessionVerifier.usernameFromInitialState('<html/>'), '');
    });
  });

  test(
    'verify treats a WAF/network answer as unavailable, not anonymous',
    () async {
      final dio = Dio()..httpClientAdapter = _StatusAdapter(202);
      final result = await WebSessionVerifier(dio)
          .verify(cookieHeader: 'userinfo=saved');

      expect(result.state, WebSessionVerificationState.unavailable);
      expect(result.isAnonymous, isFalse);
    },
  );
}
