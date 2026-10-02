import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/platform/display_mode.dart';

// docs/4.0.x/tasks/P01.md: c3 (the system holds the app at 60 Hz) and c4
// (numbers, never a category; not a game).

const _channel = MethodChannel('pure_live/display_mode');

Map<String, Object> _info(double current) => {
  'currentRefreshRate': current,
  'maxRefreshRate': 120.0,
  'supportedRefreshRates': [60.0, 90.0, 120.0],
};

void main() {
  group('c3: held at 60 Hz', () {
    // What the display runs at; every answer of the activity reports it.
    var current = 60.0;
    final calls = <String>[];

    setUp(() {
      current = 60.0;
      calls.clear();
      DisplayMode.debugAndroid = true;
      DisplayMode.publish(DisplayModeInfo.fromMap(_info(current)));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (
        call,
      ) async {
        calls.add(call.method);
        return _info(current);
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
      DisplayMode.debugReset();
    });

    Future<void> wait(WidgetTester tester, Duration duration) async {
      await tester.pump(duration);
      // The timer's second look at the display answers.
      await tester.pump();
    }

    testWidgets('touching for 3 s at 60 Hz against 120 turns it on; a faster display turns it off', (tester) async {
      await tester.pumpWidget(const SizedBox.expand());
      await DisplayMode.applyHighRefreshRate(high: true);
      final finger = await tester.startGesture(const Offset(20, 20));
      await wait(tester, const Duration(seconds: 2));
      expect(DisplayMode.limited.value, isFalse, reason: 'not 3 s yet');
      await wait(tester, const Duration(seconds: 1));
      expect(DisplayMode.limited.value, isTrue);
      expect(calls, contains('getDisplayModeInfo'), reason: 'read again before saying so');

      // The user raised it in the system settings: the next look sees 120.
      current = 120;
      await wait(tester, const Duration(seconds: 3));
      expect(DisplayMode.limited.value, isFalse);
      await finger.up();
      await wait(tester, const Duration(seconds: 2));
    });

    testWidgets('a report of the display switching turns it off at once', (tester) async {
      await tester.pumpWidget(const SizedBox.expand());
      await DisplayMode.applyHighRefreshRate(high: true);
      final finger = await tester.startGesture(const Offset(20, 20));
      await wait(tester, const Duration(seconds: 3));
      expect(DisplayMode.limited.value, isTrue);
      DisplayMode.publish(DisplayModeInfo.fromMap(_info(120)));
      expect(DisplayMode.limited.value, isFalse);
      await finger.up();
      await wait(tester, const Duration(seconds: 2));
    });

    testWidgets('a still screen may idle down: performance without a touch stays quiet', (tester) async {
      await tester.pumpWidget(const SizedBox.expand());
      await DisplayMode.applyHighRefreshRate(high: true);
      await wait(tester, const Duration(seconds: 5));
      expect(DisplayMode.limited.value, isFalse);
      // A tap counts for 1.5 s after the finger lifts; 3 s are not reached.
      await tester.tap(find.byType(SizedBox));
      await wait(tester, const Duration(seconds: 5));
      expect(DisplayMode.limited.value, isFalse);
    });

    testWidgets('balanced: the high rate released before 3 s, or asking for 60, stays quiet', (tester) async {
      await tester.pumpWidget(const SizedBox.expand());
      await DisplayMode.applyHighRefreshRate(high: true);
      final finger = await tester.startGesture(const Offset(20, 20));
      await wait(tester, const Duration(seconds: 2));
      await DisplayMode.applyHighRefreshRate(high: false);
      await wait(tester, const Duration(seconds: 2));
      expect(DisplayMode.limited.value, isFalse);

      // A 30-frame video at rest in balanced asks for 60.
      await DisplayMode.setPlayback(const PlaybackRefresh(frameRate: 30, mode: 'balanced'));
      await wait(tester, const Duration(seconds: 4));
      expect(DisplayMode.limited.value, isFalse);
      // Touching asks for 120: held at 60, it shows.
      await DisplayMode.applyHighRefreshRate(high: true);
      await wait(tester, const Duration(seconds: 3));
      expect(DisplayMode.limited.value, isTrue);
      await finger.up();
      await wait(tester, const Duration(seconds: 2));
    });
  });

  group('c4: numbers, not a game', () {
    test('the manifests never call the app a game (Android 15 holds games at 60 Hz)', () {
      final manifests = Directory('android/app/src')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('AndroidManifest.xml'))
          .toList();
      expect(manifests, isNotEmpty);
      for (final manifest in manifests) {
        final text = manifest.readAsStringSync();
        expect(text, isNot(contains('appCategory')), reason: manifest.path);
        expect(text, isNot(contains('isGame')), reason: manifest.path);
      }
    });

    test('the activity asks for rates as numbers, never a frame-rate category (HIGH is 90 Hz on the K90)', () {
      final kotlin = Directory('android/app/src/main/kotlin')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.kt'));
      for (final file in kotlin) {
        final text = file.readAsStringSync();
        expect(text, isNot(contains('FRAME_RATE_CATEGORY')), reason: file.path);
        expect(text, isNot(contains('setRequestedFrameRate')), reason: file.path);
        expect(text, isNot(contains('setFrameRateCategory')), reason: file.path);
      }
      final activity = File('android/app/src/main/kotlin/com/mystyle/purelive/MainActivity.kt').readAsStringSync();
      expect(activity, contains('Surface.FRAME_RATE_COMPATIBILITY_FIXED_SOURCE'));
      expect(activity, contains('Surface.FRAME_RATE_COMPATIBILITY_AT_LEAST'));
    });
  });
}
