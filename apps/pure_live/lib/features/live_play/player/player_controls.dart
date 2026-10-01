import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/buttons/follow_button.dart';
import 'package:pure_live/features/live_play/danmaku/chat_panel.dart';
import 'package:pure_live/features/live_play/dialogs/iptv_guide.dart';
import 'package:pure_live/features/live_play/dialogs/player_dialogs.dart';
import 'package:pure_live/features/live_play/dialogs/room_switcher.dart';
import 'package:pure_live/features/live_play/dialogs/stream_dialogs.dart';
import 'package:pure_live/features/live_play/layout/room_info_bar.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/player/recording_badge.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// How far the shade under a control bar reaches past the bar into the
/// picture (U.2a change 3).
const double controlShadeReach = 28;

/// The height of a control bar.
const double controlBarHeight = 52;

/// The meta key that remembers the hint about hiding danmaku was shown (E4).
const String danmakuOffHintKey = 'live_play.danmakuOffHinted';

/// The trailing buttons of the top bar (3.x `resolveTopActionTrailingSlots`
/// without the fullscreen clock and battery of U.2c): audio only always,
/// cast and picture-in-picture on Android.
enum TopBarSlot {
  /// Audio only.
  audioOnly,

  /// Cast.
  cast,

  /// Picture-in-picture.
  pip,
}

/// The top bar's trailing buttons in 3.x's order.
List<TopBarSlot> topBarSlots({required bool android}) => [
  TopBarSlot.audioOnly,
  if (android) TopBarSlot.cast,
  if (android) TopBarSlot.pip,
];

/// A button on the picture: white with a soft shadow (the bar's icon theme),
/// 48 × 48.
class VideoIconButton extends StatelessWidget {
  /// Creates the button.
  const new({required this.tooltip, required this.onPressed, required this.icon, this.color, this.iconSize, super.key});

  /// What it does.
  final String tooltip;

  /// The action; null greys it out.
  final VoidCallback? onPressed;

  /// The icon.
  final Widget icon;

  /// The icon's colour ([OnVideoColors.foreground] by default).
  final Color? color;

  /// The icon's size.
  final double? iconSize;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    iconSize: iconSize,
    color: color ?? OnVideoColors.foreground,
    disabledColor: OnVideoColors.disabled,
    constraints: const BoxConstraints(minWidth: kMinInteractiveDimension, minHeight: kMinInteractiveDimension),
    icon: icon,
  );
}

/// The bar along the top of the picture (3.x `TopActionBar`), shown in the
/// portrait room too (U.2a change 2): back in fullscreen, the recording mark,
/// the room's title (and the IPTV programme), the guide, the room switcher
/// in fullscreen, then audio only, cast and picture-in-picture.
class PlayerTopBar extends StatelessWidget {
  /// Creates the bar.
  const new({
    required this.controller,
    required this.fullscreen,
    required this.android,
    required this.pipSupported,
    required this.onBack,
    required this.onPip,
    required this.onInteract,
    super.key,
  });

  /// The room.
  final LiveRoomController controller;

  /// The player fills the screen.
  final bool fullscreen;

  /// Android: cast and picture-in-picture.
  final bool android;

  /// Whether picture-in-picture is offered.
  final Future<bool> pipSupported;

  /// Leaves fullscreen.
  final VoidCallback onBack;

  /// Enters picture-in-picture.
  final VoidCallback onPip;

