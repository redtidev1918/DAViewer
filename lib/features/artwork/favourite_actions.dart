import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/runtime/runtime_provider.dart';
import 'artwork_detail_providers.dart';
import 'artwork_store.dart';
import '../favourites/favourites_providers.dart';

typedef FavouriteMutation = Future<bool> Function(
  String artworkId,
  bool favourite,
);

final favouriteBusyProvider = StateProvider.family<bool, String>(
  (ref, id) => false,
);

/// Network boundary, separate from shared mutation state for all UI entry points.
final favouriteRequestProvider = Provider<FavouriteMutation>(
  (ref) => (id, favourite) async {
    final runtime = ref.read(runtimeProvider);
    final social = OfficialSocialRepository(runtime.transport!);
    final uuid = await ref.read(artworkUuidProvider(id).future);
    final result = favourite
        ? await social.favourite(uuid)
        : await social.unfavourite(uuid);
    return result.isFavourite;
  },
);

final favouriteActionsProvider = Provider<FavouriteMutation>(
  (ref) => (id, favourite) async {
    final busy = ref.read(favouriteBusyProvider(id).notifier);
    if (busy.state) throw StateError('Favourite update already in progress');
    final request = ref.read(favouriteRequestProvider);
    busy.state = true;
    try {
      final result = await request(id, favourite);
      if (ref.mounted) {
        ref.read(artworkStoreProvider.notifier).setFavourite(id, result);
        ref.invalidate(currentFavouritesProvider);
      }
      return result;
    } finally {
      if (ref.mounted) busy.state = false;
    }
  },
);

/// Favourites or unfavourites an artwork, resolving a numeric web id to its
/// OAuth UUID first. Updates the in-memory store so the detail screen reflects
/// the new state, and returns the new favourite flag.
Future<bool> setArtworkFavourite(
  WidgetRef ref,
  String artworkId,
  bool favourite,
) => ref.read(favouriteActionsProvider)(artworkId, favourite);
