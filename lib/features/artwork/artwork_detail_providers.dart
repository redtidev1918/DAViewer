import 'dart:async';

import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/auth/session_state.dart';
import '../../core/auth/web_session_controller.dart';
import '../../core/auth/web_session_refresher.dart';
import '../../core/auth/web_session_status.dart'
    show webSessionRestrictionCheckProvider;
import '../../core/data/data_access.dart';
import '../../core/diagnostics/app_logger.dart';

import 'package:dakit_web/dakit_web.dart';

import '../../core/runtime/runtime_provider.dart';
import '../../core/search/interest_store.dart';
import 'artwork_store.dart';
import 'artwork_access.dart';
import 'artwork_access_controller.dart';
import 'artwork_access_state.dart';
import 'artwork_web_repository.dart';
import 'more_like_this_failure.dart';

/// True for numeric ids used by public website URLs (the OAuth API accepts
/// UUIDs, e.g. `97B067C2-…`).
bool isNumericDeviationId(String id) => RegExp(r'^\d+$').hasMatch(id);

/// The artwork's author when the detail was opened from a pasted link. Feed
/// items already carry the author, so this is only set by [ArtworkDetailScreen]
/// from the link's URL segment.
final linkUsernameProvider = StateProvider<String?>((ref) => null);

/// Retry session-dependent detail data after a confirmed web login.
final artworkSessionRecoveryProvider = Provider<void Function()>((ref) {
  return () {
    ref.invalidate(artworkMediaHydrationProvider);
    ref.read(artworkStoreProvider.notifier).clearMediaResolutions();
    ref.invalidate(webArtworkInitPayloadProvider);
    ref.invalidate(deviationInitProvider);
    ref.invalidate(artworkDetailProvider);
    ref.invalidate(originalFileProvider);
    ref.invalidate(journalHtmlProvider);
    ref.invalidate(moreLikeThisProvider);
  };
});

/// Resolves a numeric website id to the OAuth UUID plus the full description,
/// via the private web `dadeviation/init` endpoint and a public browser token.
/// Returns `null` for ids that are already OAuth UUIDs.
final webArtworkInitPayloadProvider = FutureProvider.autoDispose
    .family<Map<Object?, Object?>?, String>((ref, artworkId) async {
      if (!isNumericDeviationId(artworkId)) return null;
      final access = ref.read(artworkAccessControllerProvider.notifier);
      final epoch = access.sessionEpoch;
      var csrf = ref.watch(
        webSessionControllerProvider.select((web) => web.csrf),
      );
      if (csrf.isEmpty) {
        await ref.read(webSessionRefresherProvider).refresh();
        csrf = ref.read(webSessionControllerProvider).csrf;
      }
      if (csrf.isEmpty) {
        throw StateError('Public browser session is unavailable');
      }
      final webSession = ref.read(webSessionProvider);
      final cookieHeader = await webSession.cookieHeader();
      final cached = ref.read(artworkStoreProvider)[artworkId];
      final username =
          cached?.author.username ?? ref.read(linkUsernameProvider) ?? '';
      final runtime = ref.watch(runtimeProvider);
      final payload = await ArtworkWebRepository(runtime.dio!).init(
        deviationId: artworkId,
        username: username,
        cookieHeader: cookieHeader,
        csrfToken: csrf,
      );
      if (epoch == access.sessionEpoch) {
        final raw = Map<Object?, Object?>.from(payload['deviation'] as Map);
        if (raw['author'] is! Map) raw.remove('author');
        final mapped = WebDeviationMapper.mapDeviation(raw);
        final evidence = ArtworkAccessEvidence.fromWeb(
          raw,
          mapped,
          source: ArtworkAccessSource.webDetail,
        );
        access.observe(artworkId, evidence, epoch: epoch);
        if (evidence.requestsSessionCheck) {
          unawaited(ref.read(webSessionRestrictionCheckProvider)());
        }
      }
      return payload;
    });

final deviationInitProvider = FutureProvider.autoDispose
    .family<DeviationInit?, String>((ref, artworkId) async {
      final payload = await ref.watch(
        webArtworkInitPayloadProvider(artworkId).future,
      );
      return payload == null ? null : DeviationInitFetcher.parseInit(payload);
    });

