import 'dart:convert';
import 'dart:io';

import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:daviewer/features/artwork/artwork_description.dart';
import 'package:daviewer/features/artwork/artwork_detail_providers.dart';
import 'package:daviewer/features/artwork/artwork_detail_sections.dart';
import 'package:daviewer/features/artwork/artwork_store.dart';
import 'package:daviewer/core/l10n/app_strings.dart';
import 'package:daviewer/features/artwork/rich_html.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

// Fixtures are independently captured live `/_puppy/dadeviation/init`
// responses (2026-10-14); provenance and the official OpenAPI metadata
// contract are documented in test/fixtures/artwork_description/README.md.
Map<Object?, Object?> _loadFixture(String name) => Map<Object?, Object?>.from(
  jsonDecode(File('test/fixtures/artwork_description/$name').readAsStringSync())
      as Map,
);

const _uuid = 'A47E9A8B-7A7F-3C7C-5367-DBC635E21816';

Artwork _cachedArtwork({String? description, String id = _uuid}) => Artwork(
  id: id,
  title: 'Cached work',
  author: const UserProfile(id: 'artist', username: 'artist'),
  pageUri: Uri.parse('https://www.deviantart.com/artist/art/work-1'),
  description: description,
  media: <MediaAsset>[
    MediaAsset(
      id: '$_uuid:preview',
      kind: MediaKind.image,
      role: MediaRole.preview,
      availability: MediaAvailability.available,
      uri: Uri.parse('https://images.example.test/preview.jpg'),
    ),
  ],
);

final class _Tokens implements AuthTokenProvider {
  @override
  Future<AuthTokens> validTokens({bool forceRefresh = false}) async =>
      AuthTokens(
        accessToken: 'test-token',
        tokenType: 'Bearer',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
}

/// Serves `deviation/metadata` rows shaped after the official OpenAPI
/// v1.20240701 schema (required `metadata[].deviationid`/`description`).
final class _MetadataAdapter implements HttpClientAdapter {
  _MetadataAdapter({this.failFirstN = 0});

  int failFirstN;
  int requests = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    expect(options.uri.path, endsWith('/deviation/metadata'));
    expect(options.queryParameters['deviationids[]'], contains(_uuid));
    expect(options.queryParameters['mature_content'], isTrue);
    if (requests <= failFirstN) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'connection error',
      );
    }
    return ResponseBody.fromString(
      jsonEncode(<String, Object?>{
        'metadata': <Object?>[
          <String, Object?>{
            'deviationid': _uuid,
            'description': 'Made for <a href="https://www.deviantart.com/">a challenge</a>.',
          },
        ],
      }),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }
}

/// FileDownloaderBackend exposes a single-subscription `updates` stream
/// (documented in background_downloader's FileDownloader.updates), so every
/// test in this file must share one transfer manager, exactly as the other
/// runtime-backed suites do.
final _sharedTransfers = BackgroundTransferManager(
  diagnostics: AppLogger.instance,
);

