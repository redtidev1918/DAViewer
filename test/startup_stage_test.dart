import 'dart:async';

import 'package:daviewer/core/runtime/startup_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('optional startup stage returns its successful value', () async {
    expect(
      await runOptionalStartupStage(
        stage: 'preferences',
        operation: () async => 'stored',
        fallback: 'default',
      ),
      'stored',
    );
  });

  test(
    'synchronous native startup exception releases the startup chain',
    () async {
      expect(
        await runOptionalStartupStage(
          stage: 'crash_marker',
          operation: () => throw StateError('unavailable'),
          fallback: false,
        ),
        isFalse,
      );
    },
  );

  test(
    'asynchronous native startup exception releases the startup chain',
    () async {
      expect(
        await runOptionalStartupStage(
          stage: 'preferences',
          operation: () => Future<bool>.error(StateError('unavailable')),
          fallback: false,
        ),
        isFalse,
      );
    },
  );

  test('timeout returns fallback and late read cannot replace it or block a new startup', () async {
    final pending = Completer<String>();
    final result = await runOptionalStartupStage(
      stage: 'preferences',
      operation: () => pending.future,
      fallback: 'default',
      budget: const Duration(milliseconds: 5),
    );
    expect(result, 'default');
    pending.complete('late');
    expect(
      await runOptionalStartupStage(
        stage: 'preferences',
        operation: () async => 'next',
        fallback: 'default',
      ),
      'next',
    );
    expect(result, 'default');
  });
}
