import 'package:dakit_flutter/dakit_flutter.dart' hide WebSession;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/session_state.dart';
import '../../core/auth/web_session_controller.dart';
import '../../core/auth/web_session_refresher.dart';
import '../../core/data/web_session.dart';

import 'package:dakit_web/dakit_web.dart';

import '../../core/diagnostics/app_logger.dart';
import '../../core/feed/artwork_feed_controller.dart';
import '../../core/runtime/runtime_provider.dart';
import '../artwork/artwork_store.dart';

/// The website-personalized `rfy/deviations` recommendation feed, fetched with
/// the embedded WebView's web session (Cookie + CSRF). Requires a signed-in web
/// session and rebuilds when the web session identity changes.
///
/// A persisted session can be stale after a restart, so a failed fetch refreshes
/// the CSRF once from the stored cookies before giving up.
final personalizedFeedProvider =
    StateNotifierProvider<ArtworkFeedController, ArtworkFeedState>((ref) {
      final runtime = ref.watch(runtimeProvider);
      final webSession = ref.watch(webSessionProvider);
      ref.watch(
        webSessionControllerProvider.select(personalizedFeedSessionIdentity),
      );
      final controller = ArtworkFeedController((request) async {
        final dio = runtime.dio;
        if (dio == null) {
          throw const DAKitException(
            kind: DAKitFailureKind.configuration,
            code: 'app.runtime.dio',
            message: 'The network layer is not available.',
          );
        }
        var csrf = ref.read(webSessionControllerProvider).csrf;
        var cookieHeader = await webSession.cookieHeader();
        final expectedWebUsername = ref
            .read(webSessionControllerProvider)
            .username;
        if (!await _cookieKeepsWebIdentity(webSession, expectedWebUsername)) {
          // The recommendation feed must be personalized; an anonymous (or
          // stale) cookie header would render the generic daily-like feed.
          // Re-attempt the persisted-cookie restore before deciding the web
          // session really is unavailable.
          await ref
              .read(webSessionControllerProvider.notifier)
              .restorePersistedCookies();
          cookieHeader = await webSession.cookieHeader();
        }
        if (!await _cookieKeepsWebIdentity(webSession, expectedWebUsername)) {
          throw const DAKitException(
            kind: DAKitFailureKind.authentication,
            code: 'web.session.unavailable',
            message: 'The personalized feed requires a signed-in web session.',
          );
        }
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
        ref.read(artworkStoreProvider.notifier).putAll(page.items);
        return page;
      });
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

/// Live health of the personalized-feed web session. Unlike OAuth sign-in,
/// the recommendation feed additionally needs the signed-in `userinfo`
/// DeviantArt cookie; without it the endpoint silently returns the generic
/// daily-like feed. This provider re-attempts restoration and reports false
/// when the cookie could not be recovered, so the UI can ask for a web login
/// instead of showing non-personalized content.
final webCookieHealthProvider = FutureProvider<bool>((ref) async {
  final webSession = ref.watch(webSessionProvider);
  ref.watch(webSessionControllerProvider.select((web) => web.username));
  final expected = ref.read(webSessionControllerProvider).username;
  if (await _cookieKeepsWebIdentity(webSession, expected)) return true;
  await ref
      .read(webSessionControllerProvider.notifier)
      .restorePersistedCookies();
  return _cookieKeepsWebIdentity(webSession, expected);
});

/// Whether the live DeviantArt cookies still carry the signed-in identity the
/// app thinks it has. `userinfo` is the cookie DeviantArt uses for the web
/// session, so an empty or mismatched value means the feed is not personalized.
Future<bool> _cookieKeepsWebIdentity(
  WebSession webSession,
  String expectedUsername,
) async {
  final userInfo = (await webSession.cookies())['userinfo'];
  if (userInfo == null || userInfo.isEmpty) return false;
  final actual = WebSession.usernameFromUserInfo(userInfo).trim();
  if (actual.isEmpty) return false;
  if (expectedUsername.trim().isEmpty) return true;
  return actual.toLowerCase() == expectedUsername.trim().toLowerCase();
}

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
  try {
    return await RfyFeedFetcher(dio).fetch(
      cookieHeader: cookieHeader,
      csrfToken: csrf,
      cursor: request.cursor,
    );
  } on Object catch (error, stack) {
    logger.warning('home', 'rfy fetch failed', error, stack);
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
