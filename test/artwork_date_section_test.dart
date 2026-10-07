import 'package:daviewer/core/l10n/app_strings.dart';
import 'package:daviewer/features/artwork/artwork_detail_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => ProviderScope(
    retry: (_, _) => null,
    child: MaterialApp(home: Scaffold(body: child)),
  );

  testWidgets('shows publish and update rows for an edited artwork', (
    tester,
  ) async {
    final strings = AppStrings.zh;
    await tester.pumpWidget(
      host(
        ArtworkDateSection(
          publishedAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.now().toUtc(),
          s: strings,
        ),
      ),
    );

    expect(find.textContaining(strings.publishedLabel), findsOneWidget);
    expect(find.textContaining(strings.updatedLabel), findsOneWidget);
  });

  testWidgets('shows only the publish row when never edited', (tester) async {
    final strings = AppStrings.zh;
    await tester.pumpWidget(
      host(
        ArtworkDateSection(
          publishedAt: DateTime.utc(2026, 1, 1),
          updatedAt: null,
          s: strings,
        ),
      ),
    );

    expect(find.textContaining(strings.publishedLabel), findsOneWidget);
    expect(find.textContaining(strings.updatedLabel), findsNothing);
  });

  testWidgets('ignores an update time that is not later than publish time', (
    tester,
  ) async {
    final strings = AppStrings.zh;
    final published = DateTime.utc(2026, 6, 1);
    await tester.pumpWidget(
      host(
        ArtworkDateSection(
          publishedAt: published,
          // Same instant: no real edit happened, so don't show a misleading
          // "updated" row.
          updatedAt: published,
          s: strings,
        ),
      ),
    );

    expect(find.textContaining(strings.publishedLabel), findsOneWidget);
    expect(find.textContaining(strings.updatedLabel), findsNothing);
  });

  testWidgets('renders nothing when no dates are known', (tester) async {
    await tester.pumpWidget(
      host(
        ArtworkDateSection(
          publishedAt: null,
          updatedAt: null,
          s: AppStrings.zh,
        ),
      ),
    );

    expect(find.byType(Row), findsNothing);
  });
}
