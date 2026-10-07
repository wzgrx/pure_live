import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/danmaku/message_panel.dart';
import 'package:pure_live/features/live_play/dialogs/player_dialogs.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/local_gift_effect.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/features/live_play/logic/mini_window.dart';
import 'package:pure_live/features/live_play/logic/reconnect_watch.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/logic/room_layout.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/logic/room_status.dart';
import 'package:pure_live/features/live_play/mini/mini_player.dart';
import 'package:pure_live/features/live_play/mini/room_mini_window.dart';
import 'package:pure_live/features/live_play/player/bar_parts.dart';
import 'package:pure_live/features/live_play/player/player_controls.dart';
import 'package:pure_live/features/live_play/player/player_gestures.dart';
import 'package:pure_live/features/live_play/player/player_status.dart';
import 'package:pure_live/features/live_play/player/portrait_diagnostics.dart';
import 'package:pure_live/features/live_play/player/recording_badge.dart';
import 'package:pure_live/features/live_play/player/room_swipe.dart';
import 'package:pure_live/platform/display_mode.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings.dart';
import 'package:pure_live/shared/danmaku/danmaku_templates.dart';
import 'package:pure_live/shared/danmaku/emotes.dart';

export 'package:pure_live/features/live_play/dialogs/player_dialogs.dart' show videoFits;

/// How the picture itself is drawn (docs/A-界面设计/A07-直播间界面/A07.2-竖屏流和竖屏全屏).
enum PicturePresentation {
  /// The stream as the "画面比例" setting fits it, on black.
  plain,

  /// A portrait stream in the middle, the ambient background on both sides
  /// (landscape fullscreen, the wide room; change 13).
  ambient,

  /// A portrait stream in the portrait fullscreen, as the "竖屏全屏画面模式"
  /// setting says.
  portraitModes,
}

/// The video with its danmaku, status and controls (3.x `VideoPlayer` +
/// `VideoControllerPanel`, the playback part): one control layer with three
/// arrangements ([ControlsArrangement]; U.2b-U.2d).
///
/// The picture fills the player; the danmaku, the status, the gestures and
/// the controls only take the part above [overlayBottom] (the portrait
/// room's panel covers the rest, U.2b change 2). The picture, the flying
/// danmaku and the controls each draw on their own layer (UI_PLAN §9.2):
/// showing or hiding the controls, a ticking clock or a new audience number
/// never repaints the picture or the danmaku. The status layer is the
/// picture's one place for loading, offline, reconnecting and the rest
/// (U.2g fills it).
class RoomPlayer extends ConsumerStatefulWidget {
  /// Creates the player area.
  const new({
    required this.controller,
    required this.display,
    required this.arrangement,
    required this.onToggleFullscreen,
    required this.onBack,
    required this.orientation,
    required this.reconnect,
    this.platform = const RoomPlatform(TargetPlatform.android),
    this.pip = false,
    this.portraitStream = false,
    this.presentation = PicturePresentation.plain,
    this.overlayBottom = 0,
    this.wide,
    this.onWindowFullscreen,
    this.onSwipeUp,
    this.entryHint = false,
    this.onOpenGuide,
    this.swipe,
    this.edge,
    this.onTitle,
    this.pickersInBar = false,
    this.alignment = Alignment.center,
    super.key,
  });

  /// A phone held sideways (A07.17 c2): the title shows the figures and
  /// opens or closes the room details ([PlayerBarActions.onTitle]).
  final VoidCallback? onTitle;

  /// The quality and line buttons in the inline bottom bar (A07.17 c2).
  final bool pickersInBar;

  /// Where the picture sits in the player: at the top under the portrait
  /// room's panel (A07.17 c3: centred, a portrait picture left a black
  /// strip above it and hid as much under the panel), else in the middle.
  final Alignment alignment;

  /// On the middle of the right edge, shown and hidden with the controls:
  /// the wide room's handle that folds the chat or guide column (B09 c5,
  /// audit B-19: always there, it took the volume drag and the danmaku
  /// taps on that edge).
  final Widget? edge;

  /// The portrait fullscreen's swipe between rooms (U.2b2): the middle third
  /// of the picture drags it; null without one.
  final RoomSwipeController? swipe;

  /// Opens or reveals the IPTV guide (the replay mark, U.2g c18).
  final VoidCallback? onOpenGuide;

