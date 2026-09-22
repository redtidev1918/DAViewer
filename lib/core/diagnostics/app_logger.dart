import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dakit_core/dakit_core.dart';
import 'package:flutter/foundation.dart' hide DiagnosticLevel;
import 'package:path_provider/path_provider.dart';

import 'crash_marker.dart';

/// Level-filtered, file-backed logger that also implements DAKit's
/// [DiagnosticSink] so every OAuth/network/transfer diagnostic event is
/// recorded automatically.
///
/// Usage:
/// ```dart
/// final logger = await AppLogger.initialize();
/// logger.info('auth', 'session restored');
/// logger.error('network', 'request failed', error, stackTrace);
/// ```
final class AppLogger implements DiagnosticSink {
  AppLogger._(this._file, this._directory);

  static AppLogger? _instance;

  /// Current logger, or a console-only fallback when [initialize] has not been
  /// called yet (e.g. inside unit tests that construct the runtime directly).
  static AppLogger get instance {
    final current = _instance;
    if (current != null) return current;
    return _fallback ??= AppLogger._(NullSink(), Directory.systemTemp);
  }

  static AppLogger? _fallback;

  static bool get isInitialized => _instance != null;

  final Directory _directory;
  final IOSink _file;
  int _errorCount = 0;

  static Future<AppLogger> initialize({String? fileName}) async {
    if (_instance case final existing?) return existing;
    final support = await getApplicationSupportDirectory();
    final logsDir = Directory('${support.path}${Platform.pathSeparator}logs');
    await logsDir.create(recursive: true);
    final name =
        fileName ??
        'daviewer-${DateTime.now().toIso8601String().replaceAll(':', '-')}.log';
    final file = File('${logsDir.path}${Platform.pathSeparator}$name');
    final sink = file.openWrite(mode: FileMode.append);
    final logger = AppLogger._(sink, logsDir);
    _instance = logger;
    logger.info('app', 'logger initialized: $name');
    return logger;
  }

  /// Directory containing rotated log files (exposed for UI/debugging).
  String get logsDirectory => _directory.path;

  /// Stable user-facing name. The physical sandbox path contains the package
  /// identifier on Android/macOS and must not be presented as the product name.
  String get logsDisplayName => 'DAViewer/logs';

  /// Number of error-level events recorded in this session.
  int get errorCount => _errorCount;

  void debug(
    String scope,
    String message, [
    Object? error,
    StackTrace? stack,
  ]) => _write(DiagnosticLevel.debug, scope, message, error, stack);

  void info(String scope, String message, [Object? error, StackTrace? stack]) =>
      _write(DiagnosticLevel.info, scope, message, error, stack);

  void warning(
    String scope,
    String message, [
    Object? error,
    StackTrace? stack,
  ]) => _write(DiagnosticLevel.warning, scope, message, error, stack);

  void error(
    String scope,
    String message, [
    Object? error,
    StackTrace? stack,
  ]) => _write(DiagnosticLevel.error, scope, message, error, stack);

  void _write(
    DiagnosticLevel level,
    String scope,
    String message, [
    Object? error,
    StackTrace? stack,
  ]) {
    final line = _format(
      level: level,
      scope: scope,
      message: message,
      error: error,
      stack: stack,
    );
    debugPrint(line);
    _file.writeln(line);
    if (level == DiagnosticLevel.error) _errorCount += 1;
  }

  /// DAKit [DiagnosticSink] bridge: every event DAKit produces (OAuth launch,
  /// callback, token exchange, HTTP, storage, transfer) lands in the log.
  @override
  void add(DiagnosticEvent event) {
    final elapsed = event.elapsed == null
        ? ''
        : ' [${event.elapsed!.inMilliseconds}ms]';
    final attrs = event.attributes.isEmpty
        ? ''
        : ' ${event.attributes.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
    final line = _format(
      level: event.level,
      scope: event.stage.name,
      message: '${event.code}$elapsed$attrs ${event.message}',
    );
    debugPrint(line);
    _file.writeln(line);
    if (event.level == DiagnosticLevel.error) _errorCount += 1;
  }

  static String _format({
    required DiagnosticLevel level,
    required String scope,
    required String message,
    Object? error,
    StackTrace? stack,
  }) {
    final now = DateTime.now().toIso8601String();
    final buffer = StringBuffer(
      '$now [${level.name.toUpperCase()}] [$scope] $message',
    );
    if (error != null) buffer.write(' | error=$error');
    if (stack != null) buffer.write('\n$stack');
    return buffer.toString();
  }

  Future<void> dispose() async {
    await _file.flush();
    await _file.close();
    if (identical(_instance, this)) _instance = null;
  }
}

/// Discards writes; used only as a pre-initialization fallback sink.
final class NullSink implements IOSink {
  @override
  void write(Object? object) {}

  @override
  void writeln([Object? object = '']) {}

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> get done async {}

  @override
  Encoding get encoding => utf8;

  @override
  set encoding(Encoding encoding) {}
}

/// Installs global handlers so unexpected Dart/Flutter errors are captured
/// into the log file instead of only the console, and a local crash marker is
/// written so the next launch can offer to report it.
void installGlobalErrorHandlers(AppLogger logger) {
  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    logger.error(
      'flutter',
      details.toString(),
      details.exception,
      details.stack,
    );
    unawaited(CrashMarker.record());
    previousFlutterError?.call(details);
  };

  final previousPlatformError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    logger.error('platform', error.toString(), error, stack);
    unawaited(CrashMarker.record());
    return previousPlatformError?.call(error, stack) ?? false;
  };
}
