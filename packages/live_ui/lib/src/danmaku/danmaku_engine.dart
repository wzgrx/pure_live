import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'package:live_ui/src/danmaku/danmaku_lanes.dart';
import 'package:live_ui/src/danmaku/danmaku_models.dart';
import 'package:live_ui/src/danmaku/danmaku_text.dart';

/// Frame pacing (REN-2): turns display vsync times into motion steps at the
/// configured rate. Below the display rate an accumulator skips vsyncs; one
/// step never covers more than three frame intervals, so a stall slows the
/// layer for a moment instead of making it jump.
final class DanmakuFrameClock {
  Duration? _last;
  int _phase = 0;
  int _unstepped = 0;

  /// Forgets the last vsync; the next [advance] starts a new run.
  void reset() {
    _last = null;
    _phase = 0;
    _unstepped = 0;
  }

  /// Seconds to advance at the vsync [elapsed] (a ticker's time since it
  /// started), or null to skip this vsync. [fps] null follows the display.
  double? advance(Duration elapsed, int? fps) {
    final last = _last;
    _last = elapsed;
    if (last == null) return 0;
    final delta = (elapsed - last).inMicroseconds;
    if (delta <= 0) return null;
    final interval = Duration.microsecondsPerSecond ~/ (fps == null || fps <= 0 ? 60 : fps.clamp(1, 240));
    final capped = math.min(delta, interval * 3);
    if (fps == null || fps <= 0) return capped / Duration.microsecondsPerSecond;
    _phase += capped;
    _unstepped += capped;
    // A small tolerance keeps 59.94 Hz displays from losing every other step.
    if (_phase + 250 < interval) return null;
    _phase = _phase < interval ? 0 : _phase % interval;
    final step = math.min(_unstepped, interval * 3);
    _unstepped = 0;
    return step / Duration.microsecondsPerSecond;
  }
}

final class _Pending {
  new(this.item, this.seq, this.enqueuedAt);

  final DanmakuItem item;
  final int seq;
  final Duration enqueuedAt;
}

final class _Entry {
  new(this.item, this.glyph, this.lane, this.x, this.until);

  final DanmakuItem item;
  DanmakuGlyph glyph;
  final int lane;

  /// Left edge of a scrolling item in view coordinates.
  double x;

  /// Engine time a fixed item expires at.
  final double until;
}

/// The layer's state machine: waiting queues, lanes, on-screen items, text
/// cache and painting. Time comes in only through [step], so tests drive it
/// with simulated frames. `DanmakuController` wires it to a ticker.
final class DanmakuEngine {
  /// Creates an engine. [clock] is the monotonic clock waiting times are
  /// measured with (REN-4 drops items waiting over 5 s even while paused).
  new({this._style = const DanmakuStyle(), this._budget = const DanmakuBudget(), Duration Function()? clock})
    : _cache = DanmakuGlyphCache(_budget.glyphCacheSize),
      _clock = clock ?? _stopwatch();

  static Duration Function() _stopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  /// Scans of the waiting queues per frame, bounding the work of skipping
  /// blank or emoji-only items.
  static const int maxScanPerFrame = 32;

  final Duration Function() _clock;
  final DanmakuGlyphCache _cache;
  DanmakuStyle _style;
  DanmakuBudget _budget;

  final List<ListQueue<_Pending>> _waiting = List.generate(DanmakuKind.values.length, (_) => ListQueue<_Pending>());
  final ListQueue<_Pending> _local = ListQueue<_Pending>();
  final List<_Entry> _scroll = [];
  final List<_Entry> _top = [];
  final List<_Entry> _bottom = [];
  final List<double?> _tails = [];
  final List<double> _busy = [];

  Size? _size;
  double _topInset = 0;
  double _bottomInset = 0;
  int _laneCount = 0;
  double _now = 0;
  double _credit = double.infinity;
  int _seq = 0;
  int _localVisible = 0;
  bool _restyle = false;
  bool _dirty = false;

