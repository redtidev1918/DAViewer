import 'package:dakit_core/dakit_core.dart';
import 'package:daviewer/core/l10n/app_strings.dart';
import 'package:daviewer/features/artwork/artwork_detail_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Artwork _lockedArtwork() => Artwork(
  id: 'locked',
  title: 'Members only',
  author: const UserProfile(id: '1', username: 'artist'),
  pageUri: Uri.parse('https://example.test/art/locked'),
  media: const <MediaAsset>[
    MediaAsset(
      id: 'preview',
      kind: MediaKind.image,
      role: MediaRole.preview,
      availability: MediaAvailability.restricted,
    ),
  ],
  downloadAvailability: MediaAvailability.restricted,
);

void main() {
  testWidgets('detail header explains restricted viewing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArtworkHeader(artwork: _lockedArtwork(), s: AppStrings.zh),
        ),
      ),
    );

    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.text('受限'), findsOneWidget);
  });
}
