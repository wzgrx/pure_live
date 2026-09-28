import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_store/live_store.dart' show VideoFit;
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/app_prefs.dart';
import 'package:pure_live_app/core/audience.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/danmaku/danmaku_preferences.dart';
import 'package:pure_live_app/features/room/player_view.dart';
import 'package:pure_live_app/features/room/room_menus.dart';
import 'package:pure_live_app/features/room/room_switch.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// The side panel open over the picture on TV (principles §6.3).
enum TvPanel {
  /// Nothing.
  none,

  /// Left: the rooms of the list, to jump to one.
  rooms,

  /// Right: playback settings (弹幕, 画质, 线路, 比例).
  settings,
}

/// The room page on a remote (spec/modules/live-room.md §3.5, principles
/// §6.3). The picture is always fullscreen. With nothing shown, up and down
/// switch to the previous and next live room of the list the room came
/// from, left opens the room list, right the playback settings, OK shows
/// the info bar and control row, a long OK or the menu key opens the
/// settings. Back closes a panel or the control row first, then leaves.
class TvRoomLayer extends ConsumerStatefulWidget {
  const new({
    required this.detail,
    required this.session,
    required this.player,
    required this.entries,
    required this.onStep,
    required this.onPick,
    required this.child,
    this.listLabel,
    this.followed = false,
    this.onFollow,
    super.key,
  });

  /// The room shown.
  final RoomDetail detail;

  /// The page's playback session.
  final PlaybackSession session;

  /// The picture, for its commands (play, refresh, danmaku, fit, sleep timer).
  final GlobalKey<PlayerViewState> player;

  /// The list to switch in, read when needed.
  final List<RoomEntry> Function() entries;

  /// Name of the list.
  final String? listLabel;

  /// Up (-1) and down (+1).
  final ValueChanged<int> onStep;

  /// A room chosen in the list.
  final ValueChanged<RoomRef> onPick;

  /// Whether the room is followed.
  final bool followed;

  /// Follows or unfollows.
  final VoidCallback? onFollow;

  /// The picture and its layout.
  final Widget child;

  @override
  ConsumerState<TvRoomLayer> createState() => TvRoomLayerState();
}

/// State of a [TvRoomLayer]; public for tests.
class TvRoomLayerState extends ConsumerState<TvRoomLayer> {
  final FocusNode _root = FocusNode(debugLabel: 'tv-room');
  final FocusNode _firstControl = FocusNode(debugLabel: 'tv-room-play');
  late final OkPressTracker _ok = OkPressTracker(
    onPress: showControls,
    onLongPress: () =>
        () => openPanel(TvPanel.settings),
  );
  StreamSubscription<PlaybackState>? _states;
  late PlaybackState _state = widget.session.state;
  Timer? _hide;
  bool _controls = false;
  TvPanel _panel = TvPanel.none;

  /// Whether the info bar and control row show.
  bool get controlsVisible => _controls;

  /// The open side panel.
  TvPanel get panel => _panel;

