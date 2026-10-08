import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The system bars for a theme of [brightness] (A06.5; 3.x set them once at
/// start in `MobileManager.initialize`): see-through status and navigation
/// bars without the navigation divider, edge to edge. The icons contrast
/// with the theme; 3.x kept the navigation icons dark, unreadable in the
/// dark theme. On Android 15 and later the system ignores the bar colours
/// (edge to edge is enforced) but still follows the icon brightness.
SystemUiOverlayStyle systemBarsStyle(Brightness brightness) {
  final icons = brightness == Brightness.dark ? Brightness.light : Brightness.dark;
  const clear = Color(0x00000000);
  return SystemUiOverlayStyle(
    statusBarColor: clear,
    statusBarBrightness: brightness,
    statusBarIconBrightness: icons,
    systemNavigationBarColor: clear,
    systemNavigationBarDividerColor: clear,
    systemNavigationBarIconBrightness: icons,
  );
}

/// Puts [systemBarsStyle] of the current theme under every page: Flutter
/// applies it from the first frame and again whenever the theme changes.
/// Pages override the status bar with their own app bar (its colour decides
/// the icons there); the navigation bar keeps this style unless a page
/// covers the bottom with a region of its own (the splash page).
class SystemBarsScope extends StatelessWidget {
  /// Wraps [child].
  const new({required this.child, super.key});

  /// The app's pages.
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      AnnotatedRegion<SystemUiOverlayStyle>(value: systemBarsStyle(Theme.of(context).brightness), child: child);
}
