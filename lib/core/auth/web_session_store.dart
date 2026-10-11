import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../data/web_session.dart';
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
  const WebSessionStore({
    this.directoryFactory,
    this.storage = const FlutterSecureStorage(),
  });

  final Future<Directory> Function()? directoryFactory;
  final FlutterSecureStorage storage;
  static const storageKey = 'daviewer.web-session.v1';
  static Future<void> _writeTail = Future<void>.value();

  Future<Directory> _directory() =>
      directoryFactory?.call() ?? getApplicationSupportDirectory();

  Future<File> _file() async {
    final dir = await _directory();
    return File('${dir.path}/web_session.json');
  }

  Future<Map<String, Object?>> read() => _queue(() async {
    try {
      final result = await _readRaw();
      if (result.containsKey('cookies')) {
        result['cookies'] = parsePersistedCookies(result['cookies']);
      }
      return result;
    } on Object catch (error) {
      AppLogger.instance.warning(
        'web-session',
        'failed to read persisted snapshot errorType=${error.runtimeType}',
      );
      return const <String, Object?>{};
    }
  });

  Future<Map<String, Object?>> _readRaw() async {
    final secured = await storage.read(key: storageKey);
    final file = await _file();
    if (secured != null) {
      final decoded = _decode(secured);
      // A previous migration may have saved successfully but failed cleanup.
      await _removeLegacy(file);
      return decoded;
    }
    if (!await file.exists()) return <String, Object?>{};
    final legacy = await file.readAsString();
    final decoded = _decode(legacy);
    await _save(jsonEncode(decoded));
    await _removeLegacy(file);
    return decoded;
  }

  Future<void> _save(String snapshot) async {
    await storage.write(key: storageKey, value: snapshot);
    if (await storage.read(key: storageKey) != snapshot) {
      throw StateError('Web session secure-storage verification failed');
    }
  }

  Map<String, Object?> _decode(String snapshot) {
    try {
      return (jsonDecode(snapshot) as Map).cast<String, Object?>();
    } on Object {
      // FormatException normally includes its JSON source, which is a credential.
      throw const FormatException('Invalid stored web session');
    }
  }

  Future<void> _removeLegacy(File file) async {
    for (final candidate in [file, File('${file.path}.tmp')]) {
      if (await candidate.exists()) await candidate.delete();
    }
  }

  /// Patches the snapshot. Omitted fields keep their latest persisted values.
  /// [cookies] is written only when the caller explicitly supplies a valid,
  /// non-empty list; `null` never clears an existing Cookie snapshot.
  Future<void> update({
    String? csrf,
    bool? isLoggedIn,
    String? username,
    List<PersistedWebCookie>? cookies,
  }) => _queue(
    () => _performUpdate((map) {
      if (csrf != null) map['csrf'] = csrf;
      if (isLoggedIn != null) map['isLoggedIn'] = isLoggedIn;
      if (username != null) map['username'] = username;
      if (cookies != null && cookies.isNotEmpty) {
        map['cookies'] = <Map<String, Object?>>[
          for (final cookie in cookies) cookie.toJson(),
        ];
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
    try {
      final map = await _readRaw();
      mutate(map);
      await _save(jsonEncode(map));
      await _removeLegacy(await _file());
      final cookies = map['cookies'];
      AppLogger.instance.info(
        'web-session',
        'persist snapshot '
            'cookies=${cookies is List ? cookies.length : 0} '
            'generation=${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      );
    } on Object catch (error) {
      AppLogger.instance.warning(
        'web-session',
        'persist snapshot failed storage=platform-secure-storage errorType=${error.runtimeType}',
      );
      rethrow;
    }
  }

  Future<void> _performClear(String reason) async {
    try {
      await storage.delete(key: storageKey);
      final file = await _file();
      await _removeLegacy(file);
      AppLogger.instance.info(
        'web-session',
        'cleared persisted snapshot reason=$reason',
      );
    } on Object catch (error) {
      AppLogger.instance.warning(
        'web-session',
        'failed to clear persisted snapshot errorType=${error.runtimeType}',
      );
      rethrow;
    }
  }
}
