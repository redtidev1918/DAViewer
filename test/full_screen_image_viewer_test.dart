import 'dart:convert';

import 'package:daviewer/shared/widgets/full_screen_image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    'YAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  );

  testWidgets('zoom action switches to an interactive pan-enabled viewer', (
    tester,
  ) async {
    var artworkNavigation = 0;
    var longPressedPage = -1;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          home: FullScreenImageViewer(
            imageProvider: MemoryImage(bytes),
            onNextArtwork: () => artworkNavigation++,
            onImageLongPress: (page) => longPressedPage = page,
          ),
        ),
      ),
    );

    // 未缩放：没有 InteractiveViewer（它会在未缩放时抢走水平拖动），
    // 但有缩放按钮。
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.byIcon(Icons.zoom_in), findsOneWidget);

    // 缩放后切换到交互查看器，支持平移。
    await tester.tap(find.byIcon(Icons.zoom_in));
    await tester.pump();
    expect(find.byIcon(Icons.zoom_out_map), findsOneWidget);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.panEnabled, isTrue);
    expect(viewer.minScale, 1);
    expect(viewer.maxScale, 8);

    // 缩放状态下拖动应该被 InteractiveViewer 消费（不触发作品切换）。
    final controller = viewer.transformationController!;
    final before = controller.value.getTranslation();
    await tester.drag(find.byType(InteractiveViewer), const Offset(80, 40));
    await tester.pump();
    final after = controller.value.getTranslation();
    expect(after.x, isNot(before.x));
    expect(artworkNavigation, 0);
    await tester.longPress(find.byType(InteractiveViewer));
    expect(longPressedPage, 0);
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('horizontal swipe at base zoom navigates to next artwork', (
    tester,
  ) async {
    var next = 0;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => FullScreenImageViewer(
                    imageProvider: MemoryImage(bytes),
                    onNextArtwork: () => next++,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // 在基础缩放下直接向左滑——手势由全屏查看器自身的
    // GestureDetector 处理（不经过 InteractiveViewer）。
    await tester.drag(find.byType(Scaffold), const Offset(-180, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(next, 1);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('multi-image viewer starts on the requested page and swipes', (
    tester,
  ) async {
    var previousArtwork = 0;
    var longPressedPage = -1;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          home: FullScreenImageViewer(
            imageProvider: MemoryImage(bytes),
            additionalMedia: <ImageProvider<Object>>[MemoryImage(bytes)],
            initialPage: 1,
            onPreviousArtwork: () => previousArtwork++,
            onImageLongPress: (page) => longPressedPage = page,
          ),
        ),
      ),
    );

    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.controller?.initialPage, 1);
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    await tester.longPress(find.byType(Scaffold));
    expect(longPressedPage, 1);

    await tester.fling(find.byType(PageView), const Offset(700, 0), 1000);
    await tester.pumpAndSettle();

    expect(pageView.controller?.page, 0);
    expect(previousArtwork, 0);
    await tester.longPress(find.byType(Scaffold));
    expect(longPressedPage, 0);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byIcon(Icons.zoom_in), findsNothing);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsNothing);

    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byIcon(Icons.zoom_in), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('fullscreen requires a new edge swipe to change artwork', (
    tester,
  ) async {
    var nextArtwork = 0;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => FullScreenImageViewer(
                    imageProvider: MemoryImage(bytes),
                    additionalMedia: <ImageProvider<Object>>[
                      MemoryImage(bytes),
                    ],
                    onNextArtwork: () => nextArtwork++,
                  ),
                ),
              ),
              child: const Text('open multi'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open multi'));
    await tester.pumpAndSettle();

    // First gesture belongs exclusively to the image pager.
    await tester.fling(find.byType(PageView), const Offset(-700, 0), 1000);
    await tester.pumpAndSettle();
    expect(nextArtwork, 0);
    expect(find.byType(FullScreenImageViewer), findsOneWidget);

    // A separate outward gesture that starts at the last image may navigate
    // to the next artwork.
    await tester.drag(find.byType(PageView), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(nextArtwork, 1);
    expect(find.text('open multi'), findsOneWidget);
  });
}
