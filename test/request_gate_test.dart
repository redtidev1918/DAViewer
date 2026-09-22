import 'dart:async';

import 'package:daviewer/core/data/request_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('concurrent loads share one request per key', () async {
    var calls = 0;
    final gate = RepositoryRequestGate<String>();
    final gateValue = Completer<String>();

    final first = gate.load('art-1', () {
      calls += 1;
      return gateValue.future;
    });
    final second = gate.load('art-1', () async {
      calls += 1;
      return 'duplicate';
    });

    expect(calls, 1);
    gateValue.complete('loaded');
    expect(await first, 'loaded');
    expect(await second, 'loaded');
    expect(calls, 1);
  });

  test('success is cached and force reload bypasses cache', () async {
    var calls = 0;
    final gate = RepositoryRequestGate<String>();

    final first = await gate.load('user-1', () async {
      calls += 1;
      return 'a';
    });
    final cached = await gate.load('user-1', () async {
      calls += 1;
      return 'b';
    });
    expect(calls, 1);
    expect(first, 'a');
    expect(cached, 'a');

    final forced = await gate.load('user-1', () async {
      calls += 1;
      return 'b';
    }, force: true);
    expect(calls, 2);
    expect(forced, 'b');
  });

  test('failed result is not cached and may be retried', () async {
    var calls = 0;
    final gate = RepositoryRequestGate<String>();

    await expectLater(
      gate.load('art-2', () async {
        calls += 1;
        throw StateError('boom');
      }),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      gate.load('art-2', () async {
        calls += 1;
        return 'recovered';
      }),
      completes,
    );

    expect(calls, 2);
    expect(
      await gate.load('art-2', () async {
        calls += 1;
        return 'cached';
      }),
      'recovered',
    );
  });

  test(
    'cancel drops an in-flight request so a later call starts fresh',
    () async {
      final gate = RepositoryRequestGate<String>();
      final gateValue = Completer<String>();
      var calls = 0;

      final first = gate.load('stalled', () {
        calls += 1;
        return gateValue.future;
      });
      expect(calls, 1);
      gate.cancel('stalled');

      final second = gate.load('stalled', () async {
        calls += 1;
        return 'fresh';
      });
      expect(await second, 'fresh');
      expect(
        calls,
        2,
        reason: 'cancel must not leave a stale in-flight request',
      );

      gateValue.complete('late');
      expect(await first, 'late');
    },
  );
}
