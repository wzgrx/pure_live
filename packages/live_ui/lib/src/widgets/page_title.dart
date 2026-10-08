import 'package:flutter/material.dart';
import 'package:live_ui/src/theme/live_colors.dart';
import 'package:live_ui/src/theme/live_theme.dart';
import 'package:live_ui/src/theme/text_styles.dart';

/// A page's name with a short line under it, for an app bar's title
/// (docs/A-界面设计/A09-浏览界面/A09.8-网页搜索, U.5c: "网页搜索 / 哔哩哔哩 · 晚风", "观看记录 /
/// 18 / 50 条"): the name 17 points semibold, the line 12 points in the
/// variant colour, both on one line each and left-aligned (give the app bar
/// `centerTitle: false`), or both centred with [centred] (the history, whose
/// title 3.x centred).
class PageTitle extends StatelessWidget {
  /// Creates the title.
  const new({required this.title, this.subtitle, this.centred = false, super.key});

  /// Both lines centred (give the app bar `centerTitle: true`).
  final bool centred;

  /// The page's name.
  final String title;

  /// The line under it; none shows only the name.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = subtitle;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: centred ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          key: const ValueKey('page-title'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // 17 by default: the app bar title size × 17 / 20 (A01.2).
          style: (theme.textTheme.titleLarge ?? const TextStyle()).emphasis.copyWith(
            fontSize: LiveFontSizes.of(theme.textTheme).titleLarge * 17 / 20,
            height: 1.3,
            color: theme.colorScheme.onSurface,
          ),
        ),
        if (line != null && line.isNotEmpty)
          Text(
            line,
            key: const ValueKey('page-subtitle'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textStyles.t12.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.3),
          ),
      ],
    );
  }
}
