import 'dart:io';

import 'package:daviewer/core/search/search_history_store.dart';
import 'package:daviewer/core/search/interest_store.dart';
import 'package:daviewer/features/search/search_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  late Directory directory;
  late PathProviderPlatform previousPaths;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('search-history-store');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    await directory.delete(recursive: true);
  });

  test('concurrent additions retain the newest 20 queries', () async {
    final writes = [
      for (var i = 0; i < 30; i++) SearchHistoryStore.add('query $i'),
    ];
    final read = SearchHistoryStore.load();
    await Future.wait(writes);
    expect(await read, [for (var i = 29; i >= 10; i--) 'query $i']);
  });

  test('add, remove, clear and read respect invocation order', () async {
    final operations = <Future<void>>[
      SearchHistoryStore.add('old'),
      SearchHistoryStore.clear(),
      SearchHistoryStore.add('keep'),
      SearchHistoryStore.add('remove'),
      SearchHistoryStore.remove('remove'),
    ];
    final read = SearchHistoryStore.load();
    await Future.wait(operations);
    expect(await read, ['keep']);
  });

  test('interest reads include all previously requested writes', () async {
    final writes = [
      for (var i = 0; i < 30; i++) InterestStore.recordTags([' Art ', 'art']),
    ];
    final read = InterestStore.load();
    await Future.wait(writes);
    expect(await read, {'art': 30});
  });

  test('pending history operations safely finish after disposal', () async {
    final controller = SearchHistoryController();
    final add = controller.add('query');
    final remove = controller.remove('query');
    final clear = controller.clear();
    controller.dispose();
    await Future.wait([add, remove, clear]);
    expect(await SearchHistoryStore.load(), isEmpty);
  });
}
