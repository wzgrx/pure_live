import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/network.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/danmaku/chat_panel.dart';
import 'package:pure_live/features/live_play/danmaku/danmaku_settings_panel.dart';
import 'package:pure_live/features/live_play/dialogs/iptv_guide.dart';
import 'package:pure_live/features/live_play/layout/portrait_panel.dart';
import 'package:pure_live/features/live_play/layout/room_details.dart';
import 'package:pure_live/features/live_play/layout/room_header.dart';
import 'package:pure_live/features/live_play/layout/room_info_bar.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/local_composer.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/features/live_play/logic/mini_window.dart';
import 'package:pure_live/features/live_play/logic/player_standby.dart';
import 'package:pure_live/features/live_play/logic/predictive_back.dart';
import 'package:pure_live/features/live_play/logic/reconnect_watch.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/logic/room_layout.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/logic/room_playlist.dart';
import 'package:pure_live/features/live_play/logic/room_refresh_rate.dart';
import 'package:pure_live/features/live_play/logic/room_runtime.dart';
import 'package:pure_live/features/live_play/mini/room_mini_window.dart';
import 'package:pure_live/features/live_play/player/player_controls.dart';
import 'package:pure_live/features/live_play/player/player_view.dart';
import 'package:pure_live/features/live_play/player/room_swipe.dart';
import 'package:pure_live/features/live_play/record/record_panel.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/routes/route_path.dart';

/// The live room (argument: the `LiveRoom`, or a `LiveRoomArgs` with the
/// list it was opened from) (3.x `lib/modules/live_play`).
///
/// Routes: `RoutePath.kLivePlay`.
///
/// One room, one picture: the player is mounted once and moves between the
/// layouts ([RoomDisplay], docs/ui/UI_PLAN.md §5.3), which follow the space
/// the page gets ([roomPageLayout]):
///
/// - 840 and wider: the picture beside the chat column (U.2d), which folds
///   away and stays folded for the next room;
/// - narrower: the picture on top and the strip and chat below, or for a
///   portrait stream the picture filling the area under a three-stop panel
///   (U.2b);
/// - under 480 high (a phone held sideways): the picture with the landscape
///   bars;
/// - fullscreen (U.2c), the portrait fullscreen (U.2b) and, on desktops, the
///   in-window fullscreen.
///
/// The room details open over the chat (never over the picture). The record
/// and danmaku settings panels (U.2f) open under the picture in portrait and
/// on the right otherwise, never over the picture's left half; at the bottom
/// in the portrait fullscreen. Back and Esc close a panel first, then leave
/// fullscreen, then close the details, then the room. On Android the room
/// holds the system's back while it is open ([RoomBackChannel], F.1c).
///
/// U.2j: the room's player, danmaku and logic live in a [RoomRuntime]. When
/// the page closes with "退出小窗播放" on and the room playing, the in-app
/// floating window takes it over ([FloatingRoom]); opening the same room
/// again takes it back, so nothing is built twice. Closing without the
/// floating window stops the player and, unless "播放器强制销毁" is on, keeps
/// it for the next room ([PlayerStandby], F.1d). The picture's mini window
/// button ([RoomMiniWindow]) enters Android's picture-in-picture or shrinks a
/// desktop window to the mini window; the page then shows only the picture.
///
/// U.2b2: opened from a list ([LiveRoomArgs.playlist]) and with "竖屏全屏上下滑
/// 换台" on, the portrait fullscreen's middle third swipes up to the next
/// room of the list and down to the previous ([RoomSwipeController]). The
/// page stays and so does the player: the room's [RoomRuntime] is replaced
/// by one for the new room on the same session.
class LivePlayPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  ConsumerState<LivePlayPage> createState() => _LivePlayPageState();
}

/// The settings the page's layout follows, read once per build.
typedef _LayoutSettings = ({
  bool adaptation,
  bool adaptiveHeight,
  String mode,
  String policy,
  bool collapsed,
  bool composer,
  bool swipe,
});

class _LivePlayPageState extends ConsumerState<LivePlayPage> {
  RoomRuntime? _runtime;
  RoomMiniWindow? _mini;

  /// Where the player waits for the next room (F.1d).
  PlayerStandby? _standby;

  /// The page closes on purpose (the desktop mini window's ✕): no floating
  /// window.
  bool _closingOnPurpose = false;
  late final SettingsStore _settings;
  LiveRoomController? _controller;
  RoomOrientationChoice? _orientation;
  late ReconnectWatch _reconnect;
  StreamSubscription<PlaybackState>? _autoFullscreen;
  StreamSubscription<PlaybackState>? _shape;
  RoomDisplay _display = RoomDisplay.inline;

  /// A landscape fullscreen forced from a portrait room turns the phone back
  /// upright when it ends (appendix A 11).
  bool _restorePortrait = false;
  Timer? _releaseOrientation;
  bool _entryHint = false;
  bool _pip = false;
  bool _details = false;
  String? _problem;

  /// What the player found, or before the first frame what the platform
  /// declared: a portrait picture.
  final ValueNotifier<bool> _detectedPortrait = ValueNotifier(false);

  /// The record or danmaku settings panel (U.2f); one at a time, and not
  /// together with the details.
  final RoomPanelController _panels = RoomPanelController();

  /// Ticks when the IPTV guide should show the programme being watched
  /// (U.2g c16: the picture's guide button, the replay mark).
  final ValueNotifier<int> _guideReveal = ValueNotifier(0);

