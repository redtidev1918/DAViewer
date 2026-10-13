import 'dart:async';

import 'package:dakit_core/dakit_core.dart';
import 'package:daviewer/core/feed/artwork_feed_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final user = UserProfile(id: 'user-1', username: 'sample');
  Artwork artwork(int index) => Artwork(
    id: 'art-$index',
    title: 'Art $index',
    author: user,
    pageUri: Uri.parse('https://example.test/art-$index'),
    media: const <MediaAsset>[],
  );

  testWidgets('obsolete pagination timeout cancels only its own request', (
    tester,
  ) async {
    final oldPage = Completer<Page<Artwork>>();
    final newPage = Completer<Page<Artwork>>();
    final cancelled = <PageRequest>[];
    PageRequest? paginationRequest;
    var firstPages = 0;
    var broadCancelCalls = 0;
    final controller = ArtworkFeedController(
      (request) async {
        if (request.cursor != null) {
          paginationRequest = request;
          return oldPage.future;
        }
        if (++firstPages > 1) return newPage.future;
        return Page<Artwork>(
          items: [artwork(1)],
          hasMore: true,
          nextCursor: 'next',
        );
      },
      autoLoad: false,
      requestTimeout: const Duration(seconds: 10),
      cancelRequests: (_) => broadCancelCalls++,
      cancelRequest: (request, _) => cancelled.add(request),
    );
    await controller.refresh();
    final pagination = controller.loadMore();
    await tester.pump(const Duration(seconds: 9));
    final refresh = controller.forceRefresh();
    await tester.pump(const Duration(seconds: 1));
    await pagination;
    expect(cancelled, [paginationRequest]);
    expect(broadCancelCalls, 0);
    newPage.complete(Page<Artwork>(items: [artwork(2)], hasMore: false));
    await refresh;
    expect(controller.state.items.single.id, 'art-2');
    oldPage.complete(Page<Artwork>(items: [artwork(99)], hasMore: false));
    controller.dispose();
  });

  test('loads and appends pages from cursor', () async {
    var calls = 0;
    final controller = ArtworkFeedController((request) async {
      calls += 1;
      if (request.cursor == null) {
        return Page<Artwork>(
          items: <Artwork>[artwork(1), artwork(2)],
          hasMore: true,
          nextCursor: 'next',
        );
      }
      return Page<Artwork>(items: <Artwork>[artwork(3)], hasMore: false);
    }, autoLoad: false);

    await controller.refresh();
    expect(controller.state.items, hasLength(2));
    expect(controller.state.hasMore, isTrue);

    await controller.loadMore();
    expect(controller.state.items, hasLength(3));
    expect(controller.state.hasMore, isFalse);
    expect(calls, 2);
  });

  test('auto-loads first page on construction', () async {
    var calls = 0;
    final controller = ArtworkFeedController((request) async {
      calls += 1;
      return Page<Artwork>(items: <Artwork>[artwork(1)], hasMore: false);
    });

    // Wait a microtask for the scheduled refresh to complete.
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(controller.state.items, hasLength(1));
    expect(controller.state.isLoading, isFalse);
  });

  test(
    'short pages append through three pages using opaque server cursors',
    () async {
      final cursors = <String?>[];
      final controller = ArtworkFeedController((request) async {
        cursors.add(request.cursor);
        switch (request.cursor) {
          case null:
            return Page(
              items: [artwork(1)],
              hasMore: true,
              nextCursor: 'opaque-a',
            );
          case 'opaque-a':
            return Page(
              items: [artwork(1), artwork(2)],
              hasMore: true,
              nextCursor: 'opaque-b',
            );
          default:
            return Page(items: [artwork(3)], hasMore: false);
        }
      }, autoLoad: false);
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.loadMore();
      await controller.loadMore();
      await controller.loadMore();
      expect(cursors, [null, 'opaque-a', 'opaque-b']);
      expect(controller.state.items.map((item) => item.id), [
        'art-1',
        'art-2',
        'art-3',
      ]);
      expect(controller.state.paginationStatus, FeedPaginationStatus.exhausted);
    },
  );

  test('cursor cycle is an error and explicit retry can recover without losing cards', () async {
    var calls = 0;
    final controller = ArtworkFeedController((request) async {
      calls++;
      return Page(
        items: [artwork(calls)],
        hasMore: calls < 4,
        nextCursor: calls == 1
            ? 'a'
            : calls == 2
            ? 'b'
            : calls == 3
            ? 'a'
            : null,
      );
    }, autoLoad: false);
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.loadMore();
    await controller.loadMore();
    expect(controller.state.paginationStatus, FeedPaginationStatus.failed);
    expect(controller.state.items, hasLength(3));
    await controller.loadMore();
    expect(calls, 3, reason: 'Backoff prevents repeated automatic asks');
    await controller.retryLoadMore();
    expect(calls, 4);
    expect(controller.state.items, hasLength(4));
    expect(controller.state.paginationStatus, FeedPaginationStatus.exhausted);
  });

  test('empty continuing page retains the server cursor rather than inventing an end', () async {
    final controller = ArtworkFeedController(
      (request) async => request.cursor == null
          ? Page(items: [artwork(1)], hasMore: true, nextCursor: 'a')
          : const Page(items: <Artwork>[], hasMore: true, nextCursor: 'b'),
      autoLoad: false,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.loadMore();
    expect(controller.state.items, hasLength(1));
    expect(controller.state.paginationStatus, FeedPaginationStatus.hasMore);
    expect(controller.state.nextCursor, 'b');
  });

  test('empty terminal page ends according to server flag', () async {
    final controller = ArtworkFeedController(
      (request) async => request.cursor == null
          ? Page(items: [artwork(1)], hasMore: true, nextCursor: 'a')
          : const Page(items: <Artwork>[], hasMore: false),
      autoLoad: false,
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.loadMore();
    expect(controller.state.items, hasLength(1));
    expect(controller.state.paginationStatus, FeedPaginationStatus.exhausted);
    expect(controller.state.error, isNull);
  });

  test('refreshSilently keeps items when the re-fetch fails', () async {
    var calls = 0;
    final controller = ArtworkFeedController((request) async {
      calls += 1;
      if (calls == 1) {
        return Page<Artwork>(items: <Artwork>[artwork(1)], hasMore: false);
      }
      throw StateError('boom');
    }, autoLoad: false);

    await controller.refresh();
    expect(controller.state.items, hasLength(1));

    await controller.refreshSilently();
    expect(calls, 2);
    expect(controller.state.items, hasLength(1));
  });

  test('refreshSilently replaces items on success', () async {
    final controller = ArtworkFeedController(
      (request) async => Page<Artwork>(
        items: <Artwork>[artwork(2), artwork(3)],
        hasMore: false,
      ),
      autoLoad: false,
    );

    await controller.refresh();
    await controller.refreshSilently();
    expect(controller.state.items.map((a) => a.id), <String>['art-2', 'art-3']);
  });

  test(
    'manual refresh failure preserves items and the previous cursor',
    () async {
      var calls = 0;
      final controller = ArtworkFeedController((request) async {
        if (++calls == 2) throw StateError('offline');
        return Page<Artwork>(
          items: [artwork(calls)],
          hasMore: true,
          nextCursor: 'next',
        );
      }, autoLoad: false);
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.refresh();
      expect(controller.state.items.single.id, 'art-1');
      expect(controller.state.nextCursor, 'next');
      expect(controller.state.lastRefreshError, isA<StateError>());
      expect(controller.state.isLoading, isFalse);
      await controller.refresh();
      expect(controller.state.items.single.id, 'art-3');
      expect(controller.state.lastRefreshError, isNull);
    },
  );

  for (final failOldPage in [false, true]) {
    test('refresh supersedes old pagination (failure=$failOldPage)', () async {
      final old = Completer<Page<Artwork>>();
      var firstPages = 0;
      final controller = ArtworkFeedController((request) async {
        if (request.cursor != null) return old.future;
        return Page<Artwork>(
          items: [artwork(++firstPages)],
          hasMore: true,
          nextCursor: 'cursor-$firstPages',
        );
      }, autoLoad: false);
      addTearDown(controller.dispose);
      await controller.refresh();
      final pagination = controller.loadMore();
      await controller.refresh();
      if (failOldPage) {
        old.completeError(StateError('obsolete failure'));
      } else {
        old.complete(Page<Artwork>(items: [artwork(99)], hasMore: false));
      }
      await pagination;
      expect(controller.state.items.single.id, 'art-2');
      expect(controller.state.nextCursor, 'cursor-2');
      expect(controller.state.error, isNull);
      expect(controller.state.phase, FeedRequestPhase.idle);
    });
  }

  test('overlapping pages deduplicate works and a repeated cursor is retryable failure', () async {
    final controller = ArtworkFeedController((request) async {
      return Page<Artwork>(
        items: request.cursor == null
            ? [artwork(1), artwork(1)]
            : [artwork(1), artwork(2)],
        hasMore: true,
        nextCursor: 'same',
      );
    }, autoLoad: false);
    addTearDown(controller.dispose);
    await controller.refresh();
    await controller.loadMore();
    expect(controller.state.items.map((item) => item.id), ['art-1', 'art-2']);
    expect(controller.state.hasMore, isTrue);
    expect(controller.state.paginationStatus, FeedPaginationStatus.failed);
    expect(
      (controller.state.error as DAKitException).code,
      'feed.pagination.invalid_progress',
    );
  });

  test(
    'a refreshed feed cannot join an old request for the same cursor',
    () async {
      final old = Completer<Page<Artwork>>();
      var firstPages = 0;
      var pageCalls = 0;
      final controller = ArtworkFeedController((request) async {
        if (request.cursor == null) {
          return Page<Artwork>(
            items: [artwork(++firstPages)],
            hasMore: true,
            nextCursor: 'same',
          );
        }
        if (++pageCalls == 1) return old.future;
        return Page<Artwork>(items: [artwork(3)], hasMore: false);
      }, autoLoad: false);
      addTearDown(controller.dispose);
      await controller.refresh();
      final oldPage = controller.loadMore();
      await controller.refresh();
      await controller.loadMore();
      expect(pageCalls, 2);
      old.complete(Page<Artwork>(items: [artwork(99)], hasMore: false));
      await oldPage;
      expect(controller.state.items.map((item) => item.id), ['art-2', 'art-3']);
    },
  );

  test('coalesces overlapping first-page refreshes', () async {
    var calls = 0;
    final gate = Completer<Page<Artwork>>();
    final controller = ArtworkFeedController((request) {
      calls += 1;
      return gate.future;
    }, autoLoad: false);

    final first = controller.refresh();
    final second = controller.refresh();
    final silent = controller.refreshSilently();
    expect(calls, 1);

    gate.complete(Page<Artwork>(items: <Artwork>[artwork(1)], hasMore: false));
    await Future.wait(<Future<void>>[first, second, silent]);
    expect(calls, 1);
    expect(controller.state.items.single.id, 'art-1');
  });

  test('failed pagination enters bounded backoff until success', () async {
    var calls = 0;
    var now = DateTime(2026, 1, 1);
    final controller = ArtworkFeedController(
      (request) async {
        calls += 1;
        if (request.cursor == null) {
          return Page<Artwork>(
            items: <Artwork>[artwork(1)],
            hasMore: true,
            nextCursor: 'next',
          );
        }
        if (calls == 2) throw StateError('boom');
        return Page<Artwork>(items: <Artwork>[artwork(2)], hasMore: false);
      },
      autoLoad: false,
      now: () => now,
      paginationBackoff: const <Duration>[Duration(minutes: 1)],
    );

    await controller.refresh();
    await controller.loadMore();
    expect(calls, 2);
    expect(controller.state.error, isA<StateError>());
    expect(controller.state.isLoading, isFalse);

    await controller.loadMore();
    expect(calls, 2, reason: 'backoff must block repeat pagination requests');

    now = now.add(const Duration(minutes: 1, seconds: 1));
    await controller.loadMore();
    expect(calls, 3);
    expect(controller.state.items, hasLength(2));
    expect(controller.state.error, isNull);

    // A success resets the failure counter, so a later failure gets the same
    // bounded window instead of an ever-growing one.
    calls = 0;
    now = now.add(const Duration(minutes: 1, seconds: 1));
    final failing = ArtworkFeedController(
      (request) async {
        calls += 1;
        if (request.cursor == null) {
          return Page<Artwork>(
            items: <Artwork>[artwork(1)],
            hasMore: true,
            nextCursor: 'next',
          );
        }
        throw StateError('boom');
      },
      autoLoad: false,
      now: () => now,
      paginationBackoff: const <Duration>[Duration(minutes: 1)],
    );

    await failing.refresh();
    await failing.loadMore();
    await failing.loadMore();
    expect(calls, 2);
  });

  test('duplicate loadMore shares one in-flight pagination request', () async {
    var calls = 0;
    final gate = Completer<Page<Artwork>>();
    final controller = ArtworkFeedController((request) async {
      calls += 1;
      if (request.cursor == null) {
        return Page<Artwork>(
          items: <Artwork>[artwork(1)],
          hasMore: true,
          nextCursor: 'next',
        );
      }
      return gate.future;
    }, autoLoad: false);

    await controller.refresh();
    final first = controller.loadMore();
    final second = controller.loadMore();
    expect(calls, 2);

    gate.complete(Page<Artwork>(items: <Artwork>[artwork(2)], hasMore: false));
    await Future.wait(<Future<void>>[first, second]);
    expect(calls, 2);
    expect(controller.state.items, hasLength(2));
  });

  test(
    'a stalled page fetch times out and later retries start fresh',
    () async {
      var calls = 0;
      var now = DateTime(2026, 1, 1);
      final stalled = Completer<Page<Artwork>>();
      final controller = ArtworkFeedController(
        (request) {
          calls += 1;
          if (request.cursor == null) {
            return Future<Page<Artwork>>.value(
              Page<Artwork>(
                items: <Artwork>[artwork(1)],
                hasMore: true,
                nextCursor: 'next',
              ),
            );
          }
          // The second call never completes: a stalled response body would
          // otherwise leave the feed permanently in-flight.
          if (calls == 2) return stalled.future;
          return Future<Page<Artwork>>.value(
            Page<Artwork>(items: <Artwork>[artwork(2)], hasMore: false),
          );
        },
        autoLoad: false,
        now: () => now,
        requestTimeout: const Duration(milliseconds: 50),
        paginationBackoff: const <Duration>[Duration(minutes: 1)],
      );

      await controller.refresh();
      await controller.loadMore();
      expect(calls, 2);
      expect(controller.state.phase, FeedRequestPhase.stopped);
      expect(controller.state.error, isA<DAKitException>());

      now = now.add(const Duration(minutes: 1, seconds: 1));
      await controller.loadMore();
      expect(calls, 3, reason: 'retry must not await the abandoned request');
      expect(controller.state.items, hasLength(2));
      expect(controller.state.phase, FeedRequestPhase.idle);
    },
  );

  test('retryLoadMore resets the backoff and retries immediately', () async {
    var calls = 0;
    var now = DateTime(2026, 1, 1);
    final controller = ArtworkFeedController(
      (request) async {
        calls += 1;
        if (request.cursor == null) {
          return Page<Artwork>(
            items: <Artwork>[artwork(1)],
            hasMore: true,
            nextCursor: 'next',
          );
        }
        if (calls == 2) throw StateError('boom');
        return Page<Artwork>(items: <Artwork>[artwork(2)], hasMore: false);
      },
      autoLoad: false,
      now: () => now,
      paginationBackoff: const <Duration>[Duration(minutes: 1)],
    );

    await controller.refresh();
    await controller.loadMore();
    expect(controller.state.phase, FeedRequestPhase.stopped);

    // A scroll-triggered loadMore inside the backoff window stays quiet.
    await controller.loadMore();
    expect(calls, 2);

    // An explicit user retry resets the backoff and fires immediately.
    await controller.retryLoadMore();
    expect(calls, 3);
    expect(controller.state.items, hasLength(2));
    expect(controller.state.phase, FeedRequestPhase.idle);
  });

  test('dispose stops new pagination requests', () async {
    var calls = 0;
    final controller = ArtworkFeedController((request) async {
      calls += 1;
      return Page<Artwork>(
        items: <Artwork>[artwork(1)],
        hasMore: true,
        nextCursor: 'next',
      );
    }, autoLoad: false);

    await controller.refresh();
    controller.dispose();
    await controller.loadMore();
    expect(calls, 1);
  });

  test('manual refresh after failure clears error with one request', () async {
    var calls = 0;
    final controller = ArtworkFeedController((request) async {
      calls += 1;
      if (calls == 1) throw StateError('boom');
      return Page<Artwork>(items: <Artwork>[artwork(1)], hasMore: false);
    }, autoLoad: false);

    await controller.refresh();
    expect(controller.state.error, isA<StateError>());

    await controller.refresh();

    expect(calls, 2);
    expect(controller.state.error, isNull);
    expect(controller.state.items.single.id, 'art-1');
  });

  test('refresh transitions through refreshing and back to idle', () async {
    final controller = ArtworkFeedController((request) async {
      return Page<Artwork>(items: <Artwork>[artwork(1)], hasMore: false);
    }, autoLoad: false);

    await controller.refresh();
    expect(controller.state.phase, FeedRequestPhase.idle);

    final refreshing = controller.refresh();
    expect(controller.state.isLoading, isTrue);
    expect(controller.state.phase, FeedRequestPhase.refreshing);
    await refreshing;
    expect(controller.state.phase, FeedRequestPhase.idle);
  });

  test('silent refresh failure becomes an observable stopped state', () async {
    var calls = 0;
    final controller = ArtworkFeedController((request) async {
      calls += 1;
      if (calls == 1) {
        return Page<Artwork>(items: <Artwork>[artwork(1)], hasMore: false);
      }
      throw StateError('silent boom');
    }, autoLoad: false);

    await controller.refresh();
    await controller.refreshSilently();

    expect(calls, 2);
    expect(controller.state.items, hasLength(1));
    expect(controller.state.phase, FeedRequestPhase.stopped);
    expect(controller.state.lastRefreshError, isA<StateError>());
  });

  group('first-page ownership (session context)', () {
    test(
      'a repeat refresh in the same session context never refetches',
      () async {
        var calls = 0;
        var context = 'csrf-a|cookie-a';
        final controller = ArtworkFeedController(
          (request) async {
            calls += 1;
            return Page<Artwork>(items: <Artwork>[artwork(1)], hasMore: false);
          },
          autoLoad: false,
          sessionContextKey: () async => context,
        );

        await controller.refresh();
        expect(calls, 1);

        // The healthy-transition recovery and an explicit retry are one
        // transaction: owning the page twice must not double the request.
        await controller.refresh();
        expect(calls, 1);
      },
    );

    test('a rotated session context refetches the first page', () async {
      var calls = 0;
      var context = 'csrf-a|cookie-a';
      final controller = ArtworkFeedController(
        (request) async {
          calls += 1;
          return Page<Artwork>(items: <Artwork>[artwork(1)], hasMore: false);
        },
        autoLoad: false,
        sessionContextKey: () async => context,
      );

      await controller.refresh();
      expect(calls, 1);

      context = 'csrf-b|cookie-b';
      await controller.refresh();
      expect(calls, 2);
      expect(controller.state.items, hasLength(1));
    });

    test('forceRefresh always fetches for an explicit user gesture', () async {
      var calls = 0;
      final controller = ArtworkFeedController(
        (request) async {
          calls += 1;
          return Page<Artwork>(items: <Artwork>[artwork(1)], hasMore: false);
        },
        autoLoad: false,
        sessionContextKey: () async => 'csrf-a|cookie-a',
      );

      await controller.refresh();
      await controller.forceRefresh();
      expect(calls, 2);
    });

    test('a failed first page releases ownership so retry refetches', () async {
      var calls = 0;
      var fail = true;
      final controller = ArtworkFeedController(
        (request) async {
          calls += 1;
          if (fail) throw StateError('boom');
          return Page<Artwork>(items: <Artwork>[artwork(1)], hasMore: false);
        },
        autoLoad: false,
        sessionContextKey: () async => 'csrf-a|cookie-a',
      );

      await controller.refresh();
      expect(calls, 1);
      expect(controller.state.error, isA<StateError>());

      fail = false;
      await controller.refresh();
      expect(calls, 2);
      expect(controller.state.items, hasLength(1));
    });
  });
}
