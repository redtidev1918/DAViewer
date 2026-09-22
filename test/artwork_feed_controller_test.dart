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
}
