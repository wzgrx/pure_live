import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

// docs/4.0.x/tasks/P03.md: tab pages turn like Android's ViewPager and
// settle firmly; a drag let go of carries on at the finger's speed. On the
// K90's screen (400 × 869 dp at 3×) at 120 Hz.

const _frame = Duration(microseconds: 8333);
const double _frameSeconds = 8333 / 1e6;

void _k90(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2607);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Three tab pages under [physics], each a list scrolling up and down.
Future<TabController> _pages(WidgetTester tester, ScrollPhysics physics) async {
  final tabs = TabController(length: 3, vsync: tester, animationDuration: pureLiveTabTransitionDuration);
  addTearDown(tabs.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TabBarView(
          controller: tabs,
          physics: physics,
          children: [
            for (var page = 0; page < 3; page++)
              ListView.builder(
                key: PageStorageKey(page),
                itemExtent: 100,
                itemCount: 100,
                itemBuilder: (_, row) => Text('page $page row $row'),
              ),
          ],
        ),
      ),
    ),
  );
  return tabs;
}

/// The pages' own scroll position (not a list's).
ScrollPosition _pagesPosition(WidgetTester tester) => tester
    .state<ScrollableState>(find.descendant(of: find.byType(TabBarView), matching: find.byType(Scrollable)).first)
    .position;

/// Pumps 120 Hz frames from a release until the pages rest: the page shown,
/// when they came within 1 % of a page of where they rest (§2.3's
/// settling, to the frame) and when they stopped.
Future<({int page, double settled, double stopped})> _rest(WidgetTester tester, TabController tabs) async {
  final position = _pagesPosition(tester);
  final offsets = [position.pixels];
  while (position.isScrollingNotifier.value && offsets.length < 600) {
    await tester.pump(_frame);
    offsets.add(position.pixels);
  }
  await tester.pumpAndSettle();
  final width = position.viewportDimension;
  final end = offsets.last;
  var settled = 0;
  for (var i = 0; i < offsets.length; i++) {
    if ((offsets[i] - end).abs() > width * 0.01) settled = i + 1;
  }
  expect(tabs.index, (end / width).round());
  return (page: tabs.index, settled: settled * _frameSeconds, stopped: (offsets.length - 1) * _frameSeconds);
}

/// A finger on the pages making [moves], one a 120 Hz frame (as Android
/// hands them over), then lifting; the rest.
Future<({int page, double settled, double stopped})> _finger(
  WidgetTester tester,
  ScrollPhysics physics,
  Iterable<Offset> moves,
) async {
  final tabs = await _pages(tester, physics);
  final gesture = await tester.startGesture(const Offset(200, 600));
  var time = Duration.zero;
  for (final move in moves) {
    time += _frame;
    await gesture.moveBy(move, timeStamp: time);
    await tester.pump(_frame);
  }
  await gesture.up(timeStamp: time);
  return await _rest(tester, tabs);
}

/// A sideways swipe [distance] dp to the left at [speed] dp/s.
Future<({int page, double settled, double stopped})> _swipe(
  WidgetTester tester,
  ScrollPhysics physics, {
  required double distance,
  required double speed,
}) {
  final step = speed * _frameSeconds;
  return _finger(tester, physics, List.filled((distance / step).round(), Offset(-step, 0)));
}

/// An upward scroll that starts a little sideways (so the pages, not the
/// list, take the finger) and then goes up fast: 24 dp left in four frames,
/// then 24 dp left and 168 dp up in twelve (240 dp/s sideways, 1680 up).
Future<int> _slantedScroll(WidgetTester tester, ScrollPhysics physics) async {
  final moves = [...List.filled(4, const Offset(-6, -1)), ...List.filled(12, const Offset(-2, -14))];
  return (await _finger(tester, physics, moves)).page;
}

