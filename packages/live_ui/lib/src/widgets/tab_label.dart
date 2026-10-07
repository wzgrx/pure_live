import 'package:flutter/material.dart';
import 'package:live_ui/src/theme/live_colors.dart';
import 'package:live_ui/src/widgets/focus_ring.dart';
import 'package:live_ui/src/widgets/scrollable_tab_bar.dart';

/// A tab's content (docs/A-界面设计/A02-组件/A02.1-通用组件 c12): the label, optionally a
/// number after it (tabular, in the tab's colour; the follows' states and
/// platforms, U.4c c4) or a badge (a count on the primary colour, U.2e's
/// super chats); the label is never cut: on a very narrow bar the whole tab
/// shrinks. While the keyboard focus is on the tab it draws the focus frame
/// (U.1c c21; the theme only tints the tab).
class TabLabel extends StatelessWidget {
  /// Creates the content.
  const new({required this.label, this.count, this.badge, this.countKey, super.key});

  /// The words.
  final String label;

  /// A number after the label (null: none).
  final int? count;

  /// A badge after the label ("2", "99+"); null or empty: none.
  final String? badge;

  /// Key of the number (tests).
  final Key? countKey;

  @override
  Widget build(BuildContext context) {
    final count = this.count;
    final badge = this.badge;
    final scheme = Theme.of(context).colorScheme;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, maxLines: 1, softWrap: false),
        if (count != null) ...[
          const SizedBox(width: 4),
          Text(
            '$count',
            key: countKey,
            maxLines: 1,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500).tabular,
          ),
        ],
        if (badge != null && badge.isNotEmpty) ...[
          const SizedBox(width: 4),
          Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(9)),
            child: Text(
              badge,
              style: TextStyle(fontSize: 12, height: 1.2, fontWeight: FontWeight.w600, color: scheme.onPrimary).tabular,
            ),
          ),
        ],
      ],
    );
    final node = Focus.maybeOf(context);
    final framed = node != null && node.hasPrimaryFocus && focusFramesShown;
    return Tab(
      child: CustomPaint(
        foregroundPainter: framed
            ? FocusRingPainter(color: scheme.primary, borderRadius: BorderRadius.circular(4), gap: 6)
            : null,
        child: FittedBox(fit: BoxFit.scaleDown, child: content),
      ),
    );
  }
}

/// The second row of tabs under the first (docs/A-界面设计/A02-组件/A02.1-通用组件 c12, U.4d
/// c2): 14 points, the selected one dark and semi-bold, the others in the
/// variant ink; the indicator under the whole tab; a line under the row;
/// from the left; scrolls with the wheel and the mouse like
/// [ScrollableTabBar].
class SecondaryTabBar extends StatelessWidget {
  /// Creates the row.
  const new({required this.tabs, this.controller, this.physics, super.key});

  /// The tabs ([TabLabel]s).
  final List<Widget> tabs;

  /// The selection.
  final TabController? controller;

  /// The strip's physics.
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme.bodyLarge ?? const TextStyle();
    return ScrollableTabBar(
      controller: controller,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      indicatorSize: TabBarIndicatorSize.tab,
      indicatorColor: scheme.primary,
      dividerColor: scheme.outlineVariant,
      dividerHeight: 1,
      labelColor: scheme.onSurface,
      unselectedLabelColor: scheme.onSurfaceVariant,
      labelStyle: text.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      unselectedLabelStyle: text.copyWith(fontSize: 14, fontWeight: FontWeight.w400),
      labelPadding: const EdgeInsets.symmetric(horizontal: 14),
      physics: physics,
      tabs: tabs,
    );
  }
}
