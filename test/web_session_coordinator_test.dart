import 'dart:async';
import 'dart:typed_data';

import 'package:dakit_flutter/dakit_flutter.dart' hide WebSession;
import 'package:daviewer/core/auth/web_session_controller.dart';
import 'package:daviewer/core/auth/web_session_coordinator.dart';
import 'package:daviewer/core/auth/web_session_status.dart';
import 'package:daviewer/core/auth/web_session_verifier.dart';
import 'package:daviewer/core/data/web_session.dart';
import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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

/// Answers every request with one canned status, so a coordinator signal can be
/// produced without a network stack.
final class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.statusCode, {this.body = '{}'});

  final int statusCode;
  final String body;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    statusCode,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>['application/json'],
    },
  );
}

/// Counts home-page fetches, so a test can prove the verdict chain never ran.
final class _CountingHtmlAdapter implements HttpClientAdapter {
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
      '<html></html>',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['text/html'],
      },
    );
  }
}

final class _VerifyRecorder {
  _VerifyRecorder({this.error});

  final List<(bool forced, String source)> calls =
      <(bool forced, String source)>[];
  final Object? error;

  int countOf(String source) => calls.where((call) => call.$2 == source).length;

  Future<void> call(bool forced, String source) async {
    calls.add((forced, source));
    final failure = error;
    if (failure != null) throw failure;
  }
}

({WebSessionCoordinator coordinator, Dio dio, _VerifyRecorder recorder})
_coordinator({
  int statusCode = 200,
  String body = '{}',
  bool shouldVerify = true,
  Duration interval = const Duration(minutes: 1),
}) {
  final dio = Dio()..httpClientAdapter = _StatusAdapter(statusCode, body: body);
  final recorder = _VerifyRecorder();
  final coordinator = WebSessionCoordinator(
    dio: dio,
    shouldVerify: () => shouldVerify,
    verify: recorder.call,
    interval: interval,
  );
  return (coordinator: coordinator, dio: dio, recorder: recorder);
}

const String _apiUrl = 'https://www.deviantart.com/_puppy/dadeviation/init';

/// Swallows the status error the interceptor is expected to observe.
Future<void> _request(Dio dio, [String url = _apiUrl]) async {
  try {
    await dio.get<Object?>(url);
  } on DioException {
    // Expected for the 4xx cases under test.
  }
}

Response<Object?> _response({
  String url = _apiUrl,
  int statusCode = 200,
  Object? data,
  List<RedirectRecord> redirects = const <RedirectRecord>[],
}) => Response<Object?>(
  requestOptions: RequestOptions(path: url),
  statusCode: statusCode,
  data: data,
  redirects: redirects,
);