  @override
  void initState() {
    super.initState();
    _states = widget.session.states.listen((state) {
      if (mounted) setState(() => _state = state);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // The page's own focus may hold the route's focus from the loading
      // state; the remote keys start here.
      _root.requestFocus();
      // Once per installation (principles §6.5).
      if (ref.read(appPrefsProvider.notifier).takeTip(Tip.tvRoom)) {
        widget.player.currentState?.showHint(
          Icons.settings_remote_outlined,
          t.room.tv.hint,
          duration: const Duration(seconds: 4),
        );
      }
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _ok.dispose();
    unawaited(_states?.cancel());
    _root.dispose();
    _firstControl.dispose();
    super.dispose();
  }

  /// Shows the info bar and control row with focus on its first button.
  void showControls() {
    setState(() => _controls = true);
    _armHide();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controls) _firstControl.requestFocus();
    });
  }

  /// Hides them; the remote keys return to switching rooms.
  void hideControls() {
    _hide?.cancel();
    setState(() => _controls = false);
    _root.requestFocus();
  }

  void _armHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 5), () {
      if (mounted && _controls && _panel == TvPanel.none) hideControls();
    });
  }

  /// Opens a side panel; its current item takes focus.
  void openPanel(TvPanel panel) {
    _hide?.cancel();
    setState(() {
      _panel = panel;
      _controls = false;
    });
  }

  /// Closes the side panel.
  void closePanel() {
    setState(() => _panel = TvPanel.none);
    _root.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (_panel != TvPanel.none) {
      // The direction that opened a panel's opposite closes it.
      final closing =
          (_panel == TvPanel.rooms && key == LogicalKeyboardKey.arrowRight) ||
          (_panel == TvPanel.settings && key == LogicalKeyboardKey.arrowLeft);
      if (closing && event is KeyDownEvent) {
        closePanel();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_controls) {
      _armHide();
      final moves = TvKeys.directions.containsKey(key) || TvKeys.ok.contains(key);
      if (_root.hasPrimaryFocus && event is KeyDownEvent && moves) {
        _firstControl.requestFocus();
        return KeyEventResult.handled;
      }
      // A button has focus: the framework moves between buttons and presses them.
      return KeyEventResult.ignored;
    }
    if (!_root.hasPrimaryFocus) return KeyEventResult.ignored;
    if (_ok.handle(event)) return KeyEventResult.handled;
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final direction = TvKeys.directions[key];
    // A held arrow does not flip through rooms: every switch opens streams.
    if (event is KeyRepeatEvent) return direction == null ? KeyEventResult.ignored : KeyEventResult.handled;
    switch (direction) {
      case TraversalDirection.up:
        widget.onStep(-1);
      case TraversalDirection.down:
        widget.onStep(1);
      case TraversalDirection.left:
        openPanel(TvPanel.rooms);
      case TraversalDirection.right:
        openPanel(TvPanel.settings);
      case null:
        if (key != LogicalKeyboardKey.contextMenu) return KeyEventResult.ignored;
        openPanel(TvPanel.settings);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // TV-06: back closes a panel or the control row before leaving.
    canPop: _panel == TvPanel.none && !_controls,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      if (_panel != TvPanel.none) {
        closePanel();
      } else if (_controls) {
        hideControls();
      }
    },
    child: Focus(
      focusNode: _root,
      onKeyEvent: _onKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_controls)
            _ControlBar(
              detail: widget.detail,
              state: _state,
              entries: widget.entries(),
              firstFocus: _firstControl,
              followed: widget.followed,
              onFollow: widget.onFollow,
              player: widget.player,
              onPanel: openPanel,
            ),
          if (_panel == TvPanel.rooms)
            Align(
              alignment: Alignment.centerLeft,
              child: _SidePanel(
                left: true,
                title: widget.listLabel ?? t.room.tv.roomList,
                child: _RoomList(
                  entries: widget.entries(),
                  current: widget.detail.ref,
                  onPick: (room) {
                    closePanel();
                    widget.onPick(room);
                  },
                ),
              ),
            ),
          if (_panel == TvPanel.settings)
            Align(
              alignment: Alignment.centerRight,
              child: _SidePanel(
                left: false,
                title: t.room.tv.playbackSettings,
                child: _PlaybackSettings(
                  session: widget.session,
                  state: _state,
                  player: widget.player,
                  live: widget.detail.state == LiveState.live,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// The info bar and control row (TV-04): who, what, where in the list, and
/// the buttons, reachable with the D-pad.
class _ControlBar extends ConsumerWidget {
  const new({
    required this.detail,
    required this.state,
    required this.entries,
    required this.firstFocus,
    required this.followed,
    required this.player,
    required this.onPanel,
    this.onFollow,
  });

  final RoomDetail detail;
  final PlaybackState state;
  final List<RoomEntry> entries;
  final FocusNode firstFocus;
  final bool followed;
  final VoidCallback? onFollow;
  final GlobalKey<PlayerViewState> player;
  final ValueChanged<TvPanel> onPanel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    const ink = Colors.white;
    final card = detail.card;
    final prefs = ref.watch(danmakuPrefsProvider);
    final audience = shownAudience(card.audience, preferOnline: ref.watch(preferRealOnlineSetting));
    final position = entries.indexWhere((entry) => entry.ref == card.ref);
    final paused = state.phase == PlaybackPhase.paused;
    Widget button(IconData icon, String label, VoidCallback onPressed, {FocusNode? focusNode}) => Padding(
      padding: const EdgeInsets.only(right: Space.s3),
      child: FilledButton.tonalIcon(focusNode: focusNode, onPressed: onPressed, icon: Icon(icon), label: Text(label)),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0x00000000), Color(0xB3000000)],
                stops: [0, 0.45, 1],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    PlatformLogo(platformId: card.ref.platform, size: Sizes.logoLarge),
                    const SizedBox(width: Space.s2),
                    Flexible(
                      child: Text(
                        card.anchorName,
                        style: theme.textTheme.titleLarge!.copyWith(color: ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: Space.s3),
                    if (card.state == LiveState.live) const LiveBadge(),
                    if (audience != null) ...[
                      const SizedBox(width: Space.s3),
                      Text(
                        formatCount(audience),
                        style: LiveTheme.numeric(Theme.of(context).textTheme.labelMedium!).copyWith(color: ink),
                      ),
                    ],
                    const Spacer(),
                    if (position >= 0)
                      Text(
                        '${position + 1} / ${entries.length}',
                        style: LiveTheme.numeric(Theme.of(context).textTheme.labelMedium!)
                            .copyWith(color: Colors.white70),
                      ),
                  ],
                ),
                const SizedBox(height: Space.s1),
                Text(
                  [card.title, platformNames[card.ref.platform] ?? card.ref.platform, ?card.area].join(' · '),
                  style: theme.textTheme.bodyMedium!.copyWith(color: Colors.white70),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Space.s3),
                FocusTraversalGroup(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: Row(
                      children: [
                        button(
                          paused ? Icons.play_arrow : Icons.pause,
                          paused ? t.common.play : t.common.pause,
                          () => player.currentState?.togglePlay(),
                          focusNode: firstFocus,
                        ),
                        button(Icons.refresh, t.common.refresh, () => player.currentState?.refresh()),
                        if (prefs.enabled && card.state == LiveState.live)
                          button(
                            prefs.hidden ? Icons.subtitles_off_outlined : Icons.subtitles,
                            prefs.hidden ? t.danmaku.turnOn : t.multiview.danmakuOff,
                            () => player.currentState?.toggleDanmaku(),
                          ),
                        button(Icons.tune, t.room.tv.qualityLine, () => onPanel(TvPanel.settings)),
                        button(Icons.format_list_bulleted, t.room.tv.roomList, () => onPanel(TvPanel.rooms)),
                        if (onFollow != null)
                          button(
                            followed ? Icons.favorite : Icons.favorite_border,
                            followed ? t.common.followed : t.common.follow,
                            onFollow!,
                          ),
                        button(
                          Icons.bedtime_outlined,
                          t.room.sleepTimer,
                          () => unawaited(player.currentState?.openSleepTimer()),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A panel over one side of the picture: solid (no blur, principles §7),
/// focus stays inside until it closes.
class _SidePanel extends StatelessWidget {
  const new({required this.left, required this.title, required this.child});

  final bool left;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: TvMetrics.panelWidth + TvMetrics.safeX,
      height: double.infinity,
      child: Material(
        color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.96),
        child: SafeArea(
          left: left,
          right: !left,
          child: FocusScope(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s2),
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomList extends StatelessWidget {
  const new({required this.entries, required this.current, required this.onPick});

  final List<RoomEntry> entries;
  final RoomRef current;
  final ValueChanged<RoomRef> onPick;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return MessageView(title: t.room.tv.noLiveRooms);
    final here = entries.indexWhere((entry) => entry.ref == current);
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final playing = index == here;
        return ListTile(
          autofocus: index == (here < 0 ? 0 : here),
          selected: playing,
          leading: PlatformLogo(platformId: entry.ref.platform, size: Sizes.logoLarge),
          title: Text(entry.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: entry.title.isEmpty ? null : Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: playing ? Text(t.room.tv.watching) : null,
          onTap: () => onPick(entry.ref),
        );
      },
    );
  }
}

/// 弹幕, 画质, 线路, 比例 (principles §6.3, right panel).
class _PlaybackSettings extends ConsumerWidget {
  const new({required this.session, required this.state, required this.player, required this.live});

  final PlaybackSession session;
  final PlaybackState state;
  final GlobalKey<PlayerViewState> player;
  final bool live;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final prefs = ref.watch(danmakuPrefsProvider);
    final fit = ref.watch(videoFitSetting);
    final switching = const {PlaybackPhase.resolving, PlaybackPhase.connecting}.contains(state.phase);
    final danmaku = prefs.enabled && live;
    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s4, Space.s1),
      child: Text(text, style: theme.textTheme.labelLarge!.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
    Widget choice(String label, {required bool selected, required VoidCallback onTap, bool autofocus = false}) =>
        ListTile(
          autofocus: autofocus,
          selected: selected,
          title: Text(label),
          trailing: selected ? const Icon(Icons.check) : null,
          onTap: onTap,
        );
    return ListView(
      children: [
        if (switching) const LinearProgressIndicator(),
        if (danmaku)
          SwitchListTile(
            autofocus: true,
            title: Text(t.danmaku.show),
            value: !prefs.hidden,
            onChanged: (_) => player.currentState?.toggleDanmaku(),
          ),
        if (state.qualities.isNotEmpty) ...[
          header(t.multiview.quality),
          for (final (index, quality) in state.qualities.indexed)
            choice(
              quality.label,
              selected: quality == state.quality,
              autofocus: !danmaku && index == 0,
              // Q-8: the last choice wins; the panel stays to show the switch.
              onTap: () => unawaited(session.selectQuality(quality)),
            ),
        ],
        if (state.lines.length > 1) ...[
          header(t.multiview.line),
          for (final (index, line) in state.lines.indexed)
            choice(
              t.multiview.lineN(n: index + 1),
              selected: line.lineId == state.line?.lineId,
              onTap: () => unawaited(session.selectLine(line.lineId)),
            ),
        ],
        header(t.room.aspect),
        for (final (value, label) in [
          (VideoFit.contain, t.room.fit.contain),
          (VideoFit.cover, t.room.fit.cover),
          (VideoFit.fill, t.room.fit.fill),
        ])
          choice(
            label,
            selected: fit == value,
            autofocus: !danmaku && state.qualities.isEmpty && value == VideoFit.contain,
            onTap: () => player.currentState?.setFit(value),
          ),
        if (state.qualities.isNotEmpty) ...[
          const SizedBox(height: Space.s2),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s4),
            child: Text(qualityLineLabel(state), style: theme.textTheme.bodySmall),
          ),
        ],
      ],
    );
  }
}
