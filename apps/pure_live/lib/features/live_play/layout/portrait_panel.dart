import 'package:flutter/gestures.dart';
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

/// The portrait room (3.x `PortraitLiveRoomLayout`, docs/ui/compare/U.2b):
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

class _PortraitPanelLayoutState extends State<PortraitPanelLayout> {
  /// The stop to start at ([PortraitPanelLayout.stop]) until the mode
  /// changes.
  late int? _first = widget.stop;

  /// The chosen height (a stop, or where a drag is now); null: the initial
  /// stop.
  double? _height;

  /// The height the picture's overlay leaves room for: changed when a drag
  /// ends, not while it moves.
  double? _settled;

  /// How far the panel has been pulled down past its lowest stop.
  double _dismiss = 0;

  bool _animate = false;
  bool _entering = false;

  @override
  void didUpdateWidget(PortraitPanelLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _first = null;
      _height = null;
      _settled = null;
      _dismiss = 0;
      _entering = false;
    }
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

  void _drag(DragUpdateDetails details, _Stops stops) {
    if (_entering) return;
    final delta = details.delta.dy;
    if (delta == 0) return;
    setState(() {
      _animate = false;
      final height = (_height ?? _start(stops)).clamp(stops.minimum, stops.maximum);
      if (delta > 0) {
        final collapse = delta.clamp(0.0, height - stops.minimum);
        _height = height - collapse;
        final rest = delta - collapse;
        if (widget.onPortraitFullscreen != null && rest > 0) {
          _dismiss = (_dismiss + rest).clamp(0.0, height);
        }
        return;
      }
      var up = -delta;
      final reveal = up.clamp(0.0, _dismiss);
      _dismiss -= reveal;
      up -= reveal;
      if (up > 0) _height = (height + up).clamp(stops.minimum, stops.maximum);
    });
  }

  void _release(DragEndDetails details, _Stops stops) {
    if (_entering) return;
    final height = (_height ?? _start(stops)).clamp(stops.minimum, stops.maximum);
    if (widget.onPortraitFullscreen != null &&
        panelDragEntersFullscreen(dismissed: _dismiss, panelHeight: height, velocity: details.primaryVelocity ?? 0)) {
      _enter(height);
      return;
    }
    _settle(nearestStop(height, _list(stops)), stops);
  }

  void _settle(double stop, _Stops stops) {
    setState(() {
      _animate = true;
      _dismiss = 0;
      _height = stop;
      _settled = stop;
    });
    final index = _list(stops).indexOf(stop);
    if (index >= 0) widget.onStop?.call(index);
  }

  void _enter(double height) {
    if (_entering || widget.onPortraitFullscreen == null) return;
    setState(() {
      _entering = true;
      _animate = true;
      _dismiss = height + 36;
    });
  }

  /// The panel's slide has ended: a pending entry happens now (3.x: the
  /// animation, not a timer, owns the request), then the panel comes back
  /// for when the room returns.
  void _slid() {
    if (!_entering || !mounted) return;
    _entering = false;
    // Not inside the animation's own update (a zero-length one ends while
    // the layout is built).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onPortraitFullscreen?.call();
      setState(() {
        _animate = false;
        _dismiss = 0;
      });
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stops = portraitPanelStops(constraints.maxHeight, widget.mode, least: widget.least);
      final current = (_height ?? _start(stops)).clamp(stops.minimum, stops.maximum);
      final covered = (_settled ?? _start(stops)).clamp(stops.minimum, stops.maximum);
      final still = MediaQuery.disableAnimationsOf(context);
      final duration = _animate && !still ? const Duration(milliseconds: 180) : Duration.zero;
      return Stack(
        key: const ValueKey('live-play-portrait-panel-layout'),
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: widget.player(covered)),
          AnimatedPositioned(
            key: const ValueKey('live-play-portrait-sheet'),
            duration: duration,
            curve: Curves.easeOutCubic,
            left: 0,
            right: 0,
            bottom: -_dismiss,
            height: current,
            onEnd: _slid,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 3,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _handle(context, stops, current),
                      Expanded(child: widget.content),
                    ],
                  ),
                ),
                widget.panels,
              ],
            ),
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
      onTap: enter == null ? null : () => _enter(current),
      onIncrease: up == null ? null : () => _settle(up, stops),
      onDecrease: down != null
          ? () => _settle(down, stops)
          : enter == null
          ? null
          : () => _enter(current),
      child: GestureDetector(
        key: const ValueKey('live-play-portrait-handle'),
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onTap: enter == null ? null : () => _enter(current),
        onVerticalDragUpdate: (details) => _drag(details, stops),
        onVerticalDragEnd: (details) => _release(details, stops),
        onVerticalDragCancel: () => _settle(nearestStop(current, _list(stops)), stops),
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
