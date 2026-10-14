import 'dart:async';

import 'package:daviewer/core/auth/browser_session_observer.dart';
import 'package:daviewer/core/auth/web_session_controller.dart';
import 'package:daviewer/core/auth/web_session_refresher.dart'
    hide webSessionProbeProvider;
import 'package:daviewer/core/auth/web_session_status.dart';
import 'package:daviewer/core/auth/web_session_verifier.dart';
import 'package:daviewer/core/data/web_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the v0.5.19 Android incident: a DeviantArt WAF
/// lockout on the headless session probe was discarded whenever the cookie jar
/// rotated with the block page, which
///
/// 1. classified the block as a generic `page_uninitialized`, and
/// 2. let `recovery inconclusive retained=healthy_lease` keep a stale healthy
///    verdict, so the feed kept retrying a blocked network with no actionable
///    guidance for the user.
///
/// A block or verification challenge makes no identity claim, so it must
/// survive credential churn and must reach the locked state.

final class _FakeCookieManager extends Fake implements CookieManager {
  _FakeCookieManager(this._cookies);

  final List<Cookie> _cookies;

  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    InAppWebViewController? webViewController,
    @Deprecated('Use webViewController instead')
    InAppWebViewController? iosBelow11WebViewController,
  }) async => _cookies;
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
    '<script>window.__INITIAL_STATE__ = JSON.parse("{\\"@@publicSession\\":{\\"isLoggedIn\\":true,\\"user\\":{\\"username\\":\\"artist\\"}}}");</script>';

ProviderContainer _container({
  Future<WebSessionProbeResult> Function()? probe,
}) {
  final container = ProviderContainer(
    retry: (_, _) => null,
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
          Dio()..httpClientAdapter = _HomeHtmlAdapter(_signedInHomeHtml),
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
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('blocked or challenged evidence survives credential rotation', () {
    test('keeps an explicit WAF lockout page', () async {
      // Cookies rotate across the read, exactly as a block page's Set-Cookie
      // does; losing the sample here is what hid the lockout.
      var reads = 0;
      final evidence = await readBrowserEvidenceWithCredentials(
        cookieHeader: () async =>
            'userinfo=${reads++ == 0 ? 'before' : 'after'}',
        readPage: () async =>
            const BrowserSessionEvidence(blocked: true, initialized: false),
      );

      expect(evidence.blocked, isTrue);
      expect(evidence.classification, 'blocked');
    });

    test('keeps a human-verification challenge page', () async {
      var reads = 0;
      final evidence = await readBrowserEvidenceWithCredentials(
        cookieHeader: () async => 'userinfo=${reads++ == 0 ? 'a' : 'b'}',
        readPage: () async =>
            const BrowserSessionEvidence(challenge: true, initialized: false),
      );

      expect(evidence.challenge, isTrue);
      expect(evidence.classification, 'challenge');
    });

    test('an ordinary rotated sample is still discarded', () async {
      // The credential-binding boundary is unchanged for identity claims.
      var reads = 0;
      final evidence = await readBrowserEvidenceWithCredentials(
        cookieHeader: () async => 'userinfo=${reads++ == 0 ? 'a' : 'b'}',
        readPage: () async => const BrowserSessionEvidence(
          username: 'artist',
          loggedIn: true,
          initialized: true,
        ),
      );

      expect(evidence.hasIdentity, isFalse);
      expect(evidence.classification, 'page_uninitialized');
    });
  });

  group('probe outcome decides the verdict', () {
    test(
      'a blocked probe locks instead of retaining a healthy lease',
      () async {
        final container = _container(
          probe: () async =>
              const WebSessionProbeResult.unavailable(blocked: true),
        );
        final owner = container.read(webSessionStatusProvider.notifier);
        // A previous check succeeded inside the lease window.
        owner.markHealthy(serverUsername: 'artist');
        expect(container.read(webSessionStatusProvider).isHealthy, isTrue);

        await owner.check(force: true, browser: true);

        final status = container.read(webSessionStatusProvider);
        expect(
          status.isLocked,
          isTrue,
          reason: 'a server lockout must not be hidden by the healthy lease',
        );
        expect(status.needsLogin, isTrue, reason: 'the user must be told');
        expect(status.isHealthy, isFalse);
      },
    );

    test('a plain unavailable probe still retains a healthy lease', () async {
      final container = _container(
        probe: () async => const WebSessionProbeResult.unavailable(),
      );
      final owner = container.read(webSessionStatusProvider.notifier);
      owner.markHealthy(serverUsername: 'artist');

      await owner.check(force: true, browser: true);

      // Unchanged behaviour: an inconclusive probe is not a lockout.
      expect(container.read(webSessionStatusProvider).isHealthy, isTrue);
    });
  });
}
