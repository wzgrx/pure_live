import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/shared/panels/side_panel.dart';

import '../support.dart';

// docs/4.0.x/tasks/P03.md c3 (research 2026-10-02 S2): the room panel's
// header pulled down follows the finger, and when let go a spring takes it
// on at the finger's speed, out of sight and closed or back to its place.
// On the K90 (400 × 869 dp at 3×) at 120 Hz, the panel under a 225 dp
// picture as in portrait.

const _frame = Duration(microseconds: 8333);
const double _frameSeconds = 8333 / 1e6;

/// The panel shown; false once it closed.
Future<ValueNotifier<bool>> _panel(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2607);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final open = ValueNotifier(true);
  addTearDown(open.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: const LiveTheme().light,
      home: Scaffold(
        body: Column(
          children: [
            const SizedBox(height: 225),
            Expanded(
              child: ClipRect(
                child: ValueListenableBuilder(
                  valueListenable: open,
                  builder: (context, shown, _) => shown
                      ? RoomSidePanel(
                          title: '录制',
                          dragToClose: true,
                          onClose: () => open.value = false,
                          child: ListView(children: [for (var i = 0; i < 20; i++) ListTile(title: Text('$i'))]),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  return open;
}

final Finder _sheet = find.byKey(const ValueKey('room-panel'));

double _top(WidgetTester tester) => tester.getTopLeft(_sheet).dy;

/// The header pulled by [moves], one a 120 Hz frame, and let go; then
/// frames until the panel rests or closes. Where its top was on the frames
/// from the last move on, and how long it took after the finger lifted.
Future<({List<double> tops, double seconds})> _pull(WidgetTester tester, Iterable<Offset> moves) async {
  final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('room-panel-title'))));
  var time = Duration.zero;
  var tops = <double>[];
  for (final move in moves) {
    time += _frame;
    await gesture.moveBy(move, timeStamp: time);
    await tester.pump(_frame);
    tops = [if (tops.isNotEmpty) tops.last, _top(tester)];
  }
  await gesture.up(timeStamp: time);
  var frames = 0;
  while (frames < 200) {
    await tester.pump(_frame);
    frames++;
    if (_sheet.evaluate().isEmpty) break;
    final top = _top(tester);
    tops.add(top);
    if (!tester.binding.hasScheduledFrame) break;
  }
  return (tops: tops, seconds: frames * _frameSeconds);
}

/// The first frame's movement after the finger lifted over the last one's
/// before.
double _carried(List<double> tops) => (tops[2] - tops[1]) / (tops[1] - tops[0]);

void main() {
  setUpAll(loadStrings);

  testWidgets('a fling down carries on at its speed and closes the panel within 350 ms', (tester) async {
    final open = await _panel(tester);
    final rest = _top(tester);
    // 3000 dp/s.
    final pull = await _pull(tester, List.filled(8, const Offset(0, 25)));
    expect(_carried(pull.tops), inInclusiveRange(0.8, 1.25));
    for (var i = 1; i < pull.tops.length; i++) {
      expect(pull.tops[i], greaterThan(pull.tops[i - 1]));
    }
    expect(open.value, isFalse);
    expect(pull.seconds, lessThanOrEqualTo(0.35));
    // It left out of sight before it closed.
    expect(pull.tops.last, greaterThanOrEqualTo(rest + 644 - 1));
  });

  testWidgets('pulled past 72 dp and let go slowly, it still closes without a stop', (tester) async {
    final open = await _panel(tester);
    // 600 dp/s, under the 700 of a fling.
    final pull = await _pull(tester, List.filled(20, const Offset(0, 5)));
    expect(_carried(pull.tops), greaterThanOrEqualTo(0.8));
    expect(open.value, isFalse);
    expect(pull.seconds, lessThanOrEqualTo(0.35));
  });

  testWidgets('a short pull springs back without jumping', (tester) async {
    final open = await _panel(tester);
    final rest = _top(tester);
    final pull = await _pull(tester, List.filled(10, const Offset(0, 3)));
    // It goes on the finger's way a little, slowing; not back in one frame.
    final first = pull.tops[2] - pull.tops[1];
    expect(first, inInclusiveRange(0, pull.tops[1] - pull.tops[0]));
    expect(open.value, isTrue);
    expect(pull.tops.last, rest);
    expect(pull.seconds, lessThanOrEqualTo(0.35));
    for (final top in pull.tops) {
      expect(top, greaterThanOrEqualTo(rest));
    }
  });

  testWidgets('a fling back up keeps it open, however far it was pulled', (tester) async {
    final open = await _panel(tester);
    final rest = _top(tester);
    // 300 dp down, then 200 back up at 2000 dp/s: 100 dp pulled when let go.
    final pull = await _pull(tester, [
      ...List.filled(30, const Offset(0, 10)),
      ...List.filled(12, const Offset(0, -200 / 12)),
    ]);
    expect(pull.tops[1] - rest, greaterThan(72));
    expect(_carried(pull.tops), inInclusiveRange(0.8, 1.25));
    expect(open.value, isTrue);
    expect(pull.tops.last, rest);
    expect(pull.seconds, lessThanOrEqualTo(0.35));
    for (final top in pull.tops) {
      expect(top, greaterThanOrEqualTo(rest));
    }
  });

  testWidgets('it follows the finger all the way down', (tester) async {
    await _panel(tester);
    final rest = _top(tester);
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('room-panel-title'))));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    var last = _top(tester);
    for (var i = 0; i < 25; i++) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump();
      // One for one.
      expect(_top(tester) - last, closeTo(20, 0.01));
      last = _top(tester);
    }
    // Further than the 400 dp the old panel stopped at.
    expect(last - rest, greaterThan(500));
    await gesture.moveBy(const Offset(0, -600));
    await tester.pump();
    expect(_top(tester), rest);
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
