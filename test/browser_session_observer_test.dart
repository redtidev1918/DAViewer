import 'dart:async';
import 'dart:convert';

import 'package:daviewer/core/auth/browser_session_observer.dart';
import 'package:daviewer/core/auth/web_session_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('current document initializer can confirm identity after the global disappears', () async {
    final state = jsonEncode({
      '@@publicSession': {
        'isLoggedIn': true,
        'user': {'username': 'artist'},
      },
    });
    final evidence = await readBrowserSessionEvidence(
      getUrl: () async => Uri.parse('https://www.deviantart.com/'),
      evaluate: () async => jsonEncode({
        'origin': 'https://www.deviantart.com',
        'csrf': 'synthetic',
      }),
      getHtml: () async =>
          'window.__INITIAL_STATE__ = JSON.parse(${jsonEncode(state)});',
    );
    expect(evidence.username, 'artist');
    expect(evidence.identitySource, 'document_initial_state');
  });
  test(
    'CSRF with no global or document identity remains inconclusive',
    () async {
      final evidence = await readBrowserSessionEvidence(
        getUrl: () async => Uri.parse('https://www.deviantart.com/'),
        evaluate: () async => jsonEncode({
          'origin': 'https://www.deviantart.com',
          'csrf': 'synthetic',
        }),
        getHtml: () async => '<html>artist public profile</html>',
      );
      expect(evidence.hasIdentity, isFalse);
      expect(evidence.classification, 'page_uninitialized');
    },
  );
  test(
    'document evidence is rejected if navigation changed while reading',
    () async {
      var reads = 0;
      final state = jsonEncode({
        '@@publicSession': {
          'isLoggedIn': true,
          'user': {'username': 'artist'},
        },
      });
      final evidence = await readBrowserSessionEvidence(
        getUrl: () async => Uri.parse(
          'https://www.deviantart.com/${reads++ == 0 ? '' : 'users/login'}',
        ),
        evaluate: () async => jsonEncode({
          'origin': 'https://www.deviantart.com',
          'csrf': 'synthetic',
        }),
        getHtml: () async =>
            'window.__INITIAL_STATE__ = JSON.parse(${jsonEncode(state)});',
      );
      expect(evidence.hasIdentity, isFalse);
    },
  );
  group('production page shape (regression: key is @@publicSession)', () {
    // Mirrors the real anonymous home page fetched 2026-10-13:
    // "window.__INITIAL_STATE__ = JSON.parse(\"{\\\"@@publicSession\\\":
    // {\\\"isLoggedIn\\\":false,...,\\\"user\\\":{...,\\\"username\\\":\\\"anonymous\\\"}}}\")"
    test('real anonymous page reports explicit anonymous', () {
      final evidence = BrowserSessionEvidence.decode(
        jsonEncode({
          'origin': 'https://www.deviantart.com',
          'csrf': 'token',
          'username': 'anonymous',
          'loggedIn': false,
          'initialized': true,
        }),
      );
      expect(evidence.classification, 'explicit_anonymous');
      expect(evidence.parseFailed, isFalse);
    });
    test('isLoggedIn=false without a username is still explicit anonymous', () {
      final evidence = BrowserSessionEvidence.decode(
        jsonEncode({
          'origin': 'https://www.deviantart.com',
          'csrf': 'token',
          'username': null,
          'loggedIn': false,
          'initialized': true,
        }),
      );
      expect(evidence.classification, 'explicit_anonymous');
    });
    test(
      'isLoggedIn=true without a username stays unverified, not healthy',
      () {
        final evidence = BrowserSessionEvidence.decode(
          jsonEncode({
            'origin': 'https://www.deviantart.com',
            'csrf': 'token',
            'username': null,
            'loggedIn': true,
            'initialized': true,
          }),
        );
        expect(evidence.classification, 'identity_pending');
        expect(evidence.hasIdentity, isFalse);
      },
    );
    test('legacy single-@ spelling still confirms identity', () {
      final evidence = BrowserSessionEvidence.decode(
        jsonEncode({
          'origin': 'https://www.deviantart.com',
          'csrf': 'token',
          'username': 'artist',
          'loggedIn': true,
          'initialized': true,
        }),
      );
      expect(evidence.classification, 'verified_identity');
    });
    test('document fallback parses the production escaped anonymous page', () async {
      const productionHtml =
          r'''<script>window.__INITIAL_STATE__ = JSON.parse("{\"@@publicSession\":{\"isLoggedIn\":false,\"csrfToken\":\"tok\",\"user\":{\"username\":\"anonymous\"}}}");</script>''';
      expect(
        WebSessionVerifier.pageUsernameFromInitialState(productionHtml),
        'anonymous',
      );
      final evidence = await readBrowserSessionEvidence(
        getUrl: () async => Uri.parse('https://www.deviantart.com/'),
        evaluate: () async => jsonEncode({
          'origin': 'https://www.deviantart.com',
          'csrf': 'synthetic',
        }),
        getHtml: () async => productionHtml,
      );
      expect(evidence.username, 'anonymous');
      expect(evidence.identitySource, 'document_initial_state');
    });
  });
  testWidgets('full navigation cannot confirm the previous document', (
    tester,
  ) async {
    var reads = 0;
    final observations = <BrowserSessionEvidence>[];
    final observer = BrowserSessionObserver(
      read: () async {
        reads++;
        return const BrowserSessionEvidence(username: 'artist');
      },
      onEvidence: (evidence, _) => observations.add(evidence),
      onDeadline: () {},
    );
    observer.navigationStarted(loading: true);
    observer.start();
    await tester.pump(const Duration(seconds: 2));
    observer.navigationStarted(); // history may fire before full load commit
    await observer.sample();
    expect(reads, 0);
    expect(observations, isEmpty);
    observer.navigationCommitted();
    await observer.sample();
    expect(observations.single.username, 'artist');
    observer.dispose();
  });
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
          onEvidence: (evidence, _) => observations.add(evidence),
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
        onEvidence: (evidence, _) => observations.add(evidence),
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
      onEvidence: (_, _) => calls++,
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
        onEvidence: (_, _) => reports++,
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
        onEvidence: (_, _) {},
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

  testWidgets(
    'evidence carries the navigation sequence it was read under (review 2026-10-14)',
    (tester) async {
      // Corroboration must bind to a NEW navigation, so the observer has to
      // tell its consumer which navigation epoch each sample belongs to: the
      // sequence only advances when a real navigation event fires.
      final reads = <Completer<BrowserSessionEvidence>>[];
      final delivered = <int>[];
      final observer = BrowserSessionObserver(
        read: () {
          final completer = Completer<BrowserSessionEvidence>();
          reads.add(completer);
          return completer.future;
        },
        onEvidence: (_, navigationSequence) =>
            delivered.add(navigationSequence),
        onDeadline: () {},
      )..start();

      await tester.pump();
      expect(reads, hasLength(1));
      reads[0].complete(const BrowserSessionEvidence(username: 'anonymous'));
      await tester.pump();
      expect(delivered, [0]);

      // No navigation yet: a re-read of the same document (dedup reset by a
      // CSRF rotation) still reports the same sequence.
      observer.navigationStarted();
      observer.navigationCommitted();
      await tester.pump(const Duration(milliseconds: 500));
      expect(reads, hasLength(2));
      reads[1].complete(const BrowserSessionEvidence(username: 'anonymous'));
      await tester.pump();
      expect(delivered, [0, 2]);
      observer.dispose();
    },
  );
}
