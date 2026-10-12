import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:daviewer/core/auth/auth_controller.dart';
import 'package:daviewer/core/auth/auth_state.dart';
import 'package:daviewer/core/auth/web_session_controller.dart';
import 'package:daviewer/core/auth/web_session_store.dart';
import 'package:daviewer/core/auth/web_session_status.dart';
import 'package:daviewer/core/data/web_session.dart' as web;
import 'package:daviewer/core/auth/webview_oauth_bridge.dart';
import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:daviewer/core/l10n/app_strings.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:daviewer/features/web_login/web_login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:daviewer/features/home/home_providers.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

final _sharedTransfers = BackgroundTransferManager(
  diagnostics: AppLogger.instance,
);

final class _LifecyclePlatform extends InAppWebViewPlatform {
  int controllerCreateCalls = 0;
  int reloadCalls = 0;
  InAppWebViewController? controller;
  PlatformInAppWebViewWidgetCreationParams? params;
  final Set<String> _activatedKeys = <String>{};
  bool challenge = true;
  String? username;
  WebUri url = WebUri('https://www.deviantart.com/users/login');
  final launches = <Uri>[];
  bool failAuthorize = false;
  bool failHome = false;

  bool activateOnce(Key? key) {
    final id = key?.toString() ?? '<none>';
    return _activatedKeys.add(id);
  }

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewController(
    PlatformInAppWebViewControllerCreationParams params,
  ) {
    controllerCreateCalls += 1;
    return _LifecycleController(params, this);
  }

  @override
  PlatformInAppWebViewController createPlatformInAppWebViewControllerStatic() {
    return _LifecycleController(
      const PlatformInAppWebViewControllerCreationParams(id: 'static'),
      this,
    );
  }

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    return _LifecycleWidget(params, this);
  }

  Future<void> triggerLoadStop() async {
    final controller = this.controller;
    final params = this.params;
    if (controller == null || params == null) return;
    params.onLoadStop?.call(
      controller,
      WebUri('https://www.deviantart.com/users/login'),
    );
  }
}

final class _LoginTokens implements TokenStore {
  AuthTokens? value;
  @override
  Future<void> clear() async => value = null;
  @override
  Future<AuthTokens?> read() async => value;
  @override
  Future<void> write(AuthTokens tokens) async => value = tokens;
}

final class _LoginPending implements PendingAuthorizationStore {
  PendingAuthorization? value;
  @override
  Future<void> clear() async => value = null;
  @override
  Future<PendingAuthorization?> read() async => value;
  @override
  Future<void> write(PendingAuthorization pending) async => value = pending;
}

final class _LoginEndpoint implements OAuthEndpoint {
  int exchanges = 0;
  @override
  Future<Map<String, Object?>> postForm(
    Uri endpoint,
    Map<String, String> form,
  ) async {
    if (form['grant_type'] == 'authorization_code') {
      exchanges++;
      expect(form['code_verifier'], isNotEmpty);
      expect(form['code'], 'synthetic-code');
      return {
        'access_token': 'synthetic-new-token',
        'refresh_token': 'synthetic-new-refresh',
        'token_type': 'Bearer',
        'expires_in': 3600,
      };
    }
    return {};
  }
}

final class _LoginCookies extends Fake implements CookieManager {
  final values = <String, String>{
    'userinfo': '{"username":"artist"}',
    'auth': 'old',
  };
  @override
  Future<bool> deleteAllCookies() async {
    values.clear();
    return true;
  }

  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    InAppWebViewController? webViewController,
    InAppWebViewController? iosBelow11WebViewController,
  }) async => [
    for (final entry in values.entries)
      Cookie(name: entry.key, value: entry.value),
  ];
}