  /// The IPTV guide's column is folded away (wide windows, U.2g c16).
  bool _guideFolded = false;

  /// The local interaction in this room (U.2k).
  LocalRoomSession? _local;

  /// The display's refresh rate follows the video's frame rate (U.2i).
  RoomRefreshRate? _refreshRate;

  /// The list the room was opened from (U.2b2); null for a lone room.
  RoomPlaylist? _playlist;

  /// The portrait fullscreen's swipe between the rooms of [_playlist].
  late final RoomSwipeController _swipe = RoomSwipeController(onSwitch: _swipeTo);

  /// A room swiped away still stopping the player, or null: the next room
  /// starts once it is done, and every stop waits for the one before (the
  /// session takes one stop at a time).
  Future<void>? _handover;

  /// Counts the rooms shown: the page's room parts are built afresh for each.
  int _roomEpoch = 0;

  RoomPlatform get _platform => RoomPlatform.current();

  @override
  void initState() {
    super.initState();
    final (room, playlist) = switch (widget.route.arguments) {
      LiveRoomArgs(:final room, :final playlist) => (room, playlist),
      final LiveRoom room => (room, const <LiveRoom>[]),
      _ => (null, const <LiveRoom>[]),
    };
    if (room == null) {
      _problem = i18n('get_room_info_failed_retry');
      return;
    }
    final site = ref.read(sitesProvider).maybeOf(room.platform);
    if (site == null) {
      _problem = i18n('platform_retired');
      return;
    }
    final store = ref.read(storeProvider);
    _settings = store.settings;
    final standby = ref.read(playerStandbyProvider);
    _standby = standby;
    if (playlist.isNotEmpty) _playlist = RoomPlaylist(playlist, current: room);
    // The same room still playing in the floating window plays on here; any
    // other floating room stops (3.x `toLiveRoomDetail`).
    final adopted = FloatingRoom.instance.claim(room);
    final RoomRuntime runtime;
    if (adopted != null) {
      runtime = adopted;
    } else {
      final config = _engineConfig(store.settings);
      final key = engineConfigKey(config);
      // The player the last room left, when it is configured the same way.
      final session = standby.take(config: key) ?? ref.read(playbackSessionFactoryProvider)(config: config);
      runtime = _newRuntime(room, site, session: session, playerConfig: key);
    }
    _attachRoom(runtime);
    final session = runtime.session;
    final controller = runtime.controller;
    _panels.addListener(_onPanel);
    _refreshRate = RoomRefreshRate(session: session, settings: store.settings)..start();
    // F.1b: before the first frame the size the platform declares for the
    // line lays the room out (3.x `LiveStreamGeometryHint`); the decoder's
    // wins once known.
    _detectedPortrait.value = session.state.expectsPortrait;
    _shape = session.states.listen((state) {
      if (state.expectsPortrait != _detectedPortrait.value) _detectedPortrait.value = state.expectsPortrait;
    });
    if (adopted != null &&
        session.state.status == PlaybackStatus.playing &&
        store.settings.get(Settings.enableFullScreenDefault)) {
      // Back from the floating window the stream already plays.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _display == RoomDisplay.inline) unawaited(_enterFullscreen());
      });
    } else if (store.settings.get(Settings.enableFullScreenDefault)) {
      // 3.x entered fullscreen once the stream played.
      _autoFullscreen = session.states.listen((state) {
        if (state.status != PlaybackStatus.playing) return;
        unawaited(_autoFullscreen?.cancel());
        _autoFullscreen = null;
        if (mounted && _display == RoomDisplay.inline) unawaited(_enterFullscreen());
      });
    }
    if (adopted == null) unawaited(controller.start());
    // F.1c (3.x `LivePlayBackScope`): Android hands every back to the room
    // while it is open, before Flutter could pop it.
    if (_platform.android) unawaited(RoomBackChannel.instance.hold(this, _nativeBack));
  }

  /// The parts of [room] on [site], playing on [session].
  RoomRuntime _newRuntime(
    LiveRoom room,
    LiveSite site, {
    required PlaybackSession session,
    required Object? playerConfig,
  }) {
    final store = ref.read(storeProvider);
    final danmaku = ref.read(danmakuProvider);
    final controller = LiveRoomController(
      room: room,
      site: site,
      session: session,
      danmaku: danmaku.connectionFor(site.id),
      danmakuSupported: danmaku.supports(site.id),
      store: store,
      mobile: _platform.mobile,
      toast: (message) => AppNavigator.toast(message),
      // 3.x's automatic ASMR mode: Android only.
      sleepSessionOnStart: _platform.android && store.settings.get(Settings.enableAsmrSleepMode),
      network: ref.read(networkProbeProvider),
    );
    return RoomRuntime(
      controller: controller,
      session: session,
      orientation: RoomOrientationChoice(settings: store.settings, room: room),
      reconnect: ReconnectWatch(session.states),
      background: RoomBackgroundPolicy(controller: controller, settings: store.settings)..start(),
      playerConfig: playerConfig,
    );
  }

  /// Makes [runtime] the page's room, with this visit's local interaction
  /// (U.2k: it holds no subscription, so the room it talks to may be one the
  /// floating window hands back, U.2j) and mini window (U.2j).
  void _attachRoom(RoomRuntime runtime) {
    _runtime = runtime;
    final controller = _controller = runtime.controller;
    _orientation = runtime.orientation;
    _reconnect = runtime.reconnect;
    final settings = ref.read(storeProvider).settings;
    _local = LocalRoomSession(
      interaction: ref.read(localInteractionProvider),
      room: controller,
      overlayShown: () => localOverlayShown(settings),
      toast: (message) => AppNavigator.toast(message),
    );
    _mini =
        RoomMiniWindow(
            controller: controller,
            settings: settings,
            leaveFullscreen: _exitFullscreen,
            closeRoom: _closeOnPurpose,
          )
          ..addListener(_onMini)
          ..startAutoPip();
  }

  /// Lets go of the parts [_attachRoom] made.
  void _detachRoom() {
    _local?.dispose();
    _mini
      ?..removeListener(_onMini)
      ..dispose();
  }

  /// The portrait fullscreen's swipe let go past the switch (U.2b2): the
  /// room [step] places along the list.
  void _swipeTo(int step) {
    final playlist = _playlist;
    if (!mounted || playlist == null || !playlist.swipeable || _display != RoomDisplay.portraitFullscreen) return;
    _switchRoom(playlist.move(step));
  }

  /// Shows [room] in this page on the same player (3.x `switchRoom` kept the
  /// page too): the room before stops and lets the player go, then [room]
  /// starts on it. Swipes meanwhile wait their turn, and only the last room
  /// starts.
  void _switchRoom(LiveRoom room) {
    final old = _runtime;
    final site = ref.read(sitesProvider).maybeOf(room.platform);
    if (old == null || site == null) return;
    unawaited(_autoFullscreen?.cancel());
    _autoFullscreen = null;
    _panels.close();
    _detachRoom();
    final runtime = _newRuntime(room, site, session: old.session, playerConfig: old.playerConfig);
    setState(() {
      _attachRoom(runtime);
      // Everything of the room before is built afresh, the player too.
      _roomEpoch++;
      _playerKey = GlobalKey(debugLabel: 'room-player');
      _details = false;
      _entryHint = false;
    });
    Future<void> release() async {
      try {
        // Handed over only once stopped: a stop still running would stop
        // what the next room opens.
        await old.dispose(keep: (_) {});
      } on Object catch (error, stack) {
        developer.log('Releasing the room before failed', name: 'LivePlay', error: error, stackTrace: stack);
      }
    }

    final previous = _handover;
    final handover = _handover = previous == null ? release() : previous.then((_) => release());
    unawaited(
      handover.whenComplete(() {
        if (identical(_handover, handover)) _handover = null;
        if (mounted && identical(_runtime, runtime) && !runtime.disposed) unawaited(runtime.controller.start());
      }),
    );
  }

  /// The player settings (M9) as the engine's configuration.
  static MpvEngineConfig _engineConfig(SettingsStore settings) => MpvEngineConfig(
    platform: mpvPlatformOf(defaultTargetPlatform) ?? MpvPlatform.linux,
    hardwareDecoding: settings.get(Settings.enableCodec),
    customOutput: settings.get(Settings.customPlayerOutput),
    videoOutputDriver: settings.get(Settings.videoOutputDriver),
    hardwareDecoder: settings.get(Settings.videoHardwareDecoder),
    audioOutputDriver: settings.get(Settings.audioOutputDriver),
    androidCompatibility: settings.get(Settings.playerCompatMode),
    rtxVideoSuperResolution: settings.get(Settings.enableRtxVsr),
  );

  /// What decides whether a kept player fits ([PlayerStandby]): every field
  /// of [config] (it has no `==`).
  static Object engineConfigKey(MpvEngineConfig config) => (
    config.platform,
    config.hardwareDecoding,
    config.customOutput,
    config.videoOutputDriver,
    config.hardwareDecoder,
    config.audioOutputDriver,
    config.androidCompatibility,
    config.rtxVideoSuperResolution,
  );

  /// Picture-in-picture or the desktop mini window began or ended.
  void _onMini() {
    final mini = _mini;
    if (mounted && mini != null) setState(() => _pip = mini.compact);
  }

  /// The desktop mini window's ✕ (J3): the room closes without the floating
  /// window, back to the page before it.
  void _closeOnPurpose() {
    if (!mounted) return;
    _closingOnPurpose = true;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      AppNavigator.offAllNamed(RoutePath.kInitial);
    }
  }

  void _onPanel() {
    if (!mounted) return;
    setState(() {
      if (_panels.value != null) _details = false;
    });
  }

  @override
  void dispose() {
    unawaited(RoomBackChannel.instance.release(this));
    unawaited(_autoFullscreen?.cancel());
    unawaited(_shape?.cancel());
    _releaseOrientation?.cancel();
    final mini = _mini;
    if (mini != null) {
      mini.removeListener(_onMini);
      // A room leaving while the window is its mini window gives the window
      // back first.
      if (mini.desktop) unawaited(DesktopWindow.exitMini());
      mini.dispose();
    }
    final fullscreen = _display == RoomDisplay.fullscreen || _display == RoomDisplay.portraitFullscreen;
    if (fullscreen && _platform.mobile) unawaited(_restoreSystemUi(upright: _restorePortrait));
    // The brightness gesture overrides the window's only inside the room.
    unawaited(DeviceControls.resetBrightness());
    if (fullscreen && _platform.desktop) unawaited(DesktopWindow.setFullScreen(on: false));
    _refreshRate?.dispose();
    _swipe.dispose();
    _detectedPortrait.dispose();
    _guideReveal.dispose();
    _local?.dispose();
    _panels
      ..removeListener(_onPanel)
      ..dispose();
    final runtime = _runtime;
    if (runtime != null) {
      final floating = FloatingRoom.instance;
      final float = shouldFloatOnLeave(
        enabled: _settings.get(Settings.floatPlay),
        stage: runtime.controller.stage,
        suppressed: _closingOnPurpose,
        topRoute: liveRouteObserver.currentRoute.value,
      );
      final standby = _standby;
      if (float && floating.canShow) {
        floating.show(runtime);
      } else {
        final Future<void> Function() release;
        if (standby == null || _settings.get(Settings.useHardStopOnExit)) {
          release = runtime.dispose;
        } else {
          // "播放器强制销毁" off (3.x default): the stopped player waits for
          // the next room (F.1d).
          release = () => runtime.dispose(keep: (session) => standby.keep(session, config: runtime.playerConfig));
        }
        // A swipe still stopping the player goes first (U.2b2).
        final pending = _handover;
        unawaited(pending == null ? release() : pending.then((_) => release()));
      }
    }
    super.dispose();
  }

  /// Whether the stream is laid out as portrait: the room's orientation
  /// choice over what the player found, with portrait adaptation on.
  bool _portraitStream(_LayoutSettings settings) =>
      settings.adaptation &&
      isPortraitLayout(_orientation?.value ?? RoomOrientation.automatic, detected: _detectedPortrait.value);

  _LayoutSettings _layoutSettings() => (
    adaptation: ref.read(storeProvider).settings.get(Settings.enablePortraitStreamAdaptation),
    adaptiveHeight: ref.read(storeProvider).settings.get(Settings.portraitAdaptiveHeight),
    mode: ref.read(storeProvider).settings.get(Settings.portraitLayoutMode),
    policy: ref.read(storeProvider).settings.get(Settings.portraitFullscreenPolicy),
    collapsed: ref.read(storeProvider).settings.get(Settings.livePlayChatCollapsed),
    composer: ref.read(storeProvider).settings.get(Settings.localInteractionEnabled),
    swipe: ref.read(storeProvider).settings.get(Settings.portraitFullscreenSwipeSwitch),
  );

  /// Enters fullscreen: the portrait fullscreen for a portrait stream on a
  /// phone (U.2b change 5, whatever the room layout), else the landscape
  /// one; [landscape] forces a one-off landscape fullscreen ("横屏全屏") that
  /// turns the phone back upright when it ends.
  Future<void> _enterFullscreen({bool landscape = false}) async {
    if (_display != RoomDisplay.inline && _display != RoomDisplay.windowFullscreen) return;
    final settings = _layoutSettings();
    final orientation = FullscreenOrientation.of(settings.policy);
    final mobile = _platform.mobile;
    final portrait =
        !landscape &&
        portraitFullscreenEligible(
          mobile: mobile,
          portraitStream: _portraitStream(settings),
          adaptation: settings.adaptation,
          policy: settings.policy,
        );
    _releaseOrientation?.cancel();
    setState(() {
      _display = portrait ? RoomDisplay.portraitFullscreen : RoomDisplay.fullscreen;
      _entryHint = portrait;
    });
    if (!mobile) {
      // The whole window on desktops (3.x `WindowHelper`; window_manager).
      await DesktopWindow.setFullScreen(on: true);
      return;
    }
    _restorePortrait = landscape;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(
      portrait
          ? [DeviceOrientation.portraitUp]
          : !landscape && orientation == FullscreenOrientation.followSystem
          ? const []
          : [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    );
  }

  /// The portrait room's panel pulled down or its handle tapped: the
  /// portrait fullscreen, whatever the fullscreen orientation setting (3.x
  /// `enterPortraitFullScreen`).
  Future<void> _enterPortraitFullscreen() async {
    if (_display != RoomDisplay.inline || !_platform.mobile) return;
    _releaseOrientation?.cancel();
    setState(() {
      _display = RoomDisplay.portraitFullscreen;
      _entryHint = true;
    });
    _restorePortrait = false;
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  /// Back to the room page.
  Future<void> _exitFullscreen() async {
    final was = _display;
    if (was == RoomDisplay.inline) return;
    setState(() {
      _display = RoomDisplay.inline;
      _entryHint = false;
    });
    if (was == RoomDisplay.windowFullscreen) return;
    if (_platform.desktop) {
      await DesktopWindow.setFullScreen(on: false);
      return;
    }
    final upright = _restorePortrait;
    _restorePortrait = false;
    await _restoreSystemUi(upright: upright);
  }

  /// The system bars back; an [upright] phone is turned upright first and
  /// let go a moment later (3.x `exitFullscreenWithOrientationRestore`).
  Future<void> _restoreSystemUi({bool upright = false}) async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!upright) {
      await SystemChrome.setPreferredOrientations(const []);
      return;
    }
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _releaseOrientation?.cancel();
    _releaseOrientation = Timer(const Duration(seconds: 3), () {
      unawaited(SystemChrome.setPreferredOrientations(const []));
    });
  }

  /// The fullscreen button, double tap and F; in the in-window fullscreen
  /// they leave it (3.x).
  void _toggleFullscreen() => unawaited(_display == RoomDisplay.inline ? _enterFullscreen() : _exitFullscreen());

  /// Desktops: the in-window fullscreen (3.x `toggleWindowFullScreen`).
  void _toggleWindowFullscreen() {
    if (_display == RoomDisplay.windowFullscreen) {
      unawaited(_exitFullscreen());
    } else if (_display == RoomDisplay.inline) {
      setState(() => _display = RoomDisplay.windowFullscreen);
    }
  }

  void _toggleChat(bool collapsed) =>
      unawaited(ref.read(storeProvider).settings.set(Settings.livePlayChatCollapsed, !collapsed));

  void _toggleDetails() {
    _panels.close();
    setState(() => _details = !_details);
  }

  void _openDetails() {
    _panels.close();
    if (!_details) setState(() => _details = true);
  }

  void _closeDetails() {
    if (_details) setState(() => _details = false);
  }

  /// Whether back closes the room: nothing of the room's own is open.
  bool get _poppable =>
      _display == RoomDisplay.inline && !_details && _panels.value == null && !(_mini?.desktop ?? false);

  /// Android's back held by the room (F.1c, 3.x `LivePlayBackScope`): a
  /// dialog or sheet over the room closes first; then the room's own chain
  /// ([_back]); else the room closes, or the app goes back to the system
  /// when the room is the first page.
  Future<void> _nativeBack() async {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (ModalRoute.of(context)?.isCurrent == false) {
      await navigator.maybePop();
      return;
    }
    if (!_poppable) {
      _back();
      return;
    }
    if (!await navigator.maybePop()) await SystemNavigator.pop();
  }

  /// Back and Esc: a panel first, then the fullscreen, then the details,
  /// then the room.
  void _back() {
    final mini = _mini;
    if (mini != null && mini.desktop) {
      unawaited(mini.backToRoom());
    } else if (_panels.value != null) {
      _panels.close();
    } else if (_display != RoomDisplay.inline) {
      unawaited(_exitFullscreen());
    } else if (_details) {
      _closeDetails();
    }
  }

  /// The guide button and the replay mark (U.2g 按钮 8, 11): in fullscreen
  /// the guide opens on the right; on a wide window a folded column
  /// unfolds; then the guide scrolls to the programme being watched.
  void _revealGuide() {
    if (_display != RoomDisplay.inline) {
      _panels.open(RoomPanelKind.guide);
    } else if (_guideFolded) {
      setState(() => _guideFolded = false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _guideReveal.value++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return Scaffold(
        appBar: AppBar(),
        body: AppStatusView(type: AppStatusType.error, title: _problem, subtitle: ''),
      );
    }
    // The layout follows these settings; read here so a change rebuilds.
    final settings = (
      adaptation: watchSetting(ref, Settings.enablePortraitStreamAdaptation),
      adaptiveHeight: watchSetting(ref, Settings.portraitAdaptiveHeight),
      mode: watchSetting(ref, Settings.portraitLayoutMode),
      policy: watchSetting(ref, Settings.portraitFullscreenPolicy),
      collapsed: watchSetting(ref, Settings.livePlayChatCollapsed),
      composer: watchSetting(ref, Settings.localInteractionEnabled),
      swipe: watchSetting(ref, Settings.portraitFullscreenSwipeSwitch),
    );
    return RoomMiniScope(
      notifier: _mini!,
      child: LocalRoomScope(
        session: _local!,
        child: RoomPanelScope(
          notifier: _panels,
          child: IptvGuideScope(
            reveal: _revealGuide,
            // A room swiped to (U.2b2) builds its parts afresh.
            child: KeyedSubtree(
              key: ValueKey(_roomEpoch),
              child: ListenableBuilder(
                listenable: Listenable.merge([_orientation, _detectedPortrait]),
                builder: (context, _) => _page(context, controller, settings),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _page(BuildContext context, LiveRoomController controller, _LayoutSettings settings) {
    return PopScope(
      canPop: _poppable,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _back,
          const SingleActivator(LogicalKeyboardKey.keyF): () {
            if (!(_mini?.desktop ?? false)) _toggleFullscreen();
          },
          const SingleActivator(LogicalKeyboardKey.space): () => unawaited(controller.session.togglePlayPause()),
          // 3.x `VideoKeyboard`: arrows change the room's volume, R reloads.
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              unawaited(controller.setVolume(controller.volume + 0.05, save: true)),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              unawaited(controller.setVolume(controller.volume - 0.05, save: true)),
          const SingleActivator(LogicalKeyboardKey.keyR): () => unawaited(controller.load()),
          // F.1d: a keyboard's media keys (3.x `VideoKeyboard`).
          const SingleActivator(LogicalKeyboardKey.mediaPlay): () => unawaited(controller.session.resume()),
          const SingleActivator(LogicalKeyboardKey.mediaPause): () => unawaited(controller.session.pause()),
          const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () =>
              unawaited(controller.session.togglePlayPause()),
        },
        child: Focus(
          autofocus: true,
          child: _pip
              ? _player(controller, settings, arrangement: ControlsArrangement.inline)
              : _display == RoomDisplay.inline
              ? _buildInline(context, controller, settings)
              : _buildFullscreen(controller, settings),
        ),
      ),
    );
  }

  /// One player element for every layout (normal, fullscreen,
  /// picture-in-picture): its controls' state and the picture survive the
  /// switches instead of being built anew (M13.16). A new room swiped to
  /// gets a new one (U.2b2).
  GlobalKey _playerKey = GlobalKey(debugLabel: 'room-player');

  Widget _player(
    LiveRoomController controller,
    _LayoutSettings settings, {
    required ControlsArrangement arrangement,
    PicturePresentation presentation = PicturePresentation.plain,
    double covered = 0,
    WideBarActions? wide,
    VoidCallback? onBack,
    RoomSwipeController? swipe,
  }) => RoomPlayer(
    key: _playerKey,
    controller: controller,
    display: _display,
    arrangement: arrangement,
    platform: _platform,
    pip: _pip,
    portraitStream: _portraitStream(settings),
    presentation: presentation,
    overlayBottom: covered,
    wide: wide,
    orientation: _orientation!,
    reconnect: _reconnect,
    onToggleFullscreen: _toggleFullscreen,
    onWindowFullscreen: _platform.desktop ? _toggleWindowFullscreen : null,
    onBack: onBack ?? () => unawaited(_exitFullscreen()),
    onSwipeUp: _display == RoomDisplay.portraitFullscreen ? () => unawaited(_exitFullscreen()) : null,
    entryHint: _entryHint,
    onOpenGuide: _revealGuide,
    swipe: swipe,
  );

  /// The open panel, or nothing.
  Widget _panelOf(LiveRoomController controller, {required bool portrait}) => switch (_panels.value) {
    RoomPanelKind.record => RoomRecordPanel(
      key: const ValueKey('panel-record'),
      room: () => controller.room,
      qualities: () => controller.qualities,
      onClose: _panels.close,
      dragToClose: portrait,
    ),
    RoomPanelKind.danmaku => RoomDanmakuSettingsPanel(
      key: const ValueKey('panel-danmaku'),
      controller: controller,
      onClose: _panels.close,
      dragToClose: portrait,
    ),
    RoomPanelKind.guide => Material(
      key: const ValueKey('panel-guide'),
      elevation: 2,
      child: SafeArea(
        top: false,
        left: false,
        child: IptvGuideView(controller: controller, onClose: _panels.close, reveal: _guideReveal),
      ),
    ),
    // U.2k: the local interaction and its style page; the style by itself
    // from a composer's star.
    RoomPanelKind.localInteraction => LocalInteractionPanel(
      key: const ValueKey('panel-local'),
      onClose: _panels.close,
      dragToClose: portrait,
    ),
    RoomPanelKind.localStyle => LocalInteractionPanel(
      key: const ValueKey('panel-local-style'),
      onClose: _panels.close,
      dragToClose: portrait,
      startWithStyle: true,
    ),
    null => const SizedBox.shrink(key: ValueKey('no-panel')),
  };

  /// The panel sliding in: up from the picture's lower edge in [portrait],
  /// in from the right otherwise; at once when the system asks for less
  /// motion.
  Widget _panelLayer(LiveRoomController controller, {required bool portrait}) {
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: still ? Duration.zero : const Duration(milliseconds: 220),
      reverseDuration: still ? Duration.zero : const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
      transitionBuilder: (child, animation) => SlideTransition(
        position: Tween(begin: portrait ? const Offset(0, 1) : const Offset(1, 0), end: Offset.zero).animate(animation),
        child: child,
      ),
      child: _panelOf(controller, portrait: portrait),
    );
  }

  /// [below] with the panel on its right, [roomSidePanelWidth] wide and the
  /// full height (landscape, fullscreen, wide windows: over the chat
  /// column, never over the picture's left half).
  Widget _withSidePanel(LiveRoomController controller, Widget below) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth / 2 < roomSidePanelWidth ? constraints.maxWidth / 2 : roomSidePanelWidth;
      return Stack(
        fit: StackFit.expand,
        children: [
          below,
          Positioned(
            key: const ValueKey('live-play-side-panel'),
            top: 0,
            right: 0,
            bottom: 0,
            width: width,
            child: _panelLayer(controller, portrait: false),
          ),
        ],
      );
    },
  );

  /// [below] (everything under the picture) with the panel over all of it
  /// (portrait).
  Widget _withPanelBelow(LiveRoomController controller, Widget below) => ClipRect(
    child: Stack(
      fit: StackFit.expand,
      children: [
        below,
        Positioned.fill(key: const ValueKey('live-play-below-panel'), child: _panelLayer(controller, portrait: true)),
      ],
    ),
  );

  /// [below] with the panel over its lower part (a channel without chat on
  /// a phone, the portrait fullscreen).
  Widget _withPanelAtBottom(LiveRoomController controller, Widget below) => LayoutBuilder(
    builder: (context, constraints) => Stack(
      fit: StackFit.expand,
      children: [
        below,
        Positioned(
          key: const ValueKey('live-play-bottom-panel'),
          left: 0,
          right: 0,
          bottom: 0,
          height: constraints.maxHeight * 0.6,
          child: ClipRect(child: _panelLayer(controller, portrait: true)),
        ),
      ],
    ),
  );

  Widget _buildFullscreen(LiveRoomController controller, _LayoutSettings settings) => Scaffold(
    backgroundColor: OnVideoColors.ground,
    body: LayoutBuilder(
      builder: (context, constraints) {
        final arrangement = controlsArrangement(
          display: _display,
          page: RoomPageLayout.landscape,
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          mobile: _platform.mobile,
        );
        final portrait = _portraitStream(settings);
        final upright = arrangement == ControlsArrangement.portraitFullscreen;
        // U.2b2: the portrait fullscreen swipes through the list the room
        // came from, with its setting on.
        final playlist = _playlist;
        final swipe =
            upright &&
                _display == RoomDisplay.portraitFullscreen &&
                settings.swipe &&
                _platform.mobile &&
                playlist != null &&
                playlist.swipeable
            ? (_swipe..neighbours(previous: playlist.neighbour(-1), next: playlist.neighbour(1)))
            : null;
        final player = _player(
          controller,
          settings,
          arrangement: arrangement,
          presentation: portrait
              ? (upright ? PicturePresentation.portraitModes : PicturePresentation.ambient)
              // A landscape stream in the portrait fullscreen (swiped to, or
              // forced landscape) sits in the middle over the ambient
              // background (U.2b2).
              : _display == RoomDisplay.portraitFullscreen && upright
              ? PicturePresentation.ambient
              : PicturePresentation.plain,
          swipe: swipe,
        );
        final picture = swipe == null
            ? player
            : RoomSwipeStage(key: const ValueKey('live-play-swipe-stage'), controller: swipe, child: player);
        // Panels in the portrait fullscreen rise from the bottom (U.2b →
        // U.2f), elsewhere they come in from the right.
        return upright ? _withPanelAtBottom(controller, picture) : _withSidePanel(controller, picture);
      },
    ),
  );

  Widget _infoBar(LiveRoomController controller) =>
      RoomInfoBar(controller: controller, detailsOpen: _details, onToggleDetails: _toggleDetails);

  /// The details over [below] (the chat), sliding in unless the system asks
  /// for less motion.
  Widget _withDetails(LiveRoomController controller, Widget below) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        below,
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          reverseDuration: const Duration(milliseconds: 160),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: still
                ? child
                : SlideTransition(
                    position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(animation),
                    child: child,
                  ),
          ),
          child: _details
              ? RoomDetailsPanel(key: const ValueKey('details'), controller: controller, onClose: _closeDetails)
              : const SizedBox.shrink(key: ValueKey('no-details')),
        ),
      ],
    );
  }

  /// The strip, a divider and the chat with the details over it.
  Widget _chatColumn(LiveRoomController controller) => Column(
    children: [
      _infoBar(controller),
      const Divider(height: 1),
      Expanded(
        child: _withDetails(controller, ChatPanel(controller: controller, detailsOpen: _details)),
      ),
    ],
  );

  Widget _buildInline(BuildContext context, LiveRoomController controller, _LayoutSettings settings) => LayoutBuilder(
    builder: (context, page) {
      final portrait = _portraitStream(settings);
      final layout = roomPageLayout(
        width: page.maxWidth,
        height: page.maxHeight,
        portraitPanel: portraitPanelEligible(
          portraitStream: portrait,
          adaptation: settings.adaptation,
          adaptiveHeight: settings.adaptiveHeight,
          layoutMode: settings.mode,
        ),
      );
      return Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          leading: IconButton(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(AppIcons.back),
          ),
          title: RoomHeader(controller: controller, onDetails: _openDetails, windows: _platform.windows),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (controller.site.id == SiteIds.iptv) return _channel(controller, settings, layout, constraints);
              return switch (layout) {
                // A phone held sideways splits like a wide window, with the
                // narrow chat column of U.2e c17.
                RoomPageLayout.wide ||
                RoomPageLayout.landscape => _wide(controller, settings, constraints, portrait: portrait),
                RoomPageLayout.portraitPanel => _portraitPanel(controller, settings),
                RoomPageLayout.phone => _phone(controller, settings, constraints),
              };
            },
          ),
        ),
      );
    },
  );

  /// An IPTV channel (docs/ui/compare/U.2g c16, Z1): the guide where a room
  /// has its chat. Phone layout: the picture at 16:9 and the guide under it
  /// (3.x left that space empty); wide: the guide in the right column, which
  /// the same edge handle as the chat column's folds away (U.2d).
  Widget _channel(
    LiveRoomController controller,
    _LayoutSettings settings,
    RoomPageLayout layout,
    BoxConstraints constraints,
  ) {
    final guide = IptvGuideView(
      key: const ValueKey('live-play-guide-view'),
      controller: controller,
      reveal: _guideReveal,
    );
    if (layout == RoomPageLayout.wide || layout == RoomPageLayout.landscape) {
      final column = chatColumnWidth(constraints.maxWidth);
      return _withSidePanel(
        controller,
        Row(
          key: const ValueKey('live-play-channel-split'),
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _player(controller, settings, arrangement: ControlsArrangement.inline),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _ColumnHandle(
                        key: const ValueKey('live-play-guide-fold'),
                        folded: _guideFolded,
                        tooltip: i18n(_guideFolded ? 'live_play_guide_unfold' : 'live_play_guide_fold'),
                        onPressed: () => setState(() => _guideFolded = !_guideFolded),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!_guideFolded) ...[
              const VerticalDivider(width: 1),
              SizedBox(width: column, child: _withDetails(controller, guide)),
            ],
          ],
        ),
      );
    }
    final height = (constraints.maxWidth * 9 / 16).clamp(0.0, constraints.maxHeight * 0.6);
    final channel = Column(
      key: const ValueKey('live-play-channel-stack'),
      children: [
        SizedBox(
          height: height,
          child: _player(controller, settings, arrangement: ControlsArrangement.inline),
        ),
        Expanded(child: _withDetails(controller, guide)),
      ],
    );
    // The panels rise over everything under the picture (U.2f).
    return Stack(
      fit: StackFit.expand,
      children: [
        channel,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          top: height,
          child: ClipRect(child: _panelLayer(controller, portrait: true)),
        ),
      ],
    );
  }

  /// A phone, a tablet held upright, a narrow window (U.2d change 2): the
  /// 16:9 picture over the strip and the chat; panels cover everything under
  /// the picture (U.2f).
  Widget _phone(LiveRoomController controller, _LayoutSettings settings, BoxConstraints constraints) => Column(
    key: const ValueKey('live-play-portrait-stack'),
    children: [
      SizedBox(
        key: const ValueKey('live-play-video-box'),
        height: (constraints.maxWidth * 9 / 16).clamp(0.0, constraints.maxHeight * 0.6),
        child: _player(controller, settings, arrangement: ControlsArrangement.inline),
      ),
      Expanded(child: _withPanelBelow(controller, _chatColumn(controller))),
    ],
  );

  /// A portrait stream on a phone or a narrow window (U.2b): the picture
  /// under the three-stop panel.
  Widget _portraitPanel(LiveRoomController controller, _LayoutSettings settings) => PortraitPanelLayout(
    key: const ValueKey('live-play-portrait-panel'),
    mode: settings.mode,
    least: portraitPanelLeast + (settings.composer ? portraitPanelComposer : 0),
    mobile: _platform.mobile,
    onPortraitFullscreen: _platform.mobile ? () => unawaited(_enterPortraitFullscreen()) : null,
    onFullscreen: () => unawaited(_enterFullscreen(landscape: _platform.mobile)),
    player: (covered) => _player(controller, settings, arrangement: ControlsArrangement.inline, covered: covered),
    content: _chatColumn(controller),
    panels: _panelLayer(controller, portrait: true),
  );

  /// 840 and wider (U.2d): the picture beside the chat column (34 %, 300 to
  /// 400), which folds away from the bottom bar or its edge handle and stays
  /// folded for the next room (change 7). Landscape streams sit in a 16:9
  /// frame in the middle of the picture area (3.x `LivePlayVideoFrame`);
  /// portrait ones take its full height over the ambient background (U.2b
  /// change 13). Panels and the details cover the chat column, or come in
  /// from the right while it is folded (change 8).
  Widget _wide(
    LiveRoomController controller,
    _LayoutSettings settings,
    BoxConstraints constraints, {
    required bool portrait,
  }) {
    final collapsed = settings.collapsed;
    final chatWidth = chatColumnWidth(constraints.maxWidth);
    final still = MediaQuery.disableAnimationsOf(context);
    final player = _player(
      controller,
      settings,
      arrangement: ControlsArrangement.inline,
      presentation: portrait ? PicturePresentation.ambient : PicturePresentation.plain,
      wide: WideBarActions(chatCollapsed: collapsed, onToggleChat: () => _toggleChat(collapsed)),
    );
    final picture = ColoredBox(
      color: OnVideoColors.ground,
      child: portrait
          ? player
          : Center(
              child: AspectRatio(key: const ValueKey('live-play-video-frame'), aspectRatio: 16 / 9, child: player),
            ),
    );
    final scheme = Theme.of(context).colorScheme;
    final handle = _ColumnHandle(
      key: const ValueKey('live-play-chat-handle'),
      folded: collapsed,
      tooltip: i18n(collapsed ? 'live_play_show_chat' : 'live_play_hide_chat'),
      onPressed: () => _toggleChat(collapsed),
    );
    final row = Row(
      key: const ValueKey('live-play-desktop-split'),
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              picture,
              Positioned(right: 0, top: 0, bottom: 0, child: Center(child: handle)),
            ],
          ),
        ),
        AnimatedContainer(
          key: const ValueKey('live-play-chat-box'),
          duration: still ? Duration.zero : const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          width: collapsed ? 0 : chatWidth,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: chatWidth,
              maxWidth: chatWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: scheme.outlineVariant)),
                ),
                child: _chatColumn(controller),
              ),
            ),
          ),
        ),
      ],
    );
    return _withSidePanel(
      controller,
      collapsed && _details
          ? Stack(
              fit: StackFit.expand,
              children: [
                row,
                Positioned(
                  key: const ValueKey('live-play-side-details'),
                  top: 0,
                  right: 0,
                  bottom: 0,
                  width: constraints.maxWidth / 2 < roomSidePanelWidth ? constraints.maxWidth / 2 : roomSidePanelWidth,
                  child: Material(
                    color: scheme.surface,
                    elevation: 2,
                    child: RoomDetailsPanel(controller: controller, onClose: _closeDetails),
                  ),
                ),
              ],
            )
          : row,
    );
  }
}

/// The handle on the edge of a wide room's right column (the chat, U.2d
/// change 7; an IPTV channel's guide, U.2g 按钮 12): a 22 × 56 tab, 40 × 64
/// to touch; the chevron points the way the column goes.
class _ColumnHandle extends StatelessWidget {
  const new({required this.folded, required this.tooltip, required this.onPressed, super.key});

  final bool folded;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 64,
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 22,
              height: 56,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                ),
                child: Icon(
                  folded ? AppIcons.chatColumnUnfold : AppIcons.chatColumnFold,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
