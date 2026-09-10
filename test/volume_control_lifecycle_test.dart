import 'package:flutter/gestures.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/services/settings/volume_settings_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/volume_control.dart';

class _Controller implements VideoController {
  _Controller(double value) : currentVolume = value.obs;
  @override
  final RxDouble currentVolume;
  Completer<double?>? reply;
  final writes = <double>[];
  int reads = 0;
  int holdCalls = 0;
  int releaseCalls = 0;
  @override
  Future<double?> volume() {
    reads++;
    return reply?.future ?? Future.value(currentVolume.value);
  }

  @override
  Future<void> setVolume(double value) async {
    writes.add(value);
  }

  @override
  void stopHideController() {
    holdCalls++;
  }

  @override
  void enableController() {
    releaseCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends SettingsService {
  @override
  final vol = _VolumeSettings();
  @override
  // In-memory fixture; no app services or persistent storage.
  // ignore: must_call_super
  void onInit() {}
}

class _VolumeSettings implements VolumeSettingsController {
  @override
  final defaultMobileVolume = 0.5.obs;
  @override
  final defaultDesktopVolume = 0.9.obs;
  @override
  final globalVolumeMute = false.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mount(WidgetTester tester, _Controller controller) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: OverlayVolumeControl(key: const ValueKey('volume'), controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    Get.testMode = true;
    Get.put<SettingsService>(_Settings());
  });
  tearDown(() {
    Get.reset();
    Get.testMode = false;
  });

  testWidgets('replacement volume controller supplies its initial value and later events', (tester) async {
    final old = _Controller(0.2);
    final next = _Controller(0.8);
    await _mount(tester, old);
    await _mount(tester, next);
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
    next.currentVolume.value = 0;
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
  });

  testWidgets('retired volume events never overwrite the replacement widget', (tester) async {
    final old = _Controller(0.2);
    final next = _Controller(0.8);
    await _mount(tester, old);
    await _mount(tester, next);
    old.currentVolume.value = 0;
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
  });

  testWidgets('late initial volume read never overwrites a user mute', (tester) async {
    final controller = _Controller(0.8)..reply = Completer<double?>();
    await _mount(tester, controller);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    controller.reply!.complete(0.8);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
    expect(controller.writes, [0]);
  });

  testWidgets('late retired controller read never overwrites a new room', (tester) async {
    final old = _Controller(0.2)..reply = Completer<double?>();
    final next = _Controller(0.8);
    await _mount(tester, old);
    await _mount(tester, next);
    expect(old.reads, 1);
    old.reply!.complete(0);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
  });

  testWidgets('newer volume event outranks the pending initial read', (tester) async {
    final controller = _Controller(0.2)..reply = Completer<double?>();
    await _mount(tester, controller);
    controller.currentVolume.value = 0.8;
    await tester.pumpAndSettle();
    controller.reply!.complete(0.2);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
  });

  testWidgets('mobile default changes never alter current desktop room volume', (tester) async {
    final controller = _Controller(0.2);
    await _mount(tester, controller);
    SettingsService.to.vol.defaultMobileVolume.value = 0.8;
    await tester.pumpAndSettle();
    expect(controller.writes, isEmpty);
    expect(find.byIcon(Icons.volume_down), findsOneWidget);
  });
  testWidgets('mute and restore use the replacement room value rather than the old room', (tester) async {
    final old = _Controller(0.2);
    final next = _Controller(0.8);
    await _mount(tester, old);
    await _mount(tester, next);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(next.writes, [0, 0.8]);
    expect(old.writes, isEmpty);
  });

  testWidgets('current platform default and global mute still apply once', (tester) async {
    final controller = _Controller(0.2);
    await _mount(tester, controller);
    SettingsService.to.vol.defaultDesktopVolume.value = 0.7;
    await tester.pumpAndSettle();
    SettingsService.to.vol.globalVolumeMute.value = true;
    await tester.pumpAndSettle();
    SettingsService.to.vol.globalVolumeMute.value = false;
    await tester.pumpAndSettle();
    expect(controller.writes, [0.7, 0, 0.7]);
  });

  testWidgets('unmount retires a pending read and every settings subscription', (tester) async {
    final controller = _Controller(0.2)..reply = Completer<double?>();
    await _mount(tester, controller);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.reply!.complete(0.8);
    controller.currentVolume.value = 0.8;
    SettingsService.to.vol.defaultDesktopVolume.value = 0.7;
    await tester.pumpAndSettle();
    expect(controller.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open volume bar releases only its old hover owner on replacement', (tester) async {
    final old = _Controller(0.2);
    final next = _Controller(0.8);
    await _mount(tester, old);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(IconButton)));
    await tester.pumpAndSettle();
    expect(find.text('20%'), findsOneWidget);
    await mouse.moveTo(tester.getCenter(find.text('20%')));
    await tester.pumpAndSettle();
    expect(old.holdCalls, 1);
    await _mount(tester, next);
    expect(find.text('20%'), findsNothing);
    expect(old.releaseCalls, 1);
    expect(next.releaseCalls, 0);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('late read refreshes an already-open bar without writing volume', (tester) async {
    final controller = _Controller(0.2)..reply = Completer<double?>();
    await _mount(tester, controller);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(IconButton)));
    await tester.pumpAndSettle();
    expect(find.text('20%'), findsOneWidget);
    controller.reply!.complete(0.8);
    await tester.pumpAndSettle();
    expect(find.text('80%'), findsOneWidget);
    expect(controller.writes, isEmpty);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('invalid observed values are ignored and finite global values are clamped', (tester) async {
    final controller = _Controller(0.2);
    await _mount(tester, controller);
    controller.currentVolume.value = double.nan;
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.volume_down), findsOneWidget);
    SettingsService.to.vol.defaultDesktopVolume.value = 4;
    await tester.pumpAndSettle();
    expect(controller.writes, [1]);
    expect(tester.takeException(), isNull);
  });
}
