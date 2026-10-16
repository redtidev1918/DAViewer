import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../diagnostics/app_logger.dart';

/// Cold-start OAuth session evidence: `unknown` when nothing has been
/// recorded (fresh install or unreadable preferences), `signedIn` after a
/// successful save, and `signedOut` only after an explicit logout or a
/// definitive rejection.
enum OAuthSessionEvidence { unknown, signedIn, signedOut }

/// Persists non-sensitive user preferences (language, theme mode and proxy) to a small
/// JSON file in the application-support directory, mirroring the pattern used
/// by [SearchHistoryStore]. Values are stored as plain strings so this store
/// stays independent of the UI-language and theme enums.
final class AppPreferences {
  const AppPreferences._();

  static const String _fileName = 'preferences.json';
  static Future<void> _writeTail = Future<void>.value();

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  /// Loads the persisted preferences. Missing or malformed values fall back to
  /// the defaults (`zh` / `system`).
  static Future<Map<String, String>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        return const <String, String>{'language': 'zh', 'themeMode': 'system'};
      }
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        final language = decoded['language'];
        final themeMode = decoded['themeMode'];
        return <String, String>{
          'language': language == 'en' ? 'en' : 'zh',
          'themeMode': themeMode == 'light' || themeMode == 'dark'
              ? '$themeMode'
              : 'system',
        };
      }
    } on Object catch (error, stack) {
      AppLogger.instance.warning(
        'prefs',
        'failed to load preferences',
        error,
        stack,
      );
    }
    return const <String, String>{'language': 'zh', 'themeMode': 'system'};
  }

  static Future<void> saveLanguage(String language) =>
      _update((map) => map['language'] = language);

  static Future<void> saveThemeMode(String themeMode) =>
      _update((map) => map['themeMode'] = themeMode);

  static Future<String?> loadManualProxy() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        final value = decoded['manualProxy'];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    } on Object catch (error, stack) {
      AppLogger.instance.warning(
        'prefs',
        'failed to load manual proxy',
        error,
        stack,
      );
    }
    return null;
  }

  static Future<void> saveManualProxy(String? value) => _update((map) {
    if (value == null || value.trim().isEmpty) {
      map.remove('manualProxy');
    } else {
      map['manualProxy'] = value.trim();
    }
  });

  /// Cold-start OAuth session evidence: `unknown` when nothing has been
  /// recorded (fresh install or unreadable preferences), `signedIn` after a
  /// successful save, and `signedOut` only after an explicit logout or a
  /// definitive rejection. The enum lets recovery distinguish a missing flag
  /// from a recorded logout until the token store itself answers.
  static Future<OAuthSessionEvidence> loadOAuthSessionEvidence() async {
    try {
      final file = await _file();
      if (!await file.exists()) return OAuthSessionEvidence.unknown;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        final known = decoded['oauthSessionKnown'];
        if (known == true) return OAuthSessionEvidence.signedIn;
        if (known == false) return OAuthSessionEvidence.signedOut;
      }
      return OAuthSessionEvidence.unknown;
    } on Object catch (error, stack) {
      AppLogger.instance.warning(
        'prefs',
        'failed to load OAuth session evidence',
        error,
        stack,
      );
      return OAuthSessionEvidence.unknown;
    }
  }

  static Future<void> saveOAuthSessionKnown(bool value) => _update((map) {
    map['oauthSessionKnown'] = value;
  });

  /// The last release version the user dismissed from the update banner.
  /// Persisted so the same version is never re-shown.
  static Future<String?> loadDismissedUpdateVersion() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        final value = decoded['dismissedUpdateVersion'];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    } on Object catch (error, stack) {
      AppLogger.instance.warning(
        'prefs',
        'failed to load dismissed update version',
        error,
        stack,
      );
    }
    return null;
  }

  static Future<void> saveDismissedUpdateVersion(String version) =>
      _update((map) => map['dismissedUpdateVersion'] = version);

  /// Millisecond timestamp of the last automatic update check, used to throttle
  /// the check to once per day.
  static Future<int?> loadLastUpdateCheck() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        final value = decoded['lastUpdateCheck'];
        if (value is int) return value;
      }
    } on Object catch (error, stack) {
      AppLogger.instance.warning(
        'prefs',
        'failed to load last update check',
        error,
        stack,
      );
    }
    return null;
  }

  static Future<void> saveLastUpdateCheck(int timestamp) =>
      _update((map) => map['lastUpdateCheck'] = timestamp);

  /// Session-notice dismissals that must survive a restart. An id binds
  /// channel, account and incident only (see `webSessionNoticeId` /
  /// `apiSessionNoticeId` in `core/notice/web_session_notice.dart`): no Cookie,
  /// token or session payload is ever stored. The shape is re-validated on the
  /// way out of the file, which is untrusted input.
  static final RegExp _sessionNoticeId = RegExp(
    r'^(?:web-session:[^:]*:(?:invalid|locked)|api-session:[^:]*:invalid)$',
  );

  static bool isPersistableSessionNoticeId(String noticeId) =>
      _sessionNoticeId.hasMatch(noticeId);

  static Future<Set<String>> loadDismissedSessionNotices() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const <String>{};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        final value = decoded['dismissedSessionNotices'];
        if (value is List) {
          return value
              .whereType<String>()
              .where(isPersistableSessionNoticeId)
              .toSet();
        }
      }
    } on Object catch (error, stack) {
      AppLogger.instance.warning(
        'prefs',
        'failed to load session notice dismissals',
        error,
        stack,
      );
    }
    return const <String>{};
  }

  static Future<void> saveDismissedSessionNotices(Iterable<String> noticeIds) =>
      _update(
        (map) => map['dismissedSessionNotices'] = noticeIds
            .where(isPersistableSessionNoticeId)
            .toList(growable: false),
      );

  /// Resolves once every queued preference write has settled, so a caller
  /// leaving the process (or a test tearing down its directory) never races a
  /// half-written file.
  static Future<void> flush() => _writeTail;

  static Future<void> _update(void Function(Map<String, Object?>) mutate) {
    // Pin the write tail to the root zone: a caller running inside a widget
    // test's fake-async zone would otherwise strand every queued continuation
    // (the same trap documented on LoginHistoryStore), and the tail must
    // outlive the zone that happened to queue the write.
    final next = Zone.root.run(
      () => _writeTail.then((_) => _performUpdate(mutate)),
    );
    // _performUpdate catches and logs storage failures, so the tail remains
    // usable. Serializing read-modify-write prevents language/theme/proxy
    // changes made close together from overwriting each other.
    _writeTail = next;
    return next;
  }

  static Future<void> _performUpdate(
    void Function(Map<String, Object?>) mutate,
  ) async {
    try {
      final file = await _file();
      final map = <String, Object?>{};
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          map.addAll(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      }
      mutate(map);
      await file.writeAsString(jsonEncode(map));
    } on Object catch (error, stack) {
      AppLogger.instance.warning(
        'prefs',
        'failed to save preferences',
        error,
        stack,
      );
    }
  }
}
