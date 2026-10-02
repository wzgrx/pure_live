import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The keyboard of a dialog on computers (docs/ui/UI_PLAN.md §5.4): Enter
/// presses the main button ([onEnter]) and, when given, Esc runs [onEscape]
/// (a dialog that a tap outside does not close gets no Esc from the route).
///
/// The dialog takes the focus when it opens, unless [autofocus] is off
/// because something inside takes it (a text field, the "取消" of a
/// destructive question); Enter on a focused button still presses that
/// button.
class DialogKeys extends StatelessWidget {
  /// Wraps [child].
  const new({required this.child, this.onEnter, this.onEscape, this.autofocus = true, super.key});

  /// The dialog.
  final Widget child;

  /// The main button's action.
  final VoidCallback? onEnter;

  /// Esc's action; null leaves Esc to the route.
  final VoidCallback? onEscape;

  /// Whether the dialog takes the focus when it opens.
  final bool autofocus;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape && onEscape != null) {
      onEscape!();
      return KeyEventResult.handled;
    }
    // Only the dialog's own focus: a focused button keeps its Enter.
    if (node.hasPrimaryFocus &&
        onEnter != null &&
        (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter)) {
      onEnter!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(autofocus: autofocus, onKeyEvent: _onKey, child: child);
}
