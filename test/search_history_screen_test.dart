import 'dart:convert';
import 'dart:io';

import 'package:daviewer/features/search/search_screen.dart';
import 'package:daviewer/features/search/search_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  testWidgets(
    'deleting a history chip preserves other queries and idle search',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('search-history-test'),
      ))!;
      final previousPaths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPaths(directory.path);
      addTearDown(() async {
        PathProviderPlatform.instance = previousPaths;
        await directory.delete(recursive: true);
      });
      final file = File('${directory.path}/search_history.json');
      await tester.runAsync(
        () => file.writeAsString(jsonEncode(['remove me', 'keep me'])),
      );
      final container = ProviderContainer(
        overrides: [
          recommendedTagsProvider.overrideWith((ref) async => []),
          tagPreviewProvider.overrideWith((ref, tag) async => null),
        ],
      );
      addTearDown(container.dispose);
      await tester.runAsync(() async {
        container.read(searchHistoryProvider);
        for (
          var i = 0;
          i < 50 && container.read(searchHistoryProvider).isEmpty;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SearchScreen()),
        ),
      );
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      final chip = find.widgetWithText(InputChip, 'remove me');
      expect(chip, findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(
          find.descendant(
            of: chip,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Tooltip &&
                  ['删除', 'Delete'].contains(widget.message),
            ),
          ),
        );
        for (
          var i = 0;
          i < 50 && container.read(searchHistoryProvider).length != 1;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(find.widgetWithText(InputChip, 'remove me'), findsNothing);
      expect(find.widgetWithText(InputChip, 'keep me'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(jsonDecode((await tester.runAsync(() => file.readAsString()))!), [
        'keep me',
      ]);
    },
  );
}