ProviderContainer _container({
  required HttpClientAdapter adapter,
  Map<Object?, Object?>? webPayload,
  String webPayloadId = '1204523558',
  Artwork? cached,
}) {
  final dio = Dio()..httpClientAdapter = adapter;
  final container = ProviderContainer(
    overrides: <Override>[
      runtimeProvider.overrideWithValue(
        AppRuntime(
          clientId: 'test-client',
          oauth: null,
          transport: OfficialApiClient(session: _Tokens(), dio: dio),
          transfers: _sharedTransfers,
        ),
      ),
      webArtworkInitPayloadProvider(webPayloadId)
          .overrideWith((ref) async => webPayload),
    ],
  );
  addTearDown(container.dispose);
  if (cached != null) {
    container.read(artworkStoreProvider.notifier).putAll(<Artwork>[cached]);
  }
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('web init parsing from captured fixtures', () {
    test('writer markup yields full plain text', () {
      final result = ArtworkDescriptionRepository.parseWeb(
        _loadFixture('web_init_writer.json'),
      );
      expect(result.source, 'web_init_writer');
      expect(result.text, 'Some practice i did when i was on Twitch.');
      expect(result.html, 'Some practice i did when i was on Twitch.');
      expect(result.isExcerpt, isFalse);
      expect(result.hasContent, isTrue);
    });

    test('tiptap markup keeps mentions, paragraphs and links', () {
      final result = ArtworkDescriptionRepository.parseWeb(
        _loadFixture('web_init_tiptap.json'),
      );
      expect(result.source, 'web_init_tiptap');
      expect(
        result.html,
        contains(
          '<a href="https://www.deviantart.com/exampleartist">'
          '@ExampleArtist</a>',
        ),
      );
      expect(result.html, contains('<p>'));
      expect(result.text, contains('A commission drawn by @ExampleArtist'));
      expect(result.text, contains("Here’s another pretty image"));
      expect(result.isExcerpt, isFalse);
    });

    test('missing description markup is a payload error', () {
      expect(
        () => ArtworkDescriptionRepository.parseWeb(<Object?, Object?>{
          'deviation': <Object?, Object?>{
            'deviationId': 1,
            'extended': <String, Object?>{},
          },
        }),
        throwsFormatException,
      );
    });
  });

  group('official metadata parsing', () {
    test('matched row provides the author description', () {
      final result = ArtworkDescriptionRepository.parseMetadata(
        <String, Object?>{
          'metadata': <Object?>[
            <String, Object?>{'deviationid': 'other-uuid'},
            <String, Object?>{
              'deviationid': _uuid,
              'description': 'Author note <b>bold</b>',
            },
          ],
        },
        _uuid.toLowerCase(),
      );
      expect(result.source, 'official_metadata');
      expect(result.html, 'Author note <b>bold</b>');
      expect(result.text, contains('Author note'));
      expect(result.text, contains('bold'));
    });

    test('missing identity or description is a payload error', () {
      expect(
        () => ArtworkDescriptionRepository.parseMetadata(<String, Object?>{
          'metadata': <Object?>[],
        }, _uuid),
        throwsFormatException,
      );
      expect(
        () => ArtworkDescriptionRepository.parseMetadata(<String, Object?>{
          'metadata': <Object?>[
            <String, Object?>{'deviationid': _uuid},
          ],
        }, _uuid),
        throwsFormatException,
      );
    });
  });

  group('description resolution providers', () {
    test('numeric id resolves through the web init payload once', () async {
      final container = _container(
        adapter: _MetadataAdapter(),
        webPayload: _loadFixture('web_init_tiptap.json'),
        cached: _cachedArtwork(description: 'short excerpt'),
      );
      final text = await container.read(
        artworkDescriptionProvider('1204523558').future,
      );
      final html = await container.read(
        artworkDescriptionHtmlProvider('1204523558').future,
      );
      expect(text, contains('A commission drawn by @ExampleArtist'));
      expect(html, contains('exampleartist'));
      // Both consumers share one resolution: the full description wins over
      // the cached excerpt.
      expect(text, isNot('short excerpt'));
    });

    test(
      'uuid resolves the author description from official metadata',
      () async {
        final adapter = _MetadataAdapter();
        final container = _container(
          adapter: adapter,
          cached: _cachedArtwork(),
        );
        // Both consumers are subscribed before either future is awaited, which
        // is how the detail screen reads them. The resolution provider is
        // autoDispose, so awaiting one future to completion before subscribing
        // the other would dispose it and force a second request.
        final resolutionFuture = container.read(
          artworkDescriptionResolutionProvider(_uuid).future,
        );
        final textFuture = container.read(
          artworkDescriptionProvider(_uuid).future,
        );
        final resolution = await resolutionFuture;
        final text = await textFuture;
        expect(resolution.source, 'official_metadata');
        expect(resolution.html, contains('a challenge'));
        expect(text, contains('Made for a challenge'));
        // A single request serves both the text and the html consumer.
        expect(adapter.requests, 1);
      },
    );

    test('metadata failure falls back to the labelled feed excerpt', () async {
      final adapter = _MetadataAdapter(failFirstN: 1);
      final container = _container(
        adapter: adapter,
        cached: _cachedArtwork(description: 'Fallback excerpt text'),
      );
      final resolution = await container.read(
        artworkDescriptionResolutionProvider(_uuid).future,
      );
      expect(resolution.source, 'feed_excerpt');
      expect(resolution.text, 'Fallback excerpt text');
      expect(resolution.isExcerpt, isTrue);
      expect(resolution.failureCategory, 'request_failed');
      // A later retry recovers the full description from the same provider.
      container.invalidate(artworkDescriptionResolutionProvider(_uuid));
      final retried = await container.read(
        artworkDescriptionResolutionProvider(_uuid).future,
      );
      expect(retried.source, 'official_metadata');
      expect(retried.isExcerpt, isFalse);
      expect(adapter.requests, 2);
    });

    test('missing web payload falls back with an invalid-payload category', () async {
      const numericId = '1204523558';
      final container = _container(
        adapter: _MetadataAdapter(),
        webPayload: null,
        // The excerpt fallback reads the cached artwork under the same id the
        // provider is asked for, so the numeric web id must be the cached key.
        cached: _cachedArtwork(description: 'excerpt only', id: numericId),
      );
      final resolution = await container.read(
        artworkDescriptionResolutionProvider(numericId).future,
      );
      expect(resolution.source, 'feed_excerpt');
      expect(resolution.isExcerpt, isTrue);
      expect(resolution.failureCategory, 'invalid_payload');
      expect(resolution.text, 'excerpt only');
    });
  });

  group('store merge keeps known descriptions', () {
    test('incoming empty description cannot erase the cached one', () {
      final merged = mergeArtwork(
        cached: _cachedArtwork(description: 'kept description'),
        incoming: _cachedArtwork(description: null),
      );
      expect(merged.description, 'kept description');
    });
  });

  group('ArtworkDescriptionSection rendering', () {
    Future<void> pumpSection(
      WidgetTester tester, {
      bool isJournal = false,
      String? journalHtml,
      String? descriptionHtml,
      String? description,
      bool isLoading = false,
      bool hasError = false,
      bool isExcerpt = false,
      VoidCallback? onRetry,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: <Widget>[
                ArtworkDescriptionSection(
                  isJournal: isJournal,
                  s: AppStrings.en,
                  onOpenLink: (_) {},
                  journalHtml: journalHtml,
                  descriptionHtml: descriptionHtml,
                  description: description,
                  isLoading: isLoading,
                  hasError: hasError,
                  isExcerpt: isExcerpt,
                  onRetry: onRetry,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('rich description shows the title and rendered html', (
      tester,
    ) async {
      final parsed = ArtworkDescriptionRepository.parseWeb(
        _loadFixture('web_init_tiptap.json'),
      );
      await pumpSection(tester, descriptionHtml: parsed.html);
      expect(find.text('Description'), findsOneWidget);
      expect(find.byType(RichHtml), findsOneWidget);
      expect(
        find.textContaining('A commission drawn by', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('plain fallback keeps the excerpt label and a retry', (
      tester,
    ) async {
      var retries = 0;
      await pumpSection(
        tester,
        description: 'Fallback excerpt text',
        isExcerpt: true,
        hasError: true,
        onRetry: () => retries++,
      );
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.textContaining('Fallback excerpt text'), findsOneWidget);
      expect(find.textContaining('Excerpt'), findsOneWidget);
      expect(find.textContaining('Could not load'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(retries, 1);
    });

    testWidgets('loading shows progress instead of an empty description', (
      tester,
    ) async {
      await pumpSection(tester, isLoading: true);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Description'), findsNothing);
    });

    testWidgets('journal body is labelled as text, not as description', (
      tester,
    ) async {
      await pumpSection(
        tester,
        isJournal: true,
        journalHtml: '<p>Journal body</p>',
      );
      expect(find.text('Text'), findsOneWidget);
      expect(find.text('Description'), findsNothing);
      expect(find.byType(RichHtml), findsOneWidget);
    });

    testWidgets('empty resolved description hides the section content', (
      tester,
    ) async {
      await pumpSection(tester);
      expect(find.byType(RichHtml), findsNothing);
      expect(find.text('Description'), findsNothing);
    });
  });
}
