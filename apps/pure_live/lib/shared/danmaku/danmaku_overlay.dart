import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/shared/danmaku/emotes.dart';

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
    this.laneHeight,
    this.fontFamily,
    this.textOnly = false,
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

  /// The height of a lane the mini windows give (U.2j); null is 3.x's
  /// ([lane]).
  final double? laneHeight;

  /// The font (a downloaded font's id, M12.4); null for the system's.
  final String? fontFamily;

  /// 3.x's "纯文字模式": emoticons are left out.
  final bool textOnly;

  /// The height of a lane: [laneHeight], else 3.x's 1.55 × the font size
  /// (24–64) and at least the font size + 10 (`track_manager.dart:14`).
  double get lane => laneHeight ?? math.max((fontSize * 1.55).clamp(24, 64).toDouble(), fontSize + 10);

  /// The height of an emoticon (3.x: 1.3 × the font size, 16–48).
  double get emoteSize => (fontSize * 1.3).clamp(16, 48).toDouble();

  /// A copy with [fontSize] and [area] replaced (a portrait stream's modes).
  DanmakuLook copyWith({double? fontSize, double? area}) => DanmakuLook(
    fontSize: fontSize ?? this.fontSize,
    fontWeight: fontWeight,
    speed: speed,
    opacity: opacity,
    area: area ?? this.area,
    topMargin: topMargin,
    bottomMargin: bottomMargin,
    stroke: stroke,
    strokeWidth: strokeWidth,
    laneHeight: laneHeight,
    fontFamily: fontFamily,
    textOnly: textOnly,
  );

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
      other.strokeWidth == strokeWidth &&
      other.laneHeight == laneHeight &&
      other.fontFamily == fontFamily &&
      other.textOnly == textOnly;

  @override
  int get hashCode => Object.hash(
    fontSize,
    fontWeight,
    speed,
    opacity,
    area,
    topMargin,
    bottomMargin,
    stroke,
    strokeWidth,
    laneHeight,
    fontFamily,
    textOnly,
  );
}

/// How many display refreshes pass between two paintings of the danmaku
/// (U.2h c3): the frame-rate [cap] as a whole fraction of the [refreshRate],
/// the largest one not above the cap (144 Hz with a cap of 60 paints every
/// third refresh, 48 times a second; 120 Hz every second one). Steps stay
/// even, where 3.x's cap of 60 on 90 or 144 Hz alternated one and two
/// refreshes. No cap paints every refresh.
int danmakuFrameDivisor({required double refreshRate, int? cap}) {
  if (cap == null || cap <= 0 || refreshRate <= 0) return 1;
  // A display that reports 120.3 Hz is still 120.
  return math.max(1, (refreshRate / cap - 0.02).ceil());
}

/// Danmaku flying over the video, right to left in lanes (docs/ui/compare/
/// U.2h; 3.x used flame_barrage, this is a plain painter: no game engine).
///
/// Each danmaku keeps the time it entered and its own speed, and its place
/// is speed × (this frame's vsync time − that time) in microseconds, so it
/// covers the same distance per second at 60, 90, 120 or 144 Hz; a new look
/// applies to the danmaku that come next, the ones on screen fly on (c2). A
/// message is laid out once and recorded as a picture, cached by content and
/// look (c6); a frame only moves the pictures. The opacity goes into the
/// colours (c5). A message that finds no lane waits (at most 120, 5 s), four
/// enter a frame at most, 48 are on screen at most (c7). Messages arrive
/// only while [running]; a danmaku composed on this device (U.2k) always
/// enters and flies on while the video is paused (c10).
class DanmakuOverlay extends StatefulWidget {
  /// Creates the overlay.
  const new({
    required this.messages,
    required this.retractions,
    required this.look,
    this.visible = true,
    this.maxVisible = 48,
    this.fps,
    this.refreshRate,
    this.color,
    this.running = true,
    this.held = false,
    this.emotes = EmoteTable.empty,
    super.key,
  });

  /// Messages to fly.
  final Stream<LiveMessage> messages;

  /// Messages taken back.
  final Stream<LiveRetraction> retractions;

  /// The look of the messages that enter from now on.
  final DanmakuLook look;

