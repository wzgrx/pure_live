import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_ui/src/theme/live_colors.dart';

/// What [RecordGlyph] shows: the state of a room's recording
/// (docs/T08/T08b/T08b.3). Only [recording] is red; every state that does
/// not write a file is drawn in the surrounding icons' colour, so the picture
/// alone tells "not recording" from "recording".
enum RecordGlyphState {
  /// Not recording (no task, stopped, saved): a ring around a dot.
  idle,

  /// Records by itself later (waits for the room, or for a free slot): the
  /// ring with a small clock at its lower right.
  waiting,

  /// Resolving the stream or starting FFmpeg: a spinning arc on a faint ring.
  preparing,

  /// Writing media: a white rounded square on a red disc, its halo
  /// breathing unless the system asks for less motion.
  recording,

  /// Waiting to retry an interrupted attempt: an amber dashed ring.
  reconnecting,

  /// Joining the recorded segments: the join's progress on a faint ring
  /// (spinning until FFmpeg reports).
  processing,

  /// The last attempt failed: the ring with an error-coloured "!" at its
  /// lower right.
  failed,
}

/// The record picture (docs/T08/T08b/T08b.3) of the room bar's record
/// button, the fullscreen bars, the record panel's status card, the
/// recording centre and the marks on the picture: one drawing in seven
/// states, in a box of [size] (24 by default; strokes scale with it).
class RecordGlyph extends StatefulWidget {
  /// Creates the picture.
  const new({required this.state, this.size = 24, this.color, this.progress, this.onVideo = false, super.key});

  /// Which state.
  final RecordGlyphState state;

  /// The outer size.
  final double size;

  /// The ink of the states that do not record (the ring, the dot, the
  /// clock, the arcs): the surrounding icon colour ([IconTheme]) by default,
  /// so it matches the buttons beside it.
  final Color? color;

  /// The join's progress from 0 to 1 ([RecordGlyphState.processing]); null
  /// spins like [RecordGlyphState.preparing].
  final double? progress;

  /// On the picture (always dark): the dark theme's amber and error tones.
  final bool onVideo;

  /// One breath of the recording halo (in, then out).
  static const Duration breath = Duration(milliseconds: 2400);

  /// One turn of the preparing arc.
  static const Duration turn = Duration(milliseconds: 1200);

  @override
  State<RecordGlyph> createState() => _RecordGlyphState();
}

enum _Motion { none, breathe, spin }

class _RecordGlyphState extends State<RecordGlyph> with SingleTickerProviderStateMixin {
  AnimationController? _motion;
  _Motion _running = _Motion.none;

