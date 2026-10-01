import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/features/live_play/logic/mini_window.dart';
import 'package:pure_live/features/live_play/logic/reconnect_watch.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/mini/compact_danmaku.dart';
import 'package:pure_live/features/live_play/player/recording_badge.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// How long the buttons stay after a tap (3.x: 3 s).
const Duration miniButtonsTimeout = Duration(seconds: 3);

/// Two clicks closer than this are a double click (back to the room).
const Duration miniDoubleClick = Duration(milliseconds: 300);

/// The diameter of a mini window's corner buttons (U.2j: 48, a 45 % black
/// disc).
const double miniButtonSize = 48;

/// The diameter of the centre button (3.x: a 42 icon with 8 around it).
const double miniCentreSize = 58;

/// The picture of a room in a mini window with its buttons (U.2j, 3.x
/// `showAppFloating`, `buildPiPOverlay`): the same in the in-app floating
/// window, Android's picture-in-picture and the desktop mini window.
///
/// - Top left: back to the room (new); top right: close (always stops, c2);
///   the centre: play or pause, refresh when playback failed; the desktop
///   adds the pin at the bottom right and the volume (wheel, bar at the
///   bottom).
/// - A touch shows the buttons for 3 s, a touch while they show goes back
///   to the room; a mouse shows them while it hovers and a double click goes
///   back (3.x). Paused, the play button stays.
/// - Bottom left: the recording mark; over the picture the "小窗弹幕".
/// - Android's picture-in-picture has none of the buttons (the system draws
///   its own).
///
/// The picture, the danmaku and the buttons draw on their own layers; the
/// video is never clipped (UI_PLAN §9.3).
class MiniPlayerSurface extends StatefulWidget {
  /// Creates the surface.
  const new({
    required this.controller,
    required this.reconnect,
    required this.video,
    required this.kind,
    this.onBackToRoom,
    this.onClose,
    this.pinned = false,
    this.canPin = true,
    this.onPin,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    super.key,
  });

  /// The room.
  final LiveRoomController controller;

  /// The stream's drops.
  final ReconnectWatch reconnect;

  /// The picture (the room's one video view).
  final Widget video;

  /// Which mini window.
  final MiniKind kind;

  /// Back to the room (button 1, the second touch, a double click).
  final VoidCallback? onBackToRoom;

  /// Stops and closes (button 2).
  final VoidCallback? onClose;

  /// The desktop mini window stays on top (button 4).
  final bool pinned;

  /// Whether the desktop lets it stay on top.
  final bool canPin;

  /// Turns staying on top on or off.
  final VoidCallback? onPin;

  /// A drag on the picture began (moves the window).
  final GestureDragStartCallback? onDragStart;

  /// The drag moved.
  final GestureDragUpdateCallback? onDragUpdate;

  /// The drag ended.
  final GestureDragEndCallback? onDragEnd;

  @override
  State<MiniPlayerSurface> createState() => _MiniPlayerSurfaceState();
}

class _MiniPlayerSurfaceState extends State<MiniPlayerSurface> {
  bool _hovered = false;
  bool _revealed = false;
  Timer? _hide;
  DateTime? _lastClick;
  bool _volumeShown = false;
  Timer? _volumeHide;
  Timer? _volumeSave;
  double _volume = 1;

  LiveRoomController get _room => widget.controller;

  bool get _buttons => widget.kind != MiniKind.systemPip;

  bool get _desktop => widget.kind == MiniKind.desktop;

  @override
  void initState() {
    super.initState();
    _volume = _room.volume;
    _room.addListener(_onRoom);
    // 3.x showed the buttons for a moment when the floating window appeared.
    if (_buttons) _reveal();
  }