  /// The room.
  final LiveRoomController controller;

  /// How the room is shown.
  final RoomDisplay display;

  /// The controls' arrangement.
  final ControlsArrangement arrangement;

  /// The platform.
  final RoomPlatform platform;

  /// In a mini window (U.2j): Android's picture-in-picture (only the
  /// picture, the "小窗弹幕" and the recording mark) or the desktop mini
  /// window (with its buttons), as the page's `RoomMiniScope` says.
  final bool pip;

  /// The stream is laid out as portrait.
  final bool portraitStream;

  /// How the picture is drawn.
  final PicturePresentation presentation;

  /// The part of the player covered from below (the portrait panel).
  final double overlayBottom;

  /// The wide room's extras of the bottom bar.
  final WideBarActions? wide;

  /// Desktops: the in-window fullscreen.
  final VoidCallback? onWindowFullscreen;

  /// Enters or leaves fullscreen (the button and double tap).
  final VoidCallback onToggleFullscreen;

  /// The fullscreen bars' back.
  final VoidCallback onBack;

  /// The portrait fullscreen: an upward swipe at the bottom brings the
  /// panel back.
  final VoidCallback? onSwipeUp;

  /// Shows "已进入竖屏全屏 · 上滑恢复弹幕栏" for three seconds when the
  /// portrait fullscreen opens.
  final bool entryHint;

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
  int _hintEpoch = 0;
  Timer? _hide;

  /// The stream is paused: the controls stay on (B02 c1).
  bool _paused = false;
  StreamSubscription<PlaybackState>? _playback;

  /// Menus of the bars that are open, a focused composer and the room's
  /// panels: the controls do not hide by themselves meanwhile (U.2f,
  /// 统一规则).
  int _menus = 0;
  RoomPanelController? _panels;

  /// Whether the picture's mini window button shows (U.2j: Android's
  /// picture-in-picture or the desktop mini window).
  late final Future<bool> _pipSupported = RoomMiniScope.maybeOf(context)?.supported() ?? Future.value(false);

  /// The picture keeps its element (and its texture) when picture-in-picture
  /// or a presentation swaps the layout around it (M13.16).
  final GlobalKey _video = GlobalKey(debugLabel: 'room-video');

  /// The flying danmaku, asked what a tap hits (F.2b).
  final GlobalKey<DanmakuOverlayState> _flying = GlobalKey(debugLabel: 'room-danmaku');

  /// A flying danmaku's actions are open: the danmaku stand (U.2h c9).
  bool _danmakuHeld = false;

  /// The flying danmaku under the last tap when it went down (the danmaku
  /// moves on before the tap ends).
  LiveMessage? _tapHit;

  /// Where the last tap went down.
  Offset? _tapAt;

  /// B09 c1 (audit B-8): a tap acts at once instead of waiting out the
  /// double tap's timeout; a second tap within [kDoubleTapTimeout] and
  /// [kDoubleTapSlop] of it takes the first one back ([_undoTap]) and
  /// toggles the fullscreen. Open while this runs.
  Timer? _doubleTapWindow;
  Offset? _firstTapAt;
  VoidCallback? _undoTap;

  /// The controls a tap just showed take no taps while a second one may
  /// come: a double tap near the bars would press the button that appeared
  /// under it (they used to show only after the timeout).
  bool _controlsSettling = false;

  /// The platform's bundled emoticons, flown as pictures (U.2h c1).
  EmoteTable _emotes = EmoteTable.empty;

  LiveRoomController get _room => widget.controller;

  /// What the status layer follows: the room's stage and the stream's drops.
  late final Listenable _statusSources = Listenable.merge([widget.controller, widget.reconnect]);

  bool get _inline => widget.display == RoomDisplay.inline;

  @override
  void initState() {
    super.initState();
    if (widget.entryHint) _hintEpoch++;
    _paused = _room.session.state.status == PlaybackStatus.paused;
    _playback = _room.session.states.listen(_onPlayback);
    _scheduleHide();
    // The bundled emoticons, read once per platform (as the chat list).
    final library = ref.read(emoteLibraryProvider);
    final platform = _room.site.id;
    _emotes = library.tableOf(platform);
    if (_emotes.codes.isEmpty) {
      unawaited(
        library.load(platform).then((table) {
          if (mounted && table.codes.isNotEmpty) setState(() => _emotes = table);
        }),
      );
    }
  }

