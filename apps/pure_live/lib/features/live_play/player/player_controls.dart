import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/buttons/follow_button.dart';
import 'package:pure_live/features/live_play/buttons/record_button.dart';
import 'package:pure_live/features/live_play/buttons/room_menu_button.dart';
import 'package:pure_live/features/live_play/buttons/stream_menu.dart';
import 'package:pure_live/features/live_play/danmaku/danmaku_settings_panel.dart';
import 'package:pure_live/features/live_play/dialogs/iptv_guide.dart';
import 'package:pure_live/features/live_play/dialogs/player_dialogs.dart';
import 'package:pure_live/features/live_play/dialogs/room_switcher.dart';
import 'package:pure_live/features/live_play/dialogs/stream_dialogs.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/local_composer.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/logic/room_layout.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/mini/room_mini_window.dart';
import 'package:pure_live/features/live_play/player/bar_parts.dart';
import 'package:pure_live/features/live_play/player/recording_badge.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// How far the shade under a control bar reaches past the bar into the
/// picture (U.2a change 3).
const double controlShadeReach = 28;

/// The height of a control bar.
const double controlBarHeight = 52;

/// The height of a row of the portrait fullscreen's bars (U.2b).
const double portraitRowHeight = 48;

/// Below this width even the folded landscape bar scrolls sideways.
const double composerFoldMinWidth = 640;

/// The meta key that remembers the hint about hiding danmaku was shown (E4).
const String danmakuOffHintKey = 'live_play.danmakuOffHinted';

/// The platform facts the room's bars follow.
final class RoomPlatform {
  /// Facts of [platform].
  const new(this.platform);

  /// This device's platform.
  new current() : platform = defaultTargetPlatform;

  /// The platform.
  final TargetPlatform platform;

  /// Android: cast, the orientation and the system picture-in-picture.
  bool get android => platform == TargetPlatform.android;

  /// Phones and tablets: the orientation, gestures and the portrait
  /// fullscreen.
  bool get mobile => android || platform == TargetPlatform.iOS;

  /// Windows: the room menu's new window.
  bool get windows => platform == TargetPlatform.windows;

  /// Windows, Linux and macOS: the volume slider and the in-window
  /// fullscreen.
  bool get desktop => !mobile;
}

/// The trailing buttons of the top bar (3.x `resolveTopActionTrailingSlots`):
/// audio only always, cast on Android, the mini window everywhere (U.2j
/// change 5: Linux, macOS and iOS too; it shows where the room's
/// `RoomMiniScope` says the platform has one, U.17a).
enum TopBarSlot {
  /// Audio only.
  audioOnly,

  /// Cast.
  cast,

  /// Picture-in-picture.
  pip,
}

/// The top bar's trailing buttons in 3.x's order on [platform].
List<TopBarSlot> topBarSlots({required TargetPlatform platform}) => [
  TopBarSlot.audioOnly,
  if (castSupported(platform)) TopBarSlot.cast,
  if (platform != TargetPlatform.fuchsia) TopBarSlot.pip,
];

/// Extras of the wide room's bottom bar (docs/ui/compare/U.2d change 6).
final class WideBarActions {
  /// Creates the extras.
  const new({required this.chatCollapsed, required this.onToggleChat});

  /// Whether the chat column is folded away.
  final bool chatCollapsed;

  /// Folds the chat column away or brings it back.
  final VoidCallback onToggleChat;
}

/// What the bars over the picture need from the room's player: one set for
/// every arrangement, so the same buttons do the same things wherever they
/// sit.
final class PlayerBarActions {
  /// Creates the set.
  const new({
    required this.controller,
    required this.arrangement,
    required this.display,
    required this.platform,
    required this.orientation,
    required this.showDanmaku,
    required this.portraitStream,
    required this.pipSupported,
    required this.onBack,
    required this.onToggleFullscreen,
    required this.onPip,
    required this.onInteract,
    required this.onMenu,
    this.onReopen,
    this.onWindowFullscreen,
    this.wide,
    this.reduced = false,
  });

  /// The room.
  final LiveRoomController controller;

  /// Which arrangement draws the bars.
  final ControlsArrangement arrangement;

  /// How the room is shown.
  final RoomDisplay display;

  /// The platform.
  final RoomPlatform platform;

  /// The room's orientation choice.
  final RoomOrientationChoice orientation;

  /// Danmaku fly over the picture now.
  final bool showDanmaku;

  /// The stream is laid out as portrait.
  final bool portraitStream;

  /// Whether picture-in-picture can start now.
  final Future<bool> pipSupported;

