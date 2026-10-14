import 'dart:async';
import 'dart:io';

import 'package:dakit_flutter/dakit_flutter.dart' hide WebSession;
import 'package:daviewer/core/auth/web_session_controller.dart';
import 'package:daviewer/core/auth/auth_controller.dart';
import 'package:daviewer/core/auth/auth_state.dart';
import 'package:daviewer/core/auth/web_session_store.dart';
import 'package:daviewer/core/data/web_session.dart';
import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart'
    hide AndroidOptions;
import 'package:daviewer/core/auth/session_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:daviewer/core/settings/app_preferences.dart';

class _Storage extends FlutterSecureStorage {
  final values = <String, String>{};
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) values[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.remove(key);
}

class _Cookies extends Fake implements CookieManager {
  final values = <String, String>{'userinfo': '{"username":"artist"}'};
  final events = <String>[];
  final written = <PersistedWebCookie>[];
  final writeStarted = Completer<void>();
  Future<void>? writeGate;
  Future<void>? readGate;
  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    InAppWebViewController? webViewController,
    InAppWebViewController? iosBelow11WebViewController,
  }) async {
    await readGate;
    return [
      for (final e in values.entries) Cookie(name: e.key, value: e.value),
    ];
  }

  @override
  Future<bool> setCookie({
    required WebUri url,
    required String name,
    required String value,
    String path = '/',
    String? domain,
    int? expiresDate,
    int? maxAge,
    bool? isSecure,
    bool? isHttpOnly,
    HTTPCookieSameSitePolicy? sameSite,
    InAppWebViewController? iosBelow11WebViewController,
    InAppWebViewController? webViewController,
  }) async {
    if (!writeStarted.isCompleted) writeStarted.complete();
    await writeGate;
    events.add('set:$name');
    written.add(
      PersistedWebCookie(
        name: name,
        value: value,
        domain: domain,
        path: path,
        expiresDate: expiresDate == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(expiresDate, isUtc: true),
        isSecure: isSecure == true,
        isHttpOnly: isHttpOnly == true,
      ),
    );
    values[name] = value;
    return true;
  }

  @override
  Future<bool> deleteAllCookies() async {
    events.add('clear');
    values.clear();
    return true;
  }
}

class _Pending extends Fake implements PendingAuthorizationStore {
  Future<void>? clearGate;
  final clearing = Completer<void>();
  @override
  Future<void> clear() async {
    if (!clearing.isCompleted) clearing.complete();
    await clearGate;
  }
}

