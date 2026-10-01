import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_ui/src/icons/app_icons.dart';
import 'package:live_ui/src/theme/live_colors.dart';
import 'package:live_ui/src/theme/text_styles.dart';

/// One row of the small menu ([showAppMenu], [AppMenuButton]).
@immutable
final class AppMenuEntry<T> {
  /// A row with [label] and an optional [icon] that answers [value].
  const new({required this.value, required this.label, this.icon, this.key, this.enabled = true});

  /// What choosing the row returns.
  final T value;

  /// The text.
  final String label;

  /// The icon in front of the text.
  final IconData? icon;

  /// The row's key (tests find rows by it).
  final Key? key;

  /// Whether the row takes taps.
  final bool enabled;
}

/// The smallest width of the small menu (U.2f).
const double appMenuMinWidth = 128;

/// The gap between the button and the menu.
const double appMenuGap = 4;

/// Opens the small menu (docs/ui/UI_PLAN.md §7, the look U.2f confirmed for
/// the quality and line menus) next to the widget of [context], usually the
/// button that opens it: rows 48 high with a 24-point icon in the variant
/// colour, 12 apart from 14-point text; `surfaceContainerHighest`, 8-point
/// corners, at least [appMenuMinWidth] wide and as wide as its text.
///
/// The menu opens [appMenuGap] below the button, or above it when only the
/// space above takes it ([preferAbove]: above whenever it fits there); it
/// lines up with the button's left edge, or its right edge when the button
/// sits in the right half. A choice closes it and is returned; a tap
/// outside, Back and Esc close it with null. Arrows and Enter work as in
/// every Material menu.
///
/// A menu of choices passes the current one as [selected]: its row is in
/// the primary colour, semibold, with a tick at the end (docs/ui/UI_PLAN.md
/// §7: the current entry is always "primary + tick").
Future<T?> showAppMenu<T>(
  BuildContext context, {
  required List<AppMenuEntry<T>> entries,
  bool preferAbove = false,
  T? selected,
}) {
  if (entries.isEmpty) return Future.value();
  final scheme = Theme.of(context).colorScheme;
  final text = context.textStyles.t14.copyWith(color: scheme.onSurface);
  final current = text.emphasis.copyWith(color: scheme.primary);
  return showMenu<T>(
    context: context,
    position: _position(context, entries.length, preferAbove: preferAbove),
    color: scheme.surfaceContainerHighest,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    constraints: const BoxConstraints(minWidth: appMenuMinWidth, maxWidth: 280),
    items: [
      for (final entry in entries)
        PopupMenuItem<T>(
          key: entry.key,
          value: entry.value,
          enabled: entry.enabled,
          padding: const EdgeInsets.only(left: 16, right: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (entry.icon case final icon?) ...[
                Icon(icon, size: 24, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
              ],
              Flexible(
                child: Text(
                  entry.label,
                  style: selected != null && entry.value == selected ? current : text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (selected != null && entry.value == selected) ...[
                const SizedBox(width: 16),
                Icon(AppIcons.selected, size: 18, color: scheme.primary),
              ],
            ],
          ),
        ),
    ],
  );
}

/// Where the menu of [count] rows goes next to the box of [context].
RelativeRect _position(BuildContext context, int count, {required bool preferAbove}) {
  final button = context.findRenderObject()! as RenderBox;
  final overlay = Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final rect = button.localToGlobal(Offset.zero, ancestor: overlay) & button.size;
  final padding = MediaQuery.paddingOf(context);
  // Rows of 48 and the menu's own 8 above and below (Material's menu).
  final height = count * kMinInteractiveDimension + 16;
  final below = overlay.size.height - padding.bottom - rect.bottom - appMenuGap;
  final above = rect.top - padding.top - appMenuGap;
  final up = preferAbove ? height <= above || above > below : height > below && above > below;
  final top = up ? rect.top - appMenuGap - height : rect.bottom + appMenuGap;
  // Material's menu lines up with the side of the position nearer its edge.
  return RelativeRect.fromLTRB(rect.left, top, overlay.size.width - rect.right, overlay.size.height - top);
}

/// An icon button that opens [entries] in the small menu ([showAppMenu]);
/// the chosen value goes to [onSelected]. A long press (phones) or hovering
/// (mouse) shows [tooltip].
class AppMenuButton<T> extends StatefulWidget {
  /// Creates the button.
  const new({
    required this.icon,
    required this.tooltip,
    required this.entries,
    required this.onSelected,
    this.preferAbove = false,
    super.key,
  });

  /// The button's icon.
  final Widget icon;

  /// What the button is.
  final String tooltip;

  /// The rows, read when the menu opens.
  final List<AppMenuEntry<T>> Function() entries;

  /// Receives the chosen value.
  final ValueChanged<T> onSelected;

  /// Open above the button when the menu fits there.
  final bool preferAbove;

  @override
  State<AppMenuButton<T>> createState() => _AppMenuButtonState<T>();
}

class _AppMenuButtonState<T> extends State<AppMenuButton<T>> {
  bool _open = false;

  Future<void> _show() async {
    if (_open) return;
    _open = true;
    try {
      final chosen = await showAppMenu<T>(context, entries: widget.entries(), preferAbove: widget.preferAbove);
      if (chosen != null && mounted) widget.onSelected(chosen);
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) =>
      IconButton(tooltip: widget.tooltip, onPressed: () => unawaited(_show()), icon: widget.icon);
}