  /// The landscape and portrait fullscreen's back: leaves the fullscreen
  /// (the room, on a short window's page).
  final VoidCallback onBack;

  /// The fullscreen button and double tap.
  final VoidCallback onToggleFullscreen;

  /// Picture-in-picture.
  final VoidCallback onPip;

  /// Keeps the controls up a while longer.
  final VoidCallback onInteract;

  /// Told when a menu opens (true) and closes, or the composer takes the
  /// focus and lets it go: the controls stay up meanwhile.
  final ValueChanged<bool> onMenu;

  /// Called before the user asks for another quality or line.
  final VoidCallback? onReopen;

  /// Desktops: enters or leaves the in-window fullscreen.
  final VoidCallback? onWindowFullscreen;

  /// The wide room's extras.
  final WideBarActions? wide;

  /// Nothing plays (loading, offline, failed, restricted): the top bar keeps
  /// the way out and the room's buttons, without audio only, cast and the
  /// mini window that need a picture (docs/ui/compare/U.2g c6).
  final bool reduced;

  /// These actions for the [reduced] top bar.
  PlayerBarActions reducedCopy() => PlayerBarActions(
    controller: controller,
    arrangement: arrangement,
    display: display,
    platform: platform,
    orientation: orientation,
    showDanmaku: showDanmaku,
    portraitStream: portraitStream,
    pipSupported: pipSupported,
    onBack: onBack,
    onToggleFullscreen: onToggleFullscreen,
    onPip: onPip,
    onInteract: onInteract,
    onMenu: onMenu,
    onReopen: onReopen,
    onWindowFullscreen: onWindowFullscreen,
    wide: wide,
    reduced: true,
  );
}

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

/// The bars along the top of the picture (3.x `TopActionBar`):
///
/// - inline (U.2a change 2): the recording mark, the room's title (and the
///   IPTV programme), the guide, then audio only, cast and
///   picture-in-picture;
/// - landscape (U.2c): back, the clock and battery (every platform, change
///   4), the title, the guide, switch room (no dark disc, change 5), audio,
///   cast, picture-in-picture, then record and the menu (change 2);
/// - portrait fullscreen (U.2b change 6): back, the title, follow, record and
///   the menu; under them the clock and battery, switch room, audio, cast and
///   picture-in-picture.
class PlayerTopBar extends StatelessWidget {
  /// Creates the bar.
  const new({required this.actions, super.key});

  /// The player's actions.
  final PlayerBarActions actions;

  @override
  Widget build(BuildContext context) {
    final arrangement = actions.arrangement;
    final portrait = arrangement == ControlsArrangement.portraitFullscreen;
    final Widget content = switch (arrangement) {
      ControlsArrangement.inline => SizedBox(
        height: controlBarHeight,
        child: Row(
          children: [
            const SizedBox(width: 12),
            _RecordingMark(controller: actions.controller),
            Expanded(child: _VideoTitle(controller: actions.controller)),
            ..._trailing(context, switchRoom: false),
            const SizedBox(width: 4),
          ],
        ),
      ),
      ControlsArrangement.landscape => SizedBox(
        height: controlBarHeight,
        child: Row(
          children: [
            _back(context),
            const PlayerClock(),
            const PlayerBattery(),
            const SizedBox(width: 4),
            Expanded(child: _VideoTitle(controller: actions.controller)),
            ..._trailing(context, switchRoom: true),
            ..._roomActions(),
            const SizedBox(width: 4),
          ],
        ),
      ),
      ControlsArrangement.portraitFullscreen => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 4),
          SizedBox(
            height: portraitRowHeight,
            child: Row(
              children: [
                _back(context),
                Expanded(child: _VideoTitle(controller: actions.controller, programme: false)),
                _follow(),
                ..._roomActions(),
                const SizedBox(width: 4),
              ],
            ),
          ),
          SizedBox(
            height: portraitRowHeight,
            child: Row(
              key: const ValueKey('live-play-top-second-row'),
              children: [
                const SizedBox(width: 14),
                const PlayerClock(),
                const PlayerBattery(),
                const Spacer(),
                ..._trailing(context, switchRoom: true),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ],
      ),
    };
    return _ShadedBar(
      key: const ValueKey('live-play-top-bar'),
      shadeKey: const ValueKey('live-play-top-shade'),
      edge: VerticalDirection.up,
      child: Padding(
        padding: EdgeInsets.only(bottom: portrait ? 8 : controlShadeReach),
        child: SafeArea(bottom: false, child: content),
      ),
    );
  }

