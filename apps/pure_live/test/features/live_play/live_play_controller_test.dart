import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/testing.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/app_log.dart';
import 'package:pure_live/app/network.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/shared/rooms/play_quality.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

import '../../support.dart';
import 'live_play_support.dart';

const _bilibili = '../../fixtures/bilibili';

/// `getRoomPlayInfo` at qn=0 as a room offering 原画 only answers it (the
/// H01.3 rewrite of `S07-guest-qn0`): every codec lists 10000 alone.
ReplaySample _onlyOriginalListed() {
  final sample = ReplaySample.load('$_bilibili/S07-guest-qn0');
  final body = jsonDecode(utf8.decode(sample.bytes)) as Map<String, dynamic>;
  final playurl = ((body['data'] as Map)['playurl_info'] as Map)['playurl'] as Map;
  for (final stream in playurl['stream'] as List) {
    for (final format in (stream as Map)['format'] as List) {
      for (final codec in (format as Map)['codec'] as List) {
        (codec as Map)
          ..['accept_qn'] = [10000]
          ..['current_qn'] = 10000;
      }
    }
  }
  return ReplaySample(
    method: sample.method,
    url: sample.url,
    status: sample.status,
    headers: sample.headers,
    bytes: utf8.encode(jsonEncode(body)),
  );
}

/// Bilibili over the recorded guest answers of room 42062, listing 原画
/// only; a request at 10000 is served 250 (`S07-guest-qn10000`).
BilibiliSite _bilibiliGuestOriginalOnly() => BilibiliSite(
  ReplayHttp(
    [
      _onlyOriginalListed(),
      for (final name in [
        'S06-live',
        'S07-guest-qn0',
        'S07-guest-qn10000',
        'S09-guest',
        'S10-guest',
        'S11-guest',
        'S12-guest',
      ])
        ReplaySample.load('$_bilibili/$name'),
    ],
    ignoredQuery: const {'wts', 'w_rid', 'w_webid'},
  ),
  now: () => DateTime.utc(2026, 9, 27, 10, 16, 23),
  sleep: (_) async {},
);

