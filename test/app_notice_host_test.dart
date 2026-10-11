import 'package:daviewer/core/auth/web_session_status.dart';
import 'package:daviewer/shared/widgets/app_notice_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dismissal survives route replacement but resets offscreen', (
    tester,
  ) async {
    final container = ProviderContainer(retry: (_, _) => null);
    addTearDown(container.dispose);

    Future<void> showHost({
      required bool visible,
      required String route,
    }) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              key: ValueKey(route),
              body: visible ? const AppNoticeHost() : const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    final status = container.read(webSessionStatusProvider.notifier);
    status.markLocked();
    await showHost(visible: true, route: 'detail');
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    await showHost(visible: true, route: 'artist');
    expect(find.byIcon(Icons.close), findsNothing);

    await showHost(visible: false, route: 'login');
    status.markHealthy(serverUsername: 'artist');
    // No notice host can observe this recovery. A later incident still needs
    // a new prompt, including when both transitions happen between frames.
    status.markLocked();
    await showHost(visible: true, route: 'detail-again');
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('a dismissed session notice stays hidden', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
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
        retry: (_, _) => null,
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
        retry: (_, _) => null,
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
        retry: (_, _) => null,
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

  testWidgets('NoticeOverlay keeps the host visible on a pushed route', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (context) => const NoticeOverlay(
                        child: Scaffold(
                          body: Center(child: Text('Pushed page')),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Pushed page'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppNoticeHost)),
    );
    container.read(webSessionStatusProvider.notifier).markLocked();
    await tester.pump();

    // The session banner appears on the pushed page, not only on the shell.
    expect(
      find.textContaining('Max challenge attempts exceeded'),
      findsOneWidget,
    );
  });
}
