import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:flutter/material.dart';

import '../../core/filtering/content_filter_provider.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/sharing/app_share.dart';
import '../../shared/widgets/app_empty_state.dart';
import '../../shared/widgets/app_error_state.dart';
import '../../shared/widgets/artwork_card.dart';
import 'artwork_navigation.dart';
import 'collection_contents_provider.dart';

/// A native view of a favourites collection's deviations.
///
/// The "More Like This" preview only carries a few of a collection's
/// deviations, so this screen also loads the full contents in the background
/// (via [collectionContentsProvider]) and swaps them in once ready. The preview
/// deviations render instantly while that fetch is in flight, and the "open on
/// the web" fallback remains for collections that cannot be loaded natively.
final class CollectionContentsScreen extends ConsumerStatefulWidget {
  const CollectionContentsScreen({
    required this.title,
    required this.folderId,
    required this.username,
    this.initialArtworks = const <Artwork>[],
    super.key,
  });

  final String title;
  final int folderId;
  final String username;

  /// The deviations already known from the "More Like This" preview (may be
  /// empty). Shown immediately while the full contents load.
  final List<Artwork> initialArtworks;

  @override
  ConsumerState<CollectionContentsScreen> createState() =>
      _CollectionContentsScreenState();
}

class _CollectionContentsScreenState
    extends ConsumerState<CollectionContentsScreen> {
  CollectionContentsKey get _key => CollectionContentsKey(
    folderId: widget.folderId,
    username: widget.username,
  );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(collectionContentsProvider(_key));
    final s = strings(ref.watch(appLanguageProvider));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            tooltip: s.share,
            onPressed: () => shareDeviantArtLink(
              context,
              uri: folderShareUri(
                username: widget.username,
                folderId: widget.folderId.toString(),
                isCollection: true,
              ),
              title: widget.title,
              strings: s,
            ),
            icon: const Icon(Icons.share_outlined),
          ),
        ],
        bottom: async.isLoading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: async.when(
        data: (artworks) => artworks.isEmpty
            ? AppEmptyState(
                message: s.collectionEmpty,
                icon: Icons.folder_outlined,
                actionLabel: s.collectionOpenOnWeb,
                onAction: _openOnWeb,
              )
            : _grid(artworks),
        loading: () => widget.initialArtworks.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _grid(widget.initialArtworks),
        error: (_, _) => widget.initialArtworks.isEmpty
            ? AppErrorState(
                message: s.collectionLoadFailed,
                onRetry: () => ref.invalidate(collectionContentsProvider(_key)),
              )
            : _grid(widget.initialArtworks),
      ),
    );
  }

  Widget _grid(List<Artwork> artworks) {
    artworks = visibleArtworks(ref, artworks);
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = (width / 200).round().clamp(2, 4);
    return MasonryGridView.count(
      padding: const EdgeInsets.all(12),
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      itemCount: artworks.length,
      itemBuilder: (context, index) {
        final artwork = artworks[index];
        return ArtworkCard(
          artwork: artwork,
          onTap: () => openArtworkFromList(
            context,
            ref,
            artworks: artworks,
            artwork: artwork,
          ),
        );
      },
    );
  }

  Future<void> _openOnWeb() {
    final uri = Uri.parse(
      'https://www.deviantart.com/${widget.username.toLowerCase()}'
      '/favourites/${widget.folderId}',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
