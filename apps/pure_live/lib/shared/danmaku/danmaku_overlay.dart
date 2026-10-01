import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:live_core/live_core.dart';

/// How the flying danmaku look (3.x's danmaku settings).
@immutable
final class DanmakuLook {
  /// Creates a look.
  const new({
    this.fontSize = 16,
    this.fontWeight = 500,
    this.speed = 120,
    this.opacity = 1,
    this.area = 1,
    this.topMargin = 0,
    this.bottomMargin = 0,
    this.stroke = true,
    this.strokeWidth = 1.5,
  });

  /// Font size.
  final double fontSize;

  /// Font weight, 100–900.
  final int fontWeight;

  /// Speed in logical pixels per second.
  final double speed;

  /// Opacity 0–1.
  final double opacity;

  /// Share of the height the lanes may use, 0–1.
  final double area;

  /// Pixels kept free at the top.
  final double topMargin;

  /// Pixels kept free at the bottom.
  final double bottomMargin;

  /// Whether text has an outline.
  final bool stroke;

  /// Outline width.
  final double strokeWidth;

  @override
  bool operator ==(Object other) =>
      other is DanmakuLook &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight &&
      other.speed == speed &&
      other.opacity == opacity &&
      other.area == area &&
      other.topMargin == topMargin &&
      other.bottomMargin == bottomMargin &&
      other.stroke == stroke &&
      other.strokeWidth == strokeWidth;

  @override
  int get hashCode =>
      Object.hash(fontSize, fontWeight, speed, opacity, area, topMargin, bottomMargin, stroke, strokeWidth);
}

/// Danmaku flying over the video, right to left in lanes (3.x used
/// flame_barrage; this is a plain painter: no game engine, no extra
/// dependency). A message that finds no free lane is dropped instead of
/// overlapping, which keeps busy rooms readable.
class DanmakuOverlay extends StatefulWidget {
  /// Creates the overlay.
  const new({required this.messages, required this.retractions, required this.look, this.visible = true, super.key});

  /// Messages to fly.
  final Stream<LiveMessage> messages;

  /// Messages taken back.
  final Stream<LiveRetraction> retractions;

  /// The look.
  final DanmakuLook look;

  /// Hidden messages are not queued.
  final bool visible;

  @override
  State<DanmakuOverlay> createState() => DanmakuOverlayState();
}

