// G05.1: the room's audio focus (3.x `LiveAudioHandler._initSession`): a
// call pauses and resumes what it paused, a prompt lowers the volume,
// unplugged headphones pause for good.
import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:pure_live/features/live_play/logic/audio_focus.dart';

import 'live_play_support.dart';

/// The system's side: interruptions and unplugged headphones are sent by
/// hand; [activations] records every request and release of the focus.
final class _FakePort implements AudioFocusPort {
  final interruptionEvents = StreamController<AudioInterruptionEvent>.broadcast(sync: true);
  final noisyEvents = StreamController<void>.broadcast(sync: true);
  final activations = <bool>[];
  bool fails = false;

  @override
  Future<bool> activate({required bool active}) async {
    activations.add(active);
    if (fails) throw StateError('no focus');
    return true;
  }

  @override
  Stream<AudioInterruptionEvent> get interruptions => interruptionEvents.stream;

  @override
  Stream<void> get becomingNoisy => noisyEvents.stream;

  void begin(AudioInterruptionType type) => interruptionEvents.add(AudioInterruptionEvent(true, type));

  void end(AudioInterruptionType type) => interruptionEvents.add(AudioInterruptionEvent(false, type));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeEngine engine;
  late PlaybackSession session;
  late _FakePort port;
  late RoomAudioFocus focus;
  var mayPlay = true;

  Future<void> settle() => pumpEventQueue();

  setUp(() async {
    engine = FakeEngine();
    session = fakeSession(engine);
    port = _FakePort();
    mayPlay = true;
    focus = RoomAudioFocus(session: session, port: port, mayPlayNow: () => mayPlay)..start();
    await session.open(
      PlaybackRequest(
        site: SiteIds.bilibili,
        plan: PlaybackPlan.of(LivePlayUrlResolution.lines(const [LivePlayLine('https://a.example/live.flv')])),
        volume: 0.5,
      ),
    );
    await settle();
  });

  tearDown(() async {
    await focus.dispose();
    await session.dispose();
  });

  test('focus is asked for when playing starts and given back when the room is left', () async {
    expect(session.state.status, PlaybackStatus.playing);
    expect(port.activations, [true]);
    // Playing again after a pause asks no second time.
    await session.pause();
    await session.resume();
    await settle();
    expect(port.activations, [true]);
    await focus.dispose();
    expect(port.activations, [true, false]);
  });

  test('an interruption that pauses pauses the room and resumes it when it ends', () async {
    port.begin(AudioInterruptionType.pause);
    await settle();
    expect(session.state.status, PlaybackStatus.paused);
    port.end(AudioInterruptionType.pause);
    await settle();
    expect(session.state.status, PlaybackStatus.playing);
  });

  test('the user played or paused during the interruption: nothing resumes', () async {
    port.begin(AudioInterruptionType.pause);
    await settle();
    // The user plays during the call, then pauses again.
    await session.resume();
    await session.pause();
    port.end(AudioInterruptionType.pause);
    await settle();
    expect(session.state.status, PlaybackStatus.paused);
  });

  test('a room the user had paused is not started by the end of an interruption', () async {
    await session.pause();
    port.begin(AudioInterruptionType.pause);
    await settle();
    port.end(AudioInterruptionType.pause);
    await settle();
    expect(session.state.status, PlaybackStatus.paused);
  });

  test('a duck lowers the volume to 20 % and restores it', () async {
    port.begin(AudioInterruptionType.duck);
    await settle();
    expect(session.state.volume, closeTo(0.1, 1e-9));
    expect(session.state.status, PlaybackStatus.playing);
    port.end(AudioInterruptionType.duck);
    await settle();
    expect(session.state.volume, 0.5);

    // A volume the user chose meanwhile stays.
    port.begin(AudioInterruptionType.duck);
    await settle();
    await session.setVolume(0.8);
    port.end(AudioInterruptionType.duck);
    await settle();
    expect(session.state.volume, 0.8);
  });

  test('activation failing does not stop playback', () async {
    await focus.dispose();
    port = _FakePort()..fails = true;
    focus = RoomAudioFocus(session: session, port: port, mayPlayNow: () => mayPlay)..start();
    await session.pause();
    await session.resume();
    await settle();
    expect(port.activations, [true]);
    expect(session.state.status, PlaybackStatus.playing);
  });

  test('another app taking the focus for good pauses; nothing resumes; playing again asks for it again', () async {
    port.begin(AudioInterruptionType.unknown);
    await settle();
    expect(session.state.status, PlaybackStatus.paused);
    port.end(AudioInterruptionType.pause);
    await settle();
    expect(session.state.status, PlaybackStatus.paused);
    await session.resume();
    await settle();
    expect(port.activations, [true, true]);
  });

  test('unplugged headphones pause, and nothing resumes later', () async {
    port.begin(AudioInterruptionType.pause);
    await settle();
    port.noisyEvents.add(null);
    await settle();
    port.end(AudioInterruptionType.pause);
    await settle();
    expect(session.state.status, PlaybackStatus.paused);

    await session.resume();
    await settle();
    port.noisyEvents.add(null);
    await settle();
    expect(session.state.status, PlaybackStatus.paused);
  });

  test('the call ends while the room may not play in the background: it resumes once the app is back', () async {
    // The focus pauses first; then the app leaves (the background policy
    // finds it paused and pauses nothing itself).
    port.begin(AudioInterruptionType.pause);
    await settle();
    mayPlay = false;
    port.end(AudioInterruptionType.pause);
    await settle();
    expect(session.state.status, PlaybackStatus.paused);
    mayPlay = true;
    focus.onAppResumed();
    await settle();
    expect(session.state.status, PlaybackStatus.playing);
    // Only once.
    await session.pause();
    focus.onAppResumed();
    await settle();
    expect(session.state.status, PlaybackStatus.paused);
  });
}
