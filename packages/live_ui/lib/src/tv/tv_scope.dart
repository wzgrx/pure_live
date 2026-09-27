import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:live_ui/src/metrics.dart';

/// Sizes of the TV presentation (spec/design/principles.md §5.3).
abstract final class TvMetrics {
  /// The logical canvas every TV screen is scaled to.
  static const Size canvas = Size(960, 540);

  /// Horizontal safe margin (5% overscan).
  static const double safeX = Space.tvSafeX;

  /// Vertical safe margin.
  static const double safeY = Space.tvSafeY;

  /// Gap between grid cards.
  static const double gutter = Space.tvGutter;

  /// Card columns of every TV grid.
  static const int columns = 4;

  /// Width of the collapsed rail's item column.
  static const double railItems = 72;

  /// Width of the expanded rail's item column.
  static const double railExpandedItems = 200;

  /// The collapsed rail with the left safe margin: where page content starts.
  static const double railWidth = safeX + railItems;

  /// Growth of a focused card.
  static const double focusScale = 1.05;

  /// Width of the focus ring.
  static const double focusRing = 3;

  /// Holding OK this long opens the menu (remotes without a menu key).
  static const Duration longPress = Duration(milliseconds: 500);

  /// Width of the room page's side panels.
  static const double panelWidth = 320;
}

/// Keys of remotes, keyboards and game pads.
abstract final class TvKeys {
  /// OK: the D-pad centre, Enter, the game pad's A.
  static final Set<LogicalKeyboardKey> ok = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  };

  /// The D-pad and arrow keys with their directions.
  static final Map<LogicalKeyboardKey, TraversalDirection> directions = {
    LogicalKeyboardKey.arrowUp: TraversalDirection.up,
    LogicalKeyboardKey.arrowDown: TraversalDirection.down,
    LogicalKeyboardKey.arrowLeft: TraversalDirection.left,
    LogicalKeyboardKey.arrowRight: TraversalDirection.right,
  };
}

/// Whether and how the TV presentation is on.
@immutable
final class TvConfig {
  /// Creates a configuration.
  const new({this.enabled = false, this.focusGrowth = true});

  /// The phone and desktop presentation.
  static const TvConfig off = TvConfig();

  /// TV mode is on (principles §5.1 rule 1).
  final bool enabled;

  /// Focused cards grow 1.05× and lift one level; off in performance mode,
  /// which keeps only the ring (principles §5.3).
  final bool focusGrowth;

  @override
  bool operator ==(Object other) => other is TvConfig && other.enabled == enabled && other.focusGrowth == focusGrowth;

  @override
  int get hashCode => Object.hash(enabled, focusGrowth);
}

/// Tells the widgets below whether TV mode is on.
class TvScope extends InheritedWidget {
  /// Creates the scope.
  const new({required this.config, required super.child, super.key});

  /// The configuration.
  final TvConfig config;

  /// The configuration above [context]; [TvConfig.off] without a scope.
  static TvConfig of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TvScope>()?.config ?? TvConfig.off;

  @override
  bool updateShouldNotify(TvScope oldWidget) => oldWidget.config != config;
}

/// The factor that maps the 960×540 canvas onto a screen of [size] logical
/// pixels: one side fits exactly, the other gets the rest. 1 when the screen
/// already is the canvas (1080p and 4K TVs at their usual densities).
double tvCanvasScale(Size size) {
  if (size.isEmpty) return 1;
  final scale = math.min(size.width / TvMetrics.canvas.width, size.height / TvMetrics.canvas.height);
  return (scale - 1).abs() < 0.01 ? 1 : scale;
}

/// Lays the app out on the 960×540 canvas (principles §5.3): screens that
/// report another logical size are scaled, so a box at 1920×1080 logical
/// pixels shows the same layout as one at 960×540; the device pixel ratio
/// grows with the scale, so images still decode at the physical size. The
/// overscan margins (48 dp left and right, 28 dp top and bottom) become the
/// safe-area padding: app bars, sheets and lists keep their content inside,
/// backgrounds still reach the edges.
class TvCanvas extends StatelessWidget {
  /// Creates the canvas.
  const new({required this.child, super.key});

  /// The app.
  final Widget child;

  static const EdgeInsets _overscan = EdgeInsets.symmetric(horizontal: TvMetrics.safeX, vertical: TvMetrics.safeY);

