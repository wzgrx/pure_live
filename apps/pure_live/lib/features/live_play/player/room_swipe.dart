import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/logic/room_layout.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// The portrait fullscreen's swipe between rooms (docs/A-界面设计/A07-直播间界面/A07.2-竖屏流和竖屏全屏
/// c14, U.2b2): the picture's gesture layer feeds the drag in the middle
/// third ([start], [update], [end]); the [RoomSwipeStage] moves the picture
/// with it and brings the next (or previous) room's cover and name along.
///
/// The picture follows the finger 1:1; towards a side without a room it
/// resists more and more (the rubber band, at most a third of the screen).
/// Let go past a third of the screen (or after a fling) [onSwitch] gets the
/// step at once and the picture moves out at the finger's speed while the
/// room switched to connects; otherwise it springs back (A03.3, research
/// 2026-10-02 S2, S6). Only the picture and a cover move while dragging.
class RoomSwipeController extends ChangeNotifier {
  /// Creates the controller; [onSwitch] gets 1 (the next room) or -1 (the
  /// previous). [vsync] runs the motion after a release: the page's, since
  /// the room switched to builds its stage afresh while the motion goes on.
  new({required this.onSwitch, required TickerProvider vsync}) : _settle = AnimationController.unbounded(vsync: vsync) {
    _settle.addListener(_onTick);
  }

  /// Switches the room by a step.
  final void Function(int step) onSwitch;

  final AnimationController _settle;
  LiveRoom? _previous;
  LiveRoom? _next;
  double _offset = 0;

  /// How far the finger has moved the picture, before the rubber band.
  double _drag = 0;
  double _extent = 0;
  bool _dragging = false;
  bool _disposed = false;

  /// The room switched to while the picture still moves out: it fills the
  /// space the picture leaves until it lands (the page has already moved
  /// its list on).
  LiveRoom? _arriving;

  /// Counts the motions started, so a caught one does not land.
  int _runs = 0;

  // From the stage, as it builds.
  bool _still = false;
  double _refreshRate = 60;
  double _pixelRatio = 1;

  /// How far the picture has moved (upwards negative).
  double get offset => _offset;

  /// The room above (a downward swipe brings it), or null.
  LiveRoom? get previous => _previous;

  /// The room below (an upward swipe brings it), or null.
  LiveRoom? get next => _next;

  /// A finger moves the picture.
  bool get dragging => _dragging;

  /// The room the picture brings in: the one switched to while it lands,
  /// else the neighbour on the side it moved towards.
  LiveRoom? get incoming =>
      _arriving ??
      (_offset < 0
          ? _next
          : _offset > 0
          ? _previous
          : null);

  /// Where letting go now would go by the distance alone (the preview's
  /// "松手换到这个直播间"); the switch made while the picture lands.
  int get pendingStep {
    if (_arriving != null) return _offset < 0 ? 1 : -1;
    return _allowed(swipeSwitchStep(offset: _offset, extent: _extent, velocity: 0));
  }

  /// Sets the rooms around the one shown (the page, as it builds).
  void neighbours({required LiveRoom? previous, required LiveRoom? next}) {
    _previous = previous;
    _next = next;
  }

  /// A drag began in the middle of the picture; it catches a picture still
  /// moving (a switch in flight lands at once and the finger drags the room
  /// switched to).
  void start() {
    if (_settle.isAnimating) {
      _runs++;
      _settle.stop();
      if (_arriving != null) _rest();
    }
    _dragging = true;
    _drag = _past(_offset) ? rubberBandDrag(_offset, _extent) : _offset;
  }

  /// The finger moved by [dy] (downwards positive); the picture follows,
  /// with a rubber band towards a side without a room.
  void update(double dy) {
    if (!_dragging) return;
    var drag = _drag + dy;
    if (_extent > 0) drag = drag.clamp(-_extent, _extent);
    _drag = drag;
    final value = _past(drag) ? AppMotion.rubberBand(drag, _extent) : drag;
    if (value == _offset) return;
    _offset = value;
    notifyListeners();
  }

  /// The finger left at [velocity] (downwards positive): the room switches
  /// at once and the picture moves out, or it springs back.
  void end(double velocity) {
    if (!_dragging) return;
    _dragging = false;
    final step = _allowed(swipeSwitchStep(offset: _offset, extent: _extent, velocity: velocity));
    if (step == 0) {
      _back(velocity);
      return;
    }
    _arriving = step > 0 ? _next : _previous;
    _settleTo(
      -step * _extent,
      spring: AppMotion.roomSwipeSpring,
      velocity: velocity,
      // Out of sight is the end: no slow tail at the edge.
      beyond: _extent * 0.01,
    );
    onSwitch(step);
  }

  /// The drag was taken away: back to the room.
  void cancel() {
    if (!_dragging) return;
    _dragging = false;
    _back(0);
  }

  @override
  void dispose() {
    _disposed = true;
    _settle.dispose();
    super.dispose();
  }

  /// Whether [offset] moves the picture towards a side without a room.
  bool _past(double offset) => (offset < 0 && _next == null) || (offset > 0 && _previous == null);

