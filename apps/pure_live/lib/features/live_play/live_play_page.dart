import 'dart:async';

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
import 'package:pure_live/features/live_play/layout/portrait_panel.dart';
import 'package:pure_live/features/live_play/layout/room_details.dart';
import 'package:pure_live/features/live_play/layout/room_header.dart';
import 'package:pure_live/features/live_play/layout/room_info_bar.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/features/live_play/logic/reconnect_watch.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/logic/room_layout.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/player/player_controls.dart';
import 'package:pure_live/features/live_play/player/player_view.dart';
import 'package:pure_live/features/live_play/player/room_composer.dart';
import 'package:pure_live/features/live_play/record/record_panel.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';

/// The live room (argument: the `LiveRoom`) (3.x `lib/modules/live_play`).
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
/// fullscreen, then close the details, then the room.
class LivePlayPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  ConsumerState<LivePlayPage> createState() => _LivePlayPageState();
}

/// The settings the page's layout follows, read once per build.
typedef _LayoutSettings = ({bool adaptation, bool adaptiveHeight, String mode, String policy, bool collapsed});

class _LivePlayPageState extends ConsumerState<LivePlayPage> {
  LiveRoomController? _controller;
  PlaybackSession? _session;
  RoomBackgroundPolicy? _background;
  RoomOrientationChoice? _orientation;
  ReconnectWatch? _reconnect;
  RoomComposer? _composer;
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

  /// What the player found: a portrait picture.
  final ValueNotifier<bool> _detectedPortrait = ValueNotifier(false);

  /// The record or danmaku settings panel (U.2f); one at a time, and not
  /// together with the details.
  final RoomPanelController _panels = RoomPanelController();

  RoomPlatform get _platform => RoomPlatform.current();

