import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../runtime/runtime_provider.dart';
import '../settings/app_preferences.dart';

/// The running app version, taken from the Flutter build name at compile time.
/// The release workflow derives it from `pubspec.yaml`; debug runs report
/// `development`.
const String appVersion = String.fromEnvironment(
  'FLUTTER_BUILD_NAME',
  defaultValue: 'development',
);

/// The public GitHub release used to detect newer builds. No authentication and
/// no user data are involved; this is the same URL a browser would fetch.
const String _latestReleaseUrl =
    'https://github.com/redtidev1918/DAViewer/releases/latest';

/// Compares two dot-separated semantic versions; positive when `a` is newer.
int compareVersions(String a, String b) {
  final av = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final bv = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final length = av.length > bv.length ? av.length : bv.length;
  for (var i = 0; i < length; i++) {
    final x = i < av.length ? av[i] : 0;
    final y = i < bv.length ? bv[i] : 0;
    if (x != y) return x - y;
  }
  return 0;
}

/// Whether a string is a plain semantic version we can compare against.
bool isSemver(String value) => RegExp(r'^\d+(\.\d+)*$').hasMatch(value);

final class UpdateCheckState {
  const UpdateCheckState({
    this.checking = false,
    this.latestVersion,
    this.notes,
  });

  final bool checking;

  /// The newest published release version (without the leading `v`).
  final String? latestVersion;

  /// The release notes (the matching `RELEASE_NOTES.md` section) for
  /// [latestVersion], shown to the user so they know what changed.
  final String? notes;

  bool get hasUpdate => latestVersion != null;
}

/// Extracts version + release notes from the GitHub `releases/latest` payload.
/// Returns `null` when the shape is unexpected.
UpdateInfo? parseLatestRelease(Object? data) {
  if (data is! Map) return null;
  final rawTag = data['tag_name'];
  final rawBody = data['body'];
  if (rawTag is! String) return null;
  final version = rawTag.replaceFirst(RegExp('^v'), '');
  if (!isSemver(version)) return null;
  return UpdateInfo(
    version: version,
    notes: rawBody is String ? extractUserReleaseNotes(rawBody) : null,
  );
}

/// The `## 下载` / `## Downloads` heading that starts the asset table.
final RegExp _downloadsHeading = RegExp(
  r'^##\s*(?:下载|Downloads)\s*$',
  multiLine: true,
);

/// Keeps only the user-facing parts of a GitHub Release body for the in-app
/// banner. The downloads section — the asset table plus the checksums hint —
/// is the release page's job, not news; everything from the first
/// `## 下载`/`## Downloads` heading onward is dropped. Returns `null` when
/// nothing user-facing remains.
String? extractUserReleaseNotes(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return null;
  final match = _downloadsHeading.firstMatch(trimmed);
  if (match != null) {
    final notes = trimmed.substring(0, match.start).trim();
    return notes.isEmpty ? null : notes;
  }
  return trimmed;
}

/// A single parsed update check result.
final class UpdateInfo {
  const UpdateInfo({required this.version, this.notes});

  final String version;
  final String? notes;
}

String? versionFromReleaseUri(Uri uri) {
  for (var i = uri.pathSegments.length - 1; i >= 0; i -= 1) {
    final segment = uri.pathSegments[i];
    if (!segment.startsWith('v')) continue;
    final version = segment.substring(1);
    if (isSemver(version)) return version;
  }
  return null;
}

/// Reads the current latest release without depending on the anonymous GitHub
/// API rate limit. The HTML `releases/latest` endpoint redirects to the
/// concrete tag, e.g. `/releases/tag/v0.4.10`; the tag is the version.
Future<UpdateInfo?> fetchLatestReleaseInfo({required Dio dio}) async {
  final response = await dio.get<Object?>(
    _latestReleaseUrl,
    options: Options(responseType: ResponseType.plain, followRedirects: true),
  );
  final data = response.data;
  if (data is Map) return parseLatestRelease(data);
  final version = versionFromReleaseUri(response.realUri);
  if (version != null) return UpdateInfo(version: version);
  return null;
}

final updateCheckControllerProvider =
    StateNotifierProvider<UpdateCheckController, UpdateCheckState>(
      (ref) => UpdateCheckController(ref),
    );

/// Checks for a newer release at most once per day, silently. The result is
/// surfaced as a dismissible banner, never a modal, and a version the user has
/// dismissed is never shown again. Every failure stays silent.
final class UpdateCheckController extends StateNotifier<UpdateCheckState> {
  UpdateCheckController(this._ref) : super(const UpdateCheckState()) {
    unawaited(check());
  }

  final Ref _ref;

  Future<void> check() async {
    if (state.checking) return;
    final lastCheck = await AppPreferences.loadLastUpdateCheck();
    final now = DateTime.now().millisecondsSinceEpoch;
    // Throttle to once per hour (generous against GitHub's 60 req/hr rate
    // limit). A *failed* check does not record the time, so the next launch
    // or resume retries immediately instead of being suppressed for an hour.
    if (lastCheck != null &&
        now - lastCheck < const Duration(hours: 1).inMilliseconds) {
      return;
    }
    state = const UpdateCheckState(checking: true);
    try {
      final dio = _ref.read(runtimeProvider).dio;
      if (dio == null) {
        state = const UpdateCheckState();
        return;
      }
      final info = await fetchLatestReleaseInfo(dio: dio);
      if (info == null || !isSemver(appVersion)) {
        state = const UpdateCheckState();
        return;
      }
      // Only a successful check counts against the throttle window.
      await AppPreferences.saveLastUpdateCheck(now);
      if (compareVersions(info.version, appVersion) <= 0) {
        state = const UpdateCheckState();
        return;
      }
      final dismissed = await AppPreferences.loadDismissedUpdateVersion();
      if (dismissed == info.version) {
        state = const UpdateCheckState();
        return;
      }
      state = UpdateCheckState(latestVersion: info.version, notes: info.notes);
    } on Object {
      // The update check must never surface an error to the user.
      state = const UpdateCheckState();
    }
  }

  Future<void> dismiss(String version) async {
    await AppPreferences.saveDismissedUpdateVersion(version);
    state = const UpdateCheckState();
  }
}
