import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dakit_core/dakit_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/feed/artwork_feed_controller.dart';
import '../../core/l10n/app_strings.dart';
import '../../shared/widgets/artwork_feed_grid.dart';
import '../../shared/widgets/settings_action.dart';
import 'search_providers.dart';
import 'search_user_results.dart';

const List<String> _popularTags = <String>[
  'digitalart',
  'fanart',
  'anime',
  'manga',
  'photography',
  'traditionalart',
  'landscape',
  'portrait',
  'characterdesign',
  'pixelart',
];

final class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

final class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  int _mode = 0; // 0 = artworks, 1 = users
  bool _newestFirst = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final query = value.trim();
    if (query.isEmpty) return;
    // '#tag' → browse by tag.
    if (query.startsWith('#')) {
      final tag = query.substring(1).trim();
      if (tag.isNotEmpty) {
        context.push('/tag/${Uri.encodeComponent(tag)}');
        return;
      }
    }
    _debounce?.cancel();
    setState(() => _query = query);
    ref.read(searchHistoryProvider.notifier).add(query);
  }

  /// The official search has no server-side sort, so "newest" reorders the
  /// already-loaded results by publish date (newest first) client-side.
  ArtworkFeedState _sortedNewest(ArtworkFeedState feed) {
    if (!_newestFirst || feed.items.length < 2) return feed;
    final sorted = <Artwork>[...feed.items]
      ..sort((a, b) {
        final at = a.publishedAt;
        final bt = b.publishedAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
    return ArtworkFeedState(
      items: sorted,
      nextCursor: feed.nextCursor,
      isLoading: feed.isLoading,
      error: feed.error,
    );
  }

  /// Live search: results appear as the user types, debounced so a rapid burst
  /// of keystrokes triggers only one request. `#tag` navigation and search
  /// history are still commit-time actions (enter / history tap), not live.
  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() => _query = '');
      return;
    }
    if (query.startsWith('#')) return;
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      if (_query != query) setState(() => _query = query);
    });
  }

  void _selectFromHistory(String query) {
    _controller.text = query;
    _submit(query);
  }

  void _clear() {
    _controller.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim();
    final s = strings(ref.watch(appLanguageProvider));

    return Scaffold(
      appBar: AppBar(
        title: Text(s.search),
        actions: <Widget>[
          IconButton(
            tooltip: s.history,
            icon: const Icon(Icons.history_outlined),
            onPressed: () => context.push('/history'),
          ),
          PopupMenuButton<String>(
            tooltip: s.sort,
            initialValue: _newestFirst ? 'newest' : 'default',
            onSelected: (value) =>
                setState(() => _newestFirst = value == 'newest'),
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'default',
                child: Text(s.sortDefault),
              ),
              PopupMenuItem<String>(value: 'newest', child: Text(s.sortNewest)),
            ],
            icon: const Icon(Icons.sort),
          ),
          const SettingsAction(),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _controller,
              autofocus: false,
              decoration: InputDecoration(
                hintText: s.searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: s.clear,
                        icon: const Icon(Icons.close),
                        onPressed: _clear,
                      ),
              ),
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: _submit,
            ),
          ),
          if (query.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: SegmentedButton<int>(
                segments: <ButtonSegment<int>>[
                  ButtonSegment<int>(value: 0, label: Text(s.artworks)),
                  ButtonSegment<int>(value: 1, label: Text(s.users)),
                ],
                selected: <int>{_mode},
                onSelectionChanged: (selection) =>
                    setState(() => _mode = selection.first),
              ),
            ),
          Expanded(
            child: query.isEmpty
                ? _SearchIdleView(onSelect: _selectFromHistory)
                : _mode == 0
                ? ArtworkFeedGrid(
                    feed: _sortedNewest(ref.watch(searchFeedProvider(query))),
                    emptyMessage: s.noResults,
                    onRefresh: () =>
                        ref.read(searchFeedProvider(query).notifier).refresh(),
                    onLoadMore: () =>
                        ref.read(searchFeedProvider(query).notifier).loadMore(),
                  )
                : UserResults(query: query),
          ),
        ],
      ),
    );
  }
}

/// The idle search view: recommended tags, popular tags, and recent history.
final class _SearchIdleView extends ConsumerWidget {
  const _SearchIdleView({required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = strings(ref.watch(appLanguageProvider));
    final theme = Theme.of(context);
    final recommended =
        ref.watch(recommendedTagsProvider).valueOrNull ?? const <String>[];

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: <Widget>[
        // Recent searches first, compact like tags.
        _SearchHistorySection(onSelect: onSelect),
        if (recommended.isNotEmpty) ...[
          const Divider(),
          _SectionTitle(text: s.recommendedTags),
          // Personalized tags are the most relevant to the user, so give them
          // the same artwork-preview cards as popular tags.
          _TagPreviewRow(tags: recommended.take(6).toList()),
        ],
        const Divider(),
        _SectionTitle(text: s.popularTags),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(
            s.popularTagsHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _TagPreviewRow(tags: _popularTags.take(6).toList()),
      ],
    );
  }
}

/// A section header.
final class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

/// Pixiv-style popular tags with a representative artwork preview each.
final class _TagPreviewRow extends StatelessWidget {
  const _TagPreviewRow({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: tags.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) => _TagPreviewCard(tag: tags[index]),
      ),
    );
  }
}

/// A tappable tag card showing the tag's most popular artwork as its preview.
final class _TagPreviewCard extends ConsumerWidget {
  const _TagPreviewCard({required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(tagPreviewProvider(tag));
    final theme = Theme.of(context);
    return SizedBox(
      width: 132,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.push('/tag/${Uri.encodeComponent(tag)}'),
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                height: 96,
                width: double.infinity,
                child: preview.when(
                  loading: () =>
                      const ColoredBox(color: AppTheme.placeholderColor),
                  error: (error, stackTrace) => const ColoredBox(
                    color: AppTheme.placeholderColor,
                    child: Icon(Icons.tag),
                  ),
                  data: (artwork) {
                    final uri = artwork?.media
                        .where((m) => m.kind == MediaKind.image)
                        .firstOrNull
                        ?.uri;
                    if (uri == null) {
                      return const ColoredBox(
                        color: AppTheme.placeholderColor,
                        child: Icon(Icons.tag),
                      );
                    }
                    return CachedNetworkImage(
                      imageUrl: uri.toString(),
                      fit: BoxFit.cover,
                      memCacheWidth: 264,
                      placeholder: (context, url) =>
                          const ColoredBox(color: AppTheme.placeholderColor),
                      errorWidget: (context, url, error) => const ColoredBox(
                        color: AppTheme.placeholderColor,
                        child: Icon(Icons.tag),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Text(
                  '#$tag',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
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

/// The recent-search history list (with per-item delete and clear-all).
final class _SearchHistorySection extends ConsumerWidget {
  const _SearchHistorySection({required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = strings(ref.watch(appLanguageProvider));
    final theme = Theme.of(context);
    final history = ref.watch(searchHistoryProvider);

    if (history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          children: <Widget>[
            Icon(Icons.search, size: 36, color: theme.colorScheme.outline),
            const SizedBox(height: 10),
            Text(
              s.searchIdleHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: <Widget>[
              Text(s.recent, style: theme.textTheme.titleSmall),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    ref.read(searchHistoryProvider.notifier).clear(),
                child: Text(s.clearHistory),
              ),
            ],
          ),
        ),
        // Compact chips, like tags, instead of tall list tiles.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final item in history)
                ActionChip(
                  avatar: Icon(
                    Icons.history,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  label: Text(item),
                  onPressed: () => onSelect(item),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
