import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';

/// The local gift banner (U.2k-e, c9): in the middle of the picture (of the
/// part a side panel leaves free in fullscreen), on its own layer, so it
/// never rebuilds the room (3.x wrapped the whole page). Two lines ("Pure
/// Live 送出 大航海 ×1", then badge, level and title) beside the gift; a
/// solid ring instead of 3.x's blurred glow; a high-value gift's banner is
/// bigger. It grows in from 72 % unless the system asks for less motion,
/// and leaves after 3 s (the session's timer).
class LocalGiftLayer extends StatelessWidget {
  /// Creates the layer of [session].
  const new({required this.session, required this.fullscreen, super.key});

  /// The room's session.
  final LocalRoomSession session;

  /// The picture fills the screen (a side panel then covers its right part).
  final bool fullscreen;

  @override
  Widget build(BuildContext context) {
    final panels = RoomPanelScope.maybeOf(context);
    return IgnorePointer(
      child: RepaintBoundary(
        child: ListenableBuilder(
          listenable: Listenable.merge([session.giftEffect, ?panels]),
          builder: (context, _) {
            final show = session.giftEffect.value;
            if (show == null) return const SizedBox.shrink();
            return LayoutBuilder(
              builder: (context, constraints) {
                final covered = fullscreen && panels?.value != null
                    ? (constraints.maxWidth / 2 < roomSidePanelWidth ? constraints.maxWidth / 2 : roomSidePanelWidth)
                    : 0.0;
                return Padding(
                  padding: EdgeInsets.only(right: covered),
                  child: Center(
                    child: LocalGiftBanner(key: ValueKey(show.serial), show: show),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// One banner.
class LocalGiftBanner extends StatelessWidget {
  /// Creates the banner of [show].
  const new({required this.show, super.key});

  /// The gift.
  final LocalGiftShow show;

  @override
  Widget build(BuildContext context) {
    final message = show.message;
    final gift = LocalGiftData.of(message);
    final profile = LocalProfile.of(message);
    if (gift == null || profile == null) return const SizedBox.shrink();
    final big = gift.big;
    final color = Color.fromARGB(255, gift.color.r, gift.color.g, gift.color.b);
    final theme = Theme.of(context);
    final second = [if (profile.badgeLabel.isNotEmpty) profile.badgeLabel, profile.title].join(' · ');
    final banner = Container(
      key: const ValueKey('local-gift-banner'),
      constraints: BoxConstraints(maxWidth: big ? 440 : 320),
      padding: big ? const EdgeInsets.fromLTRB(16, 14, 22, 14) : const EdgeInsets.fromLTRB(12, 10, 18, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withValues(alpha: 0.94), OnVideoColors.bannerEnd]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: OnVideoColors.bannerOutline),
        // c9: a solid ring, no blur over the picture.
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), spreadRadius: big ? 4 : 3)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(localEmojiText(gift.emoji), style: localEmojiStyle(TextStyle(fontSize: big ? 44 : 30, height: 1.1))),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: big ? 19 : 16,
                    fontWeight: FontWeight.w700,
                    color: OnVideoColors.foreground,
                    shadows: OnVideoColors.shadows,
                  ),
                ),
                Text(
                  localEmojiText(second),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: localEmojiStyle(
                    theme.textTheme.bodySmall?.emphasis.copyWith(fontSize: 12, color: OnVideoColors.secondary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (MediaQuery.disableAnimationsOf(context)) return banner;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.72, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: banner,
    );
  }
}
