import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

// A04.1 stage 2 (docs/A-界面设计/A04-尺寸和适配/A04.1-尺寸和字号适配; research
// V03.2 §3.3 D3): the system's text size times the app's "文字大小", at most
// twice as large together (both at 2× once made about 4×).

/// A system curve that grows small text more than large text (Android 14's
/// non-linear font scaling does so).
final class _Curve extends TextScaler {
  const new();

  @override
  double scale(double fontSize) => fontSize + 10;

  @override
  double get textScaleFactor => 1.5;

  @override
  bool operator ==(Object other) => other is _Curve;

  @override
  int get hashCode => 0;
}

void main() {
  test('the system size times the app size, at most twice as large together', () {
    const twice = TextScaler.linear(2);
    expect(appTextScaleLimit, 2);
    expect(const AppTextScaler(twice, 2).scale(14), 28);
    expect(const AppTextScaler(twice, 2).textScaleFactor, 2);
    expect(const AppTextScaler(TextScaler.linear(1.5), 2).scale(20), 40);
    // Below the limit both still count, and the app's 50 % still shrinks.
    expect(const AppTextScaler(TextScaler.linear(1.3), 1.5).scale(10), closeTo(19.5, 1e-9));
    expect(const AppTextScaler(TextScaler.linear(1.3), 1).scale(14), const TextScaler.linear(1.3).scale(14));
    expect(const AppTextScaler(TextScaler.linear(2), 0.5).scale(14), 14);
    expect(const AppTextScaler(TextScaler.noScaling, 0.5).scale(20), 10);
    // The limit is part of the value.
    expect(const AppTextScaler(twice, 2), isNot(const AppTextScaler(twice, 2, maxScale: 3)));
  });

  test('a non-linear system curve is kept under the limit and cut at it', () {
    const scaler = AppTextScaler(_Curve(), 1.5);
    for (final size in [10.0, 14.0, 20.0, 30.0, 40.0, 60.0]) {
      expect(scaler.scale(size), math.min((size + 10) * 1.5, size * 2), reason: '$size');
    }
    // Large text keeps the curve: 40 → 75, not 80.
    expect(scaler.scale(40), 75);
    expect(scaler.textScaleFactor, 2);
  });

  testWidgets('a clamp below it (the picture controls: 1.3) still holds', (tester) async {
    late TextScaler scaler;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: AppTextScaler(TextScaler.linear(2), 2)),
        child: Builder(
          builder: (context) {
            scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(scaler.scale(10), closeTo(13, 1e-9));
  });
}
