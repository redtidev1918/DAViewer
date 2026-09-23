import 'dart:async';
import 'dart:typed_data';

import 'package:daviewer/core/auth/web_session_controller.dart';
import 'package:daviewer/core/auth/web_session_refresher.dart'
    hide webSessionProbeProvider;
import 'package:daviewer/core/auth/web_session_status.dart';
import 'package:daviewer/core/auth/web_session_verifier.dart';
import 'package:daviewer/core/data/web_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeCookieManager extends Fake implements CookieManager {
  _FakeCookieManager(this._cookies);

  final List<Cookie>? _cookies;

  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    InAppWebViewController? webViewController,
    @Deprecated('Use webViewController instead')
    InAppWebViewController? iosBelow11WebViewController,
  }) async => _cookies ?? const <Cookie>[];
}

final class _HomeHtmlAdapter implements HttpClientAdapter {
  _HomeHtmlAdapter(this.html);

  final String html;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    html,
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>['text/html'],
    },
  );
}

/// Counts how many times the home page was actually fetched.
final class _CountingHtmlAdapter implements HttpClientAdapter {
  _CountingHtmlAdapter(this.html);

  final String html;
  int calls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls += 1;
    return ResponseBody.fromString(
      html,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/html'],
      },
    );
  }
}

/// Completes the home page response only when the test decides.
final class _GatedHtmlAdapter implements HttpClientAdapter {
  _GatedHtmlAdapter(this.completer);

  final Completer<ResponseBody> completer;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => completer.future;
}

ProviderContainer _containerWith(
  HttpClientAdapter adapter, {
  Future<WebSessionProbeResult> Function()? probe,
}) {
  final container = ProviderContainer(
    overrides: <Override>[
      webSessionProvider.overrideWithValue(
        WebSession(
          () => _FakeCookieManager(<Cookie>[
            Cookie(name: 'userinfo', value: 'saved-user'),
            Cookie(name: 'csrf', value: 'token'),
          ]),
        ),
      ),
      webSessionControllerProvider.overrideWith(
        (ref) => WebSessionController(ref),
      ),
      webSessionVerifierProvider.overrideWithValue(
        WebSessionVerifier(Dio()..httpClientAdapter = adapter),
      ),
      webSessionProbeProvider.overrideWithValue(
        probe ?? () async => const WebSessionProbeResult.unavailable(),
      ),
    ],
  );
  container
      .read(webSessionControllerProvider.notifier)
      .state = const WebSessionState(
    csrf: 'token',
    isLoggedIn: true,
    username: 'artist',
  );
  return container;
}

const _signedInHomeHtml =
    '<script>window.__INITIAL_STATE__ = JSON.parse("{\\"@publicSession\\":{\\"user\\":{\\"username\\":\\"artist\\"}}}");</script>';
const _anonymousHomeHtml =
    '<script>window.__INITIAL_STATE__ = JSON.parse("{\\"@publicSession\\":{\\"user\\":{\\"username\\":\\"anonymous\\"}}}");</script>';
const _otherUserHomeHtml =
    '<script>window.__INITIAL_STATE__ = JSON.parse("{\\"@publicSession\\":{\\"user\\":{\\"username\\":\\"someone-else\\"}}}");</script>';

Future<ProviderContainer> _statusContainer(
  String homeHtml, {
  Future<WebSessionProbeResult> Function()? probe,
}) async {
  final container = ProviderContainer(
    overrides: <Override>[
      webSessionProvider.overrideWithValue(
        WebSession(
          () => _FakeCookieManager(<Cookie>[
            Cookie(name: 'userinfo', value: 'saved-user'),
            Cookie(name: 'csrf', value: 'token'),
          ]),
        ),
      ),
      webSessionControllerProvider.overrideWith(
        (ref) => WebSessionController(ref),
      ),
      webSessionVerifierProvider.overrideWithValue(
        WebSessionVerifier(
          Dio()..httpClientAdapter = _HomeHtmlAdapter(homeHtml),
        ),
      ),
      webSessionProbeProvider.overrideWithValue(
        probe ?? () async => const WebSessionProbeResult.unavailable(),
      ),
    ],
  );
  container
      .read(webSessionControllerProvider.notifier)
      .state = const WebSessionState(
    csrf: 'token',
    isLoggedIn: true,
    username: 'artist',
  );
  return container;
}