final class _LoginAdapter implements HttpClientAdapter {
  int rfyCalls = 0;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object response;
    if (options.uri.path.endsWith('/user/whoami')) {
      response = {
        'userid': 'synthetic-user',
        'username': 'artist',
        'usericon': 'https://example.test/icon.png',
      };
    } else if (options.uri.path.endsWith('/rfy/deviations')) {
      rfyCalls++;
      response = {
        'deviations': [
          {
            'deviationId': 12345,
            'title': 'Synthetic art',
            'author': {'username': 'artist'},
            'url': 'https://www.deviantart.com/artist/art/test-12345',
          },
        ],
      };
    } else {
      response = {};
    }
    return ResponseBody.fromString(
      jsonEncode(response),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

final class _LifecycleWidget extends PlatformInAppWebViewWidget {
  _LifecycleWidget(super.params, this.platform) : super.implementation();

  final _LifecyclePlatform platform;
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

final class _LifecycleController extends PlatformInAppWebViewController {
  _LifecycleController(super.params, this.platform) : super.implementation();

  final _LifecyclePlatform platform;

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
        'initialized': platform.username != null,
        'challenge': platform.challenge,
      });
    }
    if (source.contains('document.body')) {
      return platform.challenge ? 'Max challenge attempts exceeded' : '';
    }
    return '{"csrf":"fake-token"}';
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
    if ((platform.failAuthorize &&
            urlRequest.url!.path == '/oauth2/authorize') ||
        (platform.failHome && urlRequest.url!.path == '/')) {
      platform.failAuthorize = false;
      platform.failHome = false;
      throw PlatformException(
        code: 'native_load_failed',
        message: 'synthetic-private-query',
      );
    }
    platform.url = urlRequest.url!;
    platform.launches.add(platform.url.uriValue);
  }

  @override
  Future<void> reload() async {
    platform.reloadCalls += 1;
  }
}

