import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart' show DanmakuChat;
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart' as player;
import 'package:live_store/live_store.dart' as store;
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/images.dart';
import 'package:pure_live_app/core/network.dart';
import 'package:pure_live_app/core/proxy.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/danmaku/chat_actions.dart';
import 'package:pure_live_app/features/danmaku/danmaku_preferences.dart';
import 'package:pure_live_app/features/danmaku/on_video.dart';
import 'package:pure_live_app/features/danmaku/room_danmaku.dart';
import 'package:pure_live_app/features/room/gestures.dart';
import 'package:pure_live_app/features/room/playback.dart';
import 'package:pure_live_app/features/room/presentation.dart';
import 'package:pure_live_app/features/room/room_menus.dart';
import 'package:pure_live_app/features/room/sleep_timer.dart';
import 'package:pure_live_app/features/room/weak_network.dart';
import 'package:pure_live_app/features/system/launch_args.dart';
import 'package:pure_live_app/features/system/pip.dart';
import 'package:url_launcher/url_launcher.dart';

/// What the user reads when playback fails, by failure kind (principles rule 3:
/// say what happened in place and offer the next step).
String failureText(PlaybackFailure failure) => switch (failure.kind) {
  FailureKind.network => '网络中断了',
  FailureKind.source => '直播流打不开，可以换条线路试试',
  FailureKind.bufferingStall => '缓冲太久了，可以换条线路或降低画质',
  FailureKind.liveCompleted => '直播流中断了',
  FailureKind.unexpectedPause => '播放意外停止了',
  FailureKind.frameStall => '画面卡住了',
  FailureKind.videoDecode => '视频解码失败，可以在设置里关闭硬件解码',
  FailureKind.audioDecode => '音频解码失败',
  FailureKind.engine => '播放器出错了',
  FailureKind.unavailable => '拿不到直播流',
  FailureKind.exhausted => '多次重试都没有成功',
};

/// The room's single video surface with its layers (LAY-2): video, on-video
/// danmaku, controls. The page moves it between layouts with a GlobalKey
/// (PS-3), so its state and the native surface survive every presentation
/// change.
///
/// Touch (live-room §3.3): tap shows or hides the controls (T-01), double
/// tap toggles fullscreen (T-02), vertical swipes on the left and right
/// halves set brightness and volume (T-03), a spread or pinch switches fill
/// and fit (T-06), a long press opens the danmaku actions or the quick panel
/// (T-07), the lock disables all of them (T-10). Pointer (§3.4): hover
/// shows the controls for 2 s, the wheel sets the volume, right click opens
/// the quick panel. The page owns the keyboard and calls the public methods
/// of [PlayerViewState].
class PlayerView extends ConsumerStatefulWidget {
  const new({
    required this.detail,
    required this.session,
    required this.presentation,
    required this.overlay,
    required this.onToggleFullscreen,
    required this.onBack,
    this.danmaku,
    this.chatOpen = false,
    this.onToggleChat,
    this.onToggleTheater,
    this.onSwitchRoom,
    this.onStepRoom,
    this.onBlock,
    this.onOpenDanmakuSettings,
    this.resume = false,
    this.surfaceReady = true,
    this.tv = false,
    super.key,
  });

  final RoomDetail detail;

  /// The page's playback session.
  final PlaybackSession session;

  /// Presentation as shown (a phone held landscape shows fullscreen).
  final RoomPresentation presentation;

  /// The on-video danmaku renderer of this surface.
  final DanmakuController overlay;

  /// T-02: double tap, F and the fullscreen button.
  final VoidCallback onToggleFullscreen;

  /// The back button of the top bar (§3.6 without the panel step).
  final VoidCallback onBack;

  /// The room's chat, when danmaku is on and the room is live.
  final RoomDanmaku? danmaku;

  /// Whether the chat panel is open (fullscreen overlay, theater side panel).
  final bool chatOpen;

  /// Shows or hides the chat panel; null where there is none to toggle.
  final VoidCallback? onToggleChat;

  /// Toggles theater mode; null below large windows.
  final VoidCallback? onToggleTheater;

  /// Opens the switch-room panel (F-ROOM-11).
  final VoidCallback? onSwitchRoom;

  /// Steps to the previous (-1) or next (+1) room of the list; set when
  /// “上下滑切换直播间” is on, used by vertical swipes in portrait
  /// fullscreen (T-05).
  final ValueChanged<int>? onStepRoom;

  /// Blocks a word or user from an on-video danmaku (REN-8).
  final BlockCallback? onBlock;

  /// Opens the danmaku settings panel.
  final VoidCallback? onOpenDanmakuSettings;

  /// The session already plays this room (taken back from the mini window,
  /// SES-9): it is not opened again.
  final bool resume;

  /// Whether the video surface may mount; false until the mini window has
  /// let go of it (SURF-5).
  final bool surfaceReady;

  /// TV mode (live-room §3.5): the room page draws the remote's info bar,
  /// control row and side panels; this view keeps the picture, danmaku,
  /// hints and failure overlay, without the touch bars and the lock.
  final bool tv;

