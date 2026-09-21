import 'package:daviewer/core/auth/web_session_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WebSessionStatus', () {
    test('only healthy is usable by the personalized feed', () {
      const healthy = WebSessionStatus(
        state: WebSessionStatusState.healthy,
        serverUsername: 'artist',
      );
      const stale = WebSessionStatus(state: WebSessionStatusState.stale);
      const locked = WebSessionStatus(state: WebSessionStatusState.locked);

      expect(healthy.isHealthy, isTrue);
      expect(healthy.needsLogin, isFalse);
      expect(stale.isHealthy, isFalse);
      expect(stale.needsLogin, isTrue);
      expect(locked.isLocked, isTrue);
      expect(locked.needsLogin, isTrue);
    });

    test('cooldown blocks a repeat check', () {
      final status = WebSessionStatus(
        state: WebSessionStatusState.unavailable,
        cooldownUntil: DateTime.now().add(const Duration(minutes: 1)),
      );
      expect(status.inCooldown, isTrue);
    });
  });
}
