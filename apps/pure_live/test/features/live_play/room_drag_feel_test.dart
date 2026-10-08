// docs/A-界面设计/A03-动效和手感/A03.3-直播间拖动手感 (research 2026-10-02 S2, S4, S6, S8): the
// portrait fullscreen's swipe between rooms and the portrait room's
// three-stop panel follow the finger 1:1, carry its speed on when let go,
// resist past their ends, and dragging the panel leaves the picture alone.
// On the K90 (400 × 869 dp at 3×) at 120 Hz, as in side_panel_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/layout/portrait_panel.dart';
import 'package:pure_live/features/live_play/logic/room_layout.dart';
import 'package:pure_live/features/live_play/player/room_swipe.dart';

import '../../support.dart';

const _frame = Duration(microseconds: 8333);
const double _frameSeconds = 8333 / 1e6;
const double _height = 869;

LiveRoom _room(String id) =>
    LiveRoom(platform: SiteIds.bilibili, roomId: id, nick: '主播$id', title: '标题$id', liveStatus: LiveStatus.live);

void _k90(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1200, _height * 3)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// The first frame's movement after the finger lifted over the last one's
/// before; [positions] start with the last two frames of the drag.
double _carried(List<double> positions) => (positions[2] - positions[1]) / (positions[1] - positions[0]);

/// How long after the finger lifted [positions] (the release at index 1, as
/// [_drag] records them) came to stay within 1 % of the way to [target], as
/// research 2026-10-02 §2.3 counts settling.
double _settled(List<double> positions, double target) {
  final near = (positions[1] - target).abs() * 0.01;
  var last = positions.length - 1;
  while (last > 1 && (positions[last - 1] - target).abs() <= near) {
    last--;
  }
  return (last - 1) * _frameSeconds;
}

/// Drags from [from] by [moves], one each [step], and lets go; then 120 Hz
/// frames until nothing moves. [read] is recorded after every frame from
/// the last move on; [afterUp] runs the moment the finger lifts, before a
/// frame.
Future<({List<double> values, double seconds})> _drag(
  WidgetTester tester,
  Offset from,
  Iterable<Offset> moves, {
  required double Function() read,
  Duration step = _frame,
  VoidCallback? afterUp,
}) async {
  final gesture = await tester.startGesture(from);
  var time = Duration.zero;
  var values = <double>[];
  for (final move in moves) {
    time += step;
    await gesture.moveBy(move, timeStamp: time);
    await tester.pump(step);
    values = [if (values.isNotEmpty) values.last, read()];
  }
  await gesture.up(timeStamp: time);
  afterUp?.call();
  var frames = 0;
  while (frames < 200 && tester.binding.hasScheduledFrame) {
    await tester.pump(_frame);
    frames++;
    values.add(read());
  }
  return (values: values, seconds: frames * _frameSeconds);
}

// The swipe between rooms: the stage with a picture feeding the drag, as
// the player's gesture layer does.

final class _Swipe {
  new(this.controller, this.steps);

  final RoomSwipeController controller;
  final List<int> steps;
}

Future<_Swipe> _swipe(WidgetTester tester, {LiveRoom? previous, LiveRoom? next, bool still = false}) async {
  _k90(tester);
  final steps = <int>[];
  final controller = RoomSwipeController(onSwitch: steps.add, vsync: const TestVSync());
  addTearDown(controller.dispose);
  controller.neighbours(previous: previous, next: next);
  await tester.pumpWidget(
    MaterialApp(
      theme: const LiveTheme().light,
      home: MediaQuery(
        data: MediaQueryData(size: const Size(400, _height), devicePixelRatio: 3, disableAnimations: still),
        child: RoomSwipeStage(
          controller: controller,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // The picture takes taps too: a drag starts past the slop.
            onTap: () {},
            onVerticalDragStart: (_) => controller.start(),
            onVerticalDragUpdate: (details) => controller.update(details.delta.dy),
            onVerticalDragEnd: (details) => controller.end(details.primaryVelocity ?? 0),
            child: const ColoredBox(key: ValueKey('picture'), color: Color(0xFF000000)),
          ),
        ),
      ),
    ),
  );
  return _Swipe(controller, steps);
}