  @override
  void initState() {
    super.initState();
    final room = widget.route.arguments;
    if (room is! LiveRoom) {
      _problem = i18n('get_room_info_failed_retry');
      return;
    }
    final site = ref.read(sitesProvider).maybeOf(room.platform);
    if (site == null) {
      _problem = i18n('platform_retired');
      return;
    }
    final store = ref.read(storeProvider);
    final danmaku = ref.read(danmakuProvider);
    final session = _session = ref.read(playbackSessionFactoryProvider)(config: _engineConfig(store.settings));
    final controller = _controller = LiveRoomController(
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
    _orientation = RoomOrientationChoice(settings: store.settings, room: room);
    _panels.addListener(_onPanel);
    _reconnect = ReconnectWatch(session.states, now: controller.now);
    _background = RoomBackgroundPolicy(controller: controller, settings: store.settings)..start();
    _composer = ref.read(roomComposerProvider)?.call(controller);
    PictureInPicture.active.addListener(_onPip);
    _shape = session.states.listen((state) {
      if (state.isPortrait != _detectedPortrait.value) _detectedPortrait.value = state.isPortrait;
    });
    if (store.settings.get(Settings.enableFullScreenDefault)) {
      // 3.x entered fullscreen once the stream played.
      _autoFullscreen = session.states.listen((state) {
        if (state.status != PlaybackStatus.playing) return;
        unawaited(_autoFullscreen?.cancel());
        _autoFullscreen = null;
        if (mounted && _display == RoomDisplay.inline) unawaited(_enterFullscreen());
      });
    }
    unawaited(controller.start());
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

  void _onPip() {
    if (mounted) setState(() => _pip = PictureInPicture.active.value);
  }

  void _onPanel() {
    if (!mounted) return;
    setState(() {
      if (_panels.value != null) _details = false;
    });
  }

  @override
  void dispose() {
    unawaited(_autoFullscreen?.cancel());
    unawaited(_shape?.cancel());
    _releaseOrientation?.cancel();
    PictureInPicture.active.removeListener(_onPip);
    final fullscreen = _display == RoomDisplay.fullscreen || _display == RoomDisplay.portraitFullscreen;
    if (fullscreen && _platform.mobile) unawaited(_restoreSystemUi(upright: _restorePortrait));
    _background?.dispose();
    // The brightness gesture overrides the window's only inside the room.
    unawaited(DeviceControls.resetBrightness());
    if (fullscreen && _platform.desktop) unawaited(DesktopWindow.setFullScreen(on: false));
    _composer?.dispose();
    _reconnect?.dispose();
    _orientation?.dispose();
    _detectedPortrait.dispose();
    _panels
      ..removeListener(_onPanel)
      ..dispose();
    _controller?.dispose();
    final session = _session;
    if (session != null) unawaited(session.dispose());
    super.dispose();
  }

  /// Whether the stream is laid out as portrait: the room's orientation
  /// choice over what the player found, with portrait adaptation on.
  bool _portraitStream(_LayoutSettings settings) =>
      settings.adaptation &&
      isPortraitLayout(_orientation?.value ?? RoomOrientation.automatic, detected: _detectedPortrait.value);

  _LayoutSettings _settings() => (
    adaptation: ref.read(storeProvider).settings.get(Settings.enablePortraitStreamAdaptation),
    adaptiveHeight: ref.read(storeProvider).settings.get(Settings.portraitAdaptiveHeight),
    mode: ref.read(storeProvider).settings.get(Settings.portraitLayoutMode),
    policy: ref.read(storeProvider).settings.get(Settings.portraitFullscreenPolicy),
    collapsed: ref.read(storeProvider).settings.get(Settings.livePlayChatCollapsed),
  );

  /// Enters fullscreen: the portrait fullscreen for a portrait stream on a
  /// phone (U.2b change 5, whatever the room layout), else the landscape
  /// one; [landscape] forces a one-off landscape fullscreen ("横屏全屏") that
  /// turns the phone back upright when it ends.
  Future<void> _enterFullscreen({bool landscape = false}) async {
    if (_display != RoomDisplay.inline && _display != RoomDisplay.windowFullscreen) return;
    final settings = _settings();
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

  /// Back and Esc: a panel first, then the fullscreen, then the details,
  /// then the room.
  void _back() {
    if (_panels.value != null) {
      _panels.close();
    } else if (_display != RoomDisplay.inline) {
      unawaited(_exitFullscreen());
    } else if (_details) {
      _closeDetails();
    }
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
    );
    return RoomPanelScope(
      notifier: _panels,
      child: RoomComposerScope(
        composer: _composer,
        child: ListenableBuilder(
          listenable: Listenable.merge([_orientation, _detectedPortrait]),
          builder: (context, _) => _page(context, controller, settings),
        ),
      ),
    );
  }

  Widget _page(BuildContext context, LiveRoomController controller, _LayoutSettings settings) {
    return PopScope(
      canPop: _display == RoomDisplay.inline && !_details && _panels.value == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _back,
          const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
          const SingleActivator(LogicalKeyboardKey.space): () => unawaited(controller.session.togglePlayPause()),
          // 3.x `VideoKeyboard`: arrows change the room's volume, R reloads.
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              unawaited(controller.setVolume(controller.volume + 0.05, save: true)),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              unawaited(controller.setVolume(controller.volume - 0.05, save: true)),
          const SingleActivator(LogicalKeyboardKey.keyR): () => unawaited(controller.load()),
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
  /// switches instead of being built anew (M13.16).
  final GlobalKey _playerKey = GlobalKey(debugLabel: 'room-player');

  Widget _player(
    LiveRoomController controller,
    _LayoutSettings settings, {
    required ControlsArrangement arrangement,
    PicturePresentation presentation = PicturePresentation.plain,
    double covered = 0,
    WideBarActions? wide,
    VoidCallback? onBack,
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
    reconnect: _reconnect!,
    onToggleFullscreen: _toggleFullscreen,
    onWindowFullscreen: _platform.desktop ? _toggleWindowFullscreen : null,
    onBack: onBack ?? () => unawaited(_exitFullscreen()),
    onSwipeUp: _display == RoomDisplay.portraitFullscreen ? () => unawaited(_exitFullscreen()) : null,
    entryHint: _entryHint,
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
        final player = _player(
          controller,
          settings,
          arrangement: arrangement,
          presentation: !portrait
              ? PicturePresentation.plain
              : arrangement == ControlsArrangement.portraitFullscreen
              ? PicturePresentation.portraitModes
              : PicturePresentation.ambient,
        );
        // Panels in the portrait fullscreen rise from the bottom (U.2b →
        // U.2f), elsewhere they come in from the right.
        return arrangement == ControlsArrangement.portraitFullscreen
            ? _withPanelAtBottom(controller, player)
            : _withSidePanel(controller, player);
      },
    ),
  );

  Widget _infoBar(LiveRoomController controller) => RoomInfoBar(
    controller: controller,
    detailsOpen: _details,
    onToggleDetails: _toggleDetails,
    onReopen: _reconnect!.expectReopen,
  );

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
      if (layout == RoomPageLayout.landscape) {
        // A phone held sideways: the landscape arrangement on the page (its
        // back leaves the room).
        return Scaffold(
          backgroundColor: OnVideoColors.ground,
          body: _withSidePanel(
            controller,
            _player(
              controller,
              settings,
              arrangement: ControlsArrangement.landscape,
              presentation: portrait ? PicturePresentation.ambient : PicturePresentation.plain,
              onBack: () => Navigator.of(context).maybePop(),
            ),
          ),
        );
      }
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
                RoomPageLayout.wide => _wide(controller, settings, constraints, portrait: portrait),
                RoomPageLayout.portraitPanel => _portraitPanel(controller, settings),
                RoomPageLayout.phone || RoomPageLayout.landscape => _phone(controller, settings, constraints),
              };
            },
          ),
        ),
      );
    },
  );

  /// A channel (no chat): the picture with the strip under it.
  Widget _channel(
    LiveRoomController controller,
    _LayoutSettings settings,
    RoomPageLayout layout,
    BoxConstraints constraints,
  ) {
    final channel = Column(
      children: [
        Expanded(child: _player(controller, settings, arrangement: ControlsArrangement.inline)),
        _infoBar(controller),
        if (_details)
          SizedBox(
            height: constraints.maxHeight * 0.45,
            child: RoomDetailsPanel(controller: controller, onClose: _closeDetails),
          ),
      ],
    );
    if (layout == RoomPageLayout.wide) return _withSidePanel(controller, channel);
    // A channel on a phone has no chat under the picture: the panel rises
    // over the lower part instead.
    return _withPanelAtBottom(controller, channel);
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
    final handle = Tooltip(
      message: i18n(collapsed ? 'live_play_show_chat' : 'live_play_hide_chat'),
      child: InkWell(
        key: const ValueKey('live-play-chat-handle'),
        onTap: () => _toggleChat(collapsed),
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
                  collapsed ? AppIcons.chatColumnUnfold : AppIcons.chatColumnFold,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
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
