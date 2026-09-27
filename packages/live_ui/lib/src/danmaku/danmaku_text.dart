import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:live_ui/src/danmaku/danmaku_models.dart';

// Tag characters (flag sequences). Kept out of the literal: the valid_regexps
// lint reads patterns without unicode mode, where `\u{…}` is no escape.
const String _tags = r'\u{E0020}-\u{E007F}';
final RegExp _emoji = RegExp(
  '[\\p{Extended_Pictographic}\\p{Emoji_Modifier}\\p{Regional_Indicator}\u200d\ufe0e\ufe0f\u20e3$_tags]',
  unicode: true,
);
final RegExp _breaks = RegExp(r'[\r\n\t  ]+');
final RegExp _spaces = RegExp(r'\s{2,}');

/// The text a danmaku shows: one line, trimmed, and without emoji when
/// [noEmoji] is set. Empty means nothing is left to show.
///
/// Emoji are Unicode pictographs with their modifiers, joiners, flags and
/// keycaps; digits, `#` and `*` stay. Platform image emoticons are a separate,
/// still open question (spec §8 item 6).
String danmakuDisplayText(String text, {required bool noEmoji}) {
  var out = text.replaceAll(_breaks, ' ');
  if (noEmoji) out = out.replaceAll(_emoji, '').replaceAll(_spaces, ' ');
  return out.trim();
}

/// A laid-out danmaku text: fill and optional outline paragraphs, laid out
/// once and drawn every frame. Shared between identical texts and released
/// as soon as nothing uses it (REN-9).
final class DanmakuGlyph {
  /// Lays out [text] in [color] with [style].
  factory layout(String text, Color color, DanmakuStyle style) {
    final alpha = (color.a * style.opacity).clamp(0.0, 1.0);
    final weight = FontWeight(style.fontWeight.clamp(100, 900));
    final paragraphStyle = ui.ParagraphStyle(maxLines: 1, fontFamily: style.fontFamily);
    final fill = _paragraph(
      text,
      paragraphStyle,
      ui.TextStyle(
        color: color.withValues(alpha: alpha),
        fontSize: style.fontSize,
        fontWeight: weight,
        fontFamily: style.fontFamily,
      ),
    );
    final strokeWidth = style.stroke && style.strokeWidth > 0 && alpha > 0 ? style.strokeWidth : 0.0;
    ui.Paragraph? outline;
    if (strokeWidth > 0) {
      // Dark text gets a light outline so it stays readable on dark video.
      final light = color.computeLuminance() < 0.2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..color = (light ? const Color(0xFFFFFFFF) : const Color(0xFF000000)).withValues(alpha: alpha * 0.8);
      outline = _paragraph(
        text,
        paragraphStyle,
        ui.TextStyle(foreground: paint, fontSize: style.fontSize, fontWeight: weight, fontFamily: style.fontFamily),
      );
    }
    return DanmakuGlyph._(
      fill,
      outline,
      fill.maxIntrinsicWidth.ceilToDouble() + strokeWidth,
      fill.height.ceilToDouble() + strokeWidth,
      strokeWidth / 2,
    );
  }

  new _(this._fill, this._outline, this.width, this.height, this._inset);

  final ui.Paragraph _fill;
  final ui.Paragraph? _outline;
  final double _inset;

  /// Width including the outline.
  final double width;

  /// Height including the outline.
  final double height;

  int _users = 0;
  bool _cached = false;
  bool _disposed = false;

  static ui.Paragraph _paragraph(String text, ui.ParagraphStyle paragraphStyle, ui.TextStyle style) {
    final builder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(style)
      ..addText(text);
    return builder.build()..layout(const ui.ParagraphConstraints(width: double.infinity));
  }

  /// Whether the paragraphs were released.
  bool get isDisposed => _disposed;

  /// Draws the glyph with its top-left corner at [offset].
  void paint(Canvas canvas, Offset offset) {
    final origin = offset.translate(_inset, _inset);
    final outline = _outline;
    if (outline != null) canvas.drawParagraph(outline, origin);
    canvas.drawParagraph(_fill, origin);
  }

  void _evict() {
    _cached = false;
    if (_users <= 0) _dispose();
  }

  void _dispose() {
    if (_disposed) return;
    _disposed = true;
    _fill.dispose();
    _outline?.dispose();
  }
}

/// Most-recently-used glyphs by text and color, reference counted so an
/// evicted glyph still on screen is released only when it leaves.
final class DanmakuGlyphCache {
  /// Creates a cache holding up to [capacity] unused-or-used glyphs.
  new(this._capacity);

  int _capacity;
  final LinkedHashMap<String, DanmakuGlyph> _glyphs = LinkedHashMap();

  /// Glyphs in the cache.
  int get length => _glyphs.length;

  /// Most glyphs kept.
  int get capacity => _capacity;

  /// Changes the capacity, evicting the least recently used.
  set capacity(int value) {
    _capacity = value < 0 ? 0 : value;
    _trim();
  }

  /// Cache key of [text] in [color].
  static String keyOf(String text, Color color) => '${color.toARGB32()}\u0000$text';

  /// Takes a reference to the glyph for [key], or null on a miss.
  DanmakuGlyph? acquire(String key) {
    final glyph = _glyphs.remove(key);
    if (glyph == null) return null;
    _glyphs[key] = glyph;
    glyph._users++;
    return glyph;
  }

  /// Adds a new [glyph] under [key] and takes a reference to it.
  DanmakuGlyph adopt(String key, DanmakuGlyph glyph) {
    glyph._users++;
    if (_capacity > 0) {
      glyph._cached = true;
      _glyphs.remove(key)?._evict();
      _glyphs[key] = glyph;
      _trim();
    }
    return glyph;
  }

  /// Drops a reference; frees the glyph when it is unused and not cached.
  void release(DanmakuGlyph glyph) {
    glyph._users--;
    if (glyph._users <= 0 && !glyph._cached) glyph._dispose();
  }

  /// Evicts everything; glyphs still on screen are freed when released.
  void clear() {
    for (final glyph in _glyphs.values) {
      glyph._evict();
    }
    _glyphs.clear();
  }

  void _trim() {
    while (_glyphs.length > _capacity) {
      final key = _glyphs.keys.first;
      _glyphs.remove(key)!._evict();
    }
  }
}
