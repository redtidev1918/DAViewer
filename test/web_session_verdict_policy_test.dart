import 'package:daviewer/core/auth/web_session_refresher.dart';
import 'package:daviewer/core/auth/web_session_verdict.dart';
import 'package:daviewer/core/auth/web_session_status.dart';
import 'package:flutter_test/flutter_test.dart';

WebSessionEvidence evidence(
  WebSessionEvidenceSource source,
  WebSessionProbeOutcome outcome, {
  String username = '',
  int generation = 1,
}) => WebSessionEvidence(
  source: source,
  outcome: outcome,
  username: username,
  generation: generation,
);

void main() {
  group('resolveWebSessionVerdict matrix', () {
    test('bare confirmed matching claim is healthy', () {
      final decision = resolveWebSessionVerdict(
        current: WebSessionStatusState.unknown,
        evidence: evidence(
          WebSessionEvidenceSource.bareProbe,
          WebSessionProbeOutcome.confirmed,
          username: 'artist',
        ),
        claimedUsername: 'artist',
        claimedSignedIn: true,
      );
      expect(decision.nextState, WebSessionStatusState.healthy);
      expect(decision.serverUsername, 'artist');
    });

    test('bare confirmed with a different claim is anonymous', () {
      final decision = resolveWebSessionVerdict(
        current: WebSessionStatusState.healthy,
        evidence: evidence(
          WebSessionEvidenceSource.bareProbe,
          WebSessionProbeOutcome.confirmed,
          username: 'someone-else',
        ),
        claimedUsername: 'artist',
        claimedSignedIn: true,
      );
      expect(decision.nextState, WebSessionStatusState.anonymous);
    });

    test(
      'bare anonymous with a claimed session escalates, never anonymous',
      () {
        final decision = resolveWebSessionVerdict(
          current: WebSessionStatusState.healthy,
          evidence: evidence(
            WebSessionEvidenceSource.bareProbe,
            WebSessionProbeOutcome.anonymous,
          ),
          claimedUsername: 'artist',
          claimedSignedIn: true,
        );
        expect(decision.escalateToRealBrowser, isTrue);
        expect(decision.nextState, isNull);
      },
    );

    test('bare anonymous without a claimed session is anonymous', () {
      final decision = resolveWebSessionVerdict(
        current: WebSessionStatusState.unknown,
        evidence: evidence(
          WebSessionEvidenceSource.bareProbe,
          WebSessionProbeOutcome.anonymous,
        ),
        claimedUsername: '',
        claimedSignedIn: false,
      );
      expect(decision.nextState, WebSessionStatusState.anonymous);
    });

    test('real browser confirmed matching claim is healthy', () {
      final decision = resolveWebSessionVerdict(
        current: WebSessionStatusState.healthy,
        evidence: evidence(
          WebSessionEvidenceSource.realBrowserProbe,
          WebSessionProbeOutcome.confirmed,
          username: 'artist',
        ),
        claimedUsername: 'artist',
        claimedSignedIn: true,
      );
      expect(decision.nextState, WebSessionStatusState.healthy);
    });

    test('real browser anonymous is authoritative', () {
      final decision = resolveWebSessionVerdict(
        current: WebSessionStatusState.healthy,
        evidence: evidence(
          WebSessionEvidenceSource.realBrowserProbe,
          WebSessionProbeOutcome.anonymous,
        ),
        claimedUsername: 'artist',
        claimedSignedIn: true,
      );
      expect(decision.nextState, WebSessionStatusState.anonymous);
    });

    test('real browser unavailable is unverified, never logged out', () {
      final decision = resolveWebSessionVerdict(
        current: WebSessionStatusState.healthy,
        evidence: evidence(
          WebSessionEvidenceSource.realBrowserProbe,
          WebSessionProbeOutcome.unavailable,
        ),
        claimedUsername: 'artist',
        claimedSignedIn: true,
      );
      expect(decision.nextState, WebSessionStatusState.unverified);
    });

    test('unverified + real browser confirmed recovers to healthy', () {
      final decision = resolveWebSessionVerdict(
        current: WebSessionStatusState.unverified,
        evidence: evidence(
          WebSessionEvidenceSource.realBrowserProbe,
          WebSessionProbeOutcome.confirmed,
          username: 'artist',
        ),
        claimedUsername: 'artist',
        claimedSignedIn: true,
      );
      expect(decision.nextState, WebSessionStatusState.healthy);
    });

    test('unverified + real browser anonymous is anonymous', () {
      final decision = resolveWebSessionVerdict(
        current: WebSessionStatusState.unverified,
        evidence: evidence(
          WebSessionEvidenceSource.realBrowserProbe,
          WebSessionProbeOutcome.anonymous,
        ),
        claimedUsername: 'artist',
        claimedSignedIn: true,
      );
      expect(decision.nextState, WebSessionStatusState.anonymous);
    });

    test('web login confirmed is healthy regardless of prior state', () {
      for (final current in WebSessionStatusState.values) {
        final decision = resolveWebSessionVerdict(
          current: current,
          evidence: evidence(
            WebSessionEvidenceSource.webLogin,
            WebSessionProbeOutcome.confirmed,
            username: 'artist',
          ),
          claimedUsername: 'artist',
          claimedSignedIn: true,
        );
        expect(decision.nextState, WebSessionStatusState.healthy);
      }
    });

    test('local state anonymous (no usable cookies) is anonymous', () {
      final decision = resolveWebSessionVerdict(
        current: WebSessionStatusState.healthy,
        evidence: evidence(
          WebSessionEvidenceSource.localState,
          WebSessionProbeOutcome.anonymous,
        ),
        claimedUsername: 'artist',
        claimedSignedIn: true,
      );
      expect(decision.nextState, WebSessionStatusState.anonymous);
    });
  });
}
