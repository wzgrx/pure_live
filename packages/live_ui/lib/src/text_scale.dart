import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Text scaling limits of spec/design/principles.md §2.3.
abstract final class TextScale {
  /// The in-app text size, smallest.
  static const double appMin = 0.85;

  /// The in-app text size, largest.
  static const double appMax = 1.3;

  /// The system size times the in-app size never makes a font larger than
  /// this multiple of itself.
  static const double max = 2;

  /// Text over the picture (the player's controls, badges on covers, labels
  /// in multiview cells and the mini window) grows at most this much, so it
  /// never hides the picture.
  static const double onVideo = 1.3;
}

/// The system's text scaler times the in-app text size, capped at
/// [TextScale.max] times each font size (principles §2.3).
///
/// The system scaler is kept as it is, so Android 14's non-linear scaling
/// (large fonts grow less than small ones) survives the in-app factor: a
/// font of size s becomes `min(system.scale(s) × factor, max × s)`.
@immutable
final class CombinedTextScaler extends TextScaler {
  /// Combines [system] with the in-app [factor].
  const new(this.system, this.factor, {this.maxScale = TextScale.max})
    : assert(factor > 0, 'the in-app size is positive'),
      assert(maxScale > 0, 'the cap is positive');

  /// The platform's scaler.
  final TextScaler system;

  /// The in-app text size.
  final double factor;

  /// The cap as a multiple of the font size.
  final double maxScale;

  @override
  double scale(double fontSize) => math.min(system.scale(fontSize) * factor, maxScale * fontSize);

  // The framework still reads the linear estimate in a few places.
  @override
  double get textScaleFactor => math.min(system.scale(14) * factor / 14, maxScale);

  @override
  bool operator ==(Object other) =>
      other is CombinedTextScaler && other.system == system && other.factor == factor && other.maxScale == maxScale;

  @override
  int get hashCode => Object.hash(system, factor, maxScale);

  @override
  String toString() => 'CombinedTextScaler($system × $factor, ≤ $maxScale×)';
}

/// Limits the text below to [TextScale.onVideo]: the controls and labels
/// drawn over video (principles §2.3).
class OnVideoTextScale extends StatelessWidget {
  /// Clamps [child]'s text scale.
  const new({required this.child, super.key});

  /// The overlay.
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      MediaQuery.withClampedTextScaling(maxScaleFactor: TextScale.onVideo, child: child);
}
