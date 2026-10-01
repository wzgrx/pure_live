import 'package:flutter/material.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

/// What a [TvButton] does, which colours its words (U.15a c4).
enum TvButtonKind {
  /// An ordinary action (cancel, close).
  normal,

  /// The main action of a dialog or page: the primary colour.
  primary,

  /// Deleting, clearing, unfollowing: the error colour.
  danger,
}

/// A pill button of the TV interface (docs/ui/compare/U.15a, parts 1): the
/// highest surface container, the words in the colour of their [kind];
/// [selected] fills it with the primary container. Focus is the shared ring
/// and 5 % growth; a button without [onTap] is drawn at 38 % and the focus
/// skips it. Holding OK does not repeat.
class TvButton extends StatelessWidget {
  /// Creates the button.
  const new({
    required this.label,
    this.icon,
    this.onTap,
    this.onLongPress,
    this.onKey,
    this.focusNode,
    this.autofocus = false,
    this.selected = false,
    this.expand = false,
    this.kind = TvButtonKind.normal,
    this.small = false,
    super.key,
  });

  /// The words.
  final String label;

  /// The icon before the words.
  final IconData? icon;

  /// OK; null disables the button.
  final VoidCallback? onTap;

  /// A held OK or the menu key.
  final VoidCallback? onLongPress;

  /// Keys before the default handling.
  final TvKeyHandler? onKey;

  /// The node.
  final FocusNode? focusNode;

  /// Takes the focus when first built.
  final bool autofocus;

  /// Marked as the current choice (primary container).
  final bool selected;

  /// Fills the width.
  final bool expand;

  /// What it does.
  final TvButtonKind kind;

  /// The smaller form (36 high, regular weight): chips such as recent
  /// search words.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final enabled = onTap != null || onLongPress != null;
    final foreground = selected
        ? palette.onSelected
        : switch (kind) {
            TvButtonKind.normal => palette.text,
            TvButtonKind.primary => palette.accent,
            TvButtonKind.danger => palette.danger,
          };
    return Opacity(
      opacity: enabled ? 1 : 0.38,
      child: TvFocusable(
        focusNode: focusNode,
        autofocus: autofocus,
        enabled: enabled,
        onTap: onTap,
        onLongPress: onLongPress,
        onKey: onKey,
        radius: TvRadius.pill,
        builder: (context, focused) => Container(
          constraints: BoxConstraints(minHeight: scale.px(small ? 36 : 40)),
          padding: EdgeInsets.symmetric(horizontal: scale.px(small ? 16 : 20), vertical: scale.px(4)),
          decoration: ShapeDecoration(
            color: selected ? palette.selected : palette.highest,
            shape: const StadiumBorder(),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: scale.px(20), color: foreground), SizedBox(width: scale.px(8))],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: scale.font(
                    TvTextSize.body,
                    weight: small ? FontWeight.w400 : FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