void main() {
  const before = PureLiveBoundedScrollPhysics();
  const after = PureLivePageScrollPhysics();

  group('tab pages (S3)', () {
    testWidgets('the pages read the spring and the fling rule through TabBarView', (tester) async {
      await _pages(tester, after);
      final physics = _pagesPosition(tester).physics;
      expect(physics.spring, same(AppMotion.pageSpring));
      expect(physics.minFlingVelocity, 400);
      expect(physics.minFlingDistance, 25);
      // Still bounded, as the tab strip's physics.
      expect(after.applyTo(null), isA<PureLiveBoundedScrollPhysics>());
    });

    testWidgets('300 dp/s does not turn the page; it did before', (tester) async {
      _k90(tester);
      expect((await _swipe(tester, before, distance: 60, speed: 300)).page, 1);
      final result = await _swipe(tester, after, distance: 60, speed: 300);
      expect(result.page, 0);
      expect(result.settled, lessThanOrEqualTo(0.3));
    });

    testWidgets('600 dp/s turns it and settles within 300 ms (500 ms before)', (tester) async {
      _k90(tester);
      final old = await _swipe(tester, before, distance: 60, speed: 600);
      expect(old.page, 1);
      expect(old.settled, greaterThan(0.45));
      final result = await _swipe(tester, after, distance: 60, speed: 600);
      expect(result.page, 1);
      expect(result.settled, lessThanOrEqualTo(0.3));
      expect(result.stopped, lessThan(old.stopped));
    });

    testWidgets('a fast flick shorter than 25 dp does not turn it', (tester) async {
      _k90(tester);
      expect((await _swipe(tester, before, distance: 20, speed: 600)).page, 1);
      expect((await _swipe(tester, after, distance: 20, speed: 600)).page, 0);
    });

    testWidgets('dragged past half it turns without a fling', (tester) async {
      _k90(tester);
      final result = await _swipe(tester, after, distance: 240, speed: 200);
      expect(result.page, 1);
      expect(result.settled, lessThanOrEqualTo(0.3));
    });

    testWidgets('an upward scroll that starts sideways does not turn the page', (tester) async {
      _k90(tester);
      expect(await _slantedScroll(tester, before), 1);
      expect(await _slantedScroll(tester, after), 0);
    });
  });

  group('springs and thresholds (§2.3)', () {
    /// When a spring from [distance] away at rest comes within 1 % of it.
    double settling(SpringDescription spring, {double distance = 100}) {
      final simulation = SpringSimulation(spring, distance, 0, 0);
      var time = 0.0;
      while (simulation.x(time).abs() > distance * 0.01) {
        time += 0.0005;
      }
      return time;
    }

    test('the springs and how long they take', () {
      expect(settling(AppMotion.pageSpring), closeTo(0.27, 0.005));
      expect(settling(AppMotion.panelSpring), closeTo(0.30, 0.005));
      expect(settling(AppMotion.roomSwipeSpring), closeTo(0.33, 0.005));
      // Flutter's default scroll spring, what the pages had.
      expect(settling(SpringDescription.withDampingRatio(mass: 0.5, stiffness: 100, ratio: 1.1)), closeTo(0.57, 0.005));
      for (final spring in [AppMotion.pageSpring, AppMotion.panelSpring, AppMotion.roomSwipeSpring]) {
        expect(spring.mass, 1);
        expect(spring.damping, closeTo(2 * math.sqrt(spring.stiffness), 1e-9));
      }
      expect(AppMotion.refreshSpring, same(AppMotion.panelSpring));
      // A period of 0.4 s.
      expect(2 * math.pi / math.sqrt(AppMotion.overscrollSpring.stiffness), closeTo(0.4, 0.005));
      expect(AppMotion.controlSpring.stiffness, 1400);
      expect(AppMotion.controlSpring.damping, closeTo(0.9 * 2 * math.sqrt(1400), 1e-9));
    });

    test('fling thresholds: 3.x kept, 4.0 own 600 now 700', () {
      expect(AppMotion.panelFlingVelocity, 700);
      expect((AppMotion.panelFullscreenFlingVelocity, AppMotion.panelFullscreenFlingDistance), (900, 28));
      expect((AppMotion.panelRestoreFlingVelocity, AppMotion.panelRestoreFlingDistance), (850, 24));
      expect((AppMotion.roomSwipeFlingVelocity, AppMotion.roomSwipeFlingDistance), (800, 48));
      expect((AppMotion.pageFlingVelocity, AppMotion.pageFlingDistance), (400, 25));
    });

    test('the rubber band grows ever slower and stops at a third', () {
      var last = 0.0;
      var lastStep = double.infinity;
      for (var pulled = 10.0; pulled <= 900; pulled += 10) {
        final moved = AppMotion.rubberBand(pulled, 900);
        expect(moved, greaterThan(last));
        expect(moved - last, lessThanOrEqualTo(lastStep + 1e-9));
        lastStep = moved - last;
        last = moved;
      }
      expect(AppMotion.rubberBand(900, 900), closeTo(300, 1e-9));
      expect(AppMotion.rubberBand(5000, 900), closeTo(300, 1e-9));
      expect(AppMotion.rubberBand(-450, 900), closeTo(-900 * (0.5 - 0.25 + 0.125 / 3), 1e-9));
      expect(AppMotion.rubberBand(10, 0), 0);
    });
  });

  group('a drag let go of (S2)', () {
    test('the spring leaves at the finger speed and never passes its end', () {
      final back = ReleaseSpringSimulation(
        spring: AppMotion.panelSpring,
        start: 60,
        end: 0,
        velocity: -2000,
        tolerance: AppMotion.tolerance(3),
      );
      expect(back.dx(0), -2000);
      var time = 0.0;
      while (!back.isDone(time)) {
        expect(back.x(time), greaterThanOrEqualTo(0));
        time += 0.001;
      }
      expect(back.x(time), 0);
      // A critically damped spring alone would overshoot this throw.
      final free = SpringSimulation(AppMotion.panelSpring, 60, 0, -2000);
      expect(free.x(0.15), lessThan(-1));

      final gentle = ReleaseSpringSimulation(
        spring: AppMotion.panelSpring,
        start: 72,
        end: 0,
        velocity: 0,
        tolerance: AppMotion.tolerance(3),
      );
      time = 0;
      while (!gentle.isDone(time)) {
        time += 0.001;
      }
      expect(time, lessThanOrEqualTo(0.35));
      expect(gentle.x(time), 0);
    });

    test('aimed past its end it stops on reaching it, without the slow tail', () {
      final out = ReleaseSpringSimulation(
        spring: AppMotion.panelSpring,
        start: 100,
        end: 600,
        velocity: 0,
        beyond: 6,
        tolerance: AppMotion.tolerance(3),
      );
      var time = 0.0;
      while (!out.isDone(time)) {
        expect(out.x(time), lessThanOrEqualTo(600));
        time += 0.001;
      }
      expect(out.x(time), 600);
      expect(time, lessThanOrEqualTo(0.3));
    });

    /// Draws a frame (the one showing the finger's last position).
    Future<void> drawFrame(WidgetTester tester) async {
      tester.binding.scheduleFrame();
      await tester.pump(_frame);
    }

    testWidgets('the first frame after the finger lifts moves on', (tester) async {
      Future<double> firstFrame({required bool fromLastFrame}) async {
        final controller = AnimationController.unbounded(vsync: tester, value: 100);
        addTearDown(controller.dispose);
        await drawFrame(tester);
        final simulation = ReleaseSpringSimulation(spring: AppMotion.panelSpring, start: 100, end: 600, velocity: 3000);
        if (fromLastFrame) {
          // One 120 Hz frame since the last, under the 60 Hz cap.
          controller.animateRelease(simulation);
        } else {
          controller.animateWith(simulation);
        }
        await tester.pump(_frame);
        final moved = controller.value - 100;
        controller.stop();
        return moved;
      }

      // A controller started between frames repeats the last one.
      expect(await firstFrame(fromLastFrame: false), 0);
      final moved = await firstFrame(fromLastFrame: true);
      final expected = ReleaseSpringSimulation(
        spring: AppMotion.panelSpring,
        start: 100,
        end: 600,
        velocity: 3000,
      ).x(_frameSeconds);
      expect(moved, closeTo(expected - 100, 0.01));
      // About one frame at the finger's 25 dp a frame.
      expect(moved / 25, inInclusiveRange(0.8, 1.25));
    });

    testWidgets('it catches up by at most a frame after the finger rested', (tester) async {
      final controller = AnimationController.unbounded(vsync: tester, value: 72);
      addTearDown(controller.dispose);
      await drawFrame(tester);
      // Nothing drawn for half a second before the finger lifts.
      await tester.pump(const Duration(milliseconds: 500));
      final simulation = ReleaseSpringSimulation(spring: AppMotion.panelSpring, start: 72, end: 0, velocity: 0);
      // The default cap: one 60 Hz frame.
      controller.animateRelease(simulation);
      await tester.pump(_frame);
      expect(controller.value, closeTo(simulation.x(1 / 60), 1e-6));
      controller.stop();
    });
  });
}