/// The OAuth UUID for an artwork id (numeric web ids are resolved through
/// [deviationInitProvider]).
final artworkUuidProvider = FutureProvider.autoDispose.family<String, String>((
  ref,
  artworkId,
) async {
  if (!isNumericDeviationId(artworkId)) return artworkId;
  final init = await ref.watch(deviationInitProvider(artworkId).future);
  return init!.uuid;
});

/// The dates shown on the artwork detail screen: the original publish time and
/// — when the website reports one — the latest edit/update time. Web (numeric
/// id) works read both from `dadeviation/init`; official-API works only carry
/// [Artwork.publishedAt].
final class ArtworkDates {
  const ArtworkDates({this.publishedAt, this.updatedAt});

  final DateTime? publishedAt;
  final DateTime? updatedAt;

  /// The newest time known for the artwork (update time, falling back to
  /// publish time), used by the following-feed ordering.
  DateTime? get latestAt => updatedAt ?? publishedAt;
}

/// Merges the website's timestamps (when available) with the cached
/// [Artwork.publishedAt] from the feed.
final artworkDatesProvider = FutureProvider.autoDispose
    .family<ArtworkDates, String>((ref, artworkId) async {
      final artwork = await ref.watch(artworkDetailProvider(artworkId).future);
      var dates = ArtworkDates(publishedAt: artwork.publishedAt);
      if (isNumericDeviationId(artworkId)) {
        try {
          final init = await ref.watch(deviationInitProvider(artworkId).future);
          if (init != null) {
            dates = ArtworkDates(
              publishedAt: init.publishedAt ?? dates.publishedAt,
              updatedAt: init.updatedAt,
            );
          }
        } on Object {
          // Dates are supplementary; the detail page must stay usable even if
          // the init endpoint fails.
        }
      }
      return dates;
    });

/// Whether the signed-in user has favourited this artwork, read from the
/// mapped [Artwork.isFavourited] (no extra provider call needed).
final favouriteStatusProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, artworkId) async {
    final artwork = await ref.watch(artworkDetailProvider(artworkId).future);
    return artwork.isFavourited;
  },
);

/// Display-size assets for each additional page of a multi-image deviation
/// (web-feed items only; the official API no longer exposes these pages).
final additionalMediaProvider = FutureProvider.autoDispose
    .family<List<MediaAsset>, String>((ref, artworkId) async {
      if (!isNumericDeviationId(artworkId)) return const <MediaAsset>[];
      try {
        final init = await ref.watch(deviationInitProvider(artworkId).future);
        return init?.additionalMedia ?? const <MediaAsset>[];
      } on Object {
        return const <MediaAsset>[];
      }
    });

/// Original-size assets for each additional page of a multi-image deviation
/// (web-feed items only; official API no longer exposes these pages). Used by
/// the one-tap "download all pages" flow.
final additionalOriginalsProvider = FutureProvider.autoDispose
    .family<List<MediaAsset>, String>((ref, artworkId) async {
      if (!isNumericDeviationId(artworkId)) return const <MediaAsset>[];
      try {
        final init = await ref.watch(deviationInitProvider(artworkId).future);
        return init?.additionalOriginals ?? const <MediaAsset>[];
      } on Object {
        return const <MediaAsset>[];
      }
    });

/// Searchable tag names for an artwork. Web-feed items read tags from the
/// `dadeviation/init` endpoint; OAuth items from the mapped [Artwork.tags].
final artworkTagsProvider = FutureProvider.autoDispose
    .family<List<String>, String>((ref, artworkId) async {
      if (isNumericDeviationId(artworkId)) {
        try {
          final init = await ref.watch(deviationInitProvider(artworkId).future);
          return init?.tags ?? const <String>[];
        } on Object {
          return const <String>[];
        }
      }
      final artwork = await ref.watch(artworkDetailProvider(artworkId).future);
      final store = ref.read(artworkStoreProvider.notifier);
      final resolution = await resolveOfficialArtworkTags(
        artwork,
        alreadyResolved: store.hasResolvedTags(artworkId),
        fetchTags: () {
          final runtime = ref.read(runtimeProvider);
          return dataAccessFor(runtime).artworkTags(artworkId);
        },
      );
      if (resolution.isConfirmed) {
        store.setTags(artworkId, resolution.tags);
      }
      return resolution.tags;
    });

