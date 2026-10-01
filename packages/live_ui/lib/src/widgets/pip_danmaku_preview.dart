import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_ui/src/theme/live_colors.dart';

/// The preview of the mini windows' danmaku on the settings page (3.x
/// `PipDanmakuPreview`, U.6c): a dark 16:9 picture with up to 20 lines of
/// "小窗弹幕预览 n" crossing the top [area] at [speed], drawn with the
/// size, weight, opacity, colours and gap of the settings. Its own layer,
/// repainted at [fps]; still when animations are off (the system's
/// "remove animations", tests) or the page is hidden.
class PipDanmakuPreview extends StatefulWidget {
  /// Creates the preview.
  const new({
    required this.enabled,
    required this.label,
    required this.disabledLabel,
    required this.opacity,
    required this.fontSize,
    required this.fontWeight,
    required this.speed,
    required this.area,
    required this.maxVisible,
    required this.emitInterval,
    required this.fps,
    this.color,
    this.autoScale = true,
    this.minFontSize = 10,
    this.stroke = true,
    this.strokeWidth = 1,
    this.fontFamily,
    super.key,
  });

  /// Whether the mini windows show danmaku; off dims the lines and shows
  /// [disabledLabel] in the middle.
  final bool enabled;

  /// The text of a line ("小窗弹幕预览"); the number is added.
  final String label;

  /// "小窗弹幕已关闭".
  final String disabledLabel;

  /// 0.1–1.
  final double opacity;

  /// The configured size.
  final double fontSize;

  /// 100–900.
  final int fontWeight;

  /// Pixels per second at the reference width.
  final double speed;

  /// The share of the height danmaku may use, from the top.
  final double area;

  /// Lines on screen at most.
  final int maxVisible;

  /// Seconds between two lines.
  final double emitInterval;

  /// Frames per second of the movement.
  final int fps;

  /// One colour for every line; null keeps "the platform's colours" (four
  /// sample colours).
  final Color? color;

  /// Smaller text in a smaller window (3.x `CompactDanmakuMetrics`).
  final bool autoScale;

  /// The smallest scaled size (U.2j c7).
  final double minFontSize;

  /// The main danmaku's outline.
  final bool stroke;

  /// Its width.
  final double strokeWidth;

  /// The danmaku font, or the app's.
  final String? fontFamily;

  /// The width the configured size is meant for.
  static const double referenceWidth = 350;

  /// The sample colours of "keep the platform's colours".
  static const List<Color> platformColors = [
    Color(0xFFFFFFFF),
    Color(0xFF64B5F6),
    Color(0xFFFFD54F),
    Color(0xFF81C784),
  ];

  @override
  State<PipDanmakuPreview> createState() => _PipDanmakuPreviewState();
}

