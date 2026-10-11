import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/app_strings.dart';
import '../core/theme/theme_mode_provider.dart';
import '../core/auth/web_session_coordinator.dart';
import '../core/updates/update_checker.dart';
import 'router.dart';
import 'theme/app_theme.dart';

final appScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Desktop mice and trackpads must be able to drag PageView/ListView content
/// the same way touch users drag it; Flutter's default scroll behavior only
/// includes touch for drag gestures.
final class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.trackpad,
  };
}

final class DAViewerApp extends ConsumerStatefulWidget {
  const DAViewerApp({super.key});

  @override
  ConsumerState<DAViewerApp> createState() => _DAViewerAppState();
}

final class _DAViewerAppState extends ConsumerState<DAViewerApp> {
  late final AppLifecycleListener _lifecycle;
  Timer? _updateTimer;

  void _startUpdateTimer() {
    _updateTimer ??= Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(ref.read(updateCheckControllerProvider.notifier).check());
    });
  }

  void _pauseUpdates() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }

  @override
  void initState() {
    super.initState();
    final coordinator = ref.read(webSessionCoordinatorProvider);
    ref.read(updateCheckControllerProvider);
    _startUpdateTimer();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        coordinator.resume();
        _startUpdateTimer();
        unawaited(ref.read(updateCheckControllerProvider.notifier).check());
      },
      onPause: () {
        coordinator.pause();
        _pauseUpdates();
      },
      onHide: () {
        coordinator.pause();
        _pauseUpdates();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _pauseUpdates();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final language = ref.watch(appLanguageProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      scaffoldMessengerKey: appScaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      locale: language == AppLanguage.zh
          ? const Locale('zh')
          : const Locale('en'),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      scrollBehavior: const AppScrollBehavior(),
    );
  }
}
