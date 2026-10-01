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
import 'package:pure_live/features/live_play/dialogs/iptv_guide.dart';
import 'package:pure_live/features/live_play/layout/room_details.dart';
import 'package:pure_live/features/live_play/layout/room_header.dart';
import 'package:pure_live/features/live_play/layout/room_info_bar.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/features/live_play/logic/reconnect_watch.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/player/player_view.dart';
import 'package:pure_live/features/live_play/record/record_panel.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';

/// The live room (argument: the `LiveRoom`) (3.x `lib/modules/live_play`).
///
/// Routes: `RoutePath.kLivePlay`.
///
/// Phones (up to 680 wide) stack the video, the room strip and the chat
/// tabs; wider windows put the chat beside the video (3.x's breakpoint).
/// The room details open over the chat (never over the picture). The record
/// and danmaku settings panels (U.2f) open under the picture in portrait and
/// on the right otherwise, never over the picture's left half. Back and Esc
/// close a panel first, then leave fullscreen, then close the details, then
/// the room.
class LivePlayPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  ConsumerState<LivePlayPage> createState() => _LivePlayPageState();
}

/// 3.x's phone/desktop breakpoint for the room layout.
const double livePlayWideBreakpoint = 680;

bool get _mobile => defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

bool get _android => defaultTargetPlatform == TargetPlatform.android;

bool get _windows => defaultTargetPlatform == TargetPlatform.windows;

/// The height of the picture of a portrait stream on a phone held upright
/// (3.x `enablePortraitStreamAdaptation`, `portraitAdaptiveHeight`,
/// `portraitLayoutMode`): `balanced` up to 3:4 or 55 % of the screen,
/// `immersive` up to 9:16 or 75 %, `compatibility` (or adaptation off) the
/// usual 16:9.
double portraitVideoHeight({
  required double width,
  required double screenHeight,
  required bool portraitStream,
  required bool adaptation,
  required bool adaptiveHeight,
  required String mode,
}) {
  final standard = width * 9 / 16;
  if (!portraitStream || !adaptation || !adaptiveHeight) return standard;
  final (ratio, share) = switch (mode) {
    'immersive' => (16 / 9, 0.75),
    'compatibility' => (9 / 16, 1.0),
    _ => (4 / 3, 0.55),
  };
  final height = width * ratio;
  final limit = screenHeight * share;
  return height.clamp(standard, limit < standard ? standard : limit);
}

class _LivePlayPageState extends ConsumerState<LivePlayPage> {
  LiveRoomController? _controller;
  PlaybackSession? _session;
  RoomBackgroundPolicy? _background;
  RoomOrientationChoice? _orientation;
  ReconnectWatch? _reconnect;
  StreamSubscription<PlaybackState>? _autoFullscreen;
  bool _fullscreen = false;
  bool _pip = false;
  bool _details = false;
  String? _problem;

  /// The record or danmaku settings panel (U.2f); one at a time, and not
  /// together with the details.
  final RoomPanelController _panels = RoomPanelController();

  /// Ticks when the IPTV guide should show the programme being watched
  /// (U.2g c16: the picture's guide button, the replay mark).
  final ValueNotifier<int> _guideReveal = ValueNotifier(0);