/// A fling up of 250 dp at 3000 dp/s, let go; frames are left to the test.
Future<void> _flingUp(WidgetTester tester) async {
  final gesture = await tester.startGesture(const Offset(200, 500));
  var time = Duration.zero;
  for (var i = 0; i < 10; i++) {
    time += _frame;
    await gesture.moveBy(const Offset(0, -25), timeStamp: time);
    await tester.pump(_frame);
  }
  await gesture.up(timeStamp: time);
}

// The three-stop panel over a picture that counts its builds.

int _pictureBuilds = 0;

class _Picture extends StatelessWidget {
  const new({required this.covered});

  final double covered;

  @override
  Widget build(BuildContext context) {
    _pictureBuilds++;
    return ColoredBox(color: Color.fromARGB(255, 0, 0, covered.round() % 255));
  }
}

final class _Panel {
  /// How often the layout asked for the picture.
  int asked = 0;

  /// The stops it told it settled at.
  final List<int> stops = [];

  /// How often it entered the portrait fullscreen.
  int entered = 0;
}

final ({double minimum, double middle, double maximum, double initial}) _stops = portraitPanelStops(
  _height,
  'balanced',
);

Future<_Panel> _panel(WidgetTester tester, {int? stop, bool still = false}) async {
  _k90(tester);
  _pictureBuilds = 0;
  final panel = _Panel();
  await tester.pumpWidget(
    MaterialApp(
      theme: const LiveTheme().light,
      home: MediaQuery(
        data: MediaQueryData(size: const Size(400, _height), devicePixelRatio: 3, disableAnimations: still),
        child: Scaffold(
          body: PortraitPanelLayout(
            player: (covered) {
              panel.asked++;
              return _Picture(covered: covered);
            },
            content: const ColoredBox(color: Color(0xFFFFFFFF)),
            panels: const SizedBox.shrink(),
            mode: 'balanced',
            onFullscreen: () {},
            mobile: true,
            stop: stop,
            onStop: panel.stops.add,
            onPortraitFullscreen: () => panel.entered++,
          ),
        ),
      ),
    ),
  );
  return panel;
}

final Finder _sheet = find.byKey(const ValueKey('live-play-portrait-sheet'));

/// How far the panel's top is above the bottom.
double _sheetHeight(WidgetTester tester) => _height - tester.getTopLeft(_sheet).dy;

Offset _handle(WidgetTester tester) => tester.getCenter(find.byKey(const ValueKey('live-play-portrait-handle')));

