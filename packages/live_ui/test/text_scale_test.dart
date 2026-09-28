import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

/// Android 14's non-linear font scaling in miniature: small fonts get the
/// whole factor, large ones less.
final class _NonLinear extends TextScaler {
  const new();

  @override
  double scale(double fontSize) => fontSize * (fontSize < 20 ? 2 : 1.5);

  @override
  double get textScaleFactor => 2;
}

void main() {
  group('CombinedTextScaler (principles §2.3)', () {
    test('multiplies the system scale by the in-app size', () {
      const scaler = CombinedTextScaler(TextScaler.linear(1.5), 1.3);
      expect(scaler.scale(14), closeTo(27.3, 1e-9));
    });

    test('never makes a font more than twice its size', () {
      // Before: TextScaler.linear(2.0 × 1.3) made a 14 sp font 36.4 sp.
      const scaler = CombinedTextScaler(TextScaler.linear(2), 1.3);
      expect(scaler.scale(14), 28);
      expect(scaler.scale(22), 44);
    });

    test("keeps the system's non-linear curve instead of flattening it", () {
      // Before: TextScaler.linear(system.scale(1) × 1.1) grew a 30 sp title
      // by 2.2× like body text (66 sp); the system only asks for 1.5×.
      const scaler = CombinedTextScaler(_NonLinear(), 1.1);
      expect(scaler.scale(30), closeTo(49.5, 1e-9));
      expect(scaler.scale(14), 28, reason: 'small text reaches the cap first');
    });

    test('clamps like any scaler, for text over video', () {
      const scaler = CombinedTextScaler(TextScaler.linear(1.5), 1.3);
      expect(scaler.clamp(maxScaleFactor: TextScale.onVideo).scale(10), 13);
      expect(scaler.clamp(maxScaleFactor: TextScale.onVideo).scale(100), closeTo(130, 1e-9));
    });
  });

  testWidgets('OnVideoTextScale holds text over the picture at 1.3×', (tester) async {
    late double inside;
    late double outside;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: CombinedTextScaler(TextScaler.linear(1.5), 1.3)),
        child: Builder(
          builder: (context) {
            outside = MediaQuery.textScalerOf(context).scale(10);
            return OnVideoTextScale(
              child: Builder(
                builder: (context) {
                  inside = MediaQuery.textScalerOf(context).scale(10);
                  return const SizedBox();
                },
              ),
            );
          },
        ),
      ),
    );
    expect(outside, closeTo(19.5, 1e-9));
    expect(inside, closeTo(13, 1e-9));
  });

  group('cards at twice the text size', () {
    Widget host(Widget child) => MediaQuery(
      data: const MediaQueryData(textScaler: CombinedTextScaler(TextScaler.linear(1.5), 1.3)),
      child: MaterialApp(
        theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
        home: Scaffold(
          body: Center(child: SizedBox(width: 180, child: child)),
        ),
      ),
    );

    test('a compact card takes two lines from 1.5× text', () {
      expect(CardDensity.compact.shownAt(const TextScaler.linear(1.3)), CardDensity.compact);
      expect(CardDensity.compact.shownAt(const TextScaler.linear(1.5)), CardDensity.standard);
      expect(CardDensity.standard.shownAt(const TextScaler.linear(2)), CardDensity.standard);
    });

    testWidgets('the compact title is its own line, not an ellipsis after the name', (tester) async {
      await tester.pumpWidget(
        host(
          const RoomCardView(
            platformId: 'douyu',
            anchorName: '北岛看海',
            title: '周末深夜档',
            isLive: true,
            density: CardDensity.compact,
          ),
        ),
      );
      // One line would be "北岛看海 · 周末深夜档" in a single rich text.
      expect(find.text('北岛看海'), findsOneWidget);
      expect(find.text('周末深夜档'), findsOneWidget);
    });

    testWidgets('the badges on the cover grow 1.3×, the name below 2×', (tester) async {
      await tester.pumpWidget(
        host(
          const RoomCardView(
            platformId: 'douyu',
            anchorName: '主播',
            title: '标题',
            isLive: true,
            audience: '1.2万',
          ),
        ),
      );
      double scaleOf(Finder text) => MediaQuery.textScalerOf(tester.element(text)).scale(10) / 10;
      expect(scaleOf(find.text('1.2万')), closeTo(1.3, 1e-9));
      expect(scaleOf(find.text('直播')), closeTo(1.3, 1e-9));
      expect(scaleOf(find.text('主播')), closeTo(1.95, 1e-9));
    });
  });
}
