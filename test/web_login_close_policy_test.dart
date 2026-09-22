import 'package:daviewer/features/web_login/web_login_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldCloseWebLoginAfterWebSession', () {
    test('closes when a signed-in OAuth session owns the page', () {
      expect(
        shouldCloseWebLoginAfterWebSession(
          serverConfirmedNavigation: true,
          oauthSignedIn: true,
          closeAfterOAuthReport: false,
        ),
        isTrue,
      );
    });

    test('closes when OAuth just finished during this page visit', () {
      expect(
        shouldCloseWebLoginAfterWebSession(
          serverConfirmedNavigation: true,
          oauthSignedIn: false,
          closeAfterOAuthReport: true,
        ),
        isTrue,
      );
    });

    test('waits for OAuth when only the web Cookie was confirmed', () {
      expect(
        shouldCloseWebLoginAfterWebSession(
          serverConfirmedNavigation: true,
          oauthSignedIn: false,
          closeAfterOAuthReport: false,
        ),
        isFalse,
      );
    });

    test('never closes on a page that the server did not confirm as home', () {
      expect(
        shouldCloseWebLoginAfterWebSession(
          serverConfirmedNavigation: false,
          oauthSignedIn: true,
          closeAfterOAuthReport: true,
        ),
        isFalse,
      );
    });
  });
}
