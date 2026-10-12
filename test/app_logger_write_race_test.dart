import 'dart:io';

import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
