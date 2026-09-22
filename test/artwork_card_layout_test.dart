import 'package:dakit_core/dakit_core.dart';
import 'package:daviewer/shared/widgets/artwork_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Artwork _bannerArtwork() => Artwork(
  id: 'banner',
  title: 'A very wide artwork title',
  author: const UserProfile(id: 'artist-id', username: 'artist'),
  pageUri: Uri.parse('https://example.test/art/banner'),
  media: const <MediaAsset>[
    MediaAsset(
      id: 'preview',
      kind: MediaKind.image,
      role: MediaRole.preview,
      availability: MediaAvailability.available,
      width: 3000,
      height: 1000,
    ),
  ],
);

Artwork _portraitArtwork() => Artwork(
  id: 'portrait',
  title: 'A very tall portrait artwork',
  author: const UserProfile(id: 'artist-id', username: 'artist'),
  pageUri: Uri.parse('https://example.test/art/portrait'),
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

void main() {
  testWidgets('mobile banner previews keep more visual height', (tester) async {
    late double ratio;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: Builder(
            builder: (context) {
              ratio = artworkPreviewAspectRatio(context, _bannerArtwork());
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(ratio, 1.6);
  });

  testWidgets('title and author render below the image, not over it', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 180,
              child: ArtworkCard(artwork: _bannerArtwork()),
            ),
          ),
        ),
      ),
    );

    // The metadata is a normal card section beneath the image: title (up to
    // two lines) and the author with an @ prefix, without a gradient overlay.
    final title = tester.widget<Text>(find.text('A very wide artwork title'));
    expect(title.maxLines, 2);
    expect(find.text('@artist'), findsOneWidget);
  });

  testWidgets('narrow portrait rail card fits without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 140,
              height: 360,
              child: ArtworkCard(artwork: _portraitArtwork()),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
