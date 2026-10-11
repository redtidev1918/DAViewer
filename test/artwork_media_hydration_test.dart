import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:daviewer/core/auth/web_session_status.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:daviewer/features/artwork/artwork_access.dart';
import 'package:daviewer/features/artwork/artwork_detail_providers.dart';
import 'package:daviewer/features/artwork/artwork_store.dart';
import 'package:daviewer/features/artwork/artwork_access_controller.dart';
import 'package:daviewer/features/artwork/artwork_access_state.dart';
import 'package:daviewer/features/artwork/media_viewer.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:daviewer/shared/widgets/artwork_card.dart';

const _uuid = '97B067C2-0000-4000-8000-000000000001';
final _page = Uri.parse('https://www.deviantart.com/artist/art/work-123');
final _clear = Uri.parse('https://images.example.test/clear.jpg');

Map<Object?, Object?> _webPayload() => <Object?, Object?>{
  'deviation': <Object?, Object?>{
    'deviationId': 123,
    'url': '$_page',
    'title': 'Mature artwork',
    'author': <String, Object?>{'userId': 'artist', 'username': 'artist'},
    'isMature': true,
    'media': <String, Object?>{
      'baseUri': '$_clear',
      'prettyName': 'clear.jpg',
      'types': <Object?>[
        <String, Object?>{'t': 'fullview', 'w': 1000, 'h': 750, 'b': '$_clear'},
      ],
    },
    'extended': <String, Object?>{'deviationUuid': _uuid},
  },
};