  _Motion get _wanted {
    if (MediaQuery.disableAnimationsOf(context)) return _Motion.none;
    return switch (widget.state) {
      RecordGlyphState.recording => _Motion.breathe,
      RecordGlyphState.preparing => _Motion.spin,
      RecordGlyphState.processing when widget.progress == null => _Motion.spin,
      _ => _Motion.none,
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(RecordGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final wanted = _wanted;
    if (wanted == _running) return;
    _running = wanted;
    switch (wanted) {
      case _Motion.none:
        _motion?.stop();
      case _Motion.breathe:
        // Half a breath each way.
        (_motion ??= AnimationController(vsync: this))
          ..duration = RecordGlyph.breath ~/ 2
          ..repeat(reverse: true);
      case _Motion.spin:
        (_motion ??= AnimationController(vsync: this))
          ..duration = RecordGlyph.turn
          ..repeat();
    }
  }

  @override
  void dispose() {
    _motion?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final video = widget.onVideo;
    final moving = _running != _Motion.none;
    final paint = CustomPaint(
      size: Size.square(widget.size),
      painter: RecordGlyphPainter(
        state: widget.state,
        ink: widget.color ?? IconTheme.of(context).color ?? scheme.onSurfaceVariant,
        warning: LiveSemanticColors.warning(video ? Brightness.dark : scheme.brightness),
        error: video ? OnVideoColors.error : scheme.error,
        onError: video ? OnVideoColors.onError : scheme.onError,
        progress: widget.progress,
        motion: moving ? _motion : null,
      ),
    );
    return SizedBox.square(
      key: ValueKey('record-glyph-${widget.state.name}'),
      dimension: widget.size,
      // A moving glyph redraws alone.
      child: moving ? RepaintBoundary(child: paint) : paint,
    );
  }
}

/// Paints [RecordGlyph] in a 24 box scaled to the canvas (exposed for the
/// tests: what it draws in which colours).
final class RecordGlyphPainter extends CustomPainter {
  /// Creates the painter; [motion] drives the halo's breath or the arc's
  /// turn (null: still).
  new({
    required this.state,
    required this.ink,
    required this.warning,
    required this.error,
    required this.onError,
    this.progress,
    this.motion,
  }) : super(repaint: motion);

  /// The state drawn.
  final RecordGlyphState state;

  /// The colour of the states that do not record.
  final Color ink;

  /// The reconnecting amber.
  final Color warning;

  /// The failed badge.
  final Color error;

  /// The "!" on [error].
  final Color onError;

  /// The join's progress (0–1), or null.
  final double? progress;

  /// The running animation (0–1), or null when still.
  final Animation<double>? motion;

  /// The halo's opacity at rest (and while the system asks for less
  /// motion); it breathes between 15 % and 45 %.
  static const double haloRest = 0.3;
  static const double _haloLow = 0.15;
  static const double _haloHigh = 0.45;

  /// Where the clock and the "!" sit (in the 24 box).
  static const Offset _badge = Offset(18.8, 18.8);
  static const Offset _centre = Offset(12, 12);

  /// The colours this state paints with: what the tests read.
  List<Color> get colors => switch (state) {
    RecordGlyphState.idle ||
    RecordGlyphState.waiting ||
    RecordGlyphState.preparing ||
    RecordGlyphState.processing => [ink],
    RecordGlyphState.recording => const [LiveSemanticColors.recording, LiveSemanticColors.onRecording],
    RecordGlyphState.reconnecting => [warning],
    RecordGlyphState.failed => [ink, error, onError],
  };

  /// The halo's opacity now.
  double get haloOpacity {
    final value = motion?.value;
    if (value == null) return haloRest;
    return _haloLow + (_haloHigh - _haloLow) * Curves.easeInOut.transform(value);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    // Strokes stay at least 1.5 logical pixels in a small glyph (the marks
    // on the picture are 14).
    final stroke = math.max(2, 1.5 / scale).toDouble();
    canvas
      ..save()
      ..scale(scale);
    Paint line(Color color, [double width = 2]) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color
      ..isAntiAlias = true;
    Paint fill(Color color) => Paint()..color = color;
    void ring(Color color) => canvas.drawCircle(_centre, 9, line(color, stroke));
    void dot(Color color) => canvas.drawCircle(_centre, 3.5, fill(color));
    final circle = Rect.fromCircle(center: _centre, radius: 9);
    switch (state) {
      case RecordGlyphState.idle:
        ring(ink);
        dot(ink);
      case RecordGlyphState.waiting || RecordGlyphState.failed:
        // The ring and dot with a hole where the badge sits.
        canvas.saveLayer(Offset.zero & const Size.square(24), Paint());
        ring(ink);
        dot(ink);
        canvas
          ..drawCircle(_badge, 6, Paint()..blendMode = BlendMode.clear)
          ..restore();
        if (state == RecordGlyphState.waiting) {
          canvas
            ..drawCircle(_badge, 4.3, line(ink, 1.5))
            ..drawPath(
              Path()
                ..moveTo(_badge.dx, 16.6)
                ..lineTo(_badge.dx, 18.9)
                ..lineTo(_badge.dx + 1.5, 19.9),
              line(ink, 1.4)
                ..strokeCap = StrokeCap.round
                ..strokeJoin = StrokeJoin.round,
            );
        } else {
          canvas
            ..drawCircle(_badge, 5, fill(error))
            ..drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTWH(_badge.dx - 0.75, 15.9, 1.5, 3.5), const Radius.circular(0.75)),
              fill(onError),
            )
            ..drawCircle(Offset(_badge.dx, 21), 0.9, fill(onError));
        }
      case RecordGlyphState.preparing || RecordGlyphState.processing:
        canvas.drawCircle(_centre, 9, line(ink.withValues(alpha: ink.a * 0.28), stroke));
        final arc = line(ink, stroke)..strokeCap = StrokeCap.round;
        final done = state == RecordGlyphState.processing ? progress : null;
        if (done != null) {
          final sweep = done.clamp(0.0, 1.0) * 2 * math.pi;
          if (sweep > 0) canvas.drawArc(circle, -math.pi / 2, sweep, false, arc);
        } else {
          final turn = motion?.value ?? 0.15;
          canvas.drawArc(circle, -math.pi / 2 + turn * 2 * math.pi, math.pi / 2, false, arc);
        }
        dot(ink);
      case RecordGlyphState.recording:
        canvas
          ..drawCircle(_centre, 11, line(LiveSemanticColors.recording.withValues(alpha: haloOpacity)))
          ..drawCircle(_centre, 10, fill(LiveSemanticColors.recording))
          ..drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: _centre, width: 7.5, height: 7.5),
              const Radius.circular(1.8),
            ),
            fill(LiveSemanticColors.onRecording),
          );
      case RecordGlyphState.reconnecting:
        // Eight dashes, 61 % of each eighth.
        final dashes = line(warning, stroke);
        const eighth = math.pi / 4;
        for (var index = 0; index < 8; index++) {
          canvas.drawArc(circle, -math.pi / 2 + index * eighth, eighth * 0.61, false, dashes);
        }
        dot(warning);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(RecordGlyphPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.ink != ink ||
      oldDelegate.warning != warning ||
      oldDelegate.error != error ||
      oldDelegate.onError != onError ||
      oldDelegate.progress != progress ||
      oldDelegate.motion != motion;
}

