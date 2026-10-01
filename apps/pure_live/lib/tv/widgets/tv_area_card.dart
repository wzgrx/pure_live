import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_room_card.dart';

/// An area on the TV (docs/ui/compare/U.15a c6): a card of its own colour
/// (pure_live_TV drew it on the page colour, P7) with the picture filling
/// the top, the name (16, 600) and an optional second line (the platform in
/// the followed areas); a heart top right when the area is followed. Focus
/// is the shared ring and 5 % growth. A picture loading or failed shows the
/// cover placeholder.
class TvAreaCard extends StatelessWidget {
  /// Creates the card.
  const new({
    required this.name,
    this.picture,
    this.subtitle,
    this.followed = false,
    this.onTap,
    this.onLongPress,
    this.onKey,
    this.focusNode,
    super.key,
  });

  /// The area's name.
  final String name;

  /// The picture's address.
  final String? picture;

  /// A second line (the platform).
  final String? subtitle;

  /// Shows the followed heart.
  final bool followed;

  /// OK: the area's rooms.
  final VoidCallback? onTap;

  /// A held OK or the menu key.
  final VoidCallback? onLongPress;

  /// Keys before the default handling (the grid's moves).
  final TvKeyHandler? onKey;

  /// The node (the grid keeps one per card).
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    return TvFocusable(
      focusNode: focusNode,
      onTap: onTap,
      onLongPress: onLongPress,
      onKey: onKey,
      builder: (context, focused) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: focused ? palette.raised : palette.card,
          borderRadius: BorderRadius.circular(scale.px(TvRadius.card)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TvCover(url: picture, cacheWidth: 360),
                  if (followed)
                    Positioned(
                      right: scale.px(6),
                      top: scale.px(6),
                      child: Container(
                        key: const ValueKey('tv-area-followed'),
                        width: scale.px(24),
                        height: scale.px(24),
                        decoration: const BoxDecoration(color: OnVideoColors.scrim, shape: BoxShape.circle),
                        child: Icon(TvIcons.followedMark, size: scale.px(15), color: TvColors.followed),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(scale.px(10), scale.px(8), scale.px(10), scale.px(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: scale.font(TvTextSize.body, weight: FontWeight.w600, color: palette.text, height: 1.4),
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
          ],
        ),
      ),
    );
  }
}
