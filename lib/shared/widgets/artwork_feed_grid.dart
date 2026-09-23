import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/app_logger.dart';
import '../../core/diagnostics/error_text.dart';
import '../../core/feed/artwork_feed_controller.dart';
import '../../core/l10n/app_strings.dart';
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
    this.onRetryLoadMore,
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

  /// User-facing retry for a failed pagination page. Distinct from
  /// [onLoadMore] because a plain scroll-triggered loadMore is still inside
  /// its backoff window and would appear to do nothing.
  final VoidCallback? onRetryLoadMore;
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
  /// How close to the bottom (in logical pixels) a manual scroll counts as
  /// "near the bottom" and asks the controller for the next page. This is a
  /// prefetch zone, not the pagination gate: whether a page loads never depends
  /// on crossing it, because the latch is re-armed by the controller finishing
  /// a page (see [didUpdateWidget]) and by an overscroll at the exact bottom,
  /// not by re-crossing this threshold.
  static const double _prefetchPixels = 400;
  static const Duration _pointerScrollGrace = Duration(milliseconds: 400);

  DateTime? _lastPointerScrollAt;
  bool _loadMoreArmed = true;

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _lastPointerScrollAt = DateTime.now();
    }
  }

  bool _isManualScroll(ScrollNotification notification) {
    final dragDetails = switch (notification) {
      ScrollUpdateNotification(:final dragDetails) => dragDetails,
      OverscrollNotification(:final dragDetails) => dragDetails,
      _ => null,
    };
    if (dragDetails != null) return true;
    final lastPointerScroll = _lastPointerScrollAt;
    return lastPointerScroll != null &&
        DateTime.now().difference(lastPointerScroll) <= _pointerScrollGrace;
  }

  // Re-arm from the controller's state, not from scroll geometry. A page that
  // completes while the user stays at the bottom must let the next bottom drag
  // load the following page; previously the latch only re-armed when the scroll
  // re-crossed extentAfter>=400, so whether the masonry columns grew the taller
  // one (i.e. whether the two bottom cards were aligned) decided if the feed
  // kept loading.
  @override
  void didUpdateWidget(covariant ArtworkFeedGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.feed.phase == FeedRequestPhase.paginating &&
        widget.feed.phase != FeedRequestPhase.paginating) {
      _loadMoreArmed = true;
    }
  }

  bool _maybeLoadMore(ScrollNotification notification) {
    if (widget.onLoadMore == null) return false;
    if (!_isManualScroll(notification)) return false;
    if (widget.feed.isLoading ||
        widget.feed.phase == FeedRequestPhase.paginating) {
      return false;
    }
    final metrics = notification.metrics;
    // A drag that starts with the viewport already at the bottom produces only
    // OverscrollNotifications (the position cannot move), so the in-zone
    // ScrollUpdate check below would never run. Treat an overscroll at the
    // bottom edge (and only there) as a request for the next page.
    final draggedPastBottom =
        notification is OverscrollNotification &&
        metrics.extentBefore > 0 &&
        metrics.extentAfter == 0;
    if (metrics.extentAfter <= _prefetchPixels || draggedPastBottom) {
      if (!_loadMoreArmed) return false;
      _loadMoreArmed = false;
      AppLogger.instance.info('feed', 'pagination trigger');
      widget.onLoadMore?.call();
    }
    return false;
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
      final showTrailing =
          widget.feed.isLoading ||
          (widget.feed.phase == FeedRequestPhase.stopped &&
              widget.feed.error != null &&
              widget.feed.items.isNotEmpty);
      body = MasonryGridView.count(
        controller: widget.scrollController,
        padding: const EdgeInsets.all(12),
        physics: const AlwaysScrollableScrollPhysics(),
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        itemCount: widget.feed.items.length + (showTrailing ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= widget.feed.items.length) {
            if (widget.feed.isLoading) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            final onRetry = widget.onRetryLoadMore ?? widget.onLoadMore;
            if (onRetry == null) return const SizedBox.shrink();
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(strings(ref.watch(appLanguageProvider)).retry),
                ),
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
        onNotification: _maybeLoadMore,
        child: refreshable,
      ),
    );
  }
}
