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
          evidenceNavigation: 0,
          armedNavigation: 0,
        ),
        WebSessionProbeSampleDecision.corroborateAnonymous,
      );
    });

    test(
      'an anonymous sample surviving a new navigation completes the probe',
      () {
        expect(
          webSessionProbeSampleDecision(
            webSessionProbeResultFromPage(pageUsername: 'anonymous', csrf: 't'),
            corroborationPending: true,
            evidenceNavigation: 3,
            armedNavigation: 1,
          ),
          WebSessionProbeSampleDecision.complete,
        );
      },
    );

    test('an anonymous sample before the reload lands does not complete (review 2026-10-14)', () {
      // corroborationPending=true only says a reload was *requested*; it
      // proves nothing about the new page. A second anonymous sample read
      // under the same navigation sequence (or a lower one) is the stale
      // document re-read — e.g. its dedup key changed because the CSRF
      // rotated. The transaction must keep waiting; its deadline resolves
      // unavailable, never anonymous.
      expect(
        webSessionProbeSampleDecision(
          webSessionProbeResultFromPage(pageUsername: 'anonymous', csrf: 't'),
          corroborationPending: true,
          evidenceNavigation: 1,
          armedNavigation: 1,
        ),
        WebSessionProbeSampleDecision.wait,
      );
      expect(
        webSessionProbeSampleDecision(
          webSessionProbeResultFromPage(pageUsername: 'anonymous', csrf: 't'),
          corroborationPending: true,
          evidenceNavigation: 0,
          armedNavigation: 1,
        ),
        WebSessionProbeSampleDecision.wait,
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
            evidenceNavigation: 0,
            armedNavigation: 0,
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
        evidenceNavigation: 0,
        armedNavigation: 0,
      );
      expect(first, WebSessionProbeSampleDecision.corroborateAnonymous);
      pending = true; // the refresher arms the reload after that decision
      final second = webSessionProbeSampleDecision(
        webSessionProbeResultFromPage(pageUsername: 'artist', csrf: 't'),
        corroborationPending: pending,
        evidenceNavigation: 2,
        armedNavigation: 0,
      );
      expect(second, WebSessionProbeSampleDecision.complete);
    });
  });
}