  @override
  ConsumerState<PlayerView> createState() => PlayerViewState();
}

/// State of a [PlayerView]; the page calls its commands for the keyboard.
class PlayerViewState extends ConsumerState<PlayerView> {
  StreamSubscription<PlaybackState>? _subscription;
  late PlaybackState _state;
  Object? _openError;

  bool _controls = true;
  Timer? _hideTimer;
  int _hoverTick = 0;
  int _panels = 0;
  bool _locked = false;
  bool _lockButton = false;
  Timer? _lockButtonTimer;
  (IconData, String)? _hint;
  Timer? _hintTimer;
  bool _suppressTap = false;
  Timer? _suppressTimer;

  double _volume = 1;
  double _lastAudible = 1;
  bool _volumeTouched = false;
  Timer? _volumeSave;
  double _brightness = 1;
  bool _pipSupported = false;
  final StallWatch _stallWatch = StallWatch();
  late store.VideoFit _fit;

  Size _size = Size.zero;
  Offset _gestureStart = Offset.zero;
  Offset _gestureTravel = Offset.zero;
  SwipeTarget _swipe = SwipeTarget.none;
  bool _swipeDecided = false;
  double _swipeFrom = 0;
  bool _exitSwipe = false;
  bool _pinched = false;
  bool _dragging = false;

  PlaybackSession get _session => widget.session;
  bool get _live => widget.detail.state == LiveState.live;
  bool get _touch => touchPlatform;
  bool get _fullscreen => widget.presentation.isFullscreen;

  /// Whether the controls are showing.
  bool get controlsVisible => _controls;

  /// Whether the lock is on (T-10).
  bool get locked => _locked;

  /// The player volume, 0–1.
  double get volume => _volume;

  /// The brightness layer, 0.2–1 (1: no dimming).
  double get brightness => _brightness;

  /// The picture fit.
  store.VideoFit get fit => _fit;

  /// The session's latest state.
  PlaybackState get playbackState => _state;

  @override
  void initState() {
    super.initState();
    _fit = ref.read(videoFitSetting);
    _state = _session.state;
    _subscription = _session.states.listen(_onState);
    _initVolume();
    if (!widget.resume) {
      if (_live) unawaited(_open());
    } else if (!_live) {
      // Went offline while the mini window played it.
      unawaited(_session.close());
    }
    _scheduleHide();
  }

