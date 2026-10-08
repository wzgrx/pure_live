import 'package:flutter/material.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

/// An item of the TV side menu or of a list of destinations
/// (docs/A-界面设计/A17-电视界面/A17.1-电视设计系统和通用组件): the icon and the name; the current one is filled with the
/// primary container, the focused one ringed and grown (c2, c3). The menu's
/// own layout (collapsed rail, expanding on focus) is U.15b's.
class TvNavItem extends StatelessWidget {
  /// Creates the item.
  const new({
    required this.label,
    this.icon,
    this.subtitle,
    this.selected = false,
    this.onTap,
    this.onKey,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  /// The name.
  final String label;

  /// The icon before the name.
  final IconData? icon;

  /// A second line (a playlist's channel count).
  final String? subtitle;

  /// The current destination.
  final bool selected;

  /// OK.
  final VoidCallback? onTap;

  /// Keys before the default handling.
  final TvKeyHandler? onKey;

  /// The node.
  final FocusNode? focusNode;

  /// Takes the focus when first built.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final foreground = selected ? palette.onSelected : palette.textSecondary;
    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      onTap: onTap,
      onKey: onKey,
      builder: (context, focused) => Container(
        constraints: BoxConstraints(minHeight: scale.pxText(44)),
        padding: EdgeInsets.symmetric(horizontal: scale.px(12), vertical: scale.px(6)),
        decoration: BoxDecoration(
          color: selected ? palette.selected : null,
          borderRadius: BorderRadius.circular(scale.px(TvRadius.card)),
        ),
        child: Row(
          children: [
            if (icon != null) ...[Icon(icon, color: foreground, size: scale.pxText(24)), SizedBox(width: scale.px(14))],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: subtitle == null ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: scale.font(
                      TvTextSize.body,
                      weight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? palette.onSelected : palette.text,
                    ),
                  ),
                  if (subtitle case final subtitle?)
                    Text(subtitle, style: scale.font(TvTextSize.small, color: foreground)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
