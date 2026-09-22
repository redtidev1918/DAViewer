import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/l10n/app_strings.dart';
import '../../shared/widgets/artwork_feed_grid.dart';
import '../../shared/widgets/relative_time_text.dart';
import '../home/home_feeds.dart';
import '../home/home_providers.dart';

/// The "deviations from artists you watch" feed — DeviantArt's
/// `/watch/deviations`. Surfaced as a first-class bottom tab (like a follow
/// feed) so new artwork from watched artists is one tap away.
final class WatchedFeedScreen extends ConsumerWidget {
  const WatchedFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = strings(ref.watch(appLanguageProvider));
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.following),
        actions: <Widget>[
          if (auth.oauthSignedIn)
            IconButton(
              tooltip: s.watching,
              onPressed: () => context.push('/watching'),
              icon: const Icon(Icons.people_outline),
            ),
        ],
      ),
      body: auth.oauthSignedIn
          ? const _WatchedBody()
          : LoginPrompt(s: s, onLogin: () => context.push('/web-login')),
    );
  }
}

final class _WatchedBody extends ConsumerWidget {
  const _WatchedBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = strings(ref.watch(appLanguageProvider));
    final feed = ref.watch(followingFeedProvider);
    return Column(
      children: <Widget>[
        const _WatchedAuthorsStrip(),
        Expanded(
          child: ArtworkFeedGrid(
            feed: feed,
            emptyMessage: s.noWatched,
            emptyActionLabel: s.discoverArtists,
            emptyOnAction: () => context.push('/search'),
            errorMessage: s.watchedFeedLoadFailure,
            onRefresh: () => ref.read(followingFeedProvider.notifier).refresh(),
            onLoadMore: () =>
                ref.read(followingFeedProvider.notifier).loadMore(),
            onRetryLoadMore: () =>
                ref.read(followingFeedProvider.notifier).retryLoadMore(),
          ),
        ),
      ],
    );
  }
}

/// A horizontal row of recently-updated watched artists' avatars, newest first
/// (like a follow feed's "who posted" strip). Tapping an avatar opens that
/// artist's gallery.
final class _WatchedAuthorsStrip extends ConsumerWidget {
  const _WatchedAuthorsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authors = ref.watch(watchedAuthorsProvider);
    if (authors.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        itemCount: authors.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) =>
            _WatchedAuthorAvatar(author: authors[index]),
      ),
    );
  }
}

final class _WatchedAuthorAvatar extends ConsumerWidget {
  const _WatchedAuthorAvatar({required this.author});

  final WatchedAuthor author;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = strings(ref.watch(appLanguageProvider));
    final uri = author.avatarUri?.toString();
    final fallback = CircleAvatar(
      child: Text(
        author.username.isEmpty ? '?' : author.username[0].toUpperCase(),
      ),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/artist/${author.username}'),
      child: SizedBox(
        width: 64,
        child: Column(
          children: <Widget>[
            if (uri == null || uri.isEmpty)
              fallback
            else
              CachedNetworkImage(
                imageUrl: uri,
                memCacheWidth: 120,
                imageBuilder: (context, imageProvider) =>
                    CircleAvatar(backgroundImage: imageProvider),
                placeholder: (context, url) => fallback,
                errorWidget: (context, url, error) => fallback,
              ),
            const SizedBox(height: 4),
            Text(
              author.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            RelativeTimeText(
              time: author.lastUpdate,
              format: s.relativeTime,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
