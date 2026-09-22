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

void main() {
  group('WebSessionStatus', () {
    test('only healthy is usable by the personalized feed', () {
      const healthy = WebSessionStatus(
        state: WebSessionStatusState.healthy,
        serverUsername: 'artist',
      );
      const stale = WebSessionStatus(state: WebSessionStatusState.stale);
      const locked = WebSessionStatus(state: WebSessionStatusState.locked);

      expect(healthy.isHealthy, isTrue);
      expect(healthy.needsLogin, isFalse);
      expect(stale.isHealthy, isFalse);
      expect(stale.needsLogin, isTrue);
      expect(locked.isLocked, isTrue);
      expect(locked.needsLogin, isTrue);
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

    test('marks anonymous when the server sees an anonymous session', () async {
      final container = await _statusContainer(_anonymousHomeHtml);
      addTearDown(container.dispose);

      await container.read(webSessionStatusProvider.notifier).check();

      final status = container.read(webSessionStatusProvider);
      expect(status.state, WebSessionStatusState.anonymous);
      expect(status.needsLogin, isTrue);
    });

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
  });
}
