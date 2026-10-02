import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/buttons/room_menu_button.dart';
import 'package:pure_live/features/live_play/logic/reconnect_watch.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/logic/room_status.dart';
import 'package:pure_live/features/live_play/switch_room/room_switch_panel.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// A picture shorter than this is "short" (portrait 16:9): the state leaves
/// out its icon but keeps the streamer and the lock (U.2g note 10).
const double compactPictureHeight = 260;

/// The picture's state over the video (docs/ui/compare/U.2g): one
/// [VideoStateView] for loading, offline, failures, restrictions,
/// reconnecting, restoring and ended replays, in every layout. Words and
/// dimming let taps through to the picture; only the buttons take them. It
/// sits under the control bars, so they stay usable (c12).
///
/// The state itself comes from [pictureStateOf]; this layer adds the two
/// clocks the logic has no ticker for: "加载较慢" after [slowAfter] of
/// opening (c4) and "正在恢复实时画面" while the picture comes back from
/// audio only (c14).
class RoomStatusLayer extends StatefulWidget {
  /// Creates the layer.
  const new({required this.controller, required this.playback, required this.reconnect, super.key});

  /// The room.
  final LiveRoomController controller;

  /// The session's state.
  final PlaybackState playback;

  /// The drops of the stream.
  final ReconnectWatch reconnect;

  @override
  State<RoomStatusLayer> createState() => _RoomStatusLayerState();
}

class _RoomStatusLayerState extends State<RoomStatusLayer> {
  Timer? _slowTimer;
  bool _slow = false;
  Timer? _restoreTimer;
  bool _restoring = false;
  bool _audioOnly = false;

  LiveRoomController get _room => widget.controller;

  @override
  void initState() {
    super.initState();
    _audioOnly = _room.audioOnly;
    _armSlow();
  }

