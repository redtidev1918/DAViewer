import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/personalized_session_status.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/notice/web_session_notice.dart';

/// Labels suspected-generic recommendation content directly on the home
/// recommendations tab (P0-B, REG-022).
///
/// Recommendation capability is separate from website identity: while the web
/// session is healthy, a suspected-generic fallback batch is still displayed —
/// never cached as personalized — and this banner is the clear label attached
/// to exactly that content. It offers a retry and can be dismissed for the
/// current incident; it never presents itself as a login problem.
final class RecommendedDegradedBanner extends ConsumerWidget {
  const RecommendedDegradedBanner({required this.onRetry, super.key});

  /// Triggers an explicit refetch (pull-to-refresh semantics: always fetches).
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final degraded = ref.watch(
      personalizedSessionStatusProvider.select(
        (status) => status.needsRecovery,
      ),
    );
    final dismissed = ref
        .watch(webSessionNoticeDismissalProvider)
        .contains('personalized-session-degraded');
    if (!degraded || dismissed) return const SizedBox.shrink();
    final s = strings(ref.watch(appLanguageProvider));
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.label_outline,
              size: 18,
              color: scheme.onSecondaryContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.recommendedSessionDegraded,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSecondaryContainer),
              ),
            ),
            TextButton(onPressed: onRetry, child: Text(s.retry)),
            IconButton(
              tooltip: s.done,
              onPressed: () => ref
                  .read(webSessionNoticeDismissalProvider.notifier)
                  .dismiss('personalized-session-degraded'),
              icon: Icon(
                Icons.close,
                size: 16,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
