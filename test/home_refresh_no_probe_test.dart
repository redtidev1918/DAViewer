import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dakit_flutter/dakit_flutter.dart' hide WebSession;
import 'package:daviewer/core/auth/web_session_controller.dart';
import 'package:daviewer/core/auth/personalized_session_status.dart';
import 'package:daviewer/core/auth/web_session_refresher.dart'
    hide webSessionProbeProvider;
import 'package:daviewer/core/auth/web_session_status.dart';
import 'package:daviewer/core/auth/web_session_verifier.dart';
import 'package:daviewer/core/data/web_session.dart';
import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:daviewer/features/home/home_screen.dart';
import 'package:daviewer/features/home/home_providers.dart';
import 'package:daviewer/features/artwork/artwork_store.dart';
import 'package:daviewer/shared/widgets/artwork_feed_grid.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

final class _FakeCookieManager extends Fake implements CookieManager {
  String csrfCookie = 'token';
  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    InAppWebViewController? webViewController,
    @Deprecated('Use webViewController instead')
    InAppWebViewController? iosBelow11WebViewController,
  }) async => <Cookie>[
    Cookie(name: 'userinfo', value: 'artist'),
    Cookie(name: 'csrf', value: csrfCookie),
  ];
}

/// Serves the rfy endpoint and counts first-page requests by cursor.
final class _RfyAdapter implements HttpClientAdapter {
  String? nextCursor;
  Future<void>? gate;
  void Function()? onFetch;
  int calls = 0;
  final List<String> cursors = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.uri.path.endsWith('/rfy/deviations')) {
      calls += 1;
      onFetch?.call();
      await gate;
      final cursor = options.queryParameters['cursor'] as String?;
      cursors.add(cursor ?? 'initial');
      return _json(<String, Object?>{
        if (nextCursor != null) 'nextCursor': nextCursor,
        'deviations': <Object?>[
          <String, Object?>{
            'deviationId': 12345,
            'url': 'https://www.deviantart.com/artist/art/title-12345',
            'title': 'Art',
            'author': <String, Object?>{'username': 'artist'},
            'media': <String, Object?>{
              'baseUri': 'https://images.example.test/art',
              'prettyName': 'art',
              'types': <Object?>[
                <String, Object?>{'t': 'image', 'w': 600, 'h': 400},
              ],
            },
            'isDownloadable': true,
          },
        ],
      });
    }
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<Object?>(
        requestOptions: options,
        statusCode: 404,
        statusMessage: 'Not Found',
      ),
    );
  }
}

/// Serves the DeviantArt home page the way the web-session verifier reads it,
/// and counts every probe.
final class _HomeProbeAdapter implements HttpClientAdapter {
  _HomeProbeAdapter({this.username = 'artist'});
  final String username;
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
    final escaped = jsonEncode(<String, Object?>{
      '@publicSession': <String, Object?>{
        'user': <String, Object?>{'username': username},
      },
    });
    return ResponseBody.fromString(
      'window.__INITIAL_STATE__ = JSON.parse(${jsonEncode(escaped)});',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/html'],
      },
    );
  }
}

/// FileDownloaderBackend exposes a single-listener stream, so every test in
/// this file must share one transfer manager.
final _sharedTransfers = BackgroundTransferManager(
  diagnostics: AppLogger.instance,
);

