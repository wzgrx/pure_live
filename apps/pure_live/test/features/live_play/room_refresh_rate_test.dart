import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/live_play/logic/room_refresh_rate.dart';
import 'package:pure_live/platform/display_mode.dart';

import '../../support.dart';
import 'live_play_support.dart';

// docs/ui/compare/U.2i: the display's refresh rate follows the video.

const _rates = [60.0, 90.0, 120.0];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the policy (v4-policy.jpg)', () {
    test('23.976, 29.97 and 59.94 are 24, 30 and 60; whole multiples within 0.5 %', () {
      expect(normalizeFrameRate(23.976), 24);
      expect(normalizeFrameRate(29.97), 30);
      expect(normalizeFrameRate(59.94), 60);
      expect(normalizeFrameRate(27.5), 27.5);
      expect(frameRateMultiples(30, _rates), [60, 90, 120]);
      expect(frameRateMultiples(60, [60, 90, 120, 144]), [60, 120]);
      expect(frameRateMultiples(25, _rates), isEmpty);
      expect(frameRateMultiples(25, [50, 60, 100, 120]), [50, 100]);
    });

    double? rate(String mode, {required bool high, double fps = 30, List<double> supported = _rates}) =>
        playbackRefreshRate(
          playback: PlaybackRefresh(frameRate: fps, mode: mode),
          high: high,
          supported: supported,
        );

    test('power saving: the system picks (the declared frame rate leads it)', () {
      expect(rate('powerSaving', high: false), 0);
    });

    test('balanced: up to 60 at rest, the highest multiple while touching; 50 for 25 frames', () {
      expect(rate('balanced', high: false), 60);
      expect(rate('balanced', high: true), 120);
      expect(rate('balanced', high: false, fps: 25, supported: [50, 60, 100, 120]), 50);
      expect(rate('balanced', high: true, fps: 25, supported: [50, 60, 100, 120]), 100);
    });

    test('performance: 120, not 144, for 60 frames; no multiple keeps 3.x', () {
      expect(rate('performance', high: true, fps: 60, supported: [60, 90, 120, 144]), 120);
      expect(rate('performance', high: true, fps: 25), isNull);
      expect(rate('balanced', high: true, fps: 25), isNull);
    });
  });

  group('the channel', () {
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      DisplayMode.debugAndroid = true;
      DisplayMode.publish(
        DisplayModeInfo.fromMap(const {
          'currentRefreshRate': 60.0,
          'maxRefreshRate': 120.0,
          'supportedRefreshRates': _rates,
        }),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('pure_live/display_mode'),
        (call) async {
          calls.add(call);
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('pure_live/display_mode'),
        null,
      );
      DisplayMode.debugReset();
    });

    test('c2-c4: playing declares the frame rate and asks for a multiple; stopping clears both', () async {
      await DisplayMode.applyHighRefreshRate(high: false);
      expect(calls.last.arguments, {'enabled': false});

      await DisplayMode.setPlayback(const PlaybackRefresh(frameRate: 30, mode: 'balanced'));
      expect(
        [for (final call in calls.skip(1)) '${call.method} ${call.arguments}'],
        ['setVideoFrameRate {fps: 30.0}', 'setHighRefreshRate {enabled: false, refreshRate: 60.0}'],
      );
      // c3: touching asks for the highest multiple, not just the highest.
      await DisplayMode.applyHighRefreshRate(high: true);
      expect(calls.last.arguments, {'enabled': true, 'refreshRate': 120.0});

      await DisplayMode.setPlayback(null);
      expect(
        [for (final call in calls.skip(4)) '${call.method} ${call.arguments}'],
        ['setVideoFrameRate {fps: 0.0}', 'setHighRefreshRate {enabled: true}'],
      );
    });
  });

  group('the room', () {
    testWidgets('c2, c4: the frame rate while it plays; paused, switched off or in the background: nothing', (
      tester,
    ) async {
      final services = (await tester.runAsync(testServices))!;
      final settings = services.store.settings;
      final engine = FakeEngine();
      final session = fakeSession(engine);
      final sent = <PlaybackRefresh?>[];
      final watch = RoomRefreshRate(session: session, settings: settings, apply: (playback) async => sent.add(playback))
        ..start();
      expect(sent, [null]);

      await tester.runAsync(
        () => session.open(
          PlaybackRequest(
            site: SiteIds.bilibili,
            plan: PlaybackPlan.of(LivePlayUrlResolution.lines(const [LivePlayLine('https://a.example/1.flv')])),
          ),
        ),
      );
      expect(sent, [null], reason: 'no frame rate yet');
      engine.emit(const EngineFrameRate(29.97));
      await tester.pump();
      expect(sent.last, const PlaybackRefresh(frameRate: 30, mode: 'powerSaving'));

      await tester.runAsync(() => settings.set(Settings.refreshRateMode, 'balanced'));
      await tester.pump();
      expect(sent.last, const PlaybackRefresh(frameRate: 30, mode: 'balanced'));

      // Picture-in-picture (inactive) keeps it; the background drops it.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(sent.last, isNotNull);
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(sent.last, isNull);
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(sent.last, isNotNull);

      await tester.runAsync(session.togglePlayPause);
      await tester.pump();
      expect(session.state.status, PlaybackStatus.paused);
      expect(sent.last, isNull);
      await tester.runAsync(session.togglePlayPause);
      await tester.pump();
      expect(sent.last, isNotNull);

      await tester.runAsync(() => settings.set(Settings.matchVideoFrameRate, false));
      await tester.pump();
      expect(sent.last, isNull, reason: 'switched off: as 3.x');
      await tester.runAsync(() => settings.set(Settings.matchVideoFrameRate, true));
      await tester.pump();
      final count = sent.length;
      watch.dispose();
      expect(sent.length, count + 1);
      expect(sent.last, isNull, reason: 'leaving the room clears it');

      await tester.runAsync(session.dispose);
      await tester.runAsync(services.close);
    });
  });
}