  int _added = 0;
  int _admitted = 0;
  int _droppedOverflow = 0;
  int _droppedStale = 0;
  int _droppedSampled = 0;
  int _droppedFiltered = 0;
  int _layouts = 0;
  int _frameLayouts = 0;
  int _maxFrameLayouts = 0;
  int _frames = 0;

  /// Times the layer was painted; counted by the view.
  int paints = 0;

  /// Current style.
  DanmakuStyle get style => _style;

  /// Applies a new style to waiting and on-screen items; on-screen text is
  /// laid out again on the next [step] or [settle].
  set style(DanmakuStyle value) {
    if (value == _style) return;
    final old = _style;
    _style = value;
    if (!value.sameGlyphs(old)) {
      _cache.clear();
      _restyle = true;
    }
    if (value.laneHeight != old.laneHeight ||
        value.area != old.area ||
        value.topMargin != old.topMargin ||
        value.bottomMargin != old.bottomMargin) {
      _layoutLanes();
    }
    _dirty = true;
  }

  /// Current budget.
  DanmakuBudget get budget => _budget;

  /// Applies a new budget; excess waiting items are dropped, oldest first.
  set budget(DanmakuBudget value) {
    _budget = value;
    _cache.capacity = value.glyphCacheSize;
    _trimWaiting();
  }

  /// Lanes available for scrolling items (and for each fixed layer).
  int get laneCount => _laneCount;

  /// Items on screen.
  int get visibleCount => _scroll.length + _top.length + _bottom.length;

  /// Items waiting.
  int get pendingCount => _remoteWaiting + _local.length;

  int get _remoteWaiting {
    var count = 0;
    for (final queue in _waiting) {
      count += queue.length;
    }
    return count;
  }

  /// Whether frames are needed: something is on screen, or something waits
  /// and the view has a size.
  bool get hasWork => visibleCount > 0 || (pendingCount > 0 && _size != null && !_size!.isEmpty);

  /// Counters so far.
  DanmakuStats get stats => DanmakuStats(
    added: _added,
    admitted: _admitted,
    droppedOverflow: _droppedOverflow,
    droppedStale: _droppedStale,
    droppedSampled: _droppedSampled,
    droppedFiltered: _droppedFiltered,
    layouts: _layouts,
    maxFrameLayouts: _maxFrameLayouts,
    frames: _frames,
    paints: paints,
    visible: visibleCount,
    pending: pendingCount,
  );

  /// Layouts done in the last [step].
  int get lastFrameLayouts => _frameLayouts;

  /// Queues [item]. Cheap: nothing is laid out until the item goes on screen.
  void add(DanmakuItem item) {
    _added++;
    final pending = _Pending(item, _seq++, _clock());
    if (item.isLocal) {
      _local.add(pending);
    } else {
      _waiting[item.kind.index].add(pending);
      _trimWaiting();
    }
  }

  /// Queues a batch; when it holds more than the waiting queue can, keeps an
  /// even sample across the whole batch (SMP-2). Local items are always kept.
  void addAll(Iterable<DanmakuItem> items) {
    final remote = <DanmakuItem>[];
    for (final item in items) {
      if (item.isLocal) {
        add(item);
      } else {
        remote.add(item);
      }
    }
    final kept = DanmakuLanes.sampleEvenly(remote, math.max(_budget.maxPending, 1));
    final thinned = remote.length - kept.length;
    _added += thinned;
    _droppedSampled += thinned;
    kept.forEach(add);
  }

  void _trimWaiting() {
    var excess = _remoteWaiting - math.max(_budget.maxPending, 0);
    while (excess-- > 0) {
      ListQueue<_Pending>? oldest;
      for (final queue in _waiting) {
        if (queue.isNotEmpty && (oldest == null || queue.first.seq < oldest.first.seq)) oldest = queue;
      }
      oldest!.removeFirst();
      _droppedOverflow++;
    }
  }

  /// Removes everything, waiting and on screen.
  void clear() {
    for (final queue in _waiting) {
      queue.clear();
    }
    _local.clear();
    _releaseScreen();
  }

