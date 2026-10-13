import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:daviewer/core/auth/auth_controller.dart';
import 'package:daviewer/core/auth/auth_state.dart';
import 'package:daviewer/core/auth/session_state.dart';
import 'package:daviewer/core/auth/web_session_controller.dart';
import 'package:daviewer/core/auth/web_session_store.dart';
import 'package:daviewer/core/auth/webview_oauth_bridge.dart';
import 'package:daviewer/core/data/web_session.dart' as web;
import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:daviewer/features/web_login/web_login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// P0-A regression: the login screen must close itself as soon as the
/// server-confirmed web session AND the OAuth identity are both known.
///
/// The production failure (Android log 2026-10-13 13:38) was a *scheduling*
/// bug, not a missing condition: the close was already decided at 13:38:23
/// (`server confirmed web session via signed-in home navigation`) but only
/// executed at 13:38:39, as `manual_done`, because it was queued with
/// `WidgetsBinding.addPostFrameCallback` while the app was idle. Post-frame
/// callbacks never request a frame, so the queued close waited for the frame
/// the user's own tap produced — and then fired a *second* time as
/// `login_completed`.
///
/// A plain `pumpAndSettle()` widget test cannot see that: every pump produces
/// the frame the stranded callback is waiting for. These tests therefore drive
/// the whole asynchronous session report inside `tester.runAsync` and assert
/// the navigation has already happened **before any frame is pumped**.

final class _AutoClosePlatform extends InAppWebViewPlatform {
  int controllerCreateCalls = 0;
  InAppWebViewController? controller;
  PlatformInAppWebViewWidgetCreationParams? params;
  final Set<String> _activatedKeys = <String>{};
  String? username;
  WebUri url = WebUri('https://www.deviantart.com/');
  final launches = <Uri>[];

  bool activateOnce(Key? key) {
    final id = key?.toString() ?? '<none>';
    return _activatedKeys.add(id);
  }

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewController(
    PlatformInAppWebViewControllerCreationParams params,
  ) {
    controllerCreateCalls += 1;
    return _AutoCloseController(params, this);
  }

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewControllerStatic() {
    return _AutoCloseController(
      const PlatformInAppWebViewControllerCreationParams(id: 'static'),
      this,
    );
  }

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    return _AutoCloseWidget(params, this);
  }

  /// Delivers a load-stop for the current page, exactly like the platform
  /// WebView would after the signed-in home page finishes loading.
  void deliverLoadStop() {
    final controller = this.controller;
    final params = this.params;
    if (controller == null || params == null) return;
    params.onLoadStop?.call(controller, url);
  }
}

final class _AutoCloseWidget extends PlatformInAppWebViewWidget {
  _AutoCloseWidget(super.params, this.platform) : super.implementation();

  final _AutoClosePlatform platform;

  @override
  Widget build(BuildContext context) {
    if (platform.activateOnce(params.key)) {
      final controller = params.controllerFromPlatform!(
        platform.createPlatformInAppWebViewController(
          PlatformInAppWebViewControllerCreationParams(
            id: 'webview',
            webviewParams: params,
          ),
        ),
      );
      platform.controller = controller;
      platform.params = params;
      params.onWebViewCreated?.call(controller);
    }
    return const SizedBox.expand();
  }

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) {
    return params.controllerFromPlatform!(controller) as T;
  }

  @override
  void dispose() {}
}

final class _AutoCloseController extends PlatformInAppWebViewController {
  _AutoCloseController(super.params, this.platform) : super.implementation();

  final _AutoClosePlatform platform;

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    if (source.contains('JSON.stringify')) {
      return jsonEncode({
        'origin': 'https://www.deviantart.com',
        'csrf': 'synthetic-csrf',
        'username': platform.username,
        'loggedIn': platform.username == null ? null : true,
        'initialized': platform.username != null,
        'blocked': false,
        'challenge': false,
      });
    }
    if (source.contains('document.body')) return '';
    return '{"csrf":"synthetic-csrf"}';
  }

  @override
  Future<WebUri?> getUrl() async => platform.url;

  @override
  Future<String?> getHtml() async => '<html></html>';

  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    WebUri? allowingReadAccessTo,
    Uri? iosAllowingReadAccessTo,
  }) async {
    platform.url = urlRequest.url!;
    platform.launches.add(platform.url.uriValue);
  }

  @override
  Future<void> reload() async {}
}

final class _AutoCloseCookies extends Fake implements CookieManager {
  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    InAppWebViewController? webViewController,
    InAppWebViewController? iosBelow11WebViewController,
  }) async => <Cookie>[
    Cookie(name: 'userinfo', value: '{"username":"artist"}'),
    Cookie(name: 'auth', value: 'synthetic-cookie'),
  ];

  @override
  Future<bool> deleteAllCookies() async => true;
}

/// Counts real navigations so "exactly one close" can be asserted even after
/// the route is gone (a `find.byType` needs a pumped frame; `didPop` does not).
final class _PopRecorder extends NavigatorObserver {
  int pushes = 0;
  int pops = 0;
  int removes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushes += 1;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops += 1;

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      removes += 1;
}

final _sharedTransfers = BackgroundTransferManager(
  diagnostics: AppLogger.instance,
);

