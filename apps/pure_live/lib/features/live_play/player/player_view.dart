import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/dialogs/player_dialogs.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/local_gift_effect.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/features/live_play/logic/mini_window.dart';
import 'package:pure_live/features/live_play/logic/reconnect_watch.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/logic/room_status.dart';
import 'package:pure_live/features/live_play/mini/mini_player.dart';
import 'package:pure_live/features/live_play/mini/room_mini_window.dart';
import 'package:pure_live/features/live_play/player/player_controls.dart';
import 'package:pure_live/features/live_play/player/player_gestures.dart';
import 'package:pure_live/features/live_play/player/player_status.dart';
import 'package:pure_live/features/live_play/player/recording_badge.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings.dart';

export 'package:pure_live/features/live_play/dialogs/player_dialogs.dart' show videoFits;

/// The video with its danmaku, status and controls (3.x `VideoPlayer` +
/// `VideoControllerPanel`, the playback part).
///
/// The picture, the flying danmaku and the controls each draw on their own
/// layer (UI_PLAN §7.2): showing or hiding the controls, a ticking clock or
/// a new audience number never repaints the picture or the danmaku.
class RoomPlayer extends ConsumerStatefulWidget {
  /// Creates the player area.
  const new({
    required this.controller,
    required this.fullscreen,
    required this.onToggleFullscreen,
    required this.onBack,
    required this.orientation,
    required this.reconnect,
    this.pip = false,
    this.mobile = false,
    this.android = false,
    this.onOpenGuide,
    super.key,
  });

  /// Opens or reveals the IPTV guide (the replay mark, U.2g c18).
  final VoidCallback? onOpenGuide;

  /// In a mini window (U.2j): Android's picture-in-picture (only the
  /// picture, the "小窗弹幕" and the recording mark) or the desktop mini
  /// window (with its buttons), as the page's `RoomMiniScope` says.
  final bool pip;

  /// A phone: the lock and orientation buttons.
  final bool mobile;

  /// Android: cast and picture-in-picture.
  final bool android;

  /// The room.
  final LiveRoomController controller;

  /// Whether the player fills the screen.
  final bool fullscreen;

  /// Enters or leaves fullscreen.
  final VoidCallback onToggleFullscreen;

  /// Leaves fullscreen (the fullscreen top bar's back).
  final VoidCallback onBack;

  /// The room's orientation choice.
  final RoomOrientationChoice orientation;

  /// The stream's drops (E3).
  final ReconnectWatch reconnect;

  @override
  ConsumerState<RoomPlayer> createState() => _RoomPlayerState();
}

class _RoomPlayerState extends ConsumerState<RoomPlayer> {
  bool _controls = true;
  bool _locked = false;
  Timer? _hide;

  /// Menus of the bars that are open, and the room's panels: the controls
  /// do not hide by themselves meanwhile (U.2f, 统一规则).
  int _menus = 0;
  RoomPanelController? _panels;

  /// Whether the picture's mini window button shows (U.2j: Android's
  /// picture-in-picture or the desktop mini window).
  late final Future<bool> _pipSupported = RoomMiniScope.maybeOf(context)?.supported() ?? Future.value(false);

  /// The picture keeps its element (and its texture) when picture-in-picture
  /// swaps the layout around it (M13.16).
  final GlobalKey _video = GlobalKey(debugLabel: 'room-video');

  LiveRoomController get _room => widget.controller;

