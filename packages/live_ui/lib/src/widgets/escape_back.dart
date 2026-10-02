import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Esc does on a page what Back does (UI_PLAN §5.4, docs/TASKS.md §7 from
/// U.5a–U.5c): [onEscape] (close a filter first, then leave), by default the
/// route's `maybePop`. Put it around the page's [Scaffold]: the binding has
/// to sit outside it, since a [Scaffold] keeps Esc for its drawers, and the
/// page's own focus scope takes the focus when the page opens so the key
/// reaches the binding before anything is tapped.
class EscapeBack extends StatelessWidget {
  /// Wraps the page [child].
  const new({required this.child, this.onEscape, this.autofocus = true, super.key});

  /// The page.
  final Widget child;

  /// What Esc does; null pops the route (like Back).
  final VoidCallback? onEscape;

  /// Whether the page takes the focus when it opens.
  final bool autofocus;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): onEscape ?? () => Navigator.of(context).maybePop()},
    child: FocusScope(autofocus: autofocus, child: child),
  );
}
