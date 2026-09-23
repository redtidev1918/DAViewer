import 'package:daviewer/core/auth/web_session_refresher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('webSessionProbeResultFromPage', () {
    test('a rendered username is confirmed', () {
      final result = webSessionProbeResultFromPage(
        pageUsername: 'artist',
        csrf: 'token',
      );
      expect(result.outcome, WebSessionProbeOutcome.confirmed);
      expect(result.username, 'artist');
      expect(result.succeeded, isTrue);
    });

    test('the page explicitly reporting anonymous is anonymous', () {
      final result = webSessionProbeResultFromPage(
        pageUsername: 'anonymous',
        csrf: 'token',
      );
      expect(result.outcome, WebSessionProbeOutcome.anonymous);
      expect(result.succeeded, isFalse);
    });

    test('a missing username field is unavailable, never anonymous', () {
      // `__INITIAL_STATE__` missing, `@publicSession` missing, WAF/challenge
      // page, incomplete load: none of these prove the user logged out.
      for (final pageUsername in <String?>[null, '']) {
        final result = webSessionProbeResultFromPage(
          pageUsername: pageUsername,
          csrf: 'token',
        );
        expect(result.outcome, WebSessionProbeOutcome.unavailable);
        expect(result.csrf, 'token');
        expect(result.succeeded, isFalse);
      }
    });

    test('a page without CSRF is unavailable regardless of username', () {
      final result = webSessionProbeResultFromPage(
        pageUsername: 'artist',
        csrf: '',
      );
      expect(result.outcome, WebSessionProbeOutcome.unavailable);
    });
  });
}
