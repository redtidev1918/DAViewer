import 'dart:convert';
import 'dart:io';

import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:daviewer/core/settings/app_preferences.dart';
import 'package:daviewer/core/updates/update_checker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _ReleaseAdapter implements HttpClientAdapter {
  int calls = 0;
  bool fail = false;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromString(
      jsonEncode({'tag_name': 'v0.5.9', 'body': '- Cookie 修复。'}),
      fail ? 503 : 200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transfers = BackgroundTransferManager(diagnostics: AppLogger.instance);

  setUp(() async {
    final directory = await Directory.systemTemp.createTemp('daviewer-update-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
  });

  ProviderContainer containerFor(_ReleaseAdapter adapter) {
    final container = ProviderContainer(
      overrides: [
        runningAppVersionProvider.overrideWithValue('0.5.8'),
        runtimeProvider.overrideWithValue(
          AppRuntime(
            clientId: 'test',
            oauth: null,
            transport: null,
            transfers: transfers,
            dio: Dio()..httpClientAdapter = adapter,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('restart rechecks despite a recent persisted timestamp', () async {
    await AppPreferences.saveLastUpdateCheck(
      DateTime.now().millisecondsSinceEpoch,
    );
    final adapter = _ReleaseAdapter();
    final first = containerFor(adapter);
    await first.read(updateCheckControllerProvider.notifier).check();
    expect(first.read(updateCheckControllerProvider).latestVersion, '0.5.9');
    final second = containerFor(adapter);
    await second.read(updateCheckControllerProvider.notifier).check();
    expect(adapter.calls, 2);
    expect(second.read(updateCheckControllerProvider).hasUpdate, isTrue);
  });

  test(
    'concurrent checks coalesce and a cached update stays visible',
    () async {
      final adapter = _ReleaseAdapter();
      final container = containerFor(adapter);
      final controller = container.read(updateCheckControllerProvider.notifier);
      await Future.wait([controller.check(), controller.check()]);
      await controller.check();
      expect(adapter.calls, 1);
      expect(container.read(updateCheckControllerProvider).hasUpdate, isTrue);
    },
  );

  test('failed recheck preserves an already discovered update', () async {
    final adapter = _ReleaseAdapter();
    final container = containerFor(adapter);
    final controller = container.read(updateCheckControllerProvider.notifier);
    await controller.check();
    adapter.fail = true;
    await controller.check(force: true);
    expect(
      container.read(updateCheckControllerProvider).latestVersion,
      '0.5.9',
    );
    expect(container.read(updateCheckControllerProvider).checking, isFalse);
  });

  test('dismissed release stays dismissed after restarting', () async {
    final adapter = _ReleaseAdapter();
    final first = containerFor(adapter);
    final controller = first.read(updateCheckControllerProvider.notifier);
    await controller.check();
    await controller.dismiss('0.5.9');
    final second = containerFor(adapter);
    await second.read(updateCheckControllerProvider.notifier).check();
    expect(second.read(updateCheckControllerProvider).hasUpdate, isFalse);
  });
}
