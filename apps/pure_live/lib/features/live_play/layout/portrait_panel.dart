import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/logic/room_layout.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The name a screen reader gives the panel's stop [index] (0 the lowest):
/// "最低", "中间", "最高" (B09 c5, audit B-17).
String portraitPanelStopName(int index) => i18n(switch (index) {
  0 => 'portrait_panel_stop_low',
  1 => 'portrait_panel_stop_middle',
  _ => 'portrait_panel_stop_high',
});

/// The portrait room (3.x `PortraitLiveRoomLayout`, docs/A-界面设计/A07-直播间界面/A07.2-竖屏流和竖屏全屏):
/// the picture fills the area and a panel with the room strip and the chat
/// covers its lower part at one of three heights ([portraitPanelStops]).
///
/// - A drag on the handle row resizes the panel and settles on the nearest
///   stop; past the lowest stop (30 % of the panel, or a fling) or a tap on
///   the handle enters the portrait fullscreen ([onPortraitFullscreen],
///   phones and tablets; desktops only show a drag bar).
/// - "横屏全屏" sits at the right of the handle row (change 3; "全屏" on
///   desktops, which do not turn).
/// - The picture's danmaku, status and controls only take the part above the
///   panel ([player] gets the covered height); they move once the panel has
///   settled, not while it is dragged (change 2).
class PortraitPanelLayout extends StatefulWidget {
  /// Creates the layout.
  const new({
    required this.player,
    required this.content,
    required this.panels,
    required this.mode,
    required this.onFullscreen,
    required this.mobile,
    this.onPortraitFullscreen,
    this.least = portraitPanelLeast,
    this.stop,
    this.onStop,
    this.keyboard = 0,
    super.key,
  });

  /// The stop to start at (0 the lowest, 1 the middle, 2 the highest): the
  /// one the panel was left at before the fullscreen (B09 c4); null for the
  /// [mode]'s first.
  final int? stop;

  /// Told the stop the panel settles at.
  final ValueChanged<int>? onStop;

  /// The lowest stop ([portraitPanelStops]).
  final double least;

  /// The picture, told how much of it the panel covers.
  final Widget Function(double covered) player;

  /// The panel's content under the handle row (the strip and the chat).
  final Widget content;

  /// The record and danmaku settings panels: over this panel when open.
  final Widget panels;

  /// The keyboard's height (A07.18): an open [panels] grows up by as much
  /// (at most to the top of the area), so a filter's results stay above
  /// it; the chat panel under it stays where it is.
  final double keyboard;

  /// The room layout setting (`portraitLayoutMode`): "immersive" starts at
  /// the lowest stop.
  final String mode;

  /// The handle row's right button: a one-off landscape fullscreen on
  /// phones, the fullscreen on desktops.
  final VoidCallback onFullscreen;

  /// Phones and tablets (the button turns the screen).
  final bool mobile;

  /// Enters the portrait fullscreen; null where there is none (desktops).
  final VoidCallback? onPortraitFullscreen;

  @override
  State<PortraitPanelLayout> createState() => _PortraitPanelLayoutState();
}

/// The three stops of [portraitPanelStops], lowest first.
typedef _Stops = ({double minimum, double middle, double maximum, double initial});

class _PortraitPanelLayoutState extends State<PortraitPanelLayout> with SingleTickerProviderStateMixin {
  /// The stop to start at ([PortraitPanelLayout.stop]) until the mode
  /// changes.
  late int? _first = widget.stop;

  /// Where the panel's top is, above the area's bottom (A03.3): between the
  /// stops its height; under the lowest it is pulled towards the portrait
  /// fullscreen (it slides down at [_floor]'s height); over the highest the
  /// rubber band. It moves the panel without building the layout or the
  /// picture (research 2026-10-02 S4).
  late final AnimationController _top = AnimationController.unbounded(vsync: this);

  /// [_top] holds the place; until then the panel is at [_rest].
  bool _moved = false;

  /// Where the finger has taken the top, before the rubber band.
  double _drag = 0;
  bool _dragging = false;

