import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:live_ui/src/metrics.dart';
import 'package:live_ui/src/tv/tv_scope.dart';

/// What a D-pad press does inside a grid (principles §5.3, §6.3).
@immutable
sealed class GridStep {
  const new();
}

/// Focus the item at [index]; [column] is the column later vertical moves
/// aim for, so a pass through a shorter last row comes back to the same
/// column.
final class GridFocus extends GridStep {
  /// Creates the step.
  const new(this.index, this.column);

  /// Item to focus.
  final int index;

  /// Column to aim for.
  final int column;

  @override
  bool operator ==(Object other) => other is GridFocus && other.index == index && other.column == column;

  @override
  int get hashCode => Object.hash(index, column);

  @override
  String toString() => 'GridFocus($index, column $column)';
}

/// The press stays where it is: the end of a row or of the list.
final class GridHold extends GridStep {
  /// Creates the step.
  const new();

  @override
  bool operator ==(Object other) => other is GridHold;

  @override
  int get hashCode => 1;

  @override
  String toString() => 'GridHold';
}

/// The press leaves the grid: the page's traversal takes it (to the rail on
/// the left, the filters above, the footer below).
final class GridExit extends GridStep {
  /// Creates the step.
  const new();

  @override
  bool operator ==(Object other) => other is GridExit;

  @override
  int get hashCode => 2;

  @override
  String toString() => 'GridExit';
}

/// One D-pad move from [index] in a grid of [count] items, [columns] per
/// row. Moves are single-axis; left of the first column and above the first
/// row leave the grid, right of the last card of a row holds; down into a
/// shorter last row lands on its last card and [column] (the remembered
/// column) brings the next move up back to where it started.
GridStep gridStep({
  required int index,
  required TraversalDirection direction,
  required int count,
  required int columns,
  int? column,
}) {
  assert(columns > 0 && count > 0 && index >= 0 && index < count, 'index $index of $count in $columns columns');
  final row = index ~/ columns;
  final col = index % columns;
  final aim = math.min(column ?? col, columns - 1);
  final lastRow = (count - 1) ~/ columns;
  return switch (direction) {
    TraversalDirection.left => col == 0 ? const GridExit() : GridFocus(index - 1, col - 1),
    TraversalDirection.right =>
      col == columns - 1 || index + 1 >= count ? const GridHold() : GridFocus(index + 1, col + 1),
    TraversalDirection.up => row == 0 ? const GridExit() : GridFocus((row - 1) * columns + aim, aim),
    TraversalDirection.down =>
      row == lastRow ? const GridExit() : GridFocus(math.min((row + 1) * columns + aim, count - 1), aim),
  };
}

/// Focus of one card grid on a remote: a node per card, row and column
/// moves ([gridStep]) and the last focused card. The route's focus scope
/// brings focus back to that card when the user returns from a room.
class TvGridFocus {
  /// Creates the focus of a grid named [debugLabel].
  new({this.debugLabel = 'grid'});

  /// Prefix of the nodes' labels.
  final String debugLabel;

  final Map<int, FocusNode> _nodes = {};
  int? _column;
  int? _moving;

  /// The card that had focus last.
  int? lastIndex;

  /// The node of card [index].
  FocusNode node(int index) => _nodes.putIfAbsent(index, () => FocusNode(debugLabel: '$debugLabel-$index'));

  /// Records that card [index] gained focus. Focus that arrived from outside
  /// the grid forgets the remembered column.
  void focused(int index) {
    if (_moving != index) _column = null;
    _moving = null;
    lastIndex = index;
  }

  /// Handles a key on card [index]; [rowExtent] is the height of a row with
  /// its gap, used to scroll a row that is not built yet into view.
  KeyEventResult handleKey(int index, KeyEvent event, {required int count, required int columns, double? rowExtent}) {
    if (event is KeyUpEvent || index >= count) return KeyEventResult.ignored;
    final direction = TvKeys.directions[event.logicalKey];
    if (direction == null) return KeyEventResult.ignored;
    switch (gridStep(index: index, direction: direction, count: count, columns: columns, column: _column)) {
      case GridExit():
        return KeyEventResult.ignored;
      case GridHold():
        return KeyEventResult.handled;
      case GridFocus(index: final target, :final column):
        _column = direction == TraversalDirection.up || direction == TraversalDirection.down ? column : null;
        _moving = target;
        _focus(target, from: _nodes[index]?.context, down: direction == TraversalDirection.down, rowExtent: rowExtent);
        return KeyEventResult.handled;
    }
  }

  void _focus(int target, {required BuildContext? from, required bool down, double? rowExtent}) {
    final node = this.node(target);
    if (node.context != null) {
      _reveal(node);
      return;
    }
    // A row outside the built range: scroll one row towards it, focus it
    // after the frame that builds it.
    final position = from == null ? null : Scrollable.maybeOf(from)?.position;
    if (position != null && rowExtent != null) {
      final next = position.pixels + (down ? rowExtent : -rowExtent);
      position.jumpTo(next.clamp(position.minScrollExtent, position.maxScrollExtent));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (node.context != null) _reveal(node);
    });
  }

  static void _reveal(FocusNode node) {
    node.requestFocus();
    // The focused row stays in the middle of the screen.
    Scrollable.ensureVisible(node.context!, alignment: 0.5, duration: Motion.short);
  }

  /// Focuses the last focused card again; false when there is none built.
  bool restore() {
    final index = lastIndex;
    final node = index == null ? null : _nodes[index];
    if (node == null || node.context == null || !node.canRequestFocus) return false;
    node.requestFocus();
    return true;
  }

  /// Releases the nodes.
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    _nodes.clear();
  }
}
