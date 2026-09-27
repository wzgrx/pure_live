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

/// The four top-level destinations (principles §4.1) in the adaptive shell;
/// in TV mode the collapsed rail that expands on focus (§5.3).
class AppShell extends StatelessWidget {
  const new({required this.shell, super.key});

  /// go_router's branch navigator.
  final StatefulNavigationShell shell;

  // Choosing the current destination again returns to its first page.
  void _select(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) => TvScope.of(context).enabled
      ? TvNavScaffold(destinations: _destinations, selectedIndex: shell.currentIndex, onSelected: _select, body: shell)
      : AdaptiveNavScaffold(
          destinations: _destinations,
          selectedIndex: shell.currentIndex,
          onSelected: _select,
          body: shell,
        );
}
