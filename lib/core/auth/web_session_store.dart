import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../diagnostics/app_logger.dart';

/// Persists a lightweight snapshot of the DeviantArt *web* session (CSRF +
/// login flag + username + cookies) so a cold start restores it alongside the
/// OAuth session, instead of leaving the home feed signed out while the OAuth
/// account still shows in the app bar.
///
/// Mutations are serialized read-modify-write operations. A CSRF update can
/// never replace Cookies, and a Cookie update can never resurrect stale
/// metadata from a caller's earlier read. Failures are logged, never silently
/// swallowed, because an invisible failed save presents later as "cookies were
/// lost after the app update".
final class WebSessionStore {
  const WebSessionStore({this.directoryFactory});

  final Future<Directory> Function()? directoryFactory;
  static Future<void> _writeTail = Future<void>.value();

  Future<Directory> _directory() =>
      directoryFactory?.call() ?? getApplicationSupportDirectory();

  Future<File> _file() async {
    final dir = await _directory();
    return File('${dir.path}/web_session.json');
  }

  Future<Map<String, Object?>> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const <String, Object?>{};
      final text = await file.readAsString();
      final data = jsonDecode(text);
      return data is Map<String, dynamic>
          ? data.cast<String, Object?>()
          : const <String, Object?>{};
    } on Object catch (error, stack) {
      AppLogger.instance.warning(
        'web-session',
        'failed to read persisted snapshot',
        error,
        stack,
      );
      return const <String, Object?>{};
    }
  }

  /// Patches the snapshot. Omitted fields keep their latest persisted values.
  /// [cookies] is written only when the caller explicitly supplies a valid,
  /// non-empty map; `null` never clears an existing Cookie snapshot.
  Future<void> update({
    String? csrf,
    bool? isLoggedIn,
    String? username,
    Map<String, String>? cookies,
  }) => _queue(
    () => _performUpdate((map) {
      if (csrf != null) map['csrf'] = csrf;
      if (isLoggedIn != null) map['isLoggedIn'] = isLoggedIn;
      if (username != null) map['username'] = username;
      if (cookies != null && cookies.isNotEmpty) {
        map['cookies'] = cookies;
      }
    }),
  );

  /// The only path that removes the persisted Cookie credentials. Callers must
  /// pass an explicit logout reason so accidental clears are visible in logs.
  Future<void> clear({required String reason}) =>
      _queue(() => _performClear(reason));

  Future<T> _queue<T>(Future<T> Function() operation) {
    final next = _writeTail.then((_) => operation());
    // Storage failures are logged and rethrown to the caller, but must not
    // poison later operations in the queue.
    _writeTail = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _performUpdate(
    void Function(Map<String, Object?>) mutate,
  ) async {
    final file = await _file();
    final map = <String, Object?>{};
    try {
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          map.addAll(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      }
      mutate(map);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(map), flush: true);
      await temporary.rename(file.path);
      final cookies = map['cookies'];
      AppLogger.instance.info(
        'web-session',
        'persist snapshot '
            'cookies=${cookies is Map ? cookies.length : 0} '
            'generation=${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      );
    } on Object catch (error, stack) {
      AppLogger.instance.warning(
        'web-session',
        'persist snapshot failed storage=web_session.json',
        error,
        stack,
      );
      rethrow;
    }
  }

  Future<void> _performClear(String reason) async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
      AppLogger.instance.info(
        'web-session',
        'cleared persisted snapshot reason=$reason',
      );
    } on Object catch (error, stack) {
      AppLogger.instance.warning(
        'web-session',
        'failed to clear persisted snapshot',
        error,
        stack,
      );
      rethrow;
    }
  }
}
