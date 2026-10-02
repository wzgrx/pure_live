import 'package:flutter/material.dart';
import 'package:live_ui/src/icons/app_icons.dart';
import 'package:live_ui/src/theme/live_colors.dart';

/// The follow button of the live room's app bar (docs/T05/T05b/T05b.1,
/// change 12), for every other place that follows something (the card
/// dialog U.4a c11, the area rooms' app bar U.4e c3): "＋ 关注" filled with
/// the primary colour, "✓ 已关注" grey. While [busy] a spinner replaces the
/// mark and the pill is not pressable; a null [onPressed] greys it out.
class FollowPill extends StatelessWidget {
  /// Creates the pill.
  const new({
    required this.followed,
    required this.followLabel,
    required this.followedLabel,
    required this.onPressed,
    this.busy = false,
    this.tooltip,
    super.key,
  });

  /// Whether it is followed.
  final bool followed;

  /// "关注".
  final String followLabel;

  /// "已关注".
  final String followedLabel;

  /// Follows, or asks to unfollow.
  final VoidCallback? onPressed;

  /// Saving.
  final bool busy;

  /// Shown on hover.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = followed ? scheme.surfaceContainerHighest : scheme.primary;
    final foreground = followed ? scheme.onSurfaceVariant : scheme.onPrimary;
    final enabled = onPressed != null && !busy;
    final mark = busy
        ? SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: foreground))
        : Icon(followed ? AppIcons.followed : AppIcons.follow, size: 18, color: foreground);
    final button = FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: busy ? background : scheme.onSurface.withValues(alpha: 0.12),
        disabledForegroundColor: busy ? foreground : scheme.onSurface.withValues(alpha: 0.38),
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.padded,
        padding: const EdgeInsets.only(left: 12, right: 16),
        shape: const StadiumBorder(),
        textStyle: theme.textTheme.labelLarge?.emphasis,
      ),
      onPressed: enabled ? onPressed : null,
      icon: mark,
      label: Text(followed ? followedLabel : followLabel, maxLines: 1),
    );
    final message = tooltip;
    return message == null ? button : Tooltip(message: message, child: button);
  }
}
