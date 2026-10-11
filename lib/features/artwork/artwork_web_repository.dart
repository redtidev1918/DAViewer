import 'package:dakit_core/dakit_core.dart';
import 'package:dakit_web/dakit_web.dart';
import 'package:dio/dio.dart';

import 'artwork_access_state.dart';

final class WebRelatedArtworks {
  const WebRelatedArtworks(this.artworks, this.evidence);

  final List<Artwork> artworks;
  final Map<String, ArtworkAccessEvidence> evidence;
}

/// Preserve access reasons before the SDK maps them to generic availability.
/// Artwork ordering, media mapping, and page parsing remain owned by the SDK.
final class ArtworkWebRepository {
  const ArtworkWebRepository(this.dio);

  final Dio dio;

  Future<WebRelatedArtworks> related({
    required Uri pageUri,
    required String deviationId,
    required String cookieHeader,
  }) async {
    if (pageUri.scheme != 'https' ||
        (pageUri.host != 'www.deviantart.com' &&
            pageUri.host != 'deviantart.com')) {
      throw ArgumentError.value(pageUri, 'pageUri', 'Not a DeviantArt page.');
    }
    final response = await dio.get<String>(
      pageUri.toString(),
      options: webPageOptions(cookieHeader),
    );
    return parseRelated(response.data ?? '', deviationId: deviationId);
  }

  static WebRelatedArtworks parseRelated(
    String html, {
    required String deviationId,
  }) {
    final artworks = WebMoreLikeThisFetcher.parseInitialState(
      html,
      deviationId: deviationId,
    );
    final rawById = <String, Map<Object?, Object?>>{};
    var usedCache = false;
    try {
      final cache = jsonParseAssignment(
        html,
        marker: 'window.__RCACHE__ = JSON.parse(',
        missingMessage: 'No related cache',
      );
      final related = cache['relatedContent'];
      final sections = related is Map ? related['relatedContent'] : null;
      if (sections is List) {
        usedCache = true;
        for (final section in sections) {
          if (section is! Map ||
              (section['contentType'] != 'gallery' &&
                  section['contentType'] != 'recommended')) {
            continue;
          }
          final deviations = section['deviations'];
          if (deviations is! List) continue;
          for (final raw in deviations) {
            if (raw is! Map) continue;
            final id = '${raw['deviationId'] ?? raw['deviationid']}';
            rawById.putIfAbsent(id, () => Map<Object?, Object?>.from(raw));
          }
        }
      }
    } on FormatException {
      // Older pages and partial streamed caches use normalized initial state.
    }
    if (!usedCache || artworks.any((art) => !rawById.containsKey(art.id))) {
      try {
        final initial = jsonParseAssignment(
          html,
          marker: 'window.__INITIAL_STATE__ = JSON.parse(',
          missingMessage: 'No initial state',
        );
        final entities = initial['@@entities'];
        final deviations = entities is Map ? entities['deviation'] : null;
        if (deviations is Map) {
          for (final entry in deviations.entries) {
            if (entry.value is Map) {
              rawById.putIfAbsent(
                '${entry.key}',
                () => Map<Object?, Object?>.from(entry.value as Map),
              );
            }
          }
        }
      } on FormatException {
        // Missing optional reason metadata must not discard parsed artwork.
      }
    }
    return WebRelatedArtworks(artworks, <String, ArtworkAccessEvidence>{
      for (final artwork in artworks)
        if (rawById[artwork.id] case final raw?)
          artwork.id: ArtworkAccessEvidence.fromWeb(
            raw,
            artwork,
            source: ArtworkAccessSource.webList,
          ),
    });
  }

  Future<Map<Object?, Object?>> init({
    required String deviationId,
    required String username,
    required String cookieHeader,
    required String csrfToken,
  }) async {
    final response = await dio.get<Object?>(
      'https://www.deviantart.com/_puppy/dadeviation/init',
      queryParameters: <String, Object?>{
        'deviationid': deviationId,
        'username': username,
        'type': 'art',
        'include_session': false,
        'mature_content': true,
        'csrf_token': csrfToken,
      },
      options: webSessionOptions(cookieHeader),
    );
    final body = response.data;
    final raw = body is Map ? body['deviation'] : null;
    if (raw is! Map || '${raw['deviationId']}' != deviationId) {
      throw const FormatException('Missing or mismatched deviation in init.');
    }
    return Map<Object?, Object?>.from(body as Map);
  }
}
