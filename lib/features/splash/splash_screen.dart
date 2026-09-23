import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/web_session_controller.dart';
import '../../core/auth/web_session_status.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/network/proxy_controller.dart';
import '../../core/runtime/runtime_provider.dart';

final class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

final class _SplashScreenState extends ConsumerState<SplashScreen> {
  static const Duration _startupTimeout = Duration(seconds: 12);

  ProxyController? _proxyController;
  String? _connectivityStatus;
  int _connectivityEpoch = 0;

  @override
  void initState() {
    super.initState();
    _proxyController = ref.read(runtimeProvider).proxyController;
    _proxyController?.addListener(_onProxyChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void dispose() {
    _proxyController?.removeListener(_onProxyChanged);
    super.dispose();
  }

  void _onProxyChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_checkConnectivity());
  }

  Future<void> _initialize() async {
    if (!mounted) return;
    unawaited(_checkConnectivity());
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
      // Startup owns the first verification trigger. UI hosts only render the
      // resulting verdict (REG-010): no widget mounts its own probe.
      unawaited(ref.read(webSessionStatusProvider.notifier).check());
    }
  }

  Future<void> _checkConnectivity() async {
    final proxy = _proxyController;
    if (proxy == null) return;
    final epoch = ++_connectivityEpoch;
    final address = proxy.config == null
        ? null
        : '${proxy.config!.host}:${proxy.config!.port}';
    _setConnectivityStatus(
      strings(ref.read(appLanguageProvider)).splashCheckingConnection,
    );
    final result = await proxy.testConnection();
    if (!mounted || epoch != _connectivityEpoch) return;
    final s = strings(ref.read(appLanguageProvider));
    if (result.isSuccess) {
      _setConnectivityStatus(
        address == null
            ? s.directConnectionReady
            : s.proxyConnectionReady(address),
      );
      return;
    }
    _setConnectivityStatus(
      address == null
          ? s.splashDirectBlocked
          : s.splashProxyUnreachable(address),
    );
  }

  void _setConnectivityStatus(String status) {
    if (!mounted) return;
    setState(() => _connectivityStatus = status);
  }

  @override
  Widget build(BuildContext context) {
    final s = strings(ref.watch(appLanguageProvider));
    final hasProxy = _proxyController?.config != null;
    final status =
        _connectivityStatus ??
        (hasProxy ? s.splashCheckingConnection : s.splashNoProxyDetected);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const CircularProgressIndicator(),
                const SizedBox(height: 18),
                Text(
                  s.splashRestoringSession,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  status,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
