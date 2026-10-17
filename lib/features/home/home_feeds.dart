import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:flutter/material.dart';

import '../../core/filtering/content_filter_provider.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/diagnostics/error_text.dart';
import '../../core/l10n/app_strings.dart';
import '../../shared/widgets/app_empty_state.dart';
import '../../shared/widgets/app_error_state.dart';
import '../../shared/widgets/app_refresh_indicator.dart';
import '../../shared/widgets/artwork_card.dart';
import '../../shared/widgets/scrollable_fill.dart';
import '../../shared/widgets/skeleton.dart';
import '../artwork/artwork_navigation.dart';
import 'home_providers.dart';

/// The official "daily deviations" feed (OAuth).
final class DailyFeed extends ConsumerStatefulWidget {
  const DailyFeed({super.key});

  @override
  ConsumerState<DailyFeed> createState() => _DailyFeedState();
}

final class _DailyFeedState extends ConsumerState<DailyFeed>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final auth = ref.watch(authControllerProvider);
    final s = strings(ref.watch(appLanguageProvider));
    if (!auth.oauthSignedIn) {
      return LoginPrompt(s: s, onLogin: () => context.push('/web-login'));
    }
    final daily = ref.watch(dailyDeviationsProvider);
    return daily.when(
      loading: () => const SkeletonGrid(),
      error: (error, stackTrace) => AppRefreshIndicator(
        onRefresh: () => ref.refresh(dailyDeviationsProvider.future),
        child: ScrollableFill(
          child: AppErrorState(
            message: friendlyErrorMessage(error),
            onRetry: () => ref.invalidate(dailyDeviationsProvider),
          ),
        ),
      ),
      data: (items) => AppRefreshIndicator(
        onRefresh: () => ref.refresh(dailyDeviationsProvider.future),
        child: ArtworkGrid(
          items: items,
          isLoading: false,
          error: null,
          emptyMessage: s.noDaily,
        ),
      ),
    );
  }
}

/// A centered sign-in call-to-action used by the OAuth feeds.
final class LoginPrompt extends StatelessWidget {
  const LoginPrompt({
    super.key,
    required this.s,
    required this.onLogin,
    this.message,
  });

  final AppStrings s;
  final VoidCallback onLogin;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.person_outline,
              size: 56,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message ?? s.loginFirst,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onLogin,
              icon: const Icon(Icons.login),
              label: Text(s.login),
            ),
          ],
        ),
      ),
    );
  }
}

/// A scrollable grid of artworks, handling empty/error/loading states.
final class ArtworkGrid extends ConsumerWidget {
  const ArtworkGrid({
    super.key,
    required this.items,
    required this.isLoading,
    required this.error,
    required this.emptyMessage,
  });

  final List<Artwork> items;
  final bool isLoading;
  final Object? error;
  final String emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = visibleArtworks(ref, this.items);
    if (error != null && items.isEmpty) {
      return ScrollableFill(
        child: AppErrorState(message: friendlyErrorMessage(error!)),
      );
    }
    if (items.isEmpty && isLoading) {
      return const SkeletonGrid();
    }
    if (items.isEmpty) {
      return ScrollableFill(child: AppEmptyState(message: emptyMessage));
    }

    return MasonryGridView.count(
      padding: const EdgeInsets.all(12),
      physics: const AlwaysScrollableScrollPhysics(),
      crossAxisCount: (MediaQuery.of(context).size.width / 200).round().clamp(
        2,
        4,
      ),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final artwork = items[index];
        return ArtworkCard(
          artwork: artwork,
          onTap: () => openArtworkFromList(
            context,
            ref,
            artworks: items,
            artwork: artwork,
          ),
        );
      },
    );
  }
}