  /// Hidden: nothing flies and nothing waits.
  final bool visible;

  /// At most this many messages on screen at once (3.x 48; the mini
  /// windows' "最大同时显示数量", U.2j); null for no limit.
  final int? maxVisible;

  /// The frame-rate cap ([danmakuFrameDivisor]); null paints every refresh.
  final int? fps;

  /// The display's refresh rate now; null reads the window's display.
  final double? refreshRate;

  /// One colour for every message instead of the platform's; null keeps
  /// theirs.
  final Color? color;

  /// The video plays: false stops the danmaku on screen and lets no new
  /// ones in, except the ones composed on this device (3.x
  /// `sendDanmaku`'s `isPlaying`).
  final bool running;

  /// A message's actions are open (c9): everything stops until they close.
  final bool held;

  /// The platform's bundled emoticons: their codes fly as pictures.
  final EmoteTable emotes;

  @override
  State<DanmakuOverlay> createState() => DanmakuOverlayState();
}

/// The overlay's state: what is on screen, and the danmaku at a point
/// ([messageAt], c9).
class DanmakuOverlayState extends State<DanmakuOverlay> with SingleTickerProviderStateMixin {
  /// 3.x's waiting line: at most 120 messages, none older than 5 s.
  static const int maxPending = 120;

  /// How long a message may wait for a lane.
  static const Duration maxPendingAge = Duration(seconds: 5);

  /// At most this many messages enter in one frame (a burst spreads over a
  /// few frames).
  static const int perFrame = 4;

  /// A lane takes the next message once the last one is this far in.
  static const double laneGap = 40;

  late final Ticker _ticker = createTicker(_tick);
  final List<_Flying> _items = [];
  final Queue<_Waiting> _pending = Queue();
  final ValueNotifier<int> _frame = ValueNotifier(0);
  final _Pictures _pictures = _Pictures(96);
  late final _EmoteImages _images = _EmoteImages(() => scheduleMicrotask(_wake));
  StreamSubscription<LiveMessage>? _messages;
  StreamSubscription<LiveRetraction>? _retractions;
  Size _size = Size.zero;
  double _refresh = 60;

  /// The time of the platform's danmaku: it stands while the video is
  /// paused or a message is open.
  Duration _media = Duration.zero;

  /// The time of the danmaku composed here: it stands only while a message
  /// is open.
  Duration _free = Duration.zero;

  /// The ticker's time at the last frame and at the last painting.
  Duration _last = Duration.zero;
  Duration? _paintedAt;
  int _paints = 0;
  int _records = 0;
  TextStyle? _lastStyle;

  /// Messages on screen now.
  int get flyingCount => _items.length;

  /// Messages waiting for a lane.
  int get pendingCount => _pending.length;

  /// How many times the layer was painted.
  @visibleForTesting
  int get paintCount => _paints;

  /// How many messages were laid out and recorded (the cache saves the rest).
  @visibleForTesting
  int get recordCount => _records;

  /// The text style of the last recorded message.
  @visibleForTesting
  TextStyle? get lastTextStyle => _lastStyle;

  /// The messages on screen and where they are now.
  @visibleForTesting
  List<(LiveMessage, Rect)> get debugFlying => [
    for (final item in _items) (item.message, item.rect(_clockOf(item), _size.width)),
  ];

  /// Where [message] is now, or null when it is not on screen.
  @visibleForTesting
  Rect? rectOf(LiveMessage message) {
    for (final item in _items) {
      if (identical(item.message, message)) return item.rect(_clockOf(item), _size.width);
    }
    return null;
  }

  /// The danmaku drawn at [position] (the overlay's own coordinates), the
  /// one on top first; null for none (3.x `triggerItemAt`).
  LiveMessage? messageAt(Offset position) {
    for (final item in _items.reversed) {
      if (item.rect(_clockOf(item), _size.width).inflate(4).contains(position)) return item.message;
    }
    return null;
  }

