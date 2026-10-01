import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

/// A room on the TV (pure_live_TV b9d2f739 `TvRoomCard`): the cover takes
/// what the two text lines leave, with the platform, followed, replay and
/// audience chips on it; below, the avatar (or the channel number of an
/// IPTV list), the title and the streamer. Focus lights the card in the
/// accent's focused-card colour with the shared ring and glow.
///
/// The data is the shared card model (`AudiencePolicy.cardOf`, M12.2), so
/// the audience rule, the room marks and the untitled-room text are the
/// phone's.
class TvRoomCard extends StatelessWidget {
  /// Creates the card.
  const new({
    required this.data,
    this.onTap,
    this.onLongPress,
    this.onKey,
    this.onFocusChange,
    this.focusNode,
    this.followed = false,
    this.channelNumber,
    this.detail,
    super.key,
  });

  /// What the card shows.
  final RoomCardData data;

  /// OK.
  final VoidCallback? onTap;

  /// A held OK: the card menu.
  final VoidCallback? onLongPress;

  /// Keys before the default handling (the grid's moves).
  final TvKeyHandler? onKey;

  /// Focus gained or lost.
  final ValueChanged<bool>? onFocusChange;

  /// The node (the grid keeps one per card).
  final FocusNode? focusNode;

  /// Shows the followed chip.
  final bool followed;

  /// The channel number shown instead of the avatar (IPTV lists).
  final int? channelNumber;

  /// A line under the streamer (history: when it was watched).
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final cover = data.coverUrl ?? '';
    final iptv = data.platformId == 'iptv';
    return TvFocusable(
      focusNode: focusNode,
      onTap: onTap,
      onLongPress: onLongPress,
      onKey: onKey,
      onFocusChange: onFocusChange,
      radius: 24,
      scale: 1.04,
      builder: (context, focused) {
        final titleColor = focused ? palette.onFocusedCard : palette.text;
        final subtitleColor = focused ? palette.onFocusedCard.withValues(alpha: 0.7) : palette.textSecondary;
        final audience = data.audience?.value ?? '';
        final mark = data.restrictionLabel ?? '';
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: focused ? palette.focusedCard : palette.card,
            borderRadius: BorderRadius.circular(scale(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: palette.subtleFill,
                      child: cover.isEmpty
                          ? Icon(Icons.live_tv_rounded, size: scale(56), color: palette.textSecondary)
                          : LiveNetworkImage(
                              url: cover,
                              fit: iptv ? BoxFit.contain : BoxFit.cover,
                              memCacheWidth: 640,
                              placeholder: (_) => const SizedBox.shrink(),
                              error: (_) => Icon(Icons.live_tv_rounded, size: scale(56), color: palette.textSecondary),
                            ),
                    ),
                    Positioned(
                      left: scale(12),
                      top: scale(12),
                      right: scale(12),
                      child: Wrap(
                        spacing: scale(8),
                        runSpacing: scale(6),
                        children: [
                          TvCoverChip(logo: data.platformId),
                          if (followed) const TvCoverChip(icon: Icons.favorite_rounded, iconColor: Color(0xFFFF5C7A)),
                          if (mark.isNotEmpty) TvCoverChip(label: mark, iconColor: Colors.orangeAccent),
                        ],
                      ),
                    ),
                    if (data.isReplay)
                      Positioned(
                        right: scale(12),
                        top: scale(12),
                        child: const TvCoverChip(icon: Icons.videocam_rounded),
                      ),
                    if (data.isLive && audience.isNotEmpty)
                      Positioned(
                        right: scale(12),
                        bottom: scale(12),
                        child: TvCoverChip(icon: Icons.whatshot_rounded, label: audience),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.all(scale.text(8)),
                child: Row(
                  children: [
                    SizedBox(
                      width: scale.text(52),
                      child: Center(
                        child: channelNumber != null
                            ? Text(
                                '$channelNumber',
                                style: scale.style(28, weight: FontWeight.w800, color: titleColor),
                              )
                            : CommonAvatar(
                                avatarUrl: data.avatarUrl,
                                fallbackName: data.anchorName,
                                radius: scale.text(22),
                              ),
                      ),
                    ),
                    SizedBox(width: scale(10)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            data.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: scale.style(20, weight: FontWeight.w700, color: titleColor),
                          ),
                          SizedBox(height: scale(4)),
                          Text(
                            detail == null ? data.anchorName : '${data.anchorName} · $detail',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: scale.style(17, weight: FontWeight.w600, color: subtitleColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A small translucent chip on a cover (pure_live_TV `TvCoverChip`).
class TvCoverChip extends StatelessWidget {
  /// Creates the chip: a platform [logo], an [icon], a [label], or a mix.
  const new({this.icon, this.label, this.logo, this.iconColor, super.key});

  /// The icon.
  final IconData? icon;

  /// The text.
  final String? label;

  /// A platform id whose logo leads the chip.
  final String? logo;

  /// The icon's (or a lone label's) colour.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final scale = TvScale.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: scale.text(8), vertical: scale.text(4)),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(scale(20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (logo != null) PlatformLogo(logo!, size: scale.text(22)),
          if (icon != null) Icon(icon, size: scale.text(18), color: iconColor ?? Colors.white),
          if (label != null && label!.isNotEmpty) ...[
            if (icon != null || logo != null) SizedBox(width: scale(6)),
            Text(
              label!,
              style: scale.style(
                15,
                weight: FontWeight.w700,
                color: icon == null ? iconColor ?? Colors.white : Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
