import 'dart:io';

import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:daviewer/core/auth/auth_controller.dart';
import 'package:daviewer/core/auth/auth_state.dart';
import 'package:daviewer/core/auth/login_observation.dart';
import 'package:daviewer/core/auth/web_session_status.dart';
import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:daviewer/features/settings/login_status_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // BackgroundTransferManager listens to a singleton stream in its
  // constructor, so only one instance may exist per test process.
  late AppRuntime runtime;
  late Directory directory;
  late LoginHistoryStore historyStore;
  late ProviderContainer container;
  setUpAll(() {
    runtime = AppRuntime(
      clientId: '',
      oauth: null,
      transport: null,
      transfers: BackgroundTransferManager(diagnostics: AppLogger.instance),
    );
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'daviewer-login-status-test-',
    );
    historyStore = LoginHistoryStore(directory: () async => directory);
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        runtimeProvider.overrideWithValue(runtime),
        loginHistoryStoreProvider.overrideWithValue(historyStore),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    // Settle queued observation writes before Windows deletes the directory.
    await historyStore.flush();
    await directory.delete(recursive: true);
  });

  Future<void> pumpScreen(WidgetTester tester) => tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: LoginStatusScreen()),
    ),
  );

  testWidgets(
    'channels stay independent: web success with storage failure, API untouched',
    (tester) async {
      await pumpScreen(tester);
      expect(find.text('网页登录'), findsOneWidget);
      expect(find.text('官方 API 登录'), findsOneWidget);
      expect(find.text('尚未验证'), findsNWidgets(2));

      final web = container.read(
        loginObservationProvider(LoginChannel.web).notifier,
      );
      web.begin('artist');
      await tester.pump();
      expect(find.text('正在检查…'), findsOneWidget);
      // The website check action is disabled while its own check runs.
      final buttons = find.byType(OutlinedButton);
      expect(tester.widget<OutlinedButton>(buttons.at(0)).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(buttons.at(1)).onPressed, isNotNull);

      web.finish(LoginCheckResult.authenticated);
      web.storage(save: LoginStorageResult.failed, reason: 'write_failed');
      await tester.pump();
      expect(find.text('已验证登录'), findsOneWidget);
      expect(find.text('登录状态保存或恢复异常；即使当前会话可用，下次启动仍可能需要重新登录。'), findsOneWidget);
      // The API card keeps its own untouched verdict.
      expect(find.text('尚未验证'), findsOneWidget);
    },
  );

  testWidgets('challenge lock shows restricted state and blocks manual check', (
    tester,
  ) async {
    await pumpScreen(tester);
    container.read(webSessionStatusProvider.notifier).markLocked();
    await tester.pump();
    expect(find.text('网页验证受限'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byType(OutlinedButton).at(0))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byType(OutlinedButton).at(1))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('signed-out API auth never rewrites the website verdict', (
    tester,
  ) async {
    await pumpScreen(tester);
    final web = container.read(
      loginObservationProvider(LoginChannel.web).notifier,
    );
    web.begin('artist');
    web.finish(LoginCheckResult.authenticated);
    container.read(authControllerProvider.notifier).state = const AuthState(
      status: AuthStatus.signedOut,
    );
    await tester.pump();
    expect(find.text('未登录或需要重新登录'), findsOneWidget);
    expect(find.text('已验证登录'), findsOneWidget);
  });

  testWidgets('raw failure details never surface in the UI', (tester) async {
    await pumpScreen(tester);
    final web = container.read(
      loginObservationProvider(LoginChannel.web).notifier,
    );
    web.begin('artist');
    web.finish(LoginCheckResult.unauthenticated, reason: 'Cookie: userinfo=x');
    web.storage(save: LoginStorageResult.failed, reason: 'Bearer secret');
    await tester.pump();
    expect(find.textContaining('secret'), findsNothing);
    expect(find.textContaining('userinfo'), findsNothing);
    expect(find.textContaining('Bearer'), findsNothing);
    expect(find.text('未登录或需要重新登录'), findsOneWidget);
  });
}
