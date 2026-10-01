import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/pages/live_play/chat_feed.dart';
import 'package:pure_live/pages/live_play/room_controller.dart';
import 'package:pure_live/pages/live_play/room_texts.dart';

import 'live_play_support.dart';
import 'support.dart';

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

  LiveRoomController controllerFor(FakeSite site, {LiveRoom? room, bool danmakuSupported = true}) => LiveRoomController(
    room: room ?? LiveRoom(platform: SiteIds.bilibili, roomId: '6', nick: '卡片上的名字'),
    site: site,
    session: session,
    danmaku: danmaku,
    danmakuSupported: danmakuSupported,
    store: store,
    toast: toasts.add,
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

  test('a quality the platform downgrades shows the quality really played', () async {
    final site = DowngradingSite(liveRoom(), applied: 250);
    final controller = controllerFor(site);
    await controller.start();
    await settle();
    expect(controller.qualityIndex, 1);
    expect(toasts, isEmpty);

    await controller.selectQuality(0);
    expect(controller.qualityIndex, 1);
    expect(toasts.single, contains('超清'));
    controller.dispose();
  });

  test('a platform without danmaku says so once', () async {
    final controller = controllerFor(FakeSite(liveRoom()), danmakuSupported: false);
    await controller.start();
    await settle();
    expect(danmaku.connects, isEmpty);
    expect(controller.chat.lines.single.text, '该平台暂不支持弹幕');
    controller.dispose();
  });

  test("the starting quality follows 3.x's preference rules", () {
    const qualities = [LivePlayQuality(quality: '原画'), LivePlayQuality(quality: '蓝光'), LivePlayQuality(quality: '高清')];
    expect(defaultQualityIndex(qualities, '原画'), 0);
    expect(defaultQualityIndex(qualities, '流畅'), 2);
    expect(defaultQualityIndex(qualities, '超清'), 2);
    expect(defaultQualityIndex(qualities, '蓝光4M'), 1);
    expect(defaultQualityIndex(const [], '原画'), 0);
  });

  test('texts: time on air, audience numbers', () {
    expect(startedAgo(now.subtract(const Duration(minutes: 80)), now), '已开播 1 小时 20 分');
    expect(startedAgo(now.subtract(const Duration(seconds: 20)), now), '刚刚开播');
    expect(readableAudience('123456'), '12.3万');
    expect(readableAudience('999'), '999');
  });
}
