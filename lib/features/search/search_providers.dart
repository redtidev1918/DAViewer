import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session_state.dart';
import '../../core/auth/web_session_controller.dart';
import '../../core/auth/web_session_refresher.dart';
import '../../core/data/data_access.dart';
import '../../core/data/source_policy.dart';
import 'package:dakit_web/dakit_web.dart';
import '../../core/feed/artwork_feed_controller.dart';
import '../../core/runtime/app_runtime.dart';
import '../../core/runtime/runtime_provider.dart';
import '../../core/search/interest_store.dart';
import '../../core/search/search_history_store.dart';
import '../artwork/artwork_store.dart';
import '../favourites/favourites_providers.dart';
import '../home/home_providers.dart';

final searchFeedProvider = StateNotifierProvider.autoDispose
    .family<ArtworkFeedController, ArtworkFeedState, String>((ref, query) {
      final controller = ArtworkFeedController((request) async {
        final runtime = ref.read(runtimeProvider);
        final dio = runtime.dio;
        if (dio == null) {
          throw const DAKitException(
            kind: DAKitFailureKind.configuration,
            code: 'app.runtime.dio',
            message: 'The network layer is not available.',
          );
        }
        // Real search results come from the website's private search endpoint
        // (the official API removed `browse/search`). Prefer it whenever the
        // embedded WebView has a web session; a stale session is refreshed once
        // like the rfy feed. The official `browse/home?q=` fallback keeps the
        // previous behavior when no web session exists.
        final webSession = ref.read(webSessionProvider);
        var csrf = ref.read(webSessionControllerProvider).csrf;
        var cookieHeader = await webSession.cookieHeader();
        var result = await _routeSearch(
          dio,
          runtime,
          query,
          request,
          csrf: csrf,
          cookieHeader: cookieHeader,
        );
        if (!result.isSuccess && !result.isEmpty) {
          await ref.read(webSessionRefresherProvider).refresh();
          csrf = ref.read(webSessionControllerProvider).csrf;
          cookieHeader = await webSession.cookieHeader();
          result = await _routeSearch(
            dio,
            runtime,
            query,
            request,
            csrf: csrf,
            cookieHeader: cookieHeader,
          );
        }
        if (result.isSuccess) {
          ref.read(artworkStoreProvider.notifier).putAll(result.value!.items);
          return result.value!;
        }
        if (result.isEmpty) {
          return const Page<Artwork>(items: <Artwork>[], hasMore: false);
        }
        throw const DAKitException(
          kind: DAKitFailureKind.network,
          code: 'search.unavailable',
          message: 'Search is unavailable right now.',
        );
      });
      return controller;
    });

/// Routes a search page through [CapabilityPolicy.search]: Web primary, then
/// coarse official fallback. Web empty is a real "no results"; Web failure or
/// an unsupported session is the only path that reaches the official source.
Future<SourceResult<Page<Artwork>>> _routeSearch(
  Dio dio,
  AppRuntime runtime,
  String query,
  PageRequest request, {
  required String csrf,
  required String cookieHeader,
}) async {
  final plan = CapabilityPolicy.planFor(DesiredCapability.search);
  final webSupported = csrf.isNotEmpty && cookieHeader.isNotEmpty;
  final attempts = <SourceAttempt<Page<Artwork>>>[
    SourceAttempt(
      source: plan.primary,
      supported: webSupported,
      run: () => _tryWebSearch(dio, query, csrf, cookieHeader, request),
    ),
  ];
  final fallback = plan.secondary;
  if (fallback != null) {
    attempts.add(
      SourceAttempt(
        source: fallback,
        run: () async {
          try {
            final page = await dataAccessFor(runtime).search(query, request);
            return page.items.isEmpty
                ? SourceResult<Page<Artwork>>.empty(source: fallback)
                : SourceResult<Page<Artwork>>.success(page, source: fallback);
          } on Object catch (error) {
            return SourceResult<Page<Artwork>>.failed(error, source: fallback);
          }
        },
      ),
    );
  }
  return SourceCoordinator.tryInOrder(attempts);
}