  /// [step] when there is a room that way, else 0.
  int _allowed(int step) => switch (step) {
    1 when _next != null => 1,
    -1 when _previous != null => -1,
    _ => 0,
  };

  void _back(double velocity) {
    if (!_past(_offset)) {
      _settleTo(0, spring: AppMotion.roomSwipeSpring, velocity: velocity);
      return;
    }
    // Past the end the band slowed the movement; it slows the speed alike.
    final x = _extent > 0 ? math.min(_drag.abs() / _extent, 1) : 1;
    _settleTo(0, spring: AppMotion.overscrollSpring, velocity: velocity * (1 - x) * (1 - x));
  }

  /// A spring from where the picture is to [target], leaving at the
  /// finger's [velocity] and never past it; then the picture rests.
  void _settleTo(double target, {required SpringDescription spring, required double velocity, double beyond = 0}) {
    if (_still || _extent <= 0 || _offset == target) {
      _rest();
      return;
    }
    final run = ++_runs;
    _settle.value = _offset;
    _settle
        .animateRelease(
          ReleaseSpringSimulation(
            spring: spring,
            start: _offset,
            end: target,
            velocity: velocity,
            beyond: beyond,
            tolerance: AppMotion.tolerance(_pixelRatio),
          ),
          refreshRate: _refreshRate,
        )
        .whenCompleteOrCancel(() {
          if (!_disposed && run == _runs && !_dragging) _rest();
        });
  }

  void _onTick() {
    if (_offset == _settle.value) return;
    _offset = _settle.value;
    notifyListeners();
  }

  /// The picture back in its place: the room shown (a switched one by now).
  void _rest() {
    _arriving = null;
    _offset = 0;
    _drag = 0;
    notifyListeners();
  }
}

/// Moves [child] (the player) with a [RoomSwipeController]'s drag and shows
/// the room it brings in the space it leaves ([RoomSwipePreview]).
class RoomSwipeStage extends StatelessWidget {
  /// Creates the stage.
  const new({required this.controller, required this.child, super.key});

  /// The swipe.
  final RoomSwipeController controller;

  /// The player.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    controller
      .._still = MediaQuery.disableAnimationsOf(context)
      .._pixelRatio = MediaQuery.devicePixelRatioOf(context)
      .._refreshRate = View.of(context).display.refreshRate;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        controller._extent = height.isFinite ? height : 0;
        return ClipRect(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, player) {
              final offset = controller.offset;
              final room = offset == 0 ? null : controller.incoming;
              return Stack(
                fit: StackFit.expand,
                children: [
                  Transform.translate(offset: Offset(0, offset), child: player),
                  if (room != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: offset < 0 ? height + offset : offset - height,
                      height: height,
                      child: RoomSwipePreview(room: room, releases: controller.pendingStep != 0),
                    ),
                ],
              );
            },
            child: child,
          ),
        );
      },
    );
  }
}

/// The room a swipe brings in (docs/A-界面设计/A07-直播间界面/A07.2-竖屏流和竖屏全屏 v4-swipe.jpg): its cover
/// over the ambient background, and a card with the streamer's avatar and
/// name, the platform and area, and "松手换到这个直播间" once letting go
/// switches.
class RoomSwipePreview extends StatelessWidget {
  /// Creates the preview of [room].
  const new({required this.room, this.releases = false, super.key});

  /// The room.
  final LiveRoom room;

  /// Letting go now switches to it.
  final bool releases;

  @override
  Widget build(BuildContext context) {
    final cover = room.cover.trim().isNotEmpty ? room.cover.trim() : room.avatar.trim();
    final text = Theme.of(context).textTheme;
    final line = [
      platformName(room.platform),
      room.area?.trim() ?? '',
      if (releases) i18n('portrait_swipe_release_hint'),
    ].where((part) => part.isNotEmpty).join(' · ');
    return IgnorePointer(
      child: ColoredBox(
        key: ValueKey('live-play-swipe-preview-${room.identityKey}'),
        color: OnVideoColors.ground,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AmbientBackdrop(cover: cover),
            if (cover.isNotEmpty)
              LiveNetworkImage(
                url: cover,
                memCacheWidth: (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context))
                    .round()
                    .clamp(240, 1080),
                placeholder: (_) => const SizedBox.shrink(),
                error: (_) => const SizedBox.shrink(),
              ),
            const ColoredBox(color: OnVideoColors.ambientVeil),
            Positioned(
              left: 16,
              right: 16,
              top: MediaQuery.paddingOf(context).top + 120,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(color: OnVideoColors.hint, borderRadius: BorderRadius.circular(28)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CommonAvatar(avatarUrl: room.avatar, radius: 18, fallbackName: room.nick),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                room.nick.trim().isNotEmpty ? room.nick.trim() : room.title.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleSmall?.emphasis.copyWith(
                                  fontSize: 15,
                                  color: OnVideoColors.foreground,
                                ),
                              ),
                              if (line.isNotEmpty)
                                Text(
                                  line,
                                  key: const ValueKey('live-play-swipe-line'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodySmall?.copyWith(fontSize: 12, color: OnVideoColors.secondary),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
