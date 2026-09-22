import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:daviewer/features/artwork/media_viewer.dart';
import 'package:daviewer/shared/widgets/full_screen_image_viewer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

MediaAsset asset(
  String id,
  MediaKind kind, {
  MediaRole role = MediaRole.preview,
  Uri? uri,
  int? width,
  int? height,
  String? filename,
  MediaAvailability availability = MediaAvailability.available,
}) => MediaAsset(
  id: id,
  kind: kind,
  role: role,
  availability: availability,
  uri: uri,
  width: width,
  height: height,
  filename: filename,
);

void main() {
  test('returns null for empty media', () {
    expect(selectDisplayAsset(const <MediaAsset>[]), isNull);
  });

  test('prefers a playable video', () {
    final video = asset(
      'v',
      MediaKind.video,
      uri: Uri.parse('https://x/v.mp4'),
    );
    final image = asset(
      'i',
      MediaKind.image,
      uri: Uri.parse('https://x/i.jpg'),
    );
    expect(selectDisplayAsset(<MediaAsset>[image, video])?.id, 'v');
  });

  test('prefers the highest-quality playable video', () {
    final low = asset(
      'low',
      MediaKind.video,
      uri: Uri.parse('https://x/360.mp4'),
      filename: '360p',
    );
    final high = asset(
      'high',
      MediaKind.video,
      uri: Uri.parse('https://x/1080.mp4'),
      filename: '1080p',
    );
    expect(selectDisplayAsset(<MediaAsset>[low, high])?.id, 'high');
  });

  test('skips a video without a URI', () {
    final video = asset('v', MediaKind.video);
    final image = asset(
      'i',
      MediaKind.image,
      uri: Uri.parse('https://x/i.jpg'),
    );
    expect(selectDisplayAsset(<MediaAsset>[video, image])?.id, 'i');
  });

  test('prefers an animation over images', () {
    final anim = asset(
      'a',
      MediaKind.animation,
      uri: Uri.parse('https://x/a.swf'),
    );
    final image = asset(
      'i',
      MediaKind.image,
      uri: Uri.parse('https://x/i.jpg'),
    );
    expect(selectDisplayAsset(<MediaAsset>[image, anim])?.id, 'a');
  });

  test('picks the largest preview image', () {
    final small = asset(
      's',
      MediaKind.image,
      width: 400,
      uri: Uri.parse('https://x/s.jpg'),
    );
    final large = asset(
      'l',
      MediaKind.image,
      width: 1000,
      uri: Uri.parse('https://x/l.jpg'),
    );
    expect(selectDisplayAsset(<MediaAsset>[small, large])?.id, 'l');
  });

  test('falls back to any image when no preview exists', () {
    final original = asset(
      'o',
      MediaKind.image,
      role: MediaRole.original,
      uri: Uri.parse('https://x/o.jpg'),
    );
    expect(selectDisplayAsset(<MediaAsset>[original])?.id, 'o');
  });

  test('prefers an accessible preview over gated full-size content', () {
    final gatedContent = asset(
      'content',
      MediaKind.image,
      width: 2400,
      uri: Uri.parse('https://x/content.jpg'),
      availability: MediaAvailability.purchaseRequired,
    );
    final preview = asset(
      'preview',
      MediaKind.image,
      width: 800,
      uri: Uri.parse('https://x/preview.jpg'),
    );
    expect(
      selectDisplayAsset(<MediaAsset>[gatedContent, preview])?.id,
      'preview',
    );
  });

  test('prefers viewable full content over a blurred preview', () {
    final content = asset(
      'content',
      MediaKind.image,
      width: 2400,
      uri: Uri.parse('https://x/content.jpg'),
    );
    final preview = asset(
      'preview',
      MediaKind.image,
      width: 800,
      uri: Uri.parse('https://x/preview.jpg'),
    );
    expect(selectDisplayAsset(<MediaAsset>[content, preview])?.id, 'content');
  });

  testWidgets('multi-image pages consume swipes before the next artwork', (
    tester,
  ) async {
    var nextArtwork = 0;
    final first = asset(
      'first',
      MediaKind.image,
      uri: Uri.parse('https://example.test/first.jpg'),
    );
    final second = asset(
      'second',
      MediaKind.image,
      uri: Uri.parse('https://example.test/second.jpg'),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 400,
                child: MediaViewer(
                  media: <MediaAsset>[first],
                  additionalMedia: <MediaAsset>[second],
                  onNextArtwork: () => nextArtwork++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('2 / 2'), findsOneWidget);
    expect(nextArtwork, 0);

    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(nextArtwork, 1);
  });

  testWidgets('opening a multi-image page passes every image to fullscreen', (
    tester,
  ) async {
    MediaAsset? requestedDownload;
    var requestedPage = -1;
    final first = asset(
      'first',
      MediaKind.image,
      uri: Uri.parse('https://example.test/first.jpg'),
    );
    final second = asset(
      'second',
      MediaKind.image,
      uri: Uri.parse('https://example.test/second.jpg'),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 400,
                child: MediaViewer(
                  media: <MediaAsset>[first],
                  additionalMedia: <MediaAsset>[second],
                  onDownloadImage: (asset, page) {
                    requestedDownload = asset;
                    requestedPage = page;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final inlineImage = find.byType(CachedNetworkImage).first;
    final tapTarget = find
        .ancestor(of: inlineImage, matching: find.byType(GestureDetector))
        .first;
    await tester.tap(tapTarget);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final viewer = tester.widget<FullScreenImageViewer>(
      find.byType(FullScreenImageViewer),
    );
    expect(viewer.additionalMedia, hasLength(1));
    expect(viewer.initialPage, 0);
    viewer.onImageLongPress!(1);
    expect(requestedDownload, same(second));
    expect(requestedPage, 1);
    expect(
      find.descendant(
        of: find.byType(FullScreenImageViewer),
        matching: find.byType(PageView),
      ),
      findsOneWidget,
    );
  });
}
