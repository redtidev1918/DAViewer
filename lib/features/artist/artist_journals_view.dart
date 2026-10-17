import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics/error_text.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/filtering/content_filter_provider.dart';
import '../../shared/widgets/app_error_state.dart';
import '../../shared/widgets/skeleton.dart';
import '../artwork/artwork_navigation.dart';
import 'artist_providers.dart';

/// The artist's journal posts (articles).
final class JournalsView extends ConsumerWidget {
  const JournalsView({required this.username, super.key});

  final String username;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journals = ref.watch(artistJournalsProvider(username));
    final s = strings(ref.watch(appLanguageProvider));
    return journals.when(
      loading: () => const SkeletonList(),
      error: (error, stackTrace) =>
          AppErrorState(message: friendlyErrorMessage(error)),
      data: (items) {
        items = visibleArtworks(ref, items);
        if (items.isEmpty) {
          return Center(child: Text(s.noJournals));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(8),
          itemCount: items.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final journal = items[index];
            return ListTile(
              leading: const Icon(Icons.article_outlined),
              title: Text(
                journal.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: journal.publishedAt == null
                  ? null
                  : Text(formatJournalDate(journal.publishedAt!)),
              onTap: () => openArtworkFromList(
                context,
                ref,
                artworks: items,
                artwork: journal,
              ),
            );
          },
        );
      },
    );
  }
}

/// Formats a journal's publish date as `YYYY-MM-DD`.
String formatJournalDate(DateTime time) {
  final local = time.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}
