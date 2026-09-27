import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';

/// Themes for the stored choice: (light theme, dark theme, mode). Pure black is
/// a variant of dark, not a fourth mode (principles §2.2). TV mode has only
/// dark and pure black, with the TV type scale and focus (principles §5.3).
/// [seed] is the dynamic colour (wallpaper or system accent) when that is on;
/// [fontFamily] the downloaded interface font, null for the platform's;
/// [locale] the interface language, carried by the text styles (§2.3).
(ThemeData, ThemeData, ThemeMode) themesFor(
  AppThemeMode mode, {
  required bool pureBlack,
  bool tv = false,
  Color? seed,
  String? fontFamily,
  Locale? locale,
}) {
  if (tv) {
    final dark = PureTheme.tv(pureBlack ? Appearance.black : Appearance.dark, fontFamily: fontFamily, locale: locale);
    return (dark, dark, ThemeMode.dark);
  }
  return (
    PureTheme.of(Appearance.light, seed: seed, fontFamily: fontFamily, locale: locale),
    PureTheme.of(pureBlack ? Appearance.black : Appearance.dark, seed: seed, fontFamily: fontFamily, locale: locale),
    switch (mode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    },
  );
}

/// The app's dark theme — dynamic colour, interface font and language
/// included — for what is dark in every mode: video pages and the panels
/// over video (principles §3). `PureLiveApp` provides it; without it (a bare
/// test) a plain dark theme stands in.
class DarkTheme extends InheritedWidget {
  const new({required this.data, required super.child, super.key});

  final ThemeData data;

  static ThemeData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DarkTheme>()?.data ??
      PureTheme.of(Appearance.dark, platform: Theme.of(context).platform, locale: Localizations.maybeLocaleOf(context));

  @override
  bool updateShouldNotify(DarkTheme oldWidget) => oldWidget.data != data;
}
