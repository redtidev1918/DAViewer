import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/web_session_controller.dart';
import '../../core/auth/web_session_status.dart';

final class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

final class _SplashScreenState extends ConsumerState<SplashScreen> {
  static const Duration _startupTimeout = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // A startup restore that hangs (e.g. after an update while Keychain,
      // secure storage or the WebView proxy bridge is slow) must never leave
      // the splash screen black forever. Once the bounded budget expires the
      // router moves on; background restore can still complete later.
      try {
        await ref
            .read(authControllerProvider.notifier)
            .initialize()
            .timeout(_startupTimeout);
      } on Object {
        // Continue to Home; authRedirect treats an unknown-but-ready state
        // as signed-out-facing instead of trapping the app on splash.
      }
      try {
        // Restore the persisted web session (Cookie/CSRF state) so the
        // personalized feed is available without signing in again.
        await ref
            .read(webSessionControllerProvider.notifier)
            .initialize()
            .timeout(_startupTimeout);
      } on Object {
        // Best effort; the web-session notice will ask for login.
      }
      if (mounted) {
        ref.read(webSessionReadyProvider.notifier).state = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
