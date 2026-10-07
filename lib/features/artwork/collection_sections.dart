import 'package:cached_network_image/cached_network_image.dart';
import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/sharing/app_share.dart';
import 'artwork_detail_providers.dart';
import 'collection_contents_provider.dart';
import 'collection_contents_screen.dart';

/// "Featured in" / "Suggested" collections, shown as a compact horizontal rail
/// below More Like This on the detail page. Both read the same
/// [moreLikeThisProvider] (one network call for all related sections) and hide
/// themselves when empty.
///
/// Each card is clearly a collection (folder badge + name + owner), and tapping
/// opens it natively: the preview deviations render instantly while the screen
/// loads the collection's full contents in the background. The full-contents
/// path is abstracted behind `CollectionContentsSource` so a future official
/// implementation can replace the web-scraping source without touching this UI.
final class FeaturedInCollectionsSection extends ConsumerWidget {
  const FeaturedInCollectionsSection({required this.artworkId, super.key});

  final String artworkId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref
        .watch(moreLikeThisProvider(artworkId))
        .value
        ?.featuredInCollections;
    if (groups == null || groups.isEmpty) return const SizedBox.shrink();
    final s = strings(ref.watch(appLanguageProvider));
    return _CollectionRail(
      title: s.featuredInCollections,
      groups: groups,
      s: s,
    );
  }
}

final class SuggestedCollectionsSection extends ConsumerWidget {
  const SuggestedCollectionsSection({required this.artworkId, super.key});

  final String artworkId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref
        .watch(moreLikeThisProvider(artworkId))
        .value
        ?.suggestedCollections;
    if (groups == null || groups.isEmpty) return const SizedBox.shrink();
    final s = strings(ref.watch(appLanguageProvider));
    return _CollectionRail(title: s.suggestedCollections, groups: groups, s: s);
  }
}

final class _CollectionRail extends StatelessWidget {
  const _CollectionRail({
    required this.title,
    required this.groups,
    required this.s,
  });

  final String title;
  final List<CollectionWithDeviations> groups;
  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 24),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: groups.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) =>
                _CollectionCard(group: groups[index], s: s),
          ),
        ),
      ],
    );
  }
}

final class _CollectionCard extends ConsumerStatefulWidget {
  const _CollectionCard({required this.group, required this.s});

  final CollectionWithDeviations group;
  final AppStrings s;

  @override
  ConsumerState<_CollectionCard> createState() => _CollectionCardState();
}

final class _CollectionCardState extends ConsumerState<_CollectionCard> {
  Uri? _fetchedCover;

  @override
  void initState() {
    super.initState();
    _maybeFetchCover();
  }

  /// When the "More Like This" preview carried no cover, resolve one lazily
  /// from the collection's own `gallection/contents` thumbnail.
  Future<void> _maybeFetchCover() async {
    if (_collectionCover(widget.group) != null) return;
    try {
      final cover = await ref.read(
        collectionCoverProvider(
          CollectionContentsKey(
            folderId: widget.group.collection.folderId,
            username: widget.group.collection.owner.username,
          ),
        ).future,
      );
      if (mounted) setState(() => _fetchedCover = cover);
    } on Object {
      // The provider already returns null on failure; keep the placeholder.
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final s = widget.s;
    final collection = group.collection;
    final cover = _collectionCover(group) ?? _fetchedCover;
    return SizedBox(
      width: 168,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openCollection(context, group),
          onLongPress: () => shareDeviantArtLink(
            context,
            uri: folderShareUri(
              username: group.collection.owner.username,
              folderId: '${group.collection.folderId}',
              isCollection: true,
            ),
            title: group.collection.name,
            strings: s,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (cover != null)
                CachedNetworkImage(
                  imageUrl: cover.toString(),
                  fit: BoxFit.cover,
                  memCacheWidth: 480,
                  placeholder: (context, url) =>
                      const ColoredBox(color: AppTheme.placeholderColor),
                  errorWidget: (context, url, error) =>
                      const _CollectionPlaceholder(),
                )
              else
                const _CollectionPlaceholder(),
              // Name + owner on a light bottom gradient.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 28, 10, 8),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[Colors.transparent, Colors.black54],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        collection.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${s.byPrefix}${collection.owner.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Folder badge so the card clearly reads as a collection, not a
              // user or an artwork.
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(
                        Icons.folder_outlined,
                        size: 13,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        s.collectionBadge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _CollectionPlaceholder extends StatelessWidget {
  const _CollectionPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppTheme.placeholderColor,
      child: Icon(Icons.folder_outlined, size: 40),
    );
  }
}

/// The first static image among the collection's preview deviations, used as
/// a cover when the lazily fetched collection thumbnail is unavailable.
Uri? _collectionCover(CollectionWithDeviations group) {
  for (final artwork in group.deviations) {
    for (final media in artwork.media) {
      if (media.kind == MediaKind.image && media.uri != null) return media.uri;
    }
  }
  return null;
}

/// Opens the collection natively. The preview deviations render instantly while
/// the screen loads the full contents in the background; if that fails, the
/// screen falls back to its preview items and an "open on the web" action.
void _openCollection(BuildContext context, CollectionWithDeviations group) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CollectionContentsScreen(
        title: group.collection.name,
        folderId: group.collection.folderId,
        username: group.collection.owner.username,
        initialArtworks: group.deviations,
      ),
    ),
  );
}
