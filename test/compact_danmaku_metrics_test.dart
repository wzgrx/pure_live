import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/utils/compact_danmaku_metrics.dart';

void main() {
  test('compact metrics scale distance and text from the same reference width', () {
    final metrics = CompactDanmakuMetrics.resolve(
      width: 280,
      autoScale: true,
      configuredFontSize: 12,
      configuredSpeed: 120,
    );

    expect(metrics.scale, closeTo(0.8, 0.0001));
    expect(metrics.fontSize, closeTo(9.6, 0.0001));
    expect(metrics.baseSpeed, closeTo(96, 0.0001));
    expect(metrics.trackHeight, closeTo(19.6, 0.0001));
    expect(metrics.emojiSize, 14);
    expect(metrics.overlapSafeGap, 16);
  });

  test('compact metrics keep lane allocation and painting on one track height', () {
    for (final fontSize in <double>[8, 12, 18, 24]) {
      final metrics = CompactDanmakuMetrics.resolve(
        width: 350,
        autoScale: false,
        configuredFontSize: fontSize,
        configuredSpeed: 90,
      );

      expect(metrics.trackHeight, greaterThanOrEqualTo(metrics.fontSize + 10));
      expect(metrics.trackHeight, inInclusiveRange(18, 44));
    }
  });

  test('compact metrics bound tiny widths and sanitize an unbounded width', () {
    final tiny = CompactDanmakuMetrics.resolve(
      width: 40,
      autoScale: true,
      configuredFontSize: 20,
      configuredSpeed: 100,
    );
    final unbounded = CompactDanmakuMetrics.resolve(
      width: double.infinity,
      autoScale: true,
      configuredFontSize: 20,
      configuredSpeed: 100,
    );

    expect(tiny.scale, 0.65);
    expect(tiny.fontSize, 13);
    expect(tiny.baseSpeed, 65);
    expect(unbounded.scale, 1);
    expect(unbounded.fontSize, 20);
    expect(unbounded.baseSpeed, 100);
  });

  test('compact typography carries the global outline into PiP', () {
    final enabled = CompactDanmakuTypography.resolve(
      configuredFontWeight: 800,
      configuredFontFamily: 'custom-family',
      showStroke: true,
      configuredStrokeWidth: 3,
    );
    final zeroWidth = CompactDanmakuTypography.resolve(
      configuredFontWeight: 500,
      configuredFontFamily: 'Default',
      showStroke: true,
      configuredStrokeWidth: 0,
    );

    expect(enabled.fontWeight, 800);
    expect(enabled.fontFamily, 'custom-family');
    expect(enabled.showStroke, isTrue);
    expect(enabled.strokeWidth, 3);
    expect(zeroWidth.showStroke, isFalse);
  });
}