  @override
  void didUpdateWidget(PlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.ref != widget.detail.ref) {
      // Switching rooms in place: same session and surface, new source
      // (SES-3); late results of the old room are dropped by the session.
      _openError = null;
      _stallWatch.reset();
      _initVolume();
      if (_live) {
        unawaited(_open());
      } else {
        unawaited(_session.close());
      }
    }
    if (oldWidget.presentation != widget.presentation) {
      // PS-2: entering or leaving fullscreen unlocks; CL-3: controls show.
      _locked = false;
      _lockButton = false;
      _showControls();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _lockButtonTimer?.cancel();
    _hintTimer?.cancel();
    _suppressTimer?.cancel();
    _volumeSave?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _onState(PlaybackState state) {
    if (!mounted) return;
    final lower = _stallWatch.observe(_state, state);
    if (lower != null && ref.read(storeProvider).settings.get(store.Settings.autoLowerQuality)) {
      // F-NEW-10: keeps stalling, one step down.
      unawaited(_session.selectQuality(lower));
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('网络不稳，已切到${lower.label}，可以在画质里换回')));
    }
    final wasPlaying = _state.phase == PlaybackPhase.playing;
    setState(() => _state = state);
    if (state.phase == PlaybackPhase.playing && !wasPlaying) _scheduleHide();
    final notice = state.notice;
    if (notice != null) {
      _session.clearNotice();
      final text = notice == 'audio_only_failed' ? '切换纯音频失败，已恢复画面' : '恢复画面失败，仍为纯音频';
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _open() async {
    final detail = widget.detail;
    setState(() => _openError = null);
    try {
      await openRoom(
        site: ref.read(sitesProvider)[detail.ref.platform]!,
        settings: ref.read(storeProvider).settings,
        session: _session,
        detail: detail,
        proxiedHosts: ref.read(proxiedHostsProvider),
        cellular: ref.read(networkKindProvider).value == NetworkKind.cellular,
      );
    } on Object catch (error) {
      if (mounted && widget.detail.ref == detail.ref) setState(() => _openError = error);
    }
  }

  // ------------------------------------------------------------- volume

  /// INV-ROOM-03: the player's volume starts from global mute, else the
  /// room's remembered volume (desktop), else the platform default; the
  /// device volume is never written.
  void _initVolume() {
    final liveStore = ref.read(storeProvider);
    final settings = liveStore.settings;
    _volumeTouched = false;
    if (settings.get(store.Settings.globalMute)) {
      _volume = 0;
    } else if (widget.tv) {
      // The remote's volume keys set the TV's volume; the player stays at
      // full level so they have the whole range (principles §6.3).
      _volume = 1;
    } else if (_touch) {
      _volume = settings.get(store.Settings.defaultMobileVolume);
    } else {
      _volume = settings.get(store.Settings.defaultDesktopVolume);
      final room = widget.detail.ref;
      unawaited(
        liveStore.roomPrefs.volumeOf(room).then((stored) {
          if (stored == null || !mounted || _volumeTouched || widget.detail.ref != room) return;
          _applyVolume(stored, touched: false);
        }, onError: (Object _) {}),
      );
    }
    if (_volume > 0) _lastAudible = _volume;
    unawaited(_session.setVolume(_volume));
  }

  void _applyVolume(double value, {bool touched = true, bool hint = false}) {
    final next = value.clamp(0.0, 1.0);
    setState(() {
      _volume = next;
      if (next > 0) _lastAudible = next;
    });
    unawaited(_session.setVolume(next));
    if (hint) showHint(next == 0 ? Icons.volume_off : Icons.volume_up, '音量 ${(next * 100).round()}%');
    if (!touched) return;
    _volumeTouched = true;
    if (!_touch) {
      // Desktops remember the volume per room (F-ROOM-13).
      final room = widget.detail.ref;
      _volumeSave?.cancel();
      _volumeSave = Timer(const Duration(milliseconds: 600), () {
        unawaited(ref.read(storeProvider).roomPrefs.setVolume(room, next).catchError((Object _) {}));
      });
    }
  }

  /// Changes the volume by [delta] (↑/↓ and the wheel: ±5%).
  void changeVolume(double delta) => _applyVolume(_volume + delta, hint: true);

  /// M: mute or unmute.
  void toggleMute() => _applyVolume(_volume == 0 ? (_lastAudible == 0 ? 1 : _lastAudible) : 0, hint: true);

  // ------------------------------------------------------------- commands

  /// Space: play or pause.
  void togglePlay() {
    if (_state.phase == PlaybackPhase.paused || _state.phase == PlaybackPhase.error) {
      unawaited(_session.play());
    } else {
      unawaited(_session.pause());
    }
  }

  /// R, F5, Ctrl+R: reload the stream; a closed chat connects again.
  void refresh() {
    if (_openError != null || _state.phase == PlaybackPhase.idle) {
      if (_live) unawaited(_open());
    } else {
      unawaited(_session.retry());
    }
    final danmaku = widget.danmaku;
    if (danmaku != null && danmaku.connection.value == ChatConnection.closed) unawaited(danmaku.reconnect());
  }

  /// D: danmaku on the video on or off.
  void toggleDanmaku() {
    final prefs = ref.read(danmakuPrefsProvider);
    if (!prefs.enabled) return;
    ref.read(danmakuPrefsProvider.notifier).setHidden(hidden: !prefs.hidden);
    showHint(prefs.hidden ? Icons.subtitles : Icons.subtitles_off_outlined, prefs.hidden ? '弹幕已打开' : '弹幕已关闭');
  }

  /// P and the picture-in-picture button (F-PIP-01, F-PIP-02): only the
  /// video shows from the request on (PIP-2).
  Future<void> enterPip() async {
    if (!_live || !ref.read(pipProvider).supported) return;
    Rect? source;
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      // Where the video is, in physical pixels of the window.
      final ratio = MediaQuery.devicePixelRatioOf(context);
      final origin = box.localToGlobal(Offset.zero) * ratio;
      source = origin & (box.size * ratio);
    }
    final entered = await ref.read(pipProvider.notifier).enter(_session, sourceRect: source);
    if (!entered && mounted && ref.read(pipProvider).mode == PipMode.off) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('画面出来后才能进入画中画')));
    }
  }

  Future<void> _openNewWindow() async {
    final opened = await ref.read(newWindowProvider)(widget.detail.ref);
    if (!opened && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('没能打开新窗口')));
    }
  }

  /// Audio only on or off, in place (F-ROOM-9, AUD-1).
  void toggleAudioOnly() => unawaited(_session.setAudioOnly(enabled: !_state.audioOnly));

  /// Q / L: the quality and line panel.
  Future<void> chooseQualityLine() async {
    if (_state.qualities.isEmpty && _state.lines.isEmpty) return;
    await withPanel(() => showQualityLineSheet(context, _session, onQualityPicked: (_) => _stallWatch.picked()));
  }

  // ------------------------------------------------------------- controls

  Duration get _hideAfter => _touch ? const Duration(seconds: 4) : const Duration(seconds: 2);

  void _showControls() {
    if (!mounted) return;
    if (!_controls) setState(() => _controls = true);
    _scheduleHide();
  }

  /// CL-1, CL-2: hide after 4 s (touch) or 2 s (pointer) while playing; not
  /// while a panel is open or a swipe is in progress. Pointer movement only
  /// bumps a counter; the running timer re-arms when it sees it (CL-5).
  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_panels > 0 || _dragging) return;
    final tick = _hoverTick;
    _hideTimer = Timer(_hideAfter, () {
      if (!mounted) return;
      if (_hoverTick != tick) {
        _scheduleHide();
        return;
      }
      if (_panels == 0 && !_dragging && _state.phase == PlaybackPhase.playing) setState(() => _controls = false);
    });
  }

  void _onHover(PointerHoverEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    _hoverTick++;
    if (!_controls) _showControls();
    if (_hideTimer == null || !_hideTimer!.isActive) _scheduleHide();
  }

  /// Opens a panel (CL-2: controls stay while it is open; CL-4: they show
  /// again and re-time when it closes).
  Future<T?> withPanel<T>(Future<T?> Function() open) async {
    _panels++;
    _hideTimer?.cancel();
    if (!_controls) setState(() => _controls = true);
    try {
      return await open();
    } finally {
      _panels--;
      if (mounted) _showControls();
    }
  }

  /// A short message in the middle of the picture (volume, fit, room
  /// switches), gone after [duration].
  void showHint(IconData icon, String text, {Duration duration = const Duration(seconds: 1)}) {
    if (!mounted) return;
    setState(() => _hint = (icon, text));
    _hintTimer?.cancel();
    _hintTimer = Timer(duration, () {
      if (mounted) setState(() => _hint = null);
    });
  }

  void _setLocked({required bool locked}) {
    setState(() {
      _locked = locked;
      _lockButton = locked;
      _controls = !locked;
    });
    _armLockButton();
    if (!locked) _scheduleHide();
  }

  void _armLockButton() {
    _lockButtonTimer?.cancel();
    if (!_locked || !_lockButton) return;
    _lockButtonTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _lockButton = false);
    });
  }

  /// Sets and remembers the picture fit.
  void setFit(store.VideoFit fit) {
    setState(() => _fit = fit);
    showHint(Icons.aspect_ratio, switch (fit) {
      store.VideoFit.cover => '填充',
      store.VideoFit.fill => '拉伸',
      _ => '适应',
    });
    unawaited(ref.read(videoFitSetting.notifier).set(fit).catchError((Object _) {}));
  }

  // ------------------------------------------------------------- gestures

  DanmakuChat? _danmakuAt(Offset global, {required bool allowed}) {
    if (!allowed) return null;
    final prefs = ref.read(danmakuPrefsProvider);
    if (!prefs.enabled || prefs.hidden) return null;
    return chatOfHit(widget.overlay.itemAtGlobal(global));
  }

  void _suppressTaps() {
    // REN-8 / REG-ROOM-024: a tap within 1 s after a long press is ignored.
    _suppressTap = true;
    _suppressTimer?.cancel();
    _suppressTimer = Timer(const Duration(seconds: 1), () => _suppressTap = false);
  }

  void _onTapUp(TapUpDetails details) {
    if (_suppressTap) return;
    final band = inControlBand(details.localPosition.dy, _size.height);
    final prefs = ref.read(danmakuPrefsProvider);
    final hit = _locked || (_controls && band)
        ? null
        : _danmakuAt(details.globalPosition, allowed: prefs.tapActions && widget.onBlock != null);
    switch (tapOutcome(
      locked: _locked,
      controlsVisible: _controls,
      inControlBand: band,
      hitDanmaku: hit != null,
      playing: _state.phase == PlaybackPhase.playing,
      touch: _touch,
    )) {
      case TapOutcome.toggleLockButton:
        setState(() => _lockButton = !_lockButton);
        _armLockButton();
      case TapOutcome.keepControls:
        _showControls();
      case TapOutcome.danmakuActions:
        unawaited(_openDanmakuActions(hit!));
      case TapOutcome.hideControls:
        _hideTimer?.cancel();
        setState(() => _controls = false);
      case TapOutcome.showControls:
        _showControls();
        if (_state.phase == PlaybackPhase.paused) unawaited(_session.play());
    }
  }

  void _onDoubleTap() {
    if (_locked) return;
    widget.onToggleFullscreen();
  }

  void _onLongPress(LongPressStartDetails details) {
    _suppressTaps();
    final band = inControlBand(details.localPosition.dy, _size.height);
    final prefs = ref.read(danmakuPrefsProvider);
    final hit = _locked || (_controls && band)
        ? null
        : _danmakuAt(details.globalPosition, allowed: prefs.longPressActions && widget.onBlock != null);
    switch (longPressOutcome(
      locked: _locked,
      controlsVisible: _controls,
      inControlBand: band,
      hitDanmaku: hit != null,
    )) {
      case LongPressOutcome.none:
        return;
      case LongPressOutcome.keepControls:
        _showControls();
      case LongPressOutcome.danmakuActions:
        unawaited(_openDanmakuActions(hit!));
      case LongPressOutcome.quickPanel:
        unawaited(openQuickPanel());
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStart = details.localFocalPoint;
    _gestureTravel = Offset.zero;
    _swipe = SwipeTarget.none;
    _swipeDecided = false;
    _pinched = false;
    _exitSwipe =
        widget.presentation == RoomPresentation.portraitFullscreen &&
        startsInPortraitExitZone(details.localFocalPoint.dy, _size.height);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_locked) return;
    if (details.pointerCount >= 2) {
      // T-06: one fit step per gesture; a pinch cancels a swipe.
      _swipe = SwipeTarget.none;
      _swipeDecided = true;
      if (_dragging) setState(() => _dragging = false);
      if (!_pinched) {
        final next = pinchFit(_fit, details.scale);
        if (next != null) {
          _pinched = true;
          setFit(next);
        }
      }
      return;
    }
    if (_pinched) return;
    _gestureTravel += details.focalPointDelta;
    if (_exitSwipe) return;
    if (!_swipeDecided) {
      final dy = _gestureTravel.dy.abs();
      final dx = _gestureTravel.dx.abs();
      if (dy < 12 && dx < 12) return;
      _swipeDecided = true;
      if (dy <= dx * 1.5) return;
      _swipe = swipeTarget(
        x: _gestureStart.dx,
        width: _size.width,
        touch: _touch,
        switchRooms: widget.onStepRoom != null && widget.presentation == RoomPresentation.portraitFullscreen,
      );
      // T-05: the room changes when the swipe ends.
      if (_swipe == SwipeTarget.none || _swipe == SwipeTarget.switchRoom) return;
      _swipeFrom = _swipe == SwipeTarget.brightness ? _brightness : _volume;
      _hideTimer?.cancel();
      setState(() => _dragging = true);
    }
    final value = _swipeFrom + swipeChange(_gestureTravel.dy, _size.height);
    switch (_swipe) {
      case SwipeTarget.volume:
        _applyVolume(value, hint: true);
      case SwipeTarget.brightness:
        final next = value.clamp(0.2, 1.0);
        setState(() => _brightness = next);
        showHint(Icons.brightness_medium, '亮度 ${(next * 100).round()}%');
      case SwipeTarget.none || SwipeTarget.switchRoom:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_exitSwipe && !_locked && !_pinched) {
      final upward = -_gestureTravel.dy;
      if (exitsPortraitFullscreen(upward: upward, velocity: details.velocity.pixelsPerSecond.dy)) {
        widget.onToggleFullscreen();
      }
    }
    if (_swipe == SwipeTarget.switchRoom && !_locked && !_pinched) {
      final step = roomSwipeStep(dy: _gestureTravel.dy, velocity: details.velocity.pixelsPerSecond.dy);
      if (step != null) widget.onStepRoom?.call(step);
    }
    _exitSwipe = false;
    _swipe = SwipeTarget.none;
    if (_dragging) {
      setState(() => _dragging = false);
      if (_controls) _scheduleHide();
    }
  }

  void _onWheel(PointerSignalEvent event) {
    if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
      // D-04: ±5% per notch anywhere on the picture.
      changeVolume(event.scrollDelta.dy < 0 ? 0.05 : -0.05);
    }
  }

  // ------------------------------------------------------------- panels

  Future<void> _openDanmakuActions(DanmakuChat chat) async {
    final onBlock = widget.onBlock;
    if (onBlock == null) return;
    widget.overlay.pause(pausedForMenu);
    try {
      await withPanel(() => showChatLineActions(context, line: chat, onBlock: onBlock));
    } finally {
      widget.overlay.resume(pausedForMenu);
    }
  }

  /// The long-press (and right-click) quick panel (T-07).
  Future<void> openQuickPanel() async {
    final prefs = ref.read(danmakuPrefsProvider);
    final action = await withPanel(
      () => showQuickPanel(
        context,
        qualityLabel: qualityLineLabel(_state),
        danmakuAvailable: prefs.enabled && _live,
        danmakuShown: !prefs.hidden,
        canScreenshot: canScreenshot(_session),
        audioOnly: _state.audioOnly,
        fit: _fit,
      ),
    );
    if (action == null || !mounted) return;
    final fit = fitOfQuickAction(action);
    if (fit != null) {
      setFit(fit);
      return;
    }
    switch (action) {
      case QuickAction.qualityLine:
        await chooseQualityLine();
      case QuickAction.toggleDanmaku:
        toggleDanmaku();
      case QuickAction.screenshot:
        await _screenshot();
      case QuickAction.sleepTimer:
        await openSleepTimer();
      case QuickAction.audioOnly:
        toggleAudioOnly();
      case QuickAction.fitContain || QuickAction.fitCover || QuickAction.fitFill:
        break;
    }
  }

  Future<void> _screenshot() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await saveScreenshot(_session, widget.detail);
      messenger.showSnackBar(SnackBar(content: Text(file == null ? '当前没有画面可以截图' : '截图已保存：${file.path}')));
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('截图失败：$error')));
    }
  }

  /// The sleep timer sheet.
  Future<void> openSleepTimer() => withPanel(
    () =>
        showSleepTimerSheet(context, onAudioOnly: _live ? () => unawaited(_session.setAudioOnly(enabled: true)) : null),
  );

  Future<void> _openVolume() => withPanel(
    () => showRoomVolumeDialog(
      context,
      volume: _volume,
      desktop: !_touch,
      onChanged: _applyVolume,
      onSaveDefault: () {
        final setting = _touch ? store.Settings.defaultMobileVolume : store.Settings.defaultDesktopVolume;
        unawaited(ref.read(storeProvider).settings.set(setting, _volume).catchError((Object _) {}));
      },
    ),
  );

  Future<void> _onMenu(RoomMenuAction action) async {
    switch (action) {
      case RoomMenuAction.switchRoom:
        widget.onSwitchRoom?.call();
      case RoomMenuAction.openSite:
        await launchUrl(widget.detail.link, mode: LaunchMode.externalApplication);
      case RoomMenuAction.share:
        await shareRoom(context, widget.detail);
      case RoomMenuAction.copyStreamUrl:
        await copyStreamUrl(context, _state);
      case RoomMenuAction.sleepTimer:
        await openSleepTimer();
      case RoomMenuAction.volume:
        await _openVolume();
      case RoomMenuAction.danmakuSettings:
        widget.onOpenDanmakuSettings?.call();
      case RoomMenuAction.multiview:
        await context.push('/multiview', extra: [widget.detail.ref]);
      case RoomMenuAction.keys:
        await withPanel(() => showKeyHelp(context));
      case RoomMenuAction.newWindow:
        await _openNewWindow();
    }
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    ref.listen(sleepTimerProvider, (previous, next) {
      if (next.fired <= (previous?.fired ?? 0)) return;
      unawaited(_session.pause());
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(next.action == SleepAction.exit ? '定时关闭：正在退出应用' : '定时关闭：已暂停播放')));
    });
    ref.listen(videoFitSetting, (_, next) {
      if (next != _fit) setState(() => _fit = next);
    });
    final prefs = ref.watch(danmakuPrefsProvider);
    final keepOn = ref.watch(screenKeepOnSetting);
    final fit = switch (_fit) {
      store.VideoFit.cover => player.VideoFit.cover,
      store.VideoFit.fill => player.VideoFit.fill,
      _ => player.VideoFit.contain,
    };
    final danmakuShown = prefs.enabled && !prefs.hidden && _live;
    final video = !_live
        ? _OfflineCover(detail: widget.detail)
        : widget.surfaceReady
        ? player.LiveVideoView(session: _session, fit: fit, wakelock: keepOn)
        : const ColoredBox(color: Colors.black);
    // PIP-2: from the request on only the video shows, so the system's
    // entry animation captures no controls.
    if (ref.watch(pipProvider.select((pip) => pip.videoOnly))) return RepaintBoundary(child: video);
    _pipSupported = ref.watch(pipProvider.select((pip) => pip.supported));
    return MouseRegion(
      onHover: _onHover,
      cursor: _controls || _touch ? MouseCursor.defer : SystemMouseCursors.none,
      child: Listener(
        onPointerSignal: _onWheel,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _size = constraints.biggest;
            // The gesture layer sits under the buttons, not around them: a
            // double-tap recognizer around a button would hold every button
            // tap for the double-tap window.
            return ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(child: video),
                  Positioned.fill(
                    child: DanmakuOverlay(controller: widget.overlay, visible: danmakuShown),
                  ),
                  if (_brightness < 1)
                    IgnorePointer(child: ColoredBox(color: Color.fromRGBO(0, 0, 0, 1 - _brightness))),
                  if (_live && _state.showsBuffering && _openError == null)
                    const IgnorePointer(
                      child: Center(child: CircularProgressIndicator(color: Colors.white)),
                    ),
                  if (_hint case (final icon, final text))
                    Center(
                      child: _Hint(icon: icon, text: text),
                    ),
                  Positioned.fill(
                    child: GestureDetector(
                      key: const ValueKey('room-gestures'),
                      behavior: HitTestBehavior.opaque,
                      onTapUp: _onTapUp,
                      onDoubleTap: _onDoubleTap,
                      onLongPressStart: _onLongPress,
                      onSecondaryTapUp: _touch ? null : (_) => unawaited(openQuickPanel()),
                      onScaleStart: _touch ? _onScaleStart : null,
                      onScaleUpdate: _touch ? _onScaleUpdate : null,
                      onScaleEnd: _touch ? _onScaleEnd : null,
                    ),
                  ),
                  if (_live && _state.audioOnly) _AudioOnlyCover(onRestore: toggleAudioOnly),
                  if (_openError != null || _state.failure != null) _failureOverlay(),
                  if (_state.showsPaused && _openError == null)
                    Center(
                      child: IconButton.filled(
                        tooltip: '继续播放',
                        iconSize: 40,
                        onPressed: _session.play,
                        icon: const Icon(Icons.play_arrow),
                      ),
                    ),
                  // On TV the room page draws the remote's controls (§3.5).
                  if (!widget.tv) RepaintBoundary(child: _controlsLayer(prefs)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _failureOverlay() {
    final String title;
    final String message;
    if (_openError != null) {
      final text = describeError(_openError!);
      title = text.title;
      message = text.message;
    } else {
      title = failureText(_state.failure!);
      message = _state.lines.length > 1 ? '当前线路出错，可以重试或换线路' : '可以稍后重试';
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        const IgnorePointer(child: ColoredBox(color: Color(0xCC000000))),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.s4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Space.s1),
                Text(
                  message,
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Space.s3),
                Wrap(
                  spacing: Space.s2,
                  children: [
                    FilledButton(onPressed: _openError != null ? _open : _session.retry, child: const Text('重试')),
                    if (_state.lines.length > 1)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                        onPressed: chooseQualityLine,
                        child: const Text('换线路'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _controlsLayer(DanmakuPrefs prefs) {
    final lockable = _touch && _fullscreen;
    final bars = _controls && !_locked;
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          ignoring: !bars,
          child: AnimatedOpacity(opacity: bars ? 1 : 0, duration: Motion.medium, child: _bars(prefs)),
        ),
        if (lockable && (bars || (_locked && _lockButton)))
          Align(
            alignment: Alignment.centerRight,
            child: SafeArea(
              left: false,
              child: Padding(
                padding: const EdgeInsets.only(right: Space.s2),
                child: IconButton.filledTonal(
                  key: const ValueKey('room-lock'),
                  tooltip: _locked ? '解锁' : '锁定',
                  icon: Icon(_locked ? Icons.lock : Icons.lock_open),
                  onPressed: () => _setLocked(locked: !_locked),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _bars(DanmakuPrefs prefs) {
    const ink = Colors.white;
    final card = widget.detail.card;
    final wide = _size.width >= 600;
    final danmakuButton = prefs.enabled && _live;
    return Stack(
      fit: StackFit.expand,
      children: [
        // The scrim takes no pointers: gestures between the buttons reach the
        // gesture layer underneath (ZN-1 is decided there).
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x99000000), Color(0x00000000), Color(0x00000000), Color(0x99000000)],
                stops: [0, 0.3, 0.7, 1],
              ),
            ),
          ),
        ),
        SafeArea(
          top: _fullscreen,
          bottom: _fullscreen,
          child: IconTheme.merge(
            data: const IconThemeData(color: ink),
            child: Column(
              children: [
                Row(
                  key: const ValueKey('room-top-bar'),
                  children: [
                    IconButton(tooltip: '返回', color: ink, icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
                    Expanded(
                      child: Text(
                        _fullscreen ? '${card.anchorName} · ${card.title}' : card.anchorName,
                        style: const TextStyle(color: ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // F-ROOM-17: the time in the fullscreen top bar (battery:
                    // no plugin in v4 yet).
                    if (_fullscreen && _touch) const _ClockText(color: ink),
                    SleepTimerChip(color: ink, onTap: openSleepTimer),
                    if (_fullscreen && widget.onSwitchRoom != null)
                      IconButton(
                        tooltip: '切换直播间',
                        color: ink,
                        icon: const Icon(Icons.swap_horiz),
                        onPressed: widget.onSwitchRoom,
                      ),
                    if (_fullscreen && widget.onToggleChat != null)
                      IconButton(
                        tooltip: widget.chatOpen ? '收起聊天' : '聊天',
                        color: ink,
                        isSelected: widget.chatOpen,
                        icon: const Icon(Icons.chat_bubble_outline),
                        selectedIcon: const Icon(Icons.chat_bubble),
                        onPressed: widget.onToggleChat,
                      ),
                    if (_live)
                      IconButton(
                        tooltip: _state.audioOnly ? '恢复画面' : '纯音频',
                        color: ink,
                        isSelected: _state.audioOnly,
                        icon: const Icon(Icons.headphones_outlined),
                        selectedIcon: const Icon(Icons.headphones),
                        onPressed: toggleAudioOnly,
                      ),
                    PopupMenuButton<RoomMenuAction>(
                      tooltip: '更多',
                      icon: const Icon(Icons.more_vert, color: ink),
                      onOpened: () {
                        _panels++;
                        _hideTimer?.cancel();
                      },
                      onCanceled: () {
                        _panels--;
                        _showControls();
                      },
                      onSelected: (action) {
                        _panels--;
                        _showControls();
                        unawaited(_onMenu(action));
                      },
                      itemBuilder: (context) => roomMenuEntries(
                        desktop: !_touch,
                        danmakuAvailable: prefs.enabled,
                        newWindow: newWindowSupported,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  key: const ValueKey('room-bottom-bar'),
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            if (_live) ...[
                              if (_state.phase == PlaybackPhase.paused)
                                IconButton(
                                  tooltip: '播放',
                                  color: ink,
                                  icon: const Icon(Icons.play_arrow),
                                  onPressed: _session.play,
                                )
                              else
                                IconButton(
                                  tooltip: '暂停',
                                  color: ink,
                                  icon: const Icon(Icons.pause),
                                  onPressed: _session.pause,
                                ),
                              IconButton(
                                tooltip: '刷新',
                                color: ink,
                                icon: const Icon(Icons.refresh),
                                onPressed: refresh,
                              ),
                            ],
                            if (danmakuButton) ...[
                              IconButton(
                                key: const ValueKey('room-danmaku-toggle'),
                                tooltip: prefs.hidden ? '打开弹幕 (D)' : '关闭弹幕 (D)',
                                color: ink,
                                isSelected: !prefs.hidden,
                                icon: const Icon(Icons.subtitles_off_outlined),
                                selectedIcon: const Icon(Icons.subtitles),
                                onPressed: toggleDanmaku,
                              ),
                              if (widget.onOpenDanmakuSettings != null)
                                IconButton(
                                  tooltip: '弹幕设置',
                                  color: ink,
                                  icon: const Icon(Icons.tune),
                                  onPressed: widget.onOpenDanmakuSettings,
                                ),
                            ],
                            if (!_touch) ...[
                              IconButton(
                                tooltip: _volume == 0 ? '取消静音 (M)' : '静音 (M)',
                                color: ink,
                                icon: Icon(_volume == 0 ? Icons.volume_off : Icons.volume_up),
                                onPressed: toggleMute,
                              ),
                              SizedBox(
                                width: 96,
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: ink,
                                    thumbColor: ink,
                                    inactiveTrackColor: Colors.white30,
                                  ),
                                  child: Slider(value: _volume, onChanged: _applyVolume),
                                ),
                              ),
                            ],
                            if (_live && _state.qualities.isNotEmpty)
                              TextButton(
                                style: TextButton.styleFrom(foregroundColor: ink),
                                onPressed: chooseQualityLine,
                                child: Text(qualityLineLabel(_state)),
                              ),
                            if (wide)
                              PopupMenuButton<store.VideoFit>(
                                tooltip: '画面比例',
                                icon: const Icon(Icons.aspect_ratio, color: ink),
                                initialValue: _fit,
                                onSelected: setFit,
                                itemBuilder: (context) => const [
                                  PopupMenuItem(value: store.VideoFit.contain, child: Text('适应')),
                                  PopupMenuItem(value: store.VideoFit.cover, child: Text('填充')),
                                  PopupMenuItem(value: store.VideoFit.fill, child: Text('拉伸')),
                                ],
                              ),
                            if (widget.onToggleTheater != null)
                              IconButton(
                                tooltip: widget.presentation == RoomPresentation.theater ? '退出剧场 (T)' : '剧场模式 (T)',
                                color: ink,
                                isSelected: widget.presentation == RoomPresentation.theater,
                                icon: const Icon(Icons.crop_7_5),
                                onPressed: widget.onToggleTheater,
                              ),
                            if (!_fullscreen && widget.onToggleChat != null)
                              IconButton(
                                tooltip: widget.chatOpen ? '收起聊天栏 (C)' : '显示聊天栏 (C)',
                                color: ink,
                                isSelected: widget.chatOpen,
                                icon: const Icon(Icons.view_sidebar_outlined),
                                selectedIcon: const Icon(Icons.view_sidebar),
                                onPressed: widget.onToggleChat,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (_live && _pipSupported)
                      IconButton(
                        key: const ValueKey('room-pip'),
                        tooltip: '画中画 (P)',
                        color: ink,
                        icon: const Icon(Icons.picture_in_picture_alt_outlined),
                        onPressed: () => unawaited(enterPip()),
                      ),
                    // REG-ROOM-017: fullscreen stays outside the scrolling row.
                    IconButton(
                      key: const ValueKey('room-fullscreen'),
                      tooltip: _fullscreen ? '退出全屏 (F)' : '全屏 (F)',
                      color: ink,
                      icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
                      onPressed: widget.onToggleFullscreen,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const new({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(Radii.r3)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: Space.s3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: Space.s2),
            Text(
              text,
              style: const TextStyle(color: Colors.white, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AudioOnlyCover extends StatelessWidget {
  const new({required this.onRestore});

  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const IgnorePointer(child: ColoredBox(color: Colors.black)),
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.headphones, color: Colors.white, size: 48),
            const SizedBox(height: Space.s2),
            const Text('纯音频播放中', style: TextStyle(color: Colors.white)),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: onRestore,
              child: const Text('恢复画面'),
            ),
          ],
        ),
      ),
    ],
  );
}

/// "21:07", updated on the minute.
class _ClockText extends StatefulWidget {
  const new({required this.color});

  final Color color;

  @override
  State<_ClockText> createState() => _ClockTextState();
}

class _ClockTextState extends State<_ClockText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  void _arm() {
    final now = DateTime.now();
    _timer = Timer(Duration(seconds: 60 - now.second), () {
      if (!mounted) return;
      setState(() {});
      _arm();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s2),
      child: Text(
        '${two(now.hour)}:${two(now.minute)}',
        style: TextStyle(color: widget.color, fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

class _OfflineCover extends StatelessWidget {
  const new({required this.detail});

  final RoomDetail detail;

  @override
  Widget build(BuildContext context) {
    final cover = networkImage(
      detail.card.cover,
      logicalWidth: MediaQuery.sizeOf(context).width,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        if (cover != null)
          Image(image: cover, fit: BoxFit.cover, color: const Color(0xA6000000), colorBlendMode: BlendMode.srcATop),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tv_off_outlined, color: Colors.white, size: 48),
              const SizedBox(height: Space.s2),
              Text(detail.state == LiveState.replay ? '回放中' : '未开播', style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ],
    );
  }
}
