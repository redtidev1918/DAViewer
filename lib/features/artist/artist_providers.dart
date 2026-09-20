import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session_state.dart';
import '../../core/auth/web_session_controller.dart';
import '../../core/auth/web_session_refresher.dart';
import '../../core/data/data_access.dart';
import 'package:dakit_web/dakit_web.dart';
import '../../core/feed/artwork_feed_controller.dart';
import '../../core/runtime/runtime_provider.dart';
import '../artwork/artwork_store.dart';

final artistProfileProvider = FutureProvider.autoDispose
    .family<UserProfileDetails, String>((ref, username) async {
      final runtime = ref.watch(runtimeProvider);
      return dataAccessFor(runtime).profile(username);
    });

final artistGalleryProvider = StateNotifierProvider.autoDispose
    .family<ArtworkFeedController, ArtworkFeedState, String>((ref, username) {
      final controller = ArtworkFeedController((request) {
        final runtime = ref.read(runtimeProvider);
        return dataAccessFor(runtime).gallery(username, request);
      });
      return controller;
    });

final artistFavouritesProvider = StateNotifierProvider.autoDispose
    .family<ArtworkFeedController, ArtworkFeedState, String>((ref, username) {
      final controller = ArtworkFeedController((request) {
        final runtime = ref.read(runtimeProvider);
        return dataAccessFor(runtime).favourites(username, request);
      });
      return controller;
    });

/// The artist's custom gallery folders (sub-galleries).
final artistFoldersProvider = FutureProvider.autoDispose
    .family<List<ArtworkFolder>, String>((ref, username) async {
      final runtime = ref.watch(runtimeProvider);
      final page = await OfficialFolderRepository(runtime.transport!)
          .galleryFolders(
            username: username,
            options: const FolderQueryOptions(calculateSize: true),
          );
      return page.items;
    });

/// The artist's favourites collections (folders). DeviantArt lets an artist
/// organize their favourites into categories just like their gallery folders;
/// this surfaces those collections so they can be browsed natively.
final artistFavouriteFoldersProvider = FutureProvider.autoDispose
    .family<List<ArtworkFolder>, String>((ref, username) async {
      final runtime = ref.watch(runtimeProvider);
      final page = await OfficialFolderRepository(runtime.transport!)
          .collectionFolders(
            username: username,
            options: const FolderQueryOptions(calculateSize: true),
          );
      return page.items;
    });

/// Extra profile facts (watchers count, join date) from the website's about
/// endpoint. `null` when unavailable (no web session or a reshaped response) —
/// the header simply omits the enrichment.
final webUserProfileProvider = FutureProvider.autoDispose
    .family<WebUserProfileInfo?, String>((ref, username) async {
      final runtime = ref.watch(runtimeProvider);
      final dio = runtime.dio;
      if (dio == null) return null;
      final webSession = ref.read(webSessionProvider);
      var csrf = ref.read(webSessionControllerProvider).csrf;
      if (csrf.isEmpty) {
        await ref.read(webSessionRefresherProvider).refresh();
        csrf = ref.read(webSessionControllerProvider).csrf;
      }
      final cookieHeader = await webSession.cookieHeader();
      if (csrf.isEmpty || cookieHeader.isEmpty) return null;
      try {
        return await WebUserProfileFetcher(dio).fetch(
          username: username,
          cookieHeader: cookieHeader,
          csrfToken: csrf,
        );
      } on Object {
        return null;
      }
    });

/// Identifies a keyword search inside one artist's gallery.
final class ArtistGallerySearchKey {
  const ArtistGallerySearchKey({required this.username, required this.query});

  final String username;
  final String query;

  @override
  bool operator ==(Object other) =>
      other is ArtistGallerySearchKey &&
      other.username == username &&
      other.query == query;

  @override
  int get hashCode => Object.hash(username, query);
}