Future<SourceResult<Page<Artwork>>> _tryWebSearch(
  Dio dio,
  String query,
  String csrf,
  String cookieHeader,
  PageRequest request,
) async {
  try {
    final page = await WebSearchFetcher(dio).fetch(
      query: query,
      cookieHeader: cookieHeader,
      csrfToken: csrf,
      cursor: request.cursor,
    );
    return page.items.isEmpty
        ? const SourceResult<Page<Artwork>>.empty(source: DataSource.webApi)
        : SourceResult<Page<Artwork>>.success(page, source: DataSource.webApi);
  } on Object catch (error) {
    return SourceResult<Page<Artwork>>.failed(error, source: DataSource.webApi);
  }
}

/// A single representative artwork for a tag, used as the tag's preview image
/// (Pixiv-style). Picks the most popular deviation of the tag so the preview
/// looks curated rather than arbitrary.
final tagPreviewProvider = FutureProvider.autoDispose.family<Artwork?, String>((
  ref,
  tag,
) async {
  final runtime = ref.watch(runtimeProvider);
  try {
    final page = await OfficialDiscoveryRepository(runtime.transport!)
        .tag(tag, const PageRequest(limit: 1), sort: BrowseSort.popular);
    return page.items.isEmpty ? null : page.items.first;
  } on Object {
    return null;
  }
});

/// Searches users by name (official `user/friends/search` endpoint).
final userSearchProvider = FutureProvider.autoDispose
    .family<List<UserProfile>, String>((ref, query) async {
      final runtime = ref.watch(runtimeProvider);
      return OfficialUserRepository(runtime.transport!).searchFriends(query);
    });

/// Personalized search tags derived from the user's interests, weighted:
/// favourites (explicit interest, 3) > watched artists (2) > everything the
/// user has viewed (persisted view interests + the in-memory artwork cache, 1).
/// The persisted view interests survive app restarts, so recommendations are
/// available even before the favourites/watch feeds have loaded.
final recommendedTagsProvider = FutureProvider<List<String>>((ref) async {
  final persisted = await InterestStore.load();
  final counts = <String, int>{};
  void addAll(Iterable<String> tags, int weight) {
    for (final tag in tags) {
      final normalized = tag.trim().toLowerCase();
      if (normalized.isEmpty) continue;
      counts[normalized] = (counts[normalized] ?? 0) + weight;
    }
  }

  // Persisted view interests: weight 1 each (already counted per view).
  addAll(persisted.keys, 1);
  addAll(ref.watch(currentFavouritesProvider).items.expand((a) => a.tags), 3);
  addAll(ref.watch(followingFeedProvider).items.expand((a) => a.tags), 2);
  addAll(ref.watch(artworkStoreProvider).values.expand((a) => a.tags), 1);
  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return sorted.take(10).map((e) => e.key).toList(growable: false);
});

/// Merges weighted tag sources and returns the top tags by score. Pure so it
/// can be unit-tested.
List<String> recommendedTagsFrom(Map<List<String>, int> weighted) {
  final counts = <String, int>{};
  weighted.forEach((tags, weight) {
    for (final tag in tags) {
      final normalized = tag.trim().toLowerCase();
      if (normalized.isEmpty) continue;
      counts[normalized] = (counts[normalized] ?? 0) + weight;
    }
  });
  final sorted = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return sorted.take(10).map((e) => e.key).toList(growable: false);
}

/// The recent-search history, persisted via [SearchHistoryStore].
final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryController, List<String>>(
      (ref) => SearchHistoryController(),
    );

final class SearchHistoryController extends StateNotifier<List<String>> {
  SearchHistoryController() : super(const <String>[]) {
    _load();
  }

  Future<void> _load() async => state = await SearchHistoryStore.load();

  Future<void> add(String query) async =>
      state = await SearchHistoryStore.add(query);

  Future<void> remove(String query) async =>
      state = await SearchHistoryStore.remove(query);

  Future<void> clear() async {
    await SearchHistoryStore.clear();
    state = const <String>[];
  }
}
