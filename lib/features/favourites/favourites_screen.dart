import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../core/l10n/app_strings.dart';
import '../../shared/widgets/artwork_feed_grid.dart';
import '../../shared/widgets/settings_action.dart';
import 'favourites_providers.dart';

final class FavouritesScreen extends ConsumerWidget {
  const FavouritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final s = strings(ref.watch(appLanguageProvider));
    if (auth.status != AuthStatus.signedIn) {
      return Scaffold(
        appBar: AppBar(
          title: Text(s.favourites),
          actions: const <Widget>[SettingsAction()],
        ),
        body: Center(
          child: FilledButton(
            onPressed: () => context.push('/web-login'),
            child: Text(s.login),
          ),
        ),
      );
    }

    final favourites = ref.watch(currentFavouritesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.favourites),
        actions: const <Widget>[SettingsAction()],
      ),
      body: ArtworkFeedGrid(
        feed: favourites,
        emptyMessage: s.noFavourites,
        emptyActionLabel: s.discover,
        emptyOnAction: () => context.push('/search'),
        onRefresh: () => ref.read(currentFavouritesProvider.notifier).refresh(),
        onLoadMore: () =>
            ref.read(currentFavouritesProvider.notifier).loadMore(),
        onRetryLoadMore: () =>
            ref.read(currentFavouritesProvider.notifier).retryLoadMore(),
      ),
    );
  }
}
