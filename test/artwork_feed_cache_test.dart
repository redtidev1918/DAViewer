import 'dart:convert';
import 'dart:io';

import 'package:dakit_core/dakit_core.dart';
import 'package:daviewer/core/feed/artwork_feed_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync(
      'daviewer-feed-cache-test-',
    );
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  Artwork artwork(int index) => Artwork(
    id: 'art-$index',
    title: 'Art $index',
    author: const UserProfile(id: 'user-1', username: 'sample'),
    pageUri: Uri.parse('https://example.test/art-$index'),
    media: const <MediaAsset>[],
    isFavourited: index.isEven,
  );

  List<Artwork> page(int count) => <Artwork>[
    for (var i = 0; i < count; i++) artwork(i),
  ];

  List<File> cacheFiles() => directory
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .toList();

  test('round-trips a page for the same account', () async {
    final store = ArtworkFeedCacheStore(directory: directory);
    await store.write('sample', page(3));

    final snapshot = await store.read('sample');
    expect(snapshot, isNotNull);
    expect(snapshot!.username, 'sample');
    expect(snapshot.items, hasLength(3));
    expect(snapshot.items.first.id, 'art-0');
    expect(snapshot.items.first.isFavourited, isTrue);
    expect(snapshot.items[1].isFavourited, isFalse);
    expect(
      snapshot.savedAt.isAfter(
        DateTime.now().subtract(const Duration(minutes: 1)),
      ),
      isTrue,
    );
  });

  test('keeps accounts isolated', () async {
    final store = ArtworkFeedCacheStore(directory: directory);
    await store.write('sample', page(2));

    expect(await store.read('someone-else'), isNull);
    expect(await store.read(''), isNull);
  });

  test('a corrupt file reads as no cache', () async {
    final store = ArtworkFeedCacheStore(directory: directory);
    await store.write('sample', page(2));
    for (final file in cacheFiles()) {
      await file.writeAsString('{not json');
    }

    expect(await store.read('sample'), isNull);
  });

  test('a foreign format version reads as no cache', () async {
    final store = ArtworkFeedCacheStore(directory: directory);
    await store.write('sample', page(2));
    final file = cacheFiles().single;
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    data['version'] = ArtworkFeedCacheStore.formatVersion + 1;
    await file.writeAsString(jsonEncode(data));

    expect(await store.read('sample'), isNull);
  });

  test('a snapshot without parsable items reads as no cache', () async {
    final store = ArtworkFeedCacheStore(directory: directory);
    await store.write('sample', page(2));
    final file = cacheFiles().single;
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    data['items'] = <Object?>[
      <String, Object?>{'title': 'no id'},
    ];
    await file.writeAsString(jsonEncode(data));

    expect(await store.read('sample'), isNull);
  });

  test('an empty page is never written', () async {
    final store = ArtworkFeedCacheStore(directory: directory);
    await store.write('sample', const <Artwork>[]);

    expect(cacheFiles(), isEmpty);
  });

  test('what it writes is bounded', () async {
    final store = ArtworkFeedCacheStore(directory: directory);
    await store.write('sample', page(120));

    final snapshot = await store.read('sample');
    expect(snapshot!.items.length, lessThanOrEqualTo(60));
  });

  test('older accounts beyond maxEntries are pruned', () async {
    final store = ArtworkFeedCacheStore(directory: directory, maxEntries: 1);
    await store.write('older', page(1));
    final older = cacheFiles().single;
    await older.setLastModified(
      DateTime.now().subtract(const Duration(hours: 2)),
    );

    await store.write('newer', page(1));

    expect(cacheFiles(), hasLength(1));
    expect(await store.read('older'), isNull);
    expect(await store.read('newer'), isNotNull);
  });

  test('never persists credentials', () async {
    final store = ArtworkFeedCacheStore(directory: directory);
    await store.write('sample', page(2));

    final raw = await cacheFiles().single.readAsString();
    for (final forbidden in <String>[
      'cookie',
      'csrf',
      'token',
      'authorization',
      'bearer',
      'password',
    ]) {
      expect(raw.toLowerCase(), isNot(contains(forbidden)));
    }
  });
}
