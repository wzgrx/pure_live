import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_ui/src/icons/app_icons.dart';
import 'package:live_ui/src/theme/live_colors.dart';
import 'package:live_ui/src/theme/text_styles.dart';
import 'package:live_ui/src/widgets/anchored_menu.dart';

/// One row of the small menu ([showAppMenu], [AppMenuButton]).
@immutable
final class AppMenuEntry<T> {
  /// A row with [label] and an optional [icon] that answers [value].
  const new({
    required this.value,
    required this.label,
    this.icon,
    this.description,
    this.key,
    this.enabled = true,
    this.danger = false,
    this.divider = false,
    this.switchValue,
    this.switchKey,
  });

  /// What choosing the row returns.
  final T value;

  /// The text.
  final String label;

  /// The icon in front of the text.
  final IconData? icon;

  /// A second line under [label] (12 points, the variant ink, U.1d c4):
  /// what the entry is set to now ("默认比例", "28 分钟后暂停").
  final String? description;

  /// The row's key (tests find rows by it).
  final Key? key;

  /// Whether the row takes taps.
  final bool enabled;

  /// A destructive row (delete): icon and text in the error colour.
  final bool danger;

  /// A line above the row (sets the destructive row apart).
  final bool divider;

  /// A switch at the end showing an on/off setting the row toggles (the
  /// recording card's "开播自动录"); null: none. The row takes the tap, the
  /// switch only shows the state.
  final bool? switchValue;

  /// Key of [switchValue]'s switch (tests).
  final Key? switchKey;
}

/// The height of [AppMenuEntry.divider]'s line (Material's menu divider).
const double appMenuDividerHeight = 16;

/// The smallest width of the small menu (U.2f).
const double appMenuMinWidth = 128;

/// The gap between the button and the menu.
const double appMenuGap = anchoredMenuGap;

/// Opens the small menu (docs/specs/UI.md §7, the look U.2f confirmed for
/// the quality and line menus) next to the widget of [context], usually the
/// button that opens it: rows 48 high with a 24-point icon in the variant
/// colour, 12 apart from 14-point text; `surfaceContainerHighest`, 8-point
/// corners, at least [appMenuMinWidth] wide and as wide as its text.
///
/// The menu is placed by its measured height ([showAnchoredMenu]):
/// [appMenuGap] below the button, or above it when only the space above
/// takes it ([preferAbove]: above whenever it fits there); a list taller
/// than the room scrolls. It lines up with the button's left edge, or its
/// right edge when the button sits in the right half, and unfolds from the
/// button's side. A choice closes it and is returned; a tap outside, Back
/// and Esc close it with null. Arrows and Enter work as in every Material
/// menu.
///
/// A menu of choices passes the current one as [selected]: its row is in
/// the primary colour, semibold, with a tick at the end (docs/specs/UI.md
/// §7: the current entry is always "primary + tick"). A [title] row on top
/// says what the menu is about (U.1d c4: not a choice).
Future<T?> showAppMenu<T>(
  BuildContext context, {
  required List<AppMenuEntry<T>> entries,
  bool preferAbove = false,
  T? selected,
  String? title,
}) {
  if (entries.isEmpty) return Future.value();
  final scheme = Theme.of(context).colorScheme;
  final text = context.textStyles.t14.copyWith(color: scheme.onSurface);
  final current = text.emphasis.copyWith(color: scheme.primary);
  final small = context.textStyles.t12.copyWith(color: scheme.onSurfaceVariant);
  final currentRow = GlobalKey();
  final currentIndex = selected == null ? -1 : entries.indexWhere((entry) => entry.value == selected);
  return showAnchoredMenu<T>(
    context,
    preferAbove: preferAbove,
    current: currentIndex < 0 ? null : currentRow,
    constraints: const BoxConstraints(minWidth: appMenuMinWidth, maxWidth: 280),
    children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Text(
            title,
            key: const ValueKey('app-menu-title'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.t13SemiBold.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      for (final (index, entry) in entries.indexed) ...[
        if (entry.divider) const PopupMenuDivider(),
        KeyedSubtree(
          key: index == currentIndex ? currentRow : null,
          child: PopupMenuItem<T>(
            key: entry.key,
            value: entry.value,
            enabled: entry.enabled,
            padding: const EdgeInsets.only(left: 16, right: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (entry.icon case final icon?) ...[
                  Icon(icon, size: 24, color: entry.danger ? scheme.error : scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                ],
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.label,
                        style: entry.danger
                            ? text.copyWith(color: scheme.error)
                            : (selected != null && entry.value == selected ? current : text),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (entry.description case final description?)
                        Text(description, style: small, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (selected != null && entry.value == selected) ...[
                  const SizedBox(width: 16),
                  Icon(AppIcons.selected, size: 18, color: scheme.primary),
                ],
                if (entry.switchValue case final on?) ...[
                  const SizedBox(width: 16),
                  ExcludeFocus(
                    child: IgnorePointer(
                      child: Switch(key: entry.switchKey, value: on, onChanged: entry.enabled ? (_) {} : null),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ],
  );
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
    this.enabled = true,
    this.buttonKey,
    this.onMenu,
    super.key,
  });

  /// Whether the button takes taps.
  final bool enabled;

  /// Key of the icon button (tests).
  final Key? buttonKey;

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

  /// Told when the menu opens (true) and closes (false), before
  /// [onSelected] (a player keeps its controls up meanwhile).
  final ValueChanged<bool>? onMenu;

  @override
  State<AppMenuButton<T>> createState() => AppMenuButtonState<T>();
}

/// The state of an [AppMenuButton]: [show] opens the menu from elsewhere
/// (a long press on the card the button sits on).
class AppMenuButtonState<T> extends State<AppMenuButton<T>> {
  bool _open = false;

  /// Opens the menu at the button.
  Future<void> show() => _show();

  Future<void> _show() async {
    if (_open || !widget.enabled) return;
    _open = true;
    widget.onMenu?.call(true);
    T? chosen;
    try {
      chosen = await showAppMenu<T>(context, entries: widget.entries(), preferAbove: widget.preferAbove);
    } finally {
      _open = false;
      widget.onMenu?.call(false);
    }
    if (chosen != null && mounted) widget.onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) => IconButton(
    key: widget.buttonKey,
    tooltip: widget.tooltip,
    onPressed: widget.enabled ? () => unawaited(_show()) : null,
    icon: widget.icon,
  );
}
