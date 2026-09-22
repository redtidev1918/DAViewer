import 'dart:async';
import 'dart:typed_data';

import 'package:daviewer/core/auth/web_session_controller.dart';
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

ProviderContainer _containerWith(HttpClientAdapter adapter) {
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

Future<ProviderContainer> _statusContainer(String homeHtml) async {
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
      // is not a logged-out signal, but it is surfaced to the user with a
      // login reminder instead of staying silent. A WAF/network answer is
      // never treated as logged out.
      expect(unverified.isHealthy, isFalse);
      expect(unverified.needsLogin, isTrue);
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
      'a bare anonymous probe keeps a confirmed session as unverified',
      () async {
        final container = await _statusContainer(_anonymousHomeHtml);
        addTearDown(container.dispose);

        await container.read(webSessionStatusProvider.notifier).check();

        final status = container.read(webSessionStatusProvider);
        expect(status.state, WebSessionStatusState.unverified);
        // The confirmed WebView session survives, but the unverified state is
        // surfaced so the user can choose to re-verify via login.
        expect(status.needsLogin, isTrue);
        // The confirmed WebView session itself must survive the false-negative
        // probe; only explicit logout clears it.
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
