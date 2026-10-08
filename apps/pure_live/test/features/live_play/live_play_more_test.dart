import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/live_play/buttons/room_menu_button.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/logic/background_playback.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/platform/system_access.dart';
import 'package:pure_live/shared/danmaku/danmaku_templates.dart';

import '../../support.dart';
import 'live_play_support.dart';

/// An IPTV channel with a catch-up archive.
class _IptvSite extends FakeSite {
  new(super.room);

  @override
  String get id => SiteIds.iptv;

  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async => [
    const LivePlayQuality(quality: '默认', id: 'default'),
  ];

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async => [
    detail.link!,
  ];
}

void main() {
  late LiveStore store;
  late FakeDanmaku danmaku;
  late FakeEngine engine;
  late PlaybackSession session;
  final toasts = <String>[];
  final now = DateTime(2026, 10, 1, 20);

  setUpAll(loadStrings);

  setUp(() async {
    store = await LiveStore.memory(cipher: FakeCipher());
    danmaku = FakeDanmaku();
    engine = FakeEngine();
    session = fakeSession(engine);
    toasts.clear();
  });

  tearDown(() async {
    await session.dispose();
    await store.close();
  });

  LiveRoomController controllerFor(FakeSite site, {bool sleepSession = false, LiveRoom? room}) => LiveRoomController(
    room: room ?? LiveRoom(platform: site.id, roomId: '6', nick: '主播'),
    site: site,
    session: session,
    danmaku: danmaku,
    danmakuSupported: true,
    store: store,
    toast: toasts.add,
    now: () => now,
    refreshInterval: Duration.zero,
    sleepSessionOnStart: sleepSession,
    // At least a second (AGENTS.md: timers outlast the steps before them).
    minuteLength: const Duration(seconds: 1),
  );

  Future<void> settle([int ms = 20]) => Future<void>.delayed(Duration(milliseconds: ms));

  /// Polls [done] until it holds, so a slow run under load waits longer
  /// instead of failing.
  Future<void> until(bool Function() done, {Duration timeout = const Duration(seconds: 10)}) async {
    final deadline = DateTime.now().add(timeout);
    while (!done() && DateTime.now().isBefore(deadline)) {
      await settle();
    }
  }

  LiveMessage gift(String user, String text) =>
      LiveMessage(type: LiveMessageType.gift, userName: user, message: text, color: LiveMessageColor.white);

  test('gifts are chat lines (B-21); the switch hides them and is remembered', () async {
    final controller = controllerFor(FakeSite(liveRoom()));
    await controller.start();
    await settle();
    danmaku.emit(DanmakuReceived(gift('观众', '辣条 ×10')));
    final line = controller.chat.lines.last;
    expect(line.kind, ChatLineKind.gift);
    expect(line.text, '辣条 ×10');
    expect(line.message!.userName, '观众');

    await controller.setShowGifts(show: false);
    expect(controller.chat.lines.where((line) => line.kind == ChatLineKind.gift), isEmpty);
    danmaku.emit(DanmakuReceived(gift('观众', '小电视 ×1')));
    expect(controller.chat.lines.where((line) => line.kind == ChatLineKind.gift), isEmpty);
    // A08.6 c3: the switch is the `showChatGifts` setting now (it was a
    // record in `meta`), so every room and the settings page share it.
    expect(store.settings.get(Settings.showChatGifts), isFalse);
    controller.dispose();

    final next = controllerFor(FakeSite(liveRoom()));
    await next.start();
    expect(next.showGifts, isFalse);
    next.dispose();
  });

  test('A08.6 c3: the gift setting changed elsewhere applies to an open room at once', () async {
    final controller = controllerFor(FakeSite(liveRoom()));
    await controller.start();
    await settle();
    var notified = 0;
    controller.addListener(() => notified++);
    danmaku.emit(DanmakuReceived(gift('观众', '辣条 ×10')));
    expect(controller.chat.lines.where((line) => line.kind == ChatLineKind.gift), hasLength(1));

    // The settings page turns it off: the open room drops its gift lines.
    await store.settings.set(Settings.showChatGifts, false);
    await settle();
    expect(controller.showGifts, isFalse);
    expect(notified, greaterThan(0));
    expect(controller.chat.lines.where((line) => line.kind == ChatLineKind.gift), isEmpty);
    danmaku.emit(DanmakuReceived(gift('观众', '小电视 ×1')));
    expect(controller.chat.lines.where((line) => line.kind == ChatLineKind.gift), isEmpty);

    // And on again: new gifts show.
    await store.settings.set(Settings.showChatGifts, true);
    await settle();
    expect(controller.showGifts, isTrue);
    danmaku.emit(DanmakuReceived(gift('观众', '小电视 ×2')));
    expect(controller.chat.lines.where((line) => line.kind == ChatLineKind.gift), hasLength(1));
    controller.dispose();
  });

  test('audio only keeps the stream; a sleep session starts audio only and its timer pauses the room', () async {
    final controller = controllerFor(FakeSite(liveRoom()));
    await controller.start();
    await settle();
    await controller.setAudioOnly(enabled: true);
    expect(controller.audioOnly, isTrue);
    expect(session.state.audioOnly, isTrue);
    expect(engine.opens, hasLength(1));
    controller.dispose();

    await store.settings.set(Settings.asmrSleepMinutes, 2);
    final sleeping = controllerFor(FakeSite(liveRoom()), sleepSession: true);
    await sleeping.start();
    await settle();
    expect(sleeping.audioOnly, isTrue);
    expect(sleeping.sleepSessionActive, isTrue);
    expect(sleeping.sleepDeadline, now.add(const Duration(seconds: 2)));
    // The background policy keeps a sleep session playing.
    expect(
      shouldContinueInBackground(backgroundPlaybackEnabled: false, sleepSessionActive: sleeping.sleepSessionActive),
      isTrue,
    );
    await until(() => sleeping.sleepDeadline == null && session.state.status == PlaybackStatus.paused);
    expect(sleeping.sleepDeadline, isNull);
    expect(session.state.status, PlaybackStatus.paused);
    expect(toasts, contains('当前直播间已按定时设置停止播放'));
    sleeping.dispose();
  });

  test("the room volume is kept under 3.x's key", () async {
    final controller = controllerFor(FakeSite(liveRoom()));
    await controller.start();
    await settle();
    await controller.setVolume(0.35, save: true);
    expect(session.state.volume, 0.35);
    expect(store.settings.get(Settings.roomVolumes)[roomVolumeKey(SiteIds.bilibili, '6')], 0.35);
    controller.dispose();
  });

  test('IPTV: the user agent sits under the playlist headers; an ended programme replays and comes back', () async {
    await store.settings.set(Settings.customIptvUserAgent, 'MyTV/1.0');
    final channel = LiveRoom(
      platform: SiteIds.iptv,
      roomId: 'cctv1',
      title: 'CCTV-1',
      link: 'http://tv.example/cctv1.m3u8',
      data: 'http://tv.example/cctv1.m3u8',
      liveStatus: LiveStatus.live,
      httpHeaders: const {'Referer': 'http://tv.example/'},
      catchUp: const CatchUp(mode: 'default', days: 7),
    );
    final controller = controllerFor(_IptvSite(channel), room: channel);
    await controller.start();
    await settle();
    expect(engine.opens.single.headers, {'user-agent': 'MyTV/1.0', 'referer': 'http://tv.example/'});
    expect(iptvPlayHeaders(userAgent: 'MyTV', room: const {'User-Agent': 'Box'}), {
      'User-Agent': 'Box',
    }, reason: "the channel's own agent wins (3.x)");

    final programme = EpgProgramme(
      channelId: 'cctv1',
      sourceId: 'guide',
      start: now.subtract(const Duration(hours: 2)),
      stop: now.subtract(const Duration(hours: 1)),
      title: '新闻联播',
    );
    expect(await controller.playCatchup(programme), isNull);
    expect(controller.catchup, programme);
    expect(engine.opens.last.uri.queryParameters['playseek'], '20261001180000-20261001190000');
    expect(controller.room.catchUp.isActive, isTrue);

    final later = EpgProgramme(
      channelId: 'cctv1',
      sourceId: 'guide',
      start: now.add(const Duration(hours: 1)),
      stop: now.add(const Duration(hours: 2)),
      title: '电视剧',
    );
    expect(await controller.playCatchup(later), 'program_scheduled_hint');

    await controller.backToLive();
    await settle();
    expect(controller.catchup, isNull);
    expect(engine.opens.last.uri.toString(), 'http://tv.example/cctv1.m3u8');
    controller.dispose();
  });

  test('IPTV on the local network: local-network access is asked before it opens (release fixes, item 4)', () async {
    final asked = <String>[];
    SystemAccess.debugCall = (method) async {
      asked.add('$method before ${engine.opens.length} opens');
      return false;
    };
    addTearDown(() => SystemAccess.debugCall = null);
    final channel = LiveRoom(
      platform: SiteIds.iptv,
      roomId: 'home',
      title: '家里的电视',
      link: 'http://192.168.1.8:8080/live.m3u8',
      liveStatus: LiveStatus.live,
    );
    final controller = controllerFor(_IptvSite(channel), room: channel);
    await controller.start();
    await settle();
    expect(asked, ['requestLocalNetwork before 0 opens']);
    expect(toasts.single, contains('局域网里的直播源'));
    controller.dispose();
  });

  test('leaving the app pauses unless background play is on; coming back resumes', () async {
    final controller = controllerFor(FakeSite(liveRoom()));
    await controller.start();
    await settle();
    final policy = RoomBackgroundPolicy(
      controller: controller,
      settings: store.settings,
      hiddenPauseDelay: const Duration(milliseconds: 10),
    )..onHidden();
    expect(session.presentationVisible, isFalse);
    await until(() => session.state.status == PlaybackStatus.paused);
    expect(session.state.status, PlaybackStatus.paused);
    policy.onResumed();
    await settle();
    expect(session.presentationVisible, isTrue);
    expect(session.state.status, PlaybackStatus.playing);

    await store.settings.set(Settings.enableBackgroundPlay, true);
    policy.onHidden();
    await settle(40);
    expect(session.state.status, PlaybackStatus.playing);
    policy
      ..onResumed()
      ..dispose();
    controller.dispose();
  });

  group('C01.5: a room the app left', () {
    final notices = <String>[];

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      notices.clear();
      RoomMediaNotification.debugLog = notices.add;
    });

    tearDown(() => RoomMediaNotification.debugLog = null);

    RoomBackgroundPolicy policyFor(LiveRoomController controller) => RoomBackgroundPolicy(
      controller: controller,
      settings: store.settings,
      hiddenPauseDelay: const Duration(seconds: 1),
    )..start();

    for (final background in [false, true]) {
      test('offline when it left, it does not start in the background; it starts when the app is back '
          '(background play ${background ? 'on' : 'off'})', () async {
        await store.settings.set(Settings.enableBackgroundPlay, background);
        final site = FakeSite(liveRoom(status: LiveStatus.offline));
        final controller = controllerFor(site);
        final policy = policyFor(controller);
        await controller.start();
        await settle();
        policy.onHidden();
        expect(controller.stage, RoomStage.offline);

        site.room = liveRoom();
        await controller.refreshDetail();
        await settle();
        expect(engine.opens, isEmpty, reason: 'no sound while nobody looks');
        expect(controller.stage, RoomStage.offline);
        expect(controller.room.title, '今晚开黑', reason: 'the fresh detail is kept');
        expect(controller.room.liveStatus, LiveStatus.live);
        expect(notices, isEmpty, reason: 'nothing is started from the background');

        policy.onResumed();
        await until(() => controller.stage == RoomStage.playing);
        expect(engine.opens, hasLength(1));
        expect(controller.takeStartWhenBack(), isFalse, reason: 'used once');
        policy.dispose();
        controller.dispose();
      });
    }

    test('in picture-in-picture an offline room still starts when it comes on air', () async {
      // Background play on: no pause timer races the test.
      await store.settings.set(Settings.enableBackgroundPlay, true);
      final site = FakeSite(liveRoom(status: LiveStatus.offline));
      final controller = controllerFor(site);
      final policy = policyFor(controller);
      await controller.start();
      await settle();
      policy.onHidden();
      expect(policy.mayStartInBackground, isFalse, reason: 'not playing when it left');
      PictureInPicture.active.value = true;
      addTearDown(() => PictureInPicture.active.value = false);
      expect(policy.mayStartInBackground, isTrue);

      site.room = liveRoom();
      await controller.refreshDetail();
      await until(() => controller.stage == RoomStage.playing);
      expect(engine.opens, hasLength(1));
      policy.dispose();
      controller.dispose();
    });

    test('playing when it left with background play on: it reloads, ends and comes back in the background; '
        'the media notification stays, paused in between', () async {
      await store.settings.set(Settings.enableBackgroundPlay, true);
      final site = FakeSite(liveRoom());
      final controller = controllerFor(site);
      final policy = policyFor(controller);
      await controller.start();
      await settle();
      expect(notices, ['show true']);
      policy.onHidden();
      expect(policy.mayStartInBackground, isTrue);

      // The broadcast ends (a reload finds it offline): the session stops.
      site.room = liveRoom(status: LiveStatus.offline);
      await controller.load();
      await settle();
      expect(controller.stage, RoomStage.offline);
      expect(notices, ['show true', 'update false'], reason: 'kept, paused');

      // On air again: it starts by itself (B-24) and shows playing.
      site.room = liveRoom();
      await controller.refreshDetail();
      await until(() => controller.stage == RoomStage.playing);
      await settle();
      expect(engine.opens, hasLength(2));
      expect(notices, ['show true', 'update false', 'update true']);

      policy.dispose();
      await settle();
      expect(notices.last, 'hide');
      controller.dispose();
    });

    test('background play switched off while away removes the notification', () async {
      await store.settings.set(Settings.enableBackgroundPlay, true);
      final controller = controllerFor(FakeSite(liveRoom()));
      final policy = policyFor(controller);
      await controller.start();
      await settle();
      policy.onHidden();
      await store.settings.set(Settings.enableBackgroundPlay, false);
      await settle();
      expect(notices, ['show true', 'hide']);
      expect(policy.mayStartInBackground, isFalse);
      policy
        ..onResumed()
        ..dispose();
      controller.dispose();
    });

    test('back in the app a room that does not play loses the notification, as before', () async {
      await store.settings.set(Settings.enableBackgroundPlay, true);
      final site = FakeSite(liveRoom());
      final controller = controllerFor(site);
      final policy = policyFor(controller);
      await controller.start();
      await settle();
      policy.onHidden();
      site.room = liveRoom(status: LiveStatus.offline);
      await controller.load();
      await settle();
      policy.onResumed();
      await settle();
      expect(notices, ['show true', 'update false', 'hide']);
      policy.dispose();
      controller.dispose();
    });
  });

  test('danmaku templates: 3.x presets, a saved template round-trips, a damaged one is refused', () async {
    final (_, comfort) = DanmakuTemplate.presets[1];
    await comfort.apply(store.settings);
    expect(store.settings.get(Settings.danmakuArea), 0.35);
    expect(DanmakuTemplate.of(store.settings).sameLook(comfort), isTrue);

    final saved = DanmakuTemplate.of(store.settings).encode();
    final decoded = DanmakuTemplate.tryDecode(saved, DanmakuTemplate.presets.last.$2)!;
    expect(decoded.sameLook(comfort), isTrue);
    // 3.x's schema: a template without the optional fields still reads.
    expect(
      DanmakuTemplate.tryDecode(
        '{"area":0.5,"top":10,"bottom":0,"speed":100,"fontSize":18,"fontBorder":1,"opacity":0.8}',
        comfort,
      )?.top,
      10,
    );
    expect(DanmakuTemplate.tryDecode('{"area":2}', comfort), isNull);
    expect(DanmakuTemplate.tryDecode('not json', comfort), isNull);
  });

  test('external targets: the web page, the app on Android, nothing for IPTV', () {
    final bilibili = LiveRoom(platform: SiteIds.bilibili, roomId: '6', link: 'https://live.bilibili.com/6');
    final target = externalRoomTarget(bilibili)!;
    expect(target.web.toString(), 'https://live.bilibili.com/6');
    expect(target.native.toString(), 'bilibili://live/6');
    expect(
      externalRoomTarget(LiveRoom(platform: SiteIds.twitch, roomId: 'a', link: 'https://www.twitch.tv/a'))?.native,
      isNull,
    );
    expect(externalRoomTarget(LiveRoom(platform: SiteIds.iptv, roomId: 'x', link: 'http://tv.example/x.m3u8')), isNull);
    expect(externalRoomTarget(LiveRoom(platform: SiteIds.douyu, roomId: '1', link: 'javascript:alert(1)')), isNull);
  });
}
