import 'package:dakit_core/dakit_core.dart';
import 'package:daviewer/core/auth/personalized_session_status.dart';
import 'package:daviewer/core/auth/web_session_status.dart';
import 'package:daviewer/core/feed/artwork_feed_controller.dart';
import 'package:daviewer/features/home/recommended_degraded_banner.dart';
import 'package:daviewer/shared/widgets/artwork_feed_grid.dart';
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

// These are domain Page objects testing the host's scheduling contract, not
// fixtures claiming to represent DeviantArt's private response protocol.
Artwork card(int i) => Artwork(
  id: '$i',
  title: 'Art $i',
  author: const UserProfile(id: 'u', username: 'artist'),
  pageUri: Uri.parse('https://example.test/$i'),
  media: const [
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

void main() {
  testWidgets(
    'pagination failure preserves cards and retries only on an explicit tap',
    (tester) async {
      var calls = 0;
      final provider =
          StateNotifierProvider<ArtworkFeedController, ArtworkFeedState>(
            (ref) => ArtworkFeedController((request) async {
              calls++;
              await Future<void>.delayed(const Duration(milliseconds: 50));
              if (calls == 2) throw StateError('offline');
              return Page(
                items: [
                  for (
                    var i = calls == 1 ? 0 : 40;
                    i < (calls == 1 ? 40 : 80);
                    i++
                  )
                    card(i),
                ],
                hasMore: calls == 1,
                nextCursor: calls == 1 ? 'a' : null,
              );
            }),
          );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => ArtworkFeedGrid(
                  feed: ref.watch(provider),
                  emptyMessage: 'Empty',
                  scrollController: scroll,
                  onLoadMore: () => ref.read(provider.notifier).loadMore(),
                  onRetryLoadMore: () =>
                      ref.read(provider.notifier).retryLoadMore(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      await tester.drag(find.byType(ArtworkFeedGrid), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(container.read(provider).items, hasLength(40));
      expect(
        container.read(provider).paginationStatus,
        FeedPaginationStatus.failed,
      );
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      await tester.drag(find.byType(ArtworkFeedGrid), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(calls, 2);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(calls, 3);
      expect(container.read(provider).items, hasLength(80));
      expect(container.read(provider).items.first.id, '0');
      expect(
        container.read(provider).paginationStatus,
        FeedPaginationStatus.exhausted,
      );
    },
  );

  testWidgets(
    'Android inertia appends three provider pages under degraded banner',
    (tester) async {
      final requests = <String?>[];
      final provider =
          StateNotifierProvider<ArtworkFeedController, ArtworkFeedState>(
            (ref) => ArtworkFeedController((request) async {
              requests.add(request.cursor);
              await Future<void>.delayed(const Duration(milliseconds: 50));
              final page = request.cursor == null
                  ? 0
                  : request.cursor == 'a'
                  ? 1
                  : 2;
              return Page(
                items: [
                  for (var i = page * 40; i < (page + 1) * 40; i++) card(i),
                ],
                hasMore: page < 2,
                nextCursor: page == 0
                    ? 'a'
                    : page == 1
                    ? 'b'
                    : null,
              );
            }),
          );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final identity = container.read(webSessionStatusProvider.notifier);
      identity.markHealthy(serverUsername: 'artist');
      container
          .read(personalizedSessionStatusProvider.notifier)
          .observe(
            cookieHeader: 'test=session',
            degraded: true,
            generation: identity.generation,
          );
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => Column(
                  children: [
                    RecommendedDegradedBanner(
                      onRetry: () => ref.read(provider.notifier).forceRefresh(),
                    ),
                    Expanded(
                      child: ArtworkFeedGrid(
                        feed: ref.watch(provider),
                        emptyMessage: 'Empty',
                        scrollController: scroll,
                        onLoadMore: () =>
                            ref.read(provider.notifier).loadMore(),
                        onRetryLoadMore: () =>
                            ref.read(provider.notifier).retryLoadMore(),
                        onRefresh: () =>
                            ref.read(provider.notifier).forceRefresh(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(container.read(provider).items, hasLength(40));
      expect(find.byType(RecommendedDegradedBanner), findsOneWidget);
      for (var page = 2; page <= 3; page++) {
        scroll.jumpTo(scroll.position.maxScrollExtent - 900);
        await tester.pump();
        await tester.fling(
          find.byType(ArtworkFeedGrid),
          const Offset(0, -200),
          5000,
        );
        await tester.pumpAndSettle();
        expect(container.read(provider).items, hasLength(page * 40));
        expect(container.read(provider).items.first.id, '0');
      }
      expect(requests, [null, 'a', 'b']);
      expect(
        container.read(provider).paginationStatus,
        FeedPaginationStatus.exhausted,
      );
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      expect(find.text('已加载全部内容'), findsOneWidget);
      await tester.drag(find.byType(ArtworkFeedGrid), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(requests, hasLength(3));
      expect(container.read(webSessionStatusProvider).isHealthy, isTrue);
      // Refresh is independently a first-page request, even after exhaustion.
      scroll.jumpTo(0);
      await tester.pump();
      await tester.drag(find.byType(ArtworkFeedGrid), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(requests, [null, 'a', 'b', null]);
      expect(container.read(provider).items, hasLength(40));
    },
  );
}
