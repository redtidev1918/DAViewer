import 'package:dakit_flutter/dakit_flutter.dart';
import 'package:daviewer/core/auth/auth_controller.dart';
import 'package:daviewer/core/auth/auth_state.dart';
import 'package:daviewer/core/diagnostics/app_logger.dart';
import 'package:daviewer/core/runtime/app_runtime.dart';
import 'package:daviewer/core/runtime/runtime_provider.dart';
import 'package:daviewer/core/settings/app_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldRestoreOAuthSessionAfterEvidence', () {
    test('a recorded logout prevents token revival', () {
      expect(
        shouldRestoreOAuthSessionAfterEvidence(OAuthSessionEvidence.signedOut),
        isFalse,
      );
    });

    test('missing evidence keeps the legacy restore path', () {
      expect(
        shouldRestoreOAuthSessionAfterEvidence(OAuthSessionEvidence.unknown),
        isTrue,
      );
      expect(
        shouldRestoreOAuthSessionAfterEvidence(OAuthSessionEvidence.signedIn),
        isTrue,
      );
    });
  });

  test('retryLogin overrides a stale isLoggingIn transaction', () async {
    final runtime = AppRuntime(
      clientId: '',
      oauth: null,
      transport: null,
      transfers: BackgroundTransferManager(diagnostics: AppLogger.instance),
    );
    final container = ProviderContainer(
      overrides: <Override>[runtimeProvider.overrideWithValue(runtime)],
    );
    addTearDown(container.dispose);

    final auth = container.read(authControllerProvider.notifier);
    auth.state = const AuthState(
      status: AuthStatus.signedOut,
      isLoggingIn: true,
    );

    await auth.retryLogin();

    expect(auth.state.status, AuthStatus.signedOut);
    expect(auth.state.isLoggingIn, isFalse);
  });
}
