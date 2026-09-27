import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';

/// Themes for the stored choice: (light theme, dark theme, mode). Pure black is
/// a variant of dark, not a fourth mode (principles §2.2). TV mode has only
/// dark and pure black, with the TV type scale and focus (principles §5.3).
/// [seed] is the dynamic colour (wallpaper or system accent) when that is on.
(ThemeData, ThemeData, ThemeMode) themesFor(
  AppThemeMode mode, {
  required bool pureBlack,
  bool tv = false,
  Color? seed,
}) {
  if (tv) {
    final dark = PureTheme.tv(pureBlack ? Appearance.black : Appearance.dark);
    return (dark, dark, ThemeMode.dark);
  }
  return (
    PureTheme.of(Appearance.light, seed: seed),
    PureTheme.of(pureBlack ? Appearance.black : Appearance.dark, seed: seed),
    switch (mode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    },
  );
}
