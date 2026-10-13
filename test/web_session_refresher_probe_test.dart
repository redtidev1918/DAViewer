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

    test('rendered identity remains confirmed without CSRF', () {
      final result = webSessionProbeResultFromPage(
        pageUsername: 'artist',
        csrf: '',
      );
      expect(result.outcome, WebSessionProbeOutcome.confirmed);
    });
    test('explicit anonymous identity requires login even without CSRF', () {
      final result = webSessionProbeResultFromPage(
        pageUsername: 'anonymous',
        csrf: '',
      );
      expect(result.outcome, WebSessionProbeOutcome.anonymous);
    });
  });

  group('webSessionProbeSampleDecision (anonymous corroboration, RC2)', () {
    test('a first anonymous sample arms a corroborating reload', () {
      expect(
        webSessionProbeSampleDecision(
          webSessionProbeResultFromPage(pageUsername: 'anonymous', csrf: 't'),
          corroborationPending: false,
        ),
        WebSessionProbeSampleDecision.corroborateAnonymous,
      );
    });

    test('an anonymous sample surviving the reload completes the probe', () {
      expect(
        webSessionProbeSampleDecision(
          webSessionProbeResultFromPage(pageUsername: 'anonymous', csrf: 't'),
          corroborationPending: true,
        ),
        WebSessionProbeSampleDecision.complete,
      );
    });

    test('a confirmed sample completes immediately, even mid-corroboration', () {
      // The reload after a first anonymous sample lands signed-in: the session
      // is alive, so the probe must not wait for anything else (invariant 2).
      for (final pending in <bool>[false, true]) {
        expect(
          webSessionProbeSampleDecision(
            webSessionProbeResultFromPage(pageUsername: 'artist', csrf: 't'),
            corroborationPending: pending,
          ),
          WebSessionProbeSampleDecision.complete,
        );
      }
    });

    test('a redirect intermediate state cannot log out on one sample', () {
      // Sequence: anonymous (redirect shell) -> confirmed (settled page).
      // The decision reducer must never complete anonymous from sample one.
      var pending = false;
      final first = webSessionProbeSampleDecision(
        webSessionProbeResultFromPage(pageUsername: 'anonymous', csrf: 't'),
        corroborationPending: pending,
      );
      expect(first, WebSessionProbeSampleDecision.corroborateAnonymous);
      pending = true; // the refresher arms the reload after that decision
      final second = webSessionProbeSampleDecision(
        webSessionProbeResultFromPage(pageUsername: 'artist', csrf: 't'),
        corroborationPending: pending,
      );
      expect(second, WebSessionProbeSampleDecision.complete);
    });
  });
}