/// Official list endpoints often omit tags. Treat an empty feed tag list as
/// incomplete data and hydrate it from `deviation/metadata`, avoiding an extra
/// request for already-complete search/gallery items.
final class ArtworkTagResolution {
  const ArtworkTagResolution({required this.tags, required this.isConfirmed});

  final List<String> tags;

  /// True when tags came from a non-sparse object or a successful canonical
  /// detail request. False means the empty list is only a failure fallback and
  /// must not suppress a later retry.
  final bool isConfirmed;
}

Future<ArtworkTagResolution> resolveOfficialArtworkTags(
  Artwork artwork, {
  bool alreadyResolved = false,
  required Future<List<String>> Function() fetchTags,
}) async {
  if (artwork.tags.isNotEmpty || alreadyResolved) {
    return ArtworkTagResolution(tags: artwork.tags, isConfirmed: true);
  }
  try {
    final tags = await fetchTags();
    return ArtworkTagResolution(tags: tags, isConfirmed: true);
  } on Object catch (error) {
    debugPrint('[tags] metadata hydration failed for ${artwork.id}: $error');
    return const ArtworkTagResolution(tags: <String>[], isConfirmed: false);
  }
}

/// The full rich-text HTML body of a journal deviation, fetched from the web
/// `dadeviation/init` endpoint (`type=journal`) using the embedded web session.
/// The official API only exposes a truncated excerpt for journals; the complete
/// tiptap document (inline formatting + embedded images) lives here.
final journalHtmlProvider = FutureProvider.autoDispose.family<String?, String>((
  ref,
  artworkId,
) async {
  final cached = ref.read(artworkStoreProvider)[artworkId];
  // Text works come in two shapes: journal posts (`/journal/` URLs) and
  // literature deviations (`/art/...` URLs with no image media — REG-012).
  // Pasted links have no cached artwork yet, so their type is unknown until
  // the init round-trip; attempt the text fetch there and let the endpoint
  // answer null for image works.
  final mightBeText = cached == null
      ? isNumericDeviationId(artworkId) &&
            (ref.read(linkUsernameProvider)?.isNotEmpty ?? false)
      : cached.pageUri.path.contains('/journal/') || cached.media.isEmpty;
  if (!mightBeText) {
    return null;
  }
  final match = RegExp(r'-(\d+)/?$').firstMatch(cached?.pageUri.path ?? '');
  final numericId =
      match?.group(1) ?? (isNumericDeviationId(artworkId) ? artworkId : null);
  if (numericId == null) return null;
  var csrf = ref.watch(webSessionControllerProvider.select((web) => web.csrf));
  if (csrf.isEmpty) {
    await ref.read(webSessionRefresherProvider).refresh();
    csrf = ref.read(webSessionControllerProvider).csrf;
  }
  if (csrf.isEmpty) return null;
  final webSession = ref.read(webSessionProvider);
  final cookieHeader = await webSession.cookieHeader();
  final runtime = ref.watch(runtimeProvider);
  final username =
      cached?.author.username ?? ref.read(linkUsernameProvider) ?? '';
  if (username.isEmpty) return null;
  return JournalContentFetcher(runtime.dio!).fetchHtml(
    deviationId: numericId,
    username: username,
    cookieHeader: cookieHeader,
    csrfToken: csrf,
  );
});

/// Resolves an artwork by id, preferring the in-memory [artworkStoreProvider]
/// cache so web-feed items (which use a numeric id the OAuth API cannot
/// resolve) render without a failing `deviation/{id}` round-trip.
final artworkDetailProvider = FutureProvider.autoDispose
    .family<Artwork, String>((ref, artworkId) async {
      final cached = ref.read(artworkStoreProvider)[artworkId];
      if (cached != null) {
        final access = ref
            .read(artworkAccessControllerProvider.notifier)
            .forId(artworkId);
        final artwork =
            (needsArtworkMediaHydration(cached) || access.needsResolution)
            ? await ref.watch(artworkMediaHydrationProvider(artworkId).future)
            : cached;
        // Viewing a work is an interest signal for the recommended tags.
        unawaited(InterestStore.recordTags(artwork.tags));
        return artwork;
      }
      final runtime = ref.watch(runtimeProvider);
      // Numeric website ids (pasted links) must be resolved to the OAuth UUID
      // first — the official deviation/{id} endpoint rejects numeric ids with
      // "api endpoint not found". Feed items skip this because they are cached.
      final uuid = await ref.watch(artworkUuidProvider(artworkId).future);
      final artwork = await dataAccessFor(runtime).artworkById(uuid);
      ref.read(artworkStoreProvider.notifier).putAll(<Artwork>[artwork]);
      unawaited(InterestStore.recordTags(artwork.tags));
      return artwork;
    });

