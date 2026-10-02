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

// docs/ui/compare/U.2i: the display's refresh rate follows the video;
// revised in 4.0.x by P01 (the README's "4.0.x 修订").

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

    double rate(String mode, {required bool high, double fps = 30, List<double> supported = _rates}) =>
        playbackRefreshRate(
          playback: PlaybackRefresh(frameRate: fps, mode: mode),
          high: high,
          supported: supported,
        );

    test('power saving: the system picks (the declared frame rate leads it)', () {
      expect(rate('powerSaving', high: false), 0);
      expect(rate('powerSaving', high: false, fps: 25), 0);
    });

    test('balanced: up to 60 at rest, the highest multiple while touching; 50 for 25 frames', () {
      expect(rate('balanced', high: false), 60);
      expect(rate('balanced', high: true), 120);
      expect(rate('balanced', high: false, fps: 25, supported: [50, 60, 100, 120]), 50);
      expect(rate('balanced', high: true, fps: 25, supported: [50, 60, 100, 120]), 100);
    });

    test('performance: 120, not 144, for 60 frames', () {
      expect(rate('performance', high: true, fps: 60, supported: [60, 90, 120, 144]), 120);
    });

    test('P01 c2: no whole multiple takes the highest rate; nothing is left to the system', () {
      expect(rate('performance', high: true, fps: 25), 120);
      expect(rate('balanced', high: true, fps: 25), 120);
      expect(rate('balanced', high: false, fps: 25), 120);
      expect(rate('balanced', high: false, fps: 24), 120, reason: '24 × 5: the only multiple, above 60');
      expect(rate('balanced', high: false, supported: const []), 0, reason: 'rates not known yet');
    });

    // P01 acceptance: 24/25/30/50/60 frames × three kinds of display, as
    // (balanced at rest, balanced while touching and performance).
    final table = <List<double>, Map<int, (double, double)>>{
      [60, 90, 120]: {24: (120, 120), 25: (120, 120), 30: (60, 120), 50: (120, 120), 60: (60, 120)},
      [60, 120, 144]: {24: (120, 144), 25: (144, 144), 30: (60, 120), 50: (144, 144), 60: (60, 120)},
      [60, 90, 120, 144, 165]: {24: (120, 144), 25: (165, 165), 30: (60, 120), 50: (165, 165), 60: (60, 120)},
    };
    for (final MapEntry(key: supported, value: rows) in table.entries) {
      test('P01: ${supported.map((rate) => rate.round()).join('/')} Hz', () {
        for (final MapEntry(key: fps, value: (rest, touching)) in rows.entries) {
          final name = '$fps frames';
          final frames = fps.toDouble();
          expect(
            rate('balanced', high: false, fps: frames, supported: supported),
            rest,
            reason: '$name at rest',
          );
          expect(
            rate('balanced', high: true, fps: frames, supported: supported),
            touching,
            reason: '$name touching',
          );
          expect(
            rate('performance', high: true, fps: frames, supported: supported),
            touching,
            reason: '$name, performance',
          );
          expect(
            rate('powerSaving', high: false, fps: frames, supported: supported),
            0,
            reason: '$name, power saving',
          );
        }
      });
    }
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

    List<String> sent() => [for (final call in calls) '${call.method} ${call.arguments}'];

    test('P01 c1: playing declares one rate on the surface; touching raises it; stopping clears it', () async {
      await DisplayMode.applyHighRefreshRate(high: false);
      await DisplayMode.setPlayback(const PlaybackRefresh(frameRate: 30, mode: 'balanced'));
      // U.2i c3: touching asks for the highest multiple, not just the highest.
      await DisplayMode.applyHighRefreshRate(high: true);
      // Back to the video's rate when the interaction ends.
      await DisplayMode.applyHighRefreshRate(high: false);
      await DisplayMode.setPlayback(null);
      expect(sent(), [
        'setHighRefreshRate {enabled: false}',
        'setHighRefreshRate {enabled: false, frameRate: 60.0, refreshRate: 60.0}',
        'setHighRefreshRate {enabled: true, frameRate: 120.0, refreshRate: 120.0}',
        'setHighRefreshRate {enabled: false, frameRate: 60.0, refreshRate: 60.0}',
        'setHighRefreshRate {enabled: false}',
      ]);
      expect(sent(), everyElement(isNot(contains('setVideoFrameRate'))), reason: 'one call says everything');
    });

    test('P01: power saving declares the video itself; 25 frames take 120 Hz', () async {
      await DisplayMode.setPlayback(const PlaybackRefresh(frameRate: 30, mode: 'powerSaving'));
      await DisplayMode.setPlayback(const PlaybackRefresh(frameRate: 25, mode: 'balanced'));
      expect(sent(), [
        'setHighRefreshRate {enabled: false, frameRate: 30.0, refreshRate: 0.0}',
        'setHighRefreshRate {enabled: false, frameRate: 120.0, refreshRate: 120.0}',
      ]);
    });

    test('P01: another display while playing chooses again', () async {
      await DisplayMode.setPlayback(const PlaybackRefresh(frameRate: 24, mode: 'balanced'));
      await DisplayMode.applyHighRefreshRate(high: true);
      DisplayMode.publish(
        DisplayModeInfo.fromMap(const {
          'currentRefreshRate': 120.0,
          'maxRefreshRate': 144.0,
          'supportedRefreshRates': [60.0, 120.0, 144.0],
        }),
      );
      await pumpEventQueue();
      expect(sent(), [
        'setHighRefreshRate {enabled: false, frameRate: 120.0, refreshRate: 120.0}',
        'setHighRefreshRate {enabled: true, frameRate: 120.0, refreshRate: 120.0}',
        'setHighRefreshRate {enabled: true, frameRate: 144.0, refreshRate: 144.0}',
      ]);
      // The same rates again change nothing.
      DisplayMode.publish(
        DisplayModeInfo.fromMap(const {
          'currentRefreshRate': 144.0,
          'maxRefreshRate': 144.0,
          'supportedRefreshRates': [60.0, 120.0, 144.0],
        }),
      );
      await pumpEventQueue();
      expect(calls, hasLength(3));
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
