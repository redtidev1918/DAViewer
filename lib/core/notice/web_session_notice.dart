import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/login_observation.dart';
import '../auth/personalized_session_status.dart';
import '../auth/web_session_status.dart';
import '../settings/app_preferences.dart';

/// Dismissals belong to the current session incident, across all routes.
/// Keep observing recovery even while no notice host is mounted.
final webSessionNoticeDismissalProvider =
    NotifierProvider<WebSessionNoticeDismissal, Set<String>>(
      WebSessionNoticeDismissal.new,
    );

/// The recommendation label is not a channel incident: it is attached to the
/// content it qualifies and keeps its own dismissal.
const String personalizedSessionDegradedNoticeId =
    'personalized-session-degraded';

/// Ids bind channel + account + incident, so a dismissal follows the account
/// that saw it and never suppresses the next incident on that channel.
String webSessionNoticeId(String account, {required bool locked}) =>
    'web-session:$account:${locked ? 'locked' : 'invalid'}';

String apiSessionNoticeId(String account) => 'api-session:$account:invalid';

final class WebSessionNoticeDismissal extends Notifier<Set<String>> {
  static const String _webPrefix = 'web-session:';
  static const String _apiPrefix = 'api-session:';

  /// `channel:account:` scopes whose incident is over in this launch. Only a
  /// record inside such a scope is dropped on restore: another account's
  /// recovery is not this account's recovery.
  final Set<String> _recovered = <String>{};
  bool _disposed = false;
  Future<void> _restored = Future<void>.value();

  /// The dismissal set as last merged or committed. Writes derive from this
  /// instead of `state`, which is unreadable after disposal.
  Set<String> _latest = const <String>{};

  /// Resolves once the persisted dismissals have been merged, so a restart
  /// does not re-show an incident the user already closed.
  Future<void> get restored => _restored;

  @override
  Set<String> build() {
    ref.onDispose(() => _disposed = true);
    // Committed before any listener, so a dismissal or a recovery can always
    // wait for the persisted records to be merged first.
    _restored = _restore();
    var generation = ref.read(webSessionStatusProvider.notifier).generation;
    ref.listen(webSessionStatusProvider, (previous, next) {
      final current = ref.read(webSessionStatusProvider.notifier).generation;
      if (next.isHealthy &&
          (previous?.isHealthy != true || generation != current)) {
        // Only the account that recovered opens its next incident: clearing
        // the whole channel would delete another account's dismissal.
        _forgetAccount(
          _webPrefix,
          ref.read(loginObservationProvider(LoginChannel.web)).owner,
        );
      }
      generation = current;
    });
    ref.listen(personalizedSessionStatusProvider, (previous, next) {
      if (previous?.needsRecovery == true && !next.needsRecovery) {
        _remove(personalizedSessionDegradedNoticeId);
      }
    });
    ref.listen(loginObservationProvider(LoginChannel.api), (previous, next) {
      if (next.result != LoginCheckResult.authenticated) return;
      // The API channel keeps its own record: a healthy web session must not
      // clear an API reminder the user has not seen yet.
      _forgetAccount(_apiPrefix, next.owner);
    });
    return const <String>{};
  }

  void dismiss(String noticeId) => _commit({...state, noticeId});

  Future<void> _restore() async {
    final persisted = await AppPreferences.loadDismissedSessionNotices();
    // Merged before the disposed guard: a queued write awaiting this restore
    // must still persist the records this launch did not recover.
    final merged = {
      ...persisted.where((id) => !_recovered.any(id.startsWith)),
      ..._latest,
    };
    _latest = merged;
    if (_disposed || merged.isEmpty) return;
    state = merged;
  }

  /// A recovery ends the incident of ONE account on one channel. The filtered
  /// set is written even when memory had nothing to drop: the finished
  /// incident's record may still be on disk, and leaving it there would let a
  /// later launch swallow the next incident on that channel.
  void _forgetAccount(String channelPrefix, String account) {
    final scope = '$channelPrefix$account:';
    _recovered.add(scope);
    _commit(state.where((id) => !id.startsWith(scope)).toSet());
  }

  void _remove(String noticeId) {
    if (!state.contains(noticeId)) return;
    _commit({...state}..remove(noticeId));
  }

  void _commit(Set<String> next) {
    state = next;
    _latest = next;
    // Every write waits for the restore and is derived from the merged set, so
    // a dismissal made during startup cannot drop a record another launch
    // stored, and a recovery cannot leave a finished record behind.
    unawaited(_restored.then((_) => _persist()));
  }

  Future<void> _persist() =>
      AppPreferences.saveDismissedSessionNotices(_latest);
}
