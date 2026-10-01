import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/network.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/player/player_view.dart' show videoFits;
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings.dart';
import 'package:pure_live/shared/rooms/room_menu.dart';
import 'package:pure_live/tv/room/tv_room_overlays.dart';
import 'package:pure_live/tv/tv_navigation.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_room_dialog.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';

/// The player settings (M9) as the engine's configuration (the phone room's
/// rule, M13.3).
MpvEngineConfig tvEngineConfig(SettingsStore settings) => MpvEngineConfig(
  platform: mpvPlatformOf(defaultTargetPlatform) ?? MpvPlatform.linux,
  hardwareDecoding: settings.get(Settings.enableCodec),
  customOutput: settings.get(Settings.customPlayerOutput),
  videoOutputDriver: settings.get(Settings.videoOutputDriver),
  hardwareDecoder: settings.get(Settings.videoHardwareDecoder),
  audioOutputDriver: settings.get(Settings.audioOutputDriver),
  androidCompatibility: settings.get(Settings.playerCompatMode),
  rtxVideoSuperResolution: settings.get(Settings.enableRtxVsr),
);

/// The basic TV room (pure_live_TV `LivePlayPage` and `PlayerKeyScope`;
/// arguments: [TvRoomArgs] or a lone `LiveRoom`).
///
/// The picture fills the screen with the flying danmaku over it. The remote:
/// - OK shows or hides the controls (quality, line, danmaku, follow,
///   refresh, room list); on a failed or offline room OK retries;
/// - Up and Down switch to the previous or next room of the list the room
///   was opened from (presses within 300 ms add up, then one switch), the
///   list wraps around; a banner names the new room;
/// - Left, Right or Menu open the room list on the side;
/// - Back closes the list, then the controls, then leaves, telling the page
///   below which room was shown last (its card takes the focus).
///
/// The logic is the phone room's `LiveRoomController` (one per room, with
/// its own playback session); only the layout and the keys are the TV's.
/// The fuller TV room (programme guide, catch-up, danmaku panel) is M14.2.
class TvLivePlayPage extends ConsumerStatefulWidget {
  /// Creates the room for [route].
  const new({required this.route, super.key});

  /// The path and arguments the room was opened with.
  final RouteArgs route;

  @override
  ConsumerState<TvLivePlayPage> createState() => TvLivePlayPageState();
}

/// The TV room's state (tests read [index] and [controller]).
class TvLivePlayPageState extends ConsumerState<TvLivePlayPage> {
  final FocusNode _keys = FocusNode(debugLabel: 'tv room keys');
  final FocusNode _firstControl = FocusNode(debugLabel: 'tv room first control');
  List<LiveRoom> _playlist = const [];
  int _index = 0;
  LiveRoomController? _controller;
  PlaybackSession? _session;
  RoomBackgroundPolicy? _background;
  String? _problem;
  bool _controls = false;
  bool _panel = false;
  bool _banner = false;
  Timer? _hideControls;
  Timer? _hideBanner;
  Timer? _debounce;
  int _pendingDelta = 0;
  ValueNotifier<LiveRoom?>? _shown;

  /// How long the controls stay without a key.
  static const Duration controlsTimeout = Duration(seconds: 6);

  /// Presses within this window add up to one switch.
  static const Duration switchWindow = Duration(milliseconds: 300);

  /// How long the banner of a new room stays.
  static const Duration bannerTime = Duration(seconds: 3);

  /// The room's logic; null when the arguments were unusable.
  LiveRoomController? get controller => _controller;

  /// The room's place in the list.
  int get index => _index;

  /// The list switched through.
  List<LiveRoom> get playlist => _playlist;

  @override
  void initState() {
    super.initState();
    final arguments = widget.route.arguments;
    final (room, list) = switch (arguments) {
      final TvRoomArgs args => (args.room, args.playlist),
      final LiveRoom room => (room, const <LiveRoom>[]),
      _ => (null, const <LiveRoom>[]),
    };
    if (room == null) {
      _problem = i18n('get_room_info_failed_retry');
      return;
    }
    if (arguments is TvRoomArgs) _shown = arguments.shown;
    final at = list.indexWhere(room.hasSameIdentity);
    _playlist = at < 0 ? [room, ...list] : list;
    _index = at < 0 ? 0 : at;
    _open(_playlist[_index]);
  }

