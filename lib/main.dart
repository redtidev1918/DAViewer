import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'app/app.dart';
import 'core/diagnostics/app_logger.dart';
import 'core/diagnostics/crash_marker.dart';
import 'core/downloads/shared_storage_saver.dart';
import 'core/l10n/app_strings.dart';
import 'core/runtime/app_runtime.dart';
import 'core/runtime/runtime_provider.dart';
import 'core/settings/app_preferences.dart';
import 'core/theme/theme_mode_provider.dart';

String _globalProxyDirective = 'DIRECT';

void _configureImageCache() {
  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSize = 200;
  cache.maximumSizeBytes = 64 << 20; // 64 MB
}

/// Kept alive for the whole process so completed downloads are moved into the
/// public Downloads folder.
// ignore: unused_element
SharedStorageSaver? _sharedStorageSaver;

void _showDownloadComplete(String path) {
  final context = appScaffoldMessengerKey.currentContext;
  final messenger = appScaffoldMessengerKey.currentState;
  if (context == null || messenger == null) return;
  final language = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(appLanguageProvider);
  messenger.showSnackBar(
    SnackBar(content: Text('${strings(language).savedToPrefix}$path')),
  );
}

final class _AppHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) => _globalProxyDirective;
    return client;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Cap the decoded-image cache: the default is 1000 images / ~100 MB, which
  // makes long browsing sessions on low-RAM devices thrash and can OOM.
  _configureImageCache();
  final logger = await AppLogger.initialize();
  installGlobalErrorHandlers(logger);
  logger.info('app', 'DAViewer starting');
  // Detect whether the previous run ended with an uncaught error (local only).
  final crashedLastSession = await CrashMarker.consume();

  final runtime = await AppRuntime.create();
  _sharedStorageSaver = SharedStorageSaver(
    runtime.transfers,
    onSaved: _showDownloadComplete,
  );
  _globalProxyDirective = runtime.proxyController?.directive ?? 'DIRECT';
  runtime.proxyController?.addListener(() {
    _globalProxyDirective = runtime.proxyController!.directive;
  });
  HttpOverrides.global = _AppHttpOverrides();

  // Restore persisted preferences so language and theme survive a restart
  // without flashing the defaults.
  final preferences = await AppPreferences.load();
  final initialLanguage = preferences['language'] == 'en'
      ? AppLanguage.en
      : AppLanguage.zh;
  final initialThemeMode = switch (preferences['themeMode']) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  runApp(
    ProviderScope(
      retry: (_, _) => null,
      overrides: <Override>[
        runtimeProvider.overrideWithValue(runtime),
        crashDetectedProvider.overrideWithValue(crashedLastSession),
        appLanguageProvider.overrideWith(
          (ref) => AppLanguageController(initialLanguage),
        ),
        themeModeProvider.overrideWith(
          (ref) => ThemeModeController(initialThemeMode),
        ),
      ],
      child: const DAViewerApp(),
    ),
  );
}