  /// Removes the items [test] matches, waiting and on screen (a block takes
  /// effect at once, FLT-2). Returns how many left the screen.
  int removeWhere(bool Function(DanmakuItem item) test) {
    for (final queue in _waiting) {
      queue.removeWhere((pending) => test(pending.item));
    }
    _local.removeWhere((pending) => test(pending.item));
    var removed = 0;
    for (final list in [_scroll, _top, _bottom]) {
      list.removeWhere((entry) {
        if (!test(entry.item)) return false;
        _cache.release(entry.glyph);
        if (entry.item.isLocal) _localVisible--;
        removed++;
        return true;
      });
    }
    if (removed > 0) _dirty = true;
    return removed;
  }

  /// Removes what is on screen and frees every laid-out text (REN-9).
  void releaseScreen() {
    _releaseScreen();
    _cache.clear();
  }

  void _releaseScreen() {
    for (final list in [_scroll, _top, _bottom]) {
      for (final entry in list) {
        _cache.release(entry.glyph);
      }
      list.clear();
    }
    _localVisible = 0;
    _dirty = true;
  }

  /// Sets the view size and the safe-area insets. Scrolling items keep their
  /// position; lanes are recomputed. Returns whether anything changed.
  bool resize(Size size, {double topInset = 0, double bottomInset = 0}) {
    if (size == _size && topInset == _topInset && bottomInset == _bottomInset) return false;
    _size = size;
    _topInset = topInset;
    _bottomInset = bottomInset;
    _layoutLanes();
    _dirty = true;
    return true;
  }

  void _layoutLanes() {
    final size = _size;
    _laneCount = size == null
        ? 0
        : DanmakuLanes.count(
            height: size.height,
            laneHeight: _style.laneHeight,
            area: _style.area,
            topInset: _laneTop,
            bottomInset: _bottomInset + _style.bottomMargin,
          );
  }

  double get _laneTop => _topInset + _style.topMargin;

  double get _areaBottom {
    final size = _size!;
    final usable = math.max(0, size.height - _laneTop - _bottomInset - _style.bottomMargin);
    return _laneTop + usable * _style.area.clamp(0.0, 1.0);
  }

  /// Advances [seconds] of motion, retires finished items and admits waiting
  /// ones within the budget. Returns whether the picture changed.
  bool step(double seconds) {
    _frames++;
    _frameLayouts = 0;
    var changed = _dirty;
    _dirty = false;
    final dt = seconds > 0 ? seconds : 0.0;
    _now += dt;
    if (dt > 0 && _scroll.isNotEmpty) {
      final dx = _style.speed * dt;
      for (final entry in _scroll) {
        entry.x -= dx;
      }
      changed = true;
    }
    if (_retire()) changed = true;
    if (_restyle && _restyleScreen()) changed = true;
    if (_admit(dt)) changed = true;
    if (!hasWork) _credit = math.max(1, _budget.maxEmitPerFrame).toDouble();
    if (_frameLayouts > _maxFrameLayouts) _maxFrameLayouts = _frameLayouts;
    return changed;
  }

  /// Applies a pending style change without advancing time, for a paused or
  /// idle layer. Returns whether the picture changed.
  bool settle() {
    var changed = _dirty;
    _dirty = false;
    if (_restyle && _restyleScreen()) changed = true;
    return changed;
  }

  bool _retire() {
    final before = visibleCount;
    _scroll.removeWhere((entry) => entry.x + entry.glyph.width < 0 && _drop(entry));
    _top.removeWhere((entry) => entry.until <= _now && _drop(entry));
    _bottom.removeWhere((entry) => entry.until <= _now && _drop(entry));
    return visibleCount != before;
  }

  bool _drop(_Entry entry) {
    _cache.release(entry.glyph);
    if (entry.item.isLocal) _localVisible--;
    return true;
  }

