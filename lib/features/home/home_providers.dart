import 'package:dakit_flutter/dakit_flutter.dart' hide WebSession;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/web_session_controller.dart';
import '../../core/auth/web_session_refresher.dart';
import '../../core/auth/web_session_status.dart';

import 'package:dakit_web/dakit_web.dart';

import '../../core/diagnostics/app_logger.dart';
import '../../core/feed/artwork_feed_controller.dart';
import '../../core/runtime/runtime_provider.dart';
import '../artwork/artwork_access.dart';
import '../artwork/artwork_store.dart';

int _personalizedProviderSeq = 0;

/// The website-personalized `rfy/deviations` recommendation feed, fetched with
/// the embedded WebView's web session (Cookie + CSRF). Requires a signed-in web
/// session and rebuilds when the web session identity changes.
///
/// A persisted session can be stale after a restart, so a failed fetch refreshes
/// the CSRF once from the stored cookies before giving up.
final personalizedFeedProvider =
    StateNotifierProvider<ArtworkFeedController, ArtworkFeedState>((ref) {
      final providerId = ++_personalizedProviderSeq;
      AppLogger.instance.info(
        'home',
        'personalized provider created id=$providerId',
      );
      final runtime = ref.watch(runtimeProvider);
      // Request execution reads the current cookie snapshot; it must not make
      // the feed provider lifecycle depend on browser-session churn (csrf,
      // cookie refresh, metadata).
      final webSession = ref.read(webSessionProvider);
      ref.watch(
        webSessionControllerProvider.select(personalizedFeedSessionIdentity),
      );
      final controller = ArtworkFeedController((request) async {
        AppLogger.instance.info(
          'home',
          'personalized feed fetch '
              'reason=${request.cursor == null ? 'initial_or_refresh' : 'pagination'} '
              'cursor=${request.cursor ?? 'initial'}',
        );
        final dio = runtime.dio;
        if (dio == null) {
          throw const DAKitException(
            kind: DAKitFailureKind.configuration,
            code: 'app.runtime.dio',
            message: 'The network layer is not available.',
          );
        }
        // Gate on the WebView-confirmed session, not a WAF-sensitive Dio home
        // probe on every request. A bare probe that reports anonymous is not
        // proof the WebView signed out; a confirmed session proceeds to the
        // actual rfy fetch. Explicit Retry still re-runs the server check.
        final webSessionState = ref.read(webSessionControllerProvider);
        if (webSessionState.isLoggedIn != true ||
            webSessionState.username.trim().isEmpty) {
          AppLogger.instance.warning(
            'home',
            'web session not confirmed; showing web-session notice',
          );
          throw const DAKitException(
            kind: DAKitFailureKind.authentication,
            code: 'web.session.unavailable',
            message: 'The personalized feed requires a signed-in web session.',
          );
        }
        AppLogger.instance.info(
          'home',
          'web session confirmed: ${webSessionState.username}',
        );
        var csrf = ref.read(webSessionControllerProvider).csrf;
        var cookieHeader = await webSession.cookieHeader();
        var page = await _tryFetchRfy(dio, csrf, cookieHeader, request);
        if (page == null) {
          // An app update can clear the live WebView cookie store even though
          // the persisted snapshot and OAuth identity survive. The startup
          // restore may have raced WebView readiness, so retry it before the
          // headless CSRF refresh.
          if (cookieHeader.isEmpty) {
            await ref
                .read(webSessionControllerProvider.notifier)
                .restorePersistedCookies();
            cookieHeader = await webSession.cookieHeader();
          }
          // Stale session after a restart: re-read the CSRF from the persisted
          // cookies (headless page load) and retry once.
          await ref.read(webSessionRefresherProvider).refresh();
          csrf = ref.read(webSessionControllerProvider).csrf;
          cookieHeader = await webSession.cookieHeader();
          page = await _tryFetchRfy(dio, csrf, cookieHeader, request);
        }
        if (page == null) {
          throw const DAKitException(
            kind: DAKitFailureKind.authentication,
            code: 'web.session.unavailable',
            message: 'The personalized feed requires a signed-in web session.',
          );
        }
        // The actual rfy request is stronger evidence than the separate bare
        // home-page probe: DeviantArt has just accepted this Cookie session and
        // returned personalized data. Mark it healthy so a WAF-served anonymous
        // verifier answer cannot turn into a misleading web-login prompt.
        final username = webSessionState.username.trim();
        final sessionStatus = ref.read(webSessionStatusProvider);
        if (!(sessionStatus.isHealthy &&
            sessionStatus.serverUsername.trim().toLowerCase() ==
                username.toLowerCase())) {
          ref
              .read(webSessionStatusProvider.notifier)
              .markHealthy(serverUsername: username);
        }
        ref.read(artworkStoreProvider.notifier).putAll(page.items);
        return page;
      });
      AppLogger.instance.info(
        'home',
        'personalized controller created provider=$providerId',
      );
      return controller;
    });

