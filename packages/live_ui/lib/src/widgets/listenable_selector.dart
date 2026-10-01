import 'package:flutter/widgets.dart';

/// Rebuilds only when the part of [listenable] that [selector] picks changes
/// (`==`), not on every notification: a room's audience row does not rebuild
/// for each chat message its controller announces (UI_PLAN §7.2, "局部刷新").
class ListenableSelector<T> extends StatefulWidget {
  /// Creates the widget.
  const new({required this.listenable, required this.selector, required this.builder, this.child, super.key});

  /// What announces changes.
  final Listenable listenable;

  /// Picks the value the builder needs; compared with `==`.
  final T Function() selector;

  /// Builds from the picked value.
  final Widget Function(BuildContext context, T value, Widget? child) builder;

  /// A part of the result that does not depend on the value.
  final Widget? child;

  @override
  State<ListenableSelector<T>> createState() => _ListenableSelectorState<T>();
}

class _ListenableSelectorState<T> extends State<ListenableSelector<T>> {
  late T _value = widget.selector();

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(ListenableSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
    _value = widget.selector();
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final next = widget.selector();
    if (next != _value) setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value, widget.child);
}
