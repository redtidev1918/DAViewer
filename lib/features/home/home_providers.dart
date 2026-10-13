import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dakit_flutter/dakit_flutter.dart' hide WebSession;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/personalized_session_status.dart';
import '../../core/auth/web_session_controller.dart';
import '../../core/auth/web_session_status.dart';

import 'package:dakit_web/dakit_web.dart';

import '../../core/diagnostics/app_logger.dart';
import '../../core/feed/artwork_feed_cache.dart';
import '../../core/feed/artwork_feed_controller.dart';
import '../../core/feed/personalized_request_policy.dart';
import '../../core/runtime/runtime_provider.dart';
import '../artwork/artwork_access.dart';
import '../artwork/artwork_store.dart';

int _personalizedProviderSeq = 0;
int _personalizedRequestSeq = 0;

/// Overrides where per-account personalized-feed caches live (tests inject a
/// temporary directory here). `null` — the default — resolves to
/// `<application support>/feed_cache`, or to no cache at all on platforms
/// without a support directory.
final feedCacheDirectoryProvider = Provider<Directory?>((ref) => null);

/// The website-personalized `rfy/deviations` recommendation feed, fetched with
/// the embedded WebView's web session (Cookie + CSRF). Requires a signed-in web
/// session and rebuilds when the web session identity changes.
///
/// A persisted session can be stale after a restart, so a failed fetch refreshes
/// the CSRF once from the stored cookies before giving up.
final personalizedFeedProvider = StateNotifierProvider<ArtworkFeedController, ArtworkFeedState>((
  ref,
) {
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
  var requestRevision = 0;
  var triggerReason = 'initial_load';
  final pendingTokens = <CancelToken>{};
  final requestTokens = Map<PageRequest, CancelToken>.identity();
  void cancelRequests(String reason) {
    for (final token in pendingTokens.toList()) {
      token.cancel(reason);
    }
  }

  ref.onDispose(() => cancelRequests('provider_disposed'));
  final controller = ArtworkFeedController(
    (request) async {
      final revision = request.cursor == null
          ? ++requestRevision
          : requestRevision;
      final requestId = 'rfy-${++_personalizedRequestSeq}';
      final token = CancelToken();
      pendingTokens.add(token);
      requestTokens[request] = token;
      final statusOwner = ref.read(webSessionStatusProvider.notifier);
      final epoch = statusOwner.accountEpoch;
      final reason = triggerReason;
      var recoveryId = statusOwner.recoveryId;
      var sessionGeneration = statusOwner.generation;
      var credentialRevision = statusOwner.credentialRevision;
      String? terminalOutcome;
      void trace(String phase, [String detail = '']) {
        if (phase == 'accepted' || phase == 'discarded' || phase == 'failed') {
          terminalOutcome = phase;
        }
        AppLogger.instance.info(
          'home',
          'rfy requestId=$requestId provider=$providerId recoveryId=$recoveryId accountEpoch=$epoch sessionGeneration=$sessionGeneration credentialRevision=$credentialRevision triggerReason=$reason phase=$phase $detail',
        );
      }

      String? ownershipLost() {
        if (epoch != statusOwner.accountEpoch) return 'account_changed';
        if (!ref.mounted) return 'provider_disposed';
        if (revision != requestRevision) return 'newer_request_won';
        if (token.isCancelled) {
          return token.cancelError?.error?.toString() ?? 'request_cancelled';
        }
        return null;
      }

      void requireOwnership() {
        final lost = ownershipLost();
        if (lost == null) return;
        trace('discarded', 'discardReason=$lost');
        throw const DAKitException(
          kind: DAKitFailureKind.network,
          code: 'rfy.session.superseded',
          message: 'The recommendation request was superseded.',
        );
      }

      trace('created');
      trace('queued', 'waitingFor=session_verification');
      try {
        AppLogger.instance.info(
          'home',
          'personalized feed fetch '
              'request=$requestId '
              'reason=$reason '
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
        // A local identity is only a candidate. Require a recent server
        // confirmation; check() reuses its healthy lease for five minutes.
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
          'web session candidate: ${webSessionState.username}',
        );
        // rfy answers HTTP 200 with generic content even for a dead Cookie,
        // so the authoritative session verdict — not the rfy status code —
        // decides whether the fetch may run at all. Otherwise the user sees
        // "每日精选"-style generic items silently masquerade as personalized
        // recommendations.
        if (!ref.read(webSessionStatusProvider).needsLogin) {
          final currentHeader = await webSession.cookieHeader();
          requireOwnership();
          await ref
              .read(webSessionStatusProvider.notifier)
              .check(
                force: ref
                    .read(personalizedSessionStatusProvider.notifier)
                    .cookieChanged(currentHeader),
              );
        }
        requireOwnership();
        final verdict = ref.read(webSessionStatusProvider);
        if (verdict.needsLogin) {
          AppLogger.instance.warning(
            'home',
            'rfy skipped: web session verdict ${verdict.state.name} '
                'claimed=${webSessionState.username}',
          );
          throw const DAKitException(
            kind: DAKitFailureKind.authentication,
            code: 'web.session.unavailable',
            message: 'The personalized feed requires a signed-in web session.',
          );
        }
        if (!verdict.isHealthy) {
          throw const DAKitException(
            kind: DAKitFailureKind.network,
            code: 'rfy.session.unverified',
            message: 'The personalized web session could not be confirmed.',
          );
        }
        var csrf = ref.read(webSessionControllerProvider).csrf;
        var cookieHeader = await webSession.cookieHeader();
        requireOwnership();
        recoveryId = statusOwner.recoveryId;
        sessionGeneration = statusOwner.generation;
        credentialRevision = statusOwner.observeCredentials(
          cookieHeader: cookieHeader,
          csrf: csrf,
        );
        trace('queued');
        var generation = ref.read(webSessionStatusProvider.notifier).generation;
        var page = await _tryFetchRfy(
          dio,
          csrf,
          cookieHeader,
          request,
          requestId: requestId,
          cancelToken: token,
          attempt: 1,
          trace: trace,
        );
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
            requireOwnership();
          }
          // Stale session after a restart: re-read the CSRF from the persisted
          // cookies (headless page load) and retry once. This only refreshes
          // the request context; the real-browser probe never writes an auth
          // verdict from inside a feed retry (REG-010).
          await ref
              .read(webSessionStatusProvider.notifier)
              .check(force: true, browser: true);
          requireOwnership();
          if (!ref.read(webSessionStatusProvider).isHealthy) {
            trace('discarded', 'discardReason=session_superseded');
            throw const DAKitException(
              kind: DAKitFailureKind.network,
              code: 'rfy.session.unverified',
              message: 'The personalized web session could not be confirmed.',
            );
          }
          csrf = ref.read(webSessionControllerProvider).csrf;
          cookieHeader = await webSession.cookieHeader();
          requireOwnership();
          recoveryId = statusOwner.recoveryId;
          generation = sessionGeneration = statusOwner.generation;
          credentialRevision = statusOwner.observeCredentials(
            cookieHeader: cookieHeader,
            csrf: csrf,
          );
          trace('queued', 'transportReason=retry_after_failure');
          page = await _tryFetchRfy(
            dio,
            csrf,
            cookieHeader,
            request,
            requestId: requestId,
            cancelToken: token,
            attempt: 2,
            trace: trace,
          );
        }
        if (page == null) {
          AppLogger.instance.warning(
            'home',
            'rfy feed unavailable after retry request=$requestId '
                'verdict=${ref.read(webSessionStatusProvider).state.name} '
                'claimed=${webSessionState.username}',
          );
          // The retry already refreshed the request context. A still-failing
          // rfy request is a feed failure (WAF/proxy/CSRF), not a login
          // verdict: only the authoritative session chain may produce the
          // login prompt, so this must not carry web.session.unavailable.
          throw const DAKitException(
            kind: DAKitFailureKind.network,
            code: 'rfy.feed.unavailable',
            message: 'Recommendations are temporarily unavailable.',
          );
        }

        // A verdict may change while the feed is in flight. Do not commit
        // generic results after expiry or a switch to a different account.
        final currentHeader = await webSession.cookieHeader();
        final degraded = rfyCursorSignalsGenericFallback(page.nextCursor);
        final discardReason = personalizedResultDiscardReason(
          mounted: ref.mounted,
          sameAccount:
              ref.mounted &&
              ref.read(webSessionControllerProvider).username ==
                  webSessionState.username,
          sameEpoch: epoch == statusOwner.accountEpoch,
          sameRequest: revision == requestRevision,
          healthy: ref.mounted && ref.read(webSessionStatusProvider).isHealthy,
          sameGeneration: generation == statusOwner.generation,
          sameCredentials: currentHeader == cookieHeader,
          generic: degraded,
        );
        final finalDiscardReason = ownershipLost() ?? discardReason;
        if (finalDiscardReason != null &&
            finalDiscardReason != 'generic_fallback') {
          trace(
            'discarded',
            'discardReason=$finalDiscardReason credentialsChanged=${currentHeader != cookieHeader}',
          );
          throw const DAKitException(
            kind: DAKitFailureKind.network,
            code: 'rfy.session.unverified',
            message: 'The personalized web session could not be confirmed.',
          );
        }
        trace(
          'validated',
          'credentialsChanged=${currentHeader != cookieHeader}',
        );
        ref
            .read(personalizedSessionStatusProvider.notifier)
            .observe(
              cookieHeader: cookieHeader,
              degraded: degraded,
              generation: statusOwner.generation,
            );
        ref.read(artworkStoreProvider.notifier).putAll(page.items);
        trace('accepted', 'items=${page.items.length} degraded=$degraded');
        AppLogger.instance.info(
          'home',
          'personalized feed accepted items=${page.items.length} '
              'request=$requestId generation=$generation degraded=$degraded',
        );
        if (degraded) {
          // Suspected generic fallback: the group-2 cursor is a historical
          // degradation signal (REG-009), not a verified protocol — the
          // 2026-10-13 production log shows a server-confirmed signed-in
          // session can receive it too. Keep the items usable under the
          // degraded label instead of an empty tab (P0-B), but never persist
          // them as the personalized cold-start cache and never claim the
          // account is signed out.
          AppLogger.instance.warning(
            'home',
            'rfy suspected generic fallback displayed '
                'source=vespa_content_group_2 generation=$generation',
          );
          // Preserve the capability incident even if a home probe confirms
          // the username again. Only a usable feed or explicit recovery clears
          // it.
          await ref
              .read(webSessionStatusProvider.notifier)
              .recheckAfterWebSignal('rfy-generic-fallback');
        } else if (request.cursor == null) {
          // Persist the first page for the next cold start. Fire-and-forget:
          // storage latency must never delay the feed, and a failed save only
          // costs the next start its cached preview.
          unawaited(
            _persistPersonalizedFeedCache(
              ref,
              webSessionState.username,
              page.items,
            ),
          );
        }
        return page;
      } on Object catch (error) {
        if (terminalOutcome == null) {
          final lost = ownershipLost();
          if (lost != null) {
            trace('discarded', 'discardReason=$lost');
          } else {
            trace('failed', 'failureReason=${classifyFeedFetchError(error)}');
          }
        }
        rethrow;
      } finally {
        pendingTokens.remove(token);
        requestTokens.remove(request);
        trace('completed', 'outcome=${terminalOutcome ?? 'unknown'}');
      }
    },
    requestTimeout: const Duration(seconds: 60),
    autoLoad: false,
    onRequestStarted: (reason) => triggerReason = reason,
    cancelRequests: cancelRequests,
    cancelRequest: (request, reason) => requestTokens[request]?.cancel(reason),
    // Identity of the session context this page belongs to: a rotated CSRF or
    // Cookie means an already-loaded first page is stale, so an explicit
    // refresh must fetch again instead of being treated as a duplicate.
    sessionContextKey: () async => feedSessionContextKey(
      csrf: ref.read(webSessionControllerProvider).csrf,
      cookieHeader: await webSession.cookieHeader(),
    ),
  );
  // The live first page starts immediately: the cache is a best-effort
  // preview for the cold-start skeleton, never a prerequisite, so storage
  // latency (or a platform without a support directory) cannot delay it.
  unawaited(controller.refresh());
  // autoLoad stays off so the cache gets a chance to seed the list before
  // the fetch resolves; hydration is a no-op once content exists.
  final cacheIdentity = ref.read(
    webSessionControllerProvider.select(personalizedFeedSessionIdentity),
  );
  if (cacheIdentity.$1 == true && cacheIdentity.$2.trim().isNotEmpty) {
    unawaited(
      _hydratePersonalizedFeedFromCache(
        ref,
        controller,
        cacheIdentity.$2.trim(),
      ),
    );
  }
  ref.listen(webSessionStatusProvider, (previous, next) {
    if (previous?.isHealthy == false && next.isHealthy) {
      // Verification can recover after the initial feed attempt stopped.
      // Resume it once; a healthy-to-healthy update never reloads the list.
      unawaited(controller.recoverInitialPage());
    }
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
  PageRequest request, {
  required String requestId,
  required CancelToken cancelToken,
  required int attempt,
  required void Function(String phase, String detail) trace,
}) async {
  final logger = AppLogger.instance;
  if (csrf.isEmpty || cookieHeader.isEmpty) {
    logger.warning(
      'home',
      'rfy skipped: request=$requestId '
          'csrf=${csrf.isEmpty ? 'missing' : 'ok'} '
          'cookie=${cookieHeader.isEmpty ? 'missing' : 'ok'}',
    );
    return null;
  }
  final stopwatch = Stopwatch()..start();
  try {
    trace(
      'in_flight',
      'transportId=$requestId-t$attempt transportReason=${attempt == 1 ? 'owner_request' : 'retry_after_failure'} cursor=${request.cursor == null ? 'initial' : 'pagination'}',
    );
    // The SDK owns protocol/DTO parsing; the app retains physical request
    // ownership and recovery. Disable the SDK's optional CSRF refresh retry.
    final page = await RfyFeedFetcher(dio).fetch(
      csrfToken: csrf,
      cookieHeader: cookieHeader,
      cursor: request.cursor,
      cancelToken: cancelToken,
      retryInvalidCsrf: false,
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
    trace(
      'transport_succeeded',
      'transportId=$requestId-t$attempt elapsedMs=${stopwatch.elapsedMilliseconds} '
          'cursor=${request.cursor ?? 'initial'} '
          'items=${page.items.length} '
          'gated=${page.items.where((a) => artworkViewLock(a) != null).length} '
          'blurred=$blurred '
          'genericFallback=${rfyCursorSignalsGenericFallback(page.nextCursor)} '
          'cursorStructure=${rfyCursorStructureTrace(page.nextCursor) ?? (page.nextCursor == null ? 'absent' : 'undecodable')}',
    );
    return page;
  } on Object catch (error, stack) {
    if (cancelToken.isCancelled) {
      trace('transport_cancelled', 'transportId=$requestId-t$attempt');
      rethrow;
    }
    trace(
      'transport_failed',
      'transportId=$requestId-t$attempt failureReason=${classifyFeedFetchError(error)}',
    );
    logger.warning(
      'home',
      'personalized feed failure '
          'request=$requestId '
          'classification=${classifyFeedFetchError(error)} '
          'elapsedMs=${stopwatch.elapsedMilliseconds} '
          'cursor=${request.cursor ?? 'initial'}',
      error,
      stack,
    );
    return null;
  }
}

/// Identity of the web-session context a first page was fetched under.
///
/// Hashed so the CSRF/Cookie material never lands in a log or a crash report;
/// only equality matters. A change means the loaded page no longer belongs to
/// the live session and an explicit refresh must refetch it.
String feedSessionContextKey({
  required String csrf,
  required String cookieHeader,
}) => sha256.convert(utf8.encode('$csrf\u0000$cookieHeader')).toString();

/// Buckets a failed feed fetch into a stable, greppable classification so
/// production logs can tell proxy/network failures from WAF blocks and
/// protocol changes without dumping raw provider payloads.
String classifyFeedFetchError(Object error) {
  if (error is DAKitException) {
    return 'dakit:${error.kind.name}:${error.code}';
  }
  if (error is DioException) {
    final response = error.response;
    if (response != null && response.statusCode != null) {
      return 'http:${response.statusCode}';
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout => 'net:connection-timeout',
      DioExceptionType.receiveTimeout => 'net:receive-timeout',
      DioExceptionType.sendTimeout => 'net:send-timeout',
      DioExceptionType.connectionError => 'net:connection-error',
      DioExceptionType.badCertificate => 'net:bad-certificate',
      DioExceptionType.cancel => 'net:cancelled',
      _ => 'net:${error.type.name}',
    };
  }
  return 'unknown:${error.runtimeType}';
}

Future<Directory?> _resolvePersonalizedFeedCacheDirectory(Ref ref) async {
  final override = ref.read(feedCacheDirectoryProvider);
  if (override != null) return override;
  try {
    // No timeout here on purpose: a timer would outlive the widgets in a test
    // zone that has no platform channel handler, and the cache is optional —
    // a platform that never answers simply means "no cache this run", which
    // the pending future expresses without holding anything down.
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}feed_cache');
  } on Object {
    // No support directory (or storage unavailable): run without a cache.
    return null;
  }
}

Future<void> _persistPersonalizedFeedCache(
  Ref ref,
  String username,
  List<Artwork> items,
) async {
  final trimmed = username.trim();
  if (trimmed.isEmpty || !ref.mounted) return;
  try {
    final directory = await _resolvePersonalizedFeedCacheDirectory(ref);
    if (directory == null) return;
    await ArtworkFeedCacheStore(directory: directory).write(trimmed, items);
    AppLogger.instance.info(
      'home',
      'personalized feed cache saved items=${items.length} user=$trimmed',
    );
  } on Object catch (error, stack) {
    AppLogger.instance.warning(
      'home',
      'personalized feed cache save failed',
      error,
      stack,
    );
  }
}

Future<void> _hydratePersonalizedFeedFromCache(
  Ref ref,
  ArtworkFeedController controller,
  String username,
) async {
  try {
    final directory = await _resolvePersonalizedFeedCacheDirectory(ref);
    if (directory != null) {
      final snapshot = await ArtworkFeedCacheStore(directory: directory)
          .read(username);
      if (snapshot != null && snapshot.items.isNotEmpty) {
        final ageMinutes = DateTime.now()
            .difference(snapshot.savedAt)
            .inMinutes
            .abs();
        controller.hydrate(snapshot.items, snapshot.savedAt);
        AppLogger.instance.info(
          'home',
          'personalized feed hydrated from cache '
              'items=${snapshot.items.length} ageMinutes=$ageMinutes',
        );
      }
    }
  } on Object catch (error, stack) {
    AppLogger.instance.warning(
      'home',
      'personalized feed cache hydration failed',
      error,
      stack,
    );
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
