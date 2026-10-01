import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/logic/reconnect_watch.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// Loading, offline, failure, restriction, reconnecting and paused states
/// over the video. Texts and the shade let taps through to the picture;
/// only the buttons take them.
class RoomStatusLayer extends StatelessWidget {
  /// Creates the layer.
  const new({required this.controller, required this.playback, required this.reconnect, super.key});

  /// The room.
  final LiveRoomController controller;

  /// The session's state.
  final PlaybackState playback;

  /// The drops of the stream.
  final ReconnectWatch reconnect;

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    final restricted = room.isRestricted && room.isLiveNow;
    switch (controller.stage) {
      case RoomStage.loading:
        return _Message(icon: null, title: i18n('live_play_entering'), busy: true);
      case RoomStage.failed:
        return _Message(
          icon: AppIcons.playbackError,
          title: failureText(controller.failure),
          action: i18n('retry'),
          onAction: controller.retry,
        );
      case RoomStage.offline:
        return _Offline(room: room, onRefresh: controller.load);
      case RoomStage.unplayable:
        return _Message(
          icon: restricted ? AppIcons.restricted : AppIcons.noStream,
          title: restricted ? restrictionReason(room.effectiveRestriction) : failureText(controller.failure),
          subtitle: restricted ? failureText(controller.failure) : null,
          action: i18n('retry'),
          onAction: controller.retry,
        );
      case RoomStage.playing:
        break;
    }
    if (reconnect.reconnecting && playback.status != PlaybackStatus.error) {
      return _Reconnecting(controller: controller, playback: playback, reconnect: reconnect);
    }
    return switch (playback.status) {
      PlaybackStatus.idle ||
      PlaybackStatus.opening ||
      PlaybackStatus.buffering => const _Message(icon: null, title: '', busy: true),
      PlaybackStatus.error => _Message(
        icon: AppIcons.playbackError,
        title: restricted ? restrictionReason(room.effectiveRestriction) : i18n('playback_failure_title'),
        subtitle: failureText(playback.error),
        action: i18n('retry'),
        onAction: controller.retry,
      ),
      PlaybackStatus.completed => _Message(
        icon: AppIcons.playAgain,
        title: i18n('live_play_replay_ended'),
        action: i18n('live_play_replay_again'),
        onAction: () => controller.session.seek(Duration.zero),
      ),
      PlaybackStatus.paused => const IgnorePointer(
        child: Center(child: Icon(AppIcons.pausedOverlay, size: 56, color: OnVideoColors.secondary)),
      ),
      PlaybackStatus.playing || PlaybackStatus.stopped => const SizedBox.shrink(),
    };
  }
}

/// E3: a stream that dropped says it is coming back, how many times in a
/// row, and offers the next line when there is one.
class _Reconnecting extends StatelessWidget {
  const new({required this.controller, required this.playback, required this.reconnect});

  final LiveRoomController controller;
  final PlaybackState playback;
  final ReconnectWatch reconnect;

  @override
  Widget build(BuildContext context) {
    final lines = playback.lineCount;
    return _Message(
      key: const ValueKey('live-play-reconnecting'),
      icon: null,
      busy: true,
      title: i18n('live_play_reconnecting', args: {'count': '${reconnect.attempts}'}),
      action: lines > 1 ? i18n('live_play_switch_line') : null,
      onAction: lines > 1
          ? () {
              reconnect.expectReopen();
              unawaited(controller.selectLine((playback.lineIndex + 1) % lines));
            }
          : null,
    );
  }
}

class _Message extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.onAction,
    this.busy = false,
    super.key,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!busy) const IgnorePointer(child: ColoredBox(color: OnVideoColors.dim)),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const IgnorePointer(
                    child: SizedBox.square(
                      dimension: 36,
                      child: CircularProgressIndicator(color: OnVideoColors.secondary),
                    ),
                  )
                else if (icon != null)
                  IgnorePointer(child: Icon(icon, color: OnVideoColors.secondary, size: 40)),
                if (title.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  IgnorePointer(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.emphasis.copyWith(
                        color: OnVideoColors.foreground,
                        shadows: OnVideoColors.shadows,
                      ),
                    ),
                  ),
                ],
                if (subtitle case final text? when text.isNotEmpty && text != title) ...[
                  const SizedBox(height: 4),
                  IgnorePointer(
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: OnVideoColors.secondary),
                    ),
                  ),
                ],
                if (action != null && onAction != null) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonal(onPressed: onAction, child: Text(action!)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The offline state: the cover dimmed behind the streamer and the reason
/// (3.x `NotLivingVideoWidget`).
class _Offline extends StatelessWidget {
  const new({required this.room, required this.onRefresh});

  final LiveRoom room;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        _DimmedCover(url: room.cover),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CommonAvatar(avatarUrl: room.avatar, radius: 28, fallbackName: room.nick),
              const SizedBox(height: 10),
              Text(offlineText(room), style: theme.textTheme.titleSmall?.copyWith(color: OnVideoColors.foreground)),
              const SizedBox(height: 4),
              Text(
                i18n('live_play_offline_hint'),
                style: theme.textTheme.bodySmall?.copyWith(color: OnVideoColors.secondary),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: onRefresh, child: Text(i18n('refresh'))),
            ],
          ),
        ),
      ],
    );
  }
}

/// E5: the picture of an audio-only room: its cover under a dark veil, the
/// headphone and "纯音频播放中" (3.x showed a black picture).
class AudioOnlyCover extends StatelessWidget {
  /// Creates the cover of [room].
  const new({required this.room, super.key});

  /// The room.
  final LiveRoom room;

  @override
  Widget build(BuildContext context) => Stack(
    key: const ValueKey('live-play-audio-cover'),
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: OnVideoColors.ground),
      _DimmedCover(url: room.cover),
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(AppIcons.audioOnlyActive, color: OnVideoColors.secondary, size: 44),
            const SizedBox(height: 8),
            Text(
              i18n('live_play_audio_only_playing'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: OnVideoColors.secondary),
            ),
          ],
        ),
      ),
    ],
  );
}

/// A cover under a solid dark veil (no opacity layer over the picture,
/// UI_PLAN §7.4 rule 1).
class _DimmedCover extends StatelessWidget {
  const new({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.trim().isEmpty) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        LiveNetworkImage(url: url, placeholder: (_) => const SizedBox.shrink(), error: (_) => const SizedBox.shrink()),
        const ColoredBox(color: OnVideoColors.coverDim),
      ],
    );
  }
}