  /// The height the panel keeps while it slides down out of the way (the
  /// one it had when the fullscreen was asked for); null: the lowest stop.
  double? _floor;

  /// The stop the picture's overlay leaves room for: changed when a drag
  /// ends, not while it moves.
  double? _settled;

  bool _entering = false;

  /// Counts the springs started, so a caught one does not finish.
  int _runs = 0;

  /// The area's height, as last laid out.
  double _area = 0;

  /// The picture as last built and the covered height it was built for:
  /// built again only when that changes or the page rebuilds this layout.
  Widget? _picture;
  double? _pictureCovered;

  @override
  void didUpdateWidget(PortraitPanelLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    _picture = null;
    if (oldWidget.mode != widget.mode) {
      _runs++;
      _top.stop();
      _first = null;
      _moved = false;
      _dragging = false;
      _floor = null;
      _settled = null;
      _entering = false;
    }
  }

  @override
  void dispose() {
    _top.dispose();
    super.dispose();
  }

  static List<double> _list(_Stops stops) => [stops.minimum, stops.middle, stops.maximum];

  /// The height before the panel was moved: the stop it was left at, else
  /// the mode's first.
  double _start(_Stops stops) => switch (_first) {
    0 => stops.minimum,
    1 => stops.middle,
    2 => stops.maximum,
    _ => stops.initial,
  };

  /// The stop the panel rests at.
  double _rest(_Stops stops) => (_settled ?? _start(stops)).clamp(stops.minimum, stops.maximum);

  /// Where the top is now.
  double _position(_Stops stops) => _moved ? _top.value : _rest(stops);

  /// The panel's height and how far it is below the bottom.
  ({double height, double bottom}) _place(_Stops stops) {
    var top = _position(stops);
    // At rest it keeps to the stops (the area may have changed).
    if (!_dragging && !_entering && !_top.isAnimating) top = top.clamp(stops.minimum, stops.maximum);
    final floor = _floor ?? stops.minimum;
    return (height: math.max(top, floor), bottom: math.min(0, top - floor));
  }

  /// The room over the highest stop, the rubber band's length there.
  double _over(_Stops stops) => math.max(0, _area - stops.maximum);

  /// Where a drag at [drag] shows the top: 1:1 between the stops and down
  /// towards the fullscreen; with growing resistance over the highest stop,
  /// and under the lowest where there is no fullscreen (research S6).
  double _banded(double drag, _Stops stops) {
    if (drag > stops.maximum) return stops.maximum + AppMotion.rubberBand(drag - stops.maximum, _over(stops));
    if (drag < stops.minimum && widget.onPortraitFullscreen == null) {
      return stops.minimum + AppMotion.rubberBand(drag - stops.minimum, stops.minimum);
    }
    return drag;
  }

  /// The drag that shows the top at [top] ([_banded] the other way).
  double _unbanded(double top, _Stops stops) {
    if (top > stops.maximum) return stops.maximum + rubberBandDrag(top - stops.maximum, _over(stops));
    if (top < stops.minimum && widget.onPortraitFullscreen == null) {
      return stops.minimum + rubberBandDrag(top - stops.minimum, stops.minimum);
    }
    return top;
  }

  /// How much the rubber band slows the finger where it is now (its
  /// slope), 1 between the stops.
  double _slope(_Stops stops) {
    final (past, extent) = _drag > stops.maximum
        ? (_drag - stops.maximum, _over(stops))
        : _drag < stops.minimum && widget.onPortraitFullscreen == null
        ? (stops.minimum - _drag, stops.minimum)
        : (0.0, 0.0);
    if (extent <= 0) return past > 0 ? 0 : 1;
    final rest = 1 - math.min<double>(1, past / extent);
    return rest * rest;
  }

  /// Takes the top from where it is, catching a spring.
  void _hold(_Stops stops) {
    _runs++;
    final top = _position(stops);
    _top.stop();
    _moved = true;
    _top.value = top;
  }

  void _started(DragStartDetails details, _Stops stops) {
    if (_entering) return;
    _hold(stops);
    _dragging = true;
    _drag = _unbanded(_top.value, stops);
  }

