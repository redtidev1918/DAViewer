import 'dart:convert';
import 'dart:io';

import 'package:daviewer/core/auth/web_session_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late WebSessionStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('web_session_store');
    store = WebSessionStore(directoryFactory: () async => directory);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<Map<String, Object?>> read() async => jsonDecode(
    await File('${directory.path}/web_session.json').readAsString(),
  ) as Map<String, Object?>;

  test('cookie updates preserve metadata', () async {
    await store.update(
      csrf: 'old',
      isLoggedIn: true,
      username: 'Artist',
      cookies: const <String, String>{'userinfo': 'a'},
    );
    await store.update(
      cookies: const <String, String>{'userinfo': 'b', 'csrf': 'token'},
    );

    final saved = await read();
    expect(saved['csrf'], 'old');
    expect(saved['username'], 'Artist');
    expect(saved['cookies'], <String, String>{
      'userinfo': 'b',
      'csrf': 'token',
    });
  });

  test('metadata updates never modify cookies', () async {
    await store.update(
      csrf: 'old',
      isLoggedIn: true,
      username: 'Artist',
      cookies: const <String, String>{'userinfo': 'a'},
    );
    await store.update(csrf: 'fresh', username: 'Artist');

    final saved = await read();
    expect(saved['csrf'], 'fresh');
    expect(saved['cookies'], <String, String>{'userinfo': 'a'});
  });

  test('a null or empty Cookie update never clears saved cookies', () async {
    await store.update(
      csrf: 'csrf',
      isLoggedIn: true,
      username: 'Artist',
      cookies: const <String, String>{'userinfo': 'a'},
    );
    await store.update(
      csrf: 'new',
      isLoggedIn: true,
      username: 'Artist',
      cookies: const <String, String>{},
    );

    expect((await read())['cookies'], <String, String>{'userinfo': 'a'});
  });

  test(
    'serialized mutations do not let stale metadata overwrite new cookies',
    () async {
      await store.update(
        csrf: 'old',
        isLoggedIn: true,
        username: 'Artist',
        cookies: const <String, String>{'userinfo': 'old'},
      );

      final cookieWrite = store.update(
        cookies: const <String, String>{'userinfo': 'new', 'session': 'fresh'},
      );
      final staleMetadataWrite = store.update(csrf: 'stale-refresh');
      await Future.wait(<Future<void>>[cookieWrite, staleMetadataWrite]);

      final saved = await read();
      expect(saved['csrf'], 'stale-refresh');
      expect(saved['cookies'], <String, String>{
        'userinfo': 'new',
        'session': 'fresh',
      });
    },
  );

  test('clear removes only the persisted snapshot', () async {
    await store.update(
      csrf: 'csrf',
      isLoggedIn: true,
      username: 'Artist',
      cookies: const <String, String>{'userinfo': 'a'},
    );
    await store.clear(reason: 'explicit_logout');

    expect(File('${directory.path}/web_session.json').existsSync(), isFalse);
  });
}
