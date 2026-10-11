import 'dart:async';

import 'package:dakit_core/dakit_core.dart';
import 'package:daviewer/features/artwork/artwork_store.dart';
import 'package:daviewer/features/artwork/favourite_actions.dart';
import 'package:daviewer/shared/widgets/artwork_card.dart';
import 'package:daviewer/shared/widgets/artwork_favourite_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final artwork = Artwork(
    id: 'fav-test',
    title: 'Artwork',
    author: const UserProfile(id: 'artist', username: 'artist'),
    pageUri: Uri.parse('https://example.test/art/fav-test'),
    media: const [],
  );

  testWidgets(
    'card one-tap favourite syncs both buttons without opening detail',
    (tester) async {
      final pending = Completer<bool>();
      var requests = 0;
      var opened = 0;
      final container = ProviderContainer(
        overrides: [
          favouriteRequestProvider.overrideWithValue((id, favourite) {
            requests++;
            expect(id, artwork.id);
            expect(favourite, isTrue);
            return pending.future;
          }),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    width: 200,
                    child: ArtworkCard(artwork: artwork, onTap: () => opened++),
                  ),
                  ArtworkFavouriteButton(artwork: artwork, showLabel: true),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(requests, 1);
      expect(opened, 0);
      expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      pending.complete(true);
      await tester.pump();
      expect(
        container.read(artworkStoreProvider)[artwork.id]!.isFavourited,
        isTrue,
      );
      expect(find.byIcon(Icons.favorite), findsNWidgets(2));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('failed unfavourite keeps the filled heart and allows retry', (
    tester,
  ) async {
    final saved = artwork.copyWith(isFavourited: true);
    final container = ProviderContainer(
      overrides: [
        favouriteRequestProvider.overrideWithValue(
          (id, favourite) async => throw StateError('test failure'),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(artworkStoreProvider.notifier).putAll([saved]);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: ArtworkFavouriteButton(artwork: saved)),
        ),
      ),
    );
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton)).onPressed,
      isNotNull,
    );
    expect(
      container.read(artworkStoreProvider)[saved.id]!.isFavourited,
      isTrue,
    );
    expect(find.textContaining('test failure'), findsOneWidget);
  });
}
