import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/history/visit_history_store.dart';
import '../../core/l10n/app_strings.dart';
import '../../shared/widgets/app_empty_state.dart';
import '../../shared/widgets/app_refresh_indicator.dart';
import '../../shared/widgets/relative_time_text.dart';
import '../../shared/widgets/skeleton.dart';
import 'history_providers.dart';

/// Locally stored artwork history. Tapping an item reopens its detail route.
final class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = strings(ref.watch(appLanguageProvider));
    final history = ref.watch(visitHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.history),
        actions: <Widget>[
          if ((history.valueOrNull ?? const <ArtworkVisit>[]).isNotEmpty)
            IconButton(
              tooltip: s.clearHistory,
              onPressed: () async {
                await VisitHistoryStore.clear();
                ref.invalidate(visitHistoryProvider);
              },
              icon: const Icon(Icons.clear_all),
            ),
        ],
      ),
      body: history.when(
        loading: () => const SkeletonList(),
        error: (_, _) => AppRefreshIndicator(
          onRefresh: () => ref.refresh(visitHistoryProvider.future),
          child: AppEmptyState(
            message: s.noHistory,
            icon: Icons.history,
            actionLabel: s.refresh,
            onAction: () => ref.invalidate(visitHistoryProvider),
          ),
        ),
        data: (visits) {
          if (visits.isEmpty) {
            return AppRefreshIndicator(
              onRefresh: () => ref.refresh(visitHistoryProvider.future),
              child: AppEmptyState(message: s.noHistory, icon: Icons.history),
            );
          }
          return AppRefreshIndicator(
            onRefresh: () => ref.refresh(visitHistoryProvider.future),
            child: ListView.separated(
              itemCount: visits.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final visit = visits[index];
                return ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: visit.thumbnail != null
                          ? CachedNetworkImage(
                              imageUrl: visit.thumbnail.toString(),
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) =>
                                  const Icon(Icons.art_track_outlined),
                            )
                          : const Icon(Icons.art_track_outlined),
                    ),
                  ),
                  title: Text(
                    visit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Row(
                    children: <Widget>[
                      if (visit.username.isNotEmpty) ...[
                        Text('@${visit.username}'),
                        const SizedBox(width: 8),
                      ],
                      RelativeTimeText(
                        time: visit.visitedAt,
                        format: s.relativeTime,
                      ),
                    ],
                  ),
                  onTap: () => context.push(
                    '/artwork/${visit.id}'
                    '${visit.username.isEmpty ? '' : '?username=${Uri.encodeComponent(visit.username)}'}',
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