/// Rechecks suspicious web previews through the same signed-in official API as
/// artist galleries. Failures preserve the server preview and its restrictions.
final artworkMediaHydrationProvider = FutureProvider.autoDispose
    .family<Artwork, String>((ref, artworkId) async {
      final store = ref.read(artworkStoreProvider.notifier);
      final cached = store.byId(artworkId)!;
      if (store.hasResolvedMedia(artworkId)) return cached;
      final access = ref.read(artworkAccessControllerProvider.notifier);
      final epoch = access.sessionEpoch;
      final lease = ref.keepAlive();
      var disposed = false;
      ref.onDispose(() => disposed = true);
      try {
        // Cross-provider mutations start after provider initialization.
        await Future<void>.value();
        if (disposed || epoch != access.sessionEpoch) return cached;
        access.beginResolution(artworkId);
        // Content evidence requests verification, never an auth verdict.
        final initialEvidence = access.forId(artworkId).mainEvidence;
        if (initialEvidence?.requestsSessionCheck ?? true) {
          unawaited(ref.read(webSessionRestrictionCheckProvider)());
        }
        final runtime = ref.read(runtimeProvider);
        if (runtime.transport == null) {
          throw StateError('Official media lookup is unavailable');
        }
        final uuid = await ref.watch(artworkUuidProvider(artworkId).future);
        final detail = await dataAccessFor(runtime).artworkById(uuid);
        if (disposed || epoch != access.sessionEpoch) return cached;
        // Never let a misresolved ID replace a different recommendation.
        if (detail.pageUri.path != cached.pageUri.path ||
            detail.author.username.toLowerCase() !=
                cached.author.username.toLowerCase()) {
          throw const FormatException('Canonical artwork identity mismatch');
        }
        final evidence = ArtworkAccessEvidence.fromArtwork(
          detail,
          source: ArtworkAccessSource.officialDetail,
        );
        if (!evidence.isConclusive) {
          throw const FormatException('Canonical media access is inconclusive');
        }
        final resolved = detail.copyWith(id: artworkId);
        store.setResolvedMedia(resolved, evidence: evidence, epoch: epoch);
        return store.byId(artworkId) ?? cached;
      } on Object catch (error) {
        debugPrint('[media] detail hydration failed for $artworkId: $error');
        if (!disposed && epoch == access.sessionEpoch) {
          // Mature multi-image works can be absent from the OAuth endpoint.
          // A complete web detail is an independent canonical media source.
          Map<Object?, Object?>? payload;
          if (isNumericDeviationId(artworkId)) {
            try {
              payload = await ref.watch(
                webArtworkInitPayloadProvider(artworkId).future,
              );
            } on Object {
              // Neither canonical source was able to answer this lookup.
            }
          }
          if (disposed || epoch != access.sessionEpoch) return cached;
          final raw = payload?['deviation'];
          if (raw is Map && raw['author'] is Map) {
            final detail = WebDeviationMapper.mapDeviation(
              Map<Object?, Object?>.from(raw),
            );
            final webEvidence = ArtworkAccessEvidence.fromWeb(
              Map<Object?, Object?>.from(raw),
              detail,
              source: ArtworkAccessSource.webDetail,
            );
            if (detail.pageUri.path == cached.pageUri.path &&
                detail.author.username.toLowerCase() ==
                    cached.author.username.toLowerCase() &&
                webEvidence.isConclusive) {
              store.setResolvedMedia(
                detail.copyWith(id: artworkId),
                evidence: webEvidence,
                epoch: epoch,
              );
              return store.byId(artworkId) ?? cached;
            }
          }
          access.resolutionFailed(artworkId, epoch);
        }
        return cached;
      } finally {
        lease.close();
      }
    });

/// The authoritative result of probing DeviantArt's original-download
/// endpoint. [lookupError] is reserved for transient failures (network/server/
/// session resolution); expected permission denials are represented by the
/// typed [MediaAsset.availability] and [MediaAsset.availabilityReason].
final class OriginalFileResolution {
  const OriginalFileResolution({required this.asset, this.lookupError});

