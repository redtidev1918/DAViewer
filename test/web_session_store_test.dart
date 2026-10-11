import 'dart:convert';
import 'dart:io';

import 'package:daviewer/core/data/web_session.dart';
import 'package:daviewer/core/auth/web_session_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  late Directory directory;
  late WebSessionStore store;
  late _MemoryStorage storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('web_session_store');
    storage = _MemoryStorage();
    store = WebSessionStore(
      directoryFactory: () async => directory,
      storage: storage,
    );
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<Map<String, Object?>> read() async =>
      jsonDecode((await storage.read(key: WebSessionStore.storageKey))!)
          as Map<String, Object?>;

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
    expect(File('${directory.path}/web_session.json').existsSync(), isFalse);
    expect(await read(), containsPair('username', 'Artist'));
  });

  test('failed migration preserves the old file and retries safely', () async {
    final file = File('${directory.path}/web_session.json');
    final legacy = jsonEncode({'csrf': 'secret', 'username': 'Artist'});
    await file.writeAsString(legacy);
    storage.failWrites = true;
    expect(await store.read(), isEmpty);
    expect(await file.readAsString(), legacy);
    await expectLater(store.update(csrf: 'new'), throwsStateError);
    expect(await file.readAsString(), legacy);
    storage.failWrites = false;
    expect(await store.read(), containsPair('csrf', 'secret'));
    expect(await file.exists(), isFalse);
  });

  test('migration removes an abandoned plaintext temporary snapshot', () async {
    final file = File('${directory.path}/web_session.json');
    final temporary = File('${file.path}.tmp');
    await file.writeAsString('{"csrf":"saved"}');
    await temporary.writeAsString('{"csrf":"abandoned secret"}');
    expect(await store.read(), containsPair('csrf', 'saved'));
    expect(await file.exists(), isFalse);
    expect(await temporary.exists(), isFalse);
  });

  test(
    'new snapshots never create a plaintext file and survive restart',
    () async {
      await store.update(
        csrf: 'secret',
        cookies: cookies({'userinfo': 'private'}),
      );
      expect(File('${directory.path}/web_session.json').existsSync(), isFalse);
      final restarted = WebSessionStore(
        directoryFactory: () async => directory,
        storage: storage,
      );
      expect(await restarted.read(), containsPair('csrf', 'secret'));
    },
  );

  test(
    'corrupt secure storage does not overwrite a recoverable legacy file',
    () async {
      storage.value = '{broken';
      final file = File('${directory.path}/web_session.json');
      await file.writeAsString('{"csrf":"recoverable"}');
      expect(await store.read(), isEmpty);
      await expectLater(store.update(csrf: 'new'), throwsFormatException);
      expect(storage.value, '{broken');
      expect(await file.exists(), isTrue);
    },
  );

  test('clear removes only the persisted snapshot', () async {
    await store.update(
      csrf: 'csrf',
      isLoggedIn: true,
      username: 'Artist',
      cookies: cookies(<String, String>{'userinfo': 'a'}),
    );
    await store.clear(reason: 'explicit_logout');

    expect(File('${directory.path}/web_session.json').existsSync(), isFalse);
    expect(storage.value, isNull);
  });
}

class _MemoryStorage extends FlutterSecureStorage {
  String? value;
  bool failWrites = false;
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
  }) async => value;
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
  }) async {
    if (failWrites) throw StateError('locked secure storage');
    this.value = value;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
  }) async => value = null;
}
