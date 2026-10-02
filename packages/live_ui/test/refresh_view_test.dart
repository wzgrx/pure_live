import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

// docs/4.0.x/tasks/P02.md: the refreshable lists feel like 3.x's
// (easy_refresh 3.5.1's `_ERScrollPhysics` and `ClassicHeader`), on the
// K90's screen (400 × 869 dp at 3×) at 120 Hz.

const _frame = Duration(microseconds: 8333);

void _k90(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2607);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Widget _app(Widget body) => MaterialApp(
  theme: const LiveTheme().light,
  home: Scaffold(body: body),
);

Widget _refreshList({
  required Future<Object?> Function() onRefresh,
  bool stopAtEnd = false,
  int count = 200,
  GlobalKey<AppRefreshViewState>? key,
}) => _app(
  AppRefreshView(
    key: key,
    onRefresh: onRefresh,
    stopAtEnd: stopAtEnd,
    builder: (context, physics) =>
        ListView.builder(physics: physics, itemCount: count, itemExtent: 100, itemBuilder: (_, i) => Text('row $i')),
  ),
);

ScrollPosition _position(WidgetTester tester) => tester.state<ScrollableState>(find.byType(Scrollable).first).position;

/// Lets the list go at [velocity] dp/s and pumps 120 Hz frames until it
/// stops: how far it went, how long it took, and its lowest and highest
/// offsets on the way.
Future<({double distance, double seconds, double low, double high})> _glide(
  WidgetTester tester,
  double velocity,
) async {
  final position = _position(tester);
  final start = position.pixels;
  var low = start;
  var high = start;
  (position as ScrollPositionWithSingleContext).goBallistic(velocity);
  var frames = 0;
  while (position.isScrollingNotifier.value && frames < 2000) {
    await tester.pump(_frame);
    frames++;
    low = math.min(low, position.pixels);
    high = math.max(high, position.pixels);
  }
  return (distance: position.pixels - start, seconds: frames * _frame.inMicroseconds / 1e6, low: low, high: high);
}

/// Pumps 120 Hz frames until the list rests; how long that took.
Future<Duration> _settle(WidgetTester tester) async {
  var frames = 0;
  while (_position(tester).isScrollingNotifier.value && frames < 2000) {
    await tester.pump(_frame);
    frames++;
  }
  return _frame * frames;
}

/// Pulls the list down by [finger] dp in 5 dp steps, one per frame; the
/// header's offset after every 25 dp.
Future<(TestGesture, List<double>)> _pull(WidgetTester tester, double finger) async {
  final gesture = await tester.startGesture(const Offset(200, 300));
  final offsets = <double>[];
  for (var moved = 5.0; moved <= finger; moved += 5) {
    await gesture.moveBy(const Offset(0, 5));
    await tester.pump(_frame);
    if (moved % 25 == 0) offsets.add(-_position(tester).pixels);
  }
  return (gesture, offsets);
}

