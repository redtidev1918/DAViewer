import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dakit_core/dakit_core.dart';

/// One persisted personalized-feed first page, scoped to the account that
/// produced it.
final class ArtworkFeedCacheSnapshot {
  const ArtworkFeedCacheSnapshot({
    required this.username,
    required this.savedAt,
    required this.items,
  });

  final String username;
  final DateTime savedAt;
  final List<Artwork> items;
}

/// Stores the last successful personalized-feed first page per account so a
/// cold start can render real recommendations while verification and the
/// network refresh run (see REG-012).
///
/// Files are plain JSON keyed by a hash of the username, written atomically
/// (temp file + rename) and pruned to the newest [maxEntries] accounts. A
/// corrupt, foreign-version or unparsable file reads as "no cache": rendering
/// must never fail because of a stale cache file.
final class ArtworkFeedCacheStore {
  ArtworkFeedCacheStore({required this.directory, this.maxEntries = 3});

  /// Directory that holds the per-account cache files, e.g.
  /// `<application support>/feed_cache`.
  final Directory directory;

  /// How many account files to keep (newest first by modification time).
  final int maxEntries;

  /// Bump to invalidate every stored snapshot when the format changes. The
  /// value is part of the filename, so old files simply never match again.
  static const int formatVersion = 1;

  /// Defensive cap: only a first page is ever written, but a malformed caller
  /// must not be able to balloon the file.
  static const int _maxItems = 60;

  Future<ArtworkFeedCacheSnapshot?> read(String username) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) return null;
    final file = _fileFor(trimmed);
    try {
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic>) return null;
      if (data['version'] != formatVersion) return null;
      final savedAt = DateTime.tryParse(data['savedAt'] as String? ?? '');
      if (savedAt == null) return null;
      final rawItems = data['items'];
      if (rawItems is! List) return null;
      final items = <Artwork>[];
      for (final raw in rawItems) {
        if (raw is! Map<String, dynamic>) continue;
        final artwork = _artworkFromJson(raw);
        if (artwork != null) items.add(artwork);
      }
      if (items.isEmpty) return null;
      return ArtworkFeedCacheSnapshot(
        username: trimmed,
        savedAt: savedAt,
        items: items,
      );
    } on Object {
      // Missing fields, changed shapes, unreadable bytes: treat as absent.
      return null;
    }
  }

  Future<void> write(String username, List<Artwork> items) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty || items.isEmpty) return;
    final bounded = items.length > _maxItems ? items.sublist(0, _maxItems) : items;
    await directory.create(recursive: true);
    final file = _fileFor(trimmed);
    final payload = jsonEncode(<String, Object?>{
      'version': formatVersion,
      'username': trimmed,
      'savedAt': DateTime.now().toIso8601String(),
      'items': <Object?>[for (final item in bounded) _artworkToJson(item)],
    });
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(payload, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(file.path);
    await _prune();
  }

  Future<void> _prune() async {
    final files = <File, DateTime>{};
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.endsWith('.json')) continue;
      try {
        files[entity] = await entity.lastModified();
      } on Object {
        // Vanished between listing and stat: not a prune candidate.
      }
    }
    if (files.length <= maxEntries) return;
    final sorted = files.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in sorted.sublist(maxEntries)) {
      try {
        await entry.key.delete();
      } on Object {
        // Best effort; the next write retries the prune.
      }
    }
  }

  File _fileFor(String username) {
    final digest = sha256
        .convert(utf8.encode('daviewer:personalized-feed:v$formatVersion:$username'))
        .toString();
    return File('${directory.path}${Platform.pathSeparator}$digest.json');
  }
}

Map<String, Object?> _userToJson(UserProfile user) => <String, Object?>{
  'id': user.id,
  'username': user.username,
  'displayName': user.displayName,
  'avatarUri': user.avatarUri?.toString(),
  'profileUri': user.profileUri?.toString(),
};

UserProfile _userFromJson(Map<String, dynamic> json) => UserProfile(
  id: json['id'] as String? ?? '',
  username: json['username'] as String? ?? '',
  displayName: json['displayName'] as String?,
  avatarUri: _uriOrNull(json['avatarUri'] as String?),
  profileUri: _uriOrNull(json['profileUri'] as String?),
);

Map<String, Object?> _mediaToJson(MediaAsset asset) => <String, Object?>{
  'id': asset.id,
  'kind': asset.kind.name,
  'role': asset.role.name,
  'availability': asset.availability.name,
  'uri': asset.uri?.toString(),
  'mimeType': asset.mimeType,
  'filename': asset.filename,
  'byteLength': asset.byteLength,
  'width': asset.width,
  'height': asset.height,
  'durationMs': asset.duration?.inMilliseconds,
  'availabilityReason': asset.availabilityReason,
};

