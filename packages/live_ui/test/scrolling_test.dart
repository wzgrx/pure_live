import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

void main() {
  final metrics = FixedScrollMetrics(
    minScrollExtent: 0,
    maxScrollExtent: 100,
    pixels: 100,
    viewportDimension: 50,
    axisDirection: AxisDirection.down,
    devicePixelRatio: 1,
  );

  test('as a parent or unapplied it keeps the edges: a hard edge on Android, a spring on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    // AlwaysScrollable over the unapplied physics scrolled past the end (M13.1).
    const nested = AlwaysScrollableScrollPhysics(parent: PureLiveScrollPhysics());
    expect(nested.applyBoundaryConditions(metrics, 130), 30);
    expect(const PureLiveScrollPhysics().applyBoundaryConditions(metrics, 130), 30);
    expect(const PureLiveScrollPhysics().applyTo(null), isA<ClampingScrollPhysics>());

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(nested.applyBoundaryConditions(metrics, 130), 0);
    expect(const PureLiveScrollPhysics().applyTo(null), isA<BouncingScrollPhysics>());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a list under it stops at its end', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ListView(
          controller: controller,
          physics: const AlwaysScrollableScrollPhysics(parent: PureLiveScrollPhysics()),
          children: [for (var i = 0; i < 20; i++) SizedBox(height: 50, child: Text('$i'))],
        ),
      ),
    );
    await tester.fling(find.byType(ListView), const Offset(0, -5000), 5000);
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);
  });
}
