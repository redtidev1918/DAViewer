import 'package:daviewer/core/auth/web_session_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
