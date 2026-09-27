import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/l10n/strings.dart';

const _destinations = [
  NavDestination(icon: Icons.favorite_border, selectedIcon: Icons.favorite, label: S.follows),
  NavDestination(icon: Icons.explore_outlined, selectedIcon: Icons.explore, label: S.discover),
  NavDestination(icon: Icons.search, selectedIcon: Icons.saved_search, label: S.search),
  NavDestination(icon: Icons.person_outline, selectedIcon: Icons.person, label: S.me),
];

/// The four top-level destinations (principles §4.1) in the adaptive shell.
class AppShell extends StatelessWidget {
  const new({required this.shell, super.key});

  /// go_router's branch navigator.
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => AdaptiveNavScaffold(
    destinations: _destinations,
    selectedIndex: shell.currentIndex,
    // Tapping the current destination again returns to its first page.
    onSelected: (index) => shell.goBranch(index, initialLocation: index == shell.currentIndex),
    body: shell,
  );
}