MediaAsset _mediaFromJson(Map<String, dynamic> json) => MediaAsset(
  id: json['id'] as String? ?? '',
  kind: _mediaKind(json['kind'] as String?),
  role: _mediaRole(json['role'] as String?),
  availability: _mediaAvailability(json['availability'] as String?),
  uri: _uriOrNull(json['uri'] as String?),
  mimeType: json['mimeType'] as String?,
  filename: json['filename'] as String?,
  byteLength: json['byteLength'] as int?,
  width: json['width'] as int?,
  height: json['height'] as int?,
  duration: json['durationMs'] == null
      ? null
      : Duration(milliseconds: json['durationMs'] as int),
  availabilityReason: json['availabilityReason'] as String?,
);

Map<String, Object?> _textContentToJson(ArtworkTextContent text) =>
    <String, Object?>{
      'excerpt': text.excerpt,
      'format': text.format,
      'markup': text.markup,
      'features': text.features,
    };

Map<String, Object?> _artworkToJson(Artwork artwork) => <String, Object?>{
  'id': artwork.id,
  'title': artwork.title,
  'author': _userToJson(artwork.author),
  'pageUri': artwork.pageUri.toString(),
  'media': <Object?>[
    for (final asset in artwork.media) _mediaToJson(asset),
  ],
  'description': artwork.description,
  'publishedAt': artwork.publishedAt?.toIso8601String(),
  'isMature': artwork.isMature,
  'isDownloadable': artwork.isDownloadable,
  'isFavourited': artwork.isFavourited,
  'isMultiMedia': artwork.isMultiMedia,
  'downloadAvailability': artwork.downloadAvailability.name,
  'textContent': artwork.textContent == null
      ? null
      : _textContentToJson(artwork.textContent!),
  'tags': artwork.tags,
};

Artwork? _artworkFromJson(Map<String, dynamic> json) {
  final id = json['id'] as String?;
  final title = json['title'] as String?;
  final authorJson = json['author'];
  final pageUri = _uriOrNull(json['pageUri'] as String?);
  if (id == null ||
      id.isEmpty ||
      title == null ||
      authorJson is! Map<String, dynamic> ||
      pageUri == null) {
    return null;
  }
  final rawMedia = json['media'];
  final media = <MediaAsset>[
    if (rawMedia is List)
      for (final raw in rawMedia)
        if (raw is Map<String, dynamic>) _mediaFromJson(raw),
  ];
  final rawText = json['textContent'];
  final textContent = rawText is Map<String, dynamic>
      ? ArtworkTextContent(
          excerpt: rawText['excerpt'] as String? ?? '',
          format: rawText['format'] as String?,
          markup: rawText['markup'] as String?,
          features: rawText['features'] as String?,
        )
      : null;
  final rawTags = json['tags'];
  final rawAvailability = json['downloadAvailability'] as String?;
  return Artwork(
    id: id,
    title: title,
    author: _userFromJson(authorJson),
    pageUri: pageUri,
    media: media,
    description: json['description'] as String?,
    publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? ''),
    isMature: json['isMature'] as bool? ?? false,
    isDownloadable: json['isDownloadable'] as bool? ?? false,
    isFavourited: json['isFavourited'] as bool? ?? false,
    isMultiMedia: json['isMultiMedia'] as bool? ?? false,
    // null keeps the model's own default derived from isDownloadable.
    downloadAvailability: rawAvailability == null
        ? null
        : _mediaAvailability(rawAvailability),
    textContent: textContent,
    tags: <String>[
      if (rawTags is List)
        for (final tag in rawTags)
          if (tag is String) tag,
    ],
  );
}

Uri? _uriOrNull(String? value) {
  if (value == null || value.isEmpty) return null;
  return Uri.tryParse(value);
}

MediaKind _mediaKind(String? name) {
  for (final kind in MediaKind.values) {
    if (kind.name == name) return kind;
  }
  return MediaKind.unknown;
}

MediaRole _mediaRole(String? name) {
  for (final role in MediaRole.values) {
    if (role.name == name) return role;
  }
  return MediaRole.preview;
}

MediaAvailability _mediaAvailability(String? name) {
  for (final availability in MediaAvailability.values) {
    if (availability.name == name) return availability;
  }
  return MediaAvailability.missing;
}
