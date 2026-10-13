import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  Future<void>? readGate;
  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    InAppWebViewController? webViewController,
    @Deprecated('Use webViewController instead')
    InAppWebViewController? iosBelow11WebViewController,
  }) async {
    await readGate;
    return <Cookie>[
      Cookie(name: 'userinfo', value: 'artist'),
      Cookie(name: 'csrf', value: csrfCookie),
    ];
  }
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
      '@@publicSession': <String, Object?>{
        'isLoggedIn': true,
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

  test('suspected generic fallback is displayed with a degraded incident, never as confirmed personalized', () async {
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
    // P0-B (2026-10-13): the batch stays usable under the degraded label
    // instead of leaving an empty tab, but it is not a confirmed
    // personalized result and must not surface as a login problem.
    expect(container.read(personalizedFeedProvider).items, hasLength(1));
    expect(container.read(artworkStoreProvider)['12345'], isNotNull);
    expect(container.read(personalizedFeedProvider).error, isNull);

    // An explicit recovery supersedes the incident and retries the same feed.
    container
        .read(webSessionStatusProvider.notifier)
        .markHealthy(serverUsername: 'artist');
    expect(
      container.read(personalizedSessionStatusProvider).needsRecovery,
      isFalse,
    );
    rfy.nextCursor = null;
    // The user retry path is forceRefresh (pull-to-refresh/banner retry);
    // the idempotent refresh() would skip the still-valid session context.
    await container.read(personalizedFeedProvider.notifier).forceRefresh();
    expect(container.read(personalizedFeedProvider).items, hasLength(1));
    expect(
      container.read(personalizedSessionStatusProvider).phase,
      PersonalizedSessionPhase.usable,
    );
  });

  test(
    'account change while waiting on Cookie read sends no obsolete transport',
    () async {
      final gate = Completer<void>();
      final cookies = _FakeCookieManager()..readGate = gate.future;
      final rfy = _RfyAdapter();
      final container = feedContainer(
        rfy,
        _HomeProbeAdapter(),
        cookies: cookies,
      );
      final controller = container.read(personalizedFeedProvider.notifier);
      final pending = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      container
          .read(webSessionControllerProvider.notifier)
          .state = const WebSessionState(
        csrf: 'other-token',
        isLoggedIn: true,
        username: 'other-account',
      );
      gate.complete();
      await pending;
      expect(rfy.calls, 0);
      expect(container.read(artworkStoreProvider)['12345'], isNull);
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

  for (final verifiedRotation in [false, true]) {
    test(
      'RFY trace has complete metadata and one terminal outcome (verified rotation=$verifiedRotation)',
      () async {
        final logs = <String>[];
        final previousPrint = debugPrint;
        debugPrint = (message, {wrapWidth}) {
          if (message != null) logs.add(message);
        };
        addTearDown(() => debugPrint = previousPrint);
        final entered = Completer<void>();
        final gate = Completer<void>();
        final cookies = _FakeCookieManager();
        final rfy = _RfyAdapter()
          ..gate = gate.future
          ..onFetch = entered.complete;
        final container = feedContainer(
          rfy,
          _HomeProbeAdapter(),
          cookies: cookies,
        );
        final pending = container
            .read(personalizedFeedProvider.notifier)
            .refresh();
        await entered.future;
        cookies.csrfCookie = 'rotated';
        if (verifiedRotation) {
          container
              .read(webSessionStatusProvider.notifier)
              .markHealthy(serverUsername: 'artist');
        }
        gate.complete();
        await pending;
        final traces = logs
            .where((line) => line.contains('[home] rfy requestId='))
            .toList();
        final phases = traces
            .map((line) => RegExp(r'phase=(\w+)').firstMatch(line)!.group(1))
            .toList();
        expect(
          phases,
          containsAllInOrder([
            'created',
            'queued',
            'in_flight',
            'transport_succeeded',
            verifiedRotation ? 'accepted' : 'discarded',
            'completed',
          ]),
        );
        expect(
          phases.where((p) => ['accepted', 'discarded', 'failed'].contains(p)),
          hasLength(1),
        );
        for (final line in traces) {
          for (final key in [
            'recoveryId',
            'accountEpoch',
            'sessionGeneration',
            'credentialRevision',
            'triggerReason',
          ]) {
            expect(line, contains('$key='));
          }
        }
        expect(traces.any((line) => line.contains('transportId=')), isTrue);
        if (!verifiedRotation) {
          expect(
            traces.any(
              (line) => line.contains('discardReason=credentials_changed'),
            ),
            isTrue,
          );
        }
        expect(rfy.calls, 1);
      },
    );
  }

  test(
    'verification recovery automatically resumes a stopped initial feed',
    () async {
      final rfy = _RfyAdapter();
      final recovered = Completer<void>();
      rfy.onFetch = recovered.complete;
      final container = feedContainer(rfy, _HomeProbeAdapter());
      container
          .read(webSessionStatusProvider.notifier)
          .state = WebSessionStatus(
        state: WebSessionStatusState.unverified,
        cooldownUntil: DateTime.now().add(const Duration(minutes: 1)),
      );
      final feed = container.read(personalizedFeedProvider.notifier);
      await feed.refresh();
      expect(container.read(personalizedFeedProvider).items, isEmpty);
      expect(rfy.calls, 0);
      container
          .read(webSessionStatusProvider.notifier)
          .markHealthy(serverUsername: 'artist');
      await recovered.future;
      await feed.refresh();
      expect(container.read(personalizedFeedProvider).items, hasLength(1));
      expect(rfy.calls, 1);
      container
          .read(webSessionStatusProvider.notifier)
          .markHealthy(serverUsername: 'artist');
      await Future<void>.delayed(Duration.zero);
      expect(
        rfy.calls,
        1,
        reason: 'healthy updates must not reload a valid list',
      );
    },
  );

  testWidgets('explicit retry verifies despite automatic cooldown', (
    tester,
  ) async {
    final probe = _HomeProbeAdapter();
    final rfy = _RfyAdapter();
    final container = feedContainer(rfy, probe);
    container.read(webSessionReadyProvider.notifier).state = true;
    container.read(webSessionStatusProvider.notifier).state = WebSessionStatus(
      state: WebSessionStatusState.unverified,
      cooldownUntil: DateTime.now().add(const Duration(minutes: 1)),
    );
    await container.read(personalizedFeedProvider.notifier).refresh();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: PersonalizedFeed())),
      ),
    );
    await tester.pumpAndSettle();
    expect(probe.calls, 0);
    await tester.runAsync(() async {
      await tester.tap(find.byType(FilledButton).first);
      await container.read(webSessionStatusProvider.notifier).check();
      await container.read(personalizedFeedProvider.notifier).refresh();
    });
    await tester.pumpAndSettle();
    expect(probe.calls, 1);
    expect(rfy.calls, 1);
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

  test('verified same-account recovery adopts a successful in-flight response without second RFY', () async {
    final gate = Completer<void>();
    final entered = Completer<void>();
    final cookies = _FakeCookieManager();
    final rfy = _RfyAdapter()
      ..gate = gate.future
      ..onFetch = entered.complete;
    final container = feedContainer(rfy, _HomeProbeAdapter(), cookies: cookies);
    final feed = container.read(personalizedFeedProvider.notifier);
    final pending = feed.refresh();
    await entered.future;
    cookies.csrfCookie = 'verified-rotation';
    container
        .read(webSessionStatusProvider.notifier)
        .markHealthy(serverUsername: 'artist');
    final joined = feed.refresh();
    gate.complete();
    await Future.wait([pending, joined]);
    expect(container.read(personalizedFeedProvider).items, hasLength(1));
    expect(container.read(artworkStoreProvider)['12345'], isNotNull);
    expect(rfy.calls, 1);
  });

  test('account epoch changes invalidate away-and-back responses', () async {
    final gate = Completer<void>();
    final entered = Completer<void>();
    final rfy = _RfyAdapter()
      ..gate = gate.future
      ..onFetch = entered.complete;
    final container = feedContainer(rfy, _HomeProbeAdapter());
    final status = container.read(webSessionStatusProvider.notifier);
    final pending = container.read(personalizedFeedProvider.notifier).refresh();
    await entered.future;
    final before = status.accountEpoch;
    container.read(webSessionControllerProvider.notifier).state =
        const WebSessionState(isLoggedIn: false);
    expect(status.accountEpoch, greaterThan(before));
    gate.complete();
    await pending;
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
      final cacheDirectory = Directory.systemTemp.createTempSync(
        'daviewer-feed-cache-',
      );
      addTearDown(() {
        cacheDirectory.deleteSync(recursive: true);
      });
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
          feedCacheDirectoryProvider.overrideWithValue(cacheDirectory),
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
    'a missing cache directory never delays or blocks the first recommendation page',
    (tester) async {
      final rfyAdapter = _RfyAdapter();
      final probeAdapter = _HomeProbeAdapter();
      // No feedCacheDirectoryProvider override: the cache path is genuinely
      // unavailable, as on a platform without a support directory (and in
      // widget tests). The live page must still load, and the disposal below
      // fails the test if any timer outlives the widget tree.
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: <Override>[
          runtimeProvider.overrideWithValue(
            AppRuntime(
              clientId: 'test-client',
              oauth: null,
              transport: null,
              transfers: _sharedTransfers,
              dio: Dio()..httpClientAdapter = rfyAdapter,
            ),
          ),
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

      // Cache storage is a preview, never a prerequisite: one live fetch, and
      // the grid holds real recommendations rather than an endless skeleton.
      expect(rfyAdapter.calls, 1);
      expect(container.read(personalizedFeedProvider).items, isNotEmpty);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
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