/// Only account identity changes should rebuild the recommendation feed.
///
/// Website metadata requests can rotate the CSRF token while an artwork detail
/// is open. Treating that short-lived token as provider identity would recreate
/// the controller and replace the list behind the detail route, so returning to
/// recommendations would appear to refresh unexpectedly. Fetches still read the
/// latest CSRF directly from [webSessionControllerProvider].
(bool?, String) personalizedFeedSessionIdentity(WebSessionState web) =>
    (web.isLoggedIn, web.username);

/// Fetches one rfy page, or `null` when the web session is missing or the
/// request failed (the caller then refreshes the session and retries).
Future<Page<Artwork>?> _tryFetchRfy(
  Dio dio,
  String csrf,
  String cookieHeader,
  PageRequest request,
) async {
  final logger = AppLogger.instance;
  if (csrf.isEmpty || cookieHeader.isEmpty) {
    logger.warning(
      'home',
      'rfy skipped: csrf=${csrf.isEmpty ? 'missing' : 'ok'} '
          'cookie=${cookieHeader.isEmpty ? 'missing' : 'ok'}',
    );
    return null;
  }
  final stopwatch = Stopwatch()..start();
  try {
    final page = await RfyFeedFetcher(dio).fetch(
      cookieHeader: cookieHeader,
      csrfToken: csrf,
      cursor: request.cursor,
    );
    // DeviantArt gates paid/blocked works by serving blurred Wix transforms
    // (e.g. `blur_30`) rather than an explicit feed field, so `gated` alone
    // can read 0 on a stream that still contains locked previews. Log both so
    // a real run can tell "no locked works in this page" from "parser misses
    // the signal".
    final blurred = page.items.where((artwork) {
      return artwork.media.any(
        (asset) =>
            asset.role == MediaRole.preview &&
            asset.uri != null &&
            asset.uri.toString().contains('blur_'),
      );
    }).length;
    logger.info(
      'home',
      'personalized feed success elapsedMs=${stopwatch.elapsedMilliseconds} '
          'cursor=${request.cursor ?? 'initial'} '
          'items=${page.items.length} '
          'gated=${page.items.where((a) => artworkViewLock(a) != null).length} '
          'blurred=$blurred',
    );
    return page;
  } on Object catch (error, stack) {
    logger.warning(
      'home',
      'personalized feed failure elapsedMs=${stopwatch.elapsedMilliseconds} '
          'cursor=${request.cursor ?? 'initial'}',
      error,
      stack,
    );
    return null;
  }
}

/// Daily deviations (official API, requires an OAuth session). Rebuilds when
/// the signed-in account changes. Kept alive so tab switches don't re-fetch.
final dailyDeviationsProvider = FutureProvider<List<Artwork>>((ref) async {
  ref.watch(
    authControllerProvider.select((auth) => (auth.status, auth.account?.id)),
  );
  final runtime = ref.watch(runtimeProvider);
  return OfficialDiscoveryRepository(runtime.transport!).dailyDeviations();
});

