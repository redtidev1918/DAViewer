import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dakit_flutter/dakit_flutter.dart' hide WebSession;
import 'package:daviewer/core/auth/web_session_controller.dart';
import 'package:daviewer/core/auth/web_session_refresher.dart'
    hide webSessionProbeProvider;
import 'package:daviewer/core/auth/web_session_status.dart';
import 'package:daviewer/core/data/web_session.dart';
import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:daviewer/features/home/home_providers.dart';
import 'package:daviewer/features/home/home_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeCookieManager extends Fake implements CookieManager {
  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    InAppWebViewController? webViewController,
    @Deprecated('Use webViewController instead')
    InAppWebViewController? iosBelow11WebViewController,
  }) async => <Cookie>[
    Cookie(name: 'userinfo', value: 'artist'),
    Cookie(name: 'csrf', value: 'token'),
  ];
}

/// Serves rfy: the first page always succeeds; pagination either fails once
/// (with a successful retry) or fails permanently, depending on the mode.
final class _RfyPaginationAdapter implements HttpClientAdapter {
  _RfyPaginationAdapter({required this.failPaginationAlways});

  final bool failPaginationAlways;
  int pagination403s = 0;
  int paginationSuccesses = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!options.uri.path.endsWith('/rfy/deviations')) {
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
    final cursor = options.queryParameters['cursor'] as String?;
    if (cursor != null && (failPaginationAlways || pagination403s == 0)) {
      pagination403s += 1;
      return ResponseBody.fromString(
        'forbidden',
        403,
        headers: const {
          Headers.contentTypeHeader: <String>['text/plain'],
        },
      );
    }
    if (cursor != null) paginationSuccesses += 1;
    final offset = cursor == null ? 0 : 24;
    return _rfyPage(offset);
  }
}

ResponseBody _rfyPage(int offset) => ResponseBody.fromString(
  jsonEncode(<String, Object?>{
    'deviations': <Object?>[
      <String, Object?>{
        'deviationId': 1000 + offset,
        'url': 'https://www.deviantart.com/artist/art/title-$offset',
        'title': 'Art $offset',
        'author': <String, Object?>{'username': 'artist'},
        'media': <String, Object?>{
          'baseUri': 'https://images.example.test/art-$offset',
          'prettyName': 'art',
          'types': <Object?>[
            <String, Object?>{'t': 'image', 'w': 600, 'h': 400},
          ],
        },
        'isDownloadable': true,
      },
    ],
    if (offset == 0)
      'nextCursor': 'eyJvZmZzZXQiOjI0fQ'
    else
      'nextCursor': 'eyJvZmZzZXQiOjQ4fQ',
  }),
  200,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>['application/json'],
  },
);

/// FileDownloaderBackend exposes a single-listener stream, so every test in
/// this file must share one transfer manager.
final _sharedTransfers = BackgroundTransferManager(
  diagnostics: AppLogger.instance,
);

ProviderContainer _container({
  required _RfyPaginationAdapter adapter,
  required List<WebSessionProbeResult> Function() probeResults,
}) {
  final runtime = AppRuntime(
    clientId: 'test-client',
    oauth: null,
    transport: null,
    transfers: _sharedTransfers,
    dio: Dio()..httpClientAdapter = adapter,
  );
  var probeCall = 0;
  final container = ProviderContainer(
    overrides: <Override>[
      runtimeProvider.overrideWithValue(runtime),
      webSessionReadyProvider.overrideWith((ref) => true),
      webSessionProvider.overrideWithValue(WebSession(_FakeCookieManager.new)),
      webSessionControllerProvider.overrideWith(
        (ref) => WebSessionController(ref),
      ),
      webSessionProbeProvider.overrideWithValue(() async {
        final results = probeResults();
        return results[probeCall.clamp(0, results.length - 1)];
      }),
    ],
  );
  container
      .read(webSessionControllerProvider.notifier)
      .state = const WebSessionState(
    csrf: 'token',
    isLoggedIn: true,
    username: 'artist',
  );
  // The verdict chain confirmed the session healthy before any feed activity.
  container
      .read(webSessionStatusProvider.notifier)
      .state = const WebSessionStatus(
    state: WebSessionStatusState.healthy,
    serverUsername: 'artist',
  );
  return container;
}

void main() {
  testWidgets(
    'a pagination 403 plus an unavailable probe refresh never damages auth',
    (tester) async {
      final adapter = _RfyPaginationAdapter(failPaginationAlways: false);
      var probeCalls = 0;
      final container = _container(
        adapter: adapter,
        probeResults: () {
          probeCalls += 1;
          // Headless probe hit a challenge/network failure: no verdict.
          return const [WebSessionProbeResult.unavailable(csrf: 'fresh')];
        },
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: PersonalizedFeed())),
        ),
      );
      await tester.pumpAndSettle();
      final initialItems = container
          .read(personalizedFeedProvider)
          .items
          .length;
      expect(initialItems, 1);
      expect(probeCalls, 0);

      // Sliding to the bottom triggers a paginated rfy request that the WAF
      // answers with 403 once; the context refresh also cannot answer.
      unawaited(container.read(personalizedFeedProvider.notifier).loadMore());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(adapter.pagination403s, 1);
      expect(adapter.paginationSuccesses, 1);
      expect(probeCalls, 1);
      final feed = container.read(personalizedFeedProvider);
      expect(feed.error, isNull);
      expect(feed.items.length, greaterThan(initialItems));
      // Authentication is untouched: pagination cannot mutate the verdict.
      expect(
        container.read(webSessionStatusProvider).state,
        WebSessionStatusState.healthy,
      );
      final identity = container.read(webSessionControllerProvider);
      expect(identity.isLoggedIn, isTrue);
      expect(identity.username, 'artist');
    },
  );

  testWidgets(
    'a persistent pagination failure is a feed error, not a login prompt',
    (tester) async {
      final adapter = _RfyPaginationAdapter(failPaginationAlways: true);
      final container = _container(
        adapter: adapter,
        probeResults: () => const [WebSessionProbeResult.unavailable()],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: PersonalizedFeed())),
        ),
      );
      await tester.pumpAndSettle();

      unawaited(container.read(personalizedFeedProvider.notifier).loadMore());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      final feed = container.read(personalizedFeedProvider);
      expect(feed.error, isNotNull);
      final code = (feed.error! as DAKitException).code;
      // A failed rfy request must NOT surface the web-login recovery state.
      expect(code, isNot('web.session.unavailable'));
      expect(
        container.read(webSessionStatusProvider).state,
        WebSessionStatusState.healthy,
      );
      final identity = container.read(webSessionControllerProvider);
      expect(identity.isLoggedIn, isTrue);
      expect(identity.username, 'artist');
    },
  );
}