  void _dragged(DragUpdateDetails details, _Stops stops) {
    if (_entering || !_dragging) return;
    // Down towards the fullscreen at most until out of sight (3.x).
    _drag = (_drag - details.delta.dy).clamp(0, stops.maximum + _over(stops));
    _top.value = _banded(_drag, stops);
  }

  void _released(DragEndDetails details, _Stops stops) {
    if (_entering || !_dragging) return;
    _dragging = false;
    final velocity = details.primaryVelocity ?? 0;
    final top = _top.value;
    final height = top.clamp(stops.minimum, stops.maximum);
    if (widget.onPortraitFullscreen != null &&
        panelDragEntersFullscreen(
          dismissed: math.max(0, stops.minimum - top),
          panelHeight: height,
          velocity: velocity,
        )) {
      _enter(stops, velocity: velocity);
      return;
    }
    // The spring leaves at the finger's speed, as slowed by the band.
    _settle(releaseStop(height, velocity, _list(stops)), stops, velocity: -velocity * _slope(stops));
  }

  void _cancelled(_Stops stops) {
    if (!_dragging) return;
    _dragging = false;
    _settle(nearestStop(_top.value.clamp(stops.minimum, stops.maximum), _list(stops)), stops);
  }

  /// A spring takes the panel to [stop] at [velocity] (upwards positive),
  /// never past it (research S2); the overlay moves to it at once.
  void _settle(double stop, _Stops stops, {double velocity = 0}) {
    if (!_moved) _hold(stops);
    setState(() {
      _floor = null;
      _settled = stop;
    });
    final index = _list(stops).indexOf(stop);
    if (index >= 0) widget.onStop?.call(index);
    _run(stop, velocity: velocity);
  }

  /// Runs [_top] to [target] with the panel spring, then [then]; at once
  /// when the system asks for less motion.
  void _run(double target, {required double velocity, double beyond = 0, VoidCallback? then}) {
    final run = ++_runs;
    if (MediaQuery.disableAnimationsOf(context) || _top.value == target) {
      _top.value = target;
      then?.call();
      return;
    }
    _top
        .animateRelease(
          ReleaseSpringSimulation(
            spring: AppMotion.panelSpring,
            start: _top.value,
            end: target,
            velocity: velocity,
            beyond: beyond,
            tolerance: AppMotion.tolerance(MediaQuery.devicePixelRatioOf(context)),
          ),
          refreshRate: View.of(context).display.refreshRate,
        )
        .whenCompleteOrCancel(() {
          if (mounted && run == _runs) then?.call();
        });
  }

  /// The panel keeps its height and slides out of sight, 36 past the edge
  /// (3.x), at the finger's [velocity] (downwards positive); the fullscreen
  /// follows once it is out ([_slid]).
  void _enter(_Stops stops, {double velocity = 0}) {
    if (_entering || widget.onPortraitFullscreen == null) return;
    _hold(stops);
    final floor = _top.value.clamp(stops.minimum, stops.maximum);
    _entering = true;
    _floor = floor;
    // Out of sight is the end: no slow tail at the edge.
    _run(-36, velocity: -velocity, beyond: (floor + 36) * 0.01, then: _slid);
  }