Future<ProviderContainer> _anonymousSessionContainer() async {
  final container = ProviderContainer(
    overrides: <Override>[
      webSessionProvider.overrideWithValue(
        WebSession(
          () => _FakeCookieManager(<Cookie>[
            Cookie(name: 'userinfo', value: 'saved-user'),
            Cookie(name: 'csrf', value: 'token'),
          ]),
        ),
      ),
      webSessionControllerProvider.overrideWith(
        (ref) => WebSessionController(ref),
      ),
      webSessionVerifierProvider.overrideWithValue(
        WebSessionVerifier(
          Dio()..httpClientAdapter = _HomeHtmlAdapter(_anonymousHomeHtml),
        ),
      ),
    ],
  );
  container.read(webSessionControllerProvider.notifier).state =
      const WebSessionState(csrf: 'token', isLoggedIn: false);
  return container;
}

void main() {
  group('WebSessionStatus', () {
    test('only healthy is usable by the personalized feed', () {
      const healthy = WebSessionStatus(
        state: WebSessionStatusState.healthy,
        serverUsername: 'artist',
      );
      const stale = WebSessionStatus(state: WebSessionStatusState.stale);
      const locked = WebSessionStatus(state: WebSessionStatusState.locked);
      const unverified = WebSessionStatus(
        state: WebSessionStatusState.unverified,
      );
      const unavailable = WebSessionStatus(
        state: WebSessionStatusState.unavailable,
      );

      expect(healthy.isHealthy, isTrue);
      expect(healthy.needsLogin, isFalse);
      expect(stale.isHealthy, isFalse);
      expect(stale.needsLogin, isTrue);
      expect(locked.isLocked, isTrue);
      expect(locked.needsLogin, isTrue);
      // A confirmed WebView session that a bare HTTP probe could not confirm
      // is not a logged-out signal and must not nag the user, because the
      // probe cannot pass PerimeterX and contradicts a working personalized
      // feed. A WAF/network answer is never treated as logged out either.
      expect(unverified.isHealthy, isFalse);
      expect(unverified.needsLogin, isFalse);
      expect(unavailable.needsLogin, isFalse);
    });

    test('cooldown blocks a repeat check', () {
      final status = WebSessionStatus(
        state: WebSessionStatusState.unavailable,
        cooldownUntil: DateTime.now().add(const Duration(minutes: 1)),
      );
      expect(status.inCooldown, isTrue);
    });
  });

  group('WebSessionStatusController.check server verification', () {
    test(
      'marks healthy only when the server confirms the claimed user',
      () async {
        final container = await _statusContainer(_signedInHomeHtml);
        addTearDown(container.dispose);

        await container.read(webSessionStatusProvider.notifier).check();

        final status = container.read(webSessionStatusProvider);
        expect(status.isHealthy, isTrue);
        expect(status.serverUsername, 'artist');
      },
    );

    test(
      'a bare anonymous probe with a confirming real browser is healthy',
      () async {
        final container = await _statusContainer(
          _anonymousHomeHtml,
          probe: () async => const WebSessionProbeResult.confirmed(
            csrf: 'token',
            username: 'artist',
          ),
        );
        addTearDown(container.dispose);

        await container.read(webSessionStatusProvider.notifier).check();

        final status = container.read(webSessionStatusProvider);
        // The bare probe was a WAF false negative: the real browser, with the
        // same cookie store and request stack as login, confirms the account.
        expect(status.isHealthy, isTrue);
        expect(status.serverUsername, 'artist');
        expect(status.needsLogin, isFalse);
      },
    );

    test(
      'a real-browser anonymous answer surfaces the login reminder',
      () async {
        final container = await _statusContainer(
          _anonymousHomeHtml,
          probe: () async =>
              const WebSessionProbeResult.anonymous(csrf: 'token'),
        );
        addTearDown(container.dispose);

        await container.read(webSessionStatusProvider.notifier).check();

        final status = container.read(webSessionStatusProvider);
        // Both the bare page and the real browser report logged out: the web
        // Cookie is really dead and the user must be told, instead of the
        // personalized feed silently degrading to generic content.
        expect(status.state, WebSessionStatusState.anonymous);
        expect(status.needsLogin, isTrue);
        // The web identity itself is preserved for the login screen; the
        // status verdict is what gates the recommendations tab.
        final controllerState = container.read(webSessionControllerProvider);
        expect(controllerState.isLoggedIn, isTrue);
        expect(controllerState.username, 'artist');
      },
    );

    test(
      'a real-browser probe failure stays unverified, never logged out',
      () async {
        final container = await _statusContainer(_anonymousHomeHtml);
        addTearDown(container.dispose);

        await container.read(webSessionStatusProvider.notifier).check();

        final status = container.read(webSessionStatusProvider);
        // The real browser could not answer either (challenge/network):
        // stay non-committal so a WAF false negative never nags the user.
        expect(status.state, WebSessionStatusState.unverified);
        expect(status.needsLogin, isFalse);
        final controllerState = container.read(webSessionControllerProvider);
        expect(controllerState.isLoggedIn, isTrue);
        expect(controllerState.username, 'artist');
      },
    );

    test(
      'an anonymous probe without a confirmed session is anonymous',
      () async {
        final container = await _anonymousSessionContainer();
        addTearDown(container.dispose);

        await container.read(webSessionStatusProvider.notifier).check();

        final status = container.read(webSessionStatusProvider);
        expect(status.state, WebSessionStatusState.anonymous);
        expect(status.needsLogin, isTrue);
      },
    );

    test(
      'a WAF/network probe answer is unavailable, never anonymous',
      () async {
        final container = await _statusContainer('<html/>');
        addTearDown(container.dispose);

        await container.read(webSessionStatusProvider.notifier).check();

        final status = container.read(webSessionStatusProvider);
        expect(status.state, WebSessionStatusState.unavailable);
        expect(status.needsLogin, isFalse);
      },
    );

    test('empty live cookies with a saved snapshot are unavailable, not signed out', () {
      expect(
        emptyLiveCookieStatus(persistedCookieCount: 1),
        WebSessionStatusState.unavailable,
      );
    });

    test('empty live and saved cookies are anonymous', () {
      expect(
        emptyLiveCookieStatus(persistedCookieCount: 0),
        WebSessionStatusState.anonymous,
      );
    });

    test('marks anonymous when the server identity differs', () async {
      final container = await _statusContainer(_otherUserHomeHtml);
      addTearDown(container.dispose);

      await container.read(webSessionStatusProvider.notifier).check();

      final status = container.read(webSessionStatusProvider);
      expect(status.state, WebSessionStatusState.anonymous);
      expect(status.needsLogin, isTrue);
    });

    test('concurrent checks share one in-flight verification', () async {
      final adapter = _CountingHtmlAdapter(_signedInHomeHtml);
      final container = _containerWith(adapter);
      addTearDown(container.dispose);
      final controller = container.read(webSessionStatusProvider.notifier);

      await Future.wait(<Future<void>>[controller.check(), controller.check()]);

      expect(adapter.calls, 1);
      expect(container.read(webSessionStatusProvider).isHealthy, isTrue);
    });

    test('a stale anonymous check never overrides a newer login', () async {
      final gate = Completer<ResponseBody>();
      final container = _containerWith(_GatedHtmlAdapter(gate));
      addTearDown(container.dispose);
      final controller = container.read(webSessionStatusProvider.notifier);

      final checkFuture = controller.check();
      // Let the check reach the server await before login confirms the session.
      await Future<void>.delayed(Duration.zero);
      controller.markHealthy(serverUsername: 'artist');
      gate.complete(
        ResponseBody.fromString(
          _anonymousHomeHtml,
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['text/html'],
          },
        ),
      );
      await checkFuture;

      final status = container.read(webSessionStatusProvider);
      expect(status.isHealthy, isTrue);
      expect(status.serverUsername, 'artist');
    });
  });
}
