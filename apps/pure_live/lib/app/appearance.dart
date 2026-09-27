import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_ui/live_ui.dart';

/// Theme choice (principles §2.2): system, light, dark or pure black.
enum AppearanceMode {
  /// Follow the system's light or dark mode.
  system,

  /// Always light.
  light,

  /// Always dark.
  dark,

  /// Dark with black surfaces.
  black,
}

/// The user's theme choice; in memory until live_store's settings are wired in.
class AppearanceNotifier extends Notifier<AppearanceMode> {
  @override
  AppearanceMode build() => AppearanceMode.system;

  /// Changes the theme.
  AppearanceMode set(AppearanceMode mode) => state = mode;
}

/// Theme choice provider.
final appearanceProvider = NotifierProvider<AppearanceNotifier, AppearanceMode>(AppearanceNotifier.new);

/// Themes for a choice: (light theme, dark theme, mode).
(ThemeData, ThemeData, ThemeMode) themesFor(AppearanceMode mode) => (
  PureTheme.of(Appearance.light),
  PureTheme.of(mode == AppearanceMode.black ? Appearance.black : Appearance.dark),
  switch (mode) {
    AppearanceMode.system => ThemeMode.system,
    AppearanceMode.light => ThemeMode.light,
    AppearanceMode.dark || AppearanceMode.black => ThemeMode.dark,
  },
);
