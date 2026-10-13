import 'package:daviewer/app/theme/app_theme.dart';
import 'package:daviewer/core/notice/app_notices.dart';
import 'package:daviewer/shared/widgets/app_notice_card.dart';
import 'package:daviewer/features/home/update_banner.dart';
import 'package:daviewer/core/updates/update_checker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('update reminder opens notes and remains dismissible', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [runningAppVersionProvider.overrideWithValue('development')],
    );
    addTearDown(container.dispose);
    container.read(updateCheckControllerProvider.notifier).state =
        const UpdateCheckState(latestVersion: '0.5.18', notes: '改进提醒体验。');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: UpdateBanner())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看更新'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('改进提醒体验。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(container.read(updateCheckControllerProvider).hasUpdate, isFalse);
    expect(find.textContaining('发现新版本'), findsNothing);
  });
  for (final dark in [false, true]) {
    testWidgets(
      'narrow ${dark ? 'dark' : 'light'} notice keeps actions usable at large text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var actions = 0;
        var dismissals = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: AppNoticeCard(
                  message: List.filled(
                    15,
                    'This service is temporarily unavailable.',
                  ).join(' '),
                  severity: AppNoticeSeverity.warning,
                  actionLabel: 'Try again',
                  onAction: () => actions++,
                  dismissLabel: 'Close reminder',
                  onDismiss: () => dismissals++,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final close = find.byTooltip('Close reminder');
        expect(tester.getSize(close).width, greaterThanOrEqualTo(48));
        await tester.tap(find.text('Try again'));
        await tester.tap(close);
        expect(actions, 1);
        expect(dismissals, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('desktop notice stays within a readable width', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: AppNoticeCard(
              message: 'Saved',
              dismissLabel: 'Close',
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(AppNoticeCard)).width,
      lessThanOrEqualTo(640),
    );
  });
}