RedirectRecord _redirectTo(String location) =>
    RedirectRecord(302, 'GET', Uri.parse(location));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('webSessionResponseSignal', () {
    test('reports an HTTP rejection from a web content endpoint', () {
      expect(
        webSessionResponseSignal(_response(statusCode: 401)),
        'web-http-401',
      );
      expect(
        webSessionResponseSignal(_response(statusCode: 403)),
        'web-http-403',
      );
    });

    test('reports a mature_loggedout block reason nested in the payload', () {
      final nested = _response(
        data: <String, Object?>{
          'data': <String, Object?>{
            'deviation': <String, Object?>{
              'blockReasons': <Object?>['mature_loggedout'],
            },
          },
        },
      );
      expect(webSessionResponseSignal(nested), 'web-mature-loggedout');

      final snakeCase = _response(
        data: <String, Object?>{
          'block_reasons': <Object?>['mature_loggedout'],
        },
      );
      expect(webSessionResponseSignal(snakeCase), 'web-mature-loggedout');
    });

    test('reports a redirect that lands on the login page', () {
      final redirected = _response(
        redirects: <RedirectRecord>[
          _redirectTo('https://www.deviantart.com/users/login'),
        ],
      );
      expect(webSessionResponseSignal(redirected), 'web-login-redirect');

      // A direct login-page request is the same evidence, with no redirect
      // record: the Cookie no longer reaches the page that needs it.
      expect(
        webSessionResponseSignal(
          _response(url: 'https://www.deviantart.com/users/login'),
        ),
        'web-login-redirect',
      );
    });

    test('a rejection on a /users page is still session evidence', () {
      expect(
        webSessionResponseSignal(
          _response(
            url: 'https://www.deviantart.com/users/some-artist',
            statusCode: 403,
          ),
        ),
        'web-http-403',
      );
    });

    test('ignores traffic that must never feed an authentication signal', () {
      // CDN and image hosts answer 403 for restricted media; that is a content
      // restriction, not evidence about the session.
      expect(
        webSessionResponseSignal(
          _response(url: 'https://images-wixmp.test/art.png', statusCode: 403),
        ),
        isNull,
      );
      // The verifier probes the home page itself; feeding its answer back would
      // make the verification chain observe its own echo.
      expect(
        webSessionResponseSignal(
          _response(url: 'https://www.deviantart.com/', statusCode: 401),
        ),
        isNull,
      );
      expect(
        webSessionResponseSignal(
          _response(
            url: 'https://www.deviantart.com/oauth2/authorize',
            statusCode: 401,
          ),
        ),
        isNull,
      );
      // A redirect that stays on a third-party host is not a login redirect.
      expect(
        webSessionResponseSignal(
          _response(
            redirects: <RedirectRecord>[
              _redirectTo('https://images-wixmp.test/art.png'),
            ],
          ),
        ),
        isNull,
      );
    });

    test('stops descending into pathological payloads', () {
      Object? payload = <Object?>['mature_loggedout'];
      for (var depth = 0; depth < 10; depth += 1) {
        payload = <Object?>[payload];
      }
      expect(webSessionResponseSignal(_response(data: payload)), isNull);
    });
  });

  group('WebSessionCoordinator triggers', () {
    test('verifies on a successful response that denies the session', () async {
      final harness = _coordinator(
        body: '{"blockReasons":["mature_loggedout"]}',
      );
      addTearDown(harness.coordinator.dispose);

      final response = await harness.dio.get<Object?>(_apiUrl);

      // The interceptor must not alter what the caller receives.
      expect(response.statusCode, 200);
      expect(harness.recorder.calls, <(bool, String)>[
        (true, 'web-mature-loggedout'),
      ]);
    });

    test('verifies on a failed request that rejects the session', () async {
      final harness = _coordinator(statusCode: 403);
      addTearDown(harness.coordinator.dispose);

      await _request(harness.dio);

      expect(harness.recorder.calls, <(bool, String)>[(true, 'web-http-403')]);
    });

    test('stays silent when the session must not be verified', () async {
      final harness = _coordinator(statusCode: 403, shouldVerify: false);
      addTearDown(harness.coordinator.dispose);

      await _request(harness.dio);

      expect(harness.recorder.calls, isEmpty);
    });

    test('verifies silently while the app is active', () async {
      final harness = _coordinator(interval: const Duration(milliseconds: 20));
      addTearDown(harness.coordinator.dispose);

      await Future<void>.delayed(const Duration(milliseconds: 90));

      expect(harness.recorder.countOf('periodic'), greaterThanOrEqualTo(1));
      expect(harness.recorder.calls.every((call) => call.$1), isFalse);
    });

    test('pause stops the timer and resume verifies immediately', () async {
      final harness = _coordinator(interval: const Duration(milliseconds: 20));
      addTearDown(harness.coordinator.dispose);

      harness.coordinator.pause();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(harness.recorder.calls, isEmpty);

      harness.coordinator.resume();
      await Future<void>.delayed(Duration.zero);
      expect(harness.recorder.countOf('app-resume'), 1);
      expect(
        harness.recorder.calls
            .singleWhere((call) => call.$2 == 'app-resume')
            .$1,
        isTrue,
        reason: 'resuming must bypass the cached healthy verdict',
      );

      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(harness.recorder.countOf('periodic'), greaterThanOrEqualTo(1));
    });

    test('dispose detaches the interceptor and stops verifying', () async {
      final harness = _coordinator(statusCode: 403);
      final attached = harness.dio.interceptors.length;

      harness.coordinator.dispose();

      expect(harness.dio.interceptors.length, attached - 1);
      await _request(harness.dio);
      expect(harness.recorder.calls, isEmpty);
    });

    test('a failing verification never escapes the trigger', () async {
      final dio = Dio()..httpClientAdapter = _StatusAdapter(403);
      final recorder = _VerifyRecorder(error: StateError('verifier exploded'));
      final coordinator = WebSessionCoordinator(
        dio: dio,
        shouldVerify: () => true,
        verify: recorder.call,
      );
      addTearDown(coordinator.dispose);

      await _request(dio);

      expect(recorder.calls, hasLength(1));
    });
  });

  group('webSessionCoordinatorProvider', () {
    final transfers = BackgroundTransferManager(
      diagnostics: AppLogger.instance,
    );

    ProviderContainer containerFor(Dio dio, List<Override> extra) {
      final runtime = AppRuntime(
        clientId: 'test-client',
        oauth: null,
        transport: null,
        transfers: transfers,
        dio: dio,
      );
      return ProviderContainer(
        retry: (_, _) => null,
        overrides: <Override>[
          runtimeProvider.overrideWithValue(runtime),
          webSessionProvider.overrideWithValue(
            WebSession(() => _FakeCookieManager(const <Cookie>[])),
          ),
          webSessionControllerProvider.overrideWith(
            (ref) => WebSessionController(ref),
          ),
          ...extra,
        ],
      );
    }

    test('attaches to the shared Dio and detaches when disposed', () {
      final dio = Dio();
      final before = dio.interceptors.length;
      final container = containerFor(dio, const <Override>[]);

      container.read(webSessionCoordinatorProvider);
      expect(dio.interceptors.length, before + 1);

      container.dispose();
      expect(dio.interceptors.length, before);
    });

    test('a signed-out session never starts the verdict chain', () async {
      final dio = Dio()..httpClientAdapter = _StatusAdapter(403);
      final verifierAdapter = _CountingHtmlAdapter();
      final container = containerFor(dio, <Override>[
        webSessionVerifierProvider.overrideWithValue(
          WebSessionVerifier(Dio()..httpClientAdapter = verifierAdapter),
        ),
      ]);
      addTearDown(container.dispose);

      container.read(webSessionCoordinatorProvider);
      await _request(dio);

      expect(verifierAdapter.calls, 0);
      expect(
        container.read(webSessionStatusProvider).state,
        WebSessionStatusState.unknown,
      );
    });
  });
}