  Widget _back(BuildContext context) => VideoIconButton(
    key: const ValueKey('live-play-back'),
    tooltip: actions.display == RoomDisplay.inline
        ? MaterialLocalizations.of(context).backButtonTooltip
        : i18n('exit_fullscreen'),
    onPressed: actions.onBack,
    icon: const Icon(AppIcons.back),
  );

  Widget _follow() => ListenableSelector<String>(
    listenable: actions.controller,
    selector: () => actions.controller.room.identityKey,
    builder: (context, _, _) => FollowButton(
      room: actions.controller.room,
      latest: () => actions.controller.room,
      place: FollowButtonPlace.video,
    ),
  );

  /// Record and the room menu, as in the room's app bar (U.2c change 2).
  List<Widget> _roomActions() {
    final controller = actions.controller;
    final iptv = controller.site.id == SiteIds.iptv;
    return [
      if (!iptv)
        ListenableSelector<String>(
          listenable: controller,
          selector: () => controller.room.identityKey,
          builder: (context, _, _) => RecordButton(room: controller.room, latest: () => controller.room, onVideo: true),
        ),
      RoomMenuButton(controller: controller, windows: actions.platform.windows, onVideo: true, onMenu: actions.onMenu),
    ];
  }

  List<Widget> _trailing(BuildContext context, {required bool switchRoom}) {
    final controller = actions.controller;
    return [
      if (controller.site.id == SiteIds.iptv)
        VideoIconButton(
          key: const ValueKey('live-play-guide'),
          tooltip: i18n('view_schedule'),
          onPressed: () => unawaited(showIptvGuide(context, controller)),
          icon: const Icon(AppIcons.iptvGuide),
        ),
      if (switchRoom)
        VideoIconButton(
          key: const ValueKey('live-play-switch-room'),
          tooltip: i18n('switch_live_room'),
          onPressed: () => unawaited(showRoomSwitcher(context, controller.room)),
          icon: const Icon(AppIcons.switchRoom),
        ),
      for (final slot in actions.reduced ? const <TopBarSlot>[] : topBarSlots(platform: actions.platform.platform))
        switch (slot) {
          TopBarSlot.audioOnly => _AudioOnlyButton(controller: controller, onInteract: actions.onInteract),
          TopBarSlot.cast => ListenableSelector<bool>(
            listenable: controller,
            selector: () => controller.stage == RoomStage.playing,
            builder: (context, playing, _) => VideoIconButton(
              key: const ValueKey('live-play-cast'),
              tooltip: i18n('cast_screen'),
              iconSize: 22,
              onPressed: playing ? () => unawaited(showStreamPicker(context, controller, StreamUse.cast)) : null,
              icon: const Icon(AppIcons.cast),
            ),
          ),
          TopBarSlot.pip => FutureBuilder<bool>(
            future: actions.pipSupported,
            builder: (context, snapshot) {
              // Only where the platform has a mini window (U.2j); a spinner
              // while it opens or closes.
              if (!(snapshot.data ?? false)) return const SizedBox.shrink();
              final preparing = RoomMiniScope.maybeOf(context)?.preparing ?? ValueNotifier(false);
              return ValueListenableBuilder<bool>(
                valueListenable: preparing,
                builder: (context, busy, _) => VideoIconButton(
                  key: const ValueKey('live-play-pip'),
                  tooltip: i18n('float_window_play'),
                  iconSize: 22,
                  onPressed: busy ? null : actions.onPip,
                  icon: busy
                      ? const SizedBox.square(
                          key: ValueKey('live-play-pip-busy'),
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: OnVideoColors.foreground),
                        )
                      : const Icon(AppIcons.floatWindow),
                ),
              );
            },
          ),
        },
    ];
  }
}

/// The "● 录制中" mark before the inline title; it opens the record panel
/// (U.2f).
class _RecordingMark extends StatelessWidget {
  const new({required this.controller});

  final LiveRoomController controller;

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const ValueKey('live-play-recording-mark'),
    behavior: HitTestBehavior.opaque,
    onTap: () => RoomPanelScope.maybeOf(context)?.open(RoomPanelKind.record),
    child: RoomRecordingBadge(room: controller.room, gap: 8),
  );
}

/// The room's title on the picture (16, semi-bold, white) and, unless
/// [programme] is false, the IPTV programme under it.
class _VideoTitle extends StatelessWidget {
  const new({required this.controller, this.programme = true});

