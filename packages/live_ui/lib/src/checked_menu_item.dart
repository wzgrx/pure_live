import 'package:flutter/material.dart';
import 'package:live_ui/src/icons/live_icon.dart';
import 'package:live_ui/src/icons/live_icons.dart';
import 'package:live_ui/src/metrics.dart';

/// A popup menu entry with a check before the chosen one: Material's
/// [CheckedPopupMenuItem], whose check is a Material Icons glyph, with
/// [LiveIcons.check] instead (principles §2.6).
class CheckedMenuItem<T> extends PopupMenuItem<T> {
  /// An entry for [value] showing [child], checked when [checked].
  const new({required super.value, required this.checked, required super.child, super.enabled, super.key});

  /// Whether this is the chosen entry.
  final bool checked;

  @override
  PopupMenuItemState<T, CheckedMenuItem<T>> createState() => _CheckedMenuItemState<T>();
}

class _CheckedMenuItemState<T> extends PopupMenuItemState<T, CheckedMenuItem<T>> {
  @override
  Widget buildChild() {
    final theme = Theme.of(context);
    final states = {if (widget.checked) WidgetState.selected, if (!widget.enabled) WidgetState.disabled};
    final style = PopupMenuTheme.of(context).labelTextStyle?.resolve(states) ?? theme.textTheme.labelLarge;
    return Semantics(
      checked: widget.checked,
      child: IgnorePointer(
        child: ListTileTheme.merge(
          contentPadding: EdgeInsets.zero,
          child: ListTile(
            enabled: widget.enabled,
            titleTextStyle: style,
            leading: widget.checked ? const LiveIcon(LiveIcons.check) : const SizedBox.square(dimension: Sizes.iconMd),
            title: widget.child,
          ),
        ),
      ),
    );
  }
}
