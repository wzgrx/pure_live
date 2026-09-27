import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/live_play/widgets/layout/control_hover_region.dart';

class _Leases {
  final active = <Object>{};
  int acquisitions = 0;
  int releases = 0;
  void enter(Object owner) {
    acquisitions++;
    active.add(owner);
  }

  void exit(Object owner) {
    releases++;
    active.remove(owner);
  }
}

Widget _scene(_Leases leases, {bool enabled = true, Widget? child}) => MaterialApp(
  home: Align(
    alignment: Alignment.topLeft,
    child: ControlHoverRegion(
      enabled: enabled,
      onEnter: leases.enter,
      onExit: leases.exit,
      child: SizedBox(width: 200, height: 56, child: child ?? const ColoredBox(color: Colors.blue)),
    ),
  ),
);

void main() {
  testWidgets('hover lease drains on widget removal without an exit event', (tester) async {
    final leases = _Leases();
    await tester.pumpWidget(_scene(leases));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(20, 20));
    await tester.pump();
    expect(leases.active, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(leases.active, isEmpty);
    expect(leases.releases, 1);
    await mouse.removePointer();
  });

  testWidgets('hiding and revealing with a stationary pointer balances ownership', (tester) async {
    final leases = _Leases();
    await tester.pumpWidget(_scene(leases));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(20, 20));
    await tester.pump();
    await tester.pumpWidget(_scene(leases, enabled: false));
    expect(leases.active, isEmpty);
    await tester.pumpWidget(_scene(leases));
    expect(leases.active, hasLength(1));
    expect(leases.acquisitions, 2);
    await mouse.removePointer();
    await tester.pump();
    expect(leases.releases, 2);
  });

  testWidgets('replacement controller receives its own lease, not the retired exit', (tester) async {
    final old = _Leases();
    final next = _Leases();
    await tester.pumpWidget(_scene(old));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(20, 20));
    await tester.pump();
    await tester.pumpWidget(_scene(next));
    expect(old.active, isEmpty);
    expect(old.releases, 1);
    expect(next.active, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(next.active, isEmpty);
    expect(next.releases, 1);
    await mouse.removePointer();
  });

  testWidgets('multiple pointers share one lease until the last pointer leaves', (tester) async {
    final leases = _Leases();
    await tester.pumpWidget(_scene(leases));
    // Pointer identifiers alone still use device 0 in TestGesture. Model two
    // real devices so MouseTracker receives a balanced lifecycle for each.
    await tester.sendEventToBinding(
      const PointerAddedEvent(device: 1, kind: PointerDeviceKind.mouse, position: Offset(20, 20)),
    );
    await tester.sendEventToBinding(
      const PointerAddedEvent(device: 2, kind: PointerDeviceKind.mouse, position: Offset(60, 20)),
    );
    await tester.pump();
    expect(leases.acquisitions, 1);
    await tester.sendEventToBinding(const PointerRemovedEvent(device: 1, kind: PointerDeviceKind.mouse));
    await tester.pump();
    expect(leases.active, hasLength(1));
    await tester.sendEventToBinding(const PointerRemovedEvent(device: 2, kind: PointerDeviceKind.mouse));
    await tester.pump();
    expect(leases.active, isEmpty);
  });

  testWidgets('hover does not intercept control taps and stable rebuilds do not churn leases', (tester) async {
    final leases = _Leases();
    var taps = 0;
    Widget button() => TextButton(onPressed: () => taps++, child: const Text('audio'));
    await tester.pumpWidget(_scene(leases, child: button()));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(50, 20));
    await tester.pump();
    await tester.pumpWidget(_scene(leases, child: button()));
    await tester.tap(find.text('audio'));
    expect(taps, 1);
    expect(leases.acquisitions, 1);
    expect(leases.releases, 0);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
