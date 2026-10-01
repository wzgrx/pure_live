import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/live_play/room_controller.dart';
import 'package:pure_live/pages/live_play/room_panels.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// 3.x's video fit list: the setting `videoFitIndex` is an index into it.
const List<BoxFit> videoFits = [
  BoxFit.contain,
  BoxFit.cover,
  BoxFit.fill,
  BoxFit.fitHeight,
  BoxFit.fitWidth,
  BoxFit.scaleDown,
];

/// The video with its danmaku, status and controls (3.x `VideoPlayer` +
/// `VideoControllerPanel`, the playback part).
class RoomPlayer extends ConsumerStatefulWidget {
  /// Creates the player area.
  const new({
    required this.controller,
    required this.fullscreen,
    required this.onToggleFullscreen,
    required this.onBack,
    super.key,
  });

  /// The room.
  final LiveRoomController controller;

  /// Whether the player fills the screen.
  final bool fullscreen;

  /// Enters or leaves fullscreen.
  final VoidCallback onToggleFullscreen;

  /// Leaves the room (the fullscreen top bar).
  final VoidCallback onBack;

  @override
  ConsumerState<RoomPlayer> createState() => _RoomPlayerState();
}

class _RoomPlayerState extends ConsumerState<RoomPlayer> {
  bool _controls = true;
  Timer? _hide;

  LiveRoomController get _room => widget.controller;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _touch() {
    if (!_controls) setState(() => _controls = true);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final fit = videoFits[watchSetting(ref, Settings.videoFitIndex).clamp(0, videoFits.length - 1)];
    final showDanmaku = watchSetting(ref, Settings.enableDanmakuDisplay) && !watchSetting(ref, Settings.hideDanmaku);
    return ColoredBox(
      color: Colors.black,
      child: MouseRegion(
        onHover: (_) => _touch(),
        // Only the picture takes the double tap: on the buttons it would
        // hold every tap back by the double-tap timeout.
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              onDoubleTap: widget.onToggleFullscreen,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  LiveVideoView(session: _room.session, fit: fit),
                  DanmakuOverlay(
                    messages: _room.flying,
                    retractions: _room.retractions,
                    look: danmakuLookOf(ref),
                    visible: showDanmaku,
                  ),
                ],
              ),
            ),
            ListenableBuilder(
              listenable: _room,
              builder: (context, _) => StreamBuilder<PlaybackState>(
                stream: _room.session.states,
                initialData: _room.session.state,
                builder: (context, snapshot) =>
                    _StatusLayer(controller: _room, playback: snapshot.data ?? _room.session.state),
              ),
            ),
            AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_controls,
                child: _Controls(
                  controller: _room,
                  fullscreen: widget.fullscreen,
                  showDanmaku: showDanmaku,
                  onToggleFullscreen: widget.onToggleFullscreen,
                  onBack: widget.onBack,
                  onInteract: _scheduleHide,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loading, offline, failure and restriction states over the video.
class _StatusLayer extends StatelessWidget {
  const new({required this.controller, required this.playback});

  final LiveRoomController controller;
  final PlaybackState playback;

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    final restricted = room.isRestricted && room.isLiveNow;
    switch (controller.stage) {
      case RoomStage.loading:
        return _Message(icon: null, title: i18n('live_play_entering'), busy: true);
      case RoomStage.failed:
        return _Message(
          icon: Icons.error_outline_rounded,
          title: failureText(controller.failure),
          action: i18n('retry'),
          onAction: controller.retry,
        );
      case RoomStage.offline:
        return _Offline(room: room, onRefresh: controller.load);
      case RoomStage.unplayable:
        return _Message(
          icon: restricted ? Icons.lock_outline_rounded : Icons.videocam_off_outlined,
          title: restricted ? restrictionReason(room.effectiveRestriction) : failureText(controller.failure),
          subtitle: restricted ? failureText(controller.failure) : null,
          action: i18n('retry'),
          onAction: controller.retry,
        );
      case RoomStage.playing:
        break;
    }
    return switch (playback.status) {
      PlaybackStatus.idle ||
      PlaybackStatus.opening ||
      PlaybackStatus.buffering => const _Message(icon: null, title: '', busy: true),
      PlaybackStatus.error => _Message(
        icon: Icons.error_outline_rounded,
        title: restricted ? restrictionReason(room.effectiveRestriction) : i18n('playback_failure_title'),
        subtitle: failureText(playback.error),
        action: i18n('retry'),
        onAction: controller.retry,
      ),
      PlaybackStatus.completed => _Message(
        icon: Icons.replay_rounded,
        title: i18n('live_play_replay_ended'),
        action: i18n('live_play_replay_again'),
        onAction: () => controller.session.seek(Duration.zero),
      ),
      PlaybackStatus.paused => const IgnorePointer(
        child: Center(child: Icon(Icons.pause_circle_outline_rounded, size: 56, color: Colors.white70)),
      ),
      PlaybackStatus.playing || PlaybackStatus.stopped => const SizedBox.shrink(),
    };
  }
}

class _Message extends StatelessWidget {
  const new({required this.icon, required this.title, this.subtitle, this.action, this.onAction, this.busy = false});

