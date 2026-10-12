import 'dart:async';
import 'dart:io';

import 'package:dakit_flutter/dakit_flutter.dart' hide WebSession;
import 'package:daviewer/core/auth/web_session_controller.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final transfers = BackgroundTransferManager(diagnostics: AppLogger.instance);
  late Directory directory;
  late _Storage storage;
  late _Cookies cookies;
  late ProviderContainer container;
  late WebSessionController controller;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('daviewer-cookie-race-');
    storage = _Storage();
    cookies = _Cookies();
    final store = WebSessionStore(
      directoryFactory: () async => directory,
      storage: storage,
    );
    container = ProviderContainer(
      overrides: [
        runtimeProvider.overrideWithValue(
          AppRuntime(
            clientId: 'test',
            oauth: null,
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
    await directory.delete(recursive: true);
  });

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
}
