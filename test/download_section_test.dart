import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:daviewer/core/l10n/app_strings.dart';
import 'package:daviewer/features/artwork/download_section.dart';
import 'package:daviewer/features/artwork/download_planner.dart';
import 'package:daviewer/features/artwork/download_reason.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  const en = AppStrings.en;
  const zh = AppStrings.zh;

  test('availabilityLabel maps each state', () {
    expect(availabilityLabel(en, MediaAvailability.available), 'Available');
    expect(availabilityLabel(en, MediaAvailability.unavailable), 'Unavailable');
    expect(
      availabilityLabel(en, MediaAvailability.missing),
      'Deleted or unavailable',
    );
    expect(availabilityLabel(zh, MediaAvailability.available), '可下载');
  });

  test('availabilityHint is empty only for available state', () {
    expect(availabilityHint(en, MediaAvailability.available), isEmpty);
    expect(availabilityHint(en, MediaAvailability.missing), isNotEmpty);
  });

  test('availabilityHint is non-empty for restricted states', () {
    expect(availabilityHint(en, MediaAvailability.loginRequired), isNotEmpty);
    expect(
      availabilityHint(en, MediaAvailability.purchaseRequired),
      isNotEmpty,
    );
    expect(availabilityHint(en, MediaAvailability.restricted), isNotEmpty);
    expect(availabilityHint(en, MediaAvailability.unavailable), isNotEmpty);
  });

  test('formatBytes formats B, KB, and MB', () {
    expect(formatBytes(500), '500 B');
    expect(formatBytes(2048), '2.0 KB');
    expect(formatBytes(3 * 1024 * 1024), '3.0 MB');
  });

  test('provider free-limit and creator-disabled reasons are localized', () {
    const limit = MediaAsset(
      id: 'limit',
      kind: MediaKind.image,
      role: MediaRole.original,
      availability: MediaAvailability.unavailable,
      availabilityReason: 'Free download limit reached.',
    );
    const disabled = MediaAsset(
      id: 'disabled',
      kind: MediaKind.image,
      role: MediaRole.original,
      availability: MediaAvailability.unavailable,
      availabilityReason: 'Deviation not downloadable.',
    );

    expect(downloadAvailabilityReason(zh, limit), zh.downloadLimitReached);
    expect(
      downloadAvailabilityReason(zh, disabled),
      zh.creatorDisabledDownload,
    );
  });

  test('unknown provider reason is retained instead of discarded', () {
    const asset = MediaAsset(
      id: 'restricted',
      kind: MediaKind.image,
      role: MediaRole.original,
      availability: MediaAvailability.restricted,
      availabilityReason: 'Region restriction.',
    );

    expect(
      downloadAvailabilityReason(en, asset),
      'DeviantArt says: Region restriction.',
    );
  });

  test('transient lookup failure is distinct from a definitive denial', () {
    const asset = MediaAsset(
      id: 'unknown',
      kind: MediaKind.unknown,
      role: MediaRole.original,
      availability: MediaAvailability.unavailable,
    );

    expect(
      downloadAvailabilityReason(en, asset, lookupFailed: true),
      en.downloadAvailabilityCheckFailed,
    );
    expect(downloadAvailabilityReason(en, asset), en.hintUnavailable);
  });

  test('fallback chooses the largest image but never a video poster', () {
    final small = MediaAsset(
      id: 'small',
      kind: MediaKind.image,
      role: MediaRole.preview,
      availability: MediaAvailability.available,
      uri: Uri.parse('https://example.test/small.jpg'),
      width: 400,
      height: 300,
    );
    final large = MediaAsset(
      id: 'large',
      kind: MediaKind.image,
      role: MediaRole.preview,
      availability: MediaAvailability.available,
      uri: Uri.parse('https://example.test/large.jpg'),
      width: 1600,
      height: 1200,
    );
    final video = MediaAsset(
      id: 'video',
      kind: MediaKind.video,
      role: MediaRole.preview,
      availability: MediaAvailability.available,
      uri: Uri.parse('https://example.test/video.mp4'),
    );

    expect(bestFallbackImage(<MediaAsset>[small, large]), same(large));
    expect(bestFallbackImage(<MediaAsset>[small, video]), isNull);
  });

  test('planDownload prefers the transferable original', () {
    final original = MediaAsset(
      id: 'original',
      kind: MediaKind.image,
      role: MediaRole.original,
      availability: MediaAvailability.available,
      uri: Uri.parse('https://example.test/original.png'),
    );

    final plan = planDownload(original: original, media: const <MediaAsset>[]);

    expect(plan.canDownload, isTrue);
    expect(plan.usingFallback, isFalse);
    expect(plan.downloadable, same(original));
  });

  test('planDownload only falls back for transferable displayed images', () {
    final large = MediaAsset(
      id: 'large',
      kind: MediaKind.image,
      role: MediaRole.preview,
      availability: MediaAvailability.available,
      uri: Uri.parse('https://example.test/large.jpg'),
      width: 1600,
      height: 1200,
    );
    final unavailable = MediaAsset(
      id: 'original',
      kind: MediaKind.image,
      role: MediaRole.original,
      availability: MediaAvailability.unavailable,
    );
    final video = MediaAsset(
      id: 'video',
      kind: MediaKind.video,
      role: MediaRole.preview,
      availability: MediaAvailability.available,
      uri: Uri.parse('https://example.test/video.mp4'),
    );

    final fallbackPlan = planDownload(
      original: unavailable,
      media: <MediaAsset>[large],
    );
    expect(fallbackPlan.usingFallback, isTrue);
    expect(fallbackPlan.downloadable, same(large));

    final noPlan = planDownload(
      original: unavailable,
      media: <MediaAsset>[video],
    );
    expect(noPlan.usingFallback, isFalse);
    expect(noPlan.canDownload, isFalse);
  });

  test(
    'background failure reasons classify permission and not-found errors',
    () {
      const forbidden = TransferSnapshot(
        id: 'forbidden',
        state: TransferState.failed,
        progress: 0,
        failureCode: 'httpResponse',
        failureMessage: 'HTTP 403 Forbidden',
      );
      const missing = TransferSnapshot(
        id: 'missing',
        state: TransferState.notFound,
        progress: 0,
      );

      expect(
        transferFailureReason(zh, forbidden),
        zh.downloadFailurePermission,
      );
      expect(transferFailureReason(zh, missing), zh.downloadFailureNotFound);
    },
  );

  test('existing transfer messages reflect their real state', () {
    expect(
      transferStatusMessage(
        zh,
        const TransferSnapshot(
          id: 'queued',
          state: TransferState.queued,
          progress: 0,
        ),
      ),
      zh.transferQueued,
    );
    expect(
      transferStatusMessage(
        zh,
        const TransferSnapshot(
          id: 'done',
          state: TransferState.completed,
          progress: 1,
          localPath: '/downloads/image.jpg',
        ),
      ),
      '${zh.savedToPrefix}/downloads/image.jpg',
    );
  });

  testWidgets('unavailable download shows a reason without a fake button', (
    tester,
  ) async {
    const original = MediaAsset(
      id: 'blocked',
      kind: MediaKind.image,
      role: MediaRole.original,
      availability: MediaAvailability.purchaseRequired,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadSection(
            s: zh,
            original: original,
            downloadable: original,
            transfer: null,
            downloading: false,
            lookupFailed: false,
            onDownload: () {},
            onRetry: () {},
            onRetryAvailability: () {},
            onPause: () {},
            onResume: () {},
            onCancel: () {},
          ),
        ),
      ),
    );

    expect(find.text(zh.hintPurchaseRequired), findsOneWidget);
    expect(find.text(zh.downloadUnavailableReason), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('fallback is presented as a clear compact download action', (
    tester,
  ) async {
    var downloaded = false;
    const original = MediaAsset(
      id: 'original',
      kind: MediaKind.image,
      role: MediaRole.original,
      availability: MediaAvailability.unavailable,
    );
    final fallback = MediaAsset(
      id: 'preview',
      kind: MediaKind.image,
      role: MediaRole.preview,
      availability: MediaAvailability.available,
      uri: Uri.parse('https://example.test/image.jpg'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadSection(
            s: zh,
            original: original,
            downloadable: fallback,
            transfer: null,
            downloading: false,
            lookupFailed: false,
            onDownload: () => downloaded = true,
            onRetry: () {},
            onRetryAvailability: () {},
            onPause: () {},
            onResume: () {},
            onCancel: () {},
          ),
        ),
      ),
    );

    expect(find.text(zh.fallbackDownloadNotice), findsOneWidget);
    expect(find.text(zh.downloadUnavailableReason), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, zh.downloadImage),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, zh.downloadImage));
    expect(downloaded, isTrue);
  });

  testWidgets('long-press download confirmation requires explicit approval', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await confirmImageDownload(context, strings: zh);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(zh.confirmImageDownloadTitle), findsOneWidget);
    expect(result, isNull);

    await tester.tap(find.text(zh.cancel));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    result = null;
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(zh.downloadImage));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