  /// The IPTV guide's column is folded away (wide windows, U.2g c16).
  bool _guideFolded = false;

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
      mobile: _mobile,
      toast: (message) => AppNavigator.toast(message),
      // 3.x's automatic ASMR mode: Android only.
      sleepSessionOnStart: _android && store.settings.get(Settings.enableAsmrSleepMode),
      network: ref.read(networkProbeProvider),
    );
    _orientation = RoomOrientationChoice(settings: store.settings, room: room);
    _panels.addListener(_onPanel);
    _reconnect = ReconnectWatch(session.states, now: controller.now);
    _background = RoomBackgroundPolicy(controller: controller, settings: store.settings)..start();
    PictureInPicture.active.addListener(_onPip);
    if (store.settings.get(Settings.enableFullScreenDefault)) {
      // 3.x entered fullscreen once the stream played.
      _autoFullscreen = session.states.listen((state) {
        if (state.status != PlaybackStatus.playing) return;
        unawaited(_autoFullscreen?.cancel());
        _autoFullscreen = null;
        if (mounted && !_fullscreen) unawaited(_setFullscreen(true));
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
    PictureInPicture.active.removeListener(_onPip);
    if (_fullscreen && _mobile) unawaited(_restoreSystemUi());
    _background?.dispose();
    // The brightness gesture overrides the window's only inside the room.
    unawaited(DeviceControls.resetBrightness());
    if (_fullscreen && !_mobile) unawaited(DesktopWindow.setFullScreen(on: false));
    _reconnect?.dispose();
    _orientation?.dispose();
    _panels
      ..removeListener(_onPanel)
      ..dispose();
    _guideReveal.dispose();
    _controller?.dispose();
    final session = _session;
    if (session != null) unawaited(session.dispose());
    super.dispose();
  }

  /// Whether the stream is laid out as portrait: the room's orientation
  /// choice over what the player found.
  bool get _portraitStream =>
      isPortraitLayout(_orientation?.value ?? RoomOrientation.automatic, detected: _session?.state.isPortrait ?? false);

  Future<void> _setFullscreen(bool value) async {
    if (value == _fullscreen) return;
    setState(() => _fullscreen = value);
    if (!_mobile) {
      // The whole window on desktops (3.x `WindowHelper`; window_manager).
      await DesktopWindow.setFullScreen(on: value);
      return;
    }
    if (!value) {
      await _restoreSystemUi();
      return;
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // A portrait stream stays upright (3.x's portrait fullscreen).
    await SystemChrome.setPreferredOrientations(
      _portraitStream
          ? [DeviceOrientation.portraitUp]
          : [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    );
  }

  Future<void> _restoreSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const []);
  }

  void _toggleFullscreen() => unawaited(_setFullscreen(!_fullscreen));

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
    } else if (_fullscreen) {
      _toggleFullscreen();
    } else if (_details) {
      _closeDetails();
    }
  }

  /// The guide button and the replay mark (U.2g 按钮 8, 11): in fullscreen
  /// the guide opens on the right; on a wide window a folded column
  /// unfolds; then the guide scrolls to the programme being watched.
  void _revealGuide() {
    if (_fullscreen) {
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
    return RoomPanelScope(
      notifier: _panels,
      child: IptvGuideScope(reveal: _revealGuide, child: _page(context, controller)),
    );
  }

  Widget _page(BuildContext context, LiveRoomController controller) {
    return PopScope(
      canPop: !_fullscreen && !_details && _panels.value == null,
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
              ? _player(controller)
              : _fullscreen
              ? _buildFullscreen(controller)
              : _buildNormal(context, controller),
        ),
      ),
    );
  }

  /// One player element for every layout (normal, fullscreen,
  /// picture-in-picture): its controls' state and the picture survive the
  /// switches instead of being built anew (M13.16).
  final GlobalKey _playerKey = GlobalKey(debugLabel: 'room-player');

  Widget _player(LiveRoomController controller) => RoomPlayer(
    key: _playerKey,
    controller: controller,
    fullscreen: _fullscreen,
    pip: _pip,
    mobile: _mobile,
    android: _android,
    orientation: _orientation!,
    reconnect: _reconnect!,
    onToggleFullscreen: _toggleFullscreen,
    onBack: () => unawaited(_setFullscreen(false)),
    onOpenGuide: _revealGuide,
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

  Widget _buildFullscreen(LiveRoomController controller) =>
      Scaffold(backgroundColor: OnVideoColors.ground, body: _withSidePanel(controller, _player(controller)));

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

  /// An IPTV channel (docs/ui/compare/U.2g c16, Z1): the guide where a room
  /// has its chat. Portrait: the picture at 16:9 and the guide under it (3.x
  /// left that space empty); wide: the guide in the right column, which a
  /// handle on its edge folds away.
  Widget _buildChannel(LiveRoomController controller, BoxConstraints constraints) {
    final guide = IptvGuideView(
      key: const ValueKey('live-play-guide-view'),
      controller: controller,
      reveal: _guideReveal,
    );
    if (constraints.maxWidth > livePlayWideBreakpoint) {
      final column = (constraints.maxWidth * 0.34).clamp(300.0, 400.0);
      return _withSidePanel(
        controller,
        Row(
          key: const ValueKey('live-play-channel-split'),
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _player(controller),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: _GuideFoldHandle(
                        folded: _guideFolded,
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
    final channel = Column(
      key: const ValueKey('live-play-channel-stack'),
      children: [
        SizedBox(height: constraints.maxWidth * 9 / 16, child: _player(controller)),
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
          top: constraints.maxWidth * 9 / 16,
          child: ClipRect(child: _panelLayer(controller, portrait: true)),
        ),
      ],
    );
  }

  Widget _buildNormal(BuildContext context, LiveRoomController controller) {
    final showChat = controller.site.id != SiteIds.iptv;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(AppIcons.back),
        ),
        title: RoomHeader(controller: controller, onDetails: _openDetails, windows: _windows),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (!showChat) return _buildChannel(controller, constraints);
            if (constraints.maxWidth <= livePlayWideBreakpoint) {
              return Column(
                key: const ValueKey('live-play-portrait-stack'),
                children: [
                  ListenableBuilder(
                    listenable: _orientation!,
                    builder: (context, _) => StreamBuilder<PlaybackState>(
                      stream: controller.session.states,
                      initialData: controller.session.state,
                      builder: (context, snapshot) => AnimatedContainer(
                        key: const ValueKey('live-play-video-box'),
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        height: portraitVideoHeight(
                          width: constraints.maxWidth,
                          screenHeight: constraints.maxHeight,
                          portraitStream: isPortraitLayout(
                            _orientation!.value,
                            detected: snapshot.data?.isPortrait ?? false,
                          ),
                          adaptation: watchSetting(ref, Settings.enablePortraitStreamAdaptation),
                          adaptiveHeight: watchSetting(ref, Settings.portraitAdaptiveHeight),
                          mode: watchSetting(ref, Settings.portraitLayoutMode),
                        ),
                        child: _player(controller),
                      ),
                    ),
                  ),
                  // U.2f: a panel covers everything under the picture.
                  Expanded(
                    child: _withPanelBelow(
                      controller,
                      Column(
                        children: [
                          _infoBar(controller),
                          const Divider(height: 1),
                          Expanded(
                            child: _withDetails(controller, ChatPanel(controller: controller, detailsOpen: _details)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }
            final panelWidth = (constraints.maxWidth * 0.34).clamp(300.0, 400.0);
            return _withSidePanel(
              controller,
              Row(
                key: const ValueKey('live-play-desktop-split'),
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(child: _player(controller)),
                        _infoBar(controller),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  SizedBox(
                    width: panelWidth,
                    child: _withDetails(controller, ChatPanel(controller: controller, detailsOpen: _details)),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The handle on the edge of a wide channel's guide column: folds it away
/// and back (U.2g 按钮 12; the same handle as the chat column's in U.2d).
class _GuideFoldHandle extends StatelessWidget {
  const new({required this.folded, required this.onPressed});

  final bool folded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: i18n(folded ? 'live_play_guide_unfold' : 'live_play_guide_fold'),
      child: Material(
        key: const ValueKey('live-play-guide-fold'),
        color: scheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
        child: InkWell(
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
          onTap: onPressed,
          child: SizedBox(
            width: 22,
            height: 56,
            child: Icon(folded ? AppIcons.unfoldLeft : AppIcons.forward, size: 18, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
