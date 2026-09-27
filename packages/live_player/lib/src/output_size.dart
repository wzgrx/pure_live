import 'dart:math' as math;
import 'dart:ui';

/// How the picture fills its box.
enum VideoFit {
  /// Whole picture visible, letterboxed.
  contain,

  /// Box filled, picture cropped.
  cover,

  /// Box filled, picture stretched.
  fill,
}

/// The native output size for a viewport (PERF-1): the smallest size that
/// covers the visible physical viewport, keeping the source aspect ratio, not
/// larger than the source, with even width and height. An unknown source is
/// treated as 1920×1080.
Size videoOutputSize({
  required Size viewport,
  required double pixelRatio,
  required VideoFit fit,
  int? sourceWidth,
  int? sourceHeight,
}) {
  final known = (sourceWidth ?? 0) > 0 && (sourceHeight ?? 0) > 0;
  final width = known ? sourceWidth!.toDouble() : 1920.0;
  final height = known ? sourceHeight!.toDouble() : 1080.0;
  final physicalWidth = viewport.width * pixelRatio;
  final physicalHeight = viewport.height * pixelRatio;
  if (physicalWidth <= 0 || physicalHeight <= 0) return Size.zero;
  final scaleX = physicalWidth / width;
  final scaleY = physicalHeight / height;
  final scale = math.min(1, fit == VideoFit.contain ? math.min(scaleX, scaleY) : math.max(scaleX, scaleY));
  int even(double value) => math.max(2, (value / 2).ceil() * 2);
  return Size(even(width * scale).toDouble(), even(height * scale).toDouble());
}
