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
      const ProviderScope(
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

  testWidgets('trackpad scroll near the bottom loads next page', (
    tester,
  ) async {
    var calls = 0;
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

  testWidgets('a real drag near the bottom loads next page', (tester) async {
    var calls = 0;
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

  testWidgets('tall portrait cards never overflow', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
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
}
