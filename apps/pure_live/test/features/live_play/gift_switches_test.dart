// A08.12 (docs/A-界面设计/A08-弹幕界面/A08.12-礼物开关和飞行弹幕里的礼物): "只显示值钱的礼物" keeps the
// chat list's cheap gifts out (a combo shows once it adds up), "礼物价值换算成元"
// writes the fixed-rate units in yuan, "飞行弹幕显示礼物" sends the valuable
// gifts to the flying layer; all off by default, and then nothing changes.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/features/live_play/danmaku/gift_line.dart';
import 'package:pure_live/features/live_play/logic/gift_combiner.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';

import '../../support.dart';
import 'live_play_support.dart';
import 'no_images.dart';

/// [count] of a gift worth [value] in [unit] in all.
LiveMessage _gift(
  String user,
  String name, {
  int count = 1,
  int? value,
  LiveGiftUnit unit = LiveGiftUnit.goldSeed,
  String comboKey = '',
  bool free = false,
  String messageId = '',
}) {
  final gift = LiveGift(
    name: name,
    id: name,
    count: count,
    comboKey: comboKey,
    totalValue: value,
    unit: unit,
    free: free,
  );
  return LiveMessage(
    type: LiveMessageType.gift,
    userName: user,
    userId: user,
    message: gift.plainText,
    color: LiveMessageColor.white,
    messageId: messageId,
    data: gift,
  );
}

/// A feed and a combiner on it, with the clock they share.
final class _List {
  new() {
    feed = ChatFeed(giftCapacity: GiftCombiner.maxGiftLines, schedule: (flush) => flush());
    gifts = GiftCombiner(feed: feed, clock: () => now)..minTier = LiveGiftTier.valuable;
  }

  late final ChatFeed feed;
  late final GiftCombiner gifts;
  DateTime now = DateTime(2026, 10, 9, 20);

  void wait(int seconds) => now = now.add(Duration(seconds: seconds));

  List<String> get lines => [
    for (final line in feed.lines)
      if (line.kind == ChatLineKind.gift) '${line.message!.userName} ${line.text}',
  ];
}

