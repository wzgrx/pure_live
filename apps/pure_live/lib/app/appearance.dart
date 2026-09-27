import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';

/// Themes for the stored choice: (light theme, dark theme, mode). Pure black is
/// a variant of dark, not a fourth mode (principles §2.2).
(ThemeData, ThemeData, ThemeMode) themesFor(AppThemeMode mode, {required bool pureBlack}) => (
  PureTheme.of(Appearance.light),
  PureTheme.of(pureBlack ? Appearance.black : Appearance.dark),
  switch (mode) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  },
);
