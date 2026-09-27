import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Where a danmaku is shown (spec/modules/danmaku.md §1 chat position).
enum DanmakuKind {
  /// Crosses the video from right to left in a lane.
  scroll,

  /// Centered in a top lane until it expires.
  top,

  /// Centered in a bottom lane until it expires.
  bottom,
}

/// One chat line for the on-video layer.
///
/// Independent of `live_danmaku`: the app maps its chat messages to this.
/// Only chat goes on screen (REN-7); super chats, gifts, online counts and
/// system messages stay in the list widgets.
@immutable
final class DanmakuItem {
  /// Creates an item.
  const new(
    this.text, {
    this.color = const Color(0xFFFFFFFF),
    this.kind = DanmakuKind.scroll,
    this.isLocal = false,
    this.duration,
    this.data,
  });

  /// Message text; line breaks are drawn as spaces.
  final String text;

  /// Text color. Its alpha is multiplied by [DanmakuStyle.opacity].
  final Color color;

  /// Position.
  final DanmakuKind kind;

  /// Generated on this device (local interaction, send echo). Never sampled,
  /// aged out or held back by the density caps; it jumps the queue and takes
  /// the roomiest lane when none is free.
  final bool isLocal;

  /// Lifetime of a [DanmakuKind.top] or [DanmakuKind.bottom] item; null uses
  /// [DanmakuStyle.fixedDuration]. Ignored for scrolling items.
  final Duration? duration;

  /// Opaque app payload (for example the chat message), returned by hit
  /// tests so the app can open copy and block actions (REN-8).
  final Object? data;

  @override
  String toString() => 'DanmakuItem($kind, "$text")';
}

/// Look of the layer; changes apply to items already on screen
/// (design principle 3).
@immutable
final class DanmakuStyle {
  /// Creates a style; defaults follow the room settings of `live_store`.
  const new({
    this.fontSize = 16,
    this.fontWeight = 500,
    this.opacity = 1,
    this.speed = 120,
    this.area = 1,
    this.topMargin = 0,
    this.bottomMargin = 0,
    this.stroke = true,
    this.strokeWidth = 1.5,
    this.noEmoji = false,
    this.fixedDuration = const Duration(seconds: 4),
    this.fontFamily,
  });

  /// Picture-in-picture and mini-window defaults (REN-6): font 12, half the
  /// height, 90 px/s.
  const new pip({
    this.fontSize = 12,
    this.fontWeight = 500,
    this.opacity = 1,
    this.speed = 90,
    this.area = 0.5,
    this.topMargin = 0,
    this.bottomMargin = 0,
    this.stroke = true,
    this.strokeWidth = 1,
    this.noEmoji = false,
    this.fixedDuration = const Duration(seconds: 4),
    this.fontFamily,
  });

  /// Font size in logical pixels (setting range 10–30).
  final double fontSize;

  /// Font weight, 100–900.
  final int fontWeight;

  /// Text opacity, 0–1, applied to the text color's alpha (no opacity layer,
  /// principles §7 item 10).
  final double opacity;

  /// Scroll speed in logical pixels per second, the same in every
  /// orientation and on desktop (REN-5).
  final double speed;

  /// Share of the height between the margins that lanes may use, 0–1. Applied
  /// exactly once (REG-DANMAKU-010).
  final double area;

  /// Extra top margin in logical pixels, on top of the safe area.
  final double topMargin;

  /// Extra bottom margin in logical pixels, on top of the safe area.
  final double bottomMargin;

  /// Draw an outline around the text (the only text effect offered; no blur).
  final bool stroke;

  /// Outline width in logical pixels.
  final double strokeWidth;

  /// Strip emoji; emoji-only messages are not shown.
  final bool noEmoji;

  /// Default lifetime of top and bottom items.
  final Duration fixedDuration;

  /// Font family; null uses the platform default.
  final String? fontFamily;

  /// Lane height: font size × 1.55, kept within 24–64 (REN-5).
  double get laneHeight => (fontSize * 1.55).clamp(24.0, 64.0);

  /// Whether text rendered with [other] looks the same as with this style.
  bool sameGlyphs(DanmakuStyle other) =>
      fontSize == other.fontSize &&
      fontWeight == other.fontWeight &&
      opacity == other.opacity &&
      stroke == other.stroke &&
      strokeWidth == other.strokeWidth &&
      noEmoji == other.noEmoji &&
      fontFamily == other.fontFamily;

  /// A copy with the given fields replaced.
  DanmakuStyle copyWith({
    double? fontSize,
    int? fontWeight,
    double? opacity,
    double? speed,
    double? area,
    double? topMargin,
    double? bottomMargin,
    bool? stroke,
    double? strokeWidth,
    bool? noEmoji,
    Duration? fixedDuration,
    String? fontFamily,
  }) => DanmakuStyle(
    fontSize: fontSize ?? this.fontSize,
    fontWeight: fontWeight ?? this.fontWeight,
    opacity: opacity ?? this.opacity,
    speed: speed ?? this.speed,
    area: area ?? this.area,
    topMargin: topMargin ?? this.topMargin,
    bottomMargin: bottomMargin ?? this.bottomMargin,
    stroke: stroke ?? this.stroke,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    noEmoji: noEmoji ?? this.noEmoji,
    fixedDuration: fixedDuration ?? this.fixedDuration,
    fontFamily: fontFamily ?? this.fontFamily,
  );

