// D07.2 (docs/D-弹幕/D07-礼物和付费消息/D07.2-醒目留言平台表和价格单位): super chat prices in
// each platform's unit, memberships and subscriptions as cards among the
// super chats ("上舰和开会员进醒目留言", on by default, D-040) while the chat
// list keeps its one line, and Six Rooms' fly-screens as super chats; the
// cards at 280 wide, with 2x text, in the three themes. The messages come
// from the real adapters, from recorded samples where there are some.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/features/live_play/danmaku/super_chats.dart';
import 'package:pure_live/features/live_play/logic/membership_cards.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';

import '../../support.dart';
import 'live_play_support.dart';
import 'no_images.dart';

/// The three themes the cards are checked in.
final Map<String, ThemeData> _themes = {
  'light': const LiveTheme().light,
  'dark': const LiveTheme().dark,
  'pure black': const LiveTheme(pureBlack: true).dark,
};

const String _fixtures = '../../fixtures';

List<Map<String, Object?>> _lines(String path) => [
  for (final line in File('$_fixtures/$path/frames.jsonl').readAsLinesSync())
    if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
];

/// A Bilibili notice packet (operation 5) holding [json].
Uint8List _bilibiliPacket(Object? json) {
  final body = utf8.encode(jsonEncode(json));
  final bytes = Uint8List(16 + body.length);
  ByteData.sublistView(bytes)
    ..setUint32(0, bytes.length)
    ..setUint16(4, 16)
    ..setUint16(6, 0)
    ..setUint32(8, 5)
    ..setUint32(12, 1);
  bytes.setRange(16, bytes.length, body);
  return bytes;
}

List<LiveMessage> _bilibiliMessages(Uint8List packet) => [
  for (final item in BilibiliDanmakuProtocol.decode(packet).items)
    if (item case BilibiliDanmakuMessage(:final message)) message,
];

/// A `GUARD_BUY` (synthetic: no recording has one; the fields D07.4 reads):
/// [level] 3 舰长, 2 提督, 1 总督, [months] at [price] gold seeds each.
LiveMessage _guard({
  int level = 3,
  int months = 1,
  int price = 198000,
  String user = '舰长大人',
  String uid = '1000001',
  DateTime? at,
}) => _bilibiliMessages(
  _bilibiliPacket({
    'cmd': 'GUARD_BUY',
    'data': {
      'uid': uid,
      'username': user,
      'guard_level': level,
      'num': months,
      'price': price,
      'gift_id': 10000 + level,
      'gift_name': switch (level) {
        1 => '总督',
        2 => '提督',
        _ => '舰长',
      },
      if (at != null) 'start_time': at.millisecondsSinceEpoch ~/ 1000,
    },
  }),
).single;

/// Bilibili's recorded super chats (fixtures/bilibili/danmaku/S13-protover3).
List<LiveSuperChatMessage> _bilibiliSuperChats() => [
  for (final line in _lines('bilibili/danmaku/S13-protover3'))
    if (line['dir'] == 'in')
      for (final message in _bilibiliMessages(base64Decode(line['b64']! as String)))
        if (message.data case final LiveSuperChatMessage superChat) superChat,
];

/// CHZZK's recorded recent chat (fixtures/chzzk/danmaku/S11-recent).
List<LiveMessage> _chzzk() => [
  for (final line in _lines('chzzk/danmaku/S11-recent'))
    if (line['dir'] == 'in' && line['url'] == null) ...ChzzkDanmakuProtocol.decode(line['text']! as String).messages,
];

/// Twitch's recorded messages (fixtures/twitch/danmaku/S09-live) as the
/// connection reports them: a community gift is its announcement only
/// (D07.6), the subscriptions it gives are left out.
List<LiveMessage> _twitch() => [
  for (final line in _lines('twitch/danmaku/S09-live'))
    if (line['dir'] == 'in')
      if (TwitchDanmakuProtocol.decode(line['text']! as String) case final frame)
        for (final message in frame.messages)
          if (!(frame.communityGifts[message]?.announcement == false)) message,
];

/// YouTube's recorded answer with a new member and a milestone
/// (fixtures/youtube/danmaku/S10-live-all-chat, its eighth frame).
List<LiveMessage> _youtube() =>
    YouTubeDanmakuProtocol.chat(jsonDecode(_lines('youtube/danmaku/S10-live-all-chat')[7]['text']! as String)).messages;

