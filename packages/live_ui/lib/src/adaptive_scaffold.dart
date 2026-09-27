import 'package:flutter/material.dart';
import 'package:live_ui/src/window_class.dart';

/// One top-level destination.
@immutable
final class NavDestination {
  /// Creates a destination.
  const new({required this.icon, required this.selectedIcon, required this.label});

  /// Icon when not selected.
  final IconData icon;

  /// Icon when selected.
  final IconData selectedIcon;

  /// Label, the same on every device (principles rule 4).
  final String label;
}

/// App shell that shows the top-level destinations as a bottom bar, a
/// collapsed rail or an expanded rail depending on the window (principles §5.2).
class AdaptiveNavScaffold extends StatelessWidget {
  /// Creates the shell.
  const new({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.body,
    this.railLeading,
    super.key,
  });

  /// Destinations in order.
  final List<NavDestination> destinations;

  /// Selected destination.
  final int selectedIndex;

  /// Called with the tapped destination.
  final ValueChanged<int> onSelected;

  /// Page content.
  final Widget body;

  /// Shown above the rail's destinations (the app mark).
  final Widget? railLeading;

  @override
  Widget build(BuildContext context) => WindowLayoutBuilder(
    builder: (context, layout) {
      final kind = layout.navigation;
      if (kind == NavigationKind.bar) {
        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: onSelected,
            destinations: [
              for (final d in destinations)
                NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
            ],
          ),
        );
      }
      final extended = kind == NavigationKind.extendedRail;
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              right: false,
              child: NavigationRail(
                extended: extended,
                minWidth: 96,
                minExtendedWidth: 240,
                leading: railLeading,
                labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                selectedIndex: selectedIndex,
                onDestinationSelected: onSelected,
                destinations: [
                  for (final d in destinations)
                    NavigationRailDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: Text(d.label),
                    ),
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      );
    },
  );
}