/// `12:34` (minutes and seconds) under an hour, `1:02:03` from then on.
String formatRecordingTime(Duration elapsed) {
  final total = elapsed.isNegative ? 0 : elapsed.inSeconds;
  final hours = total ~/ 3600;
  final minutes = total ~/ 60 % 60;
  final seconds = total % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:${two(minutes)}:${two(seconds)}' : '${two(minutes)}:${two(seconds)}';
}

/// The mark in the picture's corner while a room's recording is busy
/// (docs/T08/T08b/T08b.3 c7): "● 录制中 12:34" on red while it records,
/// "重连中 12:34" and "合成中 45%" with their glyph on a dark pill
/// otherwise. [compact] keeps the mark and the figure (controls hidden,
/// small windows).
class RecordingBadge extends StatelessWidget {
  /// Creates the mark.
  const new({
    required this.label,
    this.state = RecordGlyphState.recording,
    this.elapsed,
    this.progress,
    this.compact = false,
    super.key,
  }) : assert(
         state == RecordGlyphState.recording ||
             state == RecordGlyphState.reconnecting ||
             state == RecordGlyphState.processing,
         'a mark shows a busy recording',
       );

  /// The word ("录制中", "重连中", "合成中"), shown unless [compact].
  final String label;

  /// Recording, reconnecting or joining.
  final RecordGlyphState state;

  /// How long the recording runs (recording, reconnecting).
  final Duration? elapsed;

  /// The join's progress from 0 to 1 (joining), or null before FFmpeg
  /// reports.
  final double? progress;

  /// Only the mark and the figure.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.labelMedium ?? const TextStyle(fontSize: 12);
    final style = base.copyWith(color: OnVideoColors.foreground, height: 1.2).emphasis.tabular;
    final recording = state == RecordGlyphState.recording;
    final done = progress;
    final figure = state == RecordGlyphState.processing
        ? (done == null ? null : '${(done.clamp(0.0, 1.0) * 100).floor()}%')
        : formatRecordingTime(elapsed ?? Duration.zero);
    final text = [if (!compact) label, ?figure].join(' ');
    return Semantics(
      label: [label, ?figure].join(' '),
      excludeSemantics: true,
      child: DecoratedBox(
        key: ValueKey('recording-badge-${state.name}'),
        decoration: BoxDecoration(
          color: recording ? LiveSemanticColors.recording : OnVideoColors.scrim,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(recording ? 8 : 5, 3, text.isEmpty ? 5 : 8, 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (recording)
                const SizedBox.square(
                  dimension: 7,
                  child: DecoratedBox(
                    decoration: BoxDecoration(shape: BoxShape.circle, color: LiveSemanticColors.onRecording),
                  ),
                )
              else
                RecordGlyph(state: state, size: 14, color: OnVideoColors.foreground, progress: progress, onVideo: true),
              if (text.isNotEmpty) ...[SizedBox(width: recording ? 5 : 4), Text(text, style: style, maxLines: 1)],
            ],
          ),
        ),
      ),
    );
  }
}
