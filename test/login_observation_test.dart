import 'dart:async';
import 'dart:io';

import 'package:daviewer/core/auth/login_observation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late LoginHistoryStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('daviewer-login-test-');
    store = LoginHistoryStore(directory: () async => directory);
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'failed check retains success and storage failure does not change identity',
    () async {
      var now = DateTime.utc(2026, 10, 16);
      final controller = LoginObservationController(
        LoginChannel.web,
        store,
        () => now,
      );
      controller.begin('Artist');
      controller.finish(LoginCheckResult.authenticated);
      final success = controller.state.lastSuccess;
      controller.storage(
        save: LoginStorageResult.failed,
        reason: 'write_failed',
      );
      expect(controller.state.result, LoginCheckResult.authenticated);
      expect(controller.state.save, LoginStorageResult.failed);
      now = now.add(const Duration(hours: 1));
      controller.begin('artist');
      controller.finish(LoginCheckResult.unavailable, reason: 'timeout');
      expect(controller.state.lastSuccess, success);
      expect(controller.state.lastAttempt, now);
      expect(controller.state.checking, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final restored = await store.read(LoginChannel.web, 'artist');
      expect(restored!.lastSuccess, success);
      expect(restored.result, LoginCheckResult.unknown);
      expect(restored.reason, 'timeout');
      expect(restored.save, LoginStorageResult.failed);
      controller.dispose();
    },
  );

  test('channel histories and account identities stay isolated', () async {
    final now = DateTime.utc(2026, 10, 16);
    await store.write(
      LoginChannel.web,
      LoginObservation(owner: 'a', lastSuccess: now),
    );
    await store.write(
      LoginChannel.api,
      const LoginObservation(owner: 'a', reason: 'timeout'),
    );
    expect((await store.read(LoginChannel.web, 'a'))!.lastSuccess, now);
    expect((await store.read(LoginChannel.api, 'a'))!.lastSuccess, isNull);
    expect(await store.read(LoginChannel.web, 'b'), isNull);
  });

  test(
    'history persists only allowlisted fields and never raw error text',
    () async {
      await store.write(
        LoginChannel.web,
        const LoginObservation(
          owner: 'artist',
          reason: 'Cookie: secret',
          storageReason: 'Bearer token',
        ),
      );
      final text = await File('${directory.path}/login-history-web.json')
          .readAsString();
      expect(text, isNot(contains('secret')));
      expect(text, isNot(contains('Bearer')));
      expect(text, isNot(contains('authenticated')));
    },
  );

  test('late account history cannot overwrite a newer account', () async {
    final gated = _GatedHistory();
    final controller = LoginObservationController(
      LoginChannel.web,
      gated,
      DateTime.now,
    );
    controller.bind('old');
    controller.bind('new');
    gated.old.complete(
      LoginObservation(owner: 'old', lastSuccess: DateTime.utc(2020)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.owner, 'new');
    expect(controller.state.lastSuccess, isNull);
    controller.dispose();
  });
}

class _GatedHistory extends LoginHistoryStore {
  final old = Completer<LoginObservation?>();
  @override
  Future<LoginObservation?> read(LoginChannel channel, String owner) async =>
      owner == 'old' ? old.future : null;
}