  Duration _clockOf(_Flying item) => item.local ? _free : _media;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh = widget.refreshRate ?? View.maybeOf(context)?.display.refreshRate ?? 60;
  }

  @override
  void didUpdateWidget(DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages != widget.messages || oldWidget.retractions != widget.retractions) {
      unawaited(_messages?.cancel());
      unawaited(_retractions?.cancel());
      _listen();
    }
    _refresh = widget.refreshRate ?? View.maybeOf(context)?.display.refreshRate ?? 60;
    if (!widget.visible) {
      _clear();
      return;
    }
    // c10: the platform's waiting messages go with the paused video.
    if (!widget.running && oldWidget.running) _pending.removeWhere((waiting) => !waiting.local);
    if (widget.running != oldWidget.running || widget.held != oldWidget.held) {
      _paintedAt = null;
      _wake();
    }
  }

  void _listen() {
    _messages = widget.messages.listen(_add);
    _retractions = widget.retractions.listen((retraction) {
      _pending.removeWhere((waiting) => retracts(retraction, waiting.message));
      final before = _items.length;
      _items.removeWhere((item) {
        final gone = retracts(retraction, item.message);
        if (gone) item.picture.release();
        return gone;
      });
      if (_items.length != before) _frame.value++;
    });
  }

  void _clear() {
    for (final item in _items) {
      item.picture.release();
    }
    _items.clear();
    _pending.clear();
    _frame.value++;
  }

  void _add(LiveMessage message) {
    if (!mounted || !widget.visible || message.message.trim().isEmpty) return;
    final local = message.isLocal && message.style != null;
    if (!local && (!widget.running || widget.held)) return;
    final segments = _segments(message);
    if (segments == null) return;
    _pending.addLast(_Waiting(message, segments, _free, local: local));
    while (_pending.length > maxPending) {
      _pending.removeFirst();
    }
    _wake();
  }

  /// The pieces of [message] to draw: text and emoticons, without the
  /// emoticons in text-only mode (3.x skipped them); null when nothing is
  /// left.
  List<ChatSegment>? _segments(LiveMessage message) {
    var segments = chatSegments(message, widget.emotes);
    if (widget.look.textOnly) segments = segments.whereType<ChatTextSegment>().toList();
    final text = segments.whereType<ChatTextSegment>().map((segment) => segment.text).join();
    if (text.trim().isEmpty && !segments.any((segment) => segment is ChatEmoteSegment)) return null;
    return segments;
  }

  /// Whether the ticker has work: something moves or a message can enter.
  bool get _busy {
    if (widget.held || !widget.visible) return false;
    if (_items.any((item) => item.local || widget.running)) return true;
    return _pending.any((waiting) => (waiting.local || widget.running) && _images.ready(waiting.segments));
  }

  void _wake() {
    if (!mounted || _ticker.isActive || !_busy) return;
    _last = Duration.zero;
    _paintedAt = null;
    _ticker.start();
  }

  void _tick(Duration elapsed) {
    final delta = elapsed - _last;
    _last = elapsed;
    if (!widget.held) {
      _free += delta;
      if (widget.running) _media += delta;
    }
    var changed = false;
    _items.removeWhere((item) {
      final gone = item.gone(_clockOf(item), _size.width);
      if (gone) {
        item.picture.release();
        changed = true;
      }
      return gone;
    });
    if (!widget.held && !_size.isEmpty) changed = _enter() || changed;
    final period = Duration.microsecondsPerSecond / (_refresh > 0 ? _refresh : 60);
    final interval = danmakuFrameDivisor(refreshRate: _refresh, cap: widget.fps) * period;
    final painted = _paintedAt;
    if (painted == null || (elapsed - painted).inMicroseconds >= interval - period / 2 || (changed && _items.isEmpty)) {
      _paintedAt = elapsed;
      _frame.value++;
    }
    if (!_busy) _ticker.stop();
  }

  /// Lets waiting messages in: the stale ones go, then at most [perFrame]
  /// enter, in their order.
  bool _enter() {
    _pending.removeWhere((waiting) => _free - waiting.at > maxPendingAge);
    var entered = 0;
    var lanesFull = false;
    for (final waiting in [..._pending]) {
      if (entered >= perFrame) break;
      if (!waiting.local && (lanesFull || !widget.running)) continue;
      if (!_images.ready(waiting.segments)) continue;
      final placed = waiting.local ? _placeLocal(waiting) : _place(waiting);
      if (placed) {
        _pending.remove(waiting);
        entered++;
      } else {
        lanesFull = true;
      }
    }
    return entered > 0;
  }

  bool _place(_Waiting waiting) {
    final look = widget.look;
    final remote = _items.where((item) => !item.local).length;
    if (widget.maxVisible case final limit? when remote >= limit) return false;
    final lane = look.lane;
    final top = look.topMargin.clamp(0, _size.height).toDouble();
    final usable = (_size.height * look.area.clamp(0, 1)).clamp(0, _size.height - top - look.bottomMargin).toDouble();
    final lanes = (usable / lane).floor();
    if (lanes <= 0) return false;
    final now = _media;
    final width = _size.width;
    var speed = look.speed;
    // 3.x `TrackAllocator`: an empty lane first, else the one whose last
    // message is furthest in (at least [laneGap]).
    int? chosen;
    _Flying? ahead;
    var room = double.infinity;
    for (var i = 0; i < lanes; i++) {
      final last = _items.lastWhereOrNull((item) => item.lane == i && !item.local && item.fixed == null);
      if (last == null) {
        chosen = i;
        ahead = null;
        break;
      }
      final right = last.right(now, width);
      if (right <= width - laneGap && right < room) {
        room = right;
        chosen = i;
        ahead = last;
      }
    }
    if (chosen == null) return false;
    // 3.x `SpeedStrategy`: a faster one (the speed changed meanwhile) slows
    // down so it does not catch up with the one ahead before that leaves.
    if (ahead != null && speed > ahead.speed && room > 0) {
      speed = math.min(speed, ahead.speed * width / room);
    }
    final color =
        widget.color ?? Color.fromARGB(255, waiting.message.color.r, waiting.message.color.g, waiting.message.color.b);
    final picture = _render(waiting.segments, _Ink.of(look, color), look.emoteSize);
    final y = top + chosen * lane + (lane - picture.height) / 2;
    _items.add(_Flying(waiting.message, picture, chosen, y, speed, now));
    return true;
  }

  /// A danmaku composed on this device (U.2k) flies in its own style (3.x
  /// `sendDanmaku`): size, weight, font, italic, spacing, opacity, outline
  /// colour and width, glow; scrolling at its own speed, or held at the top
  /// or bottom for its time. It always gets a place: it is what the user just
  /// sent.
  bool _placeLocal(_Waiting waiting) {
    final message = waiting.message;
    final style = message.style!;
    final look = widget.look;
    final color = Color.fromARGB(255, message.color.r, message.color.g, message.color.b);
    final picture = _render(
      waiting.segments,
      _Ink.local(style, color),
      (style.fontSize * 1.3).clamp(16, 48).toDouble(),
      opacity: style.opacity,
    );
    final height = style.fontSize * 1.4;
    final now = _free;
    final width = _size.width;
    final top = look.topMargin.clamp(0, _size.height).toDouble();
    final lanes = ((_size.height - top - look.bottomMargin) / height).floor().clamp(1, 1 << 20);
    final fixed = style.placement == LiveMessagePlacement.scroll ? null : style.placement;
    // The first free lane from its edge; the first one when all are taken.
    var lane = 0;
    for (var i = 0; i < lanes; i++) {
      final taken = _items.any(
        (item) =>
            item.local &&
            item.fixed == fixed &&
            item.lane == i &&
            (fixed != null || item.right(now, width) >= width - 16),
      );
      if (!taken) {
        lane = i;
        break;
      }
    }
    final inset = (height - picture.height) / 2;
    final y = fixed == LiveMessagePlacement.bottom
        ? _size.height - look.bottomMargin - (lane + 1) * height + inset
        : top + lane * height + inset;
    _items.add(
      _Flying(
        message,
        picture,
        lane,
        y,
        style.baseSpeed,
        now,
        local: true,
        fixed: fixed,
        stay: Duration(milliseconds: style.fixedDurationMs),
      ),
    );
    return true;
  }

  /// [segments] in [ink], laid out once and recorded (c6): from the cache
  /// when the same content was recorded in the same look.
  _Rendered _render(List<ChatSegment> segments, _Ink ink, double emoteSize, {double opacity = 1}) {
    final key = (_keyOf(segments), ink, emoteSize, opacity);
    return _pictures.take(key, () => _record(segments, ink, emoteSize, opacity));
  }

  String _keyOf(List<ChatSegment> segments) {
    if (segments case [ChatTextSegment(:final text)]) return text;
    return segments
        .map(
          (segment) => switch (segment) {
            ChatTextSegment(:final text) => text,
            ChatEmoteSegment(:final asset, :final url, :final alt) =>
              '\u0000${_images.imageOf(segment) == null ? alt : '$asset|$url'}\u0000',
          },
        )
        .join();
  }

  _Rendered _record(List<ChatSegment> segments, _Ink ink, double emoteSize, double opacity) {
    _records++;
    final style = ink.style();
    _lastStyle = style;
    final outline = ink.strokeWidth > 0 && ink.strokeColor != null
        ? ink.style(
            outline: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = ink.strokeWidth
              ..strokeJoin = StrokeJoin.round
              ..color = Color(ink.strokeColor!),
          )
        : null;
    final pieces = <(TextPainter, TextPainter?)?>[];
    final images = <ui.Image?>[];
    var width = 0.0;
    var textHeight = 0.0;
    var hasEmote = false;
    TextPainter layout(String text, TextStyle style) => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    for (final segment in segments) {
      final image = segment is ChatEmoteSegment ? _images.imageOf(segment) : null;
      if (image != null) {
        hasEmote = true;
        pieces.add(null);
        images.add(image);
        width += emoteSize * image.width / math.max(1, image.height);
        continue;
      }
      // A picture that failed shows its code, as the chat list does.
      final text = switch (segment) {
        ChatTextSegment(:final text) => text,
        ChatEmoteSegment(:final alt) => alt,
      };
      final fill = layout(text, style);
      pieces.add((fill, outline == null ? null : layout(text, outline)));
      images.add(null);
      width += fill.width;
      textHeight = math.max(textHeight, fill.height);
    }
    final height = math.max(textHeight, hasEmote ? emoteSize : 0.0);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final imagePaint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(0, 0, 0, ink.emoteAlpha);
    var x = 0.0;
    for (var i = 0; i < pieces.length; i++) {
      if (pieces[i] case (final fill, final stroke)) {
        final offset = Offset(x, (height - fill.height) / 2);
        stroke?.paint(canvas, offset);
        fill.paint(canvas, offset);
        x += fill.width;
        fill.dispose();
        stroke?.dispose();
      } else {
        final image = images[i]!;
        final w = emoteSize * image.width / math.max(1, image.height);
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Rect.fromLTWH(x, (height - emoteSize) / 2, w, emoteSize),
          imagePaint,
        );
        x += w;
      }
    }
    return _Rendered(recorder.endRecording(), width, height);
  }

  @override
  void dispose() {
    _ticker.dispose();
    unawaited(_messages?.cancel());
    unawaited(_retractions?.cancel());
    for (final item in _items) {
      item.picture.release();
    }
    _pictures.dispose();
    _images.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        if (_pending.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _wake());
        return CustomPaint(size: Size.infinite, painter: _DanmakuPainter(this));
      },
    ),
  );
}

