import 'package:daviewer/core/auth/auth_controller.dart';
import 'package:daviewer/core/settings/app_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldRestoreOAuthSessionAfterEvidence', () {
    test('a recorded logout prevents token revival', () {
      expect(
        shouldRestoreOAuthSessionAfterEvidence(OAuthSessionEvidence.signedOut),
        isFalse,
      );
    });

    test('missing evidence keeps the legacy restore path', () {
      expect(
        shouldRestoreOAuthSessionAfterEvidence(OAuthSessionEvidence.unknown),
        isTrue,
      );
      expect(
        shouldRestoreOAuthSessionAfterEvidence(OAuthSessionEvidence.signedIn),
        isTrue,
      );
    });
  });
}