Artwork _preview({
  String id = '123',
  bool locked = true,
  bool blurred = true,
}) => Artwork(
  id: id,
  title: 'Mature artwork',
  author: const UserProfile(id: 'artist', username: 'artist'),
  pageUri: _page,
  isMature: true,
  media: <MediaAsset>[
    MediaAsset(
      id: '$id:preview',
      kind: MediaKind.image,
      role: MediaRole.preview,
      availability: locked
          ? MediaAvailability.purchaseRequired
          : MediaAvailability.available,
      uri: blurred
          ? Uri.parse('https://images.example.test/v1/fit/blur_30/image.jpg')
          : _clear,
    ),
  ],
  downloadAvailability: locked
      ? MediaAvailability.purchaseRequired
      : MediaAvailability.unavailable,
  tags: const <String>['known-tag'],
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

final class _DetailAdapter implements HttpClientAdapter {
  _DetailAdapter({
    this.paid = false,
    this.status = 200,
    this.wrongWork = false,
    this.responseGate,
  });

  bool paid;
  int status;
  final bool wrongWork;
  final Future<void>? responseGate;
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
    expect(options.uri.path, endsWith('/deviation/$_uuid'));
    expect(options.queryParameters['mature_content'], isTrue);
    await responseGate;
    final body = <String, Object?>{
      'deviationid': _uuid,
      'title': 'Mature artwork',
      'url': wrongWork
          ? 'https://www.deviantart.com/artist/art/other-456'
          : '$_page',
      'author': <String, Object?>{'userid': 'artist', 'username': 'artist'},
      'is_mature': true,
      'is_downloadable': false,
      'content': <String, Object?>{
        'src': 'https://images.example.test/original.jpg',
        'width': 1600,
        'height': 1200,
      },
      'preview': <String, Object?>{
        'src': '$_clear',
        'width': 1000,
        'height': 750,
      },
      if (paid) 'premium_folder_data': <String, Object?>{'has_access': false},
    };
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => Directory.systemTemp.path,
      );
  final transfers = BackgroundTransferManager(diagnostics: AppLogger.instance);

  ProviderContainer containerFor(
    _DetailAdapter adapter, {
    Map<Object?, Object?>? webPayload,
  }) {
    final dio = Dio()..httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: <Override>[
        runtimeProvider.overrideWithValue(
          AppRuntime(
            clientId: 'test-client',
            oauth: null,
            transport: OfficialApiClient(session: _Tokens(), dio: dio),
            transfers: transfers,
          ),
        ),
        artworkUuidProvider('123').overrideWith((ref) async => _uuid),
        webSessionRestrictionCheckProvider.overrideWithValue(() async {}),
        webArtworkInitPayloadProvider('123')
            .overrideWith((ref) async => webPayload),
      ],
    );
    addTearDown(container.dispose);
    container.read(artworkStoreProvider.notifier).putAll(<Artwork>[_preview()]);
    return container;
  }

  test('mature is not a paid gate and blur alone only requests hydration', () {
    final clear = _preview(locked: false, blurred: false);
    expect(artworkViewLock(clear), isNull);
    expect(needsArtworkMediaHydration(clear), isFalse);
    final blurred = _preview(locked: false);
    expect(artworkViewLock(blurred), isNull);
    expect(needsArtworkMediaHydration(blurred), isTrue);
  });

  test(
    'related NSFW preview resolves to clear media through official detail',
    () async {
      final adapter = _DetailAdapter();
      final container = containerFor(adapter);
      final result = await hydrateRelatedArtworkMedia(
        <Artwork>[_preview()],
        hydrate: (artwork) =>
            container.read(artworkMediaHydrationProvider(artwork.id).future),
      );
      final resolved = result.single;
      expect(resolved.id, '123');
      expect(resolved.isMature, isTrue);
      expect(resolved.isDownloadable, isFalse);
      expect(artworkViewLock(resolved), isNull);
      expect(selectDisplayAsset(resolved.media)?.uri, _clear);
      expect(resolved.tags, <String>['known-tag']);
      // Opening the related item caches the original list again. It must not
      // resurrect the provisional paid gate or blurred CDN URL.
      container.read(artworkStoreProvider.notifier).putAll(<Artwork>[
        _preview(),
      ]);
      final detail = await container.read(artworkDetailProvider('123').future);
      expect(artworkViewLock(detail), isNull);
      expect(selectDisplayAsset(detail.media)?.uri, _clear);
      expect(adapter.requests, 1);
    },
  );

  test('opening a cached blurred detail also hydrates it', () async {
    final container = containerFor(_DetailAdapter());
    final detail = await container.read(artworkDetailProvider('123').future);
    expect(artworkViewLock(detail), isNull);
    expect(selectDisplayAsset(detail.media)?.uri, _clear);
  });

  testWidgets(
    'a stale list card updates image and lock together from the store',
    (tester) async {
      final container = containerFor(_DetailAdapter());
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 240,
                child: ArtworkCard(artwork: _preview()),
              ),
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      await tester.runAsync(
        () => container.read(artworkMediaHydrationProvider('123').future),
      );
      await tester.pump();
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(
        tester
            .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
            .imageUrl,
        '$_clear',
      );
    },
  );

  test(
    'late media from a previous session cannot update cache or phase',
    () async {
      final gate = Completer<void>();
      final adapter = _DetailAdapter(responseGate: gate.future);
      final container = containerFor(adapter);
      final pending = container.read(
        artworkMediaHydrationProvider('123').future,
      );
      while (adapter.requests == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      container.read(artworkStoreProvider.notifier).clearMediaResolutions();
      gate.complete();
      final detail = await pending;
      expect(isBlurredPreview(detail.media.single), isTrue);
      expect(
        container
            .read(artworkAccessControllerProvider.notifier)
            .forId('123')
            .phase,
        ArtworkAccessPhase.unresolved,
      );
      expect(
        container.read(artworkStoreProvider.notifier).hasResolvedMedia('123'),
        isFalse,
      );
    },
  );

  test(
    'OAuth failure can use complete identity-matched web main media',
    () async {
      final payload = _webPayload();
      final container = containerFor(
        _DetailAdapter(status: 404),
        webPayload: payload,
      );
      await container.read(webArtworkInitPayloadProvider('123').future);
      final detail = await container.read(artworkDetailProvider('123').future);
      expect(artworkViewLock(detail), isNull);
      expect(selectDisplayAsset(detail.media)?.uri, _clear);
      final evidence = container
          .read(artworkAccessControllerProvider.notifier)
          .forId('123')
          .mainEvidence!;
      expect(evidence.source, ArtworkAccessSource.webDetail);
      expect(evidence.grantsAccess, isTrue);
    },
  );

  test(
    'unknown web block reason cannot grant access after OAuth failure',
    () async {
      final payload = _webPayload();
      (payload['deviation'] as Map)['blockReasons'] = <String>[
        'unknown_policy',
      ];
      final container = containerFor(
        _DetailAdapter(status: 404),
        webPayload: payload,
      );
      await container.read(webArtworkInitPayloadProvider('123').future);
      final detail = await container.read(artworkDetailProvider('123').future);
      expect(isBlurredPreview(detail.media.single), isTrue);
      expect(
        container.read(artworkStoreProvider.notifier).hasResolvedMedia('123'),
        isFalse,
      );
      expect(
        container
            .read(artworkAccessControllerProvider.notifier)
            .forId('123')
            .phase,
        ArtworkAccessPhase.retryableFailure,
      );
    },
  );

  test('confirmed login retries a previously failed cached detail', () async {
    final adapter = _DetailAdapter(status: 403);
    final container = containerFor(adapter);
    final before = await container.read(artworkDetailProvider('123').future);
    expect(isBlurredPreview(before.media.single), isTrue);
    adapter.status = 200;
    container.read(artworkSessionRecoveryProvider)();
    final after = await container.read(artworkDetailProvider('123').future);
    expect(selectDisplayAsset(after.media)?.uri, _clear);
    expect(artworkViewLock(after), isNull);
    expect(adapter.requests, 2);
  });

  test(
    'confirmed login clears access results from the previous session',
    () async {
      final adapter = _DetailAdapter(paid: true);
      final container = containerFor(adapter);
      await container.read(artworkDetailProvider('123').future);
      adapter.paid = false;
      container.read(artworkSessionRecoveryProvider)();
      final after = await container.read(artworkDetailProvider('123').future);
      expect(artworkViewLock(after), isNull);
      expect(selectDisplayAsset(after.media)?.uri, _clear);
      expect(adapter.requests, 2);
    },
  );

  test(
    'a real purchase requirement remains locked after detail verification',
    () async {
      final container = containerFor(_DetailAdapter(paid: true));
      final detail = await container.read(artworkDetailProvider('123').future);
      expect(artworkViewLock(detail), MediaAvailability.purchaseRequired);
      expect(
        detail.media.first.availability,
        MediaAvailability.purchaseRequired,
      );
      expect(
        container.read(artworkStoreProvider.notifier).hasResolvedMedia('123'),
        isTrue,
      );
    },
  );

  test(
    'failed or mismatched detail cannot unlock or replace the preview',
    () async {
      for (final adapter in <_DetailAdapter>[
        _DetailAdapter(status: 403),
        _DetailAdapter(wrongWork: true),
      ]) {
        final container = containerFor(adapter);
        final detail = await container.read(
          artworkDetailProvider('123').future,
        );
        expect(artworkViewLock(detail), MediaAvailability.purchaseRequired);
        expect(isBlurredPreview(detail.media.single), isTrue);
        expect(
          container.read(artworkStoreProvider.notifier).hasResolvedMedia('123'),
          isFalse,
        );
      }
    },
  );

  test('hydration skips clear media, bounds concurrency, and keeps order on failure', () async {
    var active = 0;
    var peak = 0;
    final called = <String>[];
    final works = <Artwork>[
      _preview(id: 'clear', locked: false, blurred: false),
      for (var index = 0; index < 7; index++) _preview(id: '$index'),
    ];
    final result = await hydrateRelatedArtworkMedia(
      works,
      hydrate: (artwork) async {
        called.add(artwork.id);
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(Duration.zero);
        active--;
        if (artwork.id == '2') throw StateError('Unavailable');
        return artwork.copyWith(title: 'resolved');
      },
    );
    expect(called, isNot(contains('clear')));
    expect(peak, 3);
    expect(
      result.map((artwork) => artwork.id),
      works.map((artwork) => artwork.id),
    );
    expect(result[3], same(works[3]));
    expect(result[4].title, 'resolved');
  });
}
