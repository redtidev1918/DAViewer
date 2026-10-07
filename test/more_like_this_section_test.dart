import 'dart:async';

import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:daviewer/features/artwork/artwork_detail_providers.dart';
import 'package:daviewer/features/artwork/more_like_this.dart';
import 'package:daviewer/features/artwork/more_like_this_failure.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a website failure cannot be hidden by an empty official fallback', () {
    expect(
      () => mergeMoreLikeThisResult(
        official: const MoreLikeThisResult(artworks: <Artwork>[]),
        webArtworks: const <Artwork>[],
        websiteError: const FormatException('partial page'),
      ),
      throwsA(isA<MoreLikeThisFailure>()),
    );
  });

  test('two successful empty sources remain a normal empty result', () {
    final result = mergeMoreLikeThisResult(
      official: const MoreLikeThisResult(artworks: <Artwork>[]),
      webArtworks: const <Artwork>[],
      websiteError: null,
    );

    expect(result.artworks, isEmpty);
  });

  test('website artwork wins but official collections are kept', () {
    final official = MoreLikeThisResult(
      artworks: <Artwork>[_artwork('off', 'Official result')],
      featuredInCollections: <CollectionWithDeviations>[
        CollectionWithDeviations(
          collection: CollectionSummary(
            folderId: 111,
            name: 'Curated',
            owner: UserProfile(id: 'u', username: 'curator'),
          ),
          deviations: const <Artwork>[],
        ),
      ],
    );

    final result = mergeMoreLikeThisResult(
      official: official,
      webArtworks: <Artwork>[_artwork('web', 'Website result')],
      websiteError: null,
    );

    expect(result.artworks.single.id, 'web');
    expect(result.featuredInCollections, hasLength(1));
    expect(result.featuredInCollections.single.collection.name, 'Curated');
  });

  test('drops media-less items from the related grid', () {
    final result = mergeMoreLikeThisResult(
      official: MoreLikeThisResult(
        artworks: <Artwork>[
          _artwork('a', 'With media'),
          _artwork('b', 'Journal', withMedia: false),
        ],
      ),
      webArtworks: const <Artwork>[],
      websiteError: null,
    );

    expect(result.artworks.map((artwork) => artwork.id), <String>['a']);
  });

  test('keeps a duplicate collection only in featured', () {
    final collection = CollectionSummary(
      folderId: 1,
      name: 'Shared',
      owner: UserProfile(id: 'u', username: 'curator'),
    );
    final result = mergeMoreLikeThisResult(
      official: MoreLikeThisResult(
        artworks: const <Artwork>[],
        featuredInCollections: <CollectionWithDeviations>[
          CollectionWithDeviations(
            collection: collection,
            deviations: const <Artwork>[],
          ),
        ],
        suggestedCollections: <CollectionWithDeviations>[
          CollectionWithDeviations(
            collection: collection,
            deviations: const <Artwork>[],
          ),
        ],
      ),
      webArtworks: const <Artwork>[],
      websiteError: null,
    );

    expect(result.featuredInCollections, hasLength(1));
    expect(result.suggestedCollections, isEmpty);
  });

  testWidgets('an empty result stays user-facing and checks again', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: <Override>[
          moreLikeThisProvider('art-id').overrideWith((ref) async {
            attempts++;
            return const MoreLikeThisResult(artworks: <Artwork>[]);
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MoreLikeThisSection(artworkId: 'art-id'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('暂时没有找到'), findsOneWidget);
    expect(find.textContaining('网页'), findsNothing);
    expect(find.textContaining('备用来源'), findsNothing);
    expect(find.text('检查更新'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(find.text('重新加载'), findsNothing);

    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.textContaining('已检查最新推荐'), findsWidgets);
  });

  testWidgets('a transient failure retries once then explains the cause', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: <Override>[
          moreLikeThisProvider('art-id').overrideWith((ref) async {
            attempts++;
            throw DioException(
              requestOptions: RequestOptions(path: '/related'),
              type: DioExceptionType.connectionError,
            );
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MoreLikeThisSection(artworkId: 'art-id'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.textContaining('网络连接失败'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('refresh keeps current cards visible until new items arrive', (
    tester,
  ) async {
    var attempts = 0;
    final refreshed = Completer<MoreLikeThisResult>();
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: <Override>[
          moreLikeThisProvider('art-id').overrideWith((ref) async {
            attempts++;
            if (attempts == 1) {
              return MoreLikeThisResult(
                artworks: <Artwork>[_artwork('old', 'Current suggestion')],
              );
            }
            return refreshed.future;
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MoreLikeThisSection(artworkId: 'art-id'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('检查更新'));
    await tester.pump();

    expect(find.text('Current suggestion'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    refreshed.complete(
      MoreLikeThisResult(
        artworks: <Artwork>[_artwork('new', 'New suggestion')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('New suggestion'), findsOneWidget);
    expect(find.textContaining('已更新'), findsOneWidget);
  });
}

Artwork _artwork(String id, String title, {bool withMedia = true}) => Artwork(
  id: id,
  title: title,
  author: UserProfile(id: 'user-$id', username: 'artist'),
  pageUri: Uri.parse('https://www.deviantart.com/artist/art/work-$id'),
  media: withMedia
      ? <MediaAsset>[
          MediaAsset(
            id: '$id:preview',
            kind: MediaKind.image,
            role: MediaRole.preview,
            availability: MediaAvailability.available,
            uri: Uri.parse('https://images.example.test/$id.jpg'),
          ),
        ]
      : const <MediaAsset>[],
);
