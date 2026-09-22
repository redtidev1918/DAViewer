import 'package:daviewer/app/router.dart';
import 'package:daviewer/core/auth/auth_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first-run signed-out state opens login instead of Home', () {
    expect(authRedirect(AuthStatus.signedOut, '/splash'), '/web-login');
  });

  test('unknown auth stays on splash until the startup budget is ready', () {
    expect(authRedirect(AuthStatus.unknown, '/splash'), '/splash');
    expect(
      authRedirect(AuthStatus.unknown, '/splash', startupReady: true),
      '/',
    );
  });

  test('restored session leaves splash for Home', () {
    expect(authRedirect(AuthStatus.signedIn, '/splash'), '/');
  });

  test(
    'a signed-in user may open the login WebView to restore the web session',
    () {
      // The WebLoginScreen establishes the web Cookie/CSRF session as well as
      // OAuth, and closes itself after both are reported. The router must not
      // bounce it away first, or the personalized feed never gets its session.
      expect(authRedirect(AuthStatus.signedIn, '/web-login'), isNull);
    },
  );

  test(
    'settings, updates and diagnostics remain available while signed out',
    () {
      expect(authRedirect(AuthStatus.signedOut, '/history'), isNull);
      expect(authRedirect(AuthStatus.signedOut, '/settings'), isNull);
      expect(authRedirect(AuthStatus.signedOut, '/settings/proxy'), isNull);
      expect(
        authRedirect(AuthStatus.signedOut, '/settings/diagnostics'),
        isNull,
      );
    },
  );

  test('explicit logout returns account routes to public Home', () {
    expect(authRedirect(AuthStatus.signedOut, '/favourites'), '/');
    expect(authRedirect(AuthStatus.signedOut, '/web-login'), isNull);
  });
}