void main() {
  // This suite touches the platform method channels from `setUp` (not only from
  // inside `testWidgets`), so the binding has to exist before `main` runs its
  // first statement.
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final values = <String, String>{};
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('daviewer-auto-close-');
    // In-memory flutter_secure_storage mock (same shape as the lifecycle
    // suite): without it, the store's write-verification read returns null
    // and every session report fails with a StateError, so the login screen
    // would never observe a server-confirmed web session.
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = call.arguments as Map;
        if (call.method == 'read') return values[args['key']];
        if (call.method == 'write') values[args['key']] = args['value'];
        if (call.method == 'delete') values.remove(args['key']);
        return null;
      },
    );
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  });

  Future<
    ({
      ProviderContainer container,
      GlobalKey<NavigatorState> navigator,
      _PopRecorder observer,
      _AutoClosePlatform platform,
    })
  >
  boot(WidgetTester tester) async {
    final platform = _AutoClosePlatform()..username = null;
    InAppWebViewPlatform.instance = platform;
    final cookies = _AutoCloseCookies();
    final runtime = AppRuntime(
      clientId: '',
      oauth: null,
      transport: null,
      transfers: _sharedTransfers,
      webViewOAuthBridge: WebViewOAuthBridge(),
    );
    final container = ProviderContainer(
      overrides: [
        runtimeProvider.overrideWithValue(runtime),
        webSessionProvider.overrideWithValue(web.WebSession(() => cookies)),
        webSessionControllerProvider.overrideWith(
          (ref) => WebSessionController(
            ref,
            store: WebSessionStore(directoryFactory: () async => directory),
            cookieManager: () => cookies,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    // OAuth is already signed in with a matching account, so the web session
    // report is the only remaining gate before the screen may close.
    container.read(authControllerProvider.notifier).state = const AuthState(
      status: AuthStatus.signedIn,
      account: UserProfile(id: 'synthetic-user', username: 'artist'),
    );
    final navigator = GlobalKey<NavigatorState>();
    final observer = _PopRecorder();
    // The login AppBar carries four trailing action buttons (refresh,
    // settings, content settings, done). On the default 800x600 test surface
    // the *last* one — the Done button this suite must tap — is laid out
    // off-screen (its center lands around x=976), so a plain tap() would
    // silently miss. Widen the surface instead of shrinking the widget tree.
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: <NavigatorObserver>[observer],
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const WebLoginScreen()),
      ),
    );
    // Build the login route, then let `_cookiesReady` flip so the WebView is
    // instantiated and its controller is handed to the screen.
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    return (
      container: container,
      navigator: navigator,
      observer: observer,
      platform: platform,
    );
  }

  testWidgets(
    'the server-confirmed session closes the login route with no frame pumped',
    (tester) async {
      final booted = await boot(tester);
      final navigator = booted.navigator;
      final observer = booted.observer;
      final platform = booted.platform;
      expect(platform.controller, isNotNull);
      expect(navigator.currentState!.canPop(), isTrue);
      expect(observer.pops, 0);

      // The whole report chain runs in real async time. No frame is produced,
      // which is exactly the production situation: the app is idle while the
      // asynchronous web-session report completes.
      await tester.runAsync(() async {
        platform.username = 'artist';
        for (var attempt = 0; attempt < 40; attempt++) {
          platform.deliverLoadStop();
          for (var i = 0; i < 10; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
            if (!navigator.currentState!.canPop()) break;
          }
          if (!navigator.currentState!.canPop()) break;
        }
      });

      expect(
        navigator.currentState!.canPop(),
        isFalse,
        reason:
            'the login route must close from the asynchronous session report '
            'itself, without waiting for a later frame (P0-A)',
      );
      expect(observer.pops, 1, reason: 'exactly one pop, before any pump');

      // The screen must also stay closed: pumping frames afterwards must not
      // pop a second route (the production log showed `manual_done` followed
      // by a stranded `login_completed`).
      await tester.pumpAndSettle();
      expect(navigator.currentState!.canPop(), isFalse);
      expect(observer.pops, 1);
    },
  );

  testWidgets(
    'a manual close racing the automatic close navigates exactly once',
    (tester) async {
      final booted = await boot(tester);
      final navigator = booted.navigator;
      final observer = booted.observer;
      final platform = booted.platform;
      expect(platform.controller, isNotNull);

      // boot() only pumps zero-duration frames, so the MaterialPageRoute
      // entrance transition is still frozen at its "slid from the right"
      // offset and the Done button is off-canvas. Finish the transition
      // first — on a real device the user can only tap a settled screen.
      await tester.pump(const Duration(milliseconds: 350));

      // The user taps Done first, then the automatic close arrives — the exact
      // production ordering (`manual_done` at 13:38:39.398 followed by
      // `login_completed` at 13:38:39.424).
      await tester.tap(find.byIcon(Icons.check));
      expect(navigator.currentState!.canPop(), isFalse);
      expect(observer.pops, 1);

      await tester.runAsync(() async {
        platform.username = 'artist';
        for (var attempt = 0; attempt < 20; attempt++) {
          platform.deliverLoadStop();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      // The second close must be a no-op: no second pop, and no "Navigator has
      // no routes" failure from popping the root route.
      await tester.pumpAndSettle();
      expect(navigator.currentState!.canPop(), isFalse);
      expect(
        observer.pops,
        1,
        reason: 'the late automatic close must not navigate a second time',
      );
    },
  );
}
