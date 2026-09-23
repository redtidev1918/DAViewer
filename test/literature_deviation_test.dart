import 'dart:convert';
import 'dart:typed_data';

import 'package:dakit_flutter/dakit_flutter.dart' hide WebSession;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:daviewer/core/auth/web_session_controller.dart';
import 'package:daviewer/core/auth/web_session_status.dart'
    show webSessionProvider;
import 'package:daviewer/core/data/web_session.dart';
import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:daviewer/features/artwork/artwork_detail_providers.dart';
import 'package:daviewer/features/artwork/artwork_store.dart';
import 'package:daviewer/shared/widgets/artwork_card.dart';
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
    Cookie(name: 'userinfo', value: 'caisiel'),
    Cookie(name: 'csrf', value: 'token'),
  ];
}

/// Serves the web `dadeviation/init` endpoint with a literature text body
/// (captured shape of deviation 1381144810: type=literature + tiptap markup).
final class _InitAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.queryParameters['type'], 'journal');
    final body = jsonEncode(<String, Object?>{
      'deviation': <String, Object?>{
        'deviationId': 1381144810,
        'type': 'literature',
        'isJournal': false,
        'title': 'Through Closed Eyes',
        'url': 'https://www.deviantart.com/caisiel/art/Through-Closed-Eyes-1381144810',
        'author': <String, Object?>{'username': 'caisiel'},
        'textContent': <String, Object?>{
          'html': <String, Object?>{
            'type': 'tiptap',
            'markup': jsonEncode(<String, Object?>{
              'type': 'doc',
              'content': <Object?>[
                <String, Object?>{
                  'type': 'paragraph',
                  'content': <Object?>[
                    <String, Object?>{
                      'type': 'text',
                      'text': 'A small representation of drawing in a dream.',
                    },
                  ],
                },
              ],
            }),
          },
        },
      },
    });
    return ResponseBody.fromString(
      body,
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }
}

/// FileDownloaderBackend exposes a single-listener stream, so this file shares
/// one transfer manager instance.
final _sharedTransfers = BackgroundTransferManager(
  diagnostics: AppLogger.instance,
);

Artwork _literatureArtwork() => Artwork(
  id: '1381144810',
  title: 'Through Closed Eyes',
  author: const UserProfile(id: 'caisiel-id', username: 'caisiel'),
  pageUri: Uri.parse(
    'https://www.deviantart.com/caisiel/art/Through-Closed-Eyes-1381144810',
  ),
  media: const <MediaAsset>[],
);

ProviderContainer _container(Dio dio) {
  final container = ProviderContainer(
    overrides: <Override>[
      runtimeProvider.overrideWithValue(
        AppRuntime(
          clientId: 'test-client',
          oauth: null,
          transport: null,
          transfers: _sharedTransfers,
          dio: dio,
        ),
      ),
      webSessionControllerProvider.overrideWith(
        (ref) => WebSessionController(ref),
      ),
      webSessionProvider.overrideWithValue(WebSession(_FakeCookieManager.new)),
    ],
  );
  container
      .read(webSessionControllerProvider.notifier)
      .state = const WebSessionState(
    csrf: 'token',
    isLoggedIn: true,
    username: 'caisiel',
  );
  return container;
}

void main() {
  testWidgets('a literature card renders a text card, not a broken image', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: ArtworkCard(artwork: _literatureArtwork()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.article_outlined), findsOneWidget);
    // The card body and the title row below both render the title.\n    expect(find.text('Through Closed Eyes'), findsNWidgets(2));
    expect(find.byType(CachedNetworkImage), findsNothing);
  });

  test(
    'journalHtmlProvider fetches the body for media-less literature',
    () async {
      final container = _container(Dio()..httpClientAdapter = _InitAdapter());
      addTearDown(container.dispose);
      container.read(artworkStoreProvider.notifier).putAll(<Artwork>[
        _literatureArtwork(),
      ]);

      final html = await container.read(
        journalHtmlProvider('1381144810').future,
      );

      expect(html, isNotNull);
      expect(html!, contains('drawing in a dream'));
    },
  );

  test('journalHtmlProvider skips image works without a request', () async {
    final adapter = _InitAdapter();
    final container = _container(Dio()..httpClientAdapter = adapter);
    addTearDown(container.dispose);
    container.read(artworkStoreProvider.notifier).putAll(<Artwork>[
      Artwork(
        id: '1381144811',
        title: 'An image work',
        author: const UserProfile(id: 'caisiel-id', username: 'caisiel'),
        pageUri: Uri.parse(
          'https://www.deviantart.com/caisiel/art/An-image-work-1381144811',
        ),
        media: const <MediaAsset>[
          MediaAsset(
            id: 'p',
            kind: MediaKind.image,
            role: MediaRole.preview,
            availability: MediaAvailability.available,
          ),
        ],
      ),
    ]);

    final html = await container.read(journalHtmlProvider('1381144811').future);

    expect(html, isNull);
  });
}