class _PipDanmakuPreviewState extends State<PipDanmakuPreview> with SingleTickerProviderStateMixin {
  static const Duration _cycle = Duration(seconds: 12);
  late final AnimationController _clock = AnimationController(vsync: this, duration: _cycle);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _clock
        ..stop()
        ..value = 0.25;
    } else if (!_clock.isAnimating) {
      _clock.repeat();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF172033), Color(0xFF090B10)],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final scale = widget.autoScale ? (width / PipDanmakuPreview.referenceWidth).clamp(0.65, 1.0) : 1.0;
            final scaled = widget.fontSize * scale;
            final size = widget.autoScale
                ? math.max(scaled, math.min(widget.fontSize, widget.minFontSize))
                : widget.fontSize;
            final opacity = widget.enabled ? widget.opacity.clamp(0.0, 1.0) : 0.25;
            final colors = switch (widget.color) {
              final color? => [color],
              null => PipDanmakuPreview.platformColors,
            };
            final count = widget.maxVisible.clamp(1, 20);
            final lines = [
              for (var i = 0; i < count; i++)
                _Line(
                  text: '${widget.label} ${i + 1}',
                  color: colors[i % colors.length].withValues(alpha: colors[i % colors.length].a * opacity),
                ),
            ];
            return Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                  child: CustomPaint(
                    painter: _PreviewPainter(
                      clock: _clock,
                      lines: lines,
                      fontSize: size,
                      fontWeight: FontWeight.values[((widget.fontWeight ~/ 100) - 1).clamp(0, 8)],
                      fontFamily: widget.fontFamily,
                      stroke: widget.stroke ? widget.strokeWidth : 0,
                      strokeAlpha: opacity,
                      speed: widget.speed * scale,
                      area: widget.area.clamp(0.1, 1.0),
                      gap: widget.emitInterval.clamp(0.05, 2.0),
                      fps: widget.fps.clamp(1, 240),
                      cycle: _cycle,
                    ),
                  ),
                ),
                if (!widget.enabled)
                  Center(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: OnVideoColors.dim,
                        borderRadius: BorderRadius.all(Radius.circular(20)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Text(
                          widget.disabledLabel,
                          style: const TextStyle(color: OnVideoColors.foreground, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

@immutable
final class _Line {
  const new({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  bool operator ==(Object other) => other is _Line && other.text == text && other.color == color;

  @override
  int get hashCode => Object.hash(text, color);
}

/// Lines enter from the right one [gap] after another and cross at [speed];
/// each takes the first track (from the top of [area]) whose last line has
/// moved far enough, so lines never overlap (3.x's preview painter).
class _PreviewPainter extends CustomPainter {
  new({
    required this.clock,
    required this.lines,
    required this.fontSize,
    required this.fontWeight,
    required this.fontFamily,
    required this.stroke,
    required this.strokeAlpha,
    required this.speed,
    required this.area,
    required this.gap,
    required this.fps,
    required this.cycle,
  }) : super(repaint: clock);

  final Animation<double> clock;
  final List<_Line> lines;
  final double fontSize;
  final FontWeight fontWeight;
  final String? fontFamily;
  final double stroke;
  final double strokeAlpha;
  final double speed;
  final double area;
  final double gap;
  final int fps;
  final Duration cycle;

  List<(TextPainter, TextPainter?)>? _painters;

  List<(TextPainter, TextPainter?)> _layout() => _painters ??= [
    for (final line in lines)
      (
        TextPainter(
          text: TextSpan(
            text: line.text,
            style: TextStyle(
              color: line.color,
              fontSize: fontSize,
              fontWeight: fontWeight,
              fontFamily: fontFamily,
              height: 1.15,
            ),
          ),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(),
        stroke <= 0
            ? null
            : (TextPainter(
                text: TextSpan(
                  text: line.text,
                  style: TextStyle(
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = stroke
                      ..color = OnVideoColors.ground.withValues(alpha: strokeAlpha * 0.8),
                    fontSize: fontSize,
                    fontWeight: fontWeight,
                    fontFamily: fontFamily,
                    height: 1.15,
                  ),
                ),
                maxLines: 1,
                textDirection: TextDirection.ltr,
              )..layout()),
      ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final painters = _layout();
    if (painters.isEmpty || speed <= 0) return;
    final seconds = cycle.inMilliseconds / 1000;
    final frame = (clock.value * seconds * fps).floor();
    final now = frame / fps;
    final trackHeight = math.max(fontSize * 1.8, fontSize + 10).clamp(18.0, 44.0);
    final tracks = math.max(1, (size.height * area / trackHeight).floor());
    final safeGap = (fontSize * 1.5).clamp(16.0, 40.0);
    // Where each track's last line ends (its right edge), at its start time.
    final trackFree = List<double>.filled(tracks, double.negativeInfinity);
    for (var i = 0; i < painters.length; i++) {
      final (fill, outline) = painters[i];
      final start = i * gap;
      // The first track whose last line has left room for this one.
      var track = 0;
      for (var t = 0; t < tracks; t++) {
        if (trackFree[t] <= start) {
          track = t;
          break;
        }
        if (trackFree[t] < trackFree[track]) track = t;
      }
      trackFree[track] = start + (fill.width + safeGap) / speed;
      final travelled = ((now - start) % seconds + seconds) % seconds * speed;
      final x = size.width - travelled;
      if (x > size.width || x + fill.width < 0) continue;
      final offset = Offset(x, track * trackHeight + (trackHeight - fill.height) / 2);
      outline?.paint(canvas, offset);
      fill.paint(canvas, offset);
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter old) =>
      old.lines.length != lines.length ||
      !_sameLines(old.lines, lines) ||
      old.fontSize != fontSize ||
      old.fontWeight != fontWeight ||
      old.fontFamily != fontFamily ||
      old.stroke != stroke ||
      old.strokeAlpha != strokeAlpha ||
      old.speed != speed ||
      old.area != area ||
      old.gap != gap ||
      old.fps != fps;

  static bool _sameLines(List<_Line> a, List<_Line> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
