import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_ui/src/icons/app_icons.dart';
import 'package:live_ui/src/theme/live_colors.dart';
import 'package:live_ui/src/widgets/anchored_menu.dart';

// Moved from the live room (docs/T05/T05g/T05g.1) so the multi-view page
// (docs/T12/T12a/T12a.2) shows the same quality and line menus.

/// The width a stream menu never goes below (docs/T05/T05g/T05g.1).
const double streamMenuMinWidth = 128;

/// A button with the current choice and a drop-down mark that opens a small
/// menu of [entries] next to itself (3.x's `PopupMenuButton` of the room
/// strip, docs/T05/T05g/T05g.1): 14-point text on 48-high rows, at least
/// [streamMenuMinWidth] wide and otherwise as wide as its text, on
/// `surfaceContainerHighest` with 8-point corners; the current entry in the
/// primary colour, bold, with a tick. A choice applies at once and closes
/// the menu; Esc, a tap outside and Back close it too; arrows and Enter
/// work as in every Material menu. The menu sits [anchoredMenuGap] off the
/// button's outline. The mark points up while the menu is open; [busy]
/// spins in the button while a switch resolves.
class StreamMenuButton extends StatefulWidget {
  /// Creates the button.
  const new({
    required this.label,
    required this.entries,
    required this.current,
    required this.onSelected,
    required this.tooltip,
    this.entryKey = 'stream-menu-item',
    this.busy = false,
    this.enabled = true,
    this.onVideo = false,
    this.preferAbove = false,
    this.onMenu,
    super.key,
  });

  /// The current choice.
  final String label;

  /// The choices, in the platform's order.
  final List<String> entries;

  /// The index of the current choice.
  final int current;

  /// Receives the chosen index.
  final ValueChanged<int> onSelected;

  /// What the button does.
  final String tooltip;

  /// The key prefix of the menu rows (`<prefix>-<index>`).
  final String entryKey;

  /// A switch resolves: a spinner, no taps.
  final bool busy;

  /// Whether the button takes taps.
  final bool enabled;

  /// White on the picture.
  final bool onVideo;

  /// Open above the button when the menu fits there.
  final bool preferAbove;

  /// Told when the menu opens and closes.
  final ValueChanged<bool>? onMenu;

  @override
  State<StreamMenuButton> createState() => _StreamMenuButtonState();
}

class _StreamMenuButtonState extends State<StreamMenuButton> {
  // The outline the menu sits next to (not the 48-high tap area around it).
  final GlobalKey _outline = GlobalKey();

  bool _open = false;

  Future<void> _show() async {
    if (_open || widget.entries.isEmpty) return;
    setState(() => _open = true);
    widget.onMenu?.call(true);
    final chosen = await showSmallMenu(
      _outline.currentContext ?? context,
      entries: widget.entries,
      current: widget.current,
      entryKey: widget.entryKey,
      preferAbove: widget.preferAbove,
    );
    if (mounted) setState(() => _open = false);
    widget.onMenu?.call(false);
    if (chosen != null) widget.onSelected(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onVideo = widget.onVideo;
    final ink = onVideo ? OnVideoColors.foreground : scheme.onSurface;
    final style = theme.textTheme.bodyMedium?.regular.copyWith(
      color: ink,
      shadows: onVideo ? OnVideoColors.shadows : null,
    );
    final enabled = widget.enabled && !widget.busy;
    return Tooltip(
      message: widget.tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? () => unawaited(_show()) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinInteractiveDimension, minWidth: kMinInteractiveDimension),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Center(
              child: SizedBox(
                key: _outline,
                height: 32,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: onVideo ? OnVideoColors.chip : null,
                    border: Border.all(
                      color: _open && !onVideo
                          ? scheme.primary
                          : (onVideo ? OnVideoColors.chipOutline : scheme.outlineVariant),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10, right: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.busy) ...[
                          SizedBox.square(
                            key: const ValueKey('stream-menu-busy'),
                            dimension: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.8, color: ink),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Text(widget.label, style: style, maxLines: 1),
                        const SizedBox(width: 2),
                        Icon(_open ? AppIcons.foldUp : AppIcons.dropDown, size: 18, color: ink),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The small menu of the room (docs/T05/T05g/T05g.1) next to the box of
/// [anchor] ([showAnchoredMenu]: placed by its measured height, below the
/// box unless only the space above takes it, or [preferAbove] and it fits
/// there; unfolding from the box's side); 14-point [entries] on rows of at
/// least 48, an optional line of [descriptions] under each and a [title] row
/// on top; `surfaceContainerHighest`, 8-point corners, [width] wide or at
/// least [streamMenuMinWidth]; the [current] entry in the primary colour,
/// bold, with a tick, and scrolled into view in a long list. A [footer]
/// (a switch that applies at once) sits under a line after the entries and
/// does not close the menu. The picture is not dimmed. Returns the chosen
/// index, or null.
Future<int?> showSmallMenu(
  BuildContext anchor, {
  required List<String> entries,
  required int current,
  List<String>? descriptions,
  String? title,
  String entryKey = 'stream-menu-item',
  bool preferAbove = false,
  double? width,
  Widget? footer,
}) {
  final theme = Theme.of(anchor);
  final scheme = theme.colorScheme;
  final text = theme.textTheme.bodyMedium?.copyWith(fontSize: 14);
  final small = theme.textTheme.bodySmall?.regular.copyWith(fontSize: 12, color: scheme.onSurfaceVariant);
  final rowHeight = descriptions == null ? kMinInteractiveDimension : 64.0;
  final currentRow = GlobalKey();
  return showAnchoredMenu<int>(
    anchor,
    preferAbove: preferAbove,
    current: currentRow,
    constraints: width == null
        ? const BoxConstraints(minWidth: streamMenuMinWidth, maxWidth: 280)
        : BoxConstraints.tightFor(width: width),
    children: [
      if (title != null) _SmallMenuTitle(title),
      for (final (index, entry) in entries.indexed)
        KeyedSubtree(
          key: index == current ? currentRow : null,
          child: PopupMenuItem<int>(
            key: ValueKey('$entryKey-$index'),
            value: index,
            height: rowHeight,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry,
                        style: index == current
                            ? text?.emphasis.copyWith(color: scheme.primary)
                            : text?.regular.copyWith(color: scheme.onSurface),
                      ),
                      if (descriptions case final lines? when index < lines.length) ...[
                        const SizedBox(height: 2),
                        Text(lines[index], style: small),
                      ],
                    ],
                  ),
                ),
                if (index == current) ...[
                  const SizedBox(width: 16),
                  Icon(AppIcons.selected, size: 18, color: scheme.primary),
                ],
              ],
            ),
          ),
        ),
      if (footer != null) ...[const PopupMenuDivider(), footer],
    ],
  );
}

/// The title row of a small menu ("竖屏全屏画面模式"): 13 points, semi-bold,
/// the secondary ink; not a choice.
class _SmallMenuTitle extends StatelessWidget {
  const new(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Text(
        title,
        key: const ValueKey('small-menu-title'),
        style: theme.textTheme.labelLarge?.emphasis.copyWith(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
