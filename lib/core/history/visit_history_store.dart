import 'dart:convert';
import 'dart:io';

import 'package:dakit_core/dakit_core.dart';
import 'package:path_provider/path_provider.dart';

import '../diagnostics/app_logger.dart';

/// A locally persisted artwork visit. Only enough data is kept to draw the
/// list and reopen the detail route; account data is always refreshed live.
final class ArtworkVisit {
  const ArtworkVisit({
    required this.id,
    required this.title,
    required this.username,
    required this.visitedAt,
    this.thumbnail,
  });

  final String id;
  final String title;
  final String username;
  final DateTime visitedAt;
  final Uri? thumbnail;

  factory ArtworkVisit.fromArtwork(Artwork artwork) {
    final image = artwork.media
        .where((media) => media.kind == MediaKind.image)
        .firstOrNull;
    final thumbnail = (image ?? artwork.media.firstOrNull)?.uri;
    return ArtworkVisit(
      id: artwork.id,
      title: artwork.title,
      username: artwork.author.username,
      visitedAt: DateTime.now(),
      thumbnail: thumbnail,
    );
  }

  static ArtworkVisit? fromJson(Object? value) {
    if (value is! Map<Object?, Object?>) return null;
    final id = value['id'];
    if (id is! String || id.isEmpty) return null;
    final visitedAt = DateTime.tryParse(switch (value['visitedAt']) {
      final String text => text,
      _ => '',
    });
    if (visitedAt == null) return null;
    return ArtworkVisit(
      id: id,
      title: switch (value['title']) {
        final String title => title,
        _ => id,
      },
      username: switch (value['username']) {
        final String username => username,
        _ => '',
      },
      visitedAt: visitedAt,
      thumbnail: switch (value['thumbnail']) {
        final String thumbnail when thumbnail.isNotEmpty => Uri.tryParse(
          thumbnail,
        ),
        _ => null,
      },
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'username': username,
    'visitedAt': visitedAt.toUtc().toIso8601String(),
    if (thumbnail != null) 'thumbnail': thumbnail.toString(),
  };
}

/// Persists recent artwork visits as a small JSON file. Visits never leave the
/// device and are deduplicated by artwork id.
final class VisitHistoryStore {
  const VisitHistoryStore._();

  static const int _maxEntries = 200;
  static const String _fileName = 'visit_history.json';

  static Future<File> _file([Directory? directory]) async {
    final dir = directory ?? await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  static List<ArtworkVisit> _decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const <ArtworkVisit>[];
    return decoded
        .map(ArtworkVisit.fromJson)
        .whereType<ArtworkVisit>()
        .toList(growable: false);
  }

  static Future<List<ArtworkVisit>> load({Directory? directory}) async {
    try {
      final file = await _file(directory);
      if (!await file.exists()) return const <ArtworkVisit>[];
      return _decode(await file.readAsString());
    } on Object catch (error, stack) {
      AppLogger.instance.warning(
        'history',
        'failed to load visit history',
        error,
        stack,
      );
      return const <ArtworkVisit>[];
    }
  }

  static Future<List<ArtworkVisit>> record(
    Artwork artwork, {
    Directory? directory,
  }) async {
    final visit = ArtworkVisit.fromArtwork(artwork);
    if (visit.id.isEmpty) return load(directory: directory);
    try {
      final history = (await load(directory: directory))
          .where((v) => v.id != visit.id)
          .toList();
      history.insert(0, visit);
      final capped = history.take(_maxEntries).toList(growable: false);
      await (await _file(directory)).writeAsString(jsonEncode(capped));
      return capped;
    } on Object catch (error, stack) {
      AppLogger.instance.warning(
        'history',
        'failed to save visit history',
        error,
        stack,
      );
      return load(directory: directory);
    }
  }

  static Future<void> clear({Directory? directory}) async {
    try {
      final file = await _file(directory);
      if (await file.exists()) await file.delete();
    } on Object catch (error, stack) {
      AppLogger.instance.warning(
        'history',
        'failed to clear visit history',
        error,
        stack,
      );
    }
  }
}
