import 'dart:async';

import 'package:dakit_core/dakit_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/request_gate.dart';

enum FeedRequestPhase { idle, loading, refreshing, paginating, stopped }

final class ArtworkFeedState {
  const ArtworkFeedState({
    this.items = const <Artwork>[],
    this.nextCursor,
    this.isLoading = false,
    this.error,
    this.lastRefreshError,
    this.phase = FeedRequestPhase.idle,
  });

  final List<Artwork> items;
  final String? nextCursor;
  final bool isLoading;
  final Object? error;
  final Object? lastRefreshError;
  final FeedRequestPhase phase;

  bool get hasMore => nextCursor != null;
}

/// A paged artwork feed that loads its first page automatically when created
/// (so screens never sit on a spinner), then supports pull-to-refresh and
/// infinite scroll via [refresh] / [loadMore].
final class ArtworkFeedController extends StateNotifier<ArtworkFeedState> {
  ArtworkFeedController(
    this._fetch, {
    bool autoLoad = true,
    this.pageSize = 24,
    DateTime Function()? now,
    List<Duration>? paginationBackoff,
  }) : _now = now ?? DateTime.now,
       _paginationBackoff =
           paginationBackoff ??
           const <Duration>[
             Duration(seconds: 10),
             Duration(seconds: 30),
             Duration(minutes: 1),
           ],
       super(const ArtworkFeedState(isLoading: true)) {
    if (autoLoad) {
      unawaited(refresh());
    }
  }

  final Future<Page<Artwork>> Function(PageRequest request) _fetch;

  /// Items requested per page. Feeds whose first page should surface more
  /// distinct authors (e.g. the watched feed's avatar strip) use a larger size.
  final int pageSize;
  final DateTime Function() _now;
  final List<Duration> _paginationBackoff;
  final RepositoryRequestGate<Page<Artwork>> _requestGate =
      RepositoryRequestGate<Page<Artwork>>();
  Future<void>? _activeFirstPageFetch;
  int _paginationFailures = 0;
  DateTime? _paginationBackoffUntil;

  bool get _inPaginationBackoff {
    final until = _paginationBackoffUntil;
    return until != null && _now().isBefore(until);
  }

  void _resetPaginationBackoff() {
    _paginationFailures = 0;
    _paginationBackoffUntil = null;
  }

  void _enterPaginationBackoff() {
    _paginationFailures += 1;
    final index = (_paginationFailures - 1).clamp(
      0,
      _paginationBackoff.length - 1,
    );
    _paginationBackoffUntil = _now().add(_paginationBackoff[index]);
  }

  Future<Page<Artwork>> _fetchPage(PageRequest request, {bool force = false}) {
    final key = '${request.cursor ?? 'first'}:${request.limit}';
    return _requestGate.load(key, () => _fetch(request), force: force);
  }

  Future<void> refresh() => _runFirstPageFetch(silent: false);

  Future<void> _runFirstPageFetch({required bool silent}) {
    final active = _activeFirstPageFetch;
    if (active != null) return active;
    late final Future<void> tracked;
    tracked = _performFirstPageFetch(silent: silent).whenComplete(() {
      if (identical(_activeFirstPageFetch, tracked)) {
        _activeFirstPageFetch = null;
      }
    });
    _activeFirstPageFetch = tracked;
    return tracked;
  }

  Future<void> _performFirstPageFetch({required bool silent}) async {
    if (!mounted) return;
    final hasItems = state.items.isNotEmpty;
    state = ArtworkFeedState(
      items: state.items,
      nextCursor: state.nextCursor,
      isLoading: true,
      phase: hasItems ? FeedRequestPhase.refreshing : FeedRequestPhase.loading,
    );
    try {
      final page = await _fetchPage(
        PageRequest(limit: pageSize),
        force: hasItems,
      );
      if (!mounted) return;
      _resetPaginationBackoff();
      state = ArtworkFeedState(
        items: page.items,
        nextCursor: page.nextCursor,
        phase: FeedRequestPhase.idle,
      );
    } catch (error) {
      if (!mounted) return;
      if (silent && state.items.isNotEmpty) {
        state = ArtworkFeedState(
          items: state.items,
          nextCursor: state.nextCursor,
          lastRefreshError: error,
          phase: FeedRequestPhase.stopped,
        );
      } else {
        state = ArtworkFeedState(error: error, phase: FeedRequestPhase.stopped);
      }
    }
  }

  Future<void> loadMore() async {
    if (!mounted || state.isLoading || !state.hasMore) return;
    if (_inPaginationBackoff) return;
    final cursor = state.nextCursor;
    state = ArtworkFeedState(
      items: state.items,
      nextCursor: state.nextCursor,
      isLoading: true,
      phase: FeedRequestPhase.paginating,
    );
    try {
      final page = await _fetchPage(
        PageRequest(cursor: cursor, limit: pageSize),
      );
      if (!mounted) return;
      _resetPaginationBackoff();
      state = ArtworkFeedState(
        items: <Artwork>[...state.items, ...page.items],
        nextCursor: page.nextCursor,
        phase: FeedRequestPhase.idle,
      );
    } catch (error) {
      if (!mounted) return;
      _enterPaginationBackoff();
      state = ArtworkFeedState(
        items: state.items,
        nextCursor: cursor,
        error: error,
        phase: FeedRequestPhase.stopped,
      );
    }
  }

  /// Re-fetches the first page without clearing the current items, so the feed
  /// updates in place without a spinner flicker (e.g. when the app resumes).
  Future<void> refreshSilently() async {
    if (!mounted || state.isLoading) return;
    await _runFirstPageFetch(silent: true);
  }
}
