import 'dart:ui' show lerpDouble;

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
///
/// From the expanded width class on (not on landscape phones) a button at
/// the top of the rail expands and collapses it; [railExtended] is the
/// user's last choice, null until they make one: the rail is then expanded
/// on large and extra-large windows and collapsed below.
class AdaptiveNavScaffold extends StatelessWidget {
  /// Creates the shell.
  const new({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.body,
    this.railLeading,
    this.railExtended,
    this.onRailExtendedChanged,
    this.expandRailLabel = '',
    this.collapseRailLabel = '',
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

  /// The user's choice of an expanded rail; null follows the window class.
  final bool? railExtended;

  /// Called when the user expands (true) or collapses (false) the rail;
  /// without it the rail has no toggle.
  final ValueChanged<bool>? onRailExtendedChanged;

  /// Tooltip of the toggle on a collapsed rail.
  final String expandRailLabel;

  /// Tooltip of the toggle on an expanded rail.
  final String collapseRailLabel;

  /// Width of the collapsed rail.
  static const double railWidth = 96;

  /// Width of the expanded rail.
  static const double extendedRailWidth = 240;

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
      final toggle = onRailExtendedChanged;
      final canToggle = toggle != null && layout.width.atLeast(WidthClass.expanded) && !layout.isShortLandscape;
      final extended = canToggle
          ? railExtended ?? kind == NavigationKind.extendedRail
          : kind == NavigationKind.extendedRail;
      final leading = [
        if (canToggle)
          _RailToggle(
            tooltip: extended ? collapseRailLabel : expandRailLabel,
            icon: extended ? Icons.menu_open : Icons.menu,
            onPressed: () => toggle(!extended),
          ),
        ?railLeading,
      ];
      return Scaffold(
        body: Row(
          children: [
            SafeArea(
              right: false,
              child: NavigationRail(
                extended: extended,
                minWidth: railWidth,
                minExtendedWidth: extendedRailWidth,
                leading: leading.isEmpty
                    ? null
                    : leading.length == 1
                    ? leading.single
                    : Column(mainAxisSize: MainAxisSize.min, children: leading),
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

/// The rail's expand and collapse button, on the destinations' icon column
/// while the rail animates between its widths.
class _RailToggle extends StatelessWidget {
  const new({required this.tooltip, required this.icon, required this.onPressed});

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final animation = NavigationRail.extendedAnimation(context);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => SizedBox(
        width: lerpDouble(AdaptiveNavScaffold.railWidth, AdaptiveNavScaffold.extendedRailWidth, animation.value),
        child: Align(alignment: AlignmentDirectional.centerStart, child: child),
      ),
      child: SizedBox(
        width: AdaptiveNavScaffold.railWidth,
        child: Center(
          child: IconButton(tooltip: tooltip, icon: Icon(icon), onPressed: onPressed),
        ),
      ),
    );
  }
}
