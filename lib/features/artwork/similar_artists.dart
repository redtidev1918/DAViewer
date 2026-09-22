import 'package:cached_network_image/cached_network_image.dart';
import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_strings.dart';
import 'artwork_detail_providers.dart';

/// "Similar artists" — the authors of the artwork in the "More Like This" set.
/// DeviantArt has no dedicated similar-artists endpoint (the website marks the
/// concept with a `biMetadata` `type:"artist"` hint but streams the list
/// post-hydration), so this section derives the honest equivalent from the
/// related artwork's authors. Tapping opens the artist's profile.
final class SimilarArtistsSection extends ConsumerStatefulWidget {
  const SimilarArtistsSection({required this.artworkId, super.key});

  final String artworkId;

  @override
  ConsumerState<SimilarArtistsSection> createState() =>
      _SimilarArtistsSectionState();
}

final class _SimilarArtistsSectionState
    extends ConsumerState<SimilarArtistsSection>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final artworkId = widget.artworkId;
    final artists = ref.watch(similarArtistsProvider(artworkId)).valueOrNull;
    if (artists == null || artists.isEmpty) return const SizedBox.shrink();
    final s = strings(ref.watch(appLanguageProvider));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 24),
        Text(s.similarArtists, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: artists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 4),
            itemBuilder: (context, index) =>
                _ArtistCard(artist: artists[index]),
          ),
        ),
      ],
    );
  }
}

final class _ArtistCard extends StatelessWidget {
  const _ArtistCard({required this.artist});

  final UserProfile artist;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/artist/${artist.username}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircleAvatar(
              radius: 28,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              foregroundImage: artist.avatarUri == null
                  ? null
                  : CachedNetworkImageProvider(artist.avatarUri.toString()),
              child: const Icon(Icons.person, size: 26),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 72,
              child: Text(
                artist.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