  final MediaAsset asset;
  final Object? lookupError;
}

final originalFileProvider = FutureProvider.autoDispose
    .family<OriginalFileResolution, String>((ref, artworkId) async {
      final cached = ref.read(artworkStoreProvider)[artworkId];
      // Journals/literature have no downloadable original — don't hit the
      // download endpoint (it 400s for journals). Text-only posts short-circuit
      // here too.
      final isJournal =
          cached != null && cached.pageUri.path.contains('/journal/');
      if (cached != null && (cached.media.isEmpty || isJournal)) {
        return OriginalFileResolution(
          asset: MediaAsset(
            id: '$artworkId:original',
            kind: MediaKind.unknown,
            role: MediaRole.original,
            availability: MediaAvailability.missing,
          ),
        );
      }
      final runtime = ref.watch(runtimeProvider);
      try {
        // Web recommendation items use numeric ids, while the official
        // download endpoint only accepts the OAuth UUID. Always probe the
        // endpoint instead of trusting a cached media URL: entitlement and
        // free-download limits are user-specific and can change at any time.
        final uuid = await ref.watch(artworkUuidProvider(artworkId).future);
        final asset = await dataAccessFor(runtime).originalFile(uuid);
        return OriginalFileResolution(asset: asset);
      } on Object catch (error) {
        // Never let a download-availability lookup take down the whole detail
        // page. Expected 4xx denials are already converted into typed assets by
        // DAKit; only transient failures reach here and remain distinguishable
        // so the UI can say that availability could not be verified and offer
        // a retry instead of falsely claiming the artwork is not downloadable.
        debugPrint('[orig] download lookup failed: $error');
        return OriginalFileResolution(
          asset: MediaAsset(
            id: '$artworkId:original',
            kind: MediaKind.unknown,
            role: MediaRole.original,
            availability: MediaAvailability.unavailable,
          ),
          lookupError: error,
        );
      }
    });

/// The full author description as plain text. For web-feed items it comes from
/// `dadeviation/init`; for OAuth items from `deviation/content`. Falls back to
/// the artwork's short excerpt when the full description is empty.
final artworkDescriptionProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, artworkId) async {
      final cached = ref.read(artworkStoreProvider)[artworkId];
      if (isNumericDeviationId(artworkId)) {
        try {
          final init = await ref.watch(deviationInitProvider(artworkId).future);
          final text = init?.description;
          if (text != null && text.trim().isNotEmpty) return text;
        } on Object catch (error) {
          debugPrint('[desc] init fetch failed: $error');
        }
        return cached?.description;
      }
      final runtime = ref.watch(runtimeProvider);
      final artwork = await ref.watch(artworkDetailProvider(artworkId).future);
      try {
        final content = await OfficialArtworkContentRepository(
          runtime.transport!,
        ).get(artworkId);
        final html = content.html;
        debugPrint('[desc] content html len=${html?.length ?? 0}');
        if (html != null && html.trim().isNotEmpty) {
          return htmlToPlainText(html);
        }
        // The rendered `html` is empty for some deviations; the description
        // then lives in the tiptap `original_markup` document.
        final markup = content.originalMarkup;
        if (markup != null && markup.trim().isNotEmpty) {
          final text = tiptapToPlainText(markup);
          debugPrint('[desc] tiptap len=${text.length}');
          if (text.isNotEmpty) return text;
        }
      } on Object catch (error) {
        debugPrint('[desc] content fetch failed: $error');
      }
      return artwork.description;
    });

/// The full author description as an HTML fragment (rich text, preserving
/// links and inline formatting). Mirrors [artworkDescriptionProvider] but keeps
/// the renderable markup instead of collapsing it to plain text.
final artworkDescriptionHtmlProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, artworkId) async {
      if (isNumericDeviationId(artworkId)) {
        try {
          final init = await ref.watch(deviationInitProvider(artworkId).future);
          final html = init?.descriptionHtml;
          if (html != null && html.trim().isNotEmpty) return html;
        } on Object {
          // Fall through to null; plain text remains available.
        }
        return null;
      }
      final runtime = ref.watch(runtimeProvider);
      try {
        final content = await OfficialArtworkContentRepository(
          runtime.transport!,
        ).get(artworkId);
        final html = content.html;
        if (html != null && html.trim().isNotEmpty) return html;
        final markup = content.originalMarkup;
        if (markup != null && markup.trim().isNotEmpty) {
          final converted = tiptapToHtml(markup);
          return converted.isNotEmpty ? converted : markup;
        }
      } on Object {
        // Fall through to null.
      }
      return null;
    });