void main() {
  setUpAll(loadStrings);

  group('A03.3 logic', () {
    test('the rubber band read back: the drag that shows a place past the edge', () {
      for (final drag in <double>[0, 1, 50, 200, 500, 868, -1, -300]) {
        final shown = AppMotion.rubberBand(drag, _height);
        expect(rubberBandDrag(shown, _height), closeTo(drag, 1e-6), reason: '$drag');
      }
      expect(rubberBandDrag(_height / 3, _height), closeTo(_height, 1e-6), reason: 'the farthest it shows');
      expect(rubberBandDrag(100, 0), 0);
    });

    test('a release settles on the nearest stop; a fling on the next one its way', () {
      const stops = [250.0, 382.0, 591.0];
      expect(releaseStop(300, 0, stops), 250);
      expect(releaseStop(330, 0, stops), 382);
      expect(releaseStop(330, -AppMotion.panelFlingVelocity + 1, stops), 382, reason: 'too slow for a fling');
      expect(releaseStop(300, -AppMotion.panelFlingVelocity, stops), 382, reason: 'flung up');
      expect(releaseStop(390, -2000, stops), 591);
      expect(releaseStop(560, 2000, stops), 382, reason: 'flung down');
      expect(releaseStop(650, -2000, stops), 591, reason: 'over the highest: back to it');
      expect(releaseStop(200, 800, stops), 250, reason: 'under the lowest: back to it');
    });
  });

  group('A03.3 c1: the swipe between rooms', () {
    testWidgets('a fling up switches the moment it lets go, carries on at its speed and lands within 350 ms', (
      tester,
    ) async {
      final swipe = await _swipe(tester, previous: _room('5'), next: _room('7'));
      final seen = <double>[];
      swipe.controller.addListener(() => seen.add(swipe.controller.offset));
      List<int>? atRelease;
      // 3000 dp/s.
      final drag = await _drag(
        tester,
        const Offset(200, 500),
        List.filled(10, const Offset(0, -25)),
        read: () => swipe.controller.offset,
        afterUp: () => atRelease = [...swipe.steps],
      );
      expect(atRelease, [1], reason: 'the next room starts as the finger lifts, not after the motion');
      final moving = drag.values.sublist(0, drag.values.length - 1);
      expect(_carried(moving), inInclusiveRange(0.8, 1.25));
      for (var i = 1; i < moving.length; i++) {
        expect(moving[i], lessThanOrEqualTo(moving[i - 1]), reason: 'one way only');
      }
      expect(seen.reduce((a, b) => a < b ? a : b), -_height, reason: 'up to the next room in place, never past');
      expect(seen.last, 0, reason: 'then the picture is the room switched to');
      expect(drag.values.last, 0);
      expect(drag.seconds, lessThanOrEqualTo(0.35));
      expect(swipe.steps, [1]);
    });

    testWidgets('the room it switches to stays in the space it leaves until it lands', (tester) async {
      final swipe = await _swipe(tester, previous: _room('5'), next: _room('7'));
      final preview = find.byKey(ValueKey('live-play-swipe-preview-${_room('7').identityKey}'));
      await _flingUp(tester);
      // The page moves its list on: the neighbours are those of room 7 now.
      swipe.controller.neighbours(previous: _room('6'), next: _room('5'));
      await tester.pump(_frame);
      expect(preview, findsOneWidget);
      expect(find.byKey(ValueKey('live-play-swipe-preview-${_room('5').identityKey}')), findsNothing);
      await tester.pumpAndSettle();
      expect(preview, findsNothing);
    });

    testWidgets('a short slow drag springs back to its place without passing it, and stays', (tester) async {
      final swipe = await _swipe(tester, previous: _room('5'), next: _room('7'));
      // 100 dp/s for 60 dp (the first 20 take the drag).
      final drag = await _drag(
        tester,
        const Offset(200, 500),
        List.filled(16, const Offset(0, -5)),
        step: const Duration(milliseconds: 50),
        read: () => swipe.controller.offset,
      );
      expect(drag.values[1], closeTo(-60, 0.01));
      for (final value in drag.values) {
        expect(value, lessThanOrEqualTo(0), reason: 'not past its place');
      }
      expect(drag.values.last, 0);
      expect(_settled(drag.values, 0), lessThanOrEqualTo(0.35));
      expect(swipe.steps, isEmpty);
    });

    testWidgets('with less motion it lands at once, switched as it lets go', (tester) async {
      final swipe = await _swipe(tester, previous: _room('5'), next: _room('7'), still: true);
      final drag = await _drag(
        tester,
        const Offset(200, 500),
        List.filled(10, const Offset(0, -25)),
        read: () => swipe.controller.offset,
      );
      expect(swipe.steps, [1]);
      expect(drag.values.last, 0);
      expect(drag.seconds, lessThanOrEqualTo(_frameSeconds));
    });

    testWidgets('a finger catching a switch in flight lands it and drags from there', (tester) async {
      final swipe = await _swipe(tester, previous: _room('5'), next: _room('7'));
      await _flingUp(tester);
      await tester.pump(_frame);
      expect(swipe.controller.offset, lessThan(-200));
      final again = await tester.startGesture(const Offset(200, 500));
      // The first move takes the drag.
      await again.moveBy(const Offset(0, -20));
      await again.moveBy(const Offset(0, -30));
      await tester.pump(_frame);
      expect(swipe.controller.offset, closeTo(-30, 0.01), reason: 'from the room it switched to');
      await again.up();
      await tester.pumpAndSettle();
      expect(swipe.steps, [1]);
    });
  });

  group('A03.3 c2: the end of the list', () {
    testWidgets('with no room below the picture follows more and more heavily, at most a third, and springs back', (
      tester,
    ) async {
      final swipe = await _swipe(tester, previous: _room('5'));
      final offsets = <double>[];
      final gesture = await tester.startGesture(const Offset(200, 700));
      var time = Duration.zero;
      for (var i = 0; i < 40; i++) {
        time += _frame;
        await gesture.moveBy(const Offset(0, -25), timeStamp: time);
        await tester.pump(_frame);
        offsets.add(swipe.controller.offset);
      }
      for (var i = 1; i < offsets.length; i++) {
        expect(offsets[i], lessThanOrEqualTo(offsets[i - 1]), reason: 'monotonic');
        expect(offsets[i], greaterThanOrEqualTo(-_height / 3 - 0.01), reason: 'at most a third');
      }
      // 100 dp past the start (the first move only takes the drag): less.
      expect(offsets[4], inExclusiveRange(-100, -50), reason: 'it resists');
      expect(offsets.last, lessThan(-_height / 3 + 5), reason: 'still follows far out');
      await gesture.up(timeStamp: time);
      var frames = 0;
      final back = <double>[];
      while (frames < 200 && tester.binding.hasScheduledFrame) {
        await tester.pump(_frame);
        frames++;
        back.add(swipe.controller.offset);
      }
      expect(swipe.steps, isEmpty, reason: 'nothing to switch to, however far');
      for (var i = 1; i < back.length; i++) {
        expect(back[i], greaterThanOrEqualTo(back[i - 1]));
        expect(back[i], lessThanOrEqualTo(0), reason: 'not past its place');
      }
      expect(back.last, 0);
      // 1/250/1 from rest comes within 1 % in 0.42 s.
      expect(_settled([offsets[offsets.length - 2], offsets.last, ...back], 0), lessThanOrEqualTo(0.45));
    });

    testWidgets('with no room above, a pull down resists the same way', (tester) async {
      final swipe = await _swipe(tester, next: _room('7'));
      final gesture = await tester.startGesture(const Offset(200, 200));
      for (var i = 0; i < 40; i++) {
        await gesture.moveBy(const Offset(0, 25));
        await tester.pump(_frame);
      }
      expect(swipe.controller.offset, inInclusiveRange(_height / 3 - 5, _height / 3 + 0.01));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(swipe.controller.offset, 0);
      expect(swipe.steps, isEmpty);
    });
  });

  group('A03.3 c1, c3: the three-stop panel', () {
    testWidgets('a fling up carries on at its speed to the next stop, without passing it', (tester) async {
      final panel = await _panel(tester);
      expect(_sheetHeight(tester), closeTo(_stops.middle, 0.5));
      // 2400 dp/s for 100 dp (the first move takes the drag): nearer the
      // middle, but flung up.
      final drag = await _drag(
        tester,
        _handle(tester),
        List.filled(6, const Offset(0, -20)),
        read: () => _sheetHeight(tester),
      );
      expect(drag.values[1], closeTo(_stops.middle + 100, 1));
      expect(_carried(drag.values), inInclusiveRange(0.8, 1.25));
      for (var i = 1; i < drag.values.length; i++) {
        expect(drag.values[i], greaterThanOrEqualTo(drag.values[i - 1]));
        expect(drag.values[i], lessThanOrEqualTo(_stops.maximum + 0.5), reason: 'not past the stop');
      }
      expect(drag.values.last, closeTo(_stops.maximum, 0.5));
      expect(_settled(drag.values, _stops.maximum), lessThanOrEqualTo(0.35));
      expect(panel.stops, [2]);
    });

    testWidgets('a slow pull past half the way settles on the next stop; a short one goes back', (tester) async {
      final panel = await _panel(tester);
      // 100 dp/s for 120 dp (the first 20 take the drag): past half of the
      // 209 to the highest.
      var drag = await _drag(
        tester,
        _handle(tester),
        List.filled(14, const Offset(0, -10)),
        step: const Duration(milliseconds: 100),
        read: () => _sheetHeight(tester),
      );
      expect(drag.values[1], closeTo(_stops.middle + 120, 1));
      expect(drag.values.last, closeTo(_stops.maximum, 0.5));
      expect(_settled(drag.values, _stops.maximum), lessThanOrEqualTo(0.35));
      // 100 dp/s for 50 dp down: back up to the highest.
      drag = await _drag(
        tester,
        _handle(tester),
        List.filled(7, const Offset(0, 10)),
        step: const Duration(milliseconds: 100),
        read: () => _sheetHeight(tester),
      );
      expect(drag.values[1], closeTo(_stops.maximum - 50, 1));
      expect(drag.values.last, closeTo(_stops.maximum, 0.5));
      expect(panel.stops, [2, 2]);
    });

    testWidgets('above the highest stop it resists (at most a third of the room left) and springs back', (
      tester,
    ) async {
      final panel = await _panel(tester, stop: 2);
      final room = _height - _stops.maximum;
      final heights = <double>[];
      final gesture = await tester.startGesture(_handle(tester));
      var time = Duration.zero;
      for (var i = 0; i < 40; i++) {
        time += _frame;
        await gesture.moveBy(const Offset(0, -10), timeStamp: time);
        await tester.pump(_frame);
        heights.add(_sheetHeight(tester));
      }
      for (var i = 1; i < heights.length; i++) {
        expect(heights[i], greaterThanOrEqualTo(heights[i - 1]));
        expect(heights[i], lessThanOrEqualTo(_stops.maximum + room / 3 + 0.01));
      }
      // 90 dp past it: about 64.
      expect(heights[10], inExclusiveRange(_stops.maximum + 20, _stops.maximum + 89), reason: 'it resists');
      await gesture.up(timeStamp: time);
      await tester.pumpAndSettle();
      expect(_sheetHeight(tester), closeTo(_stops.maximum, 0.5));
      expect(panel.stops, [2]);
    });

    testWidgets('a drag only moves the panel: the picture is not built while it moves; once when it settles', (
      tester,
    ) async {
      final panel = await _panel(tester);
      final asked = panel.asked;
      final builds = _pictureBuilds;
      final gesture = await tester.startGesture(_handle(tester));
      var time = Duration.zero;
      // 2 s at 120 Hz, up and down.
      for (var i = 0; i < 240; i++) {
        time += _frame;
        await gesture.moveBy(Offset(0, i.isEven ? -6 : 4), timeStamp: time);
        await tester.pump(_frame);
      }
      expect(_sheetHeight(tester), greaterThan(_stops.middle + 100), reason: 'it moved');
      expect(panel.asked - asked, 0);
      expect(_pictureBuilds - builds, 0);
      await gesture.up(timeStamp: time);
      await tester.pumpAndSettle();
      expect(_pictureBuilds - builds, 1, reason: 'the overlay moves once it settles');
    });

    testWidgets('taking the drag does not jump: each frame moves at most as far as the finger', (tester) async {
      await _panel(tester);
      final start = _sheetHeight(tester);
      final heights = [start];
      final gesture = await tester.startGesture(_handle(tester));
      for (var i = 0; i < 40; i++) {
        await gesture.moveBy(const Offset(0, -1));
        await tester.pump(_frame);
        heights.add(_sheetHeight(tester));
      }
      for (var i = 1; i < heights.length; i++) {
        expect(heights[i] - heights[i - 1], lessThanOrEqualTo(1.0001), reason: 'frame $i');
      }
      expect(heights.last, greaterThan(start + 15), reason: 'it follows once taken');
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets("pulled down past the lowest it slides out at the finger's speed, then enters the fullscreen", (
      tester,
    ) async {
      final panel = await _panel(tester, stop: 0);
      var entered = -1;
      // 3000 dp/s for 175 dp (the first move takes the drag).
      final drag = await _drag(
        tester,
        _handle(tester),
        List.filled(8, const Offset(0, 25)),
        read: () => _sheetHeight(tester),
        afterUp: () => entered = panel.entered,
      );
      expect(entered, 0, reason: 'the slide, not the release, enters');
      expect(_carried(drag.values), inInclusiveRange(0.8, 1.25));
      expect(drag.seconds, lessThanOrEqualTo(0.35));
      await tester.pump();
      expect(panel.entered, 1);
    });

    testWidgets('with less motion it lands on the stop at once', (tester) async {
      await _panel(tester, still: true);
      final drag = await _drag(
        tester,
        _handle(tester),
        List.filled(6, const Offset(0, -20)),
        read: () => _sheetHeight(tester),
      );
      expect(drag.values.last, closeTo(_stops.maximum, 0.5));
      expect(drag.seconds, lessThanOrEqualTo(_frameSeconds));
    });
  });
}
