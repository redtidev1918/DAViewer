import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/sharing/app_share.dart';
import '../../shared/widgets/artwork_feed_grid.dart';
import 'artist_providers.dart';

/// The contents of a single artist gallery folder or favourites collection.
final class FolderScreen extends ConsumerWidget {
  const FolderScreen({
    required this.username,
    required this.folderId,
    required this.folderName,
    this.kind = FolderKind.gallery,
    super.key,
  });

  final String username;
  final String folderId;
  final String folderName;
  final FolderKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = strings(ref.watch(appLanguageProvider));
    final request = FolderRequest(
      username: username,
      folderId: folderId,
      kind: kind,
    );
    final feed = ref.watch(folderContentsProvider(request));
    return Scaffold(
      appBar: AppBar(
        title: Text(folderName),
        actions: <Widget>[
          IconButton(
            tooltip: s.share,
            onPressed: () => shareDeviantArtLink(
              context,
              uri: folderShareUri(
                username: username,
                folderId: folderId,
                isCollection: kind == FolderKind.collection,
              ),
              title: folderName,
              strings: s,
            ),
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: ArtworkFeedGrid(
        feed: feed,
        emptyMessage: s.emptyFolder,
        onRefresh: () =>
            ref.read(folderContentsProvider(request).notifier).refresh(),
        onLoadMore: () =>
            ref.read(folderContentsProvider(request).notifier).loadMore(),
        onRetryLoadMore: () =>
            ref.read(folderContentsProvider(request).notifier).retryLoadMore(),
      ),
    );
  }
}
