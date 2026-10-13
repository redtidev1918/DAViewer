import 'package:daviewer/shared/widgets/app_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('coalesces visible feedback and replaces queued stale results', (
    tester,
  ) async {
    late BuildContext page;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              page = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    showFeedback(page, 'first', source: 'copy');
    await tester.pumpAndSettle();
    showFeedback(page, 'first', source: 'copy');
    showFeedback(page, 'second', source: 'download');
    showFeedback(page, 'latest', source: 'download');
    await tester.pumpAndSettle();
    expect(find.text('latest'), findsOneWidget);
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsNothing);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    showFeedback(page, 'latest', source: 'download');
    await tester.pumpAndSettle();
    expect(find.text('latest'), findsOneWidget);
  });

  testWidgets('late completion from an inactive route is suppressed', (
    tester,
  ) async {
    late BuildContext page;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              page = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    Navigator.of(page).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('new page')),
      ),
    );
    await tester.pumpAndSettle();
    showFeedback(
      page,
      'stale error',
      source: 'download',
      severity: AppNoticeSeverity.error,
    );
    await tester.pumpAndSettle();
    expect(find.text('stale error'), findsNothing);
  });

  testWidgets('hidden kept-alive tab cannot show feedback', (tester) async {
    late BuildContext hidden;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TickerMode(
            enabled: false,
            child: Builder(
              builder: (context) {
                hidden = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    showFeedback(hidden, 'hidden result', source: 'refresh');
    await tester.pumpAndSettle();
    expect(find.text('hidden result'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('error feedback retains readable action in $brightness', (
      tester,
    ) async {
      late BuildContext page;
      var actions = 0;
      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: brightness,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                page = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      showFeedback(
        page,
        'failed',
        source: 'download',
        severity: AppNoticeSeverity.error,
        action: SnackBarAction(label: 'Retry', onPressed: () => actions++),
      );
      await tester.pumpAndSettle();
      final snack = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snack.backgroundColor, theme.colorScheme.errorContainer);
      expect(snack.action!.textColor, theme.colorScheme.onErrorContainer);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(actions, 1);
    });
  }
}