  /// Keeps the controls up a while longer.
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _ShadedBar(
      key: const ValueKey('live-play-top-bar'),
      shadeKey: const ValueKey('live-play-top-shade'),
      edge: VerticalDirection.up,
      child: Padding(
        padding: const EdgeInsets.only(bottom: controlShadeReach),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: controlBarHeight,
            child: Row(
              children: [
                if (fullscreen)
                  VideoIconButton(
                    key: const ValueKey('live-play-back'),
                    tooltip: i18n('exit_fullscreen'),
                    onPressed: onBack,
                    icon: const Icon(AppIcons.back),
                  )
                else
                  const SizedBox(width: 12),
                RoomRecordingBadge(room: controller.room, gap: 8),
                Expanded(
                  child: ListenableSelector<(String, String)>(
                    listenable: controller,
                    selector: () {
                      final room = controller.room;
                      return (roomLabel(room), controller.catchup?.title ?? room.currentProgramme?.trim() ?? '');
                    },
                    builder: (context, value, _) {
                      final (title, programme) = value;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            key: const ValueKey('live-play-video-title'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.emphasis.copyWith(
                              color: OnVideoColors.foreground,
                              shadows: OnVideoColors.shadows,
                            ),
                          ),
                          if (programme.isNotEmpty)
                            Text(
                              '${i18n(controller.catchup == null ? 'now_playing' : 'playing_catchup')}: $programme',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: OnVideoColors.secondary,
                                shadows: OnVideoColors.shadows,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                if (controller.site.id == SiteIds.iptv)
                  VideoIconButton(
                    key: const ValueKey('live-play-guide'),
                    tooltip: i18n('view_schedule'),
                    onPressed: () => unawaited(showIptvGuide(context, controller)),
                    icon: const Icon(AppIcons.iptvGuide),
                  ),
                if (fullscreen)
                  VideoIconButton(
                    key: const ValueKey('live-play-switch-room'),
                    tooltip: i18n('switch_live_room'),
                    onPressed: () => unawaited(showRoomSwitcher(context, controller.room)),
                    icon: const Icon(AppIcons.switchRoom),
                  ),
                for (final slot in topBarSlots(android: android))
                  switch (slot) {
                    TopBarSlot.audioOnly => _AudioOnlyButton(controller: controller, onInteract: onInteract),
                    TopBarSlot.cast => ListenableSelector<bool>(
                      listenable: controller,
                      selector: () => controller.stage == RoomStage.playing,
                      builder: (context, playing, _) => VideoIconButton(
                        key: const ValueKey('live-play-cast'),
                        tooltip: i18n('cast_screen'),
                        iconSize: 22,
                        onPressed: playing
                            ? () => unawaited(showStreamPicker(context, controller, StreamUse.cast))
                            : null,
                        icon: const Icon(AppIcons.cast),
                      ),
                    ),
                    TopBarSlot.pip => FutureBuilder<bool>(
                      future: pipSupported,
                      builder: (context, snapshot) => snapshot.data ?? false
                          ? VideoIconButton(
                              key: const ValueKey('live-play-pip'),
                              tooltip: i18n('float_window_play'),
                              iconSize: 22,
                              onPressed: onPip,
                              icon: const Icon(AppIcons.floatWindow),
                            )
                          : const SizedBox.shrink(),
                    ),
                  },
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AudioOnlyButton extends StatelessWidget {
  const new({required this.controller, required this.onInteract});

  final LiveRoomController controller;
  final VoidCallback onInteract;

  @override
  Widget build(BuildContext context) => ListenableSelector<(bool, bool)>(
    listenable: controller,
    selector: () => (controller.audioOnly, controller.stage == RoomStage.playing),
    builder: (context, value, _) {
      final (audioOnly, playing) = value;
      return VideoIconButton(
        key: const ValueKey('live-play-audio-only'),
        tooltip: i18n(audioOnly ? 'restore_video_mode' : 'switch_audio_only_mode'),
        iconSize: 22,
        color: audioOnly ? OnVideoColors.active : null,
        onPressed: playing
            ? () {
                onInteract();
                unawaited(controller.setAudioOnly(enabled: !audioOnly));
              }
            : null,
        icon: Icon(audioOnly ? AppIcons.audioOnlyActive : AppIcons.audioOnly),
      );
    },
  );
}

/// The bar along the bottom of the picture (3.x `BottomActionBar`, U.2a
/// change 4): play or pause, refresh, the danmaku switch and settings (3.x's
/// pictures) on the left; the orientation and fullscreen on the right.
/// Fullscreen adds "已关注" after refresh, and the quality, line and fit
/// before the orientation (changes 4 and 5, choice C).
class PlayerBottomBar extends ConsumerWidget {
  /// Creates the bar.
  const new({
    required this.controller,
    required this.fullscreen,
    required this.mobile,
    required this.showDanmaku,
    required this.orientation,
    required this.onToggleFullscreen,
    required this.onInteract,
    this.onReopen,
    this.onLock,
    super.key,
  });

  /// The room.
  final LiveRoomController controller;

  /// The player fills the screen.
  final bool fullscreen;

  /// A phone: the orientation button.
  final bool mobile;

  /// Danmaku fly over the picture now.
  final bool showDanmaku;

  /// The room's orientation choice.
  final RoomOrientationChoice orientation;

  /// Enters or leaves fullscreen.
  final VoidCallback onToggleFullscreen;

  /// Keeps the controls up a while longer.
  final VoidCallback onInteract;

  /// Called before the user asks for another quality or line.
  final VoidCallback? onReopen;

  /// Locks the controls (phones in fullscreen).
  final VoidCallback? onLock;

  Future<void> _toggleDanmaku(LiveStore store) async {
    final hide = showDanmaku;
    await store.settings.set(Settings.hideDanmaku, hide);
    if (!hide) return;
    // E4: the first time, say the chat list keeps showing them.
    if (await store.meta.get(danmakuOffHintKey) == '1') return;
    await store.meta.set(danmakuOffHintKey, '1');
    AppNavigator.toast(i18n('live_play_danmaku_off_hint'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.read(storeProvider);
    final display = watchSetting(ref, Settings.enableDanmakuDisplay);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final left = <Widget>[
      StreamBuilder<PlaybackState>(
        stream: controller.session.states,
        initialData: controller.session.state,
        builder: (context, snapshot) {
          final paused = snapshot.data?.status == PlaybackStatus.paused;
          return VideoIconButton(
            key: const ValueKey('live-play-pause'),
            tooltip: i18n(paused ? 'live_play_play' : 'live_play_pause'),
            iconSize: 28,
            onPressed: () {
              onInteract();
              unawaited(controller.session.togglePlayPause());
            },
            icon: Icon(paused ? AppIcons.play : AppIcons.pause),
          );
        },
      ),
      VideoIconButton(
        key: const ValueKey('live-play-refresh'),
        tooltip: i18n('live_play_refresh_room'),
        onPressed: () {
          onInteract();
          unawaited(controller.load());
        },
        icon: const Icon(AppIcons.refresh),
      ),
      // 3.x left it out of a narrow fullscreen bar (`compact`).
      if (fullscreen && !narrow)
        ListenableSelector<String>(
          listenable: controller,
          selector: () => controller.room.identityKey,
          builder: (context, _, _) =>
              FollowButton(room: controller.room, latest: () => controller.room, place: FollowButtonPlace.video),
        ),
      if (display) ...[
        VideoIconButton(
          key: const ValueKey('live-play-danmaku-toggle'),
          tooltip: i18n(showDanmaku ? 'live_play_hide_danmaku' : 'show_danmaku'),
          onPressed: () {
            onInteract();
            unawaited(_toggleDanmaku(store));
          },
          icon: DanmakuIcon(showDanmaku ? DanmakuIconKind.on : DanmakuIconKind.off),
        ),
        VideoIconButton(
          key: const ValueKey('live-play-danmaku-settings'),
          tooltip: i18n('danmaku_settings'),
          onPressed: () => unawaited(showRoomDanmakuSettings(context, controller)),
          icon: const DanmakuIcon(DanmakuIconKind.settings),
        ),
      ],
      if (onLock case final lock?)
        VideoIconButton(
          key: const ValueKey('live-play-lock'),
          tooltip: i18n('live_play_lock'),
          onPressed: lock,
          icon: const Icon(AppIcons.unlocked),
        ),
    ];
    final right = <Widget>[
      if (mobile) _OrientationButton(choice: orientation),
      VideoIconButton(
        key: const ValueKey('live-play-fullscreen'),
        tooltip: i18n(fullscreen ? 'exit_fullscreen' : 'live_play_fullscreen'),
        iconSize: 26,
        onPressed: onToggleFullscreen,
        icon: Icon(fullscreen ? AppIcons.exitFullscreen : AppIcons.fullscreen),
      ),
    ];
    return _ShadedBar(
      shadeKey: const ValueKey('live-play-bottom-shade'),
      edge: VerticalDirection.down,
      child: Padding(
        padding: const EdgeInsets.only(top: controlShadeReach),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: controlBarHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                key: const ValueKey('live-play-bottom-bar'),
                children: [
                  ...left,
                  if (fullscreen)
                    // The fullscreen extras give way on a narrow screen.
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StreamPickers(controller: controller, onVideo: true, onReopen: onReopen),
                              const _VideoFitButton(),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  ...right,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The fullscreen bar's fit button (3.x `VideoFitSetting`): the fit's name;
/// a tap moves to the next one.
class _VideoFitButton extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = watchSetting(ref, Settings.videoFitIndex).clamp(0, videoFits.length - 1);
    final style = Theme.of(context).textTheme.bodyLarge?.regular
        .copyWith(color: OnVideoColors.foreground, shadows: OnVideoColors.shadows);
    return Tooltip(
      message: i18n('settings_video_fit'),
      child: InkWell(
        key: const ValueKey('live-play-video-fit'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => unawaited(advanceVideoFit(ref.read(storeProvider).settings)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: kMinInteractiveDimension, minHeight: kMinInteractiveDimension),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(child: Text(videoFitName(index), style: style)),
          ),
        ),
      ),
    );
  }
}

/// The room's orientation (3.x `PortraitOrientationButton`): yellow when it
/// is not "自动识别"; a long press shows the current choice (E6).
class _OrientationButton extends StatelessWidget {
  const new({required this.choice});

  final RoomOrientationChoice choice;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: choice,
    builder: (context, _) {
      final value = choice.value;
      return VideoIconButton(
        key: const ValueKey('live-play-orientation'),
        tooltip: i18n('live_play_orientation_now', args: {'value': roomOrientationName(value)}),
        iconSize: 22,
        color: value == RoomOrientation.automatic ? null : OnVideoColors.active,
        onPressed: () => unawaited(showRoomOrientationPicker(context, choice)),
        icon: Icon(switch (value) {
          RoomOrientation.automatic => AppIcons.orientationAuto,
          RoomOrientation.portrait => AppIcons.orientationPortrait,
          RoomOrientation.landscape => AppIcons.orientationLandscape,
        }),
      );
    },
  );
}

/// A bar over the shade along one [edge] of the picture: the shade (60 %
/// black fading into the picture, U.2a change 3) lets taps through to the
/// picture; only the bar's buttons take them.
class _ShadedBar extends StatelessWidget {
  const new({required this.shadeKey, required this.edge, required this.child, super.key});

  final Key shadeKey;
  final VerticalDirection edge;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: IgnorePointer(
          child: DecoratedBox(
            key: shadeKey,
            decoration: BoxDecoration(gradient: OnVideoColors.shade(edge: edge)),
          ),
        ),
      ),
      child,
    ],
  );
}