  void _open(LiveRoom room) {
    _closeRoom();
    final site = ref.read(sitesProvider).maybeOf(room.platform);
    if (site == null) {
      _problem = i18n('platform_retired');
      return;
    }
    _problem = null;
    _shown?.value = room;
    final store = ref.read(storeProvider);
    final danmaku = ref.read(danmakuProvider);
    final session = _session = ref.read(playbackSessionFactoryProvider)(config: tvEngineConfig(store.settings));
    final controller = _controller = LiveRoomController(
      room: room,
      site: site,
      session: session,
      danmaku: danmaku.connectionFor(site.id),
      danmakuSupported: danmaku.supports(site.id),
      store: store,
      // A TV box plays at full volume; the TV's own volume governs.
      mobile: defaultTargetPlatform == TargetPlatform.android,
      toast: (message) => AppNavigator.toast(message),
      network: ref.read(networkProbeProvider),
    );
    _background = RoomBackgroundPolicy(controller: controller, settings: store.settings)..start();
    unawaited(controller.start());
  }

  void _closeRoom() {
    _background?.dispose();
    _background = null;
    _controller?.dispose();
    _controller = null;
    final session = _session;
    _session = null;
    if (session != null) unawaited(session.dispose());
  }

  @override
  void dispose() {
    _hideControls?.cancel();
    _hideBanner?.cancel();
    _debounce?.cancel();
    _closeRoom();
    _keys.dispose();
    _firstControl.dispose();
    super.dispose();
  }

  LiveRoom? get _room => _controller?.room ?? (_playlist.isEmpty ? null : _playlist[_index]);

