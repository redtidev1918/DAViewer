import 'package:daviewer/core/auth/web_session_status.dart';
import 'package:daviewer/shared/widgets/app_notice_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a dismissed session notice stays hidden', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('App Bar')),
            body: Stack(
              children: <Widget>[
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AppNoticeHost(),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppNoticeHost)),
    );
    container.read(webSessionStatusProvider.notifier).markLocked();
    await tester.pump();

    expect(
      find.textContaining('Max challenge attempts exceeded'),
      findsOneWidget,
    );

    final appBarRect = tester.getRect(find.byType(AppBar));
    final bannerTextRect = tester.getRect(
      find.textContaining('Max challenge attempts exceeded'),
    );
    expect(bannerTextRect.top, greaterThanOrEqualTo(appBarRect.bottom));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(
      find.textContaining('Max challenge attempts exceeded'),
      findsNothing,
    );
  });

  testWidgets('an unverified web session does not nag the user', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('App Bar')),
            body: Stack(
              children: <Widget>[
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AppNoticeHost(),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppNoticeHost)),
    );
    container.read(webSessionStatusProvider.notifier).state =
        const WebSessionStatus(state: WebSessionStatusState.unverified);
    await tester.pump();

    expect(find.textContaining('网页会话'), findsNothing);
  });

  testWidgets('a dismissed session notice may return after a healthy period', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Stack(
              children: <Widget>[
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AppNoticeHost(),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppNoticeHost)),
    );
    final status = container.read(webSessionStatusProvider.notifier);

    status.markLocked();
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(
      find.textContaining('Max challenge attempts exceeded'),
      findsNothing,
    );

    status.markHealthy(serverUsername: 'artist');
    await tester.pump();
    status.markLocked();
    await tester.pump();

    expect(
      find.textContaining('Max challenge attempts exceeded'),
      findsOneWidget,
    );
  });

  testWidgets('notice does not shift content or cover navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('App Bar')),
            body: Stack(
              children: <Widget>[
                const Center(child: Text('Content')),
                const Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AppNoticeHost(),
                ),
              ],
            ),
            bottomNavigationBar: const SizedBox(
              height: 56,
              child: ColoredBox(
                color: Colors.blueGrey,
                child: Center(child: Text('Nav')),
              ),
            ),
          ),
        ),
      ),
    );

    final content = find.text('Content');
    final contentRectBefore = tester.getRect(content);
    final navbarRect = tester.getRect(find.text('Nav'));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppNoticeHost)),
    );
    container.read(webSessionStatusProvider.notifier).markLocked();
    await tester.pump();

    final noticeText = find.textContaining('Max challenge attempts exceeded');
    expect(noticeText, findsOneWidget);
    final contentRectAfter = tester.getRect(content);
    expect(contentRectAfter, contentRectBefore);

    final noticeRect = tester.getRect(noticeText);
    expect(noticeRect.bottom, lessThanOrEqualTo(navbarRect.top));
  });
}
