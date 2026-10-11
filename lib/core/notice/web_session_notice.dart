import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/web_session_status.dart';
import '../auth/personalized_session_status.dart';

/// Dismissals belong to the current session incident, across all routes.
/// Keep observing recovery even while no notice host is mounted.
final webSessionNoticeDismissalProvider =
    NotifierProvider<WebSessionNoticeDismissal, Set<String>>(
      WebSessionNoticeDismissal.new,
    );

final class WebSessionNoticeDismissal extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    var generation = ref.read(webSessionStatusProvider.notifier).generation;
    ref.listen(webSessionStatusProvider, (previous, next) {
      final current = ref.read(webSessionStatusProvider.notifier).generation;
      if (next.isHealthy &&
          (previous?.isHealthy != true || generation != current) &&
          state.isNotEmpty) {
        state = {
          if (generation == current &&
              state.contains('personalized-session-degraded'))
            'personalized-session-degraded',
        };
      }
      generation = current;
    });
    ref.listen(personalizedSessionStatusProvider, (previous, next) {
      if (previous?.needsRecovery == true && !next.needsRecovery) {
        state = {...state}..remove('personalized-session-degraded');
      }
    });
    return const <String>{};
  }

  void dismiss(String noticeId) => state = {...state, noticeId};
}