  final IconData? icon;
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The shade and texts let taps through to the picture (controls);
    // only the button takes them.
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(child: ColoredBox(color: busy ? Colors.transparent : Colors.black54)),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  const SizedBox.square(dimension: 36, child: CircularProgressIndicator(color: Colors.white70))
                else if (icon != null)
                  Icon(icon, color: Colors.white70, size: 40),
                if (title.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(color: Colors.white),
                  ),
                ],
                if (subtitle case final text? when text.isNotEmpty && text != title) ...[
                  const SizedBox(height: 4),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
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
        if (room.cover.trim().isNotEmpty)
          Opacity(
            opacity: 0.25,
            child: LiveNetworkImage(
              url: room.cover,
              placeholder: (_) => const SizedBox.shrink(),
              error: (_) => const SizedBox.shrink(),
            ),
          ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CommonAvatar(avatarUrl: room.avatar, radius: 28, fallbackName: room.nick),
              const SizedBox(height: 10),
              Text(offlineText(room), style: theme.textTheme.titleSmall?.copyWith(color: Colors.white)),
              const SizedBox(height: 4),
              Text(i18n('live_play_offline_hint'), style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: onRefresh, child: Text(i18n('refresh'))),
            ],
          ),
        ),
      ],
    );
  }
}

/// The control bars (3.x `VideoControllerPanel`, main buttons).
class _Controls extends ConsumerWidget {
  const new({
    required this.controller,
    required this.fullscreen,
    required this.showDanmaku,
    required this.onToggleFullscreen,
    required this.onBack,
    required this.onInteract,
  });

  final LiveRoomController controller;
  final bool fullscreen;
  final bool showDanmaku;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onBack;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const shade = [Colors.black54, Colors.transparent];
    final store = ref.read(storeProvider);
    return Column(
      children: [
        if (fullscreen)
          DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: shade),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  IconButton(
                    tooltip: i18n('exit_fullscreen'),
                    color: Colors.white,
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => Text(
                        controller.room.title.trim().isEmpty
                            ? controller.room.displayNick(platformName(controller.room.platform))
                            : controller.room.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const Spacer(),
        DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: shade),
          ),
          child: SafeArea(
            top: false,
            child: IconTheme(
              data: const IconThemeData(color: Colors.white),
              child: Row(
                children: [
                  StreamBuilder<PlaybackState>(
                    stream: controller.session.states,
                    initialData: controller.session.state,
                    builder: (context, snapshot) {
                      final paused = snapshot.data?.status == PlaybackStatus.paused;
                      return IconButton(
                        key: const ValueKey('live-play-pause'),
                        tooltip: i18n(paused ? 'live_play_play' : 'live_play_pause'),
                        onPressed: () {
                          onInteract();
                          unawaited(controller.session.togglePlayPause());
                        },
                        icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                      );
                    },
                  ),
                  IconButton(
                    key: const ValueKey('live-play-refresh'),
                    tooltip: i18n('live_play_refresh_room'),
                    onPressed: () {
                      onInteract();
                      unawaited(controller.load());
                    },
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    key: const ValueKey('live-play-danmaku-toggle'),
                    tooltip: i18n(showDanmaku ? 'live_play_hide_danmaku' : 'show_danmaku'),
                    onPressed: () {
                      onInteract();
                      unawaited(store.settings.set(Settings.hideDanmaku, showDanmaku));
                      if (!showDanmaku && !store.settings.get(Settings.enableDanmakuDisplay)) {
                        unawaited(store.settings.set(Settings.enableDanmakuDisplay, true));
                      }
                    },
                    icon: Icon(showDanmaku ? Icons.subtitles_rounded : Icons.subtitles_off_outlined),
                  ),
                  const Spacer(),
                  if (fullscreen)
                    ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => DefaultTextStyle.merge(
                        style: const TextStyle(color: Colors.white),
                        child: StreamPickers(controller: controller, onDark: true),
                      ),
                    ),
                  IconButton(
                    key: const ValueKey('live-play-fullscreen'),
                    tooltip: i18n(fullscreen ? 'exit_fullscreen' : 'live_play_fullscreen'),
                    onPressed: onToggleFullscreen,
                    icon: Icon(fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