  bool _restyleScreen() {
    _restyle = false;
    if (visibleCount == 0) return false;
    for (final list in [_scroll, _top, _bottom]) {
      list.removeWhere((entry) {
        final text = danmakuDisplayText(entry.item.text, noEmoji: _style.noEmoji);
        if (text.isEmpty) return _drop(entry);
        final glyph = _glyph(text, entry.item.color);
        _cache.release(entry.glyph);
        entry.glyph = glyph;
        return false;
      });
    }
    return true;
  }

  DanmakuGlyph _glyph(String text, Color color) {
    final key = DanmakuGlyphCache.keyOf(text, color);
    final cached = _cache.acquire(key);
    if (cached != null) return cached;
    _layouts++;
    _frameLayouts++;
    return _cache.adopt(key, DanmakuGlyph.layout(text, color, _style));
  }

  bool _admit(double dt) {
    final size = _size;
    if (size == null || size.isEmpty) return false;
    if (_laneCount == 0) {
      // No lane can exist at this size or area: waiting would only burn frames.
      _droppedFiltered += pendingCount;
      for (final queue in _waiting) {
        queue.clear();
      }
      _local.clear();
      return false;
    }
    final cap = math.max(1, _budget.maxEmitPerFrame);
    var admitted = 0;
    var scans = 0;

    while (_local.isNotEmpty && admitted < cap && scans < maxScanPerFrame) {
      scans++;
      final pending = _local.first;
      final text = danmakuDisplayText(pending.item.text, noEmoji: _style.noEmoji);
      if (text.isEmpty) {
        _local.removeFirst();
        _droppedFiltered++;
        continue;
      }
      final lane = _laneFor(pending.item.kind, force: true);
      if (lane < 0) break;
      _local.removeFirst();
      _place(pending.item, text, lane);
      admitted++;
    }

    final interval = _budget.emitInterval.inMicroseconds / Duration.microsecondsPerSecond;
    _credit = interval <= 0 ? cap.toDouble() : math.min(_credit + dt / interval, cap.toDouble());

    final now = _clock();
    for (final queue in _waiting) {
      while (queue.isNotEmpty && now - queue.first.enqueuedAt > _budget.maxPendingAge) {
        queue.removeFirst();
        _droppedStale++;
      }
    }

    while (_credit >= 1 &&
        admitted < cap &&
        visibleCount - _localVisible < _budget.maxVisible &&
        scans < maxScanPerFrame) {
      scans++;
      ListQueue<_Pending>? from;
      var lane = -1;
      for (final kind in DanmakuKind.values) {
        final queue = _waiting[kind.index];
        if (queue.isEmpty || (from != null && queue.first.seq > from.first.seq)) continue;
        final candidate = _laneFor(kind, force: false);
        if (candidate < 0) continue;
        from = queue;
        lane = candidate;
      }
      if (from == null) break;
      final pending = from.removeFirst();
      final text = danmakuDisplayText(pending.item.text, noEmoji: _style.noEmoji);
      if (text.isEmpty) {
        _droppedFiltered++;
        continue;
      }
      _place(pending.item, text, lane);
      _credit -= 1;
      admitted++;
    }
    return admitted > 0;
  }

  void _place(DanmakuItem item, String text, int lane) {
    final glyph = _glyph(text, item.color);
    final life = (item.duration ?? _style.fixedDuration).inMicroseconds / Duration.microsecondsPerSecond;
    final entry = _Entry(item, glyph, lane, _size!.width, _now + life);
    switch (item.kind) {
      case DanmakuKind.scroll:
        _scroll.add(entry);
      case DanmakuKind.top:
        _top.add(entry);
      case DanmakuKind.bottom:
        _bottom.add(entry);
    }
    if (item.isLocal) _localVisible++;
    _admitted++;
  }

