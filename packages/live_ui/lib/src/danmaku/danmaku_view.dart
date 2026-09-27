import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:live_ui/src/danmaku/danmaku_engine.dart';
import 'package:live_ui/src/danmaku/danmaku_models.dart';

/// Feeds and steers one on-video danmaku surface (spec/modules/danmaku.md §5).
///
/// Create one per surface (room, PiP or mini window, focused multiview cell),
/// show it with a [DanmakuView], and dispose it with the surface's owner. Items
/// are cheap to [add]: text is laid out only when an item goes on screen, at
/// most [DanmakuBudget.maxEmitPerFrame] per frame. The frame callback runs
/// only while something is on screen or waiting, and not while paused.
///
/// ```dart
/// final danmaku = DanmakuController(style: DanmakuStyle(fontSize: 18));
/// danmaku.addAll(batch.map((m) => DanmakuItem(m.text, color: Color(m.rgb), data: m)));
/// danmaku.pause(#video);   // playback paused: positions freeze
/// danmaku.resume(#video);
/// danmaku.style = danmaku.style.copyWith(opacity: 0.6); // applies on screen
/// ```
class DanmakuController {
  /// Creates a controller. [clock] measures how long items wait (REN-4);
  /// tests pass a fake.
  new({
    DanmakuStyle style = const DanmakuStyle(),
    DanmakuBudget budget = const DanmakuBudget(),
    Duration Function()? clock,
  }) : _engine = DanmakuEngine(style: style, budget: budget, clock: clock);

  /// Pause reason used when none is given.
  static const Object defaultPause = #danmaku;

  final DanmakuEngine _engine;
  final DanmakuFrameClock _frames = DanmakuFrameClock();
  final Set<Object> _pauses = {};
  _RenderDanmaku? _host;
  bool _disposed = false;

  /// Current style.
  DanmakuStyle get style => _engine.style;

  /// Changes the style without a restart; items on screen take the new look
  /// right away, also while paused (design principle 3).
  set style(DanmakuStyle value) {
    if (value == _engine.style) return;
    _engine.style = value;
    _settleIfFrozen();
  }

  /// Current budget.
  DanmakuBudget get budget => _engine.budget;

  /// Changes the density and frame budget (for example when the surface
  /// becomes a PiP window).
  set budget(DanmakuBudget value) {
    if (value == _engine.budget) return;
    final fpsChanged = value.fps != _engine.budget.fps;
    _engine.budget = value;
    if (fpsChanged) _frames.reset();
    _update();
  }

  /// Items on screen.
  int get visibleCount => _engine.visibleCount;

  /// Items waiting to go on screen.
  int get pendingCount => _engine.pendingCount;

  /// Lanes at the current size and style.
  int get laneCount => _engine.laneCount;

  /// Whether any pause reason is held.
  bool get isPaused => _pauses.isNotEmpty;

  /// Whether the frame callback is running.
  bool get isTicking => _host?._ticker?.isActive ?? false;

  /// Items on screen with their bounds in the view, in paint order.
  List<DanmakuHit> get visibleItems => _engine.visibleItems;

  /// Counters for diagnostics and the performance suite.
  DanmakuStats get stats => _engine.stats;

  /// Queues one item.
  void add(DanmakuItem item) {
    assert(!_disposed, 'DanmakuController used after dispose');
    _engine.add(item);
    _update();
  }

  /// Queues a batch (one delivery of the chat pipeline). An oversized batch is
  /// thinned evenly across its whole span, local items excepted.
  void addAll(Iterable<DanmakuItem> items) {
    assert(!_disposed, 'DanmakuController used after dispose');
    _engine.addAll(items);
    _update();
  }

  /// Removes everything waiting and on screen (room change, danmaku off).
  void clear() {
    final hadVisible = _engine.visibleCount > 0;
    _engine.clear();
    if (hadVisible) _host?.markNeedsPaint();
    _update();
  }

  /// Freezes the layer for [reason]; items keep their positions and new ones
  /// wait (within the waiting limits). Distinct reasons (for example `#video`
  /// and `#menu` for the REN-8 action menu) stack: the layer runs again only
  /// when every one is resumed.
  void pause([Object reason = defaultPause]) {
    if (_pauses.add(reason)) _update();
  }

  /// Releases [reason]; the layer continues where it stopped.
  void resume([Object reason = defaultPause]) {
    if (_pauses.remove(reason)) _update();
  }

  /// The item under [position] in the [DanmakuView]'s coordinates, for the
  /// tap and long-press actions (REN-8). The view itself never takes
  /// pointers, so the video gesture layer calls this.
  DanmakuHit? itemAt(Offset position) => _engine.hitTest(position);

  /// Like [itemAt] for a global position; null when no view is laid out.
  DanmakuHit? itemAtGlobal(Offset globalPosition) {
    final host = _host;
    if (host == null || !host.attached || !host.hasSize) return null;
    return itemAt(host.globalToLocal(globalPosition));
  }