  void _showControls() {
    setState(() {
      _controls = true;
      _panel = false;
    });
    _touch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controls && _firstControl.context != null) _firstControl.requestFocus();
    });
  }

  /// Restarts the controls' timeout (a key or a choice in them).
  void _touch() {
    _hideControls?.cancel();
    _hideControls = Timer(controlsTimeout, () {
      if (mounted && _controls) _hide();
    });
  }

  void _hide() {
    _hideControls?.cancel();
    setState(() {
      _controls = false;
      _panel = false;
    });
    _keys.requestFocus();
  }

  void _openPanel() {
    _hideControls?.cancel();
    setState(() {
      _panel = true;
      _controls = false;
    });
  }

  /// Queues a switch by [delta] rooms; presses within [switchWindow] add up.
  void switchBy(int delta) {
    if (_playlist.length < 2) {
      AppNavigator.toast(i18n('tv_no_other_room'));
      return;
    }
    _pendingDelta += delta;
    _debounce?.cancel();
    _debounce = Timer(switchWindow, () {
      final total = _pendingDelta;
      _pendingDelta = 0;
      if (total != 0 && mounted) switchTo((_index + total) % _playlist.length);
    });
  }

  /// Shows room [index] of the list.
  void switchTo(int index) {
    if (index < 0 || index >= _playlist.length) return;
    final wasPanel = _panel;
    setState(() {
      _index = index;
      _open(_playlist[index]);
      _panel = false;
      _banner = true;
    });
    _hideBanner?.cancel();
    _hideBanner = Timer(bannerTime, () {
      if (mounted) setState(() => _banner = false);
    });
    if (wasPanel || _controls) _keys.requestFocus();
  }

  bool get _blocked {
    final controller = _controller;
    if (controller == null) return true;
    return switch (controller.stage) {
      RoomStage.failed || RoomStage.offline || RoomStage.unplayable => true,
      RoomStage.loading => false,
      RoomStage.playing => controller.session.state.status == PlaybackStatus.error,
    };
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_panel) {
      // The list walks by focus; Left closes it.
      if (key == LogicalKeyboardKey.arrowLeft) {
        _hide();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final up = key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.channelUp;
    final down = key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.channelDown;
    if (up || down) {
      switchBy(up ? -1 : 1);
      if (_controls) _touch();
      return KeyEventResult.handled;
    }
    if (_controls) {
      _touch();
      // Left, Right and OK belong to the buttons.
      return KeyEventResult.ignored;
    }
    if (isTvConfirmKey(key)) {
      if (event is KeyRepeatEvent) return KeyEventResult.handled;
      final controller = _controller;
      if (_blocked) {
        if (controller != null) {
          unawaited(controller.stage == RoomStage.offline ? controller.load() : controller.retry());
        }
      } else {
        _showControls();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.contextMenu ||
        key == LogicalKeyboardKey.info) {
      _openPanel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _pickQuality() async {
    final controller = _controller;
    if (controller == null || controller.qualities.isEmpty) return;
    _hideControls?.cancel();
    final picked = await showTvChoice<int>(
      context,
      title: i18n('tv_quality'),
      current: controller.qualityIndex,
      options: [
        for (final (index, quality) in controller.qualities.indexed) TvChoice(value: index, label: quality.quality),
      ],
    );
    if (picked != null && picked != controller.qualityIndex) unawaited(controller.selectQuality(picked));
    if (mounted && _controls) _touch();
  }

  Future<void> _pickLine() async {
    final controller = _controller;
    if (controller == null) return;
    final state = controller.session.state;
    if (state.lineCount < 2) return;
    _hideControls?.cancel();
    final picked = await showTvChoice<int>(
      context,
      title: i18n('tv_line'),
      current: state.lineIndex,
      options: [
        for (var index = 0; index < state.lineCount; index++)
          TvChoice(
            value: index,
            label: i18n('toolbox_line', args: {'index': '${index + 1}'}),
          ),
      ],
    );
    if (picked != null && picked != state.lineIndex) unawaited(controller.selectLine(picked));
    if (mounted && _controls) _touch();
  }

  Future<void> _toggleFollow({required bool followed}) async {
    final room = _room;
    if (room == null) return;
    final store = ref.read(storeProvider);
    _hideControls?.cancel();
    if (followed) {
      await tvUnfollowRoom(context, store: store, room: room);
    } else {
      await followRoom(store, room);
    }
    if (mounted && _controls) _touch();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    // Back closes the list or the controls first, then leaves (the room
    // shown is already in `TvRoomArgs.shown` for the page below).
    return PopScope<Object?>(
      canPop: !_panel && !_controls,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hide();
      },
      child: Scaffold(
        backgroundColor: OnVideoColors.ground,
        body: Focus(
          focusNode: _keys,
          autofocus: true,
          onKeyEvent: _onKey,
          child: controller == null
              ? TvBackground(
                  child: TvStatusView(
                    icon: AppIcons.playbackError,
                    title: _problem ?? i18n('get_room_info_failed_retry'),
                    subtitle: i18n('tv_room_switch_hint'),
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    _Picture(key: ObjectKey(controller), controller: controller),
                    ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => StreamBuilder<PlaybackState>(
                        stream: controller.session.states,
                        initialData: controller.session.state,
                        builder: (context, snapshot) =>
                            TvRoomStatus(controller: controller, playback: snapshot.data ?? controller.session.state),
                      ),
                    ),
                    if (_banner && !_controls && !_panel)
                      Positioned(
                        left: 0,
                        top: 0,
                        child: ListenableBuilder(
                          listenable: controller,
                          builder: (context, _) =>
                              TvChannelBanner(room: controller.room, index: _index, count: _playlist.length),
                        ),
                      ),
                    if (_controls)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ListenableBuilder(
                          listenable: controller,
                          builder: (context, _) => StreamBuilder<bool>(
                            stream: ref.read(storeProvider).follows.watchContains(controller.room),
                            builder: (context, followed) => TvRoomControls(
                              controller: controller,
                              followed: followed.data ?? false,
                              danmakuOn: watchSetting(ref, Settings.enableDanmakuDisplay),
                              onQuality: () => unawaited(_pickQuality()),
                              onLine: () => unawaited(_pickLine()),
                              onDanmaku: () {
                                _touch();
                                final settings = ref.read(storeProvider).settings;
                                unawaited(
                                  settings.set(
                                    Settings.enableDanmakuDisplay,
                                    !settings.get(Settings.enableDanmakuDisplay),
                                  ),
                                );
                              },
                              onFollow: () => unawaited(_toggleFollow(followed: followed.data ?? false)),
                              onRefresh: () {
                                _touch();
                                unawaited(controller.load());
                              },
                              onList: _openPanel,
                              firstButton: _firstControl,
                            ),
                          ),
                        ),
                      ),
                    if (_panel)
                      Positioned(
                        top: 0,
                        right: 0,
                        bottom: 0,
                        child: TvRoomList(rooms: _playlist, current: _index, onPick: switchTo),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The picture and the flying danmaku.
class _Picture extends ConsumerWidget {
  const new({required this.controller, super.key});

  final LiveRoomController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fit = videoFits[watchSetting(ref, Settings.videoFitIndex).clamp(0, videoFits.length - 1)];
    final showDanmaku = watchSetting(ref, Settings.enableDanmakuDisplay) && !watchSetting(ref, Settings.hideDanmaku);
    return Stack(
      fit: StackFit.expand,
      children: [
        LiveVideoView(session: controller.session, fit: fit),
        DanmakuOverlay(
          messages: controller.flying,
          retractions: controller.retractions,
          look: danmakuLookOf(ref),
          visible: showDanmaku,
        ),
      ],
    );
  }
}