/// "More Like This" — the current website's organic related blocks provide the
/// artwork, while the official preview endpoint provides the featured/suggested
/// collections (the website does not expose those groups). Both are fetched and
/// merged so the collections rails show consistently instead of disappearing
/// whenever the website source happens to return artwork.
final moreLikeThisProvider = FutureProvider.autoDispose
    .family<MoreLikeThisResult, String>((ref, artworkId) async {
      final runtime = ref.watch(runtimeProvider);
      final access = ref.read(artworkAccessControllerProvider.notifier);
      final epoch = access.sessionEpoch;
      final artwork = await ref.watch(artworkDetailProvider(artworkId).future);
      final numericId = isNumericDeviationId(artworkId)
          ? artworkId
          : RegExp(r'-(\d+)/?$').firstMatch(artwork.pageUri.path)?.group(1);

      // Website related artwork (current, may diverge from the legacy preview).
      List<Artwork> webArtworks = const <Artwork>[];
      Object? websiteError;
      if (numericId != null) {
        try {
          final webSession = ref.read(webSessionProvider);
          final cookieHeader = await webSession.cookieHeader();
          final batch = await ArtworkWebRepository(runtime.dio!).related(
            pageUri: artwork.pageUri,
            deviationId: numericId,
            cookieHeader: cookieHeader,
          );
          final artworks = batch.artworks;
          if (artworks.isNotEmpty) {
            if (epoch != access.sessionEpoch) {
              return const MoreLikeThisResult(artworks: <Artwork>[]);
            }
            ref.read(artworkStoreProvider.notifier).putAll(artworks);
            for (final entry in batch.evidence.entries) {
              access.observe(entry.key, entry.value, epoch: epoch);
            }
            webArtworks = await hydrateRelatedArtworkMedia(
              artworks,
              needsHydration: (artwork) =>
                  needsArtworkMediaHydration(artwork) ||
                  access.forId(artwork.id).needsResolution,
              hydrate: (artwork) =>
                  ref.watch(artworkMediaHydrationProvider(artwork.id).future),
            );
            debugPrint(
              '[moreLikeThis] website source returned ${artworks.length} '
              'items for $numericId',
            );
          } else {
            debugPrint('[moreLikeThis] website source empty for $numericId');
          }
        } on Object catch (error) {
          websiteError = error;
          debugPrint(
            '[moreLikeThis] website source failed for $numericId: $error',
          );
        }
      }

      try {
        final uuid = await ref.watch(artworkUuidProvider(artworkId).future);
        final result = await OfficialDiscoveryRepository(runtime.transport!)
            .moreLikeThis(uuid);
        if (epoch != access.sessionEpoch) {
          return const MoreLikeThisResult(artworks: <Artwork>[]);
        }
        ref.read(artworkStoreProvider.notifier).putAll(result.artworks);
        debugPrint(
          '[moreLikeThis] OAuth source returned ${result.artworks.length} '
          'items for $uuid',
        );
        return mergeMoreLikeThisResult(
          official: result,
          webArtworks: webArtworks,
          websiteError: websiteError,
        );
      } on MoreLikeThisFailure {
        rethrow;
      } on Object catch (officialError) {
        // The official source can be unreachable for numeric web-feed ids
        // without a web session (no UUID to resolve). Keep the website artwork
        // in that case, and only surface a combined failure when both are gone.
        if (webArtworks.isNotEmpty) {
          return MoreLikeThisResult(artworks: webArtworks);
        }
        throw MoreLikeThisFailure(
          websiteError: websiteError,
          officialError: officialError,
        );
      }
    });

