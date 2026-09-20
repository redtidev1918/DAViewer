import 'package:dakit_core/dakit_core.dart';
import 'package:dakit_web/dakit_web.dart';
import 'package:dio/dio.dart';

/// Fetches the full contents of a DeviantArt collection given its numeric web
/// `folderId`.
///
/// The official OAuth API only accepts a UUID `folderid`, while the "More Like
/// This" preview only exposes the numeric web id (`CollectionSummary.folderId`),
/// so opening a collection's full contents has no clean official path today.
/// This abstraction keeps the UI independent of that gap.
///
/// The current implementation is [WebCollectionContentsSource], which reads
/// DeviantArt's private web collection endpoints. A future official (UUID-based)
/// implementation can replace it without touching a single screen.
abstract interface class CollectionContentsSource {
  Future<List<Artwork>> contents(int folderId, String username);
}

/// The web implementation of [CollectionContentsSource]. Kept behind the
/// interface so a future official (UUID-based) implementation can replace it
/// without touching the collection UI.
final class WebCollectionContentsSource implements CollectionContentsSource {
  const WebCollectionContentsSource(
    this._dio, {
    required this.cookieHeader,
    required this.csrfToken,
  });

  final Dio _dio;
  final String cookieHeader;
  final String csrfToken;

  @override
  Future<List<Artwork>> contents(int folderId, String username) {
    final fetcher = WebCollectionContentsFetcher(_dio);
    // Prefer the lightweight JSON endpoint when a web session (Cookie + CSRF)
    // is available; fall back to the session-free server-rendered page.
    if (csrfToken.isNotEmpty) {
      return fetcher.fetchAllJson(
        folderId: folderId,
        username: username,
        cookieHeader: cookieHeader,
        csrfToken: csrfToken,
      );
    }
    return fetcher.fetchAll(
      folderId: folderId,
      username: username,
      cookieHeader: cookieHeader,
    );
  }
}