  @override
  void didUpdateWidget(MiniPlayerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onRoom);
      widget.controller.addListener(_onRoom);
      _volume = widget.controller.volume;
    }
  }

  @override
  void dispose() {
    _room.removeListener(_onRoom);
    _hide?.cancel();
    _volumeHide?.cancel();
    if (_volumeSave?.isActive ?? false) {
      _volumeSave!.cancel();
      unawaited(_room.saveVolume());
    }
    super.dispose();
  }

  /// The volume changed (wheel, arrow keys): the desktop shows its bar.
  void _onRoom() {
    final volume = _room.volume;
    if ((volume - _volume).abs() < 0.001) return;
    _volume = volume;
    if (!_desktop || !mounted) return;
    _volumeHide?.cancel();
    setState(() => _volumeShown = true);
    _volumeHide = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _volumeShown = false);
    });
  }

  void _reveal() {
    _hide?.cancel();
    if (!_revealed && mounted) setState(() => _revealed = true);
    _revealed = true;
    _hide = Timer(miniButtonsTimeout, () {
      if (mounted) setState(() => _revealed = false);
    });
  }

  bool get _shown => _hovered || _revealed;

  void _onTapUp(TapUpDetails details) {
    if (!_buttons) return;
    final mouse = details.kind == PointerDeviceKind.mouse || details.kind == PointerDeviceKind.trackpad;
    if (mouse) {
      final now = DateTime.now();
      final last = _lastClick;
      _lastClick = now;
      if (last != null && now.difference(last) <= miniDoubleClick) {
        _lastClick = null;
        widget.onBackToRoom?.call();
      }
      return;
    }
    // Touch: the first tap shows the buttons, a tap while they show goes
    // back to the room (3.x).
    if (_shown) {
      widget.onBackToRoom?.call();
    } else {
      _reveal();
    }
  }

  void _onScroll(PointerSignalEvent event) {
    if (!_desktop || event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    final next = (_room.volume + (event.scrollDelta.dy > 0 ? -0.05 : 0.05)).clamp(0.0, 1.0);
    unawaited(_room.setVolume(next));
    // The room's volume is kept once the wheel rests (as in the room).
    _volumeSave?.cancel();
    _volumeSave = Timer(const Duration(milliseconds: 600), () => unawaited(_room.saveVolume()));
  }

  void _togglePlay() {
    if (!_hovered) _reveal();
    unawaited(_room.session.togglePlayPause());
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final content = Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: widget.video),
        ListenableSelector<bool>(
          listenable: room,
          selector: () => room.audioOnly,
          builder: (context, audioOnly, _) => audioOnly ? _MiniAudioCover(room: room.room) : const SizedBox.shrink(),
        ),
        IgnorePointer(child: CompactDanmakuLayer(controller: room)),
        _MiniStatusLayer(controller: room, reconnect: widget.reconnect),
        Positioned(
          left: 6,
          bottom: 6,
          child: IgnorePointer(child: RoomRecordingBadge(room: room.room, compact: true)),
        ),
        if (_buttons) ...[
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('mini-surface'),
              behavior: HitTestBehavior.opaque,
              onTapUp: _onTapUp,
              onPanStart: widget.onDragStart,
              onPanUpdate: widget.onDragUpdate,
              onPanEnd: widget.onDragEnd,
            ),
          ),
          _buttonsLayer(context),
          if (_desktop) _volumeBar(context),
        ],
      ],
    );
    // Its own Material: the floating window sits above the pages.
    final framed = Material(color: OnVideoColors.ground, child: content);
    if (!_buttons) return framed;
    final hovered = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(onPointerSignal: _onScroll, child: framed),
    );
    // The desktop mini window's edges resize it (3.x).
    return _desktop ? DesktopWindow.resizeArea(hovered) : hovered;
  }

  Widget _buttonsLayer(BuildContext context) => StreamBuilder<PlaybackState>(
    stream: _room.session.states,
    initialData: _room.session.state,
    builder: (context, snapshot) {
      final playback = snapshot.data ?? _room.session.state;
      return ListenableSelector<MiniStatus>(
        listenable: Listenable.merge([_room, widget.reconnect]),
        selector: () =>
            miniStatusOf(stage: _room.stage, playback: playback.status, reconnecting: widget.reconnect.reconnecting),
        builder: (context, status, _) {
          final shown = _shown;
          final failed = status == MiniStatus.failed;
          // Paused, the play button stays (c8); failed, refresh stays.
          final centreShown = shown || status == MiniStatus.paused || failed;
          final centreBusy = status == MiniStatus.loading || status == MiniStatus.reconnecting;
          return Stack(
            fit: StackFit.expand,
            children: [
              _fade(
                shown: shown,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _MiniButton(
                      key: const ValueKey('mini-back'),
                      tooltip: i18n('mini_window_back_to_room'),
                      icon: AppIcons.backToRoom,
                      onPressed: widget.onBackToRoom,
                    ),
                  ),
                ),
              ),
              _fade(
                shown: shown,
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _MiniButton(
                      key: const ValueKey('mini-close'),
                      tooltip: i18n('close'),
                      icon: AppIcons.close,
                      onPressed: widget.onClose,
                    ),
                  ),
                ),
              ),
              if (!centreBusy)
                _fade(
                  shown: centreShown,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: failed ? 16 : 0),
                      child: failed
                          ? _MiniButton(
                              key: const ValueKey('mini-retry'),
                              tooltip: i18n('retry'),
                              icon: AppIcons.refresh,
                              size: miniCentreSize,
                              iconSize: 34,
                              onPressed: _room.retry,
                            )
                          : _MiniButton(
                              key: const ValueKey('mini-play-pause'),
                              tooltip: i18n(status == MiniStatus.paused ? 'multiview_play' : 'multiview_pause'),
                              icon: status == MiniStatus.paused ? AppIcons.miniPlay : AppIcons.miniPause,
                              size: miniCentreSize,
                              iconSize: 42,
                              onPressed: _togglePlay,
                            ),
                    ),
                  ),
                ),
              if (_desktop)
                _fade(
                  shown: shown,
                  child: Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: _PinButton(pinned: widget.pinned, canPin: widget.canPin, onPressed: widget.onPin),
                    ),
                  ),
                ),
            ],
          );
        },
      );
    },
  );

  Widget _volumeBar(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _volumeShown ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: _volumeShown
              ? DecoratedBox(
                  key: const ValueKey('mini-volume'),
                  decoration: BoxDecoration(color: OnVideoColors.scrim, borderRadius: BorderRadius.circular(14)),
                  child: SizedBox(
                    height: 28,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8, right: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _room.volume <= 0 ? AppIcons.volumeMute : AppIcons.volumeUp,
                            size: 18,
                            color: OnVideoColors.foreground,
                            semanticLabel: i18n('multiview_volume'),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 72,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: _room.volume.clamp(0.0, 1.0),
                                minHeight: 4,
                                backgroundColor: OnVideoColors.track,
                                color: OnVideoColors.foreground,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    ),
  );

  /// A button layer fading in and out; hidden ones take no taps and are not
  /// painted.
  Widget _fade({required bool shown, required Widget child}) => IgnorePointer(
    ignoring: !shown,
    child: AnimatedOpacity(opacity: shown ? 1 : 0, duration: const Duration(milliseconds: 200), child: child),
  );
}

