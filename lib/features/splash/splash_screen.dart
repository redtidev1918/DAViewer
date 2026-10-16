import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/login_observation.dart';
import '../../core/auth/web_session_controller.dart';
import '../../core/auth/web_session_coordinator.dart';
import '../../core/auth/web_session_status.dart';
import '../../core/diagnostics/app_logger.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/network/proxy_controller.dart';
import '../../core/runtime/runtime_provider.dart';

/// Application-owned bootstrap: leaving Splash does not cancel a late restore,
/// and rebuilding/re-entering Splash joins the same operation.
final startupRestoreProvider = Provider<Future<void> Function()>((ref) {
  Future<void>? operation;
  Future<void> restore() async {
    final auth = ref.read(authControllerProvider.notifier);
    final web = ref.read(webSessionControllerProvider.notifier);
    AppLogger.instance.info('startup', 'stage=oauth_restore event=start');
    try {
      await auth.initialize();
      AppLogger.instance.info('startup', 'stage=oauth_restore event=complete');
    } on Object catch (error) {
      AppLogger.instance.warning(
        'startup',
        'stage=oauth_restore event=failed errorType=${error.runtimeType}',
      );
    }
    if (!ref.mounted) return;
    AppLogger.instance.info('startup', 'stage=cookie_restore event=start');
    await web.initialize();
    AppLogger.instance.info('startup', 'stage=cookie_restore event=complete');
  }

  return () => operation ??= restore();
});

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
  Timer? _startupDeadline;
  bool _started = false;
  bool _finished = false;
  String _startupStage = 'scheduled';

  @override
  void initState() {
    super.initState();
    _proxyController = ref.read(runtimeProvider).proxyController;
    _proxyController?.addListener(_onProxyChanged);
    // Independent of every awaited Future, including a circular restore wait.
    _startupDeadline = Timer(_startupTimeout, () => _finishStartup('deadline'));
    AppLogger.instance.info(
      'startup',
      'splash created deadlineMs=${_startupTimeout.inMilliseconds}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  @override
  void dispose() {
    _startupDeadline?.cancel();
    _proxyController?.removeListener(_onProxyChanged);
    super.dispose();
  }

  void _onProxyChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_checkConnectivity());
  }

  Future<void> _initialize() async {
    if (!mounted || _started) return;
    _started = true;
    unawaited(_checkConnectivity());
    try {
      _startupStage = 'restore_pending';
      await ref.read(startupRestoreProvider)();
      _startupStage = 'restore_complete';
    } on Object catch (error) {
      AppLogger.instance.warning(
        'startup',
        'stage=$_startupStage event=failed errorType=${error.runtimeType}',
      );
    } finally {
      _finishStartup('restore_finished');
    }
  }

  void _finishStartup(String reason) {
    if (mounted && !_finished) {
      _finished = true;
      _startupDeadline?.cancel();
      AppLogger.instance.info(
        'startup',
        'ready=true reason=$reason stage=$_startupStage',
      );
      ref.read(webSessionReadyProvider.notifier).state = true;
      // Startup owns the first verification trigger. UI hosts only render the
      // resulting verdict (REG-010): no widget mounts its own probe.
      unawaited(_checkSession());
    }
  }

  Future<void> _checkSession() async {
    try {
      // Startup owns the first verification trigger, but only when the
      // persisted success history is stale: a session verified under
      // WebSessionScheduling.startupInterval is left to the feed and signal
      // driven checks that fire when a web-dependent feature is used.
      // Resolve everything through the scope container before the first await:
      // the history read can outlive this widget (setting the ready flag routes
      // away from /splash), and touching a disposed ref would drop the startup
      // verification. The container outlives the widget.
      final container = ProviderScope.containerOf(context, listen: false);
      await container
          .read(loginObservationProvider(LoginChannel.web).notifier)
          .historyReady;
      final lastSuccess = container
          .read(loginObservationProvider(LoginChannel.web))
          .lastSuccess;
      final now = container.read(webSessionClockProvider)();
      if (lastSuccess != null &&
          now.difference(lastSuccess) < WebSessionScheduling.startupInterval) {
        AppLogger.instance.info(
          'startup',
          'verification skipped: last success within startup interval',
        );
        return;
      }
      await container.read(webSessionStatusProvider.notifier).check();
    } on Object catch (error) {
      AppLogger.instance.warning(
        'startup',
        'verification failed errorType=${error.runtimeType}',
        error,
      );
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
    final result = await _testConnection(proxy);
    if (result == null) return;
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

  Future<ProxyCheckResult?> _testConnection(ProxyController proxy) async {
    try {
      return await proxy.testConnection();
    } on Object catch (error) {
      AppLogger.instance.warning(
        'startup',
        'connectivity failed errorType=${error.runtimeType}',
      );
      return null;
    }
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
