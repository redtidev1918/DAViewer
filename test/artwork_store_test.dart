import 'package:dakit_core/dakit_core.dart';
import 'package:daviewer/features/artwork/artwork_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Artwork _artwork() => Artwork(
  id: '1',
  title: 'title',
  author: UserProfile(id: 'u', username: 'alice'),
  pageUri: Uri.parse('https://d.test/a'),
  media: const <MediaAsset>[],
  description: 'desc',
  publishedAt: DateTime(2026, 1, 1),
  isMature: true,
  isDownloadable: true,
  isFavourited: false,
  isMultiMedia: true,
  tags: const <String>['a', 'b'],
);

void main() {
  test('setFavourite flips the flag and preserves other fields', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final store = container.read(artworkStoreProvider.notifier);
    store.putAll(<Artwork>[_artwork()]);

    store.setFavourite('1', true);
    final updated = container.read(artworkStoreProvider)['1']!;
    expect(updated.isFavourited, isTrue);
    expect(updated.id, '1');
    expect(updated.title, 'title');
    expect(updated.author.username, 'alice');
    expect(updated.description, 'desc');
    expect(updated.isMature, isTrue);
    expect(updated.isDownloadable, isTrue);
    expect(updated.isMultiMedia, isTrue);
    expect(updated.tags, <String>['a', 'b']);

    store.setFavourite('1', false);
    expect(container.read(artworkStoreProvider)['1']!.isFavourited, isFalse);
  });

  test('setFavourite is a no-op for an unknown id', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(artworkStoreProvider.notifier).setFavourite('nope', true);
    expect(container.read(artworkStoreProvider), isEmpty);
  });

  test('sparse feed refresh preserves hydrated tags', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final store = container.read(artworkStoreProvider.notifier);
    store.putAll(<Artwork>[_artwork()]);

    store.putAll(<Artwork>[
      Artwork(
        id: '1',
        title: 'new title',
        author: UserProfile(id: 'u', username: 'alice'),
        pageUri: Uri.parse('https://d.test/a'),
        media: const <MediaAsset>[],
        isFavourited: true,
      ),
    ]);

    final updated = container.read(artworkStoreProvider)['1']!;
    expect(updated.title, 'new title');
    expect(updated.isFavourited, isTrue);
    expect(updated.tags, const <String>['a', 'b']);
    expect(store.hasResolvedTags('1'), isTrue);
  });

  test('confirmed empty tags are remembered without mutating artwork', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final store = container.read(artworkStoreProvider.notifier);
    final artwork = _artwork().copyWith(tags: const <String>[]);
    store.putAll(<Artwork>[artwork]);

    expect(store.hasResolvedTags('1'), isFalse);
    store.setTags('1', const <String>[]);

    expect(store.hasResolvedTags('1'), isTrue);
    expect(container.read(artworkStoreProvider)['1']!.tags, isEmpty);
  });

  test(
    'hydration status distinguishes unknown, resolved, and confirmed empty',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final store = container.read(artworkStoreProvider.notifier);

      expect(store.tagStatus('1'), HydrationStatus.unknown);

      store.putAll(<Artwork>[_artwork()]);
      expect(store.tagStatus('1'), HydrationStatus.resolved);

      store.putAll(<Artwork>[_artwork().copyWith(tags: const <String>[])]);
      store.setTags('1', const <String>[]);
      expect(store.tagStatus('1'), HydrationStatus.confirmedEmpty);
    },
  );

  test('mergeArtwork keeps hydrated tags and accepts richer payloads', () {
    final hydrated = _artwork();
    final sparse = _artwork().copyWith(tags: const <String>[], title: 'sparse');

    final preserved = mergeArtwork(cached: hydrated, incoming: sparse);
    expect(preserved.title, 'sparse');
    expect(preserved.tags, hydrated.tags);

    final richer = mergeArtwork(
      cached: sparse,
      incoming: hydrated.copyWith(tags: const <String>['a', 'b', 'c']),
    );
    expect(richer.tags, const <String>['a', 'b', 'c']);
  });
}
