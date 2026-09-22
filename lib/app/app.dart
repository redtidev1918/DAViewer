import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/app_strings.dart';
import '../core/theme/theme_mode_provider.dart';
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

final class DAViewerApp extends ConsumerWidget {
  const DAViewerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
