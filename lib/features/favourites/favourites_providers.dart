import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/data/data_access.dart';
import '../../core/feed/artwork_feed_controller.dart';
import '../../core/runtime/runtime_provider.dart';

final currentFavouritesProvider =
    StateNotifierProvider.autoDispose<ArtworkFeedController, ArtworkFeedState>((
      ref,
    ) {
      // Rebuild the favourites feed whenever the signed-in account changes.
      ref.watch(
        authControllerProvider.select(
          (auth) => (auth.status, auth.account?.id),
        ),
      );
      final controller = ArtworkFeedController((request) {
        final account = ref.read(authControllerProvider).account;
        if (account == null) {
          throw Exception('Login required to view favourites.');
        }
        final runtime = ref.read(runtimeProvider);
        return dataAccessFor(runtime).favourites(account.username, request);
      });
      return controller;
    });
