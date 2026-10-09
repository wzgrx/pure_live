// O01.3 (docs/O-Android系统集成/O01-通知和前台服务/O01.3-后台播放增强): the room's background
// policy away from the app: what the notification and the locks follow, a
// failed stream tried again (fake clock), the network coming back, a call,
// "后台只播声音", "后台断开弹幕", "关闭画中画时暂停", and coming back.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/live_play/logic/background_keeper.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';

import '../../support.dart';
import 'fake_clock.dart';
import 'live_play_support.dart';

void main() {
  late LiveStore store;
  late FakeDanmaku danmaku;
  late FakeEngine engine;
  late PlaybackSession session;
  late FakeClock clock;
  final notices = <String>[];
  final locks = <bool>[];

  setUpAll(loadStrings);

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    store = await LiveStore.memory(cipher: FakeCipher());
    await store.settings.set(Settings.enableBackgroundPlay, true);
    danmaku = FakeDanmaku();
    engine = FakeEngine();
    // No retry rounds of the session's own: a failure is published at once.
    session = PlaybackSession(
      engine: () async => engine,
      opener: MediaOpener(),
      timings: const SessionTimings(liveRetryDelays: []),
    );
    clock = FakeClock();
    notices.clear();
    locks.clear();
    RoomMediaNotification.debugLog = notices.add;
    BackgroundKeepAlive.debugReset();
    BackgroundKeepAlive.debugLog = ({required enabled}) => locks.add(enabled);
  });

  tearDown(() async {
    RoomMediaNotification.debugLog = null;
    BackgroundKeepAlive.debugLog = null;
    BackgroundKeepAlive.debugReset();
    PictureInPicture.active.value = false;
    await session.dispose();
    await store.close();
  });

  LiveRoomController controllerFor(FakeSite site) => LiveRoomController(
    room: LiveRoom(platform: site.id, roomId: '6', nick: '主播'),
    site: site,
    session: session,
    danmaku: danmaku,
    danmakuSupported: true,
    store: store,
    toast: (_) {},
    refreshInterval: Duration.zero,
  );

  RoomBackgroundPolicy policyFor(LiveRoomController controller, {Stream<bool>? online}) => RoomBackgroundPolicy(
    controller: controller,
    settings: store.settings,
    // At least a second (AGENTS.md).
    hiddenPauseDelay: const Duration(seconds: 1),
    online: online,
    keeperTimer: clock.timer,
    now: () => clock.now,
  )..start();

  Future<void> settle([int ms = 20]) => Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> until(bool Function() done, {Duration timeout = const Duration(seconds: 10)}) async {
    final deadline = DateTime.now().add(timeout);
    while (!done() && DateTime.now().isBefore(deadline)) {
      await settle();
    }
  }

  /// Opens fail the way a dropped stream does.
  void failOpens() =>
      engine.onOpen = (_) async =>
          throw const PlayerException(message: 'connection reset', type: PlayerErrorType.network, code: 'transport');

  Future<(LiveRoomController, RoomBackgroundPolicy)> playing({Stream<bool>? online}) async {
    final controller = controllerFor(FakeSite(liveRoom()));
    final policy = policyFor(controller, online: online);
    await controller.start();
    await until(() => session.state.status == PlaybackStatus.playing);
    // In front the locks were let go (a no-op); only what follows counts.
    locks.clear();
    return (controller, policy);
  }

  test('away and playing: the notification plays and the locks are held; back, they go', () async {
    final (controller, policy) = await playing();
    expect(notices, ['show true']);
    expect(locks, isEmpty, reason: 'no locks in front');
    policy.onHidden();
    expect(policy.hold, BackgroundHold.playing);
    expect(locks, [true]);
    policy.onResumed();
    expect(locks, [true, false]);
    expect(policy.hold, BackgroundHold.none);
    policy.dispose();
    controller.dispose();
  });

  test('R3: a pause from the notification lets the locks go and shows paused; play takes them again', () async {
    final (controller, policy) = await playing();
    policy.onHidden();
    await policy.pauseFromNotification();
    expect(session.state.status, PlaybackStatus.paused);
    expect(policy.hold, BackgroundHold.none);
    expect(locks, [true, false]);
    expect(notices, ['show true', 'update false']);

    await session.resume();
    await until(() => session.state.status == PlaybackStatus.playing);
    expect(policy.hold, BackgroundHold.playing);
    expect(locks, [true, false, true]);
    expect(notices, ['show true', 'update false', 'update true']);
    policy.dispose();
    controller.dispose();
  });

  test('R1, R5: a stream that fails away from the app stays "playing" and is tried again after 5 s', () async {
    final (controller, policy) = await playing();
    policy.onHidden();
    failOpens();
    await session.retry();
    await until(() => session.state.status == PlaybackStatus.error);
    expect(policy.hold, BackgroundHold.recovering);
    expect(notices, ['show true'], reason: 'never "paused": the foreground service stays');
    expect(locks, [true]);

    // The stream is back on the next try.
    engine.onOpen = null;
    final opens = engine.opens.length;
    await clock.advance(const Duration(seconds: 4));
    expect(engine.opens.length, opens, reason: 'not before 5 s');
    await clock.advance(const Duration(seconds: 1));
    await until(() => session.state.status == PlaybackStatus.playing);
    expect(engine.opens.length, opens + 1);
    expect(policy.hold, BackgroundHold.playing);
    expect(notices, ['show true']);
    policy.dispose();
    controller.dispose();
  });

  test('R5: in front a failure is left to the retry button', () async {
    final (controller, policy) = await playing();
    failOpens();
    await session.retry();
    await until(() => session.state.status == PlaybackStatus.error);
    final opens = engine.opens.length;
    await clock.advance(const Duration(minutes: 2));
    expect(engine.opens.length, opens);
    expect(clock.pending, isEmpty);
    policy.dispose();
    controller.dispose();
  });

  test('R6: the network coming back tries a failed stream at once', () async {
    final online = StreamController<bool>.broadcast(sync: true);
    addTearDown(online.close);
    final (controller, policy) = await playing(online: online.stream);
    policy.onHidden();
    failOpens();
    await session.retry();
    await until(() => session.state.status == PlaybackStatus.error);
    engine.onOpen = null;
    final opens = engine.opens.length;
    online.add(true);
    await clock.advance(Duration.zero);
    await until(() => session.state.status == PlaybackStatus.playing);
    expect(engine.opens.length, opens + 1);
    policy.dispose();
    controller.dispose();
  });

  test('a pause from the notification while it failed stops the tries', () async {
    final (controller, policy) = await playing();
    policy.onHidden();
    failOpens();
    await session.retry();
    await until(() => session.state.status == PlaybackStatus.error);
    await policy.pauseFromNotification();
    expect(policy.hold, BackgroundHold.none);
    expect(locks.last, isFalse);
    final opens = engine.opens.length;
    await clock.advance(const Duration(minutes: 5));
    expect(engine.opens.length, opens);
    policy.dispose();
    controller.dispose();
  });

  test('a call away from the app (G05.1) keeps the notification playing and the locks', () async {
    final (controller, policy) = await playing();
    var call = false;
    var forgotten = 0;
    policy
      ..interrupted = (() => call)
      ..onUserPause = (() => forgotten++)
      ..onHidden();
    call = true;
    await session.pause();
    expect(policy.hold, BackgroundHold.interrupted);
    expect(notices, ['show true']);
    expect(locks, [true]);
    // The user pauses from the notification during the call: the call's
    // resume is forgotten.
    await policy.pauseFromNotification();
    expect(forgotten, 1);
    policy.dispose();
    controller.dispose();
  });

  test('R7: "后台只播声音" turns the video off away from the app, again after a reopen; back, it returns', () async {
    await store.settings.set(Settings.backgroundAudioOnly, true);
    final (controller, policy) = await playing();
    policy.onHidden();
    expect(session.state.audioOnly, isFalse, reason: 'not before the app stayed away');
    await until(() => session.state.audioOnly);
    expect(session.state.audioOnly, isTrue);
    expect(controller.audioOnly, isFalse, reason: "the room's own switch is untouched");

    // A reload opens with the video on: turned off again.
    await controller.load();
    await until(() => session.state.status == PlaybackStatus.playing && session.state.audioOnly);
    expect(session.state.audioOnly, isTrue);

    policy.onResumed();
    expect(session.state.audioOnly, isFalse);
    policy.dispose();
    controller.dispose();
  });

  test('R7: the user\'s own "纯音频" stays on after coming back; off, the video keeps decoding', () async {
    final (controller, policy) = await playing();
    policy.onHidden();
    await settle(1100);
    expect(session.state.audioOnly, isFalse, reason: 'the switch is off by default (D-040)');
    policy.onResumed();

    await store.settings.set(Settings.backgroundAudioOnly, true);
    await controller.setAudioOnly(enabled: true);
    policy.onHidden();
    await settle(1100);
    policy.onResumed();
    expect(session.state.audioOnly, isTrue);
    policy.dispose();
    controller.dispose();
  });

  test('R8: "后台断开弹幕" closes the danmaku away from the app and connects it again back', () async {
    await store.settings.set(Settings.backgroundPauseDanmaku, true);
    final (controller, policy) = await playing();
    await until(() => danmaku.connects.isNotEmpty);
    final connects = danmaku.connects.length;
    final closes = danmaku.closes;
    policy.onHidden();
    await until(() => controller.danmakuSuspended);
    expect(danmaku.closes, greaterThan(closes));
    expect(controller.chatConnection, ChatConnection.idle);

    policy.onResumed();
    await until(() => danmaku.connects.length > connects);
    expect(controller.danmakuSuspended, isFalse);
    expect(danmaku.connects.length, connects + 1);
    policy.dispose();
    controller.dispose();
  });

  test('the away switches wait while picture-in-picture shows the room', () async {
    await store.settings.set(Settings.backgroundPauseDanmaku, true);
    await store.settings.set(Settings.backgroundAudioOnly, true);
    final (controller, policy) = await playing();
    PictureInPicture.active.value = true;
    // A short stop while the window opens.
    policy.onHidden();
    await settle(1100);
    expect(controller.danmakuSuspended, isFalse);
    expect(session.state.audioOnly, isFalse);
    policy
      ..onResumed()
      ..dispose();
    controller.dispose();
  });

  for (final windowFirst in [true, false]) {
    test('R9: closing picture-in-picture pauses with "关闭画中画时暂停" on, resumes back '
        '(${windowFirst ? 'the window goes first' : 'the app stops first'})', () async {
      await store.settings.set(Settings.pauseOnPipClose, true);
      final (controller, policy) = await playing();
      PictureInPicture.active.value = true;
      if (windowFirst) {
        PictureInPicture.active.value = false;
        policy.onHidden();
      } else {
        policy.onHidden();
        PictureInPicture.active.value = false;
      }
      await until(() => session.state.status == PlaybackStatus.paused);
      expect(session.state.status, PlaybackStatus.paused);
      expect(policy.hold, BackgroundHold.none);
      policy.onResumed();
      await until(() => session.state.status == PlaybackStatus.playing);
      expect(session.state.status, PlaybackStatus.playing);
      policy.dispose();
      controller.dispose();
    });
  }

  test('R9: off (the default), a closed picture-in-picture plays on; expanding it never pauses', () async {
    final (controller, policy) = await playing();
    PictureInPicture.active.value = true;
    PictureInPicture.active.value = false;
    policy.onHidden();
    await settle(50);
    expect(session.state.status, PlaybackStatus.playing);
    policy.onResumed();

    await store.settings.set(Settings.pauseOnPipClose, true);
    // Expanded: the window goes and the app resumes.
    PictureInPicture.active.value = true;
    PictureInPicture.active.value = false;
    policy.onResumed();
    await settle(50);
    expect(session.state.status, PlaybackStatus.playing);
    policy.dispose();
    controller.dispose();
  });
}
