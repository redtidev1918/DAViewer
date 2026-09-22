import 'dart:typed_data';

import 'package:daviewer/core/auth/web_session_verifier.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

final class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.status);

  final int status;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    'challenge',
    status,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>['text/html'],
    },
  );
}

void main() {
  group('WebSessionVerifier.usernameFromInitialState', () {
    test('reads the server-rendered logged-in username', () {
      const html =
          '<script>window.__INITIAL_STATE__ = JSON.parse("{\\"@publicSession\\":{\\"user\\":{\\"username\\":\\"artist\\"}}}");</script>';

      expect(WebSessionVerifier.usernameFromInitialState(html), 'artist');
    });

    test('treats anonymous as unavailable', () {
      const html =
          '<script>window.__INITIAL_STATE__ = JSON.parse("{\\"@publicSession\\":{\\"user\\":{\\"username\\":\\"anonymous\\"}}}");</script>';

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