  final LiveRoomController controller;
  final bool programme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableSelector<(String, String)>(
      listenable: controller,
      selector: () {
        final room = controller.room;
        return (roomLabel(room), controller.catchup?.title ?? room.currentProgramme?.trim() ?? '');
      },
      builder: (context, value, _) {
        final (title, now) = value;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
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
              if (programme && now.isNotEmpty)
                Text(
                  // U.2g c18: "正在回看: 节目名" while a programme is replayed.
                  '${i18n(controller.catchup == null ? 'now_playing' : 'live_play_guide_replaying_now')}: $now',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: OnVideoColors.secondary,
                    shadows: OnVideoColors.shadows,
                  ),
                ),
            ],
          ),
        );
      },
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

/// The bars along the bottom of the picture (3.x `BottomActionBar`):
///
/// - inline (U.2a change 4, U.2d change 6): play or pause, refresh, the
///   danmaku switch and settings on the left; the orientation (phones), the
///   volume (desktops), fold the chat (wide), the in-window fullscreen
///   (desktops) and the fullscreen on the right;
/// - landscape (U.2c): play, refresh, follow, the danmaku switch and
///   settings; the local danmaku composer (U.2k's `LocalDanmakuComposer`) in
///   the middle, a star where the middle is narrow (change 3); quality, line (U.2f), the orientation, the fit (change
///   6), the volume (desktops) and leaving the fullscreen;
/// - portrait fullscreen (U.2b change 7): the composer, quality and line;
///   under them play, refresh, the danmaku switch and settings, then the
///   picture mode, the orientation and leaving the fullscreen.
class PlayerBottomBar extends ConsumerWidget {
  /// Creates the bar.
  const new({required this.actions, super.key});

  /// The player's actions.
  final PlayerBarActions actions;