/// A round button on the picture: white on a 45 % black disc (U.2j c2).
class _MiniButton extends StatelessWidget {
  const new({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.size = miniButtonSize,
    this.iconSize = 20,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: iconSize,
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: OnVideoColors.button,
        foregroundColor: OnVideoColors.foreground,
        disabledBackgroundColor: OnVideoColors.button,
        disabledForegroundColor: OnVideoColors.disabled,
        fixedSize: Size.square(size),
        minimumSize: Size.square(size),
      ),
      icon: Icon(icon),
    ),
  );
}

/// The desktop mini window's pin (c3): the theme's primary colour while on
/// top; grey where the desktop does not allow it (c5).
class _PinButton extends StatelessWidget {
  const new({required this.pinned, required this.canPin, required this.onPressed});

  final bool pinned;
  final bool canPin;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final on = pinned && canPin;
    final button = SizedBox.square(
      dimension: miniButtonSize,
      child: IconButton(
        key: const ValueKey('mini-pin'),
        tooltip: canPin ? i18n(on ? 'mini_window_unpin' : 'mini_window_pin') : null,
        onPressed: canPin ? onPressed : null,
        iconSize: 20,
        padding: EdgeInsets.zero,
        isSelected: on,
        style: IconButton.styleFrom(
          backgroundColor: on ? colors.primary : OnVideoColors.button,
          foregroundColor: on ? colors.onPrimary : OnVideoColors.foreground,
          disabledBackgroundColor: OnVideoColors.button,
          disabledForegroundColor: OnVideoColors.disabled,
          fixedSize: const Size.square(miniButtonSize),
        ),
        icon: Icon(on ? AppIcons.pinned : AppIcons.unpinned),
      ),
    );
    if (canPin) return button;
    return Tooltip(message: i18n('mini_window_pin_unsupported'), child: button);
  }
}