  @override
  void didUpdateWidget(RoomPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The lock is a fullscreen control: leaving fullscreen (Back works while
    // locked) releases it, or its unlock button stayed on the normal picture
    // with the gestures off (M13.16).
    if (widget.arrangement == ControlsArrangement.inline) _locked = false;
    if (widget.entryHint && !oldWidget.entryHint) _hintEpoch++;
    // Entering or leaving fullscreen shows the controls for a while, as a
    // new player did before the player kept its state.
    if (oldWidget.display != widget.display && !widget.pip) {
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
    _doubleTapWindow?.cancel();
    unawaited(_playback?.cancel());
    _panels?.removeListener(_scheduleHide);
    super.dispose();
  }

  /// B02 c1: pausing shows the controls and keeps them (however the stream
  /// was paused: the play key, the notification, a headset); playing again
  /// lets them hide as usual.
  void _onPlayback(PlaybackState state) {
    final paused = state.status == PlaybackStatus.paused;
    if (paused == _paused || !mounted) return;
    _paused = paused;
    if (widget.pip) return;
    if (paused) {
      _hide?.cancel();
      if (!_controls) setState(() => _controls = true);
    } else {
      _scheduleHide();
    }
  }

  bool get _holding => _menus > 0 || _panels?.value != null;

  void _onMenu(bool open) {
    _menus = (_menus + (open ? 1 : -1)).clamp(0, 8);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hide?.cancel();
    // B02 c1: paused, the controls stay until a tap hides them.
    if (_holding || _paused) return;
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controls = false);
    });
  }

  /// A tap on the picture (appendix A 1): on phones it hides visible
  /// controls while playing or paused and shows them otherwise; on desktops
  /// it only shows them. It never resumes a paused stream: the play key and
  /// the picture's play mark do (a stray tap used to start it again).
  /// Paused, the controls stay until a tap hides them (B02 c1), so the
  /// still picture can be seen without them.
  ///
  /// A tap on a flying danmaku (its switch on) opens its actions instead,
  /// but only while the controls show and the stream is not paused (D-038).
  ///
  /// B09 c1 (audit B-8): the tap acts at once (3.x, and 4.0.0, held every
  /// tap back by the double tap's timeout, about 300 ms). A second tap
  /// within that time and near the first is the double tap (appendix A 3,
  /// not while locked): it takes the first tap back and toggles the
  /// fullscreen.
  void _onTap() {
    final hit = _tapHit;
    final at = _tapAt;
    _tapHit = null;
    _tapAt = null;
    final first = _firstTapAt;
    if ((_doubleTapWindow?.isActive ?? false) &&
        !_locked &&
        at != null &&
        first != null &&
        (at - first).distance <= kDoubleTapSlop) {
      final undo = _undoTap;
      _closeDoubleTap();
      undo?.call();
      widget.onToggleFullscreen();
      return;
    }
    _closeDoubleTap();
    final shownBefore = _controls;
    // D-038 (A08.9): with many danmaku nearly every tap lands on one, so a
    // tap brings hidden controls whatever it lands on; a flying danmaku
    // opens its actions only while they show (gone the moment they start
    // to fade), and never while paused (A07.10: the tap only shows or hides
    // them).
    final message = shownBefore && !_paused ? hit : null;
    final undo = message != null ? _tapMessage(message) : _tapControls();
    if (_locked || at == null) return;
    _firstTapAt = at;
    _undoTap = undo;
    if (!shownBefore && _controls) setState(() => _controlsSettling = true);
    _doubleTapWindow = Timer(kDoubleTapTimeout, _closeDoubleTap);
  }

  void _closeDoubleTap() {
    _doubleTapWindow?.cancel();
    _doubleTapWindow = null;
    _firstTapAt = null;
    _undoTap = null;
    if (_controlsSettling && mounted) setState(() => _controlsSettling = false);
  }

  /// A tap's effect on the controls (see [_onTap]); returns what puts them
  /// back as they were.
  VoidCallback _tapControls() {
    final before = _controls;
    final status = _room.session.state.status;
    final shown = status == PlaybackStatus.playing || status == PlaybackStatus.paused;
    if (widget.platform.mobile && _controls && (shown || _locked)) {
      setState(() => _controls = false);
    } else {
      if (!_controls) setState(() => _controls = true);
      _scheduleHide();
    }
    return () {
      if (!mounted || _controls == before) return;
      setState(() => _controls = before);
      if (before) _scheduleHide();
    };
  }

  /// A tap on a flying danmaku opens its actions at once; returns what
  /// closes them again.
  VoidCallback _tapMessage(LiveMessage message) {
    unawaited(_openMessage(message));
    return () {
      final panels = mounted ? RoomPanelScope.maybeOf(context) : null;
      if (panels != null && panels.value == RoomPanelKind.message && identical(panels.message, message)) {
        panels.close();
      }
    };
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

  /// The flying danmaku a tap or long press at [global] hits (F.2b, 3.x
  /// `handleDanmakuPointer`): only with the gesture's switch on, not on the
  /// bars while the controls show, not while locked.
  LiveMessage? _danmakuAt(Offset global, {required bool longPress}) {
    if (_locked) return null;
    final settings = ref.read(storeProvider).settings;
    if (!settings.get(longPress ? Settings.enableDanmakuLongPressInteraction : Settings.enableDanmakuTapInteraction)) {
      return null;
    }
    final flying = _flying.currentState;
    final box = flying?.context.findRenderObject();
    if (flying == null || box is! RenderBox || !box.hasSize) return null;
    final local = box.globalToLocal(global);
    final padding = MediaQuery.paddingOf(context);
    final (top, bottom) = switch (widget.arrangement) {
      ControlsArrangement.inline => (controlBarHeight, controlBarHeight),
      ControlsArrangement.landscape => (padding.top + controlBarHeight, padding.bottom + controlBarHeight),
      ControlsArrangement.portraitFullscreen => (
        padding.top + 4 + portraitRowHeight * 2,
        padding.bottom + 8 + portraitRowHeight * 2,
      ),
    };
    if (!danmakuTapAllowed(local: local, size: box.size, controlsVisible: _controls, top: top, bottom: bottom)) {
      return null;
    }
    return flying.messageAt(local);
  }

  /// The message's actions (U.2f 长按弹幕); the danmaku stand meanwhile
  /// (3.x paused the barrage until the sheet closed).
  Future<void> _openMessage(LiveMessage message) async {
    setState(() => _danmakuHeld = true);
    try {
      await showRoomMessageActions(context, _room, message);
    } finally {
      if (mounted) setState(() => _danmakuHeld = false);
    }
  }

  /// The flying danmaku, kept inside the picture: they enter from beyond its
  /// right edge, which in the wide room is the chat column. They stand while
  /// the video does not play (U.2h c10; paused, as "暂停时的弹幕" says, B02 c3)
  /// and move at the danmaku frame rate as a whole fraction of the
  /// display's (c3).
  Widget _danmaku({
    required DanmakuLook look,
    required bool visible,
    required _FpsSettings fps,
    required String pausedBehavior,
  }) => ClipRect(
    child: RepaintBoundary(
      child: ValueListenableBuilder<DisplayModeInfo?>(
        valueListenable: DisplayMode.info,
        builder: (context, display, _) => StreamBuilder<PlaybackState>(
          stream: _room.session.states,
          initialData: _room.session.state,
          builder: (context, snapshot) => DanmakuOverlay(
            key: _flying,
            messages: _room.flying,
            retractions: _room.retractions,
            look: look,
            visible: visible,
            fps: resolvedDanmakuFps(
              automatic: fps.automatic,
              configured: fps.configured,
              mode: fps.mode,
              maxRefreshRate: display?.maxRefreshRate,
              currentRefreshRate: display?.currentRefreshRate,
            ),
            refreshRate: (display?.currentRefreshRate ?? 0) > 0 ? display!.currentRefreshRate : null,
            // B02 c3: paused, as "暂停时的弹幕" says.
            running: danmakuRunning((snapshot.data ?? _room.session.state).status, pausedBehavior),
            held: _danmakuHeld,
            emotes: _emotes,
          ),
        ),
      ),
    ),
  );

  /// The cover behind a portrait picture (3.x: the cover, else the avatar).
  String get _cover {
    final room = _room.room;
    return room.cover.trim().isNotEmpty ? room.cover : room.avatar;
  }

  /// The picture as [PicturePresentation] says.
  Widget _picture(BoxFit fit) {
    final presentation = widget.presentation;
    // F.1a: the screen stays on while it plays only with "屏幕常亮" on.
    final keepOn = watchSetting(ref, Settings.enableScreenKeepOn);
    if (presentation == PicturePresentation.plain) {
      return LiveVideoView(
        key: _video,
        session: _room.session,
        fit: fit,
        keepScreenOn: keepOn,
        alignment: widget.alignment,
      );
    }
    final mode = presentation == PicturePresentation.ambient
        ? PortraitDisplayMode.ambient
        : PortraitDisplayMode.of(watchSetting(ref, Settings.portraitFullscreenDisplayMode));
    final video = LiveVideoView(
      key: _video,
      session: _room.session,
      fit: mode == PortraitDisplayMode.cover ? BoxFit.cover : BoxFit.contain,
      // The ambient background shows around the picture.
      fill: OnVideoColors.clear,
      keepScreenOn: keepOn,
      alignment: widget.alignment,
    );
    return Stack(
      key: ValueKey('live-play-picture-${mode.name}'),
      fit: StackFit.expand,
      children: [
        if (mode == PortraitDisplayMode.ambient || mode == PortraitDisplayMode.balanced) AmbientBackdrop(cover: _cover),
        if (mode == PortraitDisplayMode.balanced)
          LayoutBuilder(
            builder: (context, constraints) => ClipRect(
              child: Transform.scale(
                scale: balancedScale(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  aspectRatio: _room.session.state.expectedAspectRatio ?? 9 / 16,
                ),
                child: video,
              ),
            ),
          )
        else
          video,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final fit = videoFits[watchSetting(ref, Settings.videoFitIndex).clamp(0, videoFits.length - 1)];
    final pip = widget.pip;
    final hidden = watchSetting(ref, Settings.hideDanmaku);
    final display = watchSetting(ref, Settings.enableDanmakuDisplay);
    final showDanmaku = display && !hidden && (!pip || watchSetting(ref, Settings.enablePipDanmaku));
    final portraitDanmaku = watchSetting(ref, Settings.portraitDanmakuMode);
    final look = danmakuLookOf(ref);
    final fps = (
      automatic: watchSetting(ref, Settings.danmakuAutoFps),
      configured: watchSetting(ref, Settings.danmakuFps),
      mode: watchSetting(ref, Settings.refreshRateMode),
    );
    final longPress = showDanmaku && watchSetting(ref, Settings.enableDanmakuLongPressInteraction);
    final diagnostics = watchSetting(ref, Settings.showPortraitDiagnostics);
    final pausedBehavior = watchSetting(ref, Settings.danmakuPausedBehavior);
    final video = RepaintBoundary(child: _picture(fit));
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
    final arrangement = widget.arrangement;
    final portraitRows = arrangement == ControlsArrangement.portraitFullscreen;
    final lockable = arrangement != ControlsArrangement.inline;
    final actions = PlayerBarActions(
      controller: _room,
      arrangement: arrangement,
      display: widget.display,
      platform: widget.platform,
      orientation: widget.orientation,
      showDanmaku: showDanmaku,
      portraitStream: widget.portraitStream,
      pipSupported: _pipSupported,
      onBack: widget.onBack,
      onToggleFullscreen: widget.onToggleFullscreen,
      onPip: () => unawaited(_enterPip()),
      onInteract: _scheduleHide,
      onMenu: _onMenu,
      onWindowFullscreen: widget.onWindowFullscreen,
      wide: widget.wide,
      onTitle: widget.onTitle,
      pickersInBar: widget.pickersInBar,
      overPanel: widget.overlayBottom > 0,
    );
    final padding = MediaQuery.paddingOf(context);
    final badgeTop = switch (arrangement) {
      ControlsArrangement.inline => 10.0,
      ControlsArrangement.landscape => padding.top + controlBarHeight + 8,
      ControlsArrangement.portraitFullscreen => padding.top + 4 + portraitRowHeight * 2 + 8,
    };
    var bottomBar = PlayerBottomBar(actions: actions) as Widget;
    if (portraitRows && widget.onSwipeUp != null) {
      bottomBar = _SwipeUpRegion(onSwipeUp: widget.onSwipeUp!, child: bottomBar);
    }
    // The status of the picture (loading, offline, reconnecting, ...): one
    // layer over the visible part of the picture (U.2g).
    final status = ListenableSelector<(RoomStage, Object?, LiveStatus, LiveRestriction, String, bool, int, bool)>(
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
    );
    final overlay = Stack(
      fit: StackFit.expand,
      children: [
        // The status layer sits inside the gestures: its views take taps
        // (their buttons), and a drag over them still reaches the gestures,
        // so a room still loading or off the air can be swiped past (U.2b2).
        PlayerGestureLayer(
          controller: _room,
          enabled: !_locked,
          onSwipeUp: portraitRows ? widget.onSwipeUp : null,
          swipe: portraitRows ? widget.swipe : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Only the picture takes the double tap; a tap acts at once
              // and a second one takes it back (B09 c1, [_onTap]).
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  _tapAt = details.globalPosition;
                  _tapHit = _danmakuAt(details.globalPosition, longPress: false);
                },
                onTap: _onTap,
                // F.2b: only with its switch on, so it never holds a drag back.
                onLongPressStart: longPress
                    ? (details) {
                        if (_danmakuAt(details.globalPosition, longPress: true) case final hit?) {
                          unawaited(_openMessage(hit));
                        }
                      }
                    : null,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ListenableSelector<bool>(
                      listenable: _room,
                      selector: () => _room.audioOnly,
                      builder: (context, audioOnly, _) => audioOnly
                          ? StreamBuilder<PlaybackState>(
                              stream: _room.session.states,
                              initialData: _room.session.state,
                              // B-9: "纯音频已暂停" under the play mark.
                              builder: (context, snapshot) => AudioOnlyCover(
                                room: _room.room,
                                paused: (snapshot.data ?? _room.session.state).status == PlaybackStatus.paused,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    _danmaku(
                      look: widget.portraitStream ? _portraitLook(look, portraitDanmaku) : look,
                      visible: showDanmaku && !(widget.portraitStream && portraitDanmaku == 'hidden'),
                      fps: fps,
                      pausedBehavior: pausedBehavior,
                    ),
                  ],
                ),
              ),
              status,
            ],
          ),
        ),
        // U.2k c9: the local gift banner, on its own layer in the middle of
        // the picture.
        if (LocalRoomScope.maybeOf(context) case final local?) LocalGiftLayer(session: local, fullscreen: !_inline),
        // U.2g c18: the replay mark stays whether the controls show or not.
        Positioned(
          left: 10 + (_inline ? 0 : padding.left),
          top: arrangement == ControlsArrangement.inline ? 52 : badgeTop,
          child: CatchupBadge(controller: _room, onOpenGuide: widget.onOpenGuide),
        ),
        // F.1d: "显示识别状态" (3.x: 12 from the left, 62 from the top).
        if (diagnostics)
          Positioned(
            left: 12 + (_inline ? 0 : padding.left),
            top: arrangement == ControlsArrangement.inline ? 62 : badgeTop + 30,
            child: PortraitDiagnosticsBadge(session: _room.session, orientation: widget.orientation),
          ),
        // The recording mark: in the inline title bar while the controls
        // show; under the fullscreen bars (U.2c), where the landscape bar's
        // record button carries a recording's time itself (U.2a2 c8); mark
        // and figure alone in the corner while they are hidden.
        if (!_controls || _locked)
          Positioned(
            key: const ValueKey('live-play-recording-corner'),
            // B09 c2 (audit B-10): clear of a cut-out on the left in
            // landscape, like the marks under the bars.
            left: 12 + (_inline ? 0 : padding.left),
            top: 10 + (_inline ? 0 : padding.top),
            child: IgnorePointer(child: RoomRecordingBadge(room: _room.room, compact: true)),
          )
        else if (arrangement != ControlsArrangement.inline)
          Positioned(
            left: 16 + padding.left,
            top: badgeTop,
            child: GestureDetector(
              key: const ValueKey('live-play-recording-mark'),
              behavior: HitTestBehavior.opaque,
              onTap: () => RoomPanelScope.maybeOf(context)?.open(RoomPanelKind.record),
              child: RoomRecordingBadge(
                room: _room.room,
                showsRecording: arrangement != ControlsArrangement.landscape || _room.site.id == SiteIds.iptv,
              ),
            ),
          ),
        RepaintBoundary(
          child: AnimatedOpacity(
            opacity: _controls ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_controls || _controlsSettling,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: IconTheme(
                  data: OnVideoColors.icons,
                  // U.2g c5, c6: no bars while nothing plays (the state's
                  // buttons are the way on); fullscreen keeps a reduced top
                  // bar to leave it.
                  child: ListenableSelector<bool>(
                    listenable: _room,
                    selector: () => pictureHasControls(_room.stage),
                    builder: (context, controls, _) => Stack(
                      fit: StackFit.expand,
                      children: [
                        // The bars on the edges: on a picture lower than the
                        // two (a 16:9 picture under 285 wide) their shades
                        // overlap instead of overflowing (B09 c3).
                        if (!_locked && (controls || arrangement != ControlsArrangement.inline))
                          Positioned(
                            left: 0,
                            top: 0,
                            right: 0,
                            child: PlayerTopBar(actions: controls ? actions : actions.reducedCopy()),
                          ),
                        if (!_locked && controls) Positioned(left: 0, right: 0, bottom: 0, child: bottomBar),
                        if (!_locked && widget.edge != null)
                          Positioned(right: 0, top: 0, bottom: 0, child: Center(child: widget.edge)),
                        // B-4: while locked the unlock button stays whatever
                        // the room does (off the air, failed), or nothing
                        // on screen could unlock it.
                        if (lockable && (controls || _locked))
                          Positioned(
                            right: 20 + padding.right,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: LockButton(locked: _locked, onPressed: _toggleLock),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (portraitRows && widget.entryHint && _hintEpoch > 0)
          PortraitEntryHint(key: ValueKey('hint-$_hintEpoch'), bottom: padding.bottom + 8 + portraitRowHeight * 2 + 16),
      ],
    );
    return ColoredBox(
      color: OnVideoColors.ground,
      child: MouseRegion(
        onHover: (_) => _touch(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            video,
            Positioned(left: 0, top: 0, right: 0, bottom: widget.overlayBottom, child: overlay),
          ],
        ),
      ),
    );
  }
}

/// [look] for a portrait stream (3.x `PortraitDanmakuMode`): the upper
/// quarter, or a smaller font over half the picture.
DanmakuLook _portraitLook(DanmakuLook look, String mode) => switch (mode) {
  'upperQuarter' => look.copyWith(area: look.area.clamp(0, 0.25).toDouble()),
  'reduced' => look.copyWith(
    fontSize: (look.fontSize * 0.85).roundToDouble(),
    area: look.area.clamp(0, 0.5).toDouble(),
  ),
  _ => look,
};

/// The danmaku frame-rate settings (F.2a).
typedef _FpsSettings = ({bool automatic, int configured, String mode});

/// Whether a tap at [local] on the picture may hit a flying danmaku (3.x
/// `shouldHandleVideoSurfaceTap`): while the controls show, not within
/// [top] of the top or [bottom] of the bottom, where the bars are.
@visibleForTesting
bool danmakuTapAllowed({
  required Offset local,
  required Size size,
  required bool controlsVisible,
  required double top,
  required double bottom,
}) {
  if (!controlsVisible || size.height <= 0) return true;
  final half = size.height / 2;
  return local.dy > top.clamp(0, half) && local.dy < size.height - bottom.clamp(0, half);
}

/// The portrait fullscreen's bottom bars also take the upward swipe back to
/// the panel (3.x `PortraitFullscreenRestoreGestureRegion`); their buttons
/// still take taps.
class _SwipeUpRegion extends StatefulWidget {
  const new({required this.onSwipeUp, required this.child});

  final VoidCallback onSwipeUp;
  final Widget child;

  @override
  State<_SwipeUpRegion> createState() => _SwipeUpRegionState();
}

class _SwipeUpRegionState extends State<_SwipeUpRegion> {
  double _upward = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onVerticalDragStart: (_) => _upward = 0,
    onVerticalDragUpdate: (details) => _upward = (_upward - details.delta.dy).clamp(0.0, double.infinity),
    onVerticalDragEnd: (details) {
      final restore = swipeRestoresPanel(upward: _upward, velocity: details.primaryVelocity ?? 0);
      _upward = 0;
      if (restore) widget.onSwipeUp();
    },
    child: widget.child,
  );
}