void main() {
  setUpAll(loadStrings);

  group('"只显示值钱的礼物" in the combiner', () {
    test('free and cheap gifts get no line; valuable ones do', () {
      final list = _List();
      expect(list.gifts.add(_gift('甲', '小心心', count: 3, value: 3000)), GiftOutcome.belowTier);
      expect(list.gifts.add(_gift('乙', '辣条', free: true)), GiftOutcome.belowTier);
      expect(list.gifts.add(_gift('丙', '礼物')), GiftOutcome.belowTier, reason: 'no value: normal');
      expect(list.gifts.add(_gift('丁', '告白气球', value: 52000)), GiftOutcome.added);
      expect(list.lines, ['丁 告白气球 ×1']);
      expect(list.gifts.dropped, 0, reason: 'not "over the limit"');
    });

    test('a cheap combo gets its line once its total is worth it, with the whole total; then it merges', () {
      final list = _List();
      for (var i = 0; i < 9; i++) {
        expect(list.gifts.add(_gift('甲', '牛哇', value: 1000, comboKey: 'c')), GiftOutcome.belowTier);
        list.wait(1);
      }
      expect(list.lines, isEmpty);
      expect(list.gifts.add(_gift('甲', '牛哇', value: 1000, comboKey: 'c')), GiftOutcome.added);
      expect(list.lines, ['甲 牛哇 ×10']);
      final line = list.feed.lines.last;
      expect(line.message!.gift, isA<CombinedGift>());
      expect(line.message!.gift!.tier, LiveGiftTier.valuable);
      expect(list.gifts.add(_gift('甲', '牛哇', value: 1000, comboKey: 'c')), GiftOutcome.merged);
      expect(list.lines, ['甲 牛哇 ×11']);
    });

    test('a combo counted out of sight ends after 5 s without a gift', () {
      final list = _List();
      for (var i = 0; i < 9; i++) {
        list.gifts.add(_gift('甲', '牛哇', value: 1000, comboKey: 'c'));
      }
      list.wait(6);
      expect(list.gifts.add(_gift('甲', '牛哇', value: 1000, comboKey: 'c')), GiftOutcome.belowTier);
      expect(list.lines, isEmpty);
    });

    test('back to every gift: the cheap ones get lines again, as D07.1 has it', () {
      final list = _List()..gifts.minTier = LiveGiftTier.normal;
      expect(list.gifts.add(_gift('甲', '小心心', value: 1000)), GiftOutcome.added);
      expect(list.lines, ['甲 小心心 ×1']);
    });
  });

  group('"礼物价值换算成元"', () {
    test('the fixed-rate units in yuan; the others as they were', () {
      String? yuan(LiveGiftUnit unit, int value) =>
          giftValueText(LiveGift(name: '礼物', totalValue: value, unit: unit), inYuan: true);
      String? plain(LiveGiftUnit unit, int value) => giftValueText(LiveGift(name: '礼物', totalValue: value, unit: unit));
      expect(yuan(LiveGiftUnit.goldSeed, 2000), '2 元');
      expect(yuan(LiveGiftUnit.goldSeed, 5200), '5.2 元');
      expect(yuan(LiveGiftUnit.goldSeed, 198000), '198 元');
      expect(yuan(LiveGiftUnit.goldSeed, 1980000), '1980 元');
      expect(yuan(LiveGiftUnit.goldSeed, 1), '0.01 元', reason: 'never "0 元"');
      expect(yuan(LiveGiftUnit.diamond, 28), '2.8 元');
      expect(yuan(LiveGiftUnit.douyinCoin, 100), '10 元');
      expect(yuan(LiveGiftUnit.fen, 1250), '12.5 元');
      for (final (unit, value) in [
        (LiveGiftUnit.kicks, 100),
        (LiveGiftUnit.bits, 500),
        (LiveGiftUnit.point, 100),
        (LiveGiftUnit.cheese, 1000),
        (LiveGiftUnit.starBalloon, 10),
        (LiveGiftUnit.redBean, 30),
      ]) {
        expect(yuan(unit, value), plain(unit, value), reason: '$unit stays');
      }
      expect(yuan(LiveGiftUnit.other, 100), isNull);
      expect(
        giftValueText(
          const LiveGift(name: '辣条', totalValue: 500, unit: LiveGiftUnit.silverSeed, free: true),
          inYuan: true,
        ),
        isNull,
      );
      expect(plain(LiveGiftUnit.goldSeed, 2000), '2000 金瓜子', reason: 'off: the platform unit (A08.11)');
    });

    testWidgets('the gift line writes it; 280 wide and 2x text still wrap without overflow', (tester) async {
      final message = _gift('一个很长的观众昵称', '超级无敌豪华至尊梦幻嘉年华火箭', count: 99, value: 990000);
      for (final (width, scale, yuan) in [(360.0, 1.0, false), (360.0, 1.0, true), (280.0, 2.0, true)]) {
        await tester.pumpWidget(
          LiveUiScope(
            config: LiveUiConfig(imageCacheManager: NoImages()),
            child: MaterialApp(
              theme: const LiveTheme().light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: ChatLineView(line: ChatLine.gift(message)..id = 1, giftValueInYuan: yuan),
                  ),
                ),
              ),
            ),
          ),
        );
        final value = tester.widget<Text>(find.byKey(const ValueKey('live-play-gift-value'))).data;
        expect(value, yuan ? '990 元' : '99万 金瓜子', reason: '$width $scale');
        expect(tester.takeException(), isNull, reason: '$width $scale');
      }
    });
  });

  group('the room', () {
    late LiveStore store;
    late FakeDanmaku danmaku;
    late PlaybackSession session;
    final now = DateTime(2026, 10, 9, 20);

    setUp(() async {
      store = await LiveStore.memory(cipher: FakeCipher());
      danmaku = FakeDanmaku();
      session = fakeSession(FakeEngine());
    });

    tearDown(() async {
      await session.dispose();
      await store.close();
    });

    Future<(LiveRoomController, List<LiveMessage>)> open({Map<Setting<Object>, Object> settings = const {}}) async {
      for (final MapEntry(:key, :value) in settings.entries) {
        await store.settings.set(key, value);
      }
      final site = FakeSite(liveRoom());
      final controller = LiveRoomController(
        room: LiveRoom(platform: site.id, roomId: '6', nick: '主播'),
        site: site,
        session: session,
        danmaku: danmaku,
        danmakuSupported: true,
        store: store,
        toast: (_) {},
        now: () => now,
        refreshInterval: Duration.zero,
        minuteLength: const Duration(seconds: 1),
      );
      final flown = <LiveMessage>[];
      controller.flying.listen(flown.add);
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return (controller, flown);
    }

    List<String> giftLines(LiveRoomController controller) => [
      for (final line in controller.chat.lines)
        if (line.kind == ChatLineKind.gift) '${line.message!.userName} ${line.text}',
    ];

    test('by default: every gift in the list, none flies (as before, D-040)', () async {
      final (controller, flown) = await open();
      danmaku
        ..emit(DanmakuReceived(_gift('甲', '小心心', value: 1000, messageId: '1')))
        ..emit(DanmakuReceived(_gift('乙', '火箭', value: 500000, messageId: '2')));
      expect(giftLines(controller), ['甲 小心心 ×1', '乙 火箭 ×1']);
      expect(flown, isEmpty);
      controller.dispose();
    });

    test('"只显示值钱的礼物": cheap gifts stay out; turning it on takes the cheap lines away, local ones stay', () async {
      final (controller, _) = await open();
      danmaku
        ..emit(DanmakuReceived(_gift('甲', '小心心', value: 1000, messageId: '1')))
        ..emit(DanmakuReceived(_gift('乙', '告白气球', value: 52000, messageId: '2')));
      controller.addLocal(
        const LiveMessage(
          type: LiveMessageType.gift,
          userName: '我',
          message: '本地礼物 ×1',
          color: LiveMessageColor.white,
          isLocal: true,
        ),
        fly: false,
      );
      await store.settings.set(Settings.chatGiftsAboveTier, true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(giftLines(controller), ['乙 告白气球 ×1', '我 本地礼物 ×1']);
      danmaku
        ..emit(DanmakuReceived(_gift('丙', '小心心', value: 1000, messageId: '3')))
        ..emit(DanmakuReceived(_gift('丁', '飞机', value: 100000, messageId: '4')));
      expect(giftLines(controller), ['乙 告白气球 ×1', '我 本地礼物 ×1', '丁 飞机 ×1']);
      controller.dispose();
    });

    test('"飞行弹幕显示礼物": the valuable ones fly, with their words; cheap ones and chat as before', () async {
      final (controller, flown) = await open(settings: {Settings.danmakuShowGifts: true});
      danmaku
        ..chat('聊天')
        ..emit(DanmakuReceived(_gift('甲', '小心心', value: 1000, messageId: '1')))
        ..emit(DanmakuReceived(_gift('乙', '告白气球', value: 52000, messageId: '2')));
      expect([for (final message in flown) message.message], ['聊天', '乙 送出 告白气球 ×1']);
      expect(flown.last.type, LiveMessageType.gift);
      expect(giftLines(controller), ['甲 小心心 ×1', '乙 告白气球 ×1'], reason: 'the list is unchanged');
      controller.dispose();
    });

    test('they fly with the list switch off too; blocked viewers do not fly', () async {
      await store.blockLists.add(BlockKind.user, '捣乱的');
      final (controller, flown) = await open(
        settings: {Settings.danmakuShowGifts: true, Settings.showChatGifts: false},
      );
      danmaku
        ..emit(DanmakuReceived(_gift('捣乱的', '火箭', value: 500000, messageId: '1')))
        ..emit(DanmakuReceived(_gift('乙', '火箭', value: 500000, messageId: '2')));
      expect(giftLines(controller), isEmpty);
      expect([for (final message in flown) message.message], ['乙 送出 火箭 ×1']);
      controller.dispose();
    });

    test('no flood under a combo: 40 hits of a valuable gift fly once while it goes on; 3 a second', () async {
      final (controller, flown) = await open(settings: {Settings.danmakuShowGifts: true});
      for (var i = 0; i < 40; i++) {
        danmaku.emit(DanmakuReceived(_gift('甲', '告白气球', value: 52000, comboKey: 'c', messageId: 'c$i')));
      }
      expect(flown, hasLength(1));
      expect(giftLines(controller), ['甲 告白气球 ×40'], reason: 'the list merges them (D07.1)');
      for (var i = 0; i < 6; i++) {
        danmaku.emit(DanmakuReceived(_gift('观众$i', '飞机', value: 100000, messageId: 'p$i')));
      }
      expect(flown, hasLength(3), reason: 'the same second: 3 at most');
      controller.dispose();
    });

    test('turned off: no gift flies', () async {
      final (controller, flown) = await open(settings: {Settings.danmakuShowGifts: true});
      await store.settings.set(Settings.danmakuShowGifts, false);
      danmaku.emit(DanmakuReceived(_gift('甲', '火箭', value: 500000, messageId: '1')));
      expect(flown, isEmpty);
      controller.dispose();
    });
  });

  test("the threshold is the gift line's: valuable from 10 yuan (A08.11 G1)", () {
    expect(
      giftShownTier(const LiveGift(name: 'a', totalValue: 9999, unit: LiveGiftUnit.goldSeed)),
      LiveGiftTier.normal,
    );
    expect(
      giftShownTier(const LiveGift(name: 'a', totalValue: 10000, unit: LiveGiftUnit.goldSeed)),
      LiveGiftTier.valuable,
    );
    expect(debugDefaultTargetPlatformOverride, isNull);
  });
}