/// A message waiting for a lane.
final class _Waiting {
  new(this.message, this.segments, this.at, {required this.local});

  final LiveMessage message;
  final List<ChatSegment> segments;

  /// When it arrived (on the free clock).
  final Duration at;

  /// Composed on this device.
  final bool local;
}

/// The colours and font of a recorded message; equal inks share pictures.
@immutable
final class _Ink {
  const new({
    required this.fontSize,
    required this.fontWeight,
    required this.color,
    this.fontFamily,
    this.italic = false,
    this.letterSpacing,
    this.strokeColor,
    this.strokeWidth = 0,
    this.shadowColor,
    this.shadowBlur = 0,
    this.shadowOffset = 0,
    this.emoteAlpha = 1,
  });

  /// A platform message in [look]: the opacity goes into the colours, the
  /// outline's as its square root so a faint danmaku stays readable (3.x
  /// `resolveBarrageStrokeOpacity`).
  factory of(DanmakuLook look, Color color) {
    final opacity = look.opacity.clamp(0.0, 1.0);
    return _Ink(
      fontSize: look.fontSize,
      fontWeight: look.fontWeight,
      fontFamily: look.fontFamily,
      color: color.withValues(alpha: color.a * opacity).toARGB32(),
      strokeColor: look.stroke && look.strokeWidth > 0
          ? const Color(0xFF000000).withValues(alpha: math.sqrt(opacity)).toARGB32()
          : null,
      strokeWidth: look.stroke ? look.strokeWidth : 0,
      emoteAlpha: opacity,
    );
  }

