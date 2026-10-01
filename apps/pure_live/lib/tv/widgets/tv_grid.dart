import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

/// Builds cell [index] of a [TvGrid] with the node and key handler it must
/// pass to its [TvFocusable].
typedef TvGridCellBuilder = Widget Function(BuildContext context, int index, FocusNode node, TvKeyHandler onKey);

/// A grid for the remote (pure_live_TV `BasePagedTvView` + `TvTabView`
/// memory + `TvFocusRestorer`), on Flutter's focus system:
///
/// - the arrows move by index (left and right within the row, up and down a
///   row), and the target row is scrolled into view before it takes the
///   focus, so rows that are not built yet are reachable;
/// - Left on the first column leaves by geometry (the side menu), Up on the
///   first row calls [onLeaveUp] (the tabs) or leaves by geometry;
/// - reaching the last two rows calls [onEndReached] (load more);
/// - coming back from outside lands on the cell focused last;
/// - `TvGridState.focusIndex` puts the focus on a cell (after a room page
///   closes).
class TvGrid extends StatefulWidget {
  /// Creates the grid.
  const new({
    required this.itemCount,
    required this.columns,
    required this.aspectRatio,
    required this.itemBuilder,
    this.crossSpacing = 24,
    this.mainSpacing = 24,
    this.onEndReached,
    this.onLeaveUp,
    this.padding,
    super.key,
  });

  /// How many cells.
  final int itemCount;

  /// Cells per row.
  final int columns;

  /// Width over height of a cell.
  final double aspectRatio;

  /// Builds a cell.
  final TvGridCellBuilder itemBuilder;

  /// The gap between columns, in logical pixels.
  final double crossSpacing;

  /// The gap between rows, in logical pixels.
  final double mainSpacing;

  /// The focus reached the last two rows.
  final VoidCallback? onEndReached;

  /// Up on the first row; when null the focus moves by geometry.
  final VoidCallback? onLeaveUp;

  /// Space around the cells (room for the focus glow when null).
  final EdgeInsets? padding;

  @override
  State<TvGrid> createState() => TvGridState();
}

/// The state of a [TvGrid].
class TvGridState extends State<TvGrid> {
  final ScrollController _scroll = ScrollController();
  final Map<int, FocusNode> _nodes = {};
  final Map<FocusNode, int> _indexes = {};
  double _rowExtent = 1;
  double _cellHeight = 1;
  EdgeInsets _padding = EdgeInsets.zero;
  int? _last;
  bool _inside = false;

  /// The cell focused last, if any.
  int? get lastFocused => _last;

  int get _columns => math.max(1, widget.columns);

  FocusNode _node(int index) {
    if (_nodes[index] case final node?) return node;
    final node = FocusNode(debugLabel: 'cell $index');
    _nodes[index] = node;
    _indexes[node] = index;
    return node;
  }

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_primaryChanged);
  }

  @override
  void didUpdateWidget(TvGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fewer cells (a refresh): forget the nodes past the end.
    final stale = _nodes.keys.where((index) => index >= widget.itemCount).toList();
    for (final index in stale) {
      final node = _nodes.remove(index);
      if (node == null) continue;
      _indexes.remove(node);
      node.dispose();
    }
    if (_last case final last? when last >= widget.itemCount) _last = widget.itemCount == 0 ? null : 0;
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_primaryChanged);
    for (final node in _nodes.values) {
      node.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  /// Focuses cell [index] (clamped), scrolling it into view first; false
  /// when the grid is empty.
  bool focusIndex(int index) {
    if (widget.itemCount == 0) return false;
    final target = index.clamp(0, widget.itemCount - 1);
    _reveal(target);
    final node = _node(target);
    if (node.context != null) {
      node.requestFocus();
    } else {
      // Built by the scroll above in the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && node.context != null) node.requestFocus();
      });
    }
    return true;
  }

  /// Focuses the cell focused last, else the first; false when empty.
  bool enter() => focusIndex(_last ?? 0);

  void _reveal(int index) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final top = _padding.top + (index ~/ _columns) * _rowExtent;
    final bottom = top + _cellHeight;
    final margin = _padding.top;
    var offset = position.pixels;
    if (top - margin < offset) {
      offset = top - margin;
    } else if (bottom + margin > offset + position.viewportDimension) {
      offset = bottom + margin - position.viewportDimension;
    }
    offset = offset.clamp(position.minScrollExtent, math.max(position.minScrollExtent, position.maxScrollExtent));
    // Snap, like pure_live_TV's dpad scrolling: an animated scroll races
    // the next press of a held arrow.
    if ((offset - position.pixels).abs() > 0.5) _scroll.jumpTo(offset);
  }

  KeyEventResult _move(int index, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final count = widget.itemCount;
    final columns = _columns;
    final column = index % columns;
    final row = index ~/ columns;
    final lastRow = (count - 1) ~/ columns;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        if (column == 0) return KeyEventResult.ignored;
        focusIndex(index - 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        if (column < columns - 1 && index + 1 < count) focusIndex(index + 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        if (row > 0) {
          focusIndex(index - columns);
          return KeyEventResult.handled;
        }
        final leave = widget.onLeaveUp;
        if (leave == null) return KeyEventResult.ignored;
        leave();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        if (row < lastRow) {
          focusIndex(math.min(index + columns, count - 1));
        } else {
          widget.onEndReached?.call();
        }
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Follows the focus once it settled: remembers the cell, asks for more
  /// near the end, and sends a focus coming back from outside to the cell
  /// left last.
  void _primaryChanged() {
    final primary = FocusManager.instance.primaryFocus;
    final index = primary == null ? null : _indexes[primary];
    if (index == null) {
      _inside = false;
      return;
    }
    if (!_inside) {
      _inside = true;
      final last = _last;
      final node = last == null ? null : _nodes[last];
      if (last != null && last != index && last < widget.itemCount && node != null && node.context != null) {
        node.requestFocus();
        return;
      }
    }
    _last = index;
    final lastRow = (widget.itemCount - 1) ~/ _columns;
    if (index ~/ _columns >= lastRow - 1) widget.onEndReached?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    final padding = widget.padding ?? EdgeInsets.all(scale(24));
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - padding.horizontal;
        final cellWidth = (width - widget.crossSpacing * (_columns - 1)) / _columns;
        _padding = padding;
        _cellHeight = cellWidth / widget.aspectRatio;
        _rowExtent = _cellHeight + widget.mainSpacing;
        return GridView.builder(
          controller: _scroll,
          padding: padding,
          physics: const ClampingScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _columns,
            childAspectRatio: widget.aspectRatio,
            crossAxisSpacing: widget.crossSpacing,
            mainAxisSpacing: widget.mainSpacing,
          ),
          itemCount: widget.itemCount,
          itemBuilder: (context, index) =>
              widget.itemBuilder(context, index, _node(index), (node, event) => _move(index, event)),
        );
      },
    );
  }
}