class _Tokens extends Fake implements TokenStore {
  int clears = 0;
  AuthTokens? value;
  bool failNextClear = false;
  final clearing = Completer<void>();
  @override
  Future<AuthTokens?> read() async => value;
  @override
  Future<void> write(AuthTokens tokens) async => value = tokens;
  @override
  Future<void> clear() async {
    clears++;
    if (!clearing.isCompleted) clearing.complete();
    if (failNextClear) {
      failNextClear = false;
      throw StateError('synthetic native cleanup failure');
    }
    value = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transfers = BackgroundTransferManager(diagnostics: AppLogger.instance);
  late Directory directory;
  late _Storage storage;
  late _Cookies cookies;
  late ProviderContainer container;
  late WebSessionController controller;
  late _Pending pending;
  late _Tokens tokens;
  late WebSessionStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('daviewer-cookie-race-');
    storage = _Storage();
    cookies = _Cookies();
    pending = _Pending();
    tokens = _Tokens();
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    store = WebSessionStore(
      directoryFactory: () async => directory,
      storage: storage,
    );
    container = ProviderContainer(
      overrides: [
        runtimeProvider.overrideWithValue(
          AppRuntime(
            clientId: 'test',
            oauth: DAKitOAuthClient(
              config: OAuthConfig(
                clientId: 'test',
                redirectUri: Uri.parse('dakit://oauth/callback'),
              ),
              tokenStore: tokens,
              pendingStore: pending,
              recoveryLookupTimeout: const Duration(milliseconds: 50),
            ),
            transport: null,
            transfers: transfers,
          ),
        ),
        webSessionProvider.overrideWithValue(WebSession(() => cookies)),
        webSessionControllerProvider.overrideWith(
          (ref) => WebSessionController(
            ref,
            store: store,
            cookieManager: () => cookies,
          ),
        ),
      ],
    );
    controller = container.read(webSessionControllerProvider.notifier);
    controller.state = const WebSessionState(
      isLoggedIn: true,
      username: 'artist',
      csrf: 'current',
    );
  });
  tearDown(() async {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
  });

  Future<void> saveRestorableSnapshot({bool expired = false}) async {
    container.read(authControllerProvider.notifier).state = const AuthState(
      status: AuthStatus.signedIn,
      account: UserProfile(id: 'artist', username: 'artist'),
    );
    // App-owned storage contract, written through the production store; no
    // fixture reverse-engineered from parsePersistedCookies or network API.
    for (final name in ['_px', '_pxvid', 'g_state', 'pxcts', 'td', 'tpc']) {
      cookies.values[name] = 'synthetic';
    }
    await store.update(
      csrf: 'saved-csrf',
      isLoggedIn: true,
      username: 'artist',
      cookies: [
        for (final entry in cookies.values.entries)
          PersistedWebCookie(name: entry.key, value: entry.value),
        for (final name in ['auth', 'auth_secure'])
          PersistedWebCookie(
            name: name,
            value: 'synthetic-$name',
            domain: '.deviantart.com',
            path: '/',
            isSecure: true,
            isHttpOnly: true,
            expiresDate: expired ? DateTime.utc(2020) : DateTime.utc(2030),
          ),
      ],
    );
  }

  test('cold-start restores decoded saved authentication cookies with metadata', () async {
    await saveRestorableSnapshot();
    expect(cookies.values, hasLength(7));
    expect(await controller.persistedCookies(), hasLength(9));
    await controller.initialize();
    expect(cookies.events, ['set:auth', 'set:auth_secure']);
    expect(cookies.values, hasLength(9));
    for (final cookie in cookies.written) {
      expect(cookie.domain, '.deviantart.com');
      expect(cookie.path, '/');
      expect(cookie.expiresDate, DateTime.utc(2030));
      expect(cookie.isSecure, isTrue);
      expect(cookie.isHttpOnly, isTrue);
    }
    expect(controller.state.username, 'artist');
    // Repeated cold starts retain the live cookies instead of overwriting them.
    cookies.values['auth'] = 'rotated-live';
    for (var i = 0; i < 10; i++) {
      await controller.initialize();
    }
    expect(cookies.events, hasLength(2));
    expect(cookies.values['auth'], 'rotated-live');
  });

  test('restoration rejects expired saved auth cookies', () async {
    await saveRestorableSnapshot(expired: true);
    await controller.initialize();
    expect(cookies.events, isEmpty);
    expect(cookies.values, hasLength(7));
  });

  test('restoration rejects a snapshot for another OAuth account', () async {
    await saveRestorableSnapshot();
    container.read(authControllerProvider.notifier).state = const AuthState(
      status: AuthStatus.signedIn,
      account: UserProfile(id: 'other', username: 'other'),
    );
    await controller.restorePersistedCookies();
    expect(cookies.events, isEmpty);
  });

  test('restore injects but leaves identity untouched when the read-back names no account', () async {
    // Incident follow-up (2026-10-15 02:59): injection ran (9 live cookies)
    // but no restore-verified line appeared. An unparseable read-back
    // userinfo is one such outcome; the injected cookies must stay and the
    // in-memory identity must not be overwritten.
    await saveRestorableSnapshot();
    cookies.values['userinfo'] = 'not-json';
    await controller.initialize();
    expect(cookies.events, ['set:auth', 'set:auth_secure']);
    expect(cookies.values, hasLength(9));
    expect(controller.state.username, 'artist');
    expect(controller.state.isLoggedIn, true);
    // The persisted snapshot was not rewritten by the unverified read-back.
    expect(await controller.persistedCookies(), hasLength(9));
  });

  test('cold start without any persisted snapshot injects nothing', () async {
    await controller.initialize();
    expect(cookies.events, isEmpty);
    expect(cookies.values, hasLength(1));
  });

  test('a cookie snapshot without a saved username never injects', () async {
    container.read(authControllerProvider.notifier).state = const AuthState(
      status: AuthStatus.signedIn,
      account: UserProfile(id: 'artist', username: 'artist'),
    );
    await store.update(
      isLoggedIn: true,
      cookies: [
        PersistedWebCookie(
          name: 'auth',
          value: 'synthetic-auth',
          domain: '.deviantart.com',
          expiresDate: DateTime.utc(2030),
        ),
      ],
    );
    await controller.restorePersistedCookies();
    expect(cookies.events, isEmpty);
  });

  test(
    'concurrent restores share native writes and logout fences the remainder',
    () async {
      await saveRestorableSnapshot();
      final gate = Completer<void>();
      cookies.writeGate = gate.future;
      final first = controller.restorePersistedCookies();
      final second = controller.restorePersistedCookies();
      expect(identical(first, second), isTrue);
      await cookies.writeStarted.future.timeout(const Duration(seconds: 2));
      final logout = controller.clear();
      gate.complete();
      await Future.wait([first, second, logout]);
      expect(cookies.events, ['set:auth', 'clear']);
      expect(cookies.values, isEmpty);
      expect(storage.values, isEmpty);
      expect(controller.state.isLoggedIn, isFalse);
    },
  );

  test('logout clears after an already-issued native write and stops the remaining import', () async {
    final gate = Completer<void>();
    cookies.writeGate = gate.future;
    final importing = controller.importCookies({
      'userinfo': '{"username":"artist"}',
      'auth': 'test-session',
    });
    await cookies.writeStarted.future;
    final clearing = controller.clear();
    expect(controller.state.isLoggedIn, isFalse);
    expect(cookies.events, isEmpty);
    gate.complete();
    expect((await importing).outcome, CookieImportOutcome.accountConflict);
    await clearing;
    expect(cookies.events, ['set:userinfo', 'clear']);
    expect(cookies.values, isEmpty);
    expect(storage.values, isEmpty);
  });

  test('snapshot read finishing after logout cannot recreate persisted credentials', () async {
    final gate = Completer<void>();
    cookies.readGate = gate.future;
    final saving = controller.ensurePersistentSnapshot();
    await Future<void>.delayed(Duration.zero);
    await controller.clear();
    gate.complete();
    expect(await saving, isFalse);
    expect(storage.values, isEmpty);
    expect(controller.state.isLoggedIn, isFalse);
  });

  test('old browser CSRF cannot update the new identity epoch', () async {
    final oldEpoch = controller.identityEpoch;
    await controller.clear();
    await controller.updateCsrf('obsolete', expectedEpoch: oldEpoch);
    expect(controller.state.csrf, isEmpty);
    expect(storage.values, isEmpty);
  });

  test('logout fences Web immediately and persists intent despite hanging PKCE cleanup', () async {
    final gate = Completer<void>();
    pending.clearGate = gate.future;
    final auth = container.read(authControllerProvider.notifier);
    auth.state = const AuthState(status: AuthStatus.signedIn);
    final loggingOut = auth.logout();
    await pending.clearing.future;
    expect(auth.state.status, AuthStatus.signedOut);
    expect(controller.state.isLoggedIn, isFalse);
    await loggingOut.timeout(const Duration(seconds: 4));
    expect(
      await AppPreferences.loadOAuthSessionEvidence(),
      OAuthSessionEvidence.signedOut,
    );
    expect(tokens.clears, 1);
    gate.complete();
  });

  test(
    'late logout failure does not clear a newer SDK authorization',
    () async {
      final gate = Completer<void>();
      pending.clearGate = gate.future;
      tokens.failNextClear = true;
      final auth = container.read(authControllerProvider.notifier);
      final session = container.read(runtimeProvider).oauth!.session;
      auth.state = const AuthState(status: AuthStatus.signedIn);
      final generation = session.generation;
      final loggingOut = auth.logout();
      expect(session.generation, generation + 1);
      await tokens.clearing.future;
      await Future<void>.delayed(Duration.zero);
      await session.save(
        AuthTokens(
          accessToken: 'synthetic-new-account-token',
          tokenType: 'Bearer',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );
      await loggingOut.timeout(const Duration(seconds: 4));
      expect(tokens.clears, 1);
      expect(tokens.value?.accessToken, 'synthetic-new-account-token');
      gate.complete();
    },
  );

  test(
    'cancelLogin settles despite an unavailable pending-store deletion',
    () async {
      final gate = Completer<void>();
      pending.clearGate = gate.future;
      final auth = container.read(authControllerProvider.notifier);
      auth.state = const AuthState(
        status: AuthStatus.signedOut,
        isLoggingIn: true,
      );
      await auth.cancelLogin().timeout(const Duration(seconds: 4));
      expect(auth.state.isLoggingIn, isFalse);
      gate.complete();
    },
  );

  test('post-logout cookies without a fresh OAuth identity cannot revive Web state', () async {
    await controller.clear();
    await controller.report(
      csrf: 'new',
      username: 'artist',
      capturedCookies: [
        PersistedWebCookie(name: 'userinfo', value: '{"username":"artist"}'),
      ],
    );
    expect(controller.state.isLoggedIn, isFalse);
    expect(storage.values, isEmpty);
  });
}
