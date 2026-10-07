import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:daviewer/app/router.dart';
import 'package:daviewer/features/artwork/artwork_detail_providers.dart';
import 'package:daviewer/features/artwork/artwork_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('detail route can navigate forward repeatedly with animation', (
    tester,
  ) async {
    final session = ArtworkBrowseSession(<String>['a', 'b', 'c']);
    final user = UserProfile(id: 'user', username: 'artist');
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => context.push(
                '/artwork/a',
                extra: ArtworkRouteContext(session: session),
              ),
              child: const Text('open'),
            ),
          ),
        ),
        GoRoute(path: '/artwork/:id', pageBuilder: artworkDetailPage),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: <Override>[
          artworkDetailProvider.overrideWith((ref, id) async {
            return Artwork(
              id: id,
              title: 'Artwork $id',
              author: user,
              pageUri: Uri.parse('https://example.test/art/$id'),
              media: const <MediaAsset>[],
            );
          }),
          originalFileProvider.overrideWith((ref, id) async {
            return OriginalFileResolution(
              asset: MediaAsset(
                id: '$id:missing',
                kind: MediaKind.unknown,
                role: MediaRole.original,
                availability: MediaAvailability.missing,
              ),
            );
          }),
          artworkDescriptionProvider.overrideWith((ref, id) async => null),
          artworkDescriptionHtmlProvider.overrideWith((ref, id) async => null),
          journalHtmlProvider.overrideWith((ref, id) async => null),
          additionalMediaProvider.overrideWith(
            (ref, id) async => const <MediaAsset>[],
          ),
          artworkTagsProvider.overrideWith((ref, id) async => const <String>[]),
          favouriteStatusProvider.overrideWith((ref, id) async => false),
          moreLikeThisProvider.overrideWith(
            (ref, id) async => const MoreLikeThisResult(artworks: <Artwork>[]),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Artwork a'), findsWidgets);

    await tester.drag(find.byType(ArtworkSwipeRegion), const Offset(-180, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(SlideTransition), findsWidgets);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/artwork/b');
    expect(find.text('Artwork b'), findsWidgets);

    await tester.drag(find.byType(ArtworkSwipeRegion), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/artwork/c');
    expect(find.text('Artwork c'), findsWidgets);
  });
}
