import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/danmaku/gift_count_pulse.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/i18n/i18n.dart';

/// Draws the banner [show] in the part of the picture the gift layer leaves
/// free (its constraints): D08.5's effects come in here.
typedef LocalGiftPresenter = Widget Function(BuildContext context, LocalGiftShow show);

/// The local gift banner (U.2k-e, c9): in the middle of the picture (of the
/// part a side panel leaves free in fullscreen), on its own layer, so it
/// never rebuilds the room (3.x wrapped the whole page). Two lines ("Pure
/// Live 送出 大航海", then badge, level and title) beside the gift and its
/// "×N"; a solid ring instead of 3.x's blurred glow; a high-value gift's
/// banner is bigger. It grows in from 72 % unless the system asks for less
/// motion, and leaves after 3 s (the session's queue).
///
/// D08.4: one banner at a time, the next one when it leaves
/// ([LocalRoomSession.giftEffect]); a combo's banner stays and its "×N"
/// jumps. It keeps clear of [clearance], the controls' bars (A08.12's flying
/// gifts keep clear of the same) and a landscape cut-out, and shrinks to
/// fit what is left (large system text, the small inline picture).
class LocalGiftLayer extends StatelessWidget {
  /// Creates the layer of [session].
  const new({
    required this.session,
    required this.fullscreen,
    this.clearance = EdgeInsets.zero,
    this.presenter = LocalGiftLayer.banner,
    super.key,
  });

  /// The room's session.
  final LocalRoomSession session;

  /// The picture fills the screen (a side panel then covers its right part).
  final bool fullscreen;

  /// What the banner keeps clear of at each edge.
  final EdgeInsets clearance;

  /// Draws a banner ([banner] by default).
  final LocalGiftPresenter presenter;

  /// The banner, centred, shrunk to fit.
  static Widget banner(BuildContext context, LocalGiftShow show) => Center(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: LocalGiftBanner(key: ValueKey(show.serial), show: show),
    ),
  );

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
                  key: const ValueKey('local-gift-area'),
                  padding: clearance + EdgeInsets.only(right: covered),
                  child: presenter(context, show),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// One banner; a new count of the same banner (its combo) jumps the "×N"
/// (D08.4 c2, [GiftCountJump.banner]).
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
                  '${profile.name} ${i18n('local_sent_gift')} ${gift.name}',
                  key: const ValueKey('local-gift-banner-title'),
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
          const SizedBox(width: 10),
          GiftCountPulse(
            count: gift.count,
            jump: GiftCountJump.banner,
            child: Text(
              '×${gift.count}',
              key: const ValueKey('local-gift-banner-count'),
              style: theme.textTheme.titleLarge?.tabular.copyWith(
                fontSize: big ? 30 : 24,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: OnVideoColors.foreground,
                shadows: OnVideoColors.shadows,
              ),
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
