import 'package:flutter/material.dart';
import 'package:pure_live/tv/tv_theme.dart';

/// The top of a TV sub-page (docs/ui/compare/U.15a c13, choice A3): the
/// title (22, 600), a line under it (14, secondary) and the page's own
/// actions on the right. No "返回" button: the remote's Back goes back, and
/// the page puts its first focus on the content (pure_live_TV focused the
/// back button first, P13).
class TvPageHeader extends StatelessWidget {
  /// Creates the header.
  const new({required this.title, this.subtitle, this.actions = const [], super.key});

  /// The page's title.
  final String title;

  /// The line under it (where the page is: "设置 · 主题设置").
  final String? subtitle;

  /// The page's actions (a follow button).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                key: const ValueKey('tv-page-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: scale.font(TvTextSize.title, weight: FontWeight.w600, color: palette.text, height: 1.3),
              ),
              if (subtitle case final subtitle? when subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: scale.font(TvTextSize.small, color: palette.textSecondary, height: 1.4),
                ),
            ],
          ),
        ),
        for (final action in actions) ...[SizedBox(width: scale.px(12)), action],
      ],
    );
  }
}
