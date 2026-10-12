import 'dart:async';

import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:daviewer/app/router.dart';
import 'package:daviewer/core/auth/auth_controller.dart';
import 'package:daviewer/core/auth/auth_state.dart';
import 'package:daviewer/core/auth/web_session_status.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:daviewer/features/splash/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

final _transfers = BackgroundTransferManager();

void main() {
  for (final mode in [
    'pending',
    'cycle',
    'error',
    'success',
    'actual_router',
  ]) {
    testWidgets(
      'startup $mode releases routing without changing unknown identity',
      (tester) async {
        final pending = Completer<void>();
        final readyChanges = <bool>[];
        var starts = 0;
        late final ProviderContainer container;
        container = ProviderContainer(
          overrides: [
            runtimeProvider.overrideWithValue(
              AppRuntime(
                clientId: '',
                oauth: null,
                transport: null,
                transfers: _transfers,
              ),
            ),
            startupRestoreProvider.overrideWithValue(() async {
              starts++;
              if (mode == 'error') {
                throw StateError('synthetic restore failure');
              }
              if (mode == 'pending' || mode == 'actual_router') {
                await pending.future;
              }
              if (mode == 'cycle') {
                // Account/Cookie bootstrap waits for readiness, which waits for it.
                while (!container.read(webSessionReadyProvider)) {
                  await Future<void>.delayed(const Duration(milliseconds: 100));
                }
              }
            }),
          ],
        );
        final revision = ValueNotifier<int>(0);
        final subscription = container.listen(webSessionReadyProvider, (
          _,
          next,
        ) {
          readyChanges.add(next);
          revision.value++;
        });
        final router = mode == 'actual_router'
            ? container.read(routerProvider)
            : GoRouter(
                initialLocation: '/splash',
                refreshListenable: revision,
                redirect: (_, state) => authRedirect(
                  container.read(authControllerProvider).status,
                  state.matchedLocation,
                  startupReady: container.read(webSessionReadyProvider),
                ),
                routes: [
                  GoRoute(
                    path: '/splash',
                    builder: (_, _) => const SplashScreen(),
                  ),
                  GoRoute(
                    path: '/',
                    builder: (_, _) => const Text('home-ready'),
                  ),
                  GoRoute(
                    path: '/settings/diagnostics',
                    builder: (_, _) => const Text('diagnostics-ready'),
                  ),
                ],
              );
        addTearDown(() {
          subscription.close();
          if (mode != 'actual_router') router.dispose();
          revision.dispose();
          container.dispose();
        });
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pump();
        if (mode == 'pending' || mode == 'cycle' || mode == 'actual_router') {
          expect(container.read(webSessionReadyProvider), isFalse);
          await tester.pump(const Duration(seconds: 12));
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
        expect(router.routeInformationProvider.value.uri.path, '/');
        expect(find.byType(SplashScreen), findsNothing);
        expect(
          container.read(authControllerProvider).status,
          AuthStatus.unknown,
        );
        expect(readyChanges, [true]);
        expect(starts, 1);
        router.go('/settings/diagnostics');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          router.routeInformationProvider.value.uri.path,
          '/settings/diagnostics',
        );
        expect(find.byType(SplashScreen), findsNothing);
        if (!pending.isCompleted) pending.complete();
        await tester.pump(const Duration(milliseconds: 200));
        expect(readyChanges, [true]);
        expect(starts, 1);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