/// A Six Rooms fly-screen (108) with the fields the room page's script
/// reads (`Room.GiftFly.add`: `from`, `content`, `fpic`, `ftype`; the user
/// id and time as on a chat line). No recording has one: four of the
/// hottest rooms for 40 minutes on 2026-10-09 sent none.
LiveMessage _fly({String from = '观众3', String content = '主播生日快乐', DateTime? at}) => SixRoomDanmakuProtocol.fly({
  'typeID': 108,
  'from': from,
  'fid': '10000003',
  'content': content,
  'fpic': 'https://vi0.6rooms.com/x.jpg',
  'ftype': 0,
  if (at != null) 'tm': at.millisecondsSinceEpoch ~/ 1000,
})!;

void main() {
  setUpAll(loadStrings);
  final now = DateTime(2026, 10, 9, 20);

  group('prices in the platform unit (c2)', () {
    test('the recorded and adapter-made super chats of each platform', () {
      final bilibili = _bilibiliSuperChats();
      expect(bilibili, isNotEmpty);
      expect(superChatPrice(bilibili.first), '30 元', reason: '3.x wrote ￥30');
      expect(bilibili.map((superChat) => superChat.unit), everyElement(LiveGiftUnit.yuan));
      final donations = [
        for (final message in _chzzk())
          if (message.data case final LiveSuperChatMessage superChat) superChat,
      ];
      expect(donations.map(superChatPrice), contains('1,820 치즈'), reason: "the platform's own text");
      final fly = _fly().data! as LiveSuperChatMessage;
      expect(superChatPrice(fly), '1000 六币');
      // Missevan, KilaKila, 17LIVE, Kick, Picarto and YouTube write their
      // price; the text wins over the unit.
      for (final (price, unit, text) in [
        (50, LiveGiftUnit.diamond, '50 钻'),
        (1000, LiveGiftUnit.redBean, '1,000红豆'),
        (79, LiveGiftUnit.point, '79 coins'),
        (500, LiveGiftUnit.kicks, '500 Kicks'),
        (5, LiveGiftUnit.other, '5 Kudos'),
        (550, LiveGiftUnit.other, 'TRY 550.00'),
      ]) {
        expect(
          superChatPrice(
            LiveSuperChatMessage(
              userName: 'a',
              face: '',
              message: '',
              price: price,
              priceText: text,
              unit: unit,
              startTime: now,
              endTime: now,
              backgroundColor: '',
              backgroundBottomColor: '',
            ),
          ),
          text,
        );
      }
    });

    test('without a text: the unit in words (yuan, gold seeds, diamonds, Bits, six coins), never ￥', () {
      String price(int price, LiveGiftUnit unit) => superChatPrice(
        LiveSuperChatMessage(
          userName: 'a',
          face: '',
          message: '',
          price: price,
          unit: unit,
          startTime: now,
          endTime: now,
          backgroundColor: '',
          backgroundBottomColor: '',
        ),
      );
      expect(price(30, LiveGiftUnit.yuan), '30 元');
      expect(price(3000, LiveGiftUnit.fen), '30 元');
      expect(price(1000, LiveGiftUnit.goldSeed), '1000 金瓜子');
      expect(price(50, LiveGiftUnit.diamond), '50 钻石');
      expect(price(100, LiveGiftUnit.bits), '100 Bits');
      expect(price(1000, LiveGiftUnit.cheese), '1000 奶酪');
      expect(price(1000, LiveGiftUnit.sixCoin), '1000 六币');
      expect(price(12, LiveGiftUnit.other), '12', reason: 'an unchecked unit: the number alone');
      expect(price(0, LiveGiftUnit.yuan), '');
    });

    test('in English', () async {
      await loadStrings(AppLanguage.en);
      addTearDown(loadStrings);
      expect(superChatPrice(_bilibiliSuperChats().first), '¥30');
      // Large amounts the way the gift line writes them (A08.11).
      expect(superChatPrice(_fly().data! as LiveSuperChatMessage), '1k six coins');
    });
  });

  group('membership cards (c3)', () {
    test("a Bilibili guard: the price in yuan, the gift's sentence, a Bilibili super chat's time", () {
      final card = membershipCard(
        _guard(at: now),
        platform: SiteIds.bilibili,
        now: now,
      )!;
      expect(isMembershipCard(card), isTrue);
      expect(
        (card.userName, card.message, card.price, card.unit, card.priceText),
        ('舰长大人', '开通 舰长 ×1 个月', 198, LiveGiftUnit.yuan, ''),
      );
      expect(superChatPrice(card), '198 元');
      expect(card.startTime, now);
      expect(card.endTime.difference(card.startTime), const Duration(minutes: 5));
      expect((card.face, card.backgroundColor, card.backgroundBottomColor), ('', '', ''));
      // 提督 for three months: 5994 yuan, two hours; 总督 a month: 19998.
      final admiral = membershipCard(_guard(level: 2, months: 3, price: 1998000), platform: 'bilibili', now: now)!;
      expect((admiral.message, superChatPrice(admiral)), ('开通 提督 ×3 个月', '5994 元'));
      expect(admiral.endTime.difference(admiral.startTime), const Duration(hours: 2));
      expect(admiral.startTime, now, reason: 'no platform time: now');
      // Without a price the card names what was bought.
      final unpriced = membershipCard(_guard(price: 0), platform: SiteIds.bilibili, now: now)!;
      expect(
        (superChatPrice(unpriced), unpriced.endTime.difference(unpriced.startTime)),
        ('舰长', const Duration(minutes: 1)),
      );
      // The same message twice is the same card.
      expect(
        membershipCard(
          _guard(at: now),
          platform: 'bilibili',
          now: now,
        ),
        card,
      );
    });

    test('Twitch (S09): a card for each subscription and community gift; its subscriptions are folded (D07.6)', () {
      final notices = [
        for (final message in _twitch())
          if (message.type == LiveMessageType.notice) message,
      ];
      final cards = [for (final notice in notices) ?membershipCard(notice, platform: SiteIds.twitch, now: now)];
      expect(cards, hasLength(notices.where((notice) => notice.data == LiveNoticeKind.subscription).length));
      expect(cards, isNotEmpty);
      final first = cards.first;
      expect((first.userName, first.message, superChatPrice(first)), ('pfxqwzmw', 'subscribed at Tier 1.', '订阅'));
      expect(first.endTime.difference(first.startTime), const Duration(minutes: 1));
      expect(
        cards.map((card) => card.message),
        contains("is gifting 1 Tier 1 Subs to ironmouse's community! They've gifted a total of 1 in the channel!"),
      );
      expect(cards.map((card) => card.message), isNot(contains('gifted a Tier 1 sub to yjjgig81!')));
    });

    test('CHZZK (S11, a subscription notice since D07.6) and YouTube (S10, memberships)', () {
      final chzzk = [for (final message in _chzzk()) ?membershipCard(message, platform: SiteIds.chzzk, now: now)];
      expect(chzzk.single.userName, '观众132');
      // D07.6's notice; the subscriber's words stay a chat line of their own.
      expect(chzzk.single.message, '订阅了「나나양 좋아」，已订阅 32 个月');
      expect(superChatPrice(chzzk.single), '订阅');
      final youtube = [for (final message in _youtube()) ?membershipCard(message, platform: SiteIds.youtube, now: now)];
      expect(
        [for (final card in youtube) (card.userName, card.message, superChatPrice(card))],
        [
          ('@p5x7pg0pdlzzv', 'Welcome to 生贄の祭壇!', '会员'),
          ('@3y3cwq', 'Member for 65 months（生贄の祭壇）：今年もおめでとーーーーーーーー！！ まだ末長くよろしくお願いしますなぁ〜(*´ω｀*)', '会员'),
        ],
      );
    });

    test('chat, gifts, super chats, other notices and a share have none', () {
      for (final message in [
        const LiveMessage(type: LiveMessageType.chat, userName: 'a', message: 'hi', color: LiveMessageColor.white),
        const LiveMessage(
          type: LiveMessageType.gift,
          userName: 'a',
          message: '小心心 ×1',
          color: LiveMessageColor.white,
          data: LiveGift(name: '小心心', totalValue: 1000, unit: LiveGiftUnit.goldSeed),
        ),
        _fly(),
        for (final kind in [LiveNoticeKind.system, LiveNoticeKind.raid, LiveNoticeKind.giftedSubscription])
          LiveMessage(
            type: LiveMessageType.notice,
            userName: 'a',
            message: 'a b',
            color: LiveMessageColor.white,
            data: kind,
          ),
        const LiveMessage(
          type: LiveMessageType.notice,
          userName: 'a',
          message: ' ',
          color: LiveMessageColor.white,
          data: LiveNoticeKind.subscription,
        ),
      ]) {
        expect(
          membershipCard(message, platform: SiteIds.twitch, now: now),
          isNull,
          reason: message.message,
        );
      }
    });
  });

  group('the room', () {
    late LiveStore store;
    late FakeDanmaku danmaku;
    late PlaybackSession session;

    setUp(() async {
      store = await LiveStore.memory(cipher: FakeCipher());
      danmaku = FakeDanmaku();
      session = fakeSession(FakeEngine());
    });

    tearDown(() async {
      await session.dispose();
      await store.close();
    });

    Future<LiveRoomController> open({
      String platform = SiteIds.bilibili,
      Map<Setting<Object>, Object> settings = const {},
    }) async {
      for (final MapEntry(:key, :value) in settings.entries) {
        await store.settings.set(key, value);
      }
      final site = FakeSite(liveRoom())..siteId = platform;
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
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return controller;
    }

    /// The list's lines of the platform's messages, by kind.
    List<String> lines(LiveRoomController controller) => [
      for (final line in controller.chat.lines)
        if (line.kind != ChatLineKind.system) '${line.kind.name} ${line.text}',
    ];

    test('on by default (D-040): a guard is a card among the super chats; the list keeps one gift line', () async {
      expect(Settings.superChatIncludesMembership.defaultValue, isTrue);
      final controller = await open();
      danmaku.emit(DanmakuReceived(_guard(at: now)));
      expect([for (final card in controller.superChats) (card.userName, superChatPrice(card))], [('舰长大人', '198 元')]);
      // No duplicate: the event is the gift line only, no super chat line.
      expect(lines(controller), ['gift 舰长 ×1']);
      controller.dispose();
    });

    test('off: no card, and the list is exactly the same', () async {
      final controller = await open(settings: {Settings.superChatIncludesMembership: false});
      danmaku.emit(DanmakuReceived(_guard(at: now)));
      expect(controller.superChats, isEmpty);
      expect(lines(controller), ['gift 舰长 ×1']);
      controller.dispose();
    });

    test('turned off: the cards leave at once, the real super chats and the lines stay', () async {
      final controller = await open();
      final bilibili = _bilibiliSuperChats().first;
      final paid = LiveSuperChatMessage(
        messageId: bilibili.messageId,
        userName: bilibili.userName,
        face: '',
        message: bilibili.message,
        price: bilibili.price,
        unit: bilibili.unit,
        startTime: now,
        endTime: now.add(const Duration(minutes: 1)),
        backgroundColor: bilibili.backgroundColor,
        backgroundBottomColor: bilibili.backgroundBottomColor,
      );
      var notified = 0;
      controller.addListener(() => notified++);
      danmaku
        ..emit(DanmakuReceived(_guard(at: now)))
        ..emit(
          DanmakuReceived(
            LiveMessage(
              type: LiveMessageType.superChat,
              userName: 'SUPER_CHAT_MESSAGE',
              message: 'SUPER_CHAT_MESSAGE',
              color: LiveMessageColor.white,
              data: paid,
            ),
          ),
        );
      expect(controller.superChats, hasLength(2));
      final before = notified;
      await store.settings.set(Settings.superChatIncludesMembership, false);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.superChats, [paid]);
      expect(notified, greaterThan(before));
      expect(lines(controller), ['gift 舰长 ×1', 'superChat ${paid.message}']);
      danmaku.emit(DanmakuReceived(_guard(user: '又一位', uid: '2', at: now)));
      expect(controller.superChats, [paid]);
      controller.dispose();
    });

    test('with the gift lines off the card still comes; a blocked viewer gets none', () async {
      await store.blockLists.add(BlockKind.user, '捣乱的');
      final controller = await open(settings: {Settings.showChatGifts: false});
      danmaku
        ..emit(DanmakuReceived(_guard(user: '捣乱的', uid: '9', at: now)))
        ..emit(DanmakuReceived(_guard(at: now)));
      expect([for (final card in controller.superChats) card.userName], ['舰长大人']);
      expect(lines(controller), isEmpty, reason: 'the list shows no gifts');
      controller.dispose();
    });

    test("a subscription notice (CHZZK's, recorded): the notice line and a card", () async {
      final controller = await open(platform: SiteIds.chzzk);
      final notice = _chzzk().singleWhere((message) => message.data == LiveNoticeKind.subscription);
      // Its time is the recording's: a card shown from now.
      final fresh = LiveMessage(
        type: notice.type,
        userName: notice.userName,
        userId: notice.userId,
        message: notice.message,
        messageId: notice.messageId,
        color: notice.color,
        data: notice.data,
      );
      danmaku.emit(DanmakuReceived(fresh));
      expect(lines(controller), ['notice ${notice.message}'], reason: 'the notice only; no super chat line');
      expect([for (final card in controller.superChats) superChatPrice(card)], ['订阅']);
      // A share of a community gift is the notice line only.
      danmaku.emit(
        const DanmakuReceived(
          LiveMessage(
            type: LiveMessageType.notice,
            userName: 'gifter',
            message: 'gifter gifted a Tier 1 sub to someone!',
            color: LiveMessageColor.white,
            data: LiveNoticeKind.giftedSubscription,
          ),
        ),
      );
      expect(controller.superChats, hasLength(1));
      expect(lines(controller), hasLength(2));
      controller.dispose();
    });

    test('a Six Rooms fly-screen is a super chat: the tab and one super chat line, 1000 六币 (c5)', () async {
      final controller = await open(platform: SiteIds.sixRoom);
      danmaku.emit(DanmakuReceived(_fly(at: now)));
      expect([for (final paid in controller.superChats) (paid.userName, superChatPrice(paid))], [('观众3', '1000 六币')]);
      expect(lines(controller), ['superChat 主播生日快乐']);
      expect(controller.chat.lines.where((line) => line.kind == ChatLineKind.chat), isEmpty, reason: 'no longer chat');
      controller.dispose();
    });
  });

  group('the super chat tab (c3, c5): 360 and 280 wide, 2x text, three themes', () {
    for (final MapEntry(key: name, value: theme) in _themes.entries) {
      for (final (width, scale) in [(360.0, 1.0), (280.0, 1.0), (280.0, 2.0), (240.0, 2.0)]) {
        testWidgets('$name, $width wide, ${scale}x text: a guard, a subscription and a fly-screen fit', (tester) async {
          tester.view
            ..physicalSize = const Size(400, 3000)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final cards = [
            membershipCard(
              _guard(user: '一个名字很长很长的舰长大人', at: now),
              platform: SiteIds.bilibili,
              now: now,
            )!,
            membershipCard(
              _chzzk().singleWhere((message) => message.data == LiveNoticeKind.subscription),
              platform: SiteIds.chzzk,
              now: now,
            )!,
            _fly(at: now).data! as LiveSuperChatMessage,
          ];
          await tester.pumpWidget(
            LiveUiScope(
              config: LiveUiConfig(imageCacheManager: NoImages()),
              child: MaterialApp(
                theme: theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: width,
                      height: 3000,
                      child: SuperChatList(messages: cards, now: () => now, platformName: '哔哩哔哩'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.byKey(const ValueKey('super-chat-card')), findsNWidgets(3));
          final prices = [
            for (final element in find.byKey(const ValueKey('super-chat-price')).evaluate())
              (element.widget as Text).data,
          ];
          // Newest first: the fly-screen, the subscription, the guard.
          expect(prices, ['1000 六币', '订阅', '198 元']);
          expect(
            find.byKey(const ValueKey('super-chat-head-stacked')),
            // The list's 10 px each side: a 280 column's cards are 260 wide.
            scale > 1 || width - 20 < 280 ? findsNWidgets(3) : findsNothing,
            reason: '3.x: stacked under 280 or with larger text',
          );
          for (final element in find.byKey(const ValueKey('super-chat-card')).evaluate()) {
            expect(tester.getRect(find.byWidget(element.widget)).right, lessThanOrEqualTo(width));
          }
        });
      }
    }
  });
}
