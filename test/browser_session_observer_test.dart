import 'dart:async';
import 'dart:convert';

import 'package:daviewer/core/auth/browser_session_observer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'missing, malformed and foreign-origin data cannot confirm identity',
    () {
      for (final raw in [
        null,
        '',
        '{}',
        'broken',
        jsonEncode({'origin': 'https://untrusted.test', 'username': 'artist'}),
      ]) {
        final evidence = BrowserSessionEvidence.decode(raw);
        expect(evidence.hasIdentity, isFalse);
        expect(evidence.parseFailed, isTrue);
      }
    },
  );

  test('CSRF alone is pending; anonymous needs an explicit page identity', () {
    final pending = BrowserSessionEvidence.decode(
      jsonEncode({
        'origin': 'https://www.deviantart.com',
        'csrf': 'token',
        'initialized': true,
      }),
    );
    expect(pending.classification, 'identity_pending');
    expect(pending.hasIdentity, isFalse);
    final anonymous = BrowserSessionEvidence.decode(
      jsonEncode({
        'origin': 'https://www.deviantart.com',
        'username': 'anonymous',
      }),
    );
    expect(anonymous.classification, 'explicit_anonymous');
  });

  for (final initialCsrf in ['', 'token']) {
    testWidgets(
      'asynchronous identity appears without another load stop csrf=$initialCsrf',
      (tester) async {
        var current = BrowserSessionEvidence(csrf: initialCsrf);
        final observations = <BrowserSessionEvidence>[];
        final observer = BrowserSessionObserver(
          read: () async => current,
          onEvidence: observations.add,
          onDeadline: () {},
        )..start();
        await tester.pump();
        expect(observations.single.hasIdentity, isFalse);
        current = const BrowserSessionEvidence(
          username: 'artist',
          csrf: 'rotated',
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(observations.last.username, 'artist');
        observer.dispose();
      },
    );
  }

  testWidgets(
    'many challenge navigations do not end early or extend the budget',
    (tester) async {
      var current = const BrowserSessionEvidence(challenge: true);
      final observations = <BrowserSessionEvidence>[];
      var expired = false;
      final observer = BrowserSessionObserver(
        read: () async => current,
        onEvidence: observations.add,
        onDeadline: () => expired = true,
      )..start();
      for (var i = 0; i < 5; i++) {
        observer.navigationStarted();
        await tester.pump(const Duration(seconds: 1));
        expect(expired, isFalse);
      }
      current = const BrowserSessionEvidence(username: 'artist');
      observer.navigationStarted(); // SPA event, no load stop
      await observer.sample();
      expect(observations.last.username, 'artist');
      await tester.pump(const Duration(seconds: 15));
      expect(expired, isTrue);
      final count = observations.length;
      await tester.pump(const Duration(seconds: 5));
      expect(observations.length, count);
    },
  );

  testWidgets('late navigation reads and disposed callbacks are ignored', (
    tester,
  ) async {
    final read = Completer<BrowserSessionEvidence>();
    var calls = 0;
    final observer = BrowserSessionObserver(
      read: () => read.future,
      onEvidence: (_) => calls++,
      onDeadline: () => fail('disposed deadline'),
    )..start();
    observer.navigationStarted();
    read.complete(const BrowserSessionEvidence(username: 'old-account'));
    await tester.pump();
    expect(calls, 0);
    observer.dispose();
    await tester.pump(const Duration(seconds: 25));
    expect(calls, 0);
  });

  testWidgets(
    'duplicate events join one read and unchanged samples are deduplicated',
    (tester) async {
      var reads = 0;
      var reports = 0;
      final gate = Completer<BrowserSessionEvidence>();
      final observer = BrowserSessionObserver(
        read: () {
          reads++;
          return gate.future;
        },
        onEvidence: (_) => reports++,
        onDeadline: () {},
      )..start();
      unawaited(observer.sample());
      unawaited(observer.sample());
      expect(reads, 1);
      gate.complete(const BrowserSessionEvidence(username: 'artist'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(reports, 1);
      observer.dispose();
    },
  );

  testWidgets(
    'visible fallback can reopen a bounded window after user navigation',
    (tester) async {
      var deadlines = 0;
      final observer = BrowserSessionObserver(
        read: () async => const BrowserSessionEvidence(),
        onEvidence: (_) {},
        onDeadline: () => deadlines++,
      )..start();
      await tester.pump(const Duration(seconds: 21));
      expect(observer.isDisposed, isTrue);
      observer.restart();
      await tester.pump(const Duration(seconds: 21));
      expect(deadlines, 2);
      observer.dispose();
    },
  );
}
