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
  testWidgets('A11.6: a list built again comes back where it was; another id starts at the top', (tester) async {
    var shown = true;
    var id = 'a';
    late StateSetter setOuter;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        // A route gives its pages a PageStorage; here one of its own.
        child: PageStorage(
          bucket: PageStorageBucket(),
          child: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return shown
                  ? KeepScrollPosition(
                      id: id,
                      child: ListView(children: [for (var i = 0; i < 50; i++) SizedBox(height: 50, child: Text('$i'))]),
                    )
                  : const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    double offset() => tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
    final before = offset();
    expect(before, greaterThan(0));

    setOuter(() => shown = false);
    await tester.pump();
    expect(find.byType(ListView), findsNothing);
    setOuter(() => shown = true);
    await tester.pump();
    expect(offset(), before);

    setOuter(() => id = 'b');
    await tester.pump();
    expect(offset(), 0);
  });
}