  /// The panel's slide has ended: a pending entry happens now (3.x: the
  /// animation, not a timer, owns the request), then the panel comes back
  /// at its stop for when the room returns.
  void _slid() {
    if (!_entering || !mounted) return;
    _entering = false;
    // Not inside the animation's own update.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onPortraitFullscreen?.call();
      setState(() {
        _moved = false;
        _floor = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _area = constraints.maxHeight.isFinite ? math.max(0, constraints.maxHeight) : 0;
      final stops = portraitPanelStops(constraints.maxHeight, widget.mode, least: widget.least);
      final covered = _rest(stops);
      if (_picture == null || _pictureCovered != covered) {
        _picture = widget.player(covered);
        _pictureCovered = covered;
      }
      final sheet = Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 3,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _handle(context, stops, covered),
            Expanded(child: widget.content),
          ],
        ),
      );
      return Stack(
        key: const ValueKey('live-play-portrait-panel-layout'),
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: _picture!),
          AnimatedBuilder(
            key: const ValueKey('live-play-portrait-sheet'),
            animation: _top,
            builder: (context, sheet) {
              final place = _place(stops);
              return Positioned(left: 0, right: 0, bottom: place.bottom, height: place.height, child: sheet!);
            },
            child: sheet,
          ),
          AnimatedBuilder(
            key: const ValueKey('live-play-portrait-panels'),
            animation: _top,
            builder: (context, panels) {
              final place = _place(stops);
              return Positioned(
                left: 0,
                right: 0,
                bottom: place.bottom,
                height: math.min(_area, place.height + widget.keyboard),
                child: panels!,
              );
            },
            child: widget.panels,
          ),
        ],
      );
    },
  );

  Widget _handle(BuildContext context, _Stops stops, double current) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enter = widget.onPortraitFullscreen;
    final up = current < stops.maximum ? (current < stops.middle ? stops.middle : stops.maximum) : null;
    final down = current > stops.minimum ? (current > stops.middle ? stops.middle : stops.minimum) : null;
    // B09 c5 (audit B-17): a screen reader reads the stop's name, not
    // "250 px".
    String name(double height) => portraitPanelStopName(_list(stops).indexOf(nearestStop(height, _list(stops))));
    final grip = Semantics(
      label: i18n('portrait_panel_resize'),
      value: name(current),
      hint: i18n('portrait_panel_resize_hint'),
      increasedValue: up == null ? null : name(up),
      decreasedValue: down != null
          ? name(down)
          : enter == null
          ? null
          : i18n('portrait_fullscreen_enter_hint'),
      onTap: enter == null ? null : () => _enter(stops),
      onIncrease: up == null ? null : () => _settle(up, stops),
      onDecrease: down != null
          ? () => _settle(down, stops)
          : enter == null
          ? null
          : () => _enter(stops),
      child: GestureDetector(
        key: const ValueKey('live-play-portrait-handle'),
        behavior: HitTestBehavior.opaque,
        // The default start: the panel moves from where the drag is taken,
        // without the jump of the slop that `down` had (research S8).
        onTap: enter == null ? null : () => _enter(stops),
        onVerticalDragStart: (details) => _started(details, stops),
        onVerticalDragUpdate: (details) => _dragged(details, stops),
        onVerticalDragEnd: (details) => _released(details, stops),
        onVerticalDragCancel: () => _cancelled(stops),
        child: SizedBox(
          height: kMinInteractiveDimension,
          child: Center(
            child: enter == null
                ? SizedBox(
                    key: const ValueKey('live-play-portrait-grip'),
                    width: 38,
                    height: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.30),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.portraitFullscreenEnter, size: 20, color: scheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        i18n('portrait_fullscreen_enter_hint'),
                        key: const ValueKey('live-play-portrait-enter-hint'),
                        maxLines: 1,
                        style: theme.textTheme.labelMedium?.emphasis.copyWith(fontSize: 12, color: scheme.primary),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
    final label = i18n(widget.mobile ? 'enter_landscape_fullscreen' : 'live_play_fullscreen');
    return Stack(
      children: [
        grip,
        Positioned(
          right: 8,
          top: 0,
          bottom: 0,
          child: Center(
            child: Tooltip(
              message: label,
              child: TextButton.icon(
                key: const ValueKey('portrait-landscape-fullscreen'),
                onPressed: widget.onFullscreen,
                style: TextButton.styleFrom(
                  backgroundColor: scheme.surfaceContainerHighest,
                  foregroundColor: scheme.onSurfaceVariant,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.padded,
                  padding: const EdgeInsets.only(left: 9, right: 12),
                  shape: const StadiumBorder(),
                  textStyle: theme.textTheme.labelLarge?.emphasis.copyWith(fontSize: 13),
                ),
                icon: Icon(widget.mobile ? AppIcons.landscapeFullscreen : AppIcons.fullscreen, size: 17),
                label: Text(label, maxLines: 1),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