  /// A message composed here, in its own style (U.2k).
  factory local(LiveMessageStyle style, Color color) => _Ink(
    fontSize: style.fontSize,
    fontWeight: style.fontWeight,
    fontFamily: style.fontFamily,
    italic: style.italic,
    letterSpacing: style.letterSpacing,
    color: color.withValues(alpha: style.opacity).toARGB32(),
    strokeColor: style.showStroke && style.strokeWidth > 0 ? style.strokeColor : null,
    strokeWidth: style.showStroke ? style.strokeWidth : 0,
    shadowColor: style.showShadow ? Color(style.shadowColor).withValues(alpha: style.opacity).toARGB32() : null,
    shadowBlur: style.shadowBlur,
    shadowOffset: style.shadowOffset,
    emoteAlpha: style.opacity,
  );

  final double fontSize;
  final int fontWeight;
  final String? fontFamily;
  final bool italic;
  final double? letterSpacing;
  final int color;
  final int? strokeColor;
  final double strokeWidth;
  final int? shadowColor;
  final double shadowBlur;
  final double shadowOffset;
  final double emoteAlpha;

  /// The fill's text style (3.x: a text box 1.15 × the font size), or the
  /// [outline]'s.
  TextStyle style({Paint? outline}) => TextStyle(
    fontSize: fontSize,
    fontWeight: FontWeight.values[((fontWeight ~/ 100) - 1).clamp(0, 8)],
    fontFamily: fontFamily,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    letterSpacing: letterSpacing,
    height: 1.15,
    color: outline == null ? Color(color) : null,
    foreground: outline,
    shadows: shadowColor == null || outline != null
        ? null
        : [Shadow(color: Color(shadowColor!), blurRadius: shadowBlur, offset: Offset(shadowOffset, shadowOffset))],
  );

