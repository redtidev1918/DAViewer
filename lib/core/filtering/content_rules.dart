import 'package:dakit_core/dakit_core.dart';

String normalizeTag(String value) =>
    value.trim().replaceFirst(RegExp(r'^#+'), '').toLowerCase();
String normalizeArtist(String value) =>
    value.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();
String artworkBlockKey(String value) {
  final text = value.trim();
  final uri = Uri.tryParse(text);
  if (uri != null && uri.hasScheme) {
    if (uri.host != 'www.deviantart.com' && uri.host != 'deviantart.com') {
      return '';
    }
    if (!uri.path.contains('/art/')) return '';
    return RegExp(r'-(\d+)$').firstMatch(uri.path)?.group(1) ?? '';
  }
  return RegExp(r'^(\d+|[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12})$')
          .hasMatch(text)
      ? text.toLowerCase()
      : '';
}

final class ContentRules {
  ContentRules({
    this.hideAi = false,
    Set<String> tags = const {},
    Set<String> artists = const {},
    Map<String, String> artworks = const {},
  }) : tags = Set.unmodifiable(tags),
       artists = Set.unmodifiable(artists),
       artworks = Map.unmodifiable(artworks);
  final bool hideAi;
  final Set<String> tags;
  final Set<String> artists;
  final Map<String, String> artworks;

  bool blocks(Artwork artwork, {bool? isAi}) =>
      (hideAi && isAi == true) ||
      artists.contains(normalizeArtist(artwork.author.username)) ||
      artwork.tags.any((tag) => tags.contains(normalizeTag(tag))) ||
      artworks.containsKey(artworkBlockKey(artwork.id)) ||
      artworks.containsKey(artworkBlockKey(artwork.pageUri.toString()));

  ContentRules copyWith({
    bool? hideAi,
    Set<String>? tags,
    Set<String>? artists,
    Map<String, String>? artworks,
  }) => ContentRules(
    hideAi: hideAi ?? this.hideAi,
    tags: tags ?? this.tags,
    artists: artists ?? this.artists,
    artworks: artworks ?? this.artworks,
  );
  Map<String, Object> toJson() => {
    'hideAi': hideAi,
    'tags': tags.toList(),
    'artists': artists.toList(),
    'artworks': artworks,
  };
  factory ContentRules.fromJson(Object? json) {
    if (json is! Map) return ContentRules();
    Set<String> names(Object? value, String Function(String) normalize) =>
        value is List
        ? value
              .whereType<String>()
              .map(normalize)
              .where((s) => s.isNotEmpty)
              .toSet()
        : {};
    final works = json['artworks'];
    return ContentRules(
      hideAi: json['hideAi'] == true,
      tags: names(json['tags'], normalizeTag),
      artists: names(json['artists'], normalizeArtist),
      artworks: {
        if (works is Map)
          for (final entry in works.entries)
            if (entry.key is String &&
                entry.value is String &&
                artworkBlockKey(entry.key as String).isNotEmpty)
              artworkBlockKey(entry.key as String): entry.value as String,
      },
    );
  }
}
