import 'dart:convert';
import 'dart:io';

import 'package:daviewer/core/auth/login_observation.dart';
import 'package:daviewer/core/auth/web_session_status.dart';
import 'package:daviewer/core/l10n/app_strings.dart';
import 'package:daviewer/core/notice/web_session_notice.dart';
import 'package:daviewer/core/settings/app_preferences.dart';
import 'package:daviewer/shared/widgets/app_notice_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Mounts only the notice host: every assertion below is about what the host
/// renders for a verdict, never about a page.
Future<ProviderContainer> pumpHost(WidgetTester tester) async {
  final container = ProviderContainer(retry: (_, _) => null);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: AppNoticeHost())),
    ),
  );
  await tester.pump();
  return container;
}

Future<void> markWebAuthenticated(ProviderContainer container) async {
  container.read(loginObservationProvider(LoginChannel.web).notifier)
    ..begin('artist')
    ..finish(LoginCheckResult.authenticated);
}

void main() {
  testWidgets(
    'a challenge lock asks for verification, never for a fresh login',
    (tester) async {
      final container = await pumpHost(tester);
      final s = strings(container.read(appLanguageProvider));

      container.read(webSessionStatusProvider.notifier).markLocked();
      await tester.pump();

      expect(find.text(s.webLoginChallengeExceeded), findsOneWidget);
      expect(find.text(s.openWebVerificationAction), findsOneWidget);
      // 锁定不要求反复登录, and it never claims the sign-in expired.
      expect(find.text('重新登录'), findsNothing);
      expect(find.text('Sign in again'), findsNothing);
      expect(find.textContaining('已失效'), findsNothing);
      expect(find.text(s.webSessionInvalidated), findsNothing);
    },
  );

  testWidgets('a stale web session is told to sign in again', (tester) async {
    final container = await pumpHost(tester);
    final s = strings(container.read(appLanguageProvider));

    container.read(webSessionStatusProvider.notifier).state =
        const WebSessionStatus(state: WebSessionStatusState.stale);
    await tester.pump();

    expect(find.text(s.webSessionInvalidated), findsOneWidget);
    expect(find.text(s.webSessionReloginAction), findsOneWidget);
    expect(find.text(s.webLoginChallengeExceeded), findsNothing);
  });

  testWidgets('anonymous with prior login evidence is told to sign in again', (
    tester,
  ) async {
    final container = await pumpHost(tester);
    final s = strings(container.read(appLanguageProvider));
    await markWebAuthenticated(container);

    container.read(webSessionStatusProvider.notifier).state =
        const WebSessionStatus(state: WebSessionStatusState.anonymous);
    await tester.pump();

    expect(find.text(s.webSessionInvalidated), findsOneWidget);
    expect(find.text(s.webSessionReloginAction), findsOneWidget);
  });

  testWidgets('anonymous without login history is never called expired', (
    tester,
  ) async {
    final container = await pumpHost(tester);
    final s = strings(container.read(appLanguageProvider));

    container.read(webSessionStatusProvider.notifier).state =
        const WebSessionStatus(state: WebSessionStatusState.anonymous);
    await tester.pump();

    expect(
      container.read(loginObservationProvider(LoginChannel.web)).lastSuccess,
      isNull,
    );
    expect(find.text(s.webSessionInvalidated), findsNothing);
    expect(find.text(s.webSessionReloginAction), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('unknown and transient verdicts never claim an expiry', (
    tester,
  ) async {
    final container = await pumpHost(tester);
    final s = strings(container.read(appLanguageProvider));
    final status = container.read(webSessionStatusProvider.notifier);

    for (final state in const <WebSessionStatusState>[
      WebSessionStatusState.unknown,
      WebSessionStatusState.unverified,
      WebSessionStatusState.unavailable,
    ]) {
      status.state = WebSessionStatus(state: state);
      await tester.pump();
      expect(
        find.text(s.webSessionInvalidated),
        findsNothing,
        reason: 'state ${state.name} must not be shown as an expiry',
      );
      expect(find.text(s.webSessionReloginAction), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
    }
  });

  testWidgets('a dismissed incident stays hidden across a host rebuild', (
    tester,
  ) async {
    final container = await pumpHost(tester);
    final s = strings(container.read(appLanguageProvider));
    await markWebAuthenticated(container);
    container.read(webSessionStatusProvider.notifier).state =
        const WebSessionStatus(state: WebSessionStatusState.stale);
    await tester.pump();
    expect(find.text(s.webSessionInvalidated), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text(s.webSessionInvalidated), findsNothing);

    // A new host instance on another page re-reads the same dismissal.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            key: ValueKey<String>('another-route'),
            body: AppNoticeHost(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(s.webSessionInvalidated), findsNothing);
  });

  testWidgets('an account switch does not inherit the other dismissal', (
    tester,
  ) async {
    final container = await pumpHost(tester);
    final s = strings(container.read(appLanguageProvider));
    final observation = container.read(
      loginObservationProvider(LoginChannel.web).notifier,
    );
    final status = container.read(webSessionStatusProvider.notifier);

    observation
      ..begin('artist')
      ..finish(LoginCheckResult.authenticated);
    status.state = const WebSessionStatus(state: WebSessionStatusState.locked);
    await tester.pump();
    expect(find.text(s.webLoginChallengeExceeded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text(s.webLoginChallengeExceeded), findsNothing);

    // Another account hits its own challenge: same incident word, different
    // account, so its reminder is its own.
    observation
      ..begin('other')
      ..finish(LoginCheckResult.challenge);
    await tester.pump();
    expect(find.text(s.webLoginChallengeExceeded), findsOneWidget);
  });

  testWidgets('recovery opens the next incident on the same channel', (
    tester,
  ) async {
    final container = await pumpHost(tester);
    final s = strings(container.read(appLanguageProvider));
    final status = container.read(webSessionStatusProvider.notifier);
    await markWebAuthenticated(container);

    status.state = const WebSessionStatus(state: WebSessionStatusState.locked);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text(s.webLoginChallengeExceeded), findsNothing);

    status.markHealthy(serverUsername: 'artist');
    await tester.pump();
    status.markLocked();
    await tester.pump();
    expect(find.text(s.webLoginChallengeExceeded), findsOneWidget);
  });

  testWidgets('the API channel prompts while the web channel is healthy', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const AppNoticeHost()),
        GoRoute(
          path: '/web-login',
          builder: (_, _) => const Scaffold(body: Text('Web login')),
        ),
      ],
    );
    addTearDown(router.dispose);
    final container = ProviderContainer(retry: (_, _) => null);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    final s = strings(container.read(appLanguageProvider));

    container
        .read(webSessionStatusProvider.notifier)
        .markHealthy(serverUsername: 'artist');
    final api = container.read(
      loginObservationProvider(LoginChannel.api).notifier,
    );
    api
      ..begin('artist')
      ..finish(LoginCheckResult.authenticated)
      ..finish(LoginCheckResult.unauthenticated, reason: 'unauthenticated');
    await tester.pump();

    // The web channel is healthy, so this card can only be the API incident.
    expect(find.text(s.apiSessionInvalidated), findsOneWidget);
    expect(find.text(s.webSessionInvalidated), findsNothing);
    await tester.tap(find.text(s.apiSessionReauthorizeAction));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/web-login');
  });

  testWidgets('a web incident takes precedence over a simultaneous API one', (
    tester,
  ) async {
    final container = await pumpHost(tester);
    final s = strings(container.read(appLanguageProvider));
    await markWebAuthenticated(container);
    final api = container.read(
      loginObservationProvider(LoginChannel.api).notifier,
    );
    api
      ..begin('artist')
      ..finish(LoginCheckResult.authenticated)
      ..finish(LoginCheckResult.unauthenticated, reason: 'unauthenticated');
    container.read(webSessionStatusProvider.notifier).state =
        const WebSessionStatus(state: WebSessionStatusState.stale);
    await tester.pump();

    expect(find.text(s.webSessionInvalidated), findsOneWidget);
    expect(find.text(s.apiSessionInvalidated), findsNothing);

    // Dismissals are independent: closing the web card leaves the API
    // incident readable instead of silently swallowing it.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text(s.webSessionInvalidated), findsNothing);
    expect(find.text(s.apiSessionInvalidated), findsOneWidget);
  });

  group('persisted dismissals', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('daviewer-notice-');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => directory.path);
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      });
    });

    /// A dismissal is persisted only after the restore has merged, so its write
    /// is queued a microtask later than the call that caused it.
    Future<void> settle(ProviderContainer container) async {
      await container.read(webSessionNoticeDismissalProvider.notifier).restored;
      await pumpEventQueue();
      await AppPreferences.flush();
      await container.read(loginHistoryStoreProvider).flush();
    }

    test(
      'a stored dismissal carries only channel, account and incident',
      () async {
        await AppPreferences.saveDismissedSessionNotices(const <String>[
          'web-session:artist:invalid',
          'api-session:artist:invalid',
          // Unknown shapes are dropped on the way in and on the way out.
          'api-session:artist:locked',
          'web-session:artist:expired',
          'cookie:artist:invalid',
        ]);

        expect(await AppPreferences.loadDismissedSessionNotices(), <String>{
          'web-session:artist:invalid',
          'api-session:artist:invalid',
        });
        final raw = await File(
          '${directory.path}${Platform.pathSeparator}preferences.json',
        ).readAsString();
        expect(raw, isNot(contains('cookie')));
        expect(raw, isNot(contains('token')));
      },
    );

    test('a dismissal survives a restart and recovery clears it', () async {
      final first = ProviderContainer();
      await first.read(webSessionNoticeDismissalProvider.notifier).restored;
      first.read(webSessionNoticeDismissalProvider.notifier)
        ..dismiss('web-session:artist:invalid')
        ..dismiss('api-session:artist:invalid');
      await AppPreferences.flush();
      await settle(first);
      first.dispose();

      // A restart: a fresh container reloads the same file.
      final second = ProviderContainer();
      await second.read(webSessionNoticeDismissalProvider.notifier).restored;
      expect(second.read(webSessionNoticeDismissalProvider), <String>{
        'web-session:artist:invalid',
        'api-session:artist:invalid',
      });

      // Only the recovered web channel forgets its incident.
      second
          .read(webSessionStatusProvider.notifier)
          .markHealthy(serverUsername: 'artist');
      expect(
        second
            .read(webSessionNoticeDismissalProvider)
            .where((id) => id.startsWith('web-session:')),
        isEmpty,
      );
      await AppPreferences.flush();
      await settle(second);
      second.dispose();

      final third = ProviderContainer();
      await third.read(webSessionNoticeDismissalProvider.notifier).restored;
      expect(third.read(webSessionNoticeDismissalProvider), <String>{
        'api-session:artist:invalid',
      });
      await settle(third);
      third.dispose();
    });

    test('another account keeps its own record', () async {
      final first = ProviderContainer();
      await first.read(webSessionNoticeDismissalProvider.notifier).restored;
      first
          .read(webSessionNoticeDismissalProvider.notifier)
          .dismiss('web-session:artist:invalid');
      await settle(first);
      first.dispose();

      // The dismissal really is the artist's record, on disk.
      expect(
        await AppPreferences.loadDismissedSessionNotices(),
        contains('web-session:artist:invalid'),
      );

      final second = ProviderContainer();
      await second.read(webSessionNoticeDismissalProvider.notifier).restored;
      // It is restored for the account that dismissed it ...
      expect(
        second.read(webSessionNoticeDismissalProvider),
        contains('web-session:artist:invalid'),
      );
      // ... while another account's incident is a different id, so that account
      // still gets its own reminder.
      second.read(loginObservationProvider(LoginChannel.web).notifier)
        ..begin('other')
        ..finish(LoginCheckResult.authenticated);
      second.read(webSessionStatusProvider.notifier).state =
          const WebSessionStatus(state: WebSessionStatusState.anonymous);
      final dismissed = second.read(webSessionNoticeDismissalProvider);
      expect(dismissed, contains('web-session:artist:invalid'));
      expect(dismissed, isNot(contains('web-session:other:invalid')));
      expect(
        webSessionNoticeId('other', locked: false),
        'web-session:other:invalid',
      );
      await settle(second);
      second.dispose();
    });

    test('a recovery clears only the account that recovered', () async {
      final first = ProviderContainer();
      await first.read(webSessionNoticeDismissalProvider.notifier).restored;
      final dismissed = first.read(webSessionNoticeDismissalProvider.notifier);
      dismissed.dismiss('web-session:artist:invalid');
      dismissed.dismiss('web-session:other:invalid');
      await settle(first);
      first.dispose();

      // Restart, then the OTHER account's session recovers. A channel-wide
      // clear would delete the artist's dismissal still owed to the user.
      final second = ProviderContainer();
      await second.read(webSessionNoticeDismissalProvider.notifier).restored;
      second.read(loginObservationProvider(LoginChannel.web).notifier)
        ..begin('other')
        ..finish(LoginCheckResult.authenticated);
      second
          .read(webSessionStatusProvider.notifier)
          .markHealthy(serverUsername: 'other');

      final remaining = second.read(webSessionNoticeDismissalProvider);
      expect(
        remaining,
        contains('web-session:artist:invalid'),
        reason: "another account's recovery must not forget artist's incident",
      );
      expect(remaining, isNot(contains('web-session:other:invalid')));
      await settle(second);
      // Nor may it drop the artist's record from disk.
      expect(
        await AppPreferences.loadDismissedSessionNotices(),
        contains('web-session:artist:invalid'),
      );
      second.dispose();
    });

    test('a hand-written file is re-validated on load', () async {
      final file = File(
        '${directory.path}${Platform.pathSeparator}preferences.json',
      );
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'language': 'zh',
          'dismissedSessionNotices': <Object?>[
            'web-session:artist:invalid',
            'web-session:artist:locked',
            'api-session:artist:invalid',
            // Dismissed before any account was known: the id stays
            // account-less instead of widening to the whole channel.
            'web-session::invalid',
            'api-session:artist:locked',
            'web-session:artist:expired',
            'cookie:artist:invalid',
            7,
          ],
        }),
      );
      expect(await AppPreferences.loadDismissedSessionNotices(), <String>{
        'web-session:artist:invalid',
        'web-session:artist:locked',
        'api-session:artist:invalid',
        'web-session::invalid',
      });

      // A non-list value is not a dismissal set.
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'dismissedSessionNotices': 'web-session:artist:invalid',
        }),
      );
      expect(await AppPreferences.loadDismissedSessionNotices(), isEmpty);
    });

    /// The restore is a real file read, so anything done synchronously right
    /// after the provider is first read happens before it merged.
    Future<void> seedPersisted(List<String> ids) async {
      await File('${directory.path}${Platform.pathSeparator}preferences.json')
          .writeAsString(
            jsonEncode(<String, Object?>{'dismissedSessionNotices': ids}),
          );
    }

    test(
      'a dismissal made before the restore does not drop the file',
      () async {
        await seedPersisted(const <String>[
          'web-session:artist:invalid',
          'api-session:artist:invalid',
        ]);

        final container = ProviderContainer();
        container
            .read(webSessionNoticeDismissalProvider.notifier)
            .dismiss('web-session:other:invalid');
        await settle(container);

        expect(await AppPreferences.loadDismissedSessionNotices(), <String>{
          'web-session:artist:invalid',
          'api-session:artist:invalid',
          'web-session:other:invalid',
        });
        container.dispose();
      },
    );

    test(
      'a recovery made before the restore still clears the record',
      () async {
        await seedPersisted(const <String>['web-session:artist:invalid']);

        final container = ProviderContainer();
        // Touch the notifier to start the restore, then recover in the same
        // synchronous turn: the read cannot have completed yet.
        container.read(webSessionNoticeDismissalProvider.notifier);
        container.read(loginObservationProvider(LoginChannel.web).notifier)
          ..begin('artist')
          ..finish(LoginCheckResult.authenticated);
        container
            .read(webSessionStatusProvider.notifier)
            .markHealthy(serverUsername: 'artist');
        expect(container.read(webSessionNoticeDismissalProvider), isEmpty);

        await settle(container);
        // Otherwise the next launch restores a finished incident and silently
        // swallows the next one on that account.
        expect(await AppPreferences.loadDismissedSessionNotices(), isEmpty);
        container.dispose();
      },
    );
  });
}
