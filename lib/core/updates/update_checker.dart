import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../runtime/runtime_provider.dart';
import '../settings/app_preferences.dart';

/// The running app version, taken from the Flutter build name at compile time.
/// The release script passes it explicitly as a Dart define; debug runs report
/// `development`.
const String appVersion = String.fromEnvironment(
  'DAVIEWER_VERSION',
  defaultValue: 'development',
);

final runningAppVersionProvider = Provider<String>((ref) => appVersion);

/// The public GitHub release used to detect newer builds. No authentication and
/// no user data are involved; this is the same URL a browser would fetch.
const String _latestReleaseUrl =
    'https://github.com/redtidev1918/DAViewer/releases/latest';
const String _apiLatestUrl =
    'https://api.github.com/repos/redtidev1918/DAViewer/releases/latest';
const String _releaseNotesRawUrl =
    'https://raw.githubusercontent.com/redtidev1918/DAViewer/main/RELEASE_NOTES.md';

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

  /// The release notes from the Release body or matching versioned notes for
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

/// Extracts the `## <version>` user-facing section from [RELEASE_NOTES.md].
/// Returns `null` when the repository notes have no matching section.
String? extractReleaseNotesSection(String markdown, String version) {
  final needle = '## $version';
  final lines = markdown.split('\n');
  var start = -1;
  for (var i = 0; i < lines.length; i += 1) {
    if (lines[i].trim() == needle) {
      start = i + 1;
      break;
    }
  }
  if (start < 0) return null;
  final notes = <String>[];
  final heading = RegExp(r'^##\s+');
  for (var i = start; i < lines.length; i += 1) {
    if (heading.hasMatch(lines[i])) break;
    notes.add(lines[i]);
  }
  final section = notes.join('\n').trim();
  return section.isEmpty ? null : section;
}

/// Fetches the raw `RELEASE_NOTES.md` section for [version]. Used when the
/// GitHub API is rate-limited: the app still reports the version found via the
/// HTML redirect and fills in the user-facing notes from the repository file.
Future<UpdateInfo> releaseInfoFromRawNotes({
  required Dio dio,
  required String version,
}) async {
  // The release workflow publishes this versioned file. The legacy aggregate
  // is retained only for older releases that predate per-version notes.
  try {
    final response = await dio.get<String>(
      'https://raw.githubusercontent.com/redtidev1918/DAViewer/'
      'v$version/.github/release-notes/$version.md',
      options: Options(responseType: ResponseType.plain),
    );
    final notes = extractUserReleaseNotes(response.data ?? '');
    if (notes != null) return UpdateInfo(version: version, notes: notes);
  } on Object {
    // Older tags may not contain a versioned notes file.
  }
  try {
    final response = await dio.get<String>(
      _releaseNotesRawUrl,
      options: Options(responseType: ResponseType.plain),
    );
    final notes = extractReleaseNotesSection(response.data ?? '', version);
    return UpdateInfo(version: version, notes: notes);
  } on Object {
    return UpdateInfo(version: version);
  }
}

/// Reads the current latest release with two fallbacks:
///
/// 1. GitHub API JSON, which includes the rendered Release body.
/// 2. The HTML `releases/latest` redirect for the version, then the raw
///    `RELEASE_NOTES.md` for the user-facing section when the API is
///    rate-limited. The raw file still gives full notes without an API call.
Future<UpdateInfo?> fetchLatestReleaseInfo({required Dio dio}) async {
  UpdateInfo? apiInfo;
  try {
    final response = await dio.get<Object?>(
      _apiLatestUrl,
      options: Options(responseType: ResponseType.json, followRedirects: true),
    );
    apiInfo = parseLatestRelease(response.data);
    if (apiInfo != null && apiInfo.notes != null) return apiInfo;
  } on Object {
    // API blocked or rate-limited; fall through to the HTML route.
  }

  UpdateInfo? versionOnly;
  try {
    final response = await dio.get<Object?>(
      _latestReleaseUrl,
      options: Options(responseType: ResponseType.plain, followRedirects: true),
    );
    final data = response.data;
    if (data is Map) {
      final info = parseLatestRelease(data);
      if (info?.notes != null) return info;
      versionOnly = info;
    }
    final version = versionFromReleaseUri(response.realUri);
    if (version != null) {
      versionOnly = UpdateInfo(version: version);
      if (apiInfo != null && apiInfo.version == version) {
        versionOnly = apiInfo;
      }
    }
  } on Object {
    // No HTML route either.
  }
  versionOnly ??= apiInfo;
  if (versionOnly == null) return null;

  return releaseInfoFromRawNotes(dio: dio, version: versionOnly.version);
}

final updateCheckControllerProvider =
    StateNotifierProvider<UpdateCheckController, UpdateCheckState>(
      (ref) => UpdateCheckController(ref),
    );

/// Checks for a newer release at most once per five minutes, silently. The result is
/// surfaced as a dismissible banner, never a modal, and a version the user has
/// dismissed is never shown again. Every failure stays silent.
final class UpdateCheckController extends StateNotifier<UpdateCheckState> {
  UpdateCheckController(this._ref) : super(const UpdateCheckState()) {
    unawaited(check());
  }

  final Ref _ref;
  DateTime? _lastSuccess;
  Future<void>? _activeCheck;

  Future<void> check({bool force = false}) {
    final active = _activeCheck;
    if (active != null) return active;
    final last = _lastSuccess;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 5)) {
      return Future<void>.value();
    }
    late final Future<void> tracked;
    tracked = _performCheck().whenComplete(() {
      if (identical(_activeCheck, tracked)) _activeCheck = null;
    });
    _activeCheck = tracked;
    return tracked;
  }

  Future<void> _performCheck() async {
    // Avoid writing provider state from its constructor's synchronous build.
    await Future<void>.value();
    if (!_ref.mounted) return;
    final currentVersion = _ref.read(runningAppVersionProvider);
    if (!isSemver(currentVersion)) return;
    final previous = state;
    state = UpdateCheckState(
      checking: true,
      latestVersion: previous.latestVersion,
      notes: previous.notes,
    );
    try {
      final dio = _ref.read(runtimeProvider).dio;
      if (dio == null) {
        state = previous;
        return;
      }
      final info = await fetchLatestReleaseInfo(dio: dio);
      if (!_ref.mounted) return;
      if (info == null) {
        state = previous;
        return;
      }
      // Cache only within this process: a persisted timestamp without a
      // persisted result used to hide updates after restarting the app.
      _lastSuccess = DateTime.now();
      if (compareVersions(info.version, currentVersion) <= 0) {
        state = const UpdateCheckState();
        return;
      }
      final dismissed = await AppPreferences.loadDismissedUpdateVersion();
      if (!_ref.mounted) return;
      if (dismissed == info.version) {
        state = const UpdateCheckState();
        return;
      }
      state = UpdateCheckState(latestVersion: info.version, notes: info.notes);
    } on Object {
      // The update check must never surface an error to the user.
      if (_ref.mounted) state = previous;
    }
  }

  Future<void> dismiss(String version) async {
    await AppPreferences.saveDismissedUpdateVersion(version);
    state = const UpdateCheckState();
  }
}
