import 'dart:io';
import 'dart:async';

import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native support-directory exception falls back without blocking startup',
    () async {
      AppLogger.resetForTest();
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(code: 'unavailable'),
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final logger = await AppLogger.initialize();
      logger.info('app', 'startup continues');
      await logger.flush();
      expect(AppLogger.isInitialized, isTrue);
      await logger.dispose();
    },
  );

  testWidgets(
    'hung native support-directory lookup cannot block startup forever',
    (tester) async {
      AppLogger.resetForTest();
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final never = Completer<String?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) => never.future);
      final initializing = AppLogger.initialize();
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      final logger = await initializing;
      expect(AppLogger.isInitialized, isTrue);
      logger.info('app', 'startup continues after timeout');
      await logger.flush();
      await logger.dispose();
      never.complete(null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );

  test(
    'failed file open does not poison callbacks, flush or disposal',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'daviewer-logger-',
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => directory.path);
      // Opening a directory as a file fails asynchronously in the real IOSink.
      await Directory('${directory.path}/logs/unwritable.log')
          .create(recursive: true);
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      });
      final logger = await AppLogger.initialize(fileName: 'unwritable.log');
      logger.info('oauthLaunch', 'authorize dispatched');
      await logger.flush();
      logger.info('oauthCallback', 'callback consumed');
      await logger.flush();
      await logger.dispose();
      expect(AppLogger.isInitialized, isFalse);
    },
  );

  test('concurrent disposal drains writes and allows a new logger', () async {
    final directory = await Directory.systemTemp.createTemp('daviewer-logger-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    });
    final logger = await AppLogger.initialize(fileName: 'closing.log');
    logger.info('oauthCallback', 'queued before close');
    await Future.wait([logger.dispose(), logger.dispose()]);
    logger.info('oauthCallback', 'late callback after close');
    await logger.flush();
    final text = await File('${directory.path}/logs/closing.log')
        .readAsString();
    expect(text, contains('queued before close'));
    expect(text, isNot(contains('late callback after close')));
    final replacement = await AppLogger.initialize(fileName: 'replacement.log');
    expect(replacement, isNot(same(logger)));
    await replacement.dispose();
  });

  test(
    'logging during an in-flight flush never aborts a login callback',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'daviewer-logger-',
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => directory.path);
      final logger = await AppLogger.initialize(fileName: 'race.log');
      addTearDown(() async {
        await logger.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      });

      logger.info('oauthLaunch', 'transaction created');
      // Let the scheduled flush bind IOSink before the next platform callback.
      await Future<void>.delayed(Duration.zero);
      logger.info('webview', 'controller created');
      var callbackCompleted = false;
      for (var i = 0; i < 100; i++) {
        logger.info('webview', 'event=$i');
        await Future<void>.delayed(Duration.zero);
      }
      callbackCompleted = true;
      await logger.flush();
      final text = await File('${logger.logsDirectory}/race.log')
          .readAsString();
      expect(callbackCompleted, isTrue);
      expect(text, contains('controller created'));
      for (var i = 0; i < 100; i++) {
        expect(text, contains('event=$i\n'));
      }
    },
  );
}
