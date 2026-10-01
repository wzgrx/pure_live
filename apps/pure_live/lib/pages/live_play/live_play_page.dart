import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/live_play/background_playback.dart';
import 'package:pure_live/pages/live_play/chat_panel.dart';
import 'package:pure_live/pages/live_play/player_view.dart';
import 'package:pure_live/pages/live_play/record_button.dart';
import 'package:pure_live/pages/live_play/room_controller.dart';
import 'package:pure_live/pages/live_play/room_menu_button.dart';
import 'package:pure_live/pages/live_play/room_panels.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';

/// The live room (argument: the `LiveRoom`) (3.x `lib/modules/live_play`).
///
/// Routes: `RoutePath.kLivePlay`.
///
/// Phones (up to 680 wide) stack the video, the room strip and the chat
/// tabs; wider windows put the chat beside the video (3.x's breakpoint).
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
  StreamSubscription<PlaybackState>? _autoFullscreen;
  bool _fullscreen = false;
  bool _pip = false;
  String? _problem;

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
      sleepSessionOnStart:
          defaultTargetPlatform == TargetPlatform.android && store.settings.get(Settings.enableAsmrSleepMode),
    );
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

  @override
  void dispose() {
    unawaited(_autoFullscreen?.cancel());
    PictureInPicture.active.removeListener(_onPip);
    if (_fullscreen && _mobile) unawaited(_restoreSystemUi());
    _background?.dispose();
    // The brightness gesture overrides the window's only inside the room.
    unawaited(DeviceControls.resetBrightness());
    _controller?.dispose();
    final session = _session;
    if (session != null) unawaited(session.dispose());
    super.dispose();
  }

  Future<void> _setFullscreen(bool value) async {
    if (value == _fullscreen) return;
    setState(() => _fullscreen = value);
    if (!_mobile) return;
    if (!value) {
      await _restoreSystemUi();
      return;
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // A portrait stream stays upright (3.x's portrait fullscreen).
    final portrait = _session?.state.isPortrait ?? false;
    await SystemChrome.setPreferredOrientations(
      portrait ? [DeviceOrientation.portraitUp] : [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight],
    );
  }

  Future<void> _restoreSystemUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const []);
  }

  void _toggleFullscreen() => unawaited(_setFullscreen(!_fullscreen));

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return Scaffold(
        appBar: AppBar(),
        body: AppStatusView(type: AppStatusType.error, title: _problem, subtitle: ''),
      );
    }
    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) _toggleFullscreen();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_fullscreen) _toggleFullscreen();
          },
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

  Widget _player(LiveRoomController controller) => RoomPlayer(
    controller: controller,
    fullscreen: _fullscreen,
    pip: _pip,
    mobile: _mobile,
    onToggleFullscreen: _toggleFullscreen,
    onBack: () => unawaited(_setFullscreen(false)),
  );

  Widget _buildFullscreen(LiveRoomController controller) =>
      Scaffold(backgroundColor: Colors.black, body: _player(controller));

  Widget _buildNormal(BuildContext context, LiveRoomController controller) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final showChat = controller.site.id != SiteIds.iptv;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => RoomTitle(room: controller.room),
        ),
        actions: [
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => FollowButton(room: controller.room, compact: compact),
          ),
          if (controller.site.id != SiteIds.iptv)
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => RecordButton(room: controller.room, compact: compact),
            ),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => RoomMenuButton(controller: controller, desktop: !_mobile, windows: _windows),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final infoBar = ListenableBuilder(
              listenable: controller,
              builder: (context, _) => RoomInfoBar(controller: controller),
            );
            if (!showChat) {
              return Column(
                children: [
                  Expanded(child: _player(controller)),
                  infoBar,
                ],
              );
            }
            if (constraints.maxWidth <= livePlayWideBreakpoint) {
              return Column(
                key: const ValueKey('live-play-portrait-stack'),
                children: [
                  StreamBuilder<PlaybackState>(
                    stream: controller.session.states,
                    initialData: controller.session.state,
                    builder: (context, snapshot) => AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      height: portraitVideoHeight(
                        width: constraints.maxWidth,
                        screenHeight: constraints.maxHeight,
                        portraitStream: snapshot.data?.isPortrait ?? false,
                        adaptation: watchSetting(ref, Settings.enablePortraitStreamAdaptation),
                        adaptiveHeight: watchSetting(ref, Settings.portraitAdaptiveHeight),
                        mode: watchSetting(ref, Settings.portraitLayoutMode),
                      ),
                      child: _player(controller),
                    ),
                  ),
                  infoBar,
                  const Divider(height: 1),
                  Expanded(child: ChatPanel(controller: controller)),
                ],
              );
            }
            final panelWidth = (constraints.maxWidth * 0.34).clamp(300.0, 400.0);
            return Row(
              key: const ValueKey('live-play-desktop-split'),
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: _player(controller)),
                      infoBar,
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: panelWidth,
                  child: ChatPanel(controller: controller),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