  int _laneFor(DanmakuKind kind, {required bool force}) {
    if (_laneCount == 0) return -1;
    if (kind == DanmakuKind.scroll) {
      _tails
        ..length = _laneCount
        ..fillRange(0, _laneCount, null);
      for (final entry in _scroll) {
        if (entry.lane >= _laneCount) continue;
        final right = entry.x + entry.glyph.width;
        final tail = _tails[entry.lane];
        if (tail == null || right > tail) _tails[entry.lane] = right;
      }
      final lane = DanmakuLanes.pickScroll(_tails, width: _size!.width, gap: DanmakuLanes.gap(_style.fontSize));
      return lane >= 0 || !force ? lane : DanmakuLanes.roomiestScroll(_tails);
    }
    if (_busy.length > _laneCount) _busy.length = _laneCount;
    while (_busy.length < _laneCount) {
      _busy.add(double.negativeInfinity);
    }
    _busy.fillRange(0, _laneCount, double.negativeInfinity);
    for (final entry in kind == DanmakuKind.top ? _top : _bottom) {
      if (entry.lane < _laneCount && entry.until > _busy[entry.lane]) _busy[entry.lane] = entry.until;
    }
    final lane = DanmakuLanes.pickFixed(_busy, _now);
    return lane >= 0 || !force ? lane : DanmakuLanes.soonestFixed(_busy);
  }

  Rect _rectOf(_Entry entry, DanmakuKind kind) {
    final laneHeight = _style.laneHeight;
    final glyph = entry.glyph;
    final pad = (laneHeight - glyph.height) / 2;
    final width = _size!.width;
    return switch (kind) {
      DanmakuKind.scroll => Rect.fromLTWH(entry.x, _laneTop + entry.lane * laneHeight + pad, glyph.width, glyph.height),
      DanmakuKind.top => Rect.fromLTWH(
        (width - glyph.width) / 2,
        _laneTop + entry.lane * laneHeight + pad,
        glyph.width,
        glyph.height,
      ),
      DanmakuKind.bottom => Rect.fromLTWH(
        (width - glyph.width) / 2,
        _areaBottom - (entry.lane + 1) * laneHeight + pad,
        glyph.width,
        glyph.height,
      ),
    };
  }

  /// Draws every on-screen item, clipped to the view.
  void paint(Canvas canvas, Offset offset) {
    final size = _size;
    if (size == null || visibleCount == 0) return;
    canvas
      ..save()
      ..clipRect(offset & size, doAntiAlias: false);
    final width = size.width;
    for (final entry in _scroll) {
      if (entry.x >= width || entry.x + entry.glyph.width <= 0) continue;
      entry.glyph.paint(canvas, offset + _rectOf(entry, DanmakuKind.scroll).topLeft);
    }
    for (final entry in _top) {
      entry.glyph.paint(canvas, offset + _rectOf(entry, DanmakuKind.top).topLeft);
    }
    for (final entry in _bottom) {
      entry.glyph.paint(canvas, offset + _rectOf(entry, DanmakuKind.bottom).topLeft);
    }
    canvas.restore();
  }

  /// Items on screen with their bounds, in paint order.
  List<DanmakuHit> get visibleItems {
    if (_size == null) return const [];
    return [
      for (final entry in _scroll) DanmakuHit(entry.item, _rectOf(entry, DanmakuKind.scroll)),
      for (final entry in _top) DanmakuHit(entry.item, _rectOf(entry, DanmakuKind.top)),
      for (final entry in _bottom) DanmakuHit(entry.item, _rectOf(entry, DanmakuKind.bottom)),
    ];
  }

  /// The top-most item under [position] (view coordinates), with [slop]
  /// extra pixels above and below for touch.
  DanmakuHit? hitTest(Offset position, {double slop = 4}) {
    if (_size == null) return null;
    for (final (list, kind) in [
      (_bottom, DanmakuKind.bottom),
      (_top, DanmakuKind.top),
      (_scroll, DanmakuKind.scroll),
    ]) {
      for (var i = list.length - 1; i >= 0; i--) {
        final rect = _rectOf(list[i], kind);
        if (Rect.fromLTRB(rect.left, rect.top - slop, rect.right, rect.bottom + slop).contains(position)) {
          return DanmakuHit(list[i].item, rect);
        }
      }
    }
    return null;
  }

  /// Frees everything; the engine must not be used afterwards.
  void dispose() {
    clear();
    _cache.clear();
  }
}
