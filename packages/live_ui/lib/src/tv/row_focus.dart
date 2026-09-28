import 'package:flutter/widgets.dart';

/// D-pad focus that knows list rows (principles §5.3). A row's trailing
/// buttons are its focus children and lie inside it, so the framework's
/// search for the nearest node to the right never finds them: right from a
/// row moves to its nearest inner button, left from an inner button to the
/// previous one in the row and then back to the row. Everything else moves
/// as before.
class TvRowFocusAction extends DirectionalFocusAction {
  /// Creates the action.
  new();

  @override
  void invoke(DirectionalFocusIntent intent) {
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && _moveWithinRow(primary, intent.direction)) return;
    super.invoke(intent);
  }

  static bool _contains(Rect outer, Rect inner) =>
      outer.inflate(0.5).contains(inner.topLeft) && outer.inflate(0.5).contains(inner.bottomRight);

  static bool _focusable(FocusNode node) =>
      node is! FocusScopeNode && node.canRequestFocus && !node.skipTraversal && node.context != null;

  /// Focusable nodes below [row] that lie inside it.
  static List<FocusNode> _inner(FocusNode row) => [
    for (final node in row.traversalDescendants)
      if (_focusable(node) && _contains(row.rect, node.rect)) node,
  ];

  /// The row [node] lies in: its nearest focusable ancestor that holds it.
  static FocusNode? _rowOf(FocusNode node) {
    for (var parent = node.parent; parent != null && parent is! FocusScopeNode; parent = parent.parent) {
      if (_focusable(parent) && _contains(parent.rect, node.rect)) return parent;
    }
    return null;
  }

  static bool _moveWithinRow(FocusNode primary, TraversalDirection direction) {
    switch (direction) {
      case TraversalDirection.right:
        final inner = _inner(primary)..sort((a, b) => a.rect.left.compareTo(b.rect.left));
        if (inner.isEmpty) return false;
        inner.first.requestFocus();
        return true;
      case TraversalDirection.left:
        final row = _rowOf(primary);
        if (row == null) return false;
        final before = [
          for (final node in _inner(row))
            if (node != primary && node.rect.center.dx < primary.rect.center.dx) node,
        ]..sort((a, b) => b.rect.left.compareTo(a.rect.left));
        (before.isEmpty ? row : before.first).requestFocus();
        return true;
      case TraversalDirection.up || TraversalDirection.down:
        return false;
    }
  }
}
