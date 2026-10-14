import 'dart:convert';

import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:dakit_web/dakit_web.dart';

/// A canonical empty description differs from an unavailable description.
/// Feed excerpts are always labelled as incomplete, including on fetch failure.
final class ArtworkDescription {
  const ArtworkDescription({
    this.html,
    this.text,
    this.isExcerpt = false,
    this.failureCategory,
    required this.source,
  });

  final String? html;
  final String? text;
  final bool isExcerpt;
  final String? failureCategory;
  final String source;
  bool get hasContent =>
      (html?.trim().isNotEmpty ?? false) || (text?.trim().isNotEmpty ?? false);

  factory ArtworkDescription.fromHtml(String html, {required String source}) =>
      ArtworkDescription(
        html: html,
        text: htmlToPlainText(html),
        source: source,
      );

  factory ArtworkDescription.fallback(Artwork? artwork, Object error) {
    final excerpt = artwork?.description;
    return ArtworkDescription(
      html: excerpt,
      text: excerpt == null ? null : htmlToPlainText(excerpt),
      isExcerpt: excerpt?.trim().isNotEmpty ?? false,
      failureCategory: error is FormatException
          ? 'invalid_payload'
          : 'request_failed',
      source: 'feed_excerpt',
    );
  }
}

/// Host adapter for the description omitted by DAKit's tags-only metadata API.
/// Contract: DeviantArt OpenAPI v1.20240701, captured 2026-10-14 from
/// https://deviantart.readme.io/reference/deviation_metadata .
final class ArtworkDescriptionRepository {
  const ArtworkDescriptionRepository(this.transport);
  final OfficialApiTransport transport;

  /// The description does not depend on optional UUID/media fields in init.
  /// Shape independently captured from live dadeviation/init on 2026-10-14.
  static ArtworkDescription parseWeb(Map<Object?, Object?> payload) {
    final deviation = payload['deviation'];
    final extended = deviation is Map ? deviation['extended'] : null;
    final description = extended is Map ? extended['descriptionText'] : null;
    final html = description is Map ? description['html'] : null;
    final markup = html is Map ? html['markup'] : null;
    final type = html is Map ? html['type'] : null;
    if (markup is! String) {
      throw const FormatException('Web description markup is missing.');
    }
    if (type == 'tiptap') {
      final decoded = jsonDecode(markup);
      final document = decoded is Map && decoded['document'] is Map
          ? decoded['document']
          : decoded;
      if (document is! Map || document['type'] != 'doc') {
        throw const FormatException('Invalid description document.');
      }
      // Derive the plain text from DAKit's own HTML rendering instead of
      // calling tiptapToPlainText: verified in dakit_web 0.3.0
      // lib/src/html_text.dart, _walkTiptap handles only `text`, `hardBreak`
      // and block nodes, so `da-mention`/`da-emote` inline nodes are dropped,
      // while _walkTiptapHtml renders mentions as visible `@name` anchors.
      // The 2026-10-14 captured specimen contains a real da-mention node.
      final html = tiptapToHtml(markup);
      return ArtworkDescription(
        html: html,
        text: htmlToPlainText(html),
        source: 'web_init_tiptap',
      );
    }
    if (type != 'writer') {
      throw const FormatException('Unsupported web description format.');
    }
    return ArtworkDescription.fromHtml(markup, source: 'web_init_writer');
  }

  Future<ArtworkDescription> get(String artworkId) async {
    final response = await transport.getJson(
      'deviation/metadata',
      query: <String, Object?>{
        'deviationids[]': <String>[artworkId],
        'mature_content': true,
      },
    );
    return parseMetadata(response, artworkId);
  }

  static ArtworkDescription parseMetadata(
    Map<String, Object?> response,
    String artworkId,
  ) {
    final rows = response['metadata'];
    if (rows is List) {
      for (final row in rows) {
        if (row is! Map ||
            row['deviationid'] is! String ||
            (row['deviationid'] as String).toLowerCase() !=
                artworkId.toLowerCase()) {
          continue;
        }
        final description = row['description'];
        if (description is String) {
          return ArtworkDescription.fromHtml(
            description,
            source: 'official_metadata',
          );
        }
        throw const FormatException('Metadata description field is missing.');
      }
    }
    throw const FormatException('Metadata artwork identity is missing.');
  }
}
