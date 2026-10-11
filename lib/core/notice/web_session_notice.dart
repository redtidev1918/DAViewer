import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/web_session_status.dart';

/// Dismissals belong to the current session incident, across all routes.
/// Keep observing recovery even while no notice host is mounted.
final webSessionNoticeDismissalProvider =
    NotifierProvider<WebSessionNoticeDismissal, Set<String>>(
      WebSessionNoticeDismissal.new,
    );

final class WebSessionNoticeDismissal extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.listen(webSessionStatusProvider, (previous, next) {
      if (next.isHealthy && state.isNotEmpty) state = const <String>{};
    });
    return const <String>{};
  }

  void dismiss(String noticeId) => state = {...state, noticeId};
}