  @override
  bool operator ==(Object other) =>
      other is _Ink &&
      other.fontSize == fontSize &&
      other.fontWeight == fontWeight &&
      other.fontFamily == fontFamily &&
      other.italic == italic &&
      other.letterSpacing == letterSpacing &&
      other.color == color &&
      other.strokeColor == strokeColor &&
      other.strokeWidth == strokeWidth &&
      other.shadowColor == shadowColor &&
      other.shadowBlur == shadowBlur &&
      other.shadowOffset == shadowOffset &&
      other.emoteAlpha == emoteAlpha;

  @override
  int get hashCode => Object.hash(
    fontSize,
    fontWeight,
    fontFamily,
    italic,
    letterSpacing,
    color,
    strokeColor,
    strokeWidth,
    shadowColor,
    shadowBlur,
    shadowOffset,
    emoteAlpha,
  );
}

/// A recorded message, shared by the danmaku showing it.
final class _Rendered {
  new(this.picture, this.width, this.height);

  final ui.Picture picture;
  final double width;
  final double height;
  int _users = 0;
  bool _cached = true;

  void release() {
    _users--;
    if (_users <= 0 && !_cached) picture.dispose();
  }

  void evict() {
    _cached = false;
    if (_users <= 0) picture.dispose();
  }
}

/// The recorded messages, the most recently used kept (3.x
/// `pictureCacheMaxSize` 96).
final class _Pictures {
  new(this.capacity);

  final int capacity;
  final LinkedHashMap<Object, _Rendered> _map = LinkedHashMap();

  _Rendered take(Object key, _Rendered Function() record) {
    final rendered = _map.remove(key) ?? record();
    _map[key] = rendered;
    rendered._users++;
    while (_map.length > capacity) {
      _map.remove(_map.keys.first)!.evict();
    }
    return rendered;
  }