  /// Stops frames and frees every laid-out text.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _host?._stop();
    _host = null;
    _engine.dispose();
  }

  void _settleIfFrozen() {
    final host = _host;
    if (host == null) return;
    if (!isTicking && _engine.settle()) host.markNeedsPaint();
    _update();
  }

  void _update() {
    final host = _host;
    if (host == null) return;
    if (!_disposed && !isPaused && host.attached && _engine.hasWork) {
      host._start();
    } else {
      host._stop();
      _frames.reset();
    }
  }

  void _tick(_RenderDanmaku host, Duration elapsed) {
    if (!identical(host, _host)) return;
    final seconds = _frames.advance(elapsed, _engine.budget.fps);
    if (seconds == null) return;
    if (_engine.step(seconds)) host.markNeedsPaint();
    if (!_engine.hasWork) _update();
  }

  void _attach(_RenderDanmaku host) {
    if (_disposed) return;
    final previous = _host;
    if (previous != null && !identical(previous, host)) {
      // The newest surface takes over (a PiP or fullscreen view replacing the
      // room view); the old one stops and paints nothing.
      previous
        .._stop()
        ..markNeedsPaint();
    }
    _host = host;
    _frames.reset();
    _update();
  }

  void _suspend(_RenderDanmaku host) {
    if (!identical(host, _host)) return;
    host._stop();
    _frames.reset();
  }

  void _release(_RenderDanmaku host) {
    if (!identical(host, _host)) return;
    host._stop();
    _host = null;
    _frames.reset();
    if (!_disposed) _engine.releaseScreen();
  }

  void _layout(_RenderDanmaku host, Size size, EdgeInsets padding) {
    if (!identical(host, _host)) return;
    _engine.resize(size, topInset: padding.top, bottomInset: padding.bottom);
    _update();
  }

  void _paint(_RenderDanmaku host, Canvas canvas, Offset offset) {
    if (!identical(host, _host) || _disposed) return;
    _engine
      ..paints += 1
      ..paint(canvas, offset);
  }
}

/// The on-video danmaku layer of a [DanmakuController].
///
/// Place it above the video and below the controls, filling the video area
/// (for example in a `Stack` with `Positioned.fill`). It is its own repaint
/// boundary, draws every item on one canvas, never takes pointers or focus
/// (KEY-1), and keeps lanes clear of the system insets when [safeArea] is set.
class DanmakuView extends StatefulWidget {
  /// Creates the layer.
  const new({required this.controller, this.safeArea = true, super.key});

  /// Controller that feeds this layer.
  final DanmakuController controller;

  /// Add the ambient top and bottom safe-area padding to the margins.
  final bool safeArea;

  @override
  State<DanmakuView> createState() => _DanmakuViewState();
}

class _DanmakuViewState extends State<DanmakuView> with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) => _DanmakuSurface(
    controller: widget.controller,
    vsync: this,
    padding: widget.safeArea ? MediaQuery.paddingOf(context) : EdgeInsets.zero,
  );
}

class _DanmakuSurface extends LeafRenderObjectWidget {
  const new({required this.controller, required this.vsync, required this.padding});

  final DanmakuController controller;
  final TickerProvider vsync;
  final EdgeInsets padding;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderDanmaku(controller, vsync, padding);

  @override
  void updateRenderObject(BuildContext context, _RenderDanmaku renderObject) {
    renderObject
      ..controller = controller
      ..vsync = vsync
      ..padding = padding;
  }
}

class _RenderDanmaku extends RenderBox {
  new(this._controller, this._vsync, this._padding);

  DanmakuController _controller;
  TickerProvider _vsync;
  EdgeInsets _padding;
  Ticker? _ticker;

  DanmakuController get controller => _controller;
  set controller(DanmakuController value) {
    if (identical(value, _controller)) return;
    _controller._release(this);
    _controller = value;
    if (attached) value._attach(this);
    markNeedsLayout();
  }

  TickerProvider get vsync => _vsync;
  set vsync(TickerProvider value) {
    if (identical(value, _vsync)) return;
    final wasActive = _ticker?.isActive ?? false;
    _ticker?.dispose();
    _ticker = null;
    _vsync = value;
    if (wasActive) _start();
  }

  EdgeInsets get padding => _padding;
  set padding(EdgeInsets value) {
    if (value == _padding) return;
    _padding = value;
    markNeedsLayout();
  }

  void _start() {
    final ticker = _ticker ??= _vsync.createTicker((elapsed) => _controller._tick(this, elapsed));
    if (!ticker.isActive) ticker.start();
  }

  void _stop() {
    final ticker = _ticker;
    if (ticker != null && ticker.isActive) ticker.stop();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.hasBoundedWidth && constraints.hasBoundedHeight ? constraints.biggest : constraints.smallest;

  @override
  void performLayout() => _controller._layout(this, size, _padding);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller._attach(this);
  }

  @override
  void detach() {
    // Reparenting with a GlobalKey detaches and attaches again: only stop the
    // frames here; the screen is released when the view is unmounted.
    _controller._suspend(this);
    super.detach();
  }

  @override
  void dispose() {
    _controller._release(this);
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  void paint(PaintingContext context, Offset offset) => _controller._paint(this, context.canvas, offset);
}
