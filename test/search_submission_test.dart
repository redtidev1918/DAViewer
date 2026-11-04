import 'package:dakit_core/dakit_core.dart';
import 'package:daviewer/core/feed/artwork_feed_controller.dart';
import 'package:daviewer/features/search/search_providers.dart';
import 'package:daviewer/features/search/search_screen.dart';
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final useButton in [false, true]) {
    testWidgets('gallery URL opens via ${useButton ? 'button' : 'keyboard'}', (
      tester,
    ) async {
      final searches = <String>[];
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SearchScreen()),
          GoRoute(
            path: '/artist/:username',
            builder: (_, state) =>
                Text('artist:${state.pathParameters['username']}'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recommendedTagsProvider.overrideWith((ref) async => []),
            tagPreviewProvider.overrideWith((ref, tag) async => null),
            searchFeedProvider.overrideWith((ref, query) {
              searches.add(query);
              return ArtworkFeedController(
                (_) async => const Page<Artwork>(items: [], hasMore: false),
              );
            }),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.enterText(
        find.byType(TextField),
        'https://www.deviantart.com/cyberxiandou-vore/gallery',
      );
      // A pasted link must not start a keyword request after the debounce.
      await tester.pump(const Duration(milliseconds: 500));
      expect(searches, isEmpty);
      if (useButton) {
        await tester.tap(find.widgetWithIcon(IconButton, Icons.search));
      } else {
        await tester.testTextInput.receiveAction(TextInputAction.search);
      }
      await tester.pumpAndSettle();
      expect(find.text('artist:cyberxiandou-vore'), findsOneWidget);
      expect(searches, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