  void dispose() {
    for (final rendered in _map.values) {
      rendered.evict();
    }
    _map.clear();
  }
}

/// The emoticon pictures of the flying layer, decoded once (at most 160
/// kept; a recorded message keeps its own).
final class _EmoteImages {
  new(this._onReady);

  static const int capacity = 160;

  final VoidCallback _onReady;
  final LinkedHashMap<String, ui.Image?> _done = LinkedHashMap();
  final Set<String> _loading = {};
  bool _disposed = false;

  static String _keyOf(ChatEmoteSegment emote) => emote.asset.isNotEmpty ? emote.asset : emote.url;

  /// The picture of [emote]; null while it loads or when it failed.
  ui.Image? imageOf(ChatSegment emote) => emote is ChatEmoteSegment ? _done[_keyOf(emote)] : null;

  /// Whether every emoticon of [segments] has loaded or failed; starts the
  /// loads that are missing.
  bool ready(List<ChatSegment> segments) {
    var ready = true;
    for (final segment in segments) {
      if (segment is! ChatEmoteSegment) continue;
      final key = _keyOf(segment);
      if (key.isEmpty || _done.containsKey(key)) continue;
      ready = false;
      if (_loading.add(key)) _load(key, segment);
    }
    return ready;
  }

  void _load(String key, ChatEmoteSegment emote, {bool network = false}) {
    final asset = !network && emote.asset.isNotEmpty;
    final provider = asset ? AssetImage(emote.asset) as ImageProvider : NetworkImage(emote.url);
    final stream = ResizeImage(provider, height: 96).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    void finish(ui.Image? image) {
      stream.removeListener(listener);
      _loading.remove(key);
      if (_disposed) {
        image?.dispose();
        return;
      }
      _done[key] = image;
      while (_done.length > capacity) {
        _done.remove(_done.keys.first)?.dispose();
      }
      _onReady();
    }

    listener = ImageStreamListener(
      (info, _) {
        final image = info.image.clone();
        info.dispose();
        finish(image);
      },
      onError: (_, _) {
        if (asset && emote.url.isNotEmpty) {
          stream.removeListener(listener);
          _load(key, emote, network: true);
          return;
        }
        finish(null);
      },
    );
    stream.addListener(listener);
  }

  void dispose() {
    _disposed = true;
    for (final image in _done.values) {
      image?.dispose();
    }
    _done.clear();
  }
}

final class _Flying {
  new(
    this.message,
    this.picture,
    this.lane,
    this.y,
    this.speed,
    this.start, {
    this.local = false,
    this.fixed,
    this.stay = const Duration(seconds: 4),
  });

  final LiveMessage message;
  final _Rendered picture;
  final int lane;
  final double y;

  /// Pixels a second: the look's when it entered, or its own (U.2k).
  final double speed;

  /// Composed on this device: it runs on the free clock.
  final bool local;

  /// Held at the top or bottom (a local danmaku), else scrolling.
  final LiveMessagePlacement? fixed;

  /// How long a held one stays.
  final Duration stay;

  /// When it entered (this frame's time on its clock): it starts at the
  /// right edge.
  final Duration start;

  double left(Duration now, double width) {
    if (fixed != null) return (width - picture.width) / 2;
    return width - (now - start).inMicroseconds * speed / Duration.microsecondsPerSecond;
  }

  double right(Duration now, double width) => left(now, width) + picture.width;

  Rect rect(Duration now, double width) => Rect.fromLTWH(left(now, width), y, picture.width, picture.height);

  bool gone(Duration now, double width) {
    return fixed != null ? now - start > stay : right(now, width) < 0;
  }
}

class _DanmakuPainter extends CustomPainter {
  new(this.state) : super(repaint: state._frame);

  final DanmakuOverlayState state;

  @override
  void paint(Canvas canvas, Size size) {
    state._paints++;
    for (final item in state._items) {
      final left = item.left(state._clockOf(item), size.width);
      if (left >= size.width || left + item.picture.width <= 0) continue;
      canvas
        ..save()
        ..translate(left, item.y)
        ..drawPicture(item.picture.picture)
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_DanmakuPainter oldDelegate) => !identical(oldDelegate.state, state);
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