  @override
  void didUpdateWidget(RoomStatusLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final audioOnly = _room.audioOnly;
    if (_audioOnly && !audioOnly) {
      // Back to video: say so until a picture can be there (the session
      // reports no first frame, so at most three seconds or the next size).
      _restoring = true;
      _restoreTimer?.cancel();
      _restoreTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _restoring = false);
      });
    } else if (audioOnly) {
      _restoring = false;
      _restoreTimer?.cancel();
    }
    if (_restoring &&
        oldWidget.playback.videoWidth != widget.playback.videoWidth &&
        widget.playback.status == PlaybackStatus.playing) {
      _restoring = false;
      _restoreTimer?.cancel();
    }
    _audioOnly = audioOnly;
    _armSlow();
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _restoreTimer?.cancel();
    super.dispose();
  }

  /// A source is opening (no picture yet): a stall of a picture that is
  /// there is no opening, the session's own watchdog takes it over.
  bool get _opening =>
      _room.stage == RoomStage.playing &&
      !widget.reconnect.reconnecting &&
      !pictureBuffering(widget.playback) &&
      switch (widget.playback.status) {
        PlaybackStatus.idle || PlaybackStatus.opening || PlaybackStatus.buffering => true,
        _ => false,
      };

  /// Starts the "slow" clock when the stream starts opening, stops it when
  /// it is no longer opening.
  void _armSlow() {
    if (!_opening) {
      _slowTimer?.cancel();
      _slowTimer = null;
      _slow = false;
      return;
    }
    if (_slowTimer != null || _slow) return;
    _slowTimer = Timer(slowAfter, () {
      if (!mounted) return;
      setState(() {
        _slowTimer = null;
        _slow = _opening;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = pictureStateOf(
      stage: _room.stage,
      failure: _room.failure,
      room: _room.room,
      playback: widget.playback,
      reconnecting: widget.reconnect.reconnecting,
      attempts: widget.reconnect.attempts,
      audioOnly: _room.audioOnly,
      restoring: _restoring,
      slow: _slow,
    );
    return LayoutBuilder(
      builder: (context, constraints) => PictureStateView(
        key: ValueKey('live-play-state-${state.kind.name}'),
        state: state,
        controller: _room,
        compact: constraints.maxHeight < compactPictureHeight,
        onSwitchLine: () {
          final lines = widget.playback.lineCount;
          return _room.selectLine((widget.playback.lineIndex + 1) % (lines < 1 ? 1 : lines));
        },
      ),
    );
  }
}

/// One [PictureState] drawn with the [VideoStateView] (U.2g c2): its icon,
/// words, buttons and what lies under them.
class PictureStateView extends StatelessWidget {
  /// Creates the view.
  const new({
    required this.state,
    required this.controller,
    required this.onSwitchLine,
    this.compact = false,
    super.key,
  });

  /// The state.
  final PictureState state;

  /// The room (its cover, streamer and actions).
  final LiveRoomController controller;

  /// Plays the next line.
  final Future<void> Function() onSwitchLine;

  /// A short picture: no icon (the streamer and the lock stay).
  final bool compact;

  static IconData? _icon(PictureStateKind kind) => switch (kind) {
    PictureStateKind.detailFailed ||
    PictureStateKind.notFound ||
    PictureStateKind.playbackFailed => AppIcons.playbackError,
    PictureStateKind.banned => AppIcons.banned,
    PictureStateKind.statusUnknown => AppIcons.statusUnknown,
    PictureStateKind.noStream => AppIcons.noStream,
    PictureStateKind.replayEnded => AppIcons.playAgain,
    _ => null,
  };

  VideoStateAction _action(BuildContext context, PictureAction action) {
    final room = controller.room;
    return switch (action) {
      PictureAction.switchRoom => VideoStateAction(
        key: const ValueKey('live-play-state-switch-room'),
        label: i18n('switch_live_room'),
        icon: AppIcons.switchRoom,
        onPressed: () => showRoomSwitchPanel(context, controller),
      ),
      PictureAction.refresh => VideoStateAction(
        key: const ValueKey('live-play-state-refresh'),
        label: i18n('refresh'),
        icon: AppIcons.refresh,
        onPressed: controller.load,
      ),
      PictureAction.retry => VideoStateAction(
        key: const ValueKey('live-play-state-retry'),
        label: i18n('retry'),
        icon: AppIcons.refresh,
        onPressed: controller.retry,
      ),
      PictureAction.switchLine => VideoStateAction(
        key: const ValueKey('live-play-state-switch-line'),
        label: i18n('live_play_switch_line'),
        icon: AppIcons.switchLine,
        onPressed: onSwitchLine,
      ),
      PictureAction.login => VideoStateAction(
        key: const ValueKey('live-play-state-login'),
        label: i18n('live_play_go_login'),
        icon: AppIcons.login,
        onPressed: () async {
          // The platform's sign-in lives in the account page (U.10b decides
          // where exactly); back in the room it tries again.
          await AppNavigator.toNamed<void>(RoutePath.kSettingsAccount);
          await controller.retry();
        },
      ),
      PictureAction.openInPlatform => VideoStateAction(
        key: const ValueKey('live-play-state-open'),
        label: i18n('live_play_open_in', args: {'platform': platformName(room.platform)}),
        icon: AppIcons.openExternal,
        onPressed: () => openRoomExternally(room),
      ),
      PictureAction.playAgain => VideoStateAction(
        key: const ValueKey('live-play-state-play-again'),
        label: i18n('live_play_replay_again'),
        icon: AppIcons.playAgain,
        onPressed: () => controller.session.seek(Duration.zero),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    switch (state.kind) {
      case PictureStateKind.none || PictureStateKind.audioOnly:
        return const SizedBox.shrink();
      case PictureStateKind.paused:
        // The play mark (what a tap does, as on the play key) on its disc;
        // it resumes (A-01, B02 c2: the in-app floating window's button).
        return Center(
          child: VideoCentreButton(
            key: const ValueKey('picture-paused-play'),
            tooltip: i18n('live_play_play'),
            onPressed: () => unawaited(controller.session.togglePlayPause()),
          ),
        );
      case PictureStateKind.buffering:
        // The same disc turns while the picture waits for data (B02 c2).
        return Center(
          child: IgnorePointer(
            child: VideoCentreButton(
              key: const ValueKey('picture-buffering'),
              tooltip: i18n('live_play_buffering'),
              busy: true,
            ),
          ),
        );
      case PictureStateKind.entering ||
          PictureStateKind.connecting ||
          PictureStateKind.slow ||
          PictureStateKind.offline ||
          PictureStateKind.banned ||
          PictureStateKind.carousel ||
          PictureStateKind.statusUnknown ||
          PictureStateKind.detailFailed ||
          PictureStateKind.notFound ||
          PictureStateKind.restricted ||
          PictureStateKind.noStream ||
          PictureStateKind.playbackFailed ||
          PictureStateKind.reconnecting ||
          PictureStateKind.restoring ||
          PictureStateKind.replayEnded:
        break;
    }
    final Widget? leading = switch (state.kind) {
      PictureStateKind.offline || PictureStateKind.carousel => VideoStateAvatar(
        size: compact ? 40 : 48,
        child: CommonAvatar(avatarUrl: room.avatar, radius: compact ? 20 : 24, fallbackName: room.nick),
      ),
      // The lock stays on a short picture too (U.2g note 10).
      PictureStateKind.restricted => const Icon(
        AppIcons.restricted,
        key: ValueKey('video-state-lock'),
        size: 32,
        color: OnVideoColors.secondary,
      ),
      _ => null,
    };
    final view = VideoStateView(
      busy: state.busy,
      icon: _icon(state.kind),
      leading: leading,
      title: state.title,
      reason: state.reason,
      compact: compact,
      dim: switch (state.dim) {
        PictureDim.light => OnVideoColors.dimLight,
        PictureDim.heavy => OnVideoColors.scrim,
        PictureDim.none || PictureDim.cover => null,
      },
      actions: [for (final action in state.actions) _action(context, action)],
    );
    if (state.dim != PictureDim.cover) return view;
    return Stack(
      fit: StackFit.expand,
      children: [
        const IgnorePointer(child: ColoredBox(color: OnVideoColors.ground)),
        IgnorePointer(child: _DimmedCover(url: room.cover)),
        view,
      ],
    );
  }
}

/// E5: the picture of an audio-only room: its cover under a dark veil, the
/// headphone and "纯音频播放中" (3.x showed the streamer's picture with
/// opacity, a colour filter, a blurred glow and a zoom; U.2g c14 drops them).
/// [paused] (B-9): the status layer's play mark takes the middle and
/// "纯音频已暂停" sits under it.
class AudioOnlyCover extends StatelessWidget {
  /// Creates the cover of [room].
  const new({required this.room, this.paused = false, super.key});

  /// The room.
  final LiveRoom room;

  /// The sound is paused.
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge?.regular.copyWith(color: OnVideoColors.secondary);
    return Stack(
      key: const ValueKey('live-play-audio-cover'),
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: OnVideoColors.ground),
        _DimmedCover(url: room.cover),
        if (paused)
          // Under the mark, which is in the middle of the same area.
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) => Padding(
                padding: EdgeInsets.only(top: constraints.maxHeight / 2 + videoCentreButtonSize / 2 + 8),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Text(
                    i18n('live_play_audio_only_paused'),
                    key: const ValueKey('live-play-audio-paused'),
                    style: style,
                  ),
                ),
              ),
            ),
          )
        else
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(AppIcons.audioOnlyActive, color: OnVideoColors.secondary, size: 40),
                const SizedBox(height: 8),
                Text(i18n('live_play_audio_only_playing'), style: style),
              ],
            ),
          ),
      ],
    );
  }
}

