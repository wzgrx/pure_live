import 'package:flutter/material.dart';
import 'package:live_ui/src/theme/live_colors.dart';

/// What [RecordGlyph] shows.
enum RecordGlyphState {
  /// Not recording: a grey ring around a red dot.
  idle,

  /// Recording: a white dot on a red disc with a soft red halo; the dot
  /// blinks unless the system asks for less motion.
  recording,
}

/// The record button's picture (docs/ui/compare/U.2a, change 13), drawn
/// instead of an emoji or a font glyph so the two states read the same on
/// every platform.
class RecordGlyph extends StatefulWidget {
  /// Creates the picture.
  const new({required this.state, this.size = 24, super.key});

  /// Which state.
  final RecordGlyphState state;

  /// The outer size.
  final double size;

  @override
  State<RecordGlyph> createState() => _RecordGlyphState();
}

class _RecordGlyphState extends State<RecordGlyph> with SingleTickerProviderStateMixin {
  AnimationController? _blink;

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
    final animate = widget.state == RecordGlyphState.recording && !MediaQuery.disableAnimationsOf(context);
    if (!animate) {
      _blink?.stop();
      _blink?.value = 1;
      return;
    }
    final blink = _blink ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.25,
      value: 1,
    );
    if (!blink.isAnimating) blink.repeat(reverse: true);
  }

  @override
  void dispose() {
    _blink?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final scheme = Theme.of(context).colorScheme;
    if (widget.state == RecordGlyphState.idle) {
      return SizedBox.square(
        key: const ValueKey('record-glyph-idle'),
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: scheme.onSurfaceVariant, width: size / 12),
          ),
          child: Center(
            child: SizedBox.square(
              dimension: size * 0.42,
              child: const DecoratedBox(
                decoration: BoxDecoration(shape: BoxShape.circle, color: LiveSemanticColors.recording),
              ),
            ),
          ),
        ),
      );
    }
    final dot = SizedBox.square(
      dimension: size * 0.36,
      child: const DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, color: LiveSemanticColors.onRecording),
      ),
    );
    final blink = _blink;
    return SizedBox.square(
      key: const ValueKey('record-glyph-recording'),
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: LiveSemanticColors.recording,
          border: Border.all(color: LiveSemanticColors.recordingHalo, width: size / 8, strokeAlign: 1),
        ),
        child: Center(
          child: blink == null || !blink.isAnimating
              ? dot
              : RepaintBoundary(
                  child: FadeTransition(opacity: blink, child: dot),
                ),
        ),
      ),
    );
  }
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

/// The "● 录制中 12:34" mark in the picture's corner while the room records;
/// [compact] keeps only the dot and the time (controls hidden, small
/// windows).
class RecordingBadge extends StatelessWidget {
  /// Creates the mark.
  const new({required this.elapsed, required this.label, this.compact = false, super.key});

  /// How long the recording runs.
  final Duration elapsed;

  /// The word ("录制中"), shown unless [compact].
  final String label;

  /// Only the dot and the time.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.labelMedium ?? const TextStyle(fontSize: 12);
    final style = base.copyWith(color: LiveSemanticColors.onRecording, height: 1.2).emphasis.tabular;
    final time = formatRecordingTime(elapsed);
    return Semantics(
      label: '$label $time',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: LiveSemanticColors.recording,
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 7,
                child: DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: LiveSemanticColors.onRecording),
                ),
              ),
              const SizedBox(width: 5),
              Text(compact ? time : '$label $time', style: style, maxLines: 1),
            ],
          ),
        ),
      ),
    );
  }
}