  Future<void> _toggleDanmaku(LiveStore store) async {
    final hide = actions.showDanmaku;
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
    final controller = actions.controller;
    final arrangement = actions.arrangement;
    final playPause = StreamBuilder<PlaybackState>(
      stream: controller.session.states,
      initialData: controller.session.state,
      builder: (context, snapshot) {
        final paused = snapshot.data?.status == PlaybackStatus.paused;
        return VideoIconButton(
          key: const ValueKey('live-play-pause'),
          tooltip: i18n(paused ? 'live_play_play' : 'live_play_pause'),
          iconSize: 28,
          onPressed: () {
            actions.onInteract();
            unawaited(controller.session.togglePlayPause());
          },
          icon: Icon(paused ? AppIcons.play : AppIcons.pause),
        );
      },
    );
    final refresh = VideoIconButton(
      key: const ValueKey('live-play-refresh'),
      tooltip: i18n('live_play_refresh_room'),
      onPressed: () {
        actions.onInteract();
        unawaited(controller.load());
      },
      icon: const Icon(AppIcons.refresh),
    );
    final danmaku = [
      if (display) ...[
        VideoIconButton(
          key: const ValueKey('live-play-danmaku-toggle'),
          tooltip: i18n(actions.showDanmaku ? 'live_play_hide_danmaku' : 'show_danmaku'),
          onPressed: () {
            actions.onInteract();
            unawaited(_toggleDanmaku(store));
          },
          icon: DanmakuIcon(actions.showDanmaku ? DanmakuIconKind.on : DanmakuIconKind.off),
        ),
        VideoIconButton(
          key: const ValueKey('live-play-danmaku-settings'),
          tooltip: i18n('danmaku_settings'),
          onPressed: () => showRoomDanmakuSettings(context, controller),
          icon: const DanmakuIcon(DanmakuIconKind.settings),
        ),
      ],
    ];
    final follow = ListenableSelector<String>(
      listenable: controller,
      selector: () => controller.room.identityKey,
      builder: (context, _, _) =>
          FollowButton(room: controller.room, latest: () => controller.room, place: FollowButtonPlace.video),
    );
    final streams = StreamPickers(
      controller: controller,
      onVideo: true,
      preferAbove: true,
      onReopen: actions.onReopen,
      onMenu: actions.onMenu,
    );
    final orientation = actions.platform.mobile ? _OrientationButton(choice: actions.orientation) : null;
    final volume = actions.platform.desktop
        ? VolumeSlider(controller: controller, onInteract: actions.onInteract)
        : null;
    final fullscreen = _fullscreenButton();
    return switch (arrangement) {
      ControlsArrangement.inline => _bar(
        _InlineRow(
          left: [playPause, refresh, ...danmaku],
          right: [
            ?orientation,
            ?volume,
            if (actions.wide case final wide?)
              VideoIconButton(
                key: const ValueKey('live-play-chat-column'),
                tooltip: i18n(wide.chatCollapsed ? 'live_play_show_chat' : 'live_play_hide_chat'),
                onPressed: wide.onToggleChat,
                icon: const Icon(AppIcons.chatColumn),
              ),
            if (actions.onWindowFullscreen case final onWindow?) _WindowFullscreenButton(onPressed: onWindow),
          ],
          pinned: fullscreen,
        ),
      ),
      ControlsArrangement.landscape => _bar(
        LayoutBuilder(
          builder: (context, constraints) {
            final left = [playPause, refresh, follow, ...danmaku];
            final right = [
              streams,
              ?orientation,
              VideoFitButton(onMenu: actions.onMenu),
              ?volume,
              if (actions.display == RoomDisplay.windowFullscreen && actions.onWindowFullscreen != null)
                _WindowFullscreenButton(onPressed: actions.onWindowFullscreen!, active: true)
              else
                fullscreen,
            ];
            final composer = LocalDanmakuComposer.onVideo(onHold: actions.onMenu);
            if (constraints.maxWidth < composerFoldMinWidth) {
              // Too narrow even for the field: the row scrolls, nothing
              // drops; the composer is its star.
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ...left,
                    SizedBox(width: 48, child: composer),
                    ...right,
                  ],
                ),
              );
            }
            return Row(
              children: [
                ...left,
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(
                      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: composer),
                    ),
                  ),
                ),
                ...right,
              ],
            );
          },
        ),
      ),
      ControlsArrangement.portraitFullscreen => _ShadedBar(
        key: const ValueKey('live-play-bottom-shade-box'),
        shadeKey: const ValueKey('live-play-bottom-shade'),
        edge: VerticalDirection.down,
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                key: const ValueKey('live-play-bottom-bar'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: portraitRowHeight,
                    child: Row(
                      key: const ValueKey('live-play-bottom-first-row'),
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: LocalDanmakuComposer.onVideo(onHold: actions.onMenu),
                            ),
                          ),
                        ),
                        streams,
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: portraitRowHeight,
                    child: Row(
                      children: [
                        playPause,
                        refresh,
                        ...danmaku,
                        const Spacer(),
                        if (actions.portraitStream) PortraitModeButton(onMenu: actions.onMenu),
                        ?orientation,
                        fullscreen,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    };
  }

  /// The fullscreen button: enters (inline, a short window's page) or leaves
  /// (fullscreen) it.
  Widget _fullscreenButton() {
    final inside = actions.display != RoomDisplay.inline;
    return VideoIconButton(
      key: const ValueKey('live-play-fullscreen'),
      tooltip: i18n(inside ? 'exit_fullscreen' : 'live_play_fullscreen'),
      iconSize: 26,
      onPressed: actions.onToggleFullscreen,
      icon: Icon(inside ? AppIcons.exitFullscreen : AppIcons.fullscreen),
    );
  }

  Widget _bar(Widget row) => _ShadedBar(
    shadeKey: const ValueKey('live-play-bottom-shade'),
    edge: VerticalDirection.down,
    child: Padding(
      padding: const EdgeInsets.only(top: controlShadeReach),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: controlBarHeight,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: actions.arrangement == ControlsArrangement.landscape ? 8 : 4),
            child: KeyedSubtree(key: const ValueKey('live-play-bottom-bar'), child: row),
          ),
        ),
      ),
    ),
  );
}

/// The inline bottom row: [left] and [right] apart, scrolling sideways when
/// a narrow window cannot hold them, with [pinned] (the fullscreen) always
/// at the end (3.x: the last button used to scroll out of sight).
class _InlineRow extends StatelessWidget {
  const new({required this.left, required this.right, required this.pinned});

  final List<Widget> left;
  final List<Widget> right;
  final Widget pinned;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: left),
                  Row(mainAxisSize: MainAxisSize.min, children: right),
                ],
              ),
            ),
          ),
        ),
      ),
      pinned,
    ],
  );
}

/// The in-window fullscreen (3.x `ExpandWindowButton`, U.2d 15): the picture
/// fills the window, the app bar and the chat hide; Esc leaves it.
class _WindowFullscreenButton extends StatelessWidget {
  const new({required this.onPressed, this.active = false});

  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) => VideoIconButton(
    key: const ValueKey('live-play-window-fullscreen'),
    tooltip: i18n(active ? 'live_play_window_fullscreen_exit' : 'live_play_window_fullscreen'),
    iconSize: 26,
    onPressed: onPressed,
    icon: RotatedBox(quarterTurns: 1, child: Icon(active ? AppIcons.windowFullscreenExit : AppIcons.windowFullscreen)),
  );
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