/// The replay mark on the picture (U.2g c18): "回看 19:30" and "返回直播", in
/// the top-left corner whether the controls show or not. A tap on the time
/// opens the guide ([onOpenGuide]); "返回直播" goes back to the channel.
class CatchupBadge extends StatelessWidget {
  /// Creates the mark for [controller].
  const new({required this.controller, this.onOpenGuide, super.key});

  /// The room.
  final LiveRoomController controller;

  /// Opens or reveals the guide.
  final VoidCallback? onOpenGuide;

  @override
  Widget build(BuildContext context) => ListenableSelector<EpgProgramme?>(
    listenable: controller,
    selector: () => controller.catchup,
    builder: (context, programme, _) {
      if (programme == null) return const SizedBox.shrink();
      final theme = Theme.of(context);
      final start = programme.start.toLocal();
      String two(int value) => value.toString().padLeft(2, '0');
      final style = theme.textTheme.bodyMedium?.emphasis.tabular;
      return Material(
        key: const ValueKey('live-play-catchup-badge'),
        color: OnVideoColors.scrim,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onOpenGuide,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(AppIcons.catchup, size: 16, color: OnVideoColors.foreground),
                const SizedBox(width: 5),
                Text(
                  i18n('live_play_catchup_badge', args: {'time': '${two(start.hour)}:${two(start.minute)}'}),
                  style: style?.copyWith(color: OnVideoColors.foreground),
                ),
                const SizedBox(width: 6),
                Material(
                  color: OnVideoColors.foreground,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    key: const ValueKey('live-play-catchup-back'),
                    customBorder: const StadiumBorder(),
                    onTap: () => unawaited(controller.backToLive()),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      child: Text(i18n('return_to_live'), style: style?.copyWith(color: OnVideoColors.buttonInk)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
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
