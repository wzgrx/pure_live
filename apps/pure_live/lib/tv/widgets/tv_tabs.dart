import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

/// One tab of a [TvTabBar].
@immutable
final class TvTab {
  /// Creates a tab.
  const new({required this.id, required this.label, this.logo, this.icon, this.badge});

  /// Stable identity (the platform id, a group name).
  final String id;

  /// The text.
  final String label;

  /// A platform id whose logo leads the tab.
  final String? logo;

  /// An icon leading the tab.
  final IconData? icon;

  /// A count after the label.
  final int? badge;
}

/// A row of tabs for the remote (pure_live_TV `TvTabBar` in the style of
/// docs/T18/T18a/T18a.2): pills 36 high, the current one filled with the
/// primary container, the focused one ringed and grown; a count after the
/// label in equal-width figures. Walking across the tabs only moves the
/// focus, OK switches (so browsing does not load every platform), OK on the
/// current tab refreshes it, and a thin line shows while the content loads.
/// Down leaves for the content ([onDown]).
class TvTabBar extends StatefulWidget {
  /// Creates the bar.
  const new({
    required this.tabs,
    required this.selected,
    required this.onSelect,
    this.onRefresh,
    this.onDown,
    this.busy = false,
    this.small = false,
    super.key,
  });

  /// The tabs.
  final List<TvTab> tabs;

  /// The current tab.
  final int selected;

  /// OK on another tab.
  final ValueChanged<int> onSelect;

  /// OK on the current tab.
  final VoidCallback? onRefresh;

  /// Down from a tab: returns whether it moved the focus (else the focus
  /// moves by geometry).
  final bool Function()? onDown;

  /// The content is loading.
  final bool busy;

  /// The smaller row (32 high, 14): a second row under the main tabs.
  final bool small;

  @override
  State<TvTabBar> createState() => TvTabBarState();
}

/// The bar's state: [focusSelected] puts the focus on the current tab.
class TvTabBarState extends State<TvTabBar> {
  final Map<String, FocusNode> _nodes = {};

  FocusNode _node(String id) => _nodes[id] ??= FocusNode(debugLabel: 'tab $id');

  /// Whether one of the tabs has the focus.
  bool get hasFocus => _nodes.values.any((node) => node.hasFocus);

  /// Focuses the current tab; false when there is none.
  bool focusSelected() {
    if (widget.tabs.isEmpty) return false;
    final tab = widget.tabs[widget.selected.clamp(0, widget.tabs.length - 1)];
    final node = _node(tab.id);
    if (node.context == null) return false;
    node.requestFocus();
    return true;
  }

  @override
  void didUpdateWidget(TvTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = {for (final tab in widget.tabs) tab.id};
    final gone = _nodes.keys.where((id) => !ids.contains(id)).toList();
    for (final id in gone) {
      _nodes.remove(id)?.dispose();
    }
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || event.logicalKey != LogicalKeyboardKey.arrowDown) return KeyEventResult.ignored;
    final down = widget.onDown;
    return down != null && down() ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final height = scale.pxText(widget.small ? 32 : 36);
    final fontSize = widget.small ? TvTextSize.small : TvTextSize.body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: scale.px(8), vertical: scale.px(6)),
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (final (index, tab) in widget.tabs.indexed)
                Padding(
                  padding: EdgeInsets.only(right: scale.px(8)),
                  child: TvFocusable(
                    key: ValueKey('tv-tab-${tab.id}'),
                    focusNode: _node(tab.id),
                    radius: TvRadius.pill,
                    onKey: _key,
                    onTap: () => index == widget.selected ? widget.onRefresh?.call() : widget.onSelect(index),
                    builder: (context, focused) {
                      // Selected is a fill, focus is the ring (U.15a c3): the
                      // two read apart and can be on the same tab.
                      final selected = index == widget.selected;
                      final foreground = selected ? palette.onSelected : palette.textSecondary;
                      return Container(
                        height: height,
                        padding: EdgeInsets.symmetric(horizontal: scale.px(widget.small ? 14 : 16)),
                        decoration: ShapeDecoration(
                          color: selected ? palette.selected : palette.card,
                          shape: const StadiumBorder(),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (tab.logo != null) ...[
                              PlatformLogo(tab.logo!, size: scale.pxText(20)),
                              SizedBox(width: scale.px(6)),
                            ] else if (tab.icon != null) ...[
                              Icon(tab.icon, size: scale.pxText(20), color: foreground),
                              SizedBox(width: scale.px(6)),
                            ],
                            Text(
                              tab.label,
                              style: scale.font(
                                fontSize,
                                weight: selected ? FontWeight.w600 : FontWeight.w400,
                                color: foreground,
                              ),
                            ),
                            if (tab.badge case final badge?) ...[
                              SizedBox(width: scale.px(6)),
                              Text(
                                '$badge',
                                key: ValueKey('tv-tab-${tab.id}-count'),
                                style: scale.font(TvTextSize.small, weight: FontWeight.w600, color: foreground).tabular,
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        // The refresh line under the tabs (pure_live_TV's, kept by c1).
        SizedBox(
          height: scale.px(3),
          child: widget.busy
              ? LinearProgressIndicator(
                  key: const ValueKey('tv-tabs-busy'),
                  color: palette.accent,
                  backgroundColor: palette.selected,
                  borderRadius: BorderRadius.circular(scale.px(2)),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
