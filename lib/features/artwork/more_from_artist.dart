import 'package:cached_network_image/cached_network_image.dart';
import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/l10n/app_strings.dart';
import 'artwork_detail_providers.dart';
import 'artwork_navigation.dart';

/// "More from this artist" — a horizontal rail of the author's other recent
/// works. The most directly related "artist discovery" the official API
/// exposes cleanly; true cross-artist similarity lives in an undocumented
/// website recommendation stream (see `docs/architecture.md`).
///
/// Hides itself when the author has no other works or the gallery is
/// unavailable.
final class MoreFromArtistSection extends ConsumerStatefulWidget {
  const MoreFromArtistSection({required this.artworkId, super.key});

  final String artworkId;

  @override
  ConsumerState<MoreFromArtistSection> createState() =>
      _MoreFromArtistSectionState();
}

final class _MoreFromArtistSectionState
    extends ConsumerState<MoreFromArtistSection>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final artworkId = widget.artworkId;
    final items = ref.watch(moreFromArtistProvider(artworkId)).valueOrNull;
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    final s = strings(ref.watch(appLanguageProvider));
    final author = ref
        .watch(artworkDetailProvider(artworkId))
        .valueOrNull
        ?.author
        .username;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 24),
        Text(
          s.moreFromArtist(author ?? ''),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 230,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final artwork = items[index];
              return SizedBox(
                width: 140,
                child: _MoreFromArtistCard(
                  artwork: artwork,
                  onTap: () => openArtworkFromList(
                    context,
                    ref,
                    artworks: items,
                    artwork: artwork,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

final class _MoreFromArtistCard extends StatelessWidget {
  const _MoreFromArtistCard({required this.artwork, this.onTap});

  final Artwork artwork;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = artwork.media
        .where((m) => m.kind == MediaKind.image)
        .firstOrNull;
    final imageUri = image?.uri;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 4 / 5,
              child: imageUri == null
                  ? const ColoredBox(
                      color: AppTheme.placeholderColor,
                      child: Icon(Icons.image_outlined),
                    )
                  : CachedNetworkImage(
                      imageUrl: imageUri.toString(),
                      fit: BoxFit.cover,
                      memCacheWidth: 280,
                      placeholder: (context, url) =>
                          const ColoredBox(color: AppTheme.placeholderColor),
                      errorWidget: (context, url, error) => const ColoredBox(
                        color: AppTheme.placeholderColor,
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      artwork.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    if (artwork.author.username.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@${artwork.author.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
