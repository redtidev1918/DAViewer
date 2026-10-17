import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../diagnostics/app_logger.dart';
import '../storage/storage_queue.dart';

/// Persists recent search queries as a small JSON file so users can quickly
/// re-run past searches.
final class SearchHistoryStore {
  const SearchHistoryStore._();

  static const int _maxEntries = 20;
  static const String _fileName = 'search_history.json';
  static final _queue = StorageQueue();

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  static Future<List<String>> load() => _queue.run(_load);

  static Future<List<String>> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const <String>[];
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList(growable: false);
      }
    } on Object catch (error, stack) {
      AppLogger.instance.warning(
        'search',
        'failed to load history',
        error,
        stack,
      );
    }
    return const <String>[];
  }

  static Future<List<String>> add(String query) =>
      _queue.run(() => _add(query));

  static Future<List<String>> _add(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return _load();
    try {
      final history = <String>[...await _load()];
      history.remove(trimmed);
      history.insert(0, trimmed);
      final capped = history.take(_maxEntries).toList(growable: false);
      final file = await _file();
      await file.writeAsString(jsonEncode(capped));
      return capped;
    } on Object catch (error, stack) {
      AppLogger.instance.warning(
        'search',
        'failed to save history',
        error,
        stack,
      );
    }
    return _load();
  }

  static Future<void> clear() => _queue.run(_clear);

  static Future<void> _clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } on Object catch (error, stack) {
      AppLogger.instance.warning(
        'search',
        'failed to clear history',
        error,
        stack,
      );
    }
  }

  /// Removes a single query from history and returns the updated list.
  static Future<List<String>> remove(String query) =>
      _queue.run(() => _remove(query));

  static Future<List<String>> _remove(String query) async {
    try {
      final history = <String>[...await _load()];
      history.remove(query);
      final file = await _file();
      await file.writeAsString(jsonEncode(history));
      return history;
    } on Object catch (error, stack) {
      AppLogger.instance.warning(
        'search',
        'failed to remove history',
        error,
        stack,
      );
    }
    return _load();
  }
}