void main() {
  late LiveStore store;
  late FakeDanmaku danmaku;
  late FakeEngine engine;
  late PlaybackSession session;
  final toasts = <String>[];
  final now = DateTime.utc(2026, 10, 1, 12);

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

  LiveRoomController controllerFor(
    LiveSite site, {
    LiveRoom? room,
    bool danmakuSupported = true,
    NetworkKind? network,
  }) => LiveRoomController(
    room: room ?? LiveRoom(platform: SiteIds.bilibili, roomId: '6', nick: '卡片上的名字'),
    site: site,
    session: session,
    danmaku: danmaku,
    danmakuSupported: danmakuSupported,
    store: store,
    toast: toasts.add,
    network: network == null ? null : () async => network,
    now: () => now,
    refreshInterval: Duration.zero,
  );

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('a live room plays the preferred quality, records history and joins the danmaku', () async {
    await store.settings.set(Settings.preferResolution, '超清');
    final site = FakeSite(liveRoom());
    final controller = controllerFor(site);
    await controller.start();
    await settle();

    expect(controller.stage, RoomStage.playing);
    expect(controller.room.title, '今晚开黑');
    expect(controller.qualities.map((q) => q.quality), ['原画', '超清', '流畅']);
    expect(controller.qualityIndex, 1);
    expect(session.state.status, PlaybackStatus.playing);
    expect(session.state.lineCount, 2);
    expect(engine.opens.single.uri.toString(), endsWith('250.flv'));
    expect((await store.history.all()).single.roomId, '6');
    expect(danmaku.connects, ['args-6']);
    expect(controller.chat.lines.map((line) => line.text), contains('弹幕服务器连接正常'));
    controller.dispose();
  });

  test('a detail without a cover keeps the card cover in the room and the history', () async {
    final card = LiveRoom(platform: SiteIds.bilibili, roomId: '6', nick: '卡片上的名字', cover: 'https://img/c.jpg');
    final controller = controllerFor(FakeSite(liveRoom()), room: card);
    await controller.start();
    await settle();

    expect(controller.stage, RoomStage.playing);
    expect(controller.room.cover, 'https://img/c.jpg');
    expect((await store.history.all()).single.cover, 'https://img/c.jpg');
    controller.dispose();
  });

  test('a detail with a new cover replaces the card cover', () async {
    final card = LiveRoom(platform: SiteIds.bilibili, roomId: '6', cover: 'https://img/old.jpg');
    final detail = liveRoom().copyWith(cover: 'https://img/new.jpg');
    final controller = controllerFor(FakeSite(detail), room: card);
    await controller.start();
    await settle();

    expect(controller.room.cover, 'https://img/new.jpg');
    expect((await store.history.all()).single.cover, 'https://img/new.jpg');
    controller.dispose();
  });

  test('on mobile data the first quality follows the mobile-data preference (M12.3)', () async {
    await store.settings.setAll({Settings.preferResolution: '原画', Settings.preferResolutionCellular: '流畅'});
    final mobile = controllerFor(FakeSite(liveRoom()), network: NetworkKind.mobile);
    await mobile.start();
    await settle();
    expect(mobile.qualities[mobile.qualityIndex].quality, '流畅');
    mobile.dispose();

    final wifi = controllerFor(FakeSite(liveRoom()), network: NetworkKind.other);
    await wifi.start();
    await settle();
    expect(wifi.qualities[wifi.qualityIndex].quality, '原画');
    wifi.dispose();
  });

  test('chat passes the block list; audience, super chats, retractions and notices', () async {
    await store.blockLists.add(BlockKind.keyword, '广告');
    final site = FakeSite(liveRoom())
      ..superChats = [
        LiveSuperChatMessage(
          userName: '老板',
          face: '',
          message: '加油',
          price: 30,
          startTime: now.subtract(const Duration(seconds: 10)),
          endTime: now.add(const Duration(minutes: 1)),
          backgroundColor: '#EDF5FF',
          backgroundBottomColor: '#2A60B2',
        ),
      ];
    final controller = controllerFor(site);
    final flying = <String>[];
    controller.flying.listen((message) => flying.add(message.message));
    await controller.start();
    await settle();
    expect(controller.superChats.single.userName, '老板');

    danmaku
      ..chat('你好', id: 'm1')
      ..chat('看广告领红包')
      ..chat('再见', user: '路人', id: 'm2');
    expect(flying, ['你好', '再见']);
    expect(controller.chat.lines.where((line) => line.kind == ChatLineKind.chat).map((line) => line.text), [
      '你好',
      '再见',
    ]);

    danmaku.emit(
      const DanmakuReceived(
        LiveMessage(
          type: LiveMessageType.retraction,
          userName: '',
          message: '',
          color: LiveMessageColor.white,
          data: LiveRetraction.message('m1'),
        ),
      ),
    );
    expect(controller.chat.lines.where((line) => line.kind == ChatLineKind.chat).map((line) => line.text), ['再见']);

    // Bilibili's new online count (C-1) sits beside the heat, not over it.
    danmaku.emit(
      const DanmakuReceived(
        LiveMessage(
          type: LiveMessageType.online,
          userName: '',
          message: '',
          color: LiveMessageColor.white,
          data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.onlineViewers, value: 3456),
        ),
      ),
    );
    final figures = audienceFigures(controller.room);
    expect(figures.map((f) => f.type), [AudienceMetricType.onlineViewers, AudienceMetricType.popularity]);
    expect(figures.map((f) => f.value), ['3456', '120000']);

    danmaku
      ..emit(
        const DanmakuReceived(
          LiveMessage(
            type: LiveMessageType.notice,
            userName: '',
            message: '欢迎来到直播间',
            color: LiveMessageColor.white,
            data: LiveNoticeKind.system,
          ),
        ),
      )
      ..emit(const DanmakuReconnecting(DanmakuInterruption.disconnected))
      ..emit(const DanmakuClosed(DanmakuCloseReason.reconnectsExhausted));
    final tail = controller.chat.lines.reversed.take(3).toList().reversed.toList();
    expect(tail.map((line) => line.kind), [ChatLineKind.notice, ChatLineKind.system, ChatLineKind.system]);
    expect(tail.last.text, contains('多次重连失败'));

    await controller.blockUser('路人');
    expect(await store.blockLists.list(BlockKind.user), ['路人']);
    expect(controller.chat.lines.where((line) => line.kind == ChatLineKind.chat), isEmpty);
    controller.dispose();
  });

  test('an offline room does not play; it starts by itself when the refresh finds it live (B-24)', () async {
    final site = FakeSite(liveRoom(status: LiveStatus.offline));
    final controller = controllerFor(site);
    await controller.start();
    await settle();
    expect(controller.stage, RoomStage.offline);
    expect(engine.opens, isEmpty);
    expect(danmaku.connects, isEmpty);

    site.room = liveRoom();
    await controller.refreshDetail();
    await settle();
    expect(controller.stage, RoomStage.playing);
    expect(danmaku.connects, ['args-6']);

    // The broadcast ended and came back: the closed danmaku connects again.
    danmaku.emit(const DanmakuClosed(DanmakuCloseReason.connectionFailed));
    await controller.refreshDetail();
    await settle();
    expect(danmaku.connects, ['args-6', 'args-6']);
    controller.dispose();
  });

  test('a failed detail keeps the card and says why; retry loads again', () async {
    final site = FakeSite(liveRoom())..detailError = const NeedsLogin(SiteIds.bilibili);
    final controller = controllerFor(site);
    await controller.start();
    expect(controller.stage, RoomStage.failed);
    expect(controller.room.nick, '卡片上的名字');
    expect(controller.room.isLiveStatusPending, isTrue);
    expect(failureText(controller.failure), '需要登录该平台后才能观看');

    site.detailError = null;
    await controller.retry();
    await settle();
    expect(controller.stage, RoomStage.playing);
    controller.dispose();
  });

  test('a restricted live room explains the restriction when no stream comes', () async {
    final site = FakeSite(liveRoom(restriction: LiveRestriction.paid))..qualities = const [];
    final controller = controllerFor(site);
    await controller.start();
    expect(controller.stage, RoomStage.unplayable);
    expect(restrictionReason(controller.room.effectiveRestriction), contains('付费直播'));
    controller.dispose();
  });

  test('E05.4 c3: a live room without danmaku arguments does not connect (AcFun paid show)', () async {
    final site = FakeSite(liveRoom(restriction: LiveRestriction.paid, danmakuData: null))..qualities = const [];
    final controller = controllerFor(site);
    await controller.start();
    await settle();
    expect(controller.stage, RoomStage.unplayable);
    expect(controller.chatConnection, ChatConnection.idle);
    expect(danmaku.connects, isEmpty);
    expect(controller.chat.lines.map((line) => line.text), isNot(contains('弹幕连接失败')));
    controller.dispose();

    // A playing room without arguments stays idle too.
    final playing = controllerFor(FakeSite(liveRoom(danmakuData: null)));
    await playing.start();
    await settle();
    expect(playing.stage, RoomStage.playing);
    expect(playing.chatConnection, ChatConnection.idle);
    expect(danmaku.connects, isEmpty);
    playing.dispose();
  });

  test('a quality the platform downgrades shows the quality really played', () async {
    final site = DowngradingSite(liveRoom(), applied: 250);
    final controller = controllerFor(site);
    await controller.start();
    await settle();
    expect(controller.qualityIndex, 1);
    expect(toasts, ['平台实际返回 超清，已按真实画质播放'], reason: 'C01.4: entering the room says it once');

    await controller.selectQuality(0);
    expect(controller.qualityIndex, 1);
    expect(toasts, hasLength(2), reason: 'a quality picked by hand is answered every time');
    expect(toasts.last, contains('超清'));
    controller.dispose();
  });

  group('C01.4: the quality shown is the one the platform served', () {
    test('a Bilibili guest in a room listing 原画 only sees the 超清 it is served, told once', () async {
      final controller = controllerFor(
        _bilibiliGuestOriginalOnly(),
        room: LiveRoom(platform: SiteIds.bilibili, roomId: '42062'),
      );
      await controller.start();
      await settle();

      expect(controller.stage, RoomStage.playing, reason: '${controller.failure}');
      final shown = controller.qualities[controller.qualityIndex];
      expect((shown.quality, shown.id, shown.isPlaybackUnconfirmed), ('超清', 250, false));
      expect(controller.qualities.map((q) => q.quality), ['超清']);
      expect(toasts, ['平台实际返回 超清，已按真实画质播放']);

      // Refreshing the room (also the reload after a failed stream) plays the
      // same tier again without saying it again.
      await controller.load();
      await settle();
      expect(controller.qualities[controller.qualityIndex].quality, '超清');
      expect(toasts, hasLength(1));
      controller.dispose();
    });

    test('a quality the platform did not confirm keeps the request, unconfirmed, without a toast', () async {
      final controller = controllerFor(_UnconfirmedSite(liveRoom()));
      await controller.start();
      await settle();
      final shown = controller.qualities[controller.qualityIndex];
      expect((shown.quality, shown.isPlaybackUnconfirmed), ('原画', true));
      expect(toasts, isEmpty);
      controller.dispose();
    });
  });

  test('a platform without danmaku says so once', () async {
    final controller = controllerFor(FakeSite(liveRoom()), danmakuSupported: false);
    await controller.start();
    await settle();
    expect(danmaku.connects, isEmpty);
    expect(controller.chat.lines.single.text, '该平台暂不支持弹幕');
    controller.dispose();
  });

  group("B06: Bilibili's names", () {
    LiveMessage chat(String user) =>
        LiveMessage(type: LiveMessageType.chat, userName: user, message: '前排', color: LiveMessageColor.white);

    test('a guest: the hint while the danmaku is on, and no system line for masked names', () async {
      final controller = controllerFor(FakeSite(liveRoom()));
      expect(controller.nameHint, ChatNameHint.none, reason: 'not connected yet');
      await controller.start();
      await settle();
      expect(controller.nameHint, ChatNameHint.guest);
      danmaku.emit(DanmakuReceived(chat('观***')));
      expect(controller.chat.lines.where((line) => line.kind == ChatLineKind.system).map((line) => line.text), [
        '开始连接弹幕服务器',
        '弹幕服务器连接正常',
      ]);
      await store.settings.setAll({Settings.enableDanmakuDisplay: false, Settings.enablePipDanmaku: false});
      await settle();
      expect(controller.nameHint, ChatNameHint.none, reason: 'danmaku off');
      controller.dispose();
    });

    test('signed in: none; three masked names and no full one say the login expired', () async {
      await store.secrets.setCookie(SiteIds.bilibili, 'SESSDATA=a; DedeUserID=1');
      final site = FakeSite(liveRoom());
      final controller = controllerFor(site);
      await controller.start();
      await settle();
      expect(controller.nameHint, ChatNameHint.none);
      danmaku
        ..emit(DanmakuReceived(chat('观***')))
        ..emit(DanmakuReceived(chat('离**')));
      expect(controller.nameHint, ChatNameHint.none, reason: 'two are not enough');
      danmaku.emit(DanmakuReceived(chat('V***')));
      expect(controller.nameHint, ChatNameHint.loginExpired);
      danmaku.emit(DanmakuReceived(chat('完整的名字')));
      expect(controller.nameHint, ChatNameHint.none, reason: 'a full name: the login works');

      // Signing out connects again with the guest's credentials.
      final connects = danmaku.connects.length;
      site.room = liveRoom().copyWith(danmakuData: 'args-6-guest');
      await store.secrets.setCookie(SiteIds.bilibili, '');
      await settle();
      expect(controller.nameHint, ChatNameHint.guest);
      expect(danmaku.connects.sublist(connects), ['args-6-guest']);
      controller.dispose();
    });

    test('other platforms and other logins: no hint, no reconnect', () async {
      final room = LiveRoom(
        platform: SiteIds.douyu,
        roomId: '6',
        nick: '主播',
        liveStatus: LiveStatus.live,
        danmakuData: 'args-6',
      );
      final controller = controllerFor(FakeSite(room), room: room);
      await controller.start();
      await settle();
      danmaku.emit(DanmakuReceived(chat('观***')));
      expect(controller.nameHint, ChatNameHint.none);
      await store.secrets.setCookie(SiteIds.douyu, 'acf_uid=1');
      await store.secrets.setCookie(SiteIds.bilibili, 'SESSDATA=a');
      await settle();
      expect(danmaku.connects, ['args-6']);
      controller.dispose();
    });
  });

  test("E06.3: a YY room plays stream-manager's FLV, two lines, at the quality 3.x's 原画 picks", () async {
    final site = YySite(
      ReplayHttp(
        [
          for (final name in ['S05-detail-live', 'S06-streams-g1', 'S06-streams-g2', 'S06-streams-g2-l10'])
            ReplaySample.load('../../fixtures/yy/$name'),
        ],
        ignoredQuery: const {'seq', 'send_time', 'sequence', 'osversion', 'width', 'height'},
      ),
      flvFirst: true,
      now: () => DateTime.utc(2026, 9, 27, 16, 56, 56),
    );
    final controller = controllerFor(
      site,
      room: LiveRoom(platform: SiteIds.yy, roomId: '22490906'),
    );
    await controller.start();
    await settle();

    expect(controller.stage, RoomStage.playing, reason: '${controller.failure}');
    expect(controller.qualities.map((q) => q.quality), ['高清', '流畅']);
    expect(controller.qualityIndex, 0);
    expect(session.state.lineCount, 2);
    expect(engine.opens.single.uri.path, endsWith('.flv'));
    expect(toasts, isEmpty);
    controller.dispose();
  });

  test("E06.3: YY's FLV names under 3.x's five preferences", () {
    const two = [LivePlayQuality(quality: '高清', id: '2'), LivePlayQuality(quality: '流畅', id: '1')];
    const three = [
      LivePlayQuality(quality: '蓝光', id: '3'),
      LivePlayQuality(quality: '高清', id: '2'),
      LivePlayQuality(quality: '流畅', id: '1'),
    ];
    const preferences = ['原画', '蓝光8M', '蓝光4M', '超清', '流畅'];
    expect(
      [for (final name in preferences) two[defaultQualityIndex(two, name)].quality],
      ['高清', '高清', '流畅', '流畅', '流畅'],
    );
    expect(
      [for (final name in preferences) three[defaultQualityIndex(three, name)].quality],
      ['蓝光', '高清', '高清', '流畅', '流畅'],
    );
  });

  test("the starting quality follows 3.x's preference rules", () {
    const qualities = [LivePlayQuality(quality: '原画'), LivePlayQuality(quality: '蓝光'), LivePlayQuality(quality: '高清')];
    expect(defaultQualityIndex(qualities, '原画'), 0);
    expect(defaultQualityIndex(qualities, '流畅'), 2);
    expect(defaultQualityIndex(qualities, '超清'), 2);
    expect(defaultQualityIndex(qualities, '蓝光4M'), 1);
    expect(defaultQualityIndex(const [], '原画'), 0);
  });

  test('with 优先 H.264 the name match skips an HEVC quality (G01.3)', () {
    const flv = LivePlayQuality(quality: 'FLV', codec: 'avc');
    const original = LivePlayQuality(quality: '原画', codec: 'hevc');
    expect(defaultQualityIndex(const [flv, original], '原画', preferH264: true), 0);
    expect(defaultQualityIndex(const [flv, original], '原画'), 1, reason: 'off: the name wins, as before');
    expect(defaultQualityIndex(const [original, flv], '原画'), 0);
    // Only HEVC on offer: it is still the one chosen.
    expect(defaultQualityIndex(const [original], '原画', preferH264: true), 0);
    expect(
      defaultQualityIndex(const [original, LivePlayQuality(quality: '超清', codec: 'hevc')], '原画', preferH264: true),
      0,
    );
    // Without hints the rule is unchanged.
    const unhinted = [LivePlayQuality(quality: 'FLV'), LivePlayQuality(quality: '原画')];
    expect(defaultQualityIndex(unhinted, '原画', preferH264: true), 1);
    // The skipped match falls back to the relative position.
    const ladder = [
      LivePlayQuality(quality: '蓝光', codec: 'avc'),
      LivePlayQuality(quality: '超清', codec: 'hevc'),
      LivePlayQuality(quality: '高清', codec: 'avc'),
      LivePlayQuality(quality: '流畅', codec: 'avc'),
    ];
    expect(defaultQualityIndex(ladder, '超清', preferH264: true), 2);
    expect(defaultQualityIndex(ladder, '超清'), 1);
    // A fallback position on HEVC moves to the nearest other quality.
    const hevcAtPosition = [
      LivePlayQuality(quality: '蓝光', codec: 'avc'),
      LivePlayQuality(quality: '高清', codec: 'avc'),
      LivePlayQuality(quality: '超清', codec: 'hevc'),
      LivePlayQuality(quality: '流畅', codec: 'avc'),
    ];
    expect(defaultQualityIndex(hevcAtPosition, '超清', preferH264: true), 1);
  });

  group('G01.3: the starting quality of an Inke-like room', () {
    const flv = LivePlayQuality(quality: 'FLV', id: 'flv', codec: 'avc');
    const original = LivePlayQuality(quality: '原画', id: 'origin', sort: 1, codec: 'hevc');

    test('with 优先 H.264 on (the default) the H.264 FLV opens, not the HEVC original', () async {
      final site = FakeSite(liveRoom())..qualities = const [flv, original];
      final controller = controllerFor(site);
      await controller.start();
      await settle();
      expect(store.settings.get(Settings.preferResolution), '原画');
      expect(store.settings.get(Settings.preferH264), isTrue);
      expect(controller.qualityIndex, 0);
      expect(engine.opens.single.uri.toString(), endsWith('/flv.flv'));
      controller.dispose();
    });

    test('with 优先 H.264 off the original is chosen by its name', () async {
      await store.settings.set(Settings.preferH264, false);
      final site = FakeSite(liveRoom())..qualities = const [original, flv];
      final controller = controllerFor(site);
      await controller.start();
      await settle();
      expect(controller.qualityIndex, 0);
      expect(engine.opens.single.uri.toString(), endsWith('/origin.flv'));
      controller.dispose();
    });

    test('picking the original by hand plays it', () async {
      final site = FakeSite(liveRoom())..qualities = const [flv, original];
      final controller = controllerFor(site);
      await controller.start();
      await settle();
      await controller.selectQuality(1);
      await settle();
      expect(controller.qualityIndex, 1);
      expect(engine.opens.last.uri.toString(), endsWith('/origin.flv'));
      controller.dispose();
    });
  });

  test('G02.2: every recovery attempt leaves one app log line with its count and cause', () async {
    final controller = controllerFor(FakeSite(liveRoom()));
    await controller.start();
    await settle();
    expect(session.state.status, PlaybackStatus.playing);
    List<String> lines() => [
      for (final entry in AppLog.instance.entries)
        if (entry.tag == 'playback') entry.message,
    ];
    final before = lines().length;

    // The reopened line does not play yet: the recovery goes on.
    engine
      ..onOpen = ((_) async {})
      ..emit(
        const EngineError(
          PlayerException(message: 'connection reset', type: PlayerErrorType.network, code: 'transport'),
        ),
      );
    await settle();
    expect(session.state.recovery, 1);
    expect(lines().skip(before), ['recovering #1 transport']);
    expect(AppLog.instance.entries.last.format(), endsWith('[INFO] playback: recovering #1 transport'));

    // Playing again ends it; the next drop counts on.
    engine
      ..emit(const EngineBuffering(buffering: false))
      ..emit(const EnginePlaying(playing: true))
      ..emit(const EngineError(PlayerException(message: 'reset', type: PlayerErrorType.network, code: 'b')));
    await settle();
    expect(lines().skip(before), ['recovering #1 transport', 'recovering #2 b']);
    controller.dispose();
  });

  test('texts: time on air, audience numbers', () {
    expect(startedAgo(now.subtract(const Duration(minutes: 80)), now), '已开播 1 小时 20 分');
    expect(startedAgo(now.subtract(const Duration(seconds: 20)), now), '刚刚开播');
    // One formatter for the room and the cards (M13.16): days past 24 hours.
    expect(startedAgo(now.subtract(const Duration(hours: 51, minutes: 49)), now), '已开播 2 天 3 小时');
    expect(elapsedText(const Duration(minutes: 7)), '7 分钟');
    expect(elapsedText(const Duration(seconds: 10)), '1 分钟');
    expect(elapsedText(const Duration(hours: 23, minutes: 59)), '23 小时 59 分');
    expect(elapsedText(const Duration(hours: 24)), '1 天 0 小时');
    final live = LiveRoom(platform: 'douyu', roomId: '1', liveStatus: LiveStatus.live);
    expect(
      liveDuration(live.copyWith(startedAt: now.subtract(const Duration(hours: 51, minutes: 49))), now),
      '已播 2 天 3 小时',
    );
    expect(readableAudience('123456'), '12.3万');
    expect(readableAudience('999'), '999');
  });
}

/// A platform expected to confirm the quality that did not.
class _UnconfirmedSite extends FakeSite implements LivePlayUrlResolver {
  new(super.room);

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => LivePlayUrlResolution(urls: ['https://a.example/${quality.id}.flv'], qualityUnconfirmed: true);
}
