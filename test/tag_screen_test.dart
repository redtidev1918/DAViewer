import 'package:dakit_core/dakit_core.dart' as dakit;
import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:daviewer/core/feed/artwork_feed_controller.dart';
import 'package:daviewer/features/tag/tag_screen.dart';
import 'package:daviewer/shared/widgets/compact_tag_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('related tags collapse when the artwork feed scrolls down', (
    tester,
  ) async {
    final user = dakit.UserProfile(id: 'u', username: 'artist');
    final items = List<dakit.Artwork>.generate(
      30,
      (index) => dakit.Artwork(
        id: 'art-$index',
        title: 'Artwork $index',
        author: user,
        pageUri: Uri.parse('https://example.test/art-$index'),
        media: const <dakit.MediaAsset>[],
      ),
    );
    final controller = ArtworkFeedController(
      (_) async => dakit.Page<dakit.Artwork>(items: items, hasMore: false),
    );

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: <Override>[
          tagFeedProvider(('cat', dakit.BrowseSort.recent))
              .overrideWith((ref) => controller),
          relatedTagsProvider('cat')
              .overrideWith((ref) async => <String>['catart', 'cats']),
        ],
        child: const MaterialApp(home: TagScreen(tag: 'cat')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CompactTagStrip), findsOneWidget);
    await tester.drag(find.byType(MasonryGridView), const Offset(0, -320));
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.byType(CompactTagStrip), findsNothing);
  });
}
