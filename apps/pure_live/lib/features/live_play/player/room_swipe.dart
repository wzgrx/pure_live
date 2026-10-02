import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/logic/room_layout.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// The portrait fullscreen's swipe between rooms (docs/T05/T05c/T05c.1
/// c14, U.2b2): the picture's gesture layer feeds the drag in the middle
/// third ([start], [update], [end]); the [RoomSwipeStage] moves the picture
/// with it and brings the next (or previous) room's cover and name along.
/// Let go past a third of the screen (or after a fling) the picture moves
/// out and [onSwitch] gets the step; otherwise it springs back. Only the
/// picture and a cover move while dragging: the player switches once, after
/// the release.
class RoomSwipeController extends ChangeNotifier {
  /// Creates the controller; [onSwitch] gets 1 (the next room) or -1 (the
  /// previous).
  new({required this.onSwitch});

  /// Switches the room by a step.
  final void Function(int step) onSwitch;

  LiveRoom? _previous;
  LiveRoom? _next;
  double _offset = 0;
  double _extent = 0;
  bool _dragging = false;
  AnimationController? _settle;

  /// Where the running settle starts and ends, or null.
  (double, double)? _settling;
  int _step = 0;

  /// How far the picture has moved (upwards negative).
  double get offset => _offset;

  /// The room above (a downward swipe brings it), or null.
  LiveRoom? get previous => _previous;

  /// The room below (an upward swipe brings it), or null.
  LiveRoom? get next => _next;

  /// A finger moves the picture.
  bool get dragging => _dragging;

  /// Where letting go now would go by the distance alone (the preview's
  /// "松手换到这个直播间").
  int get pendingStep => swipeSwitchStep(offset: _offset, extent: _extent, velocity: 0);

  /// Sets the rooms around the one shown (the page, as it builds).
  void neighbours({required LiveRoom? previous, required LiveRoom? next}) {
    _previous = previous;
    _next = next;
  }

  /// A drag began in the middle of the picture.
  void start() {
    _stopSettling();
    _dragging = true;
  }

  /// The finger moved by [dy] (downwards positive); the picture follows,
  /// never towards a side without a room.
  void update(double dy) {
    if (!_dragging) return;
    var value = _offset + dy;
    if (_next == null) value = math.max(value, 0);
    if (_previous == null) value = math.min(value, 0);
    if (_extent > 0) value = value.clamp(-_extent, _extent);
    if (value == _offset) return;
    _offset = value;
    notifyListeners();
  }

  /// The finger left at [velocity] (downwards positive): the picture moves
  /// out and the room switches, or it springs back.
  void end(double velocity) {
    if (!_dragging) return;
    _dragging = false;
    final step = swipeSwitchStep(offset: _offset, extent: _extent, velocity: velocity);
    _settleTo(step);
  }

  /// The drag was taken away: back to the room.
  void cancel() {
    if (!_dragging) return;
    _dragging = false;
    _settleTo(0);
  }

  void _settleTo(int step) {
    _step = step;
    final target = step == 0 ? 0.0 : -step * _extent;
    final animation = _settle;
    if (animation == null || animation.duration == Duration.zero || _offset == target) {
      _finish();
      return;
    }
    _settling = (_offset, target);
    animation.forward(from: 0).whenCompleteOrCancel(() {
      if (animation.status == AnimationStatus.completed) _finish();
    });
  }

  void _onTick() {
    final animation = _settle;
    if (_settling case (final from, final to) when animation != null) {
      _offset = from + (to - from) * Curves.easeOutCubic.transform(animation.value);
      notifyListeners();
    }
  }

  void _stopSettling() {
    if (_settle?.isAnimating ?? false) _settle!.stop();
    _settling = null;
  }

  void _finish() {
    final step = _step;
    _step = 0;
    _settling = null;
    _offset = 0;
    notifyListeners();
    if (step != 0) onSwitch(step);
  }

  void _attach(AnimationController animation) {
    _settle = animation..addListener(_onTick);
  }

  void _detach(AnimationController animation) {
    animation.removeListener(_onTick);
    if (identical(_settle, animation)) _settle = null;
  }
}

/// Moves [child] (the player) with a [RoomSwipeController]'s drag and shows
/// the room it brings in the space it leaves ([RoomSwipePreview]).
class RoomSwipeStage extends StatefulWidget {
  /// Creates the stage.
  const new({required this.controller, required this.child, super.key});

  /// The swipe.
  final RoomSwipeController controller;

  /// The player.
  final Widget child;

  @override
  State<RoomSwipeStage> createState() => _RoomSwipeStageState();
}

class _RoomSwipeStageState extends State<RoomSwipeStage> with SingleTickerProviderStateMixin {
  late final AnimationController _settle = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    widget.controller._attach(_settle);
  }

  @override
  void didUpdateWidget(RoomSwipeStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    oldWidget.controller._detach(_settle);
    widget.controller._attach(_settle);
  }

  @override
  void dispose() {
    widget.controller._detach(_settle);
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _settle.duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220);
    final controller = widget.controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        controller._extent = height.isFinite ? height : 0;
        return ClipRect(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, player) {
              final offset = controller.offset;
              final room = offset < 0
                  ? controller.next
                  : offset > 0
                  ? controller.previous
                  : null;
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
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// The room a swipe brings in (docs/T05/T05c/T05c.1 v4-swipe.jpg): its cover
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