/// Keyword search within one artist's own gallery, via the website's
/// `gallection/search` endpoint (the official API has no gallery-search
/// surface). Requires a web session (Cookie + CSRF); a missing or stale
/// session is refreshed once and retried.
final artistGallerySearchProvider = StateNotifierProvider.autoDispose
    .family<ArtworkFeedController, ArtworkFeedState, ArtistGallerySearchKey>((
      ref,
      key,
    ) {
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
        final webSession = ref.read(webSessionProvider);
        var csrf = ref.read(webSessionControllerProvider).csrf;
        var cookieHeader = await webSession.cookieHeader();
        var page = await _tryFetchGallerySearch(
          dio,
          key,
          csrf,
          cookieHeader,
          request.cursor,
        );
        if (page == null) {
          await ref.read(webSessionRefresherProvider).refresh();
          csrf = ref.read(webSessionControllerProvider).csrf;
          cookieHeader = await webSession.cookieHeader();
          page = await _tryFetchGallerySearch(
            dio,
            key,
            csrf,
            cookieHeader,
            request.cursor,
          );
        }
        if (page == null) {
          throw const DAKitException(
            kind: DAKitFailureKind.authentication,
            code: 'web.session.unavailable',
            message: 'Gallery search requires a valid web session.',
          );
        }
        ref.read(artworkStoreProvider.notifier).putAll(page.items);
        return page;
      });
      return controller;
    });

/// Fetches one gallery-search page, or `null` when the web session is missing
/// or the request failed (the caller refreshes the session and retries once).
Future<Page<Artwork>?> _tryFetchGallerySearch(
  Dio dio,
  ArtistGallerySearchKey key,
  String csrf,
  String cookieHeader,
  String? cursor,
) async {
  if (csrf.isEmpty || cookieHeader.isEmpty) return null;
  try {
    return await WebGallerySearchFetcher(dio).fetch(
      username: key.username,
      query: key.query,
      cookieHeader: cookieHeader,
      csrfToken: csrf,
      cursor: cursor,
    );
  } on Object {
    return null;
  }
}

/// The artist's journal posts (articles), via the official
/// `user/profile/posts` endpoint filtered to `/journal/` entries.
final artistJournalsProvider = FutureProvider.autoDispose
    .family<List<Artwork>, String>((ref, username) async {
      final runtime = ref.watch(runtimeProvider);
      final json = await runtime.transport!.getJson(
        'user/profile/posts',
        query: <String, Object?>{
          'username': username,
          'limit': 50,
          'mature_content': true,
        },
      );
      final rawResults = json['results'];
      if (rawResults is! List) return const <Artwork>[];
      const mapper = DeviationMapper();
      final items = <Artwork>[];
      for (final raw in rawResults) {
        if (raw is! Map) continue;
        final url = raw['url'];
        if (url is! String || !url.contains('/journal/')) continue;
        // Journals use the official deviation shape (UUID + text_content), not
        // the web rfy shape — map them with the official mapper.
        final item = raw.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        );
        try {
          items.add(mapper.artwork(item));
        } on Object {
          // Skip malformed journal entries.
        }
      }
      // Cache journals so tapping one opens the detail screen without an OAuth
      // `deviation/{numericId}` 404.
      ref.read(artworkStoreProvider.notifier).putAll(items);
      return items;
    });

/// The contents of one gallery or collection (favourites) folder.
final folderContentsProvider = StateNotifierProvider.autoDispose
    .family<ArtworkFeedController, ArtworkFeedState, FolderRequest>((
      ref,
      request,
    ) {
      final runtime = ref.watch(runtimeProvider);
      final controller = ArtworkFeedController((page) {
        final repository = OfficialFolderRepository(runtime.transport!);
        return request.kind == FolderKind.collection
            ? repository.collectionContents(
                request.folderId,
                username: request.username,
                request: page,
              )
            : repository.galleryContents(
                request.folderId,
                username: request.username,
                request: page,
              );
      });
      return controller;
    });

final class FolderRequest {
  const FolderRequest({
    required this.username,
    required this.folderId,
    this.kind = FolderKind.gallery,
  });

  final String username;
  final String folderId;
  final FolderKind kind;

  @override
  bool operator ==(Object other) =>
      other is FolderRequest &&
      other.username == username &&
      other.folderId == folderId &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(username, folderId, kind);
}
