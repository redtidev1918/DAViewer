import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/app_logger.dart';
import '../../core/diagnostics/error_text.dart';
import '../../core/feed/artwork_feed_controller.dart';
import '../../features/artwork/artwork_navigation.dart';
import 'app_empty_state.dart';
import 'app_error_state.dart';
import 'app_refresh_indicator.dart';
import 'artwork_card.dart';
import 'skeleton.dart';

final class ArtworkFeedGrid extends ConsumerStatefulWidget {
  const ArtworkFeedGrid({
    required this.feed,
    required this.emptyMessage,
    this.scrollController,
    this.onRefresh,
    this.onLoadMore,
    this.emptyActionLabel,
    this.emptyOnAction,
    this.errorMessage,
    this.errorActionLabel,
    this.errorOnAction,
    super.key,
  });

  final ArtworkFeedState feed;
  final String emptyMessage;
  final ScrollController? scrollController;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLoadMore;
  final String? errorActionLabel;
  final VoidCallback? errorOnAction;

  /// Optional call-to-action shown when the feed is empty (e.g. "Discover").
  final String? emptyActionLabel;
  final VoidCallback? emptyOnAction;

  /// Optional feature-specific copy that keeps provider/protocol failures out
  /// of the user interface. Raw errors remain available to the owning state
  /// and diagnostics.
  final String? errorMessage;

  @override
  ConsumerState<ArtworkFeedGrid> createState() => _ArtworkFeedGridState();
}

final class _ArtworkFeedGridState extends ConsumerState<ArtworkFeedGrid> {
  static const Duration _pointerScrollGrace = Duration(milliseconds: 400);

  DateTime? _lastPointerScrollAt;
  bool _loadMoreArmed = true;

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _lastPointerScrollAt = DateTime.now();
    }
  }

  bool _isManualScroll(ScrollUpdateNotification notification) {
    if (notification.dragDetails != null) return true;
    final lastPointerScroll = _lastPointerScrollAt;
    return lastPointerScroll != null &&
        DateTime.now().difference(lastPointerScroll) <= _pointerScrollGrace;
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (widget.feed.error != null && widget.feed.items.isEmpty) {
      body = AppErrorState(
        message:
            widget.errorMessage ?? friendlyErrorMessage(widget.feed.error!),
        onRetry: widget.onRefresh == null
            ? null
            : () {
                widget.onRefresh?.call();
              },
        actionLabel: widget.errorActionLabel,
        onAction: widget.errorOnAction,
      );
    } else if (widget.feed.items.isEmpty && widget.feed.isLoading) {
      body = const SkeletonGrid();
    } else if (widget.feed.items.isEmpty) {
      body = AppEmptyState(
        message: widget.emptyMessage,
        actionLabel: widget.emptyActionLabel,
        onAction: widget.emptyOnAction,
      );
    } else {
      // Masonry (waterfall) layout: cards render at their image's natural
      // aspect ratio, which looks more like a modern image feed.
      final width = MediaQuery.of(context).size.width;
      final crossAxisCount = (width / 200).round().clamp(2, 4);
      body = MasonryGridView.count(
        controller: widget.scrollController,
        padding: const EdgeInsets.all(12),
        physics: const AlwaysScrollableScrollPhysics(),
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        itemCount: widget.feed.items.length + (widget.feed.isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= widget.feed.items.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }
          final artwork = widget.feed.items[index];
          return ArtworkCard(
            artwork: artwork,
            onTap: () => openArtworkFromList(
              context,
              ref,
              artworks: widget.feed.items,
              artwork: artwork,
            ),
          );
        },
      );
    }

    // Wrap in a refreshable scroll view so pull-to-refresh works even when
    // the grid is empty or not yet filled.
    final refreshable = widget.onRefresh == null
        ? body
        : AppRefreshIndicator(
            onRefresh: widget.onRefresh!,
            child: body is ScrollView
                ? body
                : LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: constraints.maxHeight,
                        width: constraints.maxWidth,
                        child: body,
                      ),
                    ),
                  ),
          );

    if (widget.onLoadMore == null) return refreshable;

    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // Only real user scroll may page the feed. Programmatic layout,
          // rebuilds, or state updates must never call loadMore: without this
          // guard a masonry grid whose content does not fill the viewport
          // would repeatedly page through the whole collection on its own.
          // Trackpad and mouse-wheel scrolling emit PointerScrollEvent with no
          // dragDetails, so those are tracked separately instead of being
          // filtered out as if they were programmatic.
          if (notification is! ScrollUpdateNotification) return false;
          if (!_isManualScroll(notification)) return false;
          if (notification.metrics.extentAfter < 400) {
            // Keep this an edge event: while the viewport stays inside the
            // prefetch zone, repeated scroll frames must not call loadMore.
            if (!_loadMoreArmed) return false;
            _loadMoreArmed = false;
            AppLogger.instance.info('feed', 'pagination trigger');
            widget.onLoadMore?.call();
          } else {
            _loadMoreArmed = true;
          }
          return false;
        },
        child: refreshable,
      ),
    );
  }
}
