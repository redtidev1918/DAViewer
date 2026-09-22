import 'dart:convert';
import 'dart:typed_data';

import 'package:dakit_flutter/dakit_flutter.dart' hide WebSession;
import 'package:daviewer/core/auth/web_session_controller.dart';
import 'package:daviewer/core/auth/web_session_status.dart';
import 'package:daviewer/core/auth/web_session_verifier.dart';
import 'package:daviewer/core/data/web_session.dart';
import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:daviewer/features/home/home_screen.dart';
import 'package:daviewer/shared/widgets/artwork_feed_grid.dart';
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

/// Serves the rfy endpoint and counts first-page requests by cursor.
final class _RfyAdapter implements HttpClientAdapter {
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
      final cursor = options.queryParameters['cursor'] as String?;
      cursors.add(cursor ?? 'initial');
      return _json(<String, Object?>{
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
        'user': <String, Object?>{'username': 'artist'},
      },
    });
    return ResponseBody.fromString(
      'window.__INITIAL_STATE__ = JSON.parse("$escaped");',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/html'],
      },
    );
  }
}

ResponseBody _json(Map<String, Object?> body) => ResponseBody.fromString(
  jsonEncode(body),
  200,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>['application/json'],
  },
);

void main() {
  testWidgets(
    'pull-to-refresh re-fetches rfy without a home-page verifier probe',
    (tester) async {
      final rfyAdapter = _RfyAdapter();
      final probeAdapter = _HomeProbeAdapter();
      final runtime = AppRuntime(
        clientId: 'test-client',
        oauth: null,
        transport: null,
        transfers: BackgroundTransferManager(diagnostics: AppLogger.instance),
        dio: Dio()..httpClientAdapter = rfyAdapter,
      );
      final container = ProviderContainer(
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

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: PersonalizedFeed())),
        ),
      );
      await tester.pumpAndSettle();

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
}