  @override
  bool operator ==(Object other) =>
      other is DanmakuStyle &&
      sameGlyphs(other) &&
      speed == other.speed &&
      area == other.area &&
      topMargin == other.topMargin &&
      bottomMargin == other.bottomMargin &&
      fixedDuration == other.fixedDuration;

  @override
  int get hashCode => Object.hash(
    fontSize,
    fontWeight,
    opacity,
    speed,
    area,
    topMargin,
    bottomMargin,
    stroke,
    strokeWidth,
    noEmoji,
    fixedDuration,
    fontFamily,
  );
}

/// Density and frame budget of one surface (REN-4, REN-6). Exceeding it lowers
/// the density; it never costs frames.
@immutable
final class DanmakuBudget {
  /// Creates a budget; defaults are the room surface's initial budget.
  const new({
    this.emitInterval = const Duration(milliseconds: 50),
    this.maxEmitPerFrame = 2,
    this.maxVisible = 48,
    this.maxPending = 120,
    this.maxPendingAge = const Duration(seconds: 5),
    this.glyphCacheSize = 96,
    this.fps,
  });

  /// Picture-in-picture and mini-window budget (REN-6): 6 on screen, one per
  /// 350 ms, 30 fps.
  const new pip({
    this.emitInterval = const Duration(milliseconds: 350),
    this.maxEmitPerFrame = 1,
    this.maxVisible = 6,
    this.maxPending = 24,
    this.maxPendingAge = const Duration(seconds: 5),
    this.glyphCacheSize = 16,
    this.fps = 30,
  });

  /// Average spacing between two admissions.
  final Duration emitInterval;

  /// Hard cap on admissions (and so text layouts) in one frame.
  final int maxEmitPerFrame;

  /// Most items on screen at once; local items do not count.
  final int maxVisible;

  /// Most items waiting; beyond it the oldest is dropped.
  final int maxPending;

  /// Waiting longer than this drops an item.
  final Duration maxPendingAge;

  /// Laid-out texts kept for reuse (same text and color).
  final int glyphCacheSize;

  /// Frame rate the layer advances at; null follows the display. The app
  /// resolves the automatic mode (REN-3) into this value.
  final int? fps;

  /// A copy advancing at [fps] (null follows the display).
  DanmakuBudget withFps(int? fps) => DanmakuBudget(
    emitInterval: emitInterval,
    maxEmitPerFrame: maxEmitPerFrame,
    maxVisible: maxVisible,
    maxPending: maxPending,
    maxPendingAge: maxPendingAge,
    glyphCacheSize: glyphCacheSize,
    fps: fps,
  );

  @override
  bool operator ==(Object other) =>
      other is DanmakuBudget &&
      emitInterval == other.emitInterval &&
      maxEmitPerFrame == other.maxEmitPerFrame &&
      maxVisible == other.maxVisible &&
      maxPending == other.maxPending &&
      maxPendingAge == other.maxPendingAge &&
      glyphCacheSize == other.glyphCacheSize &&
      fps == other.fps;

  @override
  int get hashCode =>
      Object.hash(emitInterval, maxEmitPerFrame, maxVisible, maxPending, maxPendingAge, glyphCacheSize, fps);
}

/// An on-screen item under a point.
@immutable
final class DanmakuHit {
  /// Creates a hit.
  const new(this.item, this.rect);

  /// The item.
  final DanmakuItem item;

  /// Its bounds in the view's coordinates at the time of the hit.
  final Rect rect;
}

/// Counters since the controller was created, for tests, diagnostics and the
/// performance suite.
@immutable
final class DanmakuStats {
  /// Creates a snapshot.
  const new({
    required this.added,
    required this.admitted,
    required this.droppedOverflow,
    required this.droppedStale,
    required this.droppedSampled,
    required this.droppedFiltered,
    required this.layouts,
    required this.maxFrameLayouts,
    required this.frames,
    required this.paints,
    required this.visible,
    required this.pending,
  });

  /// Items handed to the controller.
  final int added;

  /// Items that went on screen.
  final int admitted;

  /// Dropped because the waiting queue was full (oldest first).
  final int droppedOverflow;

  /// Dropped after waiting longer than [DanmakuBudget.maxPendingAge].
  final int droppedStale;

  /// Thinned out of an oversized batch by even sampling.
  final int droppedSampled;

  /// Dropped because nothing was left to show (emoji-only in no-emoji mode,
  /// blank text) or no lane can ever exist (zero area).
  final int droppedFiltered;

  /// Text layouts performed (cache misses and restyles).
  final int layouts;

  /// Most layouts in a single frame.
  final int maxFrameLayouts;

  /// Frames advanced.
  final int frames;

  /// Times the layer was painted.
  final int paints;

  /// Items on screen now.
  final int visible;

  /// Items waiting now.
  final int pending;
}
