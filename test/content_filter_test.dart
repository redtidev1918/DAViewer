import 'dart:convert';
import 'dart:io';

import 'package:dakit_core/dakit_core.dart';
import 'package:daviewer/core/feed/artwork_feed_controller.dart';
import 'package:daviewer/core/filtering/content_filter_provider.dart';
import 'package:daviewer/core/filtering/content_rules.dart';
import 'package:daviewer/core/filtering/platform_ai_metadata.dart';
import 'package:daviewer/shared/widgets/artwork_card.dart';
import 'package:daviewer/shared/widgets/artwork_feed_grid.dart';
import 'package:daviewer/features/settings/content_blocks_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Artwork work(
  String id, {
  String artist = 'Artist',
  List<String> tags = const [],
}) => Artwork(
  id: id,
  title: 'Work $id',
  author: UserProfile(id: artist, username: artist),
  pageUri: Uri.parse('https://www.deviantart.com/$artist/art/Work-$id'),
  media: const [],
  tags: tags,
);

void main() {
  testWidgets('new platform evidence updates an already visible grid', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialContentRulesProvider.overrideWithValue(
            ContentRules(hideAi: true),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ArtworkFeedGrid(
              feed: ArtworkFeedState(items: [work('943398477')]),
              emptyMessage: 'Empty',
            ),
          ),
        ),
      ),
    );
    expect(find.byType(ArtworkCard), findsOneWidget);
    PlatformAiMetadata.instance.observe(
      jsonDecode(
        File('test/fixtures/content_filter/platform_ai_flags.json')
            .readAsStringSync(),
      ),
    );
    await tester.pump();
    expect(find.byType(ArtworkCard), findsNothing);
  });

  testWidgets(
    'settings can add a tag and remove it without losing other rules',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('filter-settings-'),
      ))!;
      final store = ContentRulesStore(directory: dir);
      final container = ProviderContainer(
        overrides: [
          contentRulesStoreProvider.overrideWithValue(store),
          initialContentRulesProvider.overrideWithValue(
            ContentRules(artists: {'alice'}),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await dir.delete(recursive: true);
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ContentBlocksScreen()),
        ),
      );
      await tester.tap(find.text('添加').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '#CAT');
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, '添加'));
      });
      for (
        var i = 0;
        i < 50 &&
            !(container
                    .read(contentRulesProvider)
                    .value
                    ?.tags
                    .contains('cat') ??
                false);
        i++
      ) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('#cat'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(
          find.descendant(
            of: find.widgetWithText(ListTile, '#cat'),
            matching: find.byType(IconButton),
          ),
        );
      });
      for (
        var i = 0;
        i < 50 &&
            (container.read(contentRulesProvider).value?.tags.contains('cat') ??
                false);
        i++
      ) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('#cat'), findsNothing);
      final restored = await tester.runAsync(store.load);
      expect(restored!.tags, isEmpty);
      expect(restored.artists, {'alice'});
    },
  );

  test(
    'rules match exact normalized tags and artist names, not substrings',
    () {
      final rules = ContentRules.fromJson({
        'tags': ['#Cat'],
        'artists': ['@Artist'],
      });
      expect(rules.blocks(work('1')), isTrue);
      expect(rules.blocks(work('2', artist: 'other', tags: ['CAT'])), isTrue);
      expect(
        rules.blocks(work('3', artist: 'Artist2', tags: ['cathedral'])),
        isFalse,
      );
    },
  );
  test('artwork URL and numeric ID refer to the same blocked work', () {
    final rules = ContentRules(artworks: {'123': 'Saved title'});
    expect(
      rules.blocks(
        work('123').copyWith(id: 'bfb02b08-9838-49f3-a794-1e74c339bce5'),
      ),
      isTrue,
    );
    expect(artworkBlockKey('https://evil.example/art/Work-123'), isEmpty);
    expect(
      artworkBlockKey('https://www.deviantart.com/artist/gallery/123'),
      isEmpty,
    );
  });
  test(
    'live platform evidence distinguishes AI creation from NoAI permission',
    () {
      final metadata = PlatformAiMetadata();
      addTearDown(metadata.dispose);
      metadata.observe(
        jsonDecode(
          File('test/fixtures/content_filter/platform_ai_flags.json')
              .readAsStringSync(),
        ),
      );
      final rules = ContentRules(hideAi: true);
      for (final (id, expected) in [
        ('943398477', true),
        ('926918391', false),
        ('99999', false),
      ]) {
        final artwork = work(id, tags: ['aiart']);
        expect(
          rules.blocks(artwork, isAi: metadata.forArtwork(artwork)),
          expected,
        );
      }
    },
  );
  test(
    'rules persist and queued updates preserve independent changes',
    () async {
      final dir = await Directory.systemTemp.createTemp('content-rules-');
      addTearDown(() => dir.delete(recursive: true));
      final store = ContentRulesStore(directory: dir);
      final container = ProviderContainer(
        overrides: [contentRulesStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final controller = container.read(contentRulesProvider.notifier);
      await Future.wait([
        controller.blockArtist('Alice'),
        controller.blockArtwork(work('123')),
        controller.changeRules((r) => r.copyWith(hideAi: true, tags: {'cat'})),
      ]);
      final restored = await store.load();
      expect(restored.hideAi, isTrue);
      expect(restored.artists, {'alice'});
      expect(restored.tags, {'cat'});
      expect(restored.artworks.keys, ['123']);
      await controller.changeRules((r) => r.copyWith(artworks: {}));
      expect((await store.load()).artworks, isEmpty);
    },
  );
  testWidgets(
    'fully filtered page keeps an explicit pagination action and unblocks reactively',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          initialContentRulesProvider.overrideWithValue(
            ContentRules(artists: {'artist'}),
          ),
        ],
      );
      addTearDown(container.dispose);
      var loads = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ArtworkFeedGrid(
                feed: ArtworkFeedState(items: [work('1')], nextCursor: 'more'),
                emptyMessage: 'Empty',
                onLoadMore: () => loads++,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(ArtworkCard), findsNothing);
      expect(find.text('当前作品已被屏蔽设置隐藏'), findsOneWidget);
      await tester.tap(find.text('加载更多作品'));
      expect(loads, 1);
      container.read(contentRulesProvider.notifier).state = AsyncData(
        ContentRules(),
      );
      await tester.pump();
      expect(find.byType(ArtworkCard), findsOneWidget);
    },
  );
  testWidgets('settings shows each category and saved entries', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialContentRulesProvider.overrideWithValue(
            ContentRules(
              hideAi: true,
              tags: {'cat'},
              artists: {'alice'},
              artworks: {'123': 'Work 123'},
            ),
          ),
        ],
        child: const MaterialApp(home: ContentBlocksScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('隐藏 AI 作品'), findsOneWidget);
    expect(find.text('#cat'), findsOneWidget);
    expect(find.text('@alice'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Work 123'), 250);
    expect(find.text('Work 123'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