void registerLogoutLoginTest(String failure) {
  testWidgets(
    'explicit logout then PKCE login restores account, closes and owns one RFY: $failure',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('daviewer-login-'),
      ))!;
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      const secure = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final values = <String, String>{};
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
      messenger.setMockMethodCallHandler(secure, (call) async {
        final args = call.arguments as Map;
        if (call.method == 'read') return values[args['key']];
        if (call.method == 'write') values[args['key']] = args['value'];
        if (call.method == 'delete') values.remove(args['key']);
        return null;
      });
      final logger = (await tester.runAsync(
        () => AppLogger.initialize(fileName: 'login.log'),
      ))!;
      final bridge = WebViewOAuthBridge();
      final tokens = _LoginTokens();
      final endpoint = _LoginEndpoint();
      final oauth = DAKitOAuthClient(
        config: OAuthConfig(
          clientId: 'synthetic-client',
          redirectUri: Uri.parse('dakit://oauth/callback'),
        ),
        tokenStore: tokens,
        pendingStore: _LoginPending(),
        launcher: bridge,
        callbacks: bridge.callbacks,
        endpoint: endpoint,
        diagnostics: logger,
      );
      final adapter = _LoginAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final cookies = _LoginCookies();
      final runtime = AppRuntime(
        clientId: 'synthetic-client',
        oauth: oauth,
        transport: OfficialApiClient(
          session: oauth.session,
          dio: dio,
          diagnostics: logger,
        ),
        transfers: _sharedTransfers,
        dio: dio,
        webViewOAuthBridge: bridge,
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
      addTearDown(() async {
        await tester.runAsync(oauth.authorization.cancelPending);
        await tester.pump(const Duration(milliseconds: 5));
        await tester.runAsync(() async {
          container.dispose();
          await bridge.dispose();
          await logger.dispose();
          messenger.setMockMethodCallHandler(paths, null);
          messenger.setMockMethodCallHandler(secure, null);
          await directory.delete(recursive: true);
        });
      });
      final auth = container.read(authControllerProvider.notifier);
      await oauth.session.save(
        AuthTokens(
          accessToken: 'synthetic-old-token',
          tokenType: 'Bearer',
          refreshToken: 'synthetic-old-refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      auth.state = const AuthState(status: AuthStatus.signedIn);
      await tester.runAsync(auth.logout);
      expect(auth.state.oauthSignedIn, isFalse);
      expect(tokens.value, isNull);
      expect(cookies.values, isEmpty);
      final platform = _LifecyclePlatform()
        ..challenge = false
        ..failAuthorize = failure == 'authorize'
        ..failHome = failure == 'home';
      InAppWebViewPlatform.instance = platform;
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('home')),
          ),
        ),
      );
      unawaited(
        navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const WebLoginScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      // Real I/O/logger flushes interleave with the OAuth and platform callbacks.
      await tester.runAsync(() async {
        for (var i = 0; i < 100 && platform.launches.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump();
      if (failure == 'authorize') {
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          find.text(
            strings(container.read(appLanguageProvider)).loginBrowserOpenFailed,
          ),
          findsOneWidget,
        );
        expect(endpoint.exchanges, 0);
        final refresh = find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.refresh),
        );
        await tester.tap(refresh);
        await tester.pump();
      }
      expect(platform.launches, hasLength(1));
      final authorize = platform.launches.single;
      expect(authorize.path, '/oauth2/authorize');
      expect(
        platform.params!.initialSettings!.useShouldOverrideUrlLoading,
        isTrue,
      );
      final callback = Uri(
        scheme: 'dakit',
        host: 'oauth',
        path: '/callback',
        queryParameters: {
          'state': authorize.queryParameters['state']!,
          'code': 'synthetic-code',
        },
      );
      await tester.runAsync(() async {
        final policy = await platform.params!.shouldOverrideUrlLoading!(
          platform.controller!,
          NavigationAction(
            request: URLRequest(url: WebUri(callback.toString())),
            isForMainFrame: true,
          ),
        );
        expect(policy, NavigationActionPolicy.CANCEL);
        for (var i = 0; i < 100 && auth.state.account == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      for (var i = 0; i < 100 && auth.state.account == null; i++) {
        await tester.pump(const Duration(milliseconds: 5));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        });
      }
      expect(endpoint.exchanges, 1);
      expect(auth.state.account?.username, 'artist');
      expect(auth.state.oauthSignedIn, isTrue);
      await tester.pump();
      if (failure == 'home') {
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          find.text(
            strings(container.read(appLanguageProvider)).loginBrowserOpenFailed,
          ),
          findsOneWidget,
        );
        expect(
          find.text(strings(container.read(appLanguageProvider)).loginSuccess),
          findsNothing,
        );
        expect(platform.url.path, '/oauth2/authorize');
        final refresh = find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.refresh),
        );
        await tester.tap(refresh);
        await tester.pump();
        expect(platform.url.path, '/');
        expect(endpoint.exchanges, 1);
      }
      expect(
        find.byType(WebLoginScreen),
        findsOneWidget,
      ); // OAuth alone cannot close
      cookies.values.addAll({
        'userinfo': '{"username":"artist"}',
        'auth': 'synthetic-cookie',
      });
      platform.username = 'artist';
      platform.url = WebUri('https://www.deviantart.com/');
      platform.params!.onLoadStop!(platform.controller!, platform.url);
      await tester.runAsync(() async {
        for (
          var i = 0;
          i < 100 &&
              container.read(webSessionControllerProvider).isLoggedIn != true;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      for (
        var i = 0;
        i < 100 &&
            container.read(webSessionStatusProvider).state !=
                WebSessionStatusState.healthy;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 5));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        });
      }
      await tester.pumpAndSettle();
      expect(find.byType(WebLoginScreen), findsNothing);
      expect(
        container.read(webSessionStatusProvider).state,
        WebSessionStatusState.healthy,
      );
      container.read(personalizedFeedProvider.notifier);
      for (
        var i = 0;
        i < 100 && container.read(personalizedFeedProvider).items.isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 5));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        });
      }
      expect(adapter.rfyCalls, 1);
      expect(container.read(personalizedFeedProvider).items, hasLength(1));
      var flushed = false;
      unawaited(logger.flush().then((_) => flushed = true));
      for (var i = 0; i < 1000 && !flushed; i++) {
        await tester.pump(const Duration(milliseconds: 5));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        });
      }
      expect(flushed, isTrue);
      final log = await tester.runAsync(
        () => File('${logger.logsDirectory}/login.log').readAsString(),
      );
      expect(
        log,
        contains('authorize dispatched target=embedded listener=true'),
      );
      expect(log, contains('callback received path=/callback'));
      expect(log, contains('oauth.callback.validated'));
      expect(log, contains('oauth.session.saved'));
      expect(log, contains('reason=login_completed'));
      expect(log, contains('phase=accepted'));
      if (failure != 'none') {
        expect(log, contains('navigation failed source=oauth_'));
        expect(log, isNot(contains('synthetic-private-query')));
      }
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

void main() {
  registerLogoutLoginTest('none');
  testWidgets(
    'rebuild and challenge banner never recreate or reload the WebView',
    (tester) async {
      final platform = _LifecyclePlatform();
      InAppWebViewPlatform.instance = platform;
      final rebuild = ValueNotifier<int>(0);
      addTearDown(rebuild.dispose);
      final runtime = AppRuntime(
        clientId: '',
        oauth: null,
        transport: null,
        transfers: _sharedTransfers,
        webViewOAuthBridge: WebViewOAuthBridge(),
      );

      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: <Override>[runtimeProvider.overrideWithValue(runtime)],
          child: ValueListenableBuilder<int>(
            valueListenable: rebuild,
            builder: (context, value, child) =>
                MaterialApp(home: WebLoginScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(platform.controllerCreateCalls, 1);
      await platform.triggerLoadStop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining('Max challenge attempts exceeded'),
        findsOneWidget,
      );

      rebuild.value += 1;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(platform.controllerCreateCalls, 1);
      expect(platform.reloadCalls, 0);
    },
  );
}