/// Only suspicious previews need extra lookups; limit concurrency while keeping
/// website order and allowing an individual lookup to fail independently.
Future<List<Artwork>> hydrateRelatedArtworkMedia(
  List<Artwork> artworks, {
  required Future<Artwork> Function(Artwork artwork) hydrate,
  bool Function(Artwork artwork)? needsHydration,
}) async {
  final result = List<Artwork>.of(artworks);
  final indices = <int>[
    for (var i = 0; i < artworks.length; i++)
      if ((needsHydration ?? needsArtworkMediaHydration)(artworks[i])) i,
  ];
  for (var start = 0; start < indices.length; start += 3) {
    await Future.wait(
      indices.skip(start).take(3).map((index) async {
        try {
          result[index] = await hydrate(artworks[index]);
        } on Object {
          // Keep the original server-provided preview on a failed lookup.
        }
      }),
    );
  }
  return List<Artwork>.unmodifiable(result);
}

/// Merges the website's related artwork with the official preview's
/// collections (and its artwork as the fallback). Website artwork wins when
/// present, while collections always come from the official source.
///
/// An empty result is authoritative only when the website source also completed
/// successfully. If the website failed or was only partially hydrated, an empty
/// success would falsely tell the user that no recommendations exist even
/// though the browser may be showing them.
MoreLikeThisResult mergeMoreLikeThisResult({
  required MoreLikeThisResult official,
  required List<Artwork> webArtworks,
  required Object? websiteError,
}) {
  // Only show items with a thumbnail in the related grid; journals and other
  // media-less posts would otherwise render as empty image cards.
  final artworks = (webArtworks.isNotEmpty ? webArtworks : official.artworks)
      .where((artwork) => artwork.media.isNotEmpty)
      .toList(growable: false);

  // The preview can list the same collection in both groups; keep it only in
  // "Featured" (the more specific claim) and drop it from "Suggested".
  final featuredIds = official.featuredInCollections
      .map((group) => group.collection.folderId)
      .toSet();
  final suggested = official.suggestedCollections
      .where((group) => !featuredIds.contains(group.collection.folderId))
      .toList(growable: false);

  final merged = MoreLikeThisResult(
    artworks: List<Artwork>.unmodifiable(artworks),
    featuredInCollections: official.featuredInCollections,
    suggestedCollections: List<CollectionWithDeviations>.unmodifiable(
      suggested,
    ),
  );
  if (merged.artworks.isEmpty && websiteError != null) {
    throw MoreLikeThisFailure(websiteError: websiteError, officialError: null);
  }
  return merged;
}

/// The author's other recent works, shown as a "More from this artist" rail
/// below the artwork. Reads the first page of the author's gallery and excludes
/// the current artwork. Failures are swallowed so the rail simply hides instead
/// of taking down the whole detail page.
final moreFromArtistProvider = FutureProvider.autoDispose
    .family<List<Artwork>, String>((ref, artworkId) async {
      final runtime = ref.watch(runtimeProvider);
      final artwork = await ref.watch(artworkDetailProvider(artworkId).future);
      final username = artwork.author.username;
      if (username.isEmpty) return const <Artwork>[];
      try {
        final page = await dataAccessFor(runtime)
            .gallery(username, const PageRequest(limit: 24));
        final visible = List<Artwork>.unmodifiable(
          page.items.where(
            (item) => item.id != artworkId && item.media.isNotEmpty,
          ),
        );
        AppLogger.instance.info(
          'more-from-artist',
          'gallery/all raw=${page.items.length} final=${visible.length}',
        );
        return visible;
      } on Object {
        // Best-effort rail: an unavailable gallery is not an error for the page.
        return const <Artwork>[];
      }
    });

/// Artists whose work appears in the "More Like This" set — DeviantArt's
/// recommendation engine surfaces similar artists through their artwork, so the
/// authors of the related deviations are the honest "similar artists" signal.
final similarArtistsProvider = FutureProvider.autoDispose
    .family<List<UserProfile>, String>((ref, artworkId) async {
      final seed = await ref.watch(artworkDetailProvider(artworkId).future);
      final related = await ref.watch(moreLikeThisProvider(artworkId).future);
      return similarArtistsFrom(
        seedAuthor: seed.author,
        related: related.artworks,
      );
    });

/// De-duplicated authors of [related] artworks, excluding [seedAuthor].
List<UserProfile> similarArtistsFrom({
  required UserProfile seedAuthor,
  required Iterable<Artwork> related,
}) {
  final seen = <String>{seedAuthor.username};
  final artists = <UserProfile>[];
  for (final artwork in related) {
    final author = artwork.author;
    if (author.username.isEmpty || !seen.add(author.username)) continue;
    artists.add(author);
  }
  return List<UserProfile>.unmodifiable(artists);
}