/// The overlay's state (tests read [flyingCount]).
class DanmakuOverlayState extends State<DanmakuOverlay> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final List<_Flying> _items = [];
  final ValueNotifier<int> _frame = ValueNotifier(0);
  StreamSubscription<LiveMessage>? _messages;
  StreamSubscription<LiveRetraction>? _retractions;
  Duration _elapsed = Duration.zero;
  Size _size = Size.zero;

  /// Messages on screen now.
  int get flyingCount => _items.length;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages != widget.messages || oldWidget.retractions != widget.retractions) {
      unawaited(_messages?.cancel());
      unawaited(_retractions?.cancel());
      _listen();
    }
    if (oldWidget.look != widget.look) _clear();
    if (!widget.visible) _clear();
  }

  void _listen() {
    _messages = widget.messages.listen(_add);
    _retractions = widget.retractions.listen((retraction) {
      final before = _items.length;
      _items.removeWhere((item) {
        final gone = retracts(retraction, item.message);
        if (gone) item.dispose();
        return gone;
      });
      if (_items.length != before) _frame.value++;
    });
  }

  void _clear() {
    for (final item in _items) {
      item.dispose();
    }
    _items.clear();
    _frame.value++;
  }

  double get _lineHeight => widget.look.fontSize * 1.4;

  void _add(LiveMessage message) {
    if (!mounted || !widget.visible || _size.isEmpty || message.message.trim().isEmpty) return;
    final local = message.isLocal ? message.style : null;
    if (local != null) {
      _addLocal(message, local);
      return;
    }
    final look = widget.look;
    final top = look.topMargin.clamp(0, _size.height).toDouble();
    final usable = (_size.height * look.area.clamp(0, 1)).clamp(0, _size.height - top - look.bottomMargin).toDouble();
    final lanes = (usable / _lineHeight).floor();
    if (lanes <= 0) return;
    final now = _elapsed;
    // The first lane whose last message has fully entered the screen.
    int? lane;
    for (var i = 0; i < lanes; i++) {
      final last = _items.lastWhereOrNull((item) => item.lane == i && item.fixed == null);
      if (last == null || last.right(now, _size.width, look.speed) < _size.width - 16) {
        lane = i;
        break;
      }
    }
    if (lane == null) return;
    final color = Color.fromARGB(255, message.color.r, message.color.g, message.color.b);
    final style = TextStyle(
      fontSize: look.fontSize,
      fontWeight: FontWeight.values[((look.fontWeight ~/ 100) - 1).clamp(0, 8)],
      color: color,
      height: 1.2,
    );
    final fill = TextPainter(
      text: TextSpan(text: message.message, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final outline = look.stroke && look.strokeWidth > 0
        ? (TextPainter(
            text: TextSpan(
              text: message.message,
              style: style.copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = look.strokeWidth
                  ..color = Colors.black,
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout())
        : null;
    _items.add(_Flying(message, lane, top + lane * _lineHeight, now, fill, outline));
    if (!_ticker.isActive) _ticker.start();
  }

  /// A danmaku composed on this device (U.2k) flies in its own style (3.x
  /// `sendDanmaku`): size, weight, font, italic, spacing, opacity, outline
  /// colour and width, glow; scrolling at its own speed, or held at the top
  /// or bottom for its time. It always gets a place: it is what the user just
  /// sent.
  void _addLocal(LiveMessage message, LiveMessageStyle style) {
    final color = Color.fromARGB(
      255,
      message.color.r,
      message.color.g,
      message.color.b,
    ).withValues(alpha: style.opacity);
    final base = TextStyle(
      fontSize: style.fontSize,
      fontWeight: FontWeight.values[((style.fontWeight ~/ 100) - 1).clamp(0, 8)],
      fontFamily: style.fontFamily,
      fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
      letterSpacing: style.letterSpacing,
      height: 1.2,
    );
    final fill = TextPainter(
      text: TextSpan(
        text: message.message,
        style: base.copyWith(
          color: color,
          shadows: style.showShadow
              ? [
                  Shadow(
                    color: Color(style.shadowColor).withValues(alpha: style.opacity),
                    blurRadius: style.shadowBlur,
                    offset: Offset(style.shadowOffset, style.shadowOffset),
                  ),
                ]
              : null,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final outline = style.showStroke && style.strokeWidth > 0
        ? (TextPainter(
            text: TextSpan(
              text: message.message,
              style: base.copyWith(
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = style.strokeWidth
                  ..color = Color(style.strokeColor),
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout())
        : null;
    final height = style.fontSize * 1.4;
    final look = widget.look;
    final now = _elapsed;
    final top = look.topMargin.clamp(0, _size.height).toDouble();
    final lanes = ((_size.height - top - look.bottomMargin) / height).floor().clamp(1, 1 << 20);
    final fixed = style.placement == LiveMessagePlacement.scroll ? null : style.placement;
    // The first free lane from its edge; the first one when all are taken.
    var lane = 0;
    for (var i = 0; i < lanes; i++) {
      final taken = _items.any(
        (item) =>
            item.fixed == fixed &&
            item.lane == i &&
            item.message.isLocal &&
            (fixed != null || item.right(now, _size.width, item.speed ?? look.speed) >= _size.width - 16),
      );
      if (!taken) {
        lane = i;
        break;
      }
    }
    final y = fixed == LiveMessagePlacement.bottom
        ? _size.height - look.bottomMargin - (lane + 1) * height
        : top + lane * height;
    _items.add(
      _Flying(
        message,
        lane,
        y,
        now,
        fill,
        outline,
        speed: style.baseSpeed,
        fixed: fixed,
        stay: Duration(milliseconds: style.fixedDurationMs),
      ),
    );
    if (!_ticker.isActive) _ticker.start();
  }

  void _tick(Duration elapsed) {
    _elapsed = elapsed;
    final speed = widget.look.speed;
    _items.removeWhere((item) {
      final gone = item.gone(elapsed, _size.width, speed);
      if (gone) item.dispose();
      return gone;
    });
    _frame.value++;
    if (_items.isEmpty) {
      _ticker.stop();
      _elapsed = Duration.zero;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    unawaited(_messages?.cancel());
    unawaited(_retractions?.cancel());
    for (final item in _items) {
      item.dispose();
    }
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        return Opacity(
          opacity: widget.look.opacity.clamp(0, 1),
          child: CustomPaint(size: Size.infinite, painter: _DanmakuPainter(this)),
        );
      },
    ),
  );
}

final class _Flying {
  new(this.message, this.lane, this.y, this.start, this.fill, this.outline, {this.speed, this.fixed, this.stay});

  final LiveMessage message;
  final int lane;
  final double y;
  final Duration start;
  final TextPainter fill;
  final TextPainter? outline;

  /// Its own speed (a local danmaku), else the look's.
  final double? speed;

  /// Held at the top or bottom (a local danmaku), else scrolling.
  final LiveMessagePlacement? fixed;

  /// How long a held one stays.
  final Duration? stay;

  double left(Duration now, double width, double speed) {
    if (fixed != null) return (width - fill.width) / 2;
    return width - (now - start).inMicroseconds / Duration.microsecondsPerSecond * (this.speed ?? speed);
  }

  double right(Duration now, double width, double speed) => left(now, width, speed) + fill.width;

  bool gone(Duration now, double width, double speed) =>
      fixed != null ? now - start > (stay ?? const Duration(seconds: 4)) : right(now, width, speed) < 0;

  void dispose() {
    fill.dispose();
    outline?.dispose();
  }
}

class _DanmakuPainter extends CustomPainter {
  new(this.state) : super(repaint: state._frame);

  final DanmakuOverlayState state;

  @override
  void paint(Canvas canvas, Size size) {
    final speed = state.widget.look.speed;
    for (final item in state._items) {
      final offset = Offset(item.left(state._elapsed, size.width, speed), item.y);
      item.outline?.paint(canvas, offset);
      item.fill.paint(canvas, offset);
    }
  }

  @override
  bool shouldRepaint(_DanmakuPainter oldDelegate) => true;
}

extension<T> on List<T> {
  T? lastWhereOrNull(bool Function(T item) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}

/// Whether [message] is taken back by [retraction] (the flying layer).
bool retracts(LiveRetraction retraction, LiveMessage message) {
  if (retraction.isAll) return true;
  final messageId = retraction.messageId;
  if (messageId != null) return message.messageId == messageId;
  return retraction.userId != null && message.userId == retraction.userId;
}
