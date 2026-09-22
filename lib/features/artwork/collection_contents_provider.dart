import 'package:dakit_core/dakit_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session_state.dart';
import '../../core/auth/web_session_controller.dart';
import '../../core/auth/web_session_refresher.dart';
import '../../core/data/collection_contents.dart';

import 'package:dakit_web/dakit_web.dart';

import '../../core/runtime/runtime_provider.dart';

/// Identifies a DeviantArt favourites collection by its numeric web folder id
/// and the owner's username.
final class CollectionContentsKey {
  const CollectionContentsKey({required this.folderId, required this.username});

  final int folderId;
  final String username;

  @override
  bool operator ==(Object other) =>
      other is CollectionContentsKey &&
      other.folderId == folderId &&
      other.username == username;

  @override
  int get hashCode => Object.hash(folderId, username);
}

/// The full contents of a favourites collection. Uses the lightweight
/// `gallection/contents` JSON endpoint when a web session (Cookie + CSRF) is
/// available, and falls back to the server-rendered folder page otherwise.
final collectionContentsProvider = FutureProvider.autoDispose
    .family<List<Artwork>, CollectionContentsKey>((ref, key) async {
      final runtime = ref.watch(runtimeProvider);
      final webSession = ref.read(webSessionProvider);
      var csrf = ref.watch(
        webSessionControllerProvider.select((web) => web.csrf),
      );
      if (csrf.isEmpty) {
        await ref.read(webSessionRefresherProvider).refresh();
        csrf = ref.read(webSessionControllerProvider).csrf;
      }
      final cookieHeader = await webSession.cookieHeader();
      return WebCollectionContentsSource(
        runtime.dio!,
        cookieHeader: cookieHeader,
        csrfToken: csrf,
      ).contents(key.folderId, key.username);
    });

/// A collection's cover image, fetched lazily from the website's own
/// `gallection/contents` endpoint. Used when the "More Like This" preview did
/// not carry a cover, so every collection card can still show a thumbnail.
/// Returns `null` when the cover cannot be resolved (renders a placeholder).
final collectionCoverProvider = FutureProvider.autoDispose
    .family<Uri?, CollectionContentsKey>((ref, key) async {
      final runtime = ref.watch(runtimeProvider);
      final webSession = ref.read(webSessionProvider);
      var csrf = ref.watch(
        webSessionControllerProvider.select((web) => web.csrf),
      );
      if (csrf.isEmpty) {
        await ref.read(webSessionRefresherProvider).refresh();
        csrf = ref.read(webSessionControllerProvider).csrf;
      }
      final cookieHeader = await webSession.cookieHeader();
      try {
        return await WebCollectionContentsFetcher(runtime.dio!).fetchCover(
          folderId: key.folderId,
          username: key.username,
          cookieHeader: cookieHeader,
          csrfToken: csrf,
        );
      } on Object {
        return null;
      }
    });
