import 'package:dakit_core/dakit_core.dart';
import 'package:daviewer/core/feed/artwork_feed_controller.dart';
import 'package:daviewer/shared/widgets/artwork_feed_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Artwork artwork(int index) => Artwork(
    id: 'art-$index',
    title: 'Art $index',
    author: const UserProfile(id: 'user-1', username: 'artist'),
    pageUri: Uri.parse('https://www.deviantart.com/artist/art/art-$index'),
    media: const <MediaAsset>[
      MediaAsset(
        id: 'preview',
        kind: MediaKind.image,
        role: MediaRole.preview,
        availability: MediaAvailability.available,
        width: 600,
        height: 400,
      ),
    ],
  );

  ArtworkFeedState longFeed() => ArtworkFeedState(
    items: <Artwork>[for (var i = 0; i < 40; i += 1) artwork(i)],
    nextCursor: 'next',
  );

  Artwork portrait(int index) => Artwork(
    id: 'portrait-$index',
    title: 'Portrait $index',
    author: const UserProfile(id: 'user-1', username: 'artist'),
    pageUri: Uri.parse('https://www.deviantant.com/artist/art/portrait-$index'),
    media: const <MediaAsset>[
      MediaAsset(
        id: 'preview',
        kind: MediaKind.image,
        role: MediaRole.preview,
        availability: MediaAvailability.available,
        width: 240,
        height: 720,
      ),
    ],
  );

  testWidgets('feature copy hides provider parsing details', (tester) async {
    const rawMessage = 'The official API page does not contain a results list.';
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          home: Scaffold(
            body: ArtworkFeedGrid(
              feed: ArtworkFeedState(
                error: DAKitException(
                  kind: DAKitFailureKind.parsing,
                  code: 'api.page.missing_results',
                  message: rawMessage,
                ),
              ),
              emptyMessage: 'Empty',
              errorMessage: 'Watched feed is temporarily unavailable.',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Watched feed is temporarily unavailable.'), findsOne);
    expect(find.text(rawMessage), findsNothing);
  });

  testWidgets('error state can offer a login action beside retry', (
    tester,
  ) async {
    var loginTaps = 0;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          home: Scaffold(
            body: ArtworkFeedGrid(
              feed: const ArtworkFeedState(
                error: DAKitException(
                  kind: DAKitFailureKind.authentication,
                  code: 'web.session.unavailable',
                  message: 'Session unavailable',
                ),
              ),
              emptyMessage: 'Empty',
              errorMessage: 'Watched feed is temporarily unavailable.',
              onRefresh: () async {},
              errorActionLabel: 'Login',
              errorOnAction: () {
                loginTaps += 1;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('Login'), findsOneWidget);
    await tester.tap(find.text('Login'));
    expect(loginTaps, 1);
  });

  testWidgets('rebuilds never load more without a user drag', (tester) async {
    var calls = 0;
    final artwork = Artwork(
      id: '1',
      title: 'Art',
      author: UserProfile(id: '1', username: 'artist'),
      pageUri: Uri.parse('https://www.deviantart.com/artist/art/art-1'),
      media: <MediaAsset>[],
    );
    final isLoading = ArtworkFeedState(
      items: <Artwork>[artwork],
      nextCursor: 'next',
      isLoading: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          home: Scaffold(
            body: ArtworkFeedGrid(
              feed: isLoading,
              emptyMessage: 'Empty',
              onLoadMore: () {
                calls += 1;
              },
            ),
          ),
        ),
      ),
    );

    for (var i = 0; i < 10; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(calls, 0);
  });

  testWidgets('programmatic scroll never loads more', (tester) async {
    var calls = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          home: Scaffold(
            body: ArtworkFeedGrid(
              feed: longFeed(),
              emptyMessage: 'Empty',
              scrollController: controller,
              onLoadMore: () {
                calls += 1;
              },
            ),
          ),
        ),
      ),
    );

    controller.jumpTo(controller.position.maxScrollExtent - 200);
    await tester.pump();

    expect(calls, 0);
  });

  testWidgets('Android fling reaches pagination zone only during inertia', (
    tester,
  ) async {
    var calls = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: Scaffold(
            body: ArtworkFeedGrid(
              feed: longFeed(),
              emptyMessage: 'Empty',
              scrollController: controller,
              onLoadMore: () => calls++,
            ),
          ),
        ),
      ),
    );
    controller.jumpTo(controller.position.maxScrollExtent - 900);
    await tester.pump();
    await tester.fling(
      find.byType(ArtworkFeedGrid),
      const Offset(0, -200),
      5000,
    );
    expect(calls, 0, reason: 'Direct drag ends outside the prefetch zone');
    await tester.pumpAndSettle();
    expect(controller.position.extentAfter, lessThan(400));
    expect(calls, 1);
  });

  testWidgets('trackpad scroll near the bottom loads next page', (
    tester,
  ) async {
    var calls = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          home: Scaffold(
            body: ArtworkFeedGrid(
              feed: longFeed(),
              emptyMessage: 'Empty',
              scrollController: controller,
              onLoadMore: () {
                calls += 1;
              },
            ),
          ),
        ),
      ),
    );

    controller.jumpTo(controller.position.maxScrollExtent - 200);
    await tester.pump();
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        kind: PointerDeviceKind.trackpad,
        position: Offset(400, 300),
        scrollDelta: Offset(0, 20),
      ),
    );
    await tester.pump();

    expect(calls, greaterThan(0));
  });

  testWidgets('failed pagination shows a working retry footer', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          home: Scaffold(
            body: ArtworkFeedGrid(
              feed: ArtworkFeedState(
                items: <Artwork>[artwork(0)],
                nextCursor: 'next',
                error: StateError('boom'),
                phase: FeedRequestPhase.stopped,
              ),
              emptyMessage: 'Empty',
              onRetryLoadMore: () {
                retries += 1;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.refresh), findsOneWidget);
    await tester.tap(find.byIcon(Icons.refresh));
    expect(retries, 1);
  });

  testWidgets('refresh failure keeps cards and retries the first page', (
    tester,
  ) async {
    var refreshes = 0;
    var pages = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ArtworkFeedGrid(
              feed: ArtworkFeedState(
                items: [artwork(1)],
                nextCursor: 'next',
                lastRefreshError: StateError('offline'),
                phase: FeedRequestPhase.stopped,
              ),
              emptyMessage: 'Empty',
              onRefresh: () async {
                refreshes++;
              },
              onRetryLoadMore: () {
                pages++;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Art 1'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    expect(refreshes, 1);
    expect(pages, 0);
  });

  testWidgets('in-flight pagination suppresses repeated bottom asks', (
    tester,
  ) async {
    var calls = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          home: Scaffold(
            body: ArtworkFeedGrid(
              feed: ArtworkFeedState(
                items: <Artwork>[for (var i = 0; i < 40; i += 1) artwork(i)],
                nextCursor: 'next',
                isLoading: true,
                phase: FeedRequestPhase.paginating,
              ),
              emptyMessage: 'Empty',
              scrollController: controller,
              onLoadMore: () => calls += 1,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    controller.jumpTo(controller.position.maxScrollExtent - 200);
    await tester.pump();
    await tester.drag(find.byType(ArtworkFeedGrid), const Offset(0, -40));
    await tester.pump();
    await tester.drag(find.byType(ArtworkFeedGrid), const Offset(0, -40));
    await tester.pump();

    expect(calls, 0);
  });

  testWidgets('a skipped pagination ask unlocks on the next gesture', (
    tester,
  ) async {
    var asks = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ArtworkFeedGrid(
              feed: longFeed(),
              emptyMessage: 'Empty',
              scrollController: controller,
              onLoadMore: () => asks++,
            ),
          ),
        ),
      ),
    );
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    await tester.drag(find.byType(ArtworkFeedGrid), const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(asks, 1);
    // Simulate a gate skipping the ask: no loading state or widget rebuild.
    await tester.drag(find.byType(ArtworkFeedGrid), const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(asks, 2);
  });

  testWidgets(
    'pagination spinner occupies a full-width footer after the masonry',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ArtworkFeedGrid(
                feed: ArtworkFeedState(
                  items: [artwork(0)],
                  nextCursor: 'next',
                  isLoading: true,
                  phase: FeedRequestPhase.paginating,
                ),
                emptyMessage: 'Empty',
              ),
            ),
          ),
        ),
      );
      final footer = find.byType(SliverToBoxAdapter);
      expect(footer, findsOneWidget);
      expect(
        tester
            .getSize(find.descendant(of: footer, matching: find.byType(Center)))
            .width,
        tester.getSize(find.byType(ArtworkFeedGrid)).width,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  testWidgets('a drag at the exact bottom asks for the next page', (
    tester,
  ) async {
    var calls = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          home: Scaffold(
            body: ArtworkFeedGrid(
              feed: longFeed(),
              emptyMessage: 'Empty',
              scrollController: controller,
              onLoadMore: () => calls += 1,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Land exactly on the bottom edge; a further downward drag can only
    // overscroll, and must still request the next page. This is the
    // masonry-aligned-bottom case that used to stall.
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    await tester.drag(find.byType(ArtworkFeedGrid), const Offset(0, -60));
    await tester.pump();

    expect(calls, greaterThan(0));
  });

  testWidgets(
    'page completing at the bottom loads again even if content barely grows',
    (tester) async {
      var calls = 0;
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var feed = ArtworkFeedState(
        items: <Artwork>[for (var i = 0; i < 60; i += 1) artwork(i)],
        nextCursor: 'next',
      );

      Future<void> pumpFeed() => tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          child: MaterialApp(
            home: Scaffold(
              body: ArtworkFeedGrid(
                feed: feed,
                emptyMessage: 'Empty',
                scrollController: controller,
                onLoadMore: () => calls += 1,
              ),
            ),
          ),
        ),
      );

      await pumpFeed();
      controller.jumpTo(controller.position.maxScrollExtent - 200);
      await tester.pump();
      await tester.drag(find.byType(ArtworkFeedGrid), const Offset(0, -40));
      await tester.pump();
      expect(calls, 1);

      feed = ArtworkFeedState(
        items: <Artwork>[for (var i = 0; i < 60; i += 1) artwork(i)],
        nextCursor: 'next',
        isLoading: true,
        phase: FeedRequestPhase.paginating,
      );
      await pumpFeed();
      await tester.pump();

      // The page completes while the user stays near the bottom but the scroll
      // extent barely grows (aligned columns). The next bottom drag must still
      // page again without scrolling back up.
      feed = ArtworkFeedState(
        items: <Artwork>[for (var i = 0; i < 62; i += 1) artwork(i)],
        nextCursor: 'next-2',
      );
      await pumpFeed();
      controller.jumpTo(controller.position.maxScrollExtent - 200);
      await tester.pump();

      await tester.drag(find.byType(ArtworkFeedGrid), const Offset(0, -40));
      await tester.pump();
      expect(calls, 2);
    },
  );

  testWidgets('a real drag near the bottom loads next page', (tester) async {
    var calls = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          home: Scaffold(
            body: ArtworkFeedGrid(
              feed: longFeed(),
              emptyMessage: 'Empty',
              scrollController: controller,
              onLoadMore: () {
                calls += 1;
              },
            ),
          ),
        ),
      ),
    );

    controller.jumpTo(controller.position.maxScrollExtent - 200);
    await tester.pump();
    await tester.drag(find.byType(ArtworkFeedGrid), const Offset(0, -40));
    await tester.pump();

    expect(calls, greaterThan(0));
  });

  testWidgets('pull-to-refresh from a scrolled position works in one gesture', (
    tester,
  ) async {
    var refreshes = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          home: Scaffold(
            body: ArtworkFeedGrid(
              feed: ArtworkFeedState(
                items: <Artwork>[for (var i = 0; i < 60; i += 1) artwork(i)],
                nextCursor: 'next',
              ),
              emptyMessage: 'Empty',
              scrollController: controller,
              onRefresh: () async {
                refreshes += 1;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Scrolled away from the top, a single pull-down must still refresh
    // (RefreshIndicatorTriggerMode.anywhere) instead of only scrolling to the
    // top and demanding a second gesture.
    controller.jumpTo(200);
    await tester.pump();

    await tester.drag(find.byType(ArtworkFeedGrid), const Offset(0, 600));
    await tester.pumpAndSettle();

    expect(refreshes, greaterThan(0));
  });

  testWidgets('tall portrait cards never overflow', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          home: Scaffold(
            body: ArtworkFeedGrid(
              feed: ArtworkFeedState(
                items: <Artwork>[for (var i = 0; i < 12; i += 1) portrait(i)],
              ),
              emptyMessage: 'Empty',
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pulling upward in the pagination zone refreshes without loading more',
    (tester) async {
      var pages = 0;
      var refreshes = 0;
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: ArtworkFeedGrid(
                feed: ArtworkFeedState(
                  items: [for (var i = 0; i < 8; i++) artwork(i)],
                  nextCursor: 'next',
                ),
                emptyMessage: 'Empty',
                scrollController: scroll,
                onLoadMore: () => pages++,
                onRefresh: () async {
                  refreshes++;
                },
              ),
            ),
          ),
        ),
      );
      scroll.jumpTo(200);
      await tester.pump();
      expect(scroll.position.extentAfter, lessThan(400));
      await tester.drag(find.byType(ArtworkFeedGrid), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(refreshes, 1);
      expect(pages, 0);
    },
  );
}
