import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diagnostics/app_logger.dart';
import 'web_session_diagnostics.dart';
import 'web_session_status.dart';

enum PersonalizedSessionPhase { unknown, usable, degraded }

/// Recommendation access is separate from website identity. An HTTP 200 or a
/// rendered username cannot dismiss a recommendation-specific recovery notice.
final class PersonalizedSessionStatus {
  const PersonalizedSessionStatus({
    this.phase = PersonalizedSessionPhase.unknown,
    this.cookieFingerprint,
  });

  final PersonalizedSessionPhase phase;
  final String? cookieFingerprint;
  bool get needsRecovery => phase == PersonalizedSessionPhase.degraded;
}

final personalizedSessionStatusProvider =
    NotifierProvider<PersonalizedSessionController, PersonalizedSessionStatus>(
      PersonalizedSessionController.new,
    );

final class PersonalizedSessionController
    extends Notifier<PersonalizedSessionStatus> {
  @override
  PersonalizedSessionStatus build() {
    var generation = ref.read(webSessionStatusProvider.notifier).generation;
    ref.listen(webSessionStatusProvider, (_, next) {
      final current = ref.read(webSessionStatusProvider.notifier).generation;
      // Explicit login/lockout changes the generation. Periodic identity
      // confirmations do not clear a recommendation degradation incident.
      if (generation != current) {
        generation = current;
        state = const PersonalizedSessionStatus();
      }
    });
    return const PersonalizedSessionStatus();
  }

  bool cookieChanged(String header) {
    final previous = state.cookieFingerprint;
    return previous != null && previous != cookieHeaderFingerprint(header);
  }

  void reset() => state = const PersonalizedSessionStatus();

  void observe({
    required String cookieHeader,
    required bool degraded,
    required int generation,
  }) {
    if (generation != ref.read(webSessionStatusProvider.notifier).generation) {
      return;
    }
    final next = degraded
        ? PersonalizedSessionPhase.degraded
        : PersonalizedSessionPhase.usable;
    AppLogger.instance.info(
      'auth',
      'personalized session: ${state.phase.name} -> ${next.name} '
          'source=rfy-response generation=$generation '
          'cookieFingerprint=${cookieHeaderFingerprint(cookieHeader)}',
    );
    state = PersonalizedSessionStatus(
      phase: next,
      cookieFingerprint: cookieHeaderFingerprint(cookieHeader),
    );
  }
}

/// REG-009 recorded group 2 in generic fallback responses. Treat it as a
/// degradation signal, not a universal definition of DeviantArt's algorithm or
/// evidence of logout. Unknown/malformed cursors supply no such evidence.
bool rfyCursorSignalsGenericFallback(String? cursor) {
  if (cursor == null || cursor.isEmpty || cursor.length > 8192) return false;
  try {
    final value = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(cursor))),
    );
    return value is Map && value['vespa_content_group'] == 2;
  } on Object {
    return false;
  }
}
