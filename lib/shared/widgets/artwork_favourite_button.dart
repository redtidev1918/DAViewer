import 'package:dakit_core/dakit_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/diagnostics/error_text.dart';
import '../../core/l10n/app_strings.dart';
import '../../features/artwork/artwork_store.dart';
import '../../features/artwork/favourite_actions.dart';
import 'app_feedback.dart';

/// One-tap action with shared pending state and server-confirmed feedback.
final class ArtworkFavouriteButton extends ConsumerWidget {
  const ArtworkFavouriteButton({
    required this.artwork,
    this.showLabel = false,
    super.key,
  });
  final Artwork artwork;
  final bool showLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current =
        ref.watch(artworkStoreProvider.select((items) => items[artwork.id])) ??
        artwork;
    final busy = ref.watch(favouriteBusyProvider(artwork.id));
    final s = strings(ref.watch(appLanguageProvider));
    final mutate = ref.read(favouriteActionsProvider);
    final scheme = Theme.of(context).colorScheme;
    final foreground = current.isFavourited
        ? scheme.primary
        : scheme.onSurfaceVariant;
    final icon = busy
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: foreground,
            ),
          )
        : Icon(
            current.isFavourited ? Icons.favorite : Icons.favorite_border,
            size: 20,
            color: foreground,
          );
    Future<void> toggle() async {
      // Sparse cards may be rendered before a feed has seeded the shared store.
      if (ref.read(artworkStoreProvider)[artwork.id] == null) {
        ref.read(artworkStoreProvider.notifier).putAll([current]);
      }
      try {
        final favourited = await mutate(artwork.id, !current.isFavourited);
        if (!context.mounted) return;
        showFeedback(
          context,
          favourited ? s.favouritedToast : s.unfavouritedToast,
          source: 'favourite-toggle',
        );
      } on Object catch (error) {
        if (!context.mounted) return;
        final needsLogin =
            error is DAKitException &&
            error.kind == DAKitFailureKind.authentication;
        showFeedback(
          context,
          needsLogin ? s.loginFirst : friendlyErrorMessage(error),
          source: 'favourite-toggle',
          severity: AppNoticeSeverity.error,
          action: needsLogin
              ? SnackBarAction(
                  label: s.login,
                  onPressed: () => context.push('/web-login'),
                )
              : null,
        );
      }
    }

    return Semantics(
      selected: current.isFavourited,
      child: Tooltip(
        message: current.isFavourited ? s.unfavourite : s.favourite,
        child: showLabel
            ? TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: foreground,
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: Theme.of(context).textTheme.labelMedium,
                ),
                onPressed: busy ? null : toggle,
                icon: icon,
                label: Text(
                  current.isFavourited ? s.favouritedToast : s.favourite,
                ),
              )
            : IconButton(
                style: IconButton.styleFrom(
                  foregroundColor: foreground,
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.all(12),
                ),
                onPressed: busy ? null : toggle,
                icon: icon,
              ),
      ),
    );
  }
}
