import 'dart:async';

import 'package:daviewer/core/storage/storage_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('failure reaches caller without blocking queued operations', () async {
    final queue = StorageQueue();
    final gate = Completer<void>();
    final first = queue.run(() async {
      await gate.future;
      throw StateError('failed write');
    });
    final failure = expectLater(first, throwsStateError);
    var ran = false;
    final second = queue.run(() async => ran = true);
    await Future<void>.delayed(Duration.zero);
    expect(ran, isFalse);
    gate.complete();
    await failure;
    expect(await second, isTrue);
  });
}
