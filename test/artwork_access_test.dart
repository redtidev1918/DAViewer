import 'package:dakit_core/dakit_core.dart';
import 'package:daviewer/core/l10n/app_strings.dart';
import 'package:daviewer/features/artwork/artwork_access.dart';
import 'package:flutter_test/flutter_test.dart';

Artwork _artwork({
  MediaAvailability previewAvailability = MediaAvailability.available,
  MediaAvailability downloadAvailability = MediaAvailability.unavailable,
}) => Artwork(
  id: 'art',
  title: 'Art',
  author: const UserProfile(id: '1', username: 'artist'),
  pageUri: Uri.parse('https://example.test/art'),
  media: <MediaAsset>[
    MediaAsset(
      id: 'preview',
      kind: MediaKind.image,
      role: MediaRole.preview,
      availability: previewAvailability,
    ),
  ],
  downloadAvailability: downloadAvailability,
);

void main() {
  test('gated preview is a view lock', () {
    final artwork = _artwork(
      previewAvailability: MediaAvailability.purchaseRequired,
    );

    expect(artworkViewLock(artwork), MediaAvailability.purchaseRequired);
  });

  test('paid download gate without gated preview is still a view lock', () {
    final artwork = _artwork(
      downloadAvailability: MediaAvailability.purchaseRequired,
    );

    expect(artworkViewLock(artwork), MediaAvailability.purchaseRequired);
  });

  test('not-downloadable NSFW art is not treated as locked', () {
    final artwork = _artwork(
      previewAvailability: MediaAvailability.available,
      downloadAvailability: MediaAvailability.unavailable,
    );

    expect(artworkViewLock(artwork), isNull);
  });

  test('lock label names subscription or purchase', () {
    expect(
      artworkViewLockLabel(AppStrings.zh, MediaAvailability.purchaseRequired),
      contains('订阅'),
    );
  });
}
