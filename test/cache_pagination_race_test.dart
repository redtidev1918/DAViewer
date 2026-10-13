import 'dart:async';

import 'package:dakit_core/dakit_core.dart';
import 'package:daviewer/core/feed/artwork_feed_controller.dart';
import 'package:daviewer/shared/widgets/artwork_feed_grid.dart';
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

// Scheduling reproduction of the user's v0.5.16 retained-cache log timeline
// (2026-10-13 22:16:45 / :47 / :50), using domain pages rather than protocol fixtures.
void main() {
  testWidgets(
    'cached preview scroll cannot lock pagination before the live first page',
    (tester) async {
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
      final firstPage = Completer<Page<Artwork>>();
      final requests = <String?>[];
      var asks = 0;
      final provider =
          StateNotifierProvider<ArtworkFeedController, ArtworkFeedState>(
            (ref) => ArtworkFeedController((request) async {
              requests.add(request.cursor);
              if (request.cursor == null) return firstPage.future;
              return Page(
                items: [for (var i = 24; i < 48; i++) card(i)],
                hasMore: false,
              );
            }),
          );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final notifier = container.read(provider.notifier);
      notifier.hydrate([
        for (var i = 0; i < 24; i++) card(i),
      ], DateTime(2026, 10, 13));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => ArtworkFeedGrid(
                  feed: ref.watch(provider),
                  emptyMessage: 'Empty',
                  scrollController: scroll,
                  onLoadMore: () {
                    asks++;
                    notifier.loadMore();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      await tester.drag(find.byType(ArtworkFeedGrid), const Offset(0, -80));
      await tester.pump(const Duration(milliseconds: 500));
      final earlyAsks = asks;
      expect(requests, [null]);
      // Same item count, but the live page now supplies the real cursor.
      firstPage.complete(
        Page(
          items: [for (var i = 0; i < 24; i++) card(i)],
          hasMore: true,
          nextCursor: 'opaque-next',
        ),
      );
      await tester.pumpAndSettle();
      expect(container.read(provider).hasMore, isTrue);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      await tester.drag(find.byType(ArtworkFeedGrid), const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(requests, [null, 'opaque-next']);
      expect(
        earlyAsks,
        0,
        reason: 'A cache without a live cursor cannot spend the trigger latch',
      );
      expect(container.read(provider).items, hasLength(48));
      expect(container.read(provider).items.first.id, '0');
    },
  );
}
