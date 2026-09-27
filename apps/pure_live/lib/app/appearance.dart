import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';

/// Themes for the stored choice: (light theme, dark theme, mode). Pure black is
/// a variant of dark, not a fourth mode (principles §2.2). TV mode has only
/// dark and pure black, with the TV type scale and focus (principles §5.3).
/// [seed] is the dynamic colour (wallpaper or system accent) when that is on;
/// [fontFamily] the downloaded interface font, null for the platform's.
(ThemeData, ThemeData, ThemeMode) themesFor(
  AppThemeMode mode, {
  required bool pureBlack,
  bool tv = false,
  Color? seed,
  String? fontFamily,
}) {
  if (tv) {
    final dark = PureTheme.tv(pureBlack ? Appearance.black : Appearance.dark, fontFamily: fontFamily);
    return (dark, dark, ThemeMode.dark);
  }
  return (
    PureTheme.of(Appearance.light, seed: seed, fontFamily: fontFamily),
    PureTheme.of(pureBlack ? Appearance.black : Appearance.dark, seed: seed, fontFamily: fontFamily),
    switch (mode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    },
  );
}
