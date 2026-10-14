import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dakit_flutter/dakit_flutter.dart' hide WebSession;
import 'package:daviewer/core/auth/web_session_controller.dart';
import 'package:daviewer/core/auth/session_state.dart';
import 'package:daviewer/core/data/web_session.dart';
import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:daviewer/features/artwork/artwork_detail_providers.dart';
import 'package:daviewer/features/artwork/artwork_store.dart';
import 'package:daviewer/features/artwork/more_like_this_failure.dart';
import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = '1204523558';
const _uuid = 'A47E9A8B-7A7F-3C7C-5367-DBC635E21816';

final class _Cookies extends Fake implements CookieManager {
  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    InAppWebViewController? webViewController,
    @Deprecated('Use webViewController instead')
    InAppWebViewController? iosBelow11WebViewController,
  }) async => [Cookie(name: 'userinfo', value: 'test-user')];
}

final class _Tokens implements AuthTokenProvider {
  @override
  Future<AuthTokens> validTokens({bool forceRefresh = false}) async =>
      AuthTokens(
        accessToken: 'test-token',
        tokenType: 'Bearer',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
}

final class _RecoveryAdapter implements HttpClientAdapter {
  bool offline = true;
  int initCalls = 0;
  int officialCalls = 0;
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final init = options.uri.path.endsWith('/dadeviation/init');
    final official = options.uri.path.endsWith('/browse/morelikethis/preview');
    if (init) initCalls++;
    if (official) officialCalls++;
    // Keep the optional website-related source unavailable to exercise the
    // numeric UUID -> official More Like This fallback after recovery.
    if (offline || (!init && !official)) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Connection refused',
        error: const SocketException('Connection refused'),
      );
    }
    if (init) {
      expect(options.queryParameters['deviationid'], _id);
      // Real 2026-10-14 capture; provenance alongside the unchanged fixture.
      return ResponseBody.fromString(
        File('test/fixtures/artwork_description/web_init_tiptap.json')
            .readAsStringSync(),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    expect(options.queryParameters['seed'], _uuid);
    // Schema-derived fixture, NOT a live authenticated response. Independently
    // fetched 2026-10-15 from the embedded OpenAPI document at
    // https://deviantart.readme.io/reference/browse_morelikethis_preview
    // Required root fields: seed, author, more_from_artist, more_from_da;
    // deviation: deviationid, printid, is_deleted; user: userid, username,
    // usericon, type. Optional preview uses src/width/height.
    final author = {
      'userid': 'artist',
      'username': 'artist',
      'usericon': 'https://example.test/avatar.jpg',
      'type': 'regular',
    };
    return ResponseBody.fromString(
      jsonEncode({
        'seed': _uuid,
        'author': author,
        'more_from_artist': [],
        'more_from_da': [
          {
            'deviationid': 'B47E9A8B-7A7F-3C7C-5367-DBC635E21816',
            'printid': null,
            'is_deleted': false,
            'title': 'Related work',
            'url': 'https://www.deviantart.com/artist/art/related-2',
            'author': author,
            'preview': {
              'src': 'https://example.test/related.jpg',
              'width': 100,
              'height': 100,
            },
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'numeric description and More Like This recover through one shared init',
    () async {
      final adapter = _RecoveryAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          runtimeProvider.overrideWithValue(
            AppRuntime(
              clientId: 'test',
              oauth: null,
              transport: OfficialApiClient(session: _Tokens(), dio: dio),
              transfers: BackgroundTransferManager(
                diagnostics: AppLogger.instance,
              ),
              dio: dio,
            ),
          ),
          webSessionProvider.overrideWithValue(WebSession(_Cookies.new)),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(webSessionControllerProvider.notifier)
          .state = const WebSessionState(
        csrf: 'test-csrf',
        isLoggedIn: true,
        username: 'artist',
      );
      container.read(artworkStoreProvider.notifier).putAll([
        Artwork(
          id: _id,
          title: 'Cached work',
          description: 'Cached excerpt',
          author: const UserProfile(id: 'artist', username: 'artist'),
          pageUri: Uri.parse('https://www.deviantart.com/artist/art/work-$_id'),
          media: const [],
        ),
      ]);
      container.listen(artworkDescriptionResolutionProvider(_id), (_, _) {});
      container.listen(moreLikeThisProvider(_id), (_, _) {});
      final failure = container
          .read(moreLikeThisProvider(_id).future)
          .then<Object?>((_) => null)
          .onError<Object>((error, _) => error);
      final offlineDescription = await container.read(
        artworkDescriptionResolutionProvider(_id).future,
      );
      expect(offlineDescription.text, 'Cached excerpt');
      expect(offlineDescription.isExcerpt, isTrue);
      expect(await failure, isA<MoreLikeThisFailure>());
      expect(adapter.initCalls, 1);
      expect(adapter.officialCalls, 0);
      expect(container.read(webSessionControllerProvider).isLoggedIn, isTrue);

      adapter.offline = false;
      // Existing recovery entry point used by the app, no new retry framework.
      container.read(artworkSessionRecoveryProvider)();
      final relatedFuture = container.read(moreLikeThisProvider(_id).future);
      final description = await container.read(
        artworkDescriptionResolutionProvider(_id).future,
      );
      expect(description.source, 'web_init_tiptap');
      expect(description.isExcerpt, isFalse);
      expect(description.failureCategory, isNull);
      expect(
        description.text,
        contains('A commission drawn by @ExampleArtist'),
      );
      expect((await relatedFuture).artworks, hasLength(1));
      expect(adapter.initCalls, 2);
      expect(adapter.officialCalls, 1);
    },
  );
}