  static EdgeInsets _atLeast(EdgeInsets insets) => EdgeInsets.fromLTRB(
    math.max(insets.left, _overscan.left),
    math.max(insets.top, _overscan.top),
    math.max(insets.right, _overscan.right),
    math.max(insets.bottom, _overscan.bottom),
  );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = tvCanvasScale(media.size);
    final logical = media.size / scale;
    final data = media.copyWith(
      size: logical,
      devicePixelRatio: media.devicePixelRatio * scale,
      padding: _atLeast(media.padding / scale),
      viewPadding: _atLeast(media.viewPadding / scale),
      viewInsets: media.viewInsets / scale,
      systemGestureInsets: media.systemGestureInsets / scale,
    );
    final content = MediaQuery(data: data, child: child);
    if (scale == 1) return content;
    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(size: logical, child: content),
    );
  }
}

/// The TV presentation below `MaterialApp.builder`: the [TvScope], and when
/// TV mode is on the canvas, focus highlights from the start (a remote has
/// no pointer to switch them on) and OK keys that do not repeat while held.
class TvRoot extends StatefulWidget {
  /// Creates the root.
  const new({required this.config, required this.child, super.key});

  /// The configuration.
  final TvConfig config;

  /// The app.
  final Widget child;

  @override
  State<TvRoot> createState() => _TvRootState();
}

class _TvRootState extends State<TvRoot> {
  @override
  void initState() {
    super.initState();
    _applyHighlight();
    FocusManager.instance.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(TvRoot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.enabled != widget.config.enabled) _applyHighlight();
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocus);
    if (widget.config.enabled) FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    super.dispose();
  }

  /// A dialog, sheet or menu that opens without a focused control would
  /// leave the remote nothing visible to move: its first control takes focus.
  void _onFocus() {
    if (!widget.config.enabled) return;
    final primary = FocusManager.instance.primaryFocus;
    if (primary is! FocusScopeNode || primary.focusedChild != null) return;
    final context = primary.context;
    if (context == null || ModalRoute.of(context) is! PopupRoute) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scope = primary.context;
      if (!mounted || scope == null || FocusManager.instance.primaryFocus != primary) return;
      FocusTraversalGroup.maybeOf(scope)?.findFirstFocus(primary, ignoreCurrentFocus: true)?.requestFocus();
    });
  }

  void _applyHighlight() => FocusManager.instance.highlightStrategy = widget.config.enabled
      ? FocusHighlightStrategy.alwaysTraditional
      : FocusHighlightStrategy.automatic;

  /// The framework activates on every repeat of a held OK key; a remote
  /// sends repeats while OK is held for the menu, so they stop here.
  static KeyEventResult _dropRepeats(FocusNode node, KeyEvent event) =>
      event is KeyRepeatEvent && TvKeys.ok.contains(event.logicalKey) ? KeyEventResult.handled : KeyEventResult.ignored;

  @override
  Widget build(BuildContext context) {
    var child = widget.child;
    if (widget.config.enabled) {
      child = Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _dropRepeats,
        child: TvCanvas(child: child),
      );
    }
    return TvScope(config: widget.config, child: child);
  }
}

/// Tells a short OK press from a long one: a short press acts on release, a
/// press held for [TvMetrics.longPress] opens the menu at once (principles
/// §6.3: 长按确认代替菜单键).
final class OkPressTracker {
  /// Creates a tracker; [onLongPress] returning null keeps long presses as
  /// plain presses.
  new({required this.onPress, required this.onLongPress, this.delay = TvMetrics.longPress});

  /// A short press.
  final VoidCallback onPress;

  /// The menu action for a long press, or null when there is none now.
  final VoidCallback? Function() onLongPress;

  /// How long a press must be held.
  final Duration delay;

  Timer? _timer;
  bool _down = false;
  bool _long = false;

  /// Handles [event]; true when it was an OK key (handled either way).
  bool handle(KeyEvent event) {
    if (!TvKeys.ok.contains(event.logicalKey)) return false;
    switch (event) {
      case KeyDownEvent():
        _timer?.cancel();
        _down = true;
        _long = false;
        final menu = onLongPress();
        if (menu != null) {
          _timer = Timer(delay, () {
            _long = true;
            menu();
          });
        }
      case KeyRepeatEvent():
        break;
      case KeyUpEvent():
        _timer?.cancel();
        // A release without its press (the press went to another page) does nothing.
        if (_down && !_long) onPress();
        _down = false;
        _long = false;
    }
    return true;
  }

  /// Forgets a press in progress.
  void reset() {
    _timer?.cancel();
    _down = false;
    _long = false;
  }

  /// Stops the timer.
  void dispose() => _timer?.cancel();
}
