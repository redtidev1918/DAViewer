import 'dart:io';

import 'package:dakit_core/dakit_core.dart';
import 'package:daviewer/app/theme/app_theme.dart';
import 'package:daviewer/core/feed/artwork_feed_controller.dart';
import 'package:daviewer/core/l10n/app_strings.dart';
import 'package:daviewer/core/search/search_history_store.dart';
import 'package:daviewer/features/search/search_screen.dart';
import 'package:daviewer/features/search/search_providers.dart';
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  late Directory directory;
  late PathProviderPlatform previousPaths;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('search-history-test');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    await directory.delete(recursive: true);
  });

  Future<ProviderContainer> pumpSearch(
    WidgetTester tester,
    List<String> queries, {
    List<String>? searches,
    GoRouter? router,
  }) async {
    await tester.runAsync(() async {
      for (final query in queries.reversed) {
        await SearchHistoryStore.add(query);
      }
    });
    final container = ProviderContainer(
      overrides: [
        appLanguageProvider.overrideWith(
          (ref) => AppLanguageController(AppLanguage.en),
        ),
        recommendedTagsProvider.overrideWith((ref) async => []),
        tagPreviewProvider.overrideWith((ref, tag) async => null),
        searchFeedProvider.overrideWith((ref, query) {
          searches?.add(query);
          return ArtworkFeedController(
            (_) async => const Page<Artwork>(items: [], hasMore: false),
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      container.read(searchHistoryProvider);
      await SearchHistoryStore.load();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: router == null
            ? MaterialApp(theme: AppTheme.light(), home: const SearchScreen())
            : MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'recent rows show a count, expand and collapse without searching',
    (tester) async {
      final searches = <String>[];
      await pumpSearch(tester, [
        for (var i = 0; i < 8; i++) 'query $i',
      ], searches: searches);
      expect(find.byType(ListTile), findsNWidgets(5));
      expect(find.text('8 searches · Most recent first'), findsOneWidget);
      expect(find.text('query 5'), findsNothing);
      await tester.tap(find.text('View all'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(8));
      await tester.ensureVisible(find.text('Show less'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show less'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(5));
      expect(searches, isEmpty);
    },
  );

  testWidgets('deleting a row preserves other queries and idle search', (
    tester,
  ) async {
    final container = await pumpSearch(tester, ['remove me', 'keep me']);
    final row = find.widgetWithText(ListTile, 'remove me');
    expect(row, findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(
        find.descendant(of: row, matching: find.byTooltip('Delete')),
      );
      await SearchHistoryStore.load();
    });
    await tester.pumpAndSettle();
    expect(container.read(searchHistoryProvider), ['keep me']);
    expect(find.text('remove me'), findsNothing);
    expect(find.widgetWithText(ListTile, 'keep me'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(await tester.runAsync(() => SearchHistoryStore.load()), ['keep me']);
  });

  testWidgets('tapping a row repeats its query and moves it to the front', (
    tester,
  ) async {
    final searches = <String>[];
    await pumpSearch(tester, ['newer', 'older'], searches: searches);
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(ListTile, 'older'));
      await SearchHistoryStore.load();
    });
    await tester.pumpAndSettle();
    expect(searches, ['older']);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'older',
    );
    expect(await tester.runAsync(() => SearchHistoryStore.load()), [
      'older',
      'newer',
    ]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('clearing history requires confirmation and persists', (
    tester,
  ) async {
    await pumpSearch(tester, ['keep me']);
    await tester.runAsync(() => tester.tap(find.text('Clear history')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('Cancel')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'keep me'), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('Clear history')));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Clear history'));
      await SearchHistoryStore.load();
    });
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNothing);
    expect(await tester.runAsync(() => SearchHistoryStore.load()), isEmpty);
  });

  for (final action in ['submit', 'button', 'popular', 'history']) {
    testWidgets('tag $action opens the tag page and persists tagged history', (
      tester,
    ) async {
      final searches = <String>[];
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SearchScreen()),
          GoRoute(
            path: '/tag/:tag',
            builder: (_, state) => Text('tag:${state.pathParameters['tag']}'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpSearch(
        tester,
        action == 'history' ? ['older', '#digitalart'] : [],
        searches: searches,
        router: router,
      );
      if (action == 'submit' || action == 'button') {
        await tester.enterText(find.byType(TextField), '# digitalart ');
        await tester.pump(const Duration(milliseconds: 500));
      }
      if (action == 'history') {
        expect(
          find.descendant(
            of: find.widgetWithText(ListTile, '#digitalart'),
            matching: find.byIcon(Icons.tag),
          ),
          findsOneWidget,
        );
      }
      await tester.runAsync(() async {
        switch (action) {
          case 'submit':
            tester.widget<TextField>(find.byType(TextField)).onSubmitted!(
              '# digitalart ',
            );
          case 'button':
            await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
          case 'popular':
            await tester.tap(find.text('#digitalart'));
          case 'history':
            await tester.tap(find.widgetWithText(ListTile, '#digitalart'));
        }
        await Future<void>.delayed(Duration.zero);
        await SearchHistoryStore.load();
      });
      await tester.pumpAndSettle();
      expect(find.text('tag:digitalart'), findsOneWidget);
      expect(searches, isEmpty);
      expect(await tester.runAsync(() => SearchHistoryStore.load()), [
        '#digitalart',
        if (action == 'history') 'older',
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