ResponseBody _json(Map<String, Object?> body) => ResponseBody.fromString(
  jsonEncode(body),
  200,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>['application/json'],
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer feedContainer(
    _RfyAdapter rfy,
    _HomeProbeAdapter probe, {
    _FakeCookieManager? cookies,
  }) {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        runtimeProvider.overrideWithValue(
          AppRuntime(
            clientId: 'test',
            oauth: null,
            transport: null,
            transfers: _sharedTransfers,
            dio: Dio()..httpClientAdapter = rfy,
          ),
        ),
        webSessionProvider.overrideWithValue(
          WebSession(() => cookies ?? _FakeCookieManager()),
        ),
        webSessionVerifierProvider.overrideWithValue(
          WebSessionVerifier(Dio()..httpClientAdapter = probe),
        ),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(webSessionControllerProvider.notifier)
        .state = const WebSessionState(
      csrf: 'token',
      isLoggedIn: true,
      username: 'artist',
    );
    container
        .read(webSessionStatusProvider.notifier)
        .markHealthy(serverUsername: 'artist');
    return container;
  }

  test(
    'generic signal is rejected even when identity verification succeeds',
    () async {
      final rfy = _RfyAdapter()
        ..nextCursor = base64Url.encode(
          utf8.encode(jsonEncode({'vespa_content_group': 2})),
        );
      final container = feedContainer(rfy, _HomeProbeAdapter());
      await container.read(personalizedFeedProvider.notifier).refresh();

      expect(container.read(webSessionStatusProvider).isHealthy, isTrue);
      expect(
        container.read(personalizedSessionStatusProvider).needsRecovery,
        isTrue,
      );
      expect(container.read(personalizedFeedProvider).items, isEmpty);
      expect(container.read(artworkStoreProvider)['12345'], isNull);
      expect(
        (container.read(personalizedFeedProvider).error as DAKitException).code,
        'rfy.session.degraded',
      );

      // An explicit recovery supersedes the incident and retries the same feed.
      container
          .read(webSessionStatusProvider.notifier)
          .markHealthy(serverUsername: 'artist');
      expect(
        container.read(personalizedSessionStatusProvider).needsRecovery,
        isFalse,
      );
      rfy.nextCursor = null;
      await container.read(personalizedFeedProvider.notifier).refresh();
      expect(container.read(personalizedFeedProvider).items, hasLength(1));
      expect(
        container.read(personalizedSessionStatusProvider).phase,
        PersonalizedSessionPhase.usable,
      );
    },
  );

  test('changed cookies bypass a recently healthy identity lease', () async {
    final cookies = _FakeCookieManager();
    final probe = _HomeProbeAdapter();
    final container = feedContainer(_RfyAdapter(), probe, cookies: cookies);
    final feed = container.read(personalizedFeedProvider.notifier);
    await feed.refresh();
    expect(probe.calls, 0);
    cookies.csrfCookie = 'rotated';
    await feed.refresh();
    expect(probe.calls, 1);
    expect(container.read(personalizedFeedProvider).items, hasLength(1));
  });

  test(
    'a late generic result cannot replace a newer same-account login',
    () async {
      final gate = Completer<void>();
      final entered = Completer<void>();
      final rfy = _RfyAdapter()
        ..nextCursor = base64Url.encode(
          utf8.encode(jsonEncode({'vespa_content_group': 2})),
        )
        ..gate = gate.future
        ..onFetch = entered.complete;
      final container = feedContainer(rfy, _HomeProbeAdapter());
      final pending = container
          .read(personalizedFeedProvider.notifier)
          .refresh();
      await entered.future;
      container
          .read(webSessionStatusProvider.notifier)
          .markHealthy(serverUsername: 'artist');
      gate.complete();
      await pending;
      expect(
        container.read(personalizedSessionStatusProvider).needsRecovery,
        isFalse,
      );
      expect(container.read(personalizedFeedProvider).items, isEmpty);
      expect(container.read(artworkStoreProvider)['12345'], isNull);
    },
  );

  test('a cookie rotation during a feed request discards its result', () async {
    final gate = Completer<void>();
    final entered = Completer<void>();
    final cookies = _FakeCookieManager();
    final rfy = _RfyAdapter()
      ..gate = gate.future
      ..onFetch = entered.complete;
    final container = feedContainer(rfy, _HomeProbeAdapter(), cookies: cookies);
    final pending = container.read(personalizedFeedProvider.notifier).refresh();
    await entered.future;
    cookies.csrfCookie = 'rotated';
    gate.complete();
    await pending;
    expect(container.read(personalizedFeedProvider).items, isEmpty);
    expect(container.read(artworkStoreProvider)['12345'], isNull);
  });

  for (final anonymous in [true, false]) {
    test(
      anonymous
          ? 'unknown stale Cookie is verified before accepting generic HTTP 200'
          : 'browser challenge blocks unverified recommendations without expiry',
      () async {
        final rfy = _RfyAdapter();
        final probe = _HomeProbeAdapter(username: 'anonymous');
        final container = ProviderContainer(
          retry: (_, _) => null,
          overrides: [
            runtimeProvider.overrideWithValue(
              AppRuntime(
                clientId: 'test',
                oauth: null,
                transport: null,
                transfers: _sharedTransfers,
                dio: Dio()..httpClientAdapter = rfy,
              ),
            ),
            webSessionProvider.overrideWithValue(
              WebSession(_FakeCookieManager.new),
            ),
            webSessionVerifierProvider.overrideWithValue(
              WebSessionVerifier(Dio()..httpClientAdapter = probe),
            ),
            webSessionProbeProvider.overrideWithValue(
              () async => anonymous
                  ? const WebSessionProbeResult.anonymous()
                  : const WebSessionProbeResult.unavailable(),
            ),
          ],
        );
        addTearDown(container.dispose);
        container
            .read(webSessionControllerProvider.notifier)
            .state = const WebSessionState(
          csrf: 'token',
          isLoggedIn: true,
          username: 'artist',
        );

        await container.read(personalizedFeedProvider.notifier).refresh();

        expect(probe.calls, 1);
        expect(
          rfy.calls,
          0,
          reason: 'generic HTTP 200 is not personalization proof',
        );
        expect(container.read(personalizedFeedProvider).items, isEmpty);
        expect(container.read(webSessionStatusProvider).needsLogin, anonymous);
        final error =
            container.read(personalizedFeedProvider).error as DAKitException;
        expect(
          error.code,
          anonymous ? 'web.session.unavailable' : 'rfy.session.unverified',
        );
      },
    );
  }

  testWidgets(
    'pull-to-refresh re-fetches rfy without a home-page verifier probe',
    (tester) async {
      final rfyAdapter = _RfyAdapter();
      final probeAdapter = _HomeProbeAdapter();
      final runtime = AppRuntime(
        clientId: 'test-client',
        oauth: null,
        transport: null,
        transfers: _sharedTransfers,
        dio: Dio()..httpClientAdapter = rfyAdapter,
      );
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: <Override>[
          runtimeProvider.overrideWithValue(runtime),
          webSessionReadyProvider.overrideWith((ref) => true),
          webSessionProvider.overrideWithValue(
            WebSession(_FakeCookieManager.new),
          ),
          webSessionControllerProvider.overrideWith(
            (ref) => WebSessionController(ref),
          ),
          webSessionVerifierProvider.overrideWithValue(
            WebSessionVerifier(Dio()..httpClientAdapter = probeAdapter),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(webSessionControllerProvider.notifier)
          .state = const WebSessionState(
        csrf: 'token',
        isLoggedIn: true,
        username: 'artist',
      );

      container
          .read(webSessionStatusProvider.notifier)
          .markHealthy(serverUsername: 'artist');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: PersonalizedFeed())),
        ),
      );
      await tester.pumpAndSettle();

      // The fresh login confirmation is reused. HTTP 200 did not establish it.
      expect(container.read(webSessionStatusProvider).isHealthy, isTrue);

      // The controller's initial auto-load is the only first-page fetch so
      // far, and no WAF-sensitive home-page probe ran.
      expect(rfyAdapter.calls, 1);
      expect(rfyAdapter.cursors, <String>['initial']);
      expect(probeAdapter.calls, 0);

      // User pulls to refresh: exactly one more first-page rfy request and
      // still no home-page verifier probe.
      await tester.drag(
        find.byType(ArtworkFeedGrid).first,
        const Offset(0, 400),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(rfyAdapter.calls, 2);
      expect(rfyAdapter.cursors, <String>['initial', 'initial']);
      expect(probeAdapter.calls, 0);
    },
  );

  testWidgets(
    'an anonymous web-session verdict shows recovery, not generic content',
    (tester) async {
      final rfyAdapter = _RfyAdapter();
      final runtime = AppRuntime(
        clientId: 'test-client',
        oauth: null,
        transport: null,
        transfers: _sharedTransfers,
        dio: Dio()..httpClientAdapter = rfyAdapter,
      );
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: <Override>[
          runtimeProvider.overrideWithValue(runtime),
          webSessionReadyProvider.overrideWith((ref) => true),
          webSessionProvider.overrideWithValue(
            WebSession(_FakeCookieManager.new),
          ),
          webSessionControllerProvider.overrideWith(
            (ref) => WebSessionController(ref),
          ),
          webSessionVerifierProvider.overrideWithValue(
            WebSessionVerifier(Dio()),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(webSessionControllerProvider.notifier)
          .state = const WebSessionState(
        csrf: 'token',
        isLoggedIn: true,
        username: 'artist',
      );
      // The authoritative verdict chain (bare probe anonymous + real browser
      // anonymous) decided the web Cookie is dead.
      container.read(webSessionStatusProvider.notifier).state =
          const WebSessionStatus(state: WebSessionStatusState.anonymous);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: PersonalizedFeed())),
        ),
      );
      await tester.pumpAndSettle();

      // The recommendations tab must never render the generic rfy content an
      // anonymous session gets, and it must not even send the request.
      expect(rfyAdapter.calls, 0);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.textContaining('Cookie'), findsOneWidget);
    },
  );
}
