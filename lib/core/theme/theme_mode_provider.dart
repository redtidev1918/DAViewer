import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../settings/app_preferences.dart';

/// The user-selected theme mode (system / light / dark), persisted across
/// launches and defaulting to following the system theme.
final class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController([super.state = ThemeMode.system]);

  void set(ThemeMode mode) {
    state = mode;
    unawaited(AppPreferences.saveThemeMode(mode.name));
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) => ThemeModeController(),
);