/// The "deviations from artists you watch" feed (official API, OAuth session).
/// Rebuilds when the signed-in account changes.
final followingFeedProvider =
    StateNotifierProvider<ArtworkFeedController, ArtworkFeedState>((ref) {
      final runtime = ref.watch(runtimeProvider);
      ref.watch(
        authControllerProvider.select(
          (auth) => (auth.status, auth.account?.id),
        ),
      );
      final controller = ArtworkFeedController(
        (request) async {
          final page = await OfficialDiscoveryRepository(runtime.transport!)
              .watched(request);
          // The official feed is cursor-paged newest-first, but a refresh can
          // interleave bumped/edited deviations and sparse entries lacking
          // timestamps. Re-sort the page itself by latest date so the grid and
          // the avatar strip always reflect a consistent newest-first order;
          // entries without a date keep their relative order at the tail.
          final items = sortArtworksNewestFirst(page.items);
          return Page<Artwork>(
            items: items,
            hasMore: page.hasMore,
            nextCursor: page.nextCursor,
          );
        },
        // A larger first page surfaces more distinct watched artists in the
        // top avatar strip instead of a few heavy posters dominating it.
        pageSize: 50,
      );
      return controller;
    });

/// Newest date known for an artwork. Web-feed items map the website's
/// update/publish timestamp onto [Artwork.publishedAt], so the model field is
/// already the latest known time; the detail page additionally reads a
/// separately-parsed edit timestamp via `dadeviation/init`.
DateTime? artworkLatestAt(Artwork artwork) => artwork.publishedAt;

/// Returns [items] ordered by latest date newest-first. Items without a date
/// are moved to the end while preserving their relative (server) order, and
/// equal timestamps keep their incoming order (stable sort).
List<Artwork> sortArtworksNewestFirst(List<Artwork> items) {
  final indexed = <MapEntry<int, DateTime>>[];
  final undated = <Artwork>[];
  for (var index = 0; index < items.length; index += 1) {
    final time = artworkLatestAt(items[index]);
    if (time == null) {
      undated.add(items[index]);
    } else {
      indexed.add(MapEntry<int, DateTime>(index, time));
    }
  }
  indexed.sort((a, b) {
    final byDate = b.value.compareTo(a.value);
    return byDate != 0 ? byDate : a.key.compareTo(b.key);
  });
  return List<Artwork>.unmodifiable(<Artwork>[
    for (final entry in indexed) items[entry.key],
    ...undated,
  ]);
}

/// A watched artist plus the time of their most recent deviation in the feed.
final class WatchedAuthor {
  const WatchedAuthor({
    required this.username,
    required this.avatarUri,
    required this.lastUpdate,
  });

  final String username;
  final Uri? avatarUri;
  final DateTime? lastUpdate;
}

/// The watched artists that have posted in the current feed page, newest first.
/// Derived from [followingFeedProvider] so the avatar strip needs no extra
/// network round-trip.
final watchedAuthorsProvider = Provider<List<WatchedAuthor>>((ref) {
  return watchedAuthorsFrom(ref.watch(followingFeedProvider).items);
});

/// Groups a feed page by author (keeping each author's newest deviation) and
/// returns the authors newest-first. Pure so it can be unit-tested.
List<WatchedAuthor> watchedAuthorsFrom(List<Artwork> items) {
  final byAuthor = <String, WatchedAuthor>{};
  for (final artwork in items) {
    final username = artwork.author.username;
    if (username.isEmpty) continue;
    final current = byAuthor[username];
    final time = artwork.publishedAt;
    if (current == null ||
        (time != null &&
            (current.lastUpdate == null ||
                time.isAfter(current.lastUpdate!)))) {
      byAuthor[username] = WatchedAuthor(
        username: username,
        avatarUri: artwork.author.avatarUri,
        lastUpdate: time,
      );
    }
  }
  final list = byAuthor.values.toList()
    ..sort((a, b) => _newestFirst(a.lastUpdate, b.lastUpdate));
  return list;
}

int _newestFirst(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}