/// The audio-only room in a mini window (c8, M7): the streamer's picture and
/// "纯音频模式", small enough for a 124 high window.
class _MiniAudioCover extends StatelessWidget {
  const new({required this.room});

  final LiveRoom room;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.labelMedium?.emphasis.copyWith(color: OnVideoColors.foreground);
    return Stack(
      key: const ValueKey('mini-audio-only'),
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: OnVideoColors.ground),
        if (room.cover.trim().isNotEmpty)
          LiveNetworkImage(
            url: room.cover,
            placeholder: (_) => const SizedBox.shrink(),
            error: (_) => const SizedBox.shrink(),
          ),
        const ColoredBox(color: OnVideoColors.coverDim),
        Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CommonAvatar(avatarUrl: room.avatar, radius: 22, fallbackName: room.nick),
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(color: OnVideoColors.chip, borderRadius: BorderRadius.circular(12)),
                  child: SizedBox(
                    height: 24,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(AppIcons.audioOnly, size: 14, color: OnVideoColors.foreground),
                          const SizedBox(width: 4),
                          Text(i18n('audio_only_mode'), style: text),
                        ],
                      ),
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

/// Loading, buffering, reconnecting and failure over a mini window's picture
/// (c8): small, no buttons of their own (the surface's centre button
/// retries).
class _MiniStatusLayer extends StatelessWidget {
  const new({required this.controller, required this.reconnect});

  final LiveRoomController controller;
  final ReconnectWatch reconnect;

  @override
  Widget build(BuildContext context) => StreamBuilder<PlaybackState>(
    stream: controller.session.states,
    initialData: controller.session.state,
    builder: (context, snapshot) => ListenableSelector<(MiniStatus, String)>(
      listenable: Listenable.merge([controller, reconnect]),
      selector: () {
        final status = miniStatusOf(
          stage: controller.stage,
          playback: (snapshot.data ?? controller.session.state).status,
          reconnecting: reconnect.reconnecting,
        );
        final reason = controller.stage == RoomStage.offline
            ? offlineText(controller.room)
            : i18n('multiview_play_failed');
        return (status, reason);
      },
      builder: (context, value, _) {
        final (status, reason) = value;
        final style = Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: OnVideoColors.foreground, shadows: OnVideoColors.shadows);
        const spinner = SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: OnVideoColors.foreground),
        );
        return IgnorePointer(
          child: switch (status) {
            MiniStatus.playing || MiniStatus.paused => const SizedBox.shrink(),
            MiniStatus.loading => const ColoredBox(
              key: ValueKey('mini-loading'),
              color: OnVideoColors.ground,
              child: Center(child: spinner),
            ),
            MiniStatus.buffering => const Center(key: ValueKey('mini-buffering'), child: spinner),
            MiniStatus.reconnecting => ColoredBox(
              key: const ValueKey('mini-reconnecting'),
              color: OnVideoColors.dim,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    spinner,
                    const SizedBox(height: 6),
                    Text(i18n('mini_window_reconnecting'), style: style),
                  ],
                ),
              ),
            ),
            MiniStatus.failed => ColoredBox(
              key: const ValueKey('mini-failed'),
              color: OnVideoColors.dim,
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, left: 8, right: 8),
                  child: Text(reason, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
          },
        );
      },
    ),
  );
}