void main() {
  // Research 2026-10-02 §2.2, v3 column: the distance is the limit
  // v / ln(1 / 0.135) of iOS's deceleration, the time when the speed falls
  // under Flutter's stop speed (20 / dpr = 6.67 dp/s at 3×).
  const table = {500: (250.0, 2.2), 3000: (1498.0, 3.0), 6000: (2996.0, 3.4)};
  // easy_refresh 3.5.1 as 3.x set it up, measured the same way on the same
  // Flutter (3.47.5): docs/4.0.x/records/P02.md.
  const v3 = {500: (246.38, 2.167), 1000: (496.09, 2.517), 3000: (1494.86, 3.067), 6000: (2992.97, 3.408)};

  testWidgets('a fling glides like 3.x: 500, 3000 and 6000 dp/s', (tester) async {
    _k90(tester);
    await tester.pumpWidget(_refreshList(onRefresh: () async => null));
    const stopSpeed = 20 / 3;
    final drag = math.log(1 / 0.135);
    for (final MapEntry(key: speed, value: (distance, seconds)) in v3.entries) {
      final velocity = speed.toDouble();
      _position(tester).jumpTo(8000);
      await tester.pump();
      final glide = await _glide(tester, velocity);
      // The same numbers as 3.x, frame for frame.
      expect(glide.distance, closeTo(distance, 0.01), reason: '$velocity dp/s');
      expect(glide.seconds, closeTo(seconds, 0.001), reason: '$velocity dp/s');
      if (table[speed] case (final limit, final rounded)?) {
        // The list stops (stopSpeed / drag) = 3.33 dp short of the limit.
        expect((glide.distance + stopSpeed / drag - limit).abs() / limit, lessThan(0.01), reason: '$velocity dp/s');
        // The table rounds the time to 0.1 s; the formula's own time.
        final formula = math.log(velocity / stopSpeed) / drag;
        expect((glide.seconds - formula).abs() / formula, lessThan(0.01), reason: '$velocity dp/s');
        expect(glide.seconds, closeTo(rounded, 0.07), reason: '$velocity dp/s');
      }
    }
  });

  testWidgets("other lists keep Android's deceleration (v4 before P02)", (tester) async {
    _k90(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        ListView.builder(
          controller: controller,
          physics: const AlwaysScrollableScrollPhysics(parent: PureLiveScrollPhysics()),
          itemCount: 200,
          itemExtent: 100,
          itemBuilder: (_, i) => Text('row $i'),
        ),
      ),
    );
    // Research §2.2, v4 column.
    const clamping = {500: (58.0, 0.28), 3000: (1309.0, 1.03), 6000: (4361.0, 1.71)};
    for (final MapEntry(key: speed, value: (distance, seconds)) in clamping.entries) {
      final velocity = speed.toDouble();
      controller.jumpTo(8000);
      await tester.pump();
      final glide = await _glide(tester, velocity);
      expect((glide.distance - distance).abs() / distance, lessThan(0.01), reason: '$velocity dp/s');
      expect(glide.seconds, closeTo(seconds, 0.02), reason: '$velocity dp/s');
    }
    // And the stretch at their ends.
    expect(find.byType(StretchingOverscrollIndicator), findsOneWidget);
  });

  testWidgets('no stretch and no glow on a refreshable list', (tester) async {
    _k90(tester);
    await tester.pumpWidget(_refreshList(onRefresh: () async => null));
    expect(find.byType(StretchingOverscrollIndicator), findsNothing);
    expect(find.byType(GlowingOverscrollIndicator), findsNothing);
  });

  testWidgets('the pull gets heavier the further it goes, like 3.x', (tester) async {
    _k90(tester);
    await tester.pumpWidget(_refreshList(onRefresh: () async => null));
    final (gesture, offsets) = await _pull(tester, 300);
    // easy_refresh 3.5.1 on the same screen, every 25 dp of finger.
    const v3 = [12.7, 25.2, 37.3, 49.1, 60.6, 71.7, 82.5, 93.0, 103.3, 113.3, 123.0, 132.5];
    for (final (i, offset) in offsets.indexed) {
      expect(offset, closeTo(v3[i], 0.05), reason: '${(i + 1) * 25} dp');
    }
    for (var i = 1; i < offsets.length; i++) {
      expect(offsets[i], greaterThan(offsets[i - 1]));
      if (i > 1) expect(offsets[i] - offsets[i - 1], lessThan(offsets[i - 1] - offsets[i - 2]));
    }
    // At most 0.52 of the finger (iOS's resistance at the edge).
    expect(offsets.last, lessThan(300 * 0.52));
    await gesture.up();
    await _settle(tester);
  });

  testWidgets('short of the header it springs back without refreshing', (tester) async {
    _k90(tester);
    var calls = 0;
    await tester.pumpWidget(
      _refreshList(
        onRefresh: () async {
          calls++;
          return null;
        },
      ),
    );
    final (gesture, offsets) = await _pull(tester, 120);
    expect(offsets.last, lessThan(AppRefreshView.minTriggerOffset));
    expect(find.text('下拉刷新'), findsOneWidget);
    expect(find.byIcon(AppIcons.refreshPull), findsOneWidget);
    await gesture.up();
    final back = await _settle(tester);
    expect(_position(tester).pixels, 0);
    // 3.x took 642 ms with Flutter's default spring.
    expect(back, lessThanOrEqualTo(const Duration(milliseconds: 400)));
    expect(calls, 0);
  });

  testWidgets('at the header height it arms, holds while refreshing, then closes within 400 ms', (tester) async {
    _k90(tester);
    final done = Completer<Object?>();
    var calls = 0;
    final key = GlobalKey<AppRefreshViewState>();
    await tester.pumpWidget(
      _refreshList(
        key: key,
        onRefresh: () {
          calls++;
          return done.future;
        },
      ),
    );
    // The header's height at the default text size.
    const trigger = AppRefreshView.minTriggerOffset;
    final (gesture, offsets) = await _pull(tester, 160);
    expect(offsets.last, greaterThan(trigger));
    expect(key.currentState!.mode, AppRefreshMode.armed);
    expect(find.text('松开刷新'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    // The arrow turned over.
    final turns = tester.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns;
    expect(turns, 0.5);
    await gesture.up();

    // Settles at the header's height, then refreshes (3.x: 650 ms).
    var settle = Duration.zero;
    while (calls == 0 && settle < const Duration(seconds: 2)) {
      await tester.pump(_frame);
      settle += _frame;
    }
    expect(calls, 1);
    expect(settle, lessThanOrEqualTo(const Duration(milliseconds: 400)));
    expect(_position(tester).pixels, -trigger);
    expect(key.currentState!.mode, AppRefreshMode.refreshing);
    expect(find.text('正在刷新...'), findsOneWidget);
    expect(find.byType(AppStatusView), findsOneWidget);

    // Held at the top while the refresh runs.
    await tester.pump(const Duration(seconds: 2));
    expect(_position(tester).pixels, -trigger);
    expect(find.text('正在刷新...'), findsOneWidget);

    done.complete(null);
    await tester.pump();
    expect(find.text('刷新成功'), findsOneWidget);
    expect(find.byIcon(AppIcons.refreshSucceeded), findsOneWidget);
    expect(find.textContaining(RegExp(r'^上次刷新时间 \d{1,2}:\d{2}$')), findsOneWidget);
    // The result shows for a second, the header still held.
    await tester.pump(const Duration(milliseconds: 990));
    expect(_position(tester).pixels, -trigger);
    await tester.pump(const Duration(milliseconds: 10));
    expect(key.currentState!.mode, AppRefreshMode.closing);
    final close = await _settle(tester);
    expect(_position(tester).pixels, 0);
    expect(key.currentState!.mode, AppRefreshMode.idle);
    // 3.x took about 700 ms.
    expect(close, lessThanOrEqualTo(const Duration(milliseconds: 400)));
    expect(find.byKey(const ValueKey('refresh-header')), findsNothing);
    expect(calls, 1);
  });

  testWidgets('a failed refresh says so, with the reason', (tester) async {
    _k90(tester);
    await tester.pumpWidget(_refreshList(onRefresh: () async => const AppRefreshFailure('网络连接超时')));
    final (gesture, _) = await _pull(tester, 200);
    await gesture.up();
    for (var i = 0; i < 60; i++) {
      await tester.pump(_frame);
    }
    expect(find.text('刷新失败'), findsOneWidget);
    expect(find.text('网络连接超时'), findsOneWidget);
    expect(find.byIcon(AppIcons.refreshFailed), findsOneWidget);
    await tester.pump(AppRefreshView.resultDuration);
    await _settle(tester);
    expect(_position(tester).pixels, 0);
  });

  testWidgets('a fling stops at the top; the end bounces, or stops above a loading footer', (tester) async {
    _k90(tester);
    await tester.pumpWidget(_refreshList(onRefresh: () async => null));
    _position(tester).jumpTo(300);
    await tester.pump();
    var glide = await _glide(tester, -3000);
    // 3.x: the header does not "hit over", the list stops at 0.
    expect(glide.low, 0);
    expect(_position(tester).pixels, 0);
    expect(find.byKey(const ValueKey('refresh-header')), findsNothing);

    final max = _position(tester).maxScrollExtent;
    _position(tester).jumpTo(max - 300);
    await tester.pump();
    glide = await _glide(tester, 3000);
    // Past the end and back (3.x went 58 dp past and took 0.82 s with its
    // softer spring).
    expect(glide.high, greaterThan(max + 20));
    expect(_position(tester).pixels, max);
    expect(glide.seconds, lessThan(0.82));

    await tester.pumpWidget(_refreshList(onRefresh: () async => null, stopAtEnd: true));
    _position(tester).jumpTo(max - 300);
    await tester.pump();
    glide = await _glide(tester, 3000);
    expect(glide.high, max);
    expect(_position(tester).pixels, max);
  });

  testWidgets('a finger pulls past the end and it springs back', (tester) async {
    _k90(tester);
    await tester.pumpWidget(_refreshList(onRefresh: () async => null, stopAtEnd: true));
    final max = _position(tester).maxScrollExtent;
    _position(tester).jumpTo(max);
    await tester.pump();
    final gesture = await tester.startGesture(const Offset(200, 600));
    for (var i = 0; i < 30; i++) {
      await gesture.moveBy(const Offset(0, -5));
      await tester.pump(_frame);
    }
    expect(_position(tester).pixels, greaterThan(max + 30));
    await gesture.up();
    final back = await _settle(tester);
    expect(_position(tester).pixels, max);
    expect(back, lessThanOrEqualTo(const Duration(milliseconds: 400)));
  });

  testWidgets('show() refreshes like a pull (the refresh button)', (tester) async {
    _k90(tester);
    var calls = 0;
    final key = GlobalKey<AppRefreshViewState>();
    await tester.pumpWidget(
      _refreshList(
        key: key,
        onRefresh: () async {
          calls++;
          return null;
        },
      ),
    );
    _position(tester).jumpTo(500);
    await tester.pump();
    unawaited(key.currentState!.show());
    for (var i = 0; i < 90; i++) {
      await tester.pump(_frame);
    }
    expect(calls, 1);
    expect(find.text('刷新成功'), findsOneWidget);
    await tester.pump(AppRefreshView.resultDuration);
    await _settle(tester);
    expect(_position(tester).pixels, 0);
    expect(key.currentState!.mode, AppRefreshMode.idle);
  });

  testWidgets('the header stays put when the refreshed rooms change the list', (tester) async {
    _k90(tester);
    final done = Completer<Object?>();
    var count = 3;
    late StateSetter setCount;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            setCount = setState;
            return AppRefreshView(
              onRefresh: () => done.future,
              builder: (context, physics) => ListView.builder(
                physics: physics,
                itemCount: count,
                itemExtent: 100,
                itemBuilder: (_, i) => Text('row $i'),
              ),
            );
          },
        ),
      ),
    );
    final (gesture, _) = await _pull(tester, 200);
    await gesture.up();
    for (var i = 0; i < 60; i++) {
      await tester.pump(_frame);
    }
    expect(_position(tester).pixels, -AppRefreshView.minTriggerOffset);
    setCount(() => count = 40);
    await tester.pump();
    await tester.pump(_frame);
    expect(_position(tester).pixels, -AppRefreshView.minTriggerOffset);
    expect(find.text('正在刷新...'), findsOneWidget);
    done.complete(null);
    await tester.pump();
    await tester.pump(AppRefreshView.resultDuration);
    await _settle(tester);
    expect(_position(tester).pixels, 0);
  });

  testWidgets('a finger on the held header drags the list under it', (tester) async {
    _k90(tester);
    final done = Completer<Object?>();
    await tester.pumpWidget(_refreshList(onRefresh: () => done.future));
    final (gesture, _) = await _pull(tester, 200);
    await gesture.up();
    for (var i = 0; i < 60; i++) {
      await tester.pump(_frame);
    }
    expect(_position(tester).pixels, -AppRefreshView.minTriggerOffset);
    final drag = await tester.startGesture(tester.getCenter(find.text('正在刷新...')));
    for (var i = 0; i < 20; i++) {
      await drag.moveBy(const Offset(0, -10));
      await tester.pump(_frame);
    }
    expect(_position(tester).pixels, greaterThan(0));
    await drag.up();
    done.complete(null);
    await tester.pump(AppRefreshView.resultDuration);
    await _settle(tester);
  });

  testWidgets('larger text makes the header taller, and it still arms at its height', (tester) async {
    _k90(tester);
    final key = GlobalKey<AppRefreshViewState>();
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
            child: AppRefreshView(
              key: key,
              onRefresh: () async => null,
              builder: (context, physics) => ListView.builder(
                physics: physics,
                itemCount: 200,
                itemExtent: 100,
                itemBuilder: (_, i) => Text('row $i'),
              ),
            ),
          ),
        ),
      ),
    );
    final (gesture, offsets) = await _pull(tester, 300);
    final height = tester.getSize(find.byKey(const ValueKey('refresh-header'))).height;
    expect(height, greaterThan(AppRefreshView.minTriggerOffset));
    expect(key.currentState!.mode, offsets.last >= height ? AppRefreshMode.armed : AppRefreshMode.drag);
    await gesture.up();
    for (var i = 0; i < 90; i++) {
      await tester.pump(_frame);
    }
    if (offsets.last >= height) expect(_position(tester).pixels, closeTo(-height, 0.5));
    await tester.pump(AppRefreshView.resultDuration);
    await _settle(tester);
  });
}
