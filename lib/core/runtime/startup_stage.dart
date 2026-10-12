import 'dart:async';

import '../diagnostics/app_logger.dart';

/// Optional pre-runApp reads must not prevent access to Home and diagnostics.
/// A timeout only abandons the read; it does not clear credentials or storage.
Future<T> runOptionalStartupStage<T>({
  required String stage,
  required Future<T> Function() operation,
  required T fallback,
  Duration budget = const Duration(seconds: 5),
}) async {
  try {
    return await Future<T>.sync(operation).timeout(budget);
  } on Object catch (error) {
    try {
      AppLogger.instance.warning(
        'startup',
        'optional stage=$stage failed errorType=${error.runtimeType}; continuing',
      );
    } on Object {
      // Diagnostics are observers, not a prerequisite for running the app.
    }
    return fallback;
  }
}
