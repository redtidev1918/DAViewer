import 'dart:async';

import 'package:dakit_core/dakit_core.dart';
import 'package:flutter_riverpod/legacy.dart';

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
    this.lastSuccessfulRefreshAt,
  });

  final List<Artwork> items;
  final String? nextCursor;
  final bool isLoading;
  final Object? error;
  final Object? lastRefreshError;
  final FeedRequestPhase phase;

  /// When the current items were last served by a successful first-page
  /// fetch (or by a cache hydration, whose value is the cache's save time).
  /// Retained across refresh failures so the UI can label stale-but-visible
  /// content with its age instead of presenting it as live.
  final DateTime? lastSuccessfulRefreshAt;

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
    this.requestTimeout = const Duration(seconds: 30),
    DateTime Function()? now,
    List<Duration>? paginationBackoff,
    this.sessionContextKey,
    this.onRequestStarted,
    this.cancelRequests,
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

  /// Identifies the web-session context (CSRF + Cookie header) a first page was
  /// fetched under. Feeds that can be re-authenticated pass it so [refresh]
  /// can tell "already loaded" from "loaded, but the session context rotated
  /// since" — a rotated Cookie must refetch even though the page count is
  /// unchanged. `null` (feeds without a web session) disables the check.
  final Future<String> Function()? sessionContextKey;
  final void Function(String reason)? onRequestStarted;
  final void Function(String reason)? cancelRequests;

  final Future<Page<Artwork>> Function(PageRequest request) _fetch;

  /// Items requested per page. Feeds whose first page should surface more
  /// distinct authors (e.g. the watched feed's avatar strip) use a larger size.
  final int pageSize;

  /// Hard cap on one page fetch (headers + body + decode). dio's receiveTimeout
  /// only covers waiting for the response header, so a stalled body stream can
  /// otherwise keep a feed permanently in-flight with no spinner or backoff.
  final Duration requestTimeout;
  final DateTime Function() _now;
  final List<Duration> _paginationBackoff;
  final RepositoryRequestGate<Page<Artwork>> _requestGate =
      RepositoryRequestGate<Page<Artwork>>();
  Future<void>? _activeFirstPageFetch;

  /// Set once the current session generation has a first page fetched from the
  /// network. Cache hydration never sets it (a cold start must still fetch)
  /// and every failure clears it (a retry must always refetch).
  bool _firstPageFetched = false;

  /// The session context the page in [_firstPageFetched] was fetched under;
  /// `null` when unknown, which makes the next [refresh] fetch again.
  String? _firstPageContextKey;
  int _paginationFailures = 0;
  DateTime? _paginationBackoffUntil;
  int _revision = 0;

  List<Artwork> _uniqueItems(Iterable<Artwork> items) {
    final seen = <String>{};
    return items.where((item) => seen.add(item.id)).toList();
  }

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

  Future<Page<Artwork>> _fetchPage(PageRequest request) {
    final key = '$_revision:${request.cursor ?? 'first'}:${request.limit}';
    final gate = _requestGate;
    return gate
        .load(key, () => _fetch(request), cache: false)
        .timeout(
          requestTimeout,
          onTimeout: () {
            // Drop the in-flight entry so a retry after backoff starts a fresh
            // request. The abandoned request is not cancelled (no cancel token is
            // threaded through _fetch); its connection is reclaimed when dio's own
            // timeout or the OS closes it. ponytail: single shared timeout; per-feed
            // cancellation tokens if abandoned requests accumulate.
            gate.cancel(key);
            cancelRequests?.call('request_timeout');
            throw const DAKitException(
              kind: DAKitFailureKind.network,
              code: 'feed.request.timeout',
              message: 'The feed request timed out.',
            );
          },
        );
  }

  /// Ensures the current session generation has its first page.
  ///
  /// This is the *idempotent* entry point: the healthy-transition recovery and
  /// an explicit retry triggered by the same verification are one transaction,
  /// not two refreshes, so a repeat call never issues a second request — it
  /// joins the in-flight fetch, and it is a no-op while the page already
  /// fetched still belongs to the live session context ([sessionContextKey]).
  /// Use [forceRefresh] for a user gesture that must always refetch
  /// (pull-to-refresh).
  Future<void> refresh() async {
    final active = _activeFirstPageFetch;
    if (active != null) return active;
    if (_firstPageFetched &&
        state.error == null &&
        state.lastRefreshError == null) {
      final key = sessionContextKey;
      // Only a feed that can prove the page still belongs to the live session
      // context skips the fetch; without that identity every call fetches, so
      // a plain list feed keeps refetching on refresh as it always did.
      if (key != null) {
        final live = await key();
        if (!mounted || live == _firstPageContextKey) return;
      }
    }
    return _runFirstPageFetch(
      reason: _firstPageFetched ? 'cookie_context_changed' : 'initial_load',
    );
  }

  /// Starts a new first-page fetch unconditionally, for an explicit user
  /// gesture (pull-to-refresh, reload) that expects fresh content even though
  /// the current page already loaded.
  Future<void> forceRefresh() => _runFirstPageFetch(reason: 'user_refresh');

  /// Seeds the feed with a persisted first page so a cold start can render
  /// the last good content while the refresh runs. The pending refresh (the
  /// caller starts it right after) still replaces the list, so hydration is
  /// skipped once any content exists.
  void hydrate(List<Artwork> items, DateTime refreshedAt) {
    if (!mounted || items.isEmpty || state.items.isNotEmpty) return;
    _resetPaginationBackoff();
    state = ArtworkFeedState(
      items: List<Artwork>.unmodifiable(items),
      lastSuccessfulRefreshAt: refreshedAt,
      phase: FeedRequestPhase.refreshing,
    );
  }

  /// Resume a failed load after its session prerequisite recovers.
  ///
  /// Recovers the initial page when the previous attempt errored, and also
  /// resumes a refresh whose failure left stale (cached) content on screen:
  /// the healthy transition is exactly the signal that the retry can now
  /// succeed. Content whose last refresh succeeded is never touched.
  Future<void> recoverInitialPage() async {
    if (!mounted || state.isLoading) return;
    final staleContent =
        state.items.isNotEmpty && state.lastRefreshError != null;
    final failedInitialLoad = state.items.isEmpty && state.error != null;
    if (!staleContent && !failedInitialLoad) {
      return;
    }
    await _runFirstPageFetch(reason: 'session_recovered');
  }

  Future<void> _runFirstPageFetch({String reason = 'initial_load'}) {
    final active = _activeFirstPageFetch;
    if (active != null) return active;
    onRequestStarted?.call(reason);
    late final Future<void> tracked;
    tracked = _performFirstPageFetch().whenComplete(() {
      if (identical(_activeFirstPageFetch, tracked)) {
        _activeFirstPageFetch = null;
      }
    });
    _activeFirstPageFetch = tracked;
    return tracked;
  }

  Future<void> _performFirstPageFetch() async {
    if (!mounted) return;
    final revision = ++_revision;
    final hasItems = state.items.isNotEmpty;
    state = ArtworkFeedState(
      items: state.items,
      nextCursor: state.nextCursor,
      isLoading: true,
      phase: hasItems ? FeedRequestPhase.refreshing : FeedRequestPhase.loading,
    );
    try {
      final page = await _fetchPage(PageRequest(limit: pageSize));
      if (!mounted || revision != _revision) return;
      _resetPaginationBackoff();
      _firstPageFetched = true;
      final contextKey = sessionContextKey;
      if (contextKey != null) {
        try {
          // Recorded BEFORE the state lands so a refresh arriving right after
          // this page can recognise it as the same context and stay a no-op.
          _firstPageContextKey = await contextKey();
        } on Object {
          _firstPageContextKey = null;
        }
        if (!mounted || revision != _revision) return;
      }
      state = ArtworkFeedState(
        items: _uniqueItems(page.items),
        nextCursor: page.nextCursor,
        phase: FeedRequestPhase.idle,
        lastSuccessfulRefreshAt: _now(),
      );
    } catch (error) {
      if (!mounted || revision != _revision) return;
      // Ownership of the first page is released on failure so the recovery
      // listener and a user retry can both request it again.
      _firstPageFetched = false;
      _firstPageContextKey = null;
      if (state.items.isNotEmpty) {
        state = ArtworkFeedState(
          items: state.items,
          nextCursor: state.nextCursor,
          lastRefreshError: error,
          phase: FeedRequestPhase.stopped,
          // Keep the age label of whatever the user is still looking at.
          lastSuccessfulRefreshAt: state.lastSuccessfulRefreshAt,
        );
      } else {
        state = ArtworkFeedState(
          error: error,
          phase: FeedRequestPhase.stopped,
          lastSuccessfulRefreshAt: state.lastSuccessfulRefreshAt,
        );
      }
    }
  }

  Future<void> loadMore() async {
    if (!mounted || state.isLoading || !state.hasMore) return;
    if (_inPaginationBackoff) return;
    final revision = _revision;
    final cursor = state.nextCursor;
    onRequestStarted?.call('pagination');
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
      if (!mounted || revision != _revision) return;
      _resetPaginationBackoff();
      state = ArtworkFeedState(
        items: _uniqueItems(<Artwork>[...state.items, ...page.items]),
        nextCursor: page.nextCursor == cursor ? null : page.nextCursor,
        phase: FeedRequestPhase.idle,
        lastSuccessfulRefreshAt: state.lastSuccessfulRefreshAt,
      );
    } catch (error) {
      if (!mounted || revision != _revision) return;
      _enterPaginationBackoff();
      state = ArtworkFeedState(
        items: state.items,
        nextCursor: cursor,
        error: error,
        phase: FeedRequestPhase.stopped,
      );
    }
  }

  /// Retries a failed pagination page. A user tap is an explicit retry, so it
  /// resets the backoff that would otherwise keep a scroll-triggered [loadMore]
  /// from firing.
  Future<void> retryLoadMore() {
    _resetPaginationBackoff();
    return loadMore();
  }

  /// Re-fetches the first page without clearing the current items, so the feed
  /// updates in place without a spinner flicker (e.g. when the app resumes).
  Future<void> refreshSilently() async {
    if (!mounted || state.isLoading) return;
    await _runFirstPageFetch(reason: 'resume_refresh');
  }

  @override
  void dispose() {
    _revision++;
    cancelRequests?.call('provider_disposed');
    super.dispose();
  }
}
