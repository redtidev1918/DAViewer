import 'dart:convert';
import 'dart:io';

import 'package:daviewer/core/data/web_session.dart';
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

  List<PersistedWebCookie> cookies(Map<String, String> values) =>
      <PersistedWebCookie>[
        for (final entry in values.entries)
          PersistedWebCookie(name: entry.key, value: entry.value),
      ];

  test('cookie updates preserve metadata', () async {
    await store.update(
      csrf: 'old',
      isLoggedIn: true,
      username: 'Artist',
      cookies: cookies(<String, String>{'userinfo': 'a'}),
    );
    await store.update(
      cookies: cookies(<String, String>{'userinfo': 'b', 'csrf': 'token'}),
    );

    final saved = await read();
    expect(saved['csrf'], 'old');
    expect(saved['username'], 'Artist');
    final persisted = parsePersistedCookies(saved['cookies']);
    expect(persisted, hasLength(2));
    expect(
      persisted.firstWhere((cookie) => cookie.name == 'userinfo').value,
      'b',
    );
  });

  test('metadata updates never modify cookies', () async {
    await store.update(
      csrf: 'old',
      isLoggedIn: true,
      username: 'Artist',
      cookies: cookies(<String, String>{'userinfo': 'a'}),
    );
    await store.update(csrf: 'fresh', username: 'Artist');

    final saved = await read();
    expect(saved['csrf'], 'fresh');
    expect(parsePersistedCookies(saved['cookies']).first.value, 'a');
  });

  test('a null or empty Cookie update never clears saved cookies', () async {
    await store.update(
      csrf: 'csrf',
      isLoggedIn: true,
      username: 'Artist',
      cookies: cookies(<String, String>{'userinfo': 'a'}),
    );
    await store.update(
      csrf: 'new',
      isLoggedIn: true,
      username: 'Artist',
      cookies: const <PersistedWebCookie>[],
    );

    expect(parsePersistedCookies((await read())['cookies']).first.value, 'a');
  });

  test(
    'serialized mutations do not let stale metadata overwrite new cookies',
    () async {
      await store.update(
        csrf: 'old',
        isLoggedIn: true,
        username: 'Artist',
        cookies: cookies(<String, String>{'userinfo': 'old'}),
      );

      final cookieWrite = store.update(
        cookies: cookies(<String, String>{
          'userinfo': 'new',
          'session': 'fresh',
        }),
      );
      final staleMetadataWrite = store.update(csrf: 'stale-refresh');
      await Future.wait(<Future<void>>[cookieWrite, staleMetadataWrite]);

      final saved = await read();
      expect(saved['csrf'], 'stale-refresh');
      final persisted = parsePersistedCookies(saved['cookies']);
      expect(persisted, hasLength(2));
      expect(
        persisted.firstWhere((cookie) => cookie.name == 'userinfo').value,
        'new',
      );
    },
  );

  test('persists cookie metadata (domain/path/expiry/security)', () async {
    await store.update(
      cookies: <PersistedWebCookie>[
        PersistedWebCookie(
          name: 'auth',
          value: 'secret',
          domain: '.deviantart.com',
          path: '/',
          expiresDate: DateTime.utc(2030, 1, 1),
          isSecure: true,
          isHttpOnly: true,
        ),
      ],
    );

    final restored = parsePersistedCookies((await read())['cookies']);
    expect(restored, hasLength(1));
    expect(restored.single.domain, '.deviantart.com');
    expect(restored.single.expiresDate, DateTime.utc(2030, 1, 1));
    expect(restored.single.isSecure, isTrue);
    expect(restored.single.isHttpOnly, isTrue);
  });

  test('migrates a legacy name-value map snapshot on read', () async {
    await File('${directory.path}/web_session.json').writeAsString(
      jsonEncode(<String, Object?>{
        'csrf': 'tok',
        'isLoggedIn': true,
        'username': 'Artist',
        'cookies': <String, String>{'userinfo': 'a', 'csrf': 't'},
      }),
    );

    final saved = await store.read();
    final migrated = saved['cookies'] as List<Object?>;
    expect(migrated, hasLength(2));
  });

  test('clear removes only the persisted snapshot', () async {
    await store.update(
      csrf: 'csrf',
      isLoggedIn: true,
      username: 'Artist',
      cookies: cookies(<String, String>{'userinfo': 'a'}),
    );
    await store.clear(reason: 'explicit_logout');

    expect(File('${directory.path}/web_session.json').existsSync(), isFalse);
  });
}
