import 'package:cached_network_image/cached_network_image.dart';
import 'package:dakit_core/dakit_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_theme.dart';
import '../../core/diagnostics/error_text.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/sharing/app_share.dart';
import '../../features/artwork/artwork_access.dart';
import '../../features/artwork/artwork_store.dart';
import '../../features/artwork/favourite_actions.dart';

/// A clamped aspect ratio (width / height) for an artwork's display image,
/// used by masonry layouts to size cards at the image's natural shape.
double artworkAspectRatio(
  Artwork artwork, {
  double maxLandscapeAspectRatio = 2.0,
}) {
  for (final media in artwork.media) {
    if (media.kind == MediaKind.image &&
        media.width != null &&
        media.height != null &&
        media.height! > 0) {
      return (media.width! / media.height!).clamp(0.5, maxLandscapeAspectRatio);
    }
  }
  return 0.68;
}

/// Mobile two-column feeds give very wide images a little more height so a
/// banner subject stays legible instead of becoming a thin strip.
double artworkPreviewAspectRatio(BuildContext context, Artwork artwork) =>
    artworkAspectRatio(
      artwork,
      maxLandscapeAspectRatio: MediaQuery.sizeOf(context).width < 600
          ? 1.6
          : 2.0,
    );

final class ArtworkCard extends ConsumerWidget {
  const ArtworkCard({required this.artwork, this.onTap, super.key});

  final Artwork artwork;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = strings(ref.watch(appLanguageProvider));
    final theme = Theme.of(context);
    // Track the favourite flag through the store so a favourite action here is
    // reflected immediately (and mirrored in the detail screen).
    final favourited = ref.watch(
      artworkStoreProvider.select(
        (map) => map[artwork.id]?.isFavourited ?? artwork.isFavourited,
      ),
    );
    // Prefer a static image for the grid thumbnail; fall back to any media
    // (video / animation) so every card shows something.
    final media = artwork.media;
    final image = media.where((m) => m.kind == MediaKind.image).firstOrNull;
    final thumbnail = image ?? media.firstOrNull;
    final hasVideo = media.any((m) => m.kind == MediaKind.video);
    // Animated GIFs are mapped as image assets with an `image/gif` MIME type
    // (or a `.gif` URL), not always as MediaKind.animation — cover all three
    // so the badge shows for every GIF work in the feed.
    final hasGif = media.any(
      (m) =>
          m.kind == MediaKind.animation ||
          m.mimeType == 'image/gif' ||
          (m.uri?.path.toLowerCase().endsWith('.gif') ?? false),
    );
    final viewLock = artworkViewLock(artwork);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showCardMenu(context, ref, favourited),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // The image keeps its natural shape; title/author sit below it so
            // they never cover the artwork.
            AspectRatio(
              aspectRatio: artworkPreviewAspectRatio(context, artwork),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (thumbnail?.uri case final uri?)
                    Hero(
                      tag: 'artwork-${artwork.id}',
                      child: CachedNetworkImage(
                        imageUrl: uri.toString(),
                        fit: BoxFit.cover,
                        memCacheWidth: 480,
                        placeholder: (context, url) =>
                            const ColoredBox(color: AppTheme.placeholderColor),
                        errorWidget: (context, url, error) => const ColoredBox(
                          color: AppTheme.placeholderColor,
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    )
                  else if (media.isEmpty)
                    // Literature/text works carry no media assets at all: show
                    // a text card with the title instead of a broken-image
                    // icon (REG-012). Assets that exist but lack a URI (e.g.
                    // layout probes) keep the plain placeholder.
                    ColoredBox(
                      color: AppTheme.placeholderColor,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Icon(Icons.article_outlined, size: 28),
                            const SizedBox(height: 8),
                            Text(
                              artwork.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (hasVideo)
                    const Center(
                      child: Icon(
                        Icons.play_circle_fill,
                        size: 40,
                        color: Colors.white70,
                      ),
                    ),
                  if (hasGif)
                    const Positioned(
                      top: 6,
                      left: 6,
                      child: _CornerBadge(label: 'GIF', icon: null),
                    ),
                  if (artwork.isMultiMedia)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _CornerBadge(
                        label: s.multiImageBadge,
                        icon: Icons.filter_none,
                      ),
                    ),
                  if (viewLock != null)
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: _LockBadge(
                        tooltip: artworkViewLockLabel(s, viewLock),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    artwork.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  if (artwork.author.username.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      '@${artwork.author.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCardMenu(BuildContext context, WidgetRef ref, bool favourited) {
    final s = strings(ref.read(appLanguageProvider));
    final url = artwork.pageUri.toString();
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: Text(s.viewDetail),
              onTap: () {
                Navigator.pop(context);
                onTap?.call();
              },
            ),
            ListTile(
              leading: Icon(
                favourited ? Icons.favorite : Icons.favorite_border,
              ),
              title: Text(favourited ? s.unfavourite : s.favourite),
              onTap: () async {
                Navigator.pop(context);
                try {
                  final now = await setArtworkFavourite(
                    ref,
                    artwork.id,
                    !favourited,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          now ? s.favouritedToast : s.unfavouritedToast,
                        ),
                      ),
                    );
                  }
                } on Object catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(friendlyErrorMessage(error))),
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(s.share),
              onTap: () async {
                Navigator.pop(context);
                await shareDeviantArtLink(
                  context,
                  uri: artwork.pageUri,
                  title: artwork.title,
                  strings: s,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: Text(s.copyLink),
              onTap: () async {
                Navigator.pop(context);
                await Clipboard.setData(ClipboardData(text: url));
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(s.linkCopied)));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(s.openInBrowser),
              onTap: () {
                Navigator.pop(context);
                final uri = Uri.tryParse(url);
                if (uri != null) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

final class _LockBadge extends StatelessWidget {
  const _LockBadge({required this.tooltip});

  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.lock_outline, size: 13, color: Colors.white),
      ),
    );
  }
}

/// A small translucent pill used for GIF / multi-image badges on the image.
final class _CornerBadge extends StatelessWidget {
  const _CornerBadge({required this.label, required this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final content = icon == null
        ? Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 12, color: Colors.white),
              const SizedBox(width: 2),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: content,
    );
  }
}
