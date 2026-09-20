import 'dart:convert';
import 'dart:io';

import 'package:dakit_core/dakit_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daviewer/core/history/visit_history_store.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('daviewer-history');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Artwork artwork(String id) => Artwork(
    id: id,
    title: 'Artwork $id',
    author: const UserProfile(id: 'user', username: 'artist'),
    pageUri: Uri.parse('https://www.deviantart.com/artist/art/$id'),
    media: <MediaAsset>[
      MediaAsset(
        id: '$id:preview',
        kind: MediaKind.image,
        role: MediaRole.preview,
        availability: MediaAvailability.available,
        uri: Uri.parse('https://example.com/$id.jpg'),
      ),
    ],
  );

  test(
    'records newest first, deduplicates ids, and persists locally',
    () async {
      await VisitHistoryStore.record(artwork('1'), directory: directory);
      await VisitHistoryStore.record(artwork('2'), directory: directory);
      await VisitHistoryStore.record(artwork('1'), directory: directory);

      final visits = await VisitHistoryStore.load(directory: directory);
      expect(visits.map((visit) => visit.id), <String>['1', '2']);
      expect(visits.first.username, 'artist');
      expect(visits.first.thumbnail, Uri.parse('https://example.com/1.jpg'));
      expect((await VisitHistoryStore.load(directory: directory)).length, 2);
    },
  );

  test('clear removes the local history file', () async {
    await VisitHistoryStore.record(artwork('1'), directory: directory);
    await VisitHistoryStore.clear(directory: directory);
    expect(await VisitHistoryStore.load(directory: directory), isEmpty);
    expect(File('${directory.path}/visit_history.json').existsSync(), isFalse);
  });

  test('invalid JSON degrades to empty history', () async {
    File('${directory.path}/visit_history.json')
      ..createSync()
      ..writeAsStringSync(jsonEncode(<Object>['bad']));
    expect(await VisitHistoryStore.load(directory: directory), isEmpty);
  });
}
