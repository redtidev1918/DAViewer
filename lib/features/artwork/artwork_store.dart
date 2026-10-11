import 'package:dakit_core/dakit_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'artwork_access.dart';
import 'artwork_access_controller.dart';
import 'artwork_access_state.dart';

/// Whether the canonical source has already told us a list-like field's
/// real value, as opposed to the field being missing from a sparse payload.
enum HydrationStatus { unknown, resolved, confirmedEmpty }

/// In-memory cache of [Artwork] objects that have already been loaded by a
/// feed.
///
/// Public website payloads can identify deviations by a numeric id
/// (`1365198134`) that the official OAuth API cannot resolve
/// (`deviation/{id}` only accepts UUIDs). Adapters therefore stash their fully
/// mapped [Artwork] here and the detail screen renders straight from the cache
/// instead of round-tripping through an OAuth call that would 404.
final artworkStoreProvider =
    NotifierProvider<ArtworkStore, Map<String, Artwork>>(ArtworkStore.new);

final class ArtworkStore extends Notifier<Map<String, Artwork>> {
  static const int _maxEntries = 512;
  final Set<String> _resolvedTagIds = <String>{};

  @override
  Map<String, Artwork> build() {
    _resolvedTagIds.clear();
    return <String, Artwork>{};
  }

  Artwork? byId(String id) => state[id];

  bool hasResolvedMedia(String id) =>
      ref.read(artworkAccessControllerProvider.notifier).forId(id).phase ==
      ArtworkAccessPhase.confirmed;

  /// Access results belong to the session that fetched them.
  void clearMediaResolutions() =>
      ref.read(artworkAccessControllerProvider.notifier).resetSession();

  /// A signed-in detail response may correct a provisional list-level gate.
  /// Keep that media when the same sparse recommendation is cached again on tap.
  bool setResolvedMedia(
    Artwork artwork, {
    required ArtworkAccessEvidence evidence,
    required int epoch,
  }) {
    final access = ref.read(artworkAccessControllerProvider.notifier);
    if (epoch != access.sessionEpoch || !evidence.isConclusive) return false;
    final cached = state[artwork.id];
    if (cached == null) return false;
    access.confirm(artwork.id, evidence, epoch);
    final gate = evidence.viewGate;
    final incoming = gate == null ? artwork : applyViewLock(artwork, gate);
    state = <String, Artwork>{
      ...state,
      artwork.id: mergeArtwork(
        cached: cached,
        incoming: incoming,
        accessResolved: true,
      ),
    };
    return true;
  }

  /// Whether the canonical detail endpoint has already confirmed this
  /// artwork's tags. This distinguishes a genuinely tagless work from a
  /// compact feed item whose `tags` field was omitted upstream.
  bool hasResolvedTags(String id) => tagStatus(id) != HydrationStatus.unknown;

  /// Tags from sparse list payloads are `unknown`; a canonical detail response
  /// is either `resolved` (non-empty) or `confirmedEmpty`.
  HydrationStatus tagStatus(String id) {
    if (_resolvedTagIds.contains(id)) {
      return (state[id]?.tags.isNotEmpty ?? false)
          ? HydrationStatus.resolved
          : HydrationStatus.confirmedEmpty;
    }
    return HydrationStatus.unknown;
  }

  void putAll(Iterable<Artwork> artworks) {
    var next = Map<String, Artwork>.of(state);
    for (final artwork in artworks) {
      if (artwork.id.isEmpty) continue;
      final cached = next[artwork.id];
      ref
          .read(artworkAccessControllerProvider.notifier)
          .observe(artwork.id, ArtworkAccessEvidence.fromArtwork(artwork));
      // List endpoints are allowed to return sparse artwork objects. Never let
      // a later feed refresh erase tags that the canonical detail endpoint has
      // already hydrated.
      final incoming = cached != null && hasResolvedMedia(artwork.id)
          ? artwork.copyWith(
              media: cached.media,
              downloadAvailability: cached.downloadAvailability,
              isDownloadable: cached.isDownloadable,
            )
          : artwork;
      next[artwork.id] = mergeArtwork(cached: cached, incoming: incoming);
      if (artwork.tags.isNotEmpty) _resolvedTagIds.add(artwork.id);
    }
    if (next.length > _maxEntries) {
      final entries = next.entries.toList(growable: false);
      next = Map<String, Artwork>.fromEntries(
        entries.skip(entries.length - _maxEntries),
      );
      _resolvedTagIds.removeWhere((id) => !next.containsKey(id));
      ref
          .read(artworkAccessControllerProvider.notifier)
          .retainIds(next.keys.toSet());
    }
    state = next;
  }

  /// Records the canonical tag result, including a confirmed empty list.
  void setTags(String id, List<String> tags) {
    final artwork = state[id];
    if (artwork == null) return;
    _resolvedTagIds.add(id);
    final normalized = List<String>.unmodifiable(tags);
    if (_sameStrings(artwork.tags, normalized)) return;
    state = <String, Artwork>{...state, id: artwork.copyWith(tags: normalized)};
  }

  /// Updates a cached artwork's favourite flag so the detail screen reflects a
  /// favourite/unfavourite action without a network round-trip.
  void setFavourite(String id, bool favourited) {
    final artwork = state[id];
    if (artwork == null) return;
    state = <String, Artwork>{
      ...state,
      id: artwork.copyWith(isFavourited: favourited),
    };
  }
}

/// The single merge rule for sparse list payloads vs a hydrated detail/web
/// result:
/// - a later empty-tags payload never erases already-known tags;
/// - a later payload that carried no access metadata never erases a confirmed
///   view/download gate (e.g. subscription-only art seen in the feed). Missing
///   gate info means "unknown", never "known available".
Artwork mergeArtwork({
  Artwork? cached,
  required Artwork incoming,
  bool accessResolved = false,
}) {
  if (cached == null) return incoming;
  var merged = incoming;
  if (merged.tags.isEmpty && cached.tags.isNotEmpty) {
    merged = merged.copyWith(tags: cached.tags);
  }
  final cachedLock = artworkViewLock(cached);
  if (!accessResolved &&
      cachedLock != null &&
      artworkViewLock(merged) == null) {
    merged = applyViewLock(merged, cachedLock);
  }
  return merged;
}

/// Re-applies a confirmed gate to an artwork whose later payload dropped the
/// access metadata. Gates the first available preview asset (so the card and
/// detail header keep their lock) and the download availability.
Artwork applyViewLock(Artwork artwork, MediaAvailability gate) {
  var applied = false;
  final media = <MediaAsset>[];
  for (final asset in artwork.media) {
    if (!applied &&
        asset.role == MediaRole.preview &&
        asset.availability == MediaAvailability.available) {
      media.add(_withAvailability(asset, gate));
      applied = true;
    } else {
      media.add(asset);
    }
  }
  return artwork.copyWith(
    media: List<MediaAsset>.unmodifiable(media),
    downloadAvailability: gate,
  );
}

MediaAsset _withAvailability(MediaAsset asset, MediaAvailability availability) {
  return MediaAsset(
    id: asset.id,
    kind: asset.kind,
    role: asset.role,
    availability: availability,
    uri: asset.uri,
    mimeType: asset.mimeType,
    filename: asset.filename,
    byteLength: asset.byteLength,
    width: asset.width,
    height: asset.height,
    duration: asset.duration,
    availabilityReason: asset.availabilityReason,
  );
}

bool _sameStrings(List<String> left, List<String> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