  /// What the status layer follows: the room's stage and the stream's drops.
  late final Listenable _statusSources = Listenable.merge([widget.controller, widget.reconnect]);

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void didUpdateWidget(RoomPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The lock is a fullscreen control: leaving fullscreen (Back works while
    // locked) releases it, or its unlock button stayed on the left of the
    // normal picture with the gestures off (M13.16).
    if (oldWidget.fullscreen && !widget.fullscreen) _locked = false;
    // Entering or leaving fullscreen shows the controls for a while, as a
    // new player did before the player kept its state.
    if (oldWidget.fullscreen != widget.fullscreen && !widget.pip) {
      _controls = true;
      _scheduleHide();
    }
    if (oldWidget.pip == widget.pip) return;
    if (widget.pip) {
      // Picture-in-picture has no controls: nothing to hide meanwhile.
      _hide?.cancel();
      return;
    }
    // Back from picture-in-picture (M13.16: the controls stayed on screen and
    // ignored taps until the room was left): the controls start afresh, a
    // lock from before is released, and a frame is drawn at once even if
    // the window's lifecycle report is still on its way.
    _controls = true;
    _locked = false;
    _scheduleHide();
    SchedulerBinding.instance.scheduleForcedFrame();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final panels = RoomPanelScope.maybeOf(context);
    if (identical(panels, _panels)) return;
    _panels?.removeListener(_scheduleHide);
    _panels = panels?..addListener(_scheduleHide);
  }

  @override
  void dispose() {
    _hide?.cancel();
    _panels?.removeListener(_scheduleHide);
    super.dispose();
  }

  bool get _holding => _menus > 0 || _panels?.value != null;

  void _onMenu(bool open) {
    _menus = (_menus + (open ? 1 : -1)).clamp(0, 8);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hide?.cancel();
    if (_holding) return;
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

  void _toggleLock() {
    setState(() => _locked = !_locked);
    _scheduleHide();
  }

  Future<void> _enterPip() async {
    await RoomMiniScope.maybeOf(context)?.enter(context);
  }

  Widget _danmaku({required DanmakuLook look, required bool visible}) => RepaintBoundary(
    child: DanmakuOverlay(messages: _room.flying, retractions: _room.retractions, look: look, visible: visible),
  );

  @override
  Widget build(BuildContext context) {
    final fit = videoFits[watchSetting(ref, Settings.videoFitIndex).clamp(0, videoFits.length - 1)];
    final pip = widget.pip;
    final hidden = watchSetting(ref, Settings.hideDanmaku);
    final display = watchSetting(ref, Settings.enableDanmakuDisplay);
    final showDanmaku = display && !hidden && (!pip || watchSetting(ref, Settings.enablePipDanmaku));
    final portraitDanmaku = watchSetting(ref, Settings.portraitDanmakuMode);
    final look = danmakuLookOf(ref);
    final video = RepaintBoundary(
      child: LiveVideoView(key: _video, session: _room.session, fit: fit),
    );
    if (pip) {
      // U.2j: the same surface as the in-app floating window; the picture
      // keeps its element.
      final mini = RoomMiniScope.maybeOf(context);
      final desktop = mini?.desktop ?? false;
      return MiniPlayerSurface(
        controller: _room,
        reconnect: widget.reconnect,
        video: video,
        kind: desktop ? MiniKind.desktop : MiniKind.systemPip,
        onBackToRoom: mini == null ? null : () => unawaited(mini.backToRoom()),
        onClose: mini == null ? null : () => unawaited(mini.close()),
        pinned: watchSetting(ref, Settings.windowsPipAlwaysOnTop),
        canPin: mini?.canPin ?? false,
        onPin: mini == null ? null : () => unawaited(mini.togglePin()),
        onDragStart: desktop ? (_) => unawaited(DesktopWindow.startDragging()) : null,
      );
    }
    return ColoredBox(
      color: OnVideoColors.ground,
      child: MouseRegion(
        onHover: (_) => _touch(),
        // Only the picture takes the double tap: on the buttons it would
        // hold every tap back by the double-tap timeout.
        child: Stack(
          fit: StackFit.expand,
          children: [
            PlayerGestureLayer(
              controller: _room,
              enabled: !_locked,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                onDoubleTap: _locked ? null : widget.onToggleFullscreen,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    video,
                    ListenableSelector<bool>(
                      listenable: _room,
                      selector: () => _room.audioOnly,
                      builder: (context, audioOnly, _) =>
                          audioOnly ? AudioOnlyCover(room: _room.room) : const SizedBox.shrink(),
                    ),
                    ListenableBuilder(
                      listenable: widget.orientation,
                      builder: (context, _) => StreamBuilder<PlaybackState>(
                        stream: _room.session.states,
                        initialData: _room.session.state,
                        builder: (context, snapshot) {
                          final portrait = isPortraitLayout(
                            widget.orientation.value,
                            detected: snapshot.data?.isPortrait ?? false,
                          );
                          return _danmaku(
                            look: portrait ? _portraitLook(look, portraitDanmaku) : look,
                            visible: showDanmaku && !(portrait && portraitDanmaku == 'hidden'),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // U.2g: the picture's state, one component in every layout.
            ListenableSelector<(RoomStage, Object?, LiveStatus, LiveRestriction, String, bool, int, bool)>(
              listenable: _statusSources,
              selector: () {
                final room = _room.room;
                return (
                  _room.stage,
                  _room.failure,
                  room.effectiveLiveStatus,
                  room.effectiveRestriction,
                  room.cover,
                  widget.reconnect.reconnecting,
                  widget.reconnect.attempts,
                  _room.audioOnly,
                );
              },
              builder: (context, _, _) => StreamBuilder<PlaybackState>(
                stream: _room.session.states,
                initialData: _room.session.state,
                builder: (context, snapshot) => RoomStatusLayer(
                  controller: _room,
                  playback: snapshot.data ?? _room.session.state,
                  reconnect: widget.reconnect,
                ),
              ),
            ),
            // U.2k c9: the local gift banner, on its own layer in the middle
            // of the picture.
            if (LocalRoomScope.maybeOf(context) case final local?)
              LocalGiftLayer(session: local, fullscreen: widget.fullscreen),
            // The recording mark stays in the corner while the controls are
            // hidden (dot and time only); with them it sits in the top bar.
            if (!_controls || _locked)
              Positioned(
                left: 12,
                top: 10 + (widget.fullscreen ? MediaQuery.paddingOf(context).top : 0),
                child: IgnorePointer(child: RoomRecordingBadge(room: _room.room, compact: true)),
              ),
            // U.2g c18: the replay mark stays whether the controls show or not.
            Positioned(
              left: 10,
              top: 52 + (widget.fullscreen ? MediaQuery.paddingOf(context).top : 0),
              child: CatchupBadge(controller: _room, onOpenGuide: widget.onOpenGuide),
            ),
            RepaintBoundary(
              child: AnimatedOpacity(
                opacity: _controls ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_controls,
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: IconTheme(
                      data: OnVideoColors.icons,
                      child: _locked
                          ? _LockLayer(onUnlock: _toggleLock)
                          // U.2g c5, c6: no bars while nothing plays (the
                          // state's buttons are the way on); fullscreen
                          // keeps a reduced top bar to leave it.
                          : ListenableSelector<bool>(
                              listenable: _room,
                              selector: () => pictureHasControls(_room.stage),
                              builder: (context, controls, _) => Column(
                                children: [
                                  if (controls || widget.fullscreen)
                                    PlayerTopBar(
                                      controller: _room,
                                      fullscreen: widget.fullscreen,
                                      android: widget.android,
                                      pipSupported: _pipSupported,
                                      onBack: widget.onBack,
                                      onPip: () => unawaited(_enterPip()),
                                      onInteract: _scheduleHide,
                                      reduced: !controls,
                                    ),
                                  const Spacer(),
                                  if (controls)
                                    PlayerBottomBar(
                                      controller: _room,
                                      fullscreen: widget.fullscreen,
                                      mobile: widget.mobile,
                                      showDanmaku: showDanmaku,
                                      orientation: widget.orientation,
                                      onToggleFullscreen: widget.onToggleFullscreen,
                                      onInteract: _scheduleHide,
                                      onReopen: widget.reconnect.expectReopen,
                                      onLock: widget.mobile && widget.fullscreen ? _toggleLock : null,
                                      onMenu: _onMenu,
                                    ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [look] for a portrait stream (3.x `PortraitDanmakuMode`): the upper
/// quarter, or a smaller font over half the picture.
DanmakuLook _portraitLook(DanmakuLook look, String mode) => switch (mode) {
  'upperQuarter' => _scaled(look, look.fontSize, look.area.clamp(0, 0.25).toDouble()),
  'reduced' => _scaled(look, (look.fontSize * 0.85).roundToDouble(), look.area.clamp(0, 0.5).toDouble()),
  _ => look,
};

DanmakuLook _scaled(DanmakuLook look, double fontSize, double area) => DanmakuLook(
  fontSize: fontSize,
  fontWeight: look.fontWeight,
  speed: look.speed,
  opacity: look.opacity,
  area: area,
  topMargin: look.topMargin,
  bottomMargin: look.bottomMargin,
  stroke: look.stroke,
  strokeWidth: look.strokeWidth,
);

/// The locked controls: only the unlock button (3.x `showLocked`).
class _LockLayer extends StatelessWidget {
  const new({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: IconButton.filledTonal(
        key: const ValueKey('live-play-unlock'),
        tooltip: i18n('live_play_unlock'),
        onPressed: onUnlock,
        icon: const Icon(AppIcons.locked),
      ),
    ),
  );
}
