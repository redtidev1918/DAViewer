import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../storage/storage_queue.dart';

/// Persists lightweight tag-interest counts (a tag -> weight map) so the
/// personalized "recommended tags" survive app restarts instead of vanishing
/// with the in-memory artwork cache. Only tag names and weights are stored —
/// no artworks, no account data.
final class InterestStore {
  const InterestStore._();

  static const String _fileName = 'interests.json';
  static final _queue = StorageQueue();

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  static Future<Map<String, int>> load() => _queue.run(_load);

  static Future<Map<String, int>> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return <String, int>{};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return <String, int>{};
      return <String, int>{
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is int)
            entry.key as String: entry.value as int,
      };
    } on Object {
      return <String, int>{};
    }
  }

  /// Records that the user viewed works carrying [tags] (each tag +1).
  static Future<void> recordTags(Iterable<String> tags) {
    final normalized = tags
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toSet();
    if (normalized.isEmpty) return Future<void>.value();
    return _update((map) {
      for (final tag in normalized) {
        map[tag] = (map[tag] ?? 0) + 1;
      }
    });
  }

  static Future<void> _update(void Function(Map<String, int>) mutate) {
    return _queue.run(() => _performUpdate(mutate));
  }

  static Future<void> _performUpdate(
    void Function(Map<String, int>) mutate,
  ) async {
    try {
      final file = await _file();
      final map = <String, int>{};
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          map.addAll(<String, int>{
            for (final entry in decoded.entries)
              if (entry.key is String && entry.value is int)
                entry.key as String: entry.value as int,
          });
        }
      }
      mutate(map);
      await file.writeAsString(jsonEncode(map));
    } on Object {
      // Best effort: interest recording must never break the app.
    }
  }
}
