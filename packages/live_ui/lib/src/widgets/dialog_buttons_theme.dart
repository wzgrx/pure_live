import 'package:flutter/material.dart';

/// Puts the buttons of a dialog below it on the 14-point role
/// (docs/specs/UI.md section 7: no text in a popup under 14; the theme's buttons use the
/// 13-point label, as 3.x did). Weight and shape stay the theme's.
class DialogButtonsTheme extends StatelessWidget {
  /// Wraps [child].
  const new({required this.child, super.key});

  /// The dialog.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = WidgetStatePropertyAll(
      theme.textTheme.labelLarge?.copyWith(fontSize: theme.textTheme.bodyLarge?.fontSize),
    );
    return Theme(
      data: theme.copyWith(
        textButtonTheme: TextButtonThemeData(
          style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(textStyle: text),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: (theme.filledButtonTheme.style ?? const ButtonStyle()).copyWith(textStyle: text),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: (theme.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(textStyle: text),
        ),
      ),
      child: child,
    );
  }
}
