// A08.11 (docs/A-界面设计/A08-弹幕界面/A08.11-礼物行的样子): one gift line for every
// platform: the picture or the gift icon, the name role, "送出", the gift's
// name, "×N" and the value (c1), the card (c2), the tier marks (c3), the
// combo pulse (c4), "显示用户名" off (c5), the 280 column and large text
// (c6), the long press and double tap (c7), the words in both languages
// (c8); the gifts come from the real adapters where a sample or a packet
// shape is known.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/image_cache.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/features/live_play/danmaku/gift_line.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/danmaku/chat_list_settings.dart';

import '../../support.dart';
import 'live_play_support.dart';
import 'no_images.dart';

/// The three themes the line is checked in.
final Map<String, ThemeData> _themes = {
  'light': const LiveTheme().light,
  'dark': const LiveTheme().dark,
  'pure black': const LiveTheme(pureBlack: true).dark,
};

// --- Gifts from the adapters ------------------------------------------------

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

LiveMessage _bilibili(Map<String, Object?> notice) => [
  for (final item in BilibiliDanmakuProtocol.decode(_bilibiliPacket(notice)).items)
    if (item case BilibiliDanmakuMessage(:final message)) message,
].single;

/// 3000 gold seeds: 3 yuan, normal.
LiveMessage _bilibiliGift() => _bilibili({
  'cmd': 'SEND_GIFT',
  'data': {
    'giftName': '小心心',
    'giftId': 30607,
    'num': 3,
    'uname': '观众',
    'uid': 1,
    'coin_type': 'gold',
    'total_coin': 3000,
    'batch_combo_id': 'batch:gift:combo_id:1',
  },
});

/// A combo of 20 at 20 000 gold seeds: 20 yuan, valuable.
LiveMessage _bilibiliCombo() => _bilibili({
  'cmd': 'COMBO_SEND',
  'data': {
    'gift_name': '小心心',
    'gift_id': 30607,
    'total_num': 20,
    'combo_total_coin': 20000,
    'uname': '观众',
    'uid': 1,
    'batch_combo_id': 'batch:gift:combo_id:1',
  },
});

/// 舰长 for a month: 198 yuan, precious.
LiveMessage _bilibiliGuard() => _bilibili({
  'cmd': 'GUARD_BUY',
  'data': {
    'uid': 1000001,
    'username': '舰长大人',
    'guard_level': 3,
    'num': 1,
    'price': 198000,
    'gift_id': 10003,
    'gift_name': '舰长',
  },
});

/// A silver gift: free.
LiveMessage _bilibiliSilver() => _bilibili({
  'cmd': 'SEND_GIFT',
  'data': {'giftName': '辣条', 'num': 5, 'uname': '观众', 'uid': 2, 'coin_type': 'silver', 'total_coin': 500},
});

/// A guest's recorded gifts (fixtures/bilibili/danmaku/S13-guest-gifts, D07.4):
/// 50 SEND_GIFT_V2 and one COMBO_SEND.
List<LiveMessage> _bilibiliGuests() => [
  for (final line in File('../../fixtures/bilibili/danmaku/S13-guest-gifts/frames.jsonl').readAsLinesSync())
    for (final item in BilibiliDanmakuProtocol.decode(
      base64Decode((jsonDecode(line) as Map<String, Object?>)['b64']! as String),
    ).items)
      if (item case BilibiliDanmakuMessage(:final message)) message,
];

/// Douyu's recorded gifts (fixtures/douyu/danmaku/S15-gifts).
List<LiveMessage> _douyu() {
  final sample = jsonDecode(
    File('../../fixtures/douyu/danmaku/S15-gifts/packets.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final frame = [
    for (final body in sample['packets']! as List<Object?>)
      ...DouyuDanmakuProtocol.packet(body! as String, type: DouyuDanmakuProtocol.serverPacketType),
  ];
  return DouyuDanmakuProtocol.decode(frame, roomId: sample['roomId']! as String);
}

/// Missevan's recorded events (fixtures/missevan/danmaku/S09-events): 16 is
/// a free 幻彩礼炮 with its picture, 18 a 书写星辰 of 28 diamonds.
LiveMessage _missevan(int index) {
  final lines = File('../../fixtures/missevan/danmaku/S09-events/frames.jsonl').readAsLinesSync();
  final frames = [
    for (final line in lines)
      if (jsonDecode(line) case {'room': final String room, 'b64': final String b64})
        (room: room, data: base64Decode(b64)),
  ];
  final frame = frames[index];
  return MissevanDanmakuProtocol.decode(frame.data, roomId: frame.room, uuid: 'u').messages.single;
}

/// A Kick gift of [amount] Kicks without a message (Pusher's frame).
LiveMessage _kick(int amount) => KickDanmakuProtocol.read(
  jsonEncode({
    'event': 'KicksGifted',
    'data': jsonEncode({
      'sender': {'id': 5, 'username': 'patron'},
      'gift': {'name': 'Hype', 'amount': amount},
    }),
    'channel': 'chatrooms.3852600.v2',
  }),
  const KickDanmakuArgs(chatroomId: 3852600, channelId: 3862536, slug: 'lonche'),
).messages.single;

/// A gift message holding [gift] as an adapter reports it.
LiveMessage _of(LiveGift gift, {String user = '观众', String fans = '', String level = ''}) => LiveMessage(
  type: LiveMessageType.gift,
  userName: user,
  userId: user,
  message: gift.plainText,
  color: LiveMessageColor.white,
  data: gift,
  fansName: fans,
  fansLevel: level,
);

// --- Pumping ----------------------------------------------------------------

Future<void> _pumpLine(
  WidgetTester tester,
  LiveMessage message, {
  ChatListStyle style = ChatListStyle.compact,
  bool showName = true,
  ThemeData? theme,
  double width = 360,
  double textScale = 1,
  bool still = false,
  GiftLineRoom room = GiftLineRoom.none,
  int id = 1,
  int revision = 0,
}) async {
  final line = ChatLine.gift(message, revision: revision)..id = id;
  await tester.pumpWidget(
    LiveUiScope(
      config: LiveUiConfig(imageCacheManager: NoImages()),
      child: MaterialApp(
        theme: theme ?? const LiveTheme().light,
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale), disableAnimations: still),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: ChatLineView(key: ValueKey(id), line: line, style: style, showName: showName, giftRoom: room),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The span that says [text] in the gift line, or null.
TextSpan? _span(WidgetTester tester, String text) {
  TextSpan? found;
  for (final widget in tester.widgetList<RichText>(
    find.descendant(of: find.byType(GiftLine), matching: find.byType(RichText)),
  )) {
    widget.text.visitChildren((span) {
      if (span is TextSpan && span.text == text) found = span;
      return found == null;
    });
    if (found != null) return found;
  }
  return null;
}

/// The words of the line's text, its pieces included, in order.
String _said(WidgetTester tester) {
  final rich = tester.widget<RichText>(
    find.descendant(of: find.byKey(const ValueKey('live-play-gift-text')), matching: find.byType(RichText)).first,
  );
  final out = StringBuffer();
  rich.text.visitChildren((span) {
    if (span is TextSpan) out.write(span.text ?? '');
    if (span is WidgetSpan) {
      for (final text in tester.widgetList<Text>(
        find.descendant(of: find.byWidget(span.child), matching: find.byType(Text)),
      )) {
        out.write(text.data ?? '');
      }
    }
    return true;
  });
  return out.toString();
}

Text _piece(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(ValueKey(key)));

String? _value(WidgetTester tester) {
  final value = find.byKey(const ValueKey('live-play-gift-value'));
  return value.evaluate().isEmpty ? null : tester.widget<Text>(value).data;
}

/// The gift line whose words contain [text].
Finder _lineSaying(String text) => find.ancestor(
  of: find.textContaining(text, findRichText: true),
  matching: find.byKey(const ValueKey('live-play-gift-line')),
);

/// The combo pulse of a gift line.
Finder get _pulses => find.descendant(of: find.byType(GiftLine), matching: find.byType(ScaleTransition));

Color _ground(ThemeData theme, ChatListStyle style) =>
    style == ChatListStyle.card ? theme.colorScheme.surfaceContainerLowest : theme.colorScheme.surface;

void main() {
  late BaseCacheManager? images;
  setUpAll(loadStrings);
  setUp(() {
    images = AppImageCache.manager;
    AppImageCache.manager = NoImages();
  });
  tearDown(() => AppImageCache.manager = images);

  group('c1, c8: what the line says, every platform through its adapter', () {
    testWidgets('Bilibili: gold, a combo, 舰长 and a silver gift', (tester) async {
      await _pumpLine(tester, _bilibiliGift());
      expect(_said(tester), '观众 送出 小心心 ×33000 金瓜子');
      expect(_span(tester, '送出 '), isNotNull);
      expect(_piece(tester, 'live-play-gift-count').data, '×3');
      expect(_value(tester), '3000 金瓜子');

      await _pumpLine(tester, _bilibiliCombo());
      expect(_piece(tester, 'live-play-gift-count').data, '×20');
      expect(_value(tester), '2万 金瓜子');

      await _pumpLine(tester, _bilibiliGuard());
      expect(_span(tester, '开通 '), isNotNull, reason: 'a membership is bought');
      expect(_piece(tester, 'live-play-gift-count').data, '×1 个月');
      expect(_value(tester), '19.8万 金瓜子');

      await _pumpLine(tester, _bilibiliSilver());
      expect(_piece(tester, 'live-play-gift-count').data, '×5');
      expect(_value(tester), isNull, reason: 'a free gift shows no value');
    });

    testWidgets('Bilibili guests (D07.4, S13-guest-gifts through the parser): picture, value, fan medal, receiver', (
      tester,
    ) async {
      final gifts = _bilibiliGuests();
      const room = GiftLineRoom(platform: SiteIds.bilibili, streamer: '主播');
      await _pumpLine(tester, gifts.first, room: room);
      expect(_said(tester), contains('想*** 送出 牛哇牛哇 ×1100 金瓜子'));
      expect(find.byKey(const ValueKey('live-play-gift-image')), findsOneWidget, reason: 'the packet has the picture');
      expect(find.byKey(const ValueKey('live-play-chat-fans')), findsOneWidget, reason: 'the fan medal, as on chat');
      expect(_value(tester), '100 金瓜子');
      expect(find.byKey(const ValueKey('live-play-gift-tier-valuable')), findsNothing, reason: '0.1 yuan: normal');
      // Another room's streamer: the receiver is named.
      await _pumpLine(tester, gifts.first);
      expect(_span(tester, '送给 主播 '), isNotNull);
      // The combo's COMBO_SEND: ×2, 200 gold seeds.
      await _pumpLine(tester, gifts.firstWhere((m) => m.gift!.comboTotal != null), room: room);
      expect(_piece(tester, 'live-play-gift-count').data, '×2');
      expect(_value(tester), '200 金瓜子');
      // A guard bought, with the table's picture: precious.
      final table = BilibiliApi.giftCatalog(
        File('../../fixtures/bilibili/S18-gift-config/body.json').readAsStringSync(),
      );
      final guard = BilibiliDanmakuProtocol.decode(
        _bilibiliPacket({
          'cmd': 'GUARD_BUY',
          'data': {'uid': 1, 'username': '观众', 'guard_level': 3, 'num': 1, 'price': 198000, 'gift_name': '舰长'},
        }),
        gifts: table,
      ).items.whereType<BilibiliDanmakuMessage>().single.message;
      await _pumpLine(tester, guard, room: room);
      expect(find.byKey(const ValueKey('live-play-gift-image')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-play-gift-tier-precious')), findsOneWidget);
    });

    testWidgets('Douyu (S15-gifts): the combo count, the streamer not named as receiver', (tester) async {
      final gifts = _douyu();
      final first = gifts.first;
      await _pumpLine(
        tester,
        first,
        room: const GiftLineRoom(platform: SiteIds.douyu, streamer: '若若跑的贼快'),
      );
      expect(_span(tester, '送出 '), isNotNull);
      expect(_span(tester, '精英宝典'), isNotNull);
      expect(_value(tester), isNull, reason: 'Douyu gives no price');
      // Another room's streamer: the receiver is named.
      await _pumpLine(tester, first);
      expect(_span(tester, '送给 若若跑的贼快 '), isNotNull);
      // A combo hit shows the running count.
      final combo = gifts.firstWhere((m) => (m.gift!.comboTotal ?? 0) > m.gift!.count);
      await _pumpLine(
        tester,
        combo,
        room: const GiftLineRoom(platform: SiteIds.douyu, streamer: '若若跑的贼快'),
      );
      expect(_piece(tester, 'live-play-gift-count').data, '×${combo.gift!.comboTotal}');
    });

    testWidgets('Missevan (S09-events): diamonds, a free gift, the picture', (tester) async {
      await _pumpLine(tester, _missevan(18));
      expect(_value(tester), '28 钻石');
      expect(find.byKey(const ValueKey('live-play-gift-image')), findsOneWidget);
      await _pumpLine(tester, _missevan(16));
      expect(_value(tester), isNull);
    });

    testWidgets('Kick: the Kicks are the value again (E05.5 took them out of the text)', (tester) async {
      await _pumpLine(tester, _kick(100));
      expect(_said(tester), 'patron 送出 Hype ×1100 Kicks');
      await _pumpLine(tester, _kick(0));
      expect(_value(tester), isNull);
    });

    testWidgets('niconico, KilaKila, Huya, YouTube, Baidu: their classes', (tester) async {
      // niconico: the points and the giver's rank (E05.5 took both out).
      await _pumpLine(tester, _of(const NiconicoGift(itemId: 'x', name: 'ぶんぶんみゅーと', point: 100, contributionRank: 3)));
      expect(_value(tester), '100 点 · 贡献第 3 名');
      await _pumpLine(tester, _of(const NiconicoGift(itemId: 'x', name: 'タダ', point: 0)));
      expect(_value(tester), isNull);
      // KilaKila: a guest receives it; red beans.
      await _pumpLine(tester, _of(const KilakilaGift(id: '1', name: '念念相守', count: 3, price: 30, receiverName: '豆咖')));
      expect(_span(tester, '送给 豆咖 '), isNotNull);
      expect(_value(tester), '30 红豆');
      // Huya: lPayTotal's unit is not known, so no value.
      await _pumpLine(tester, _of(const HuyaGift(id: '4', name: '虎粮', count: 1, combo: 3, payTotal: 10)));
      expect(_piece(tester, 'live-play-gift-count').data, '×3');
      expect(_value(tester), isNull);
      // YouTube: the picture, no value.
      await _pumpLine(
        tester,
        _of(YouTubeGift(name: 'Donut', text: 'sent Donut', image: Uri.parse('https://example.invalid/donut.png'))),
      );
      expect(find.byKey(const ValueKey('live-play-gift-image')), findsOneWidget);
      // Baidu: free.
      await _pumpLine(tester, _of(const BaiduLiveGift(id: '1', name: '拍拍', count: 1, free: true)));
      expect(_value(tester), isNull);
    });

    testWidgets('English: the same line in the other language', (tester) async {
      await tester.runAsync(() => loadStrings(AppLanguage.en));
      addTearDown(() => tester.runAsync(loadStrings));
      await _pumpLine(tester, _bilibiliGuard());
      expect(_span(tester, 'bought '), isNotNull);
      expect(_piece(tester, 'live-play-gift-count').data, '×1 mo');
      expect(_value(tester), '198k gold seeds');
    });

    testWidgets('a message without a LiveGift still shows its text', (tester) async {
      const plain = LiveMessage(
        type: LiveMessageType.gift,
        userName: '观众',
        message: '辣条 ×10',
        color: LiveMessageColor.white,
      );
      await _pumpLine(tester, plain);
      expect(_span(tester, '辣条 ×10'), isNotNull);
      expect(find.byKey(const ValueKey('live-play-gift-icon')), findsOneWidget);
    });
  });

  group('c1: the picture', () {
    testWidgets('16 square, decoded at the drawn size; the gift icon while it loads and when it fails', (tester) async {
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await _pumpLine(tester, _missevan(18));
      final image = tester.widget<Image>(find.byKey(const ValueKey('live-play-gift-image')));
      final resized = image.image as ResizeImage;
      expect((resized.width, resized.height, resized.policy), (48, 48, ResizeImagePolicy.fit));
      expect(tester.getSize(find.byKey(const ValueKey('live-play-gift-image'))), const Size(16, 16));
      // Loading, then failed (no pictures in tests): the icon in its place.
      expect(find.byKey(const ValueKey('live-play-gift-icon')), findsOneWidget);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.byKey(const ValueKey('live-play-gift-icon')), findsOneWidget);
    });

    testWidgets('without a picture the icon takes the same place: the words start where they would', (tester) async {
      await _pumpLine(tester, _missevan(18));
      final withPicture = tester.getTopLeft(find.byKey(const ValueKey('live-play-gift-text')));
      await _pumpLine(tester, _bilibiliGift());
      expect(find.byKey(const ValueKey('live-play-gift-image')), findsNothing);
      final icon = tester.getSize(find.byKey(const ValueKey('live-play-gift-icon')));
      expect(icon, const Size(16, 16));
      expect(tester.getTopLeft(find.byKey(const ValueKey('live-play-gift-text'))), withPicture);
    });
  });

  group('c1, c3: roles, contrast and tiers in every theme and style', () {
    testWidgets('the verb secondary, the gift semibold tertiary, the value smaller; all at 4.5:1', (tester) async {
      for (final MapEntry(key: label, value: theme) in _themes.entries) {
        for (final style in ChatListStyle.values) {
          await _pumpLine(tester, _bilibiliGift(), style: style, theme: theme);
          final reason = '$label, $style';
          final ground = _ground(theme, style);
          final scheme = theme.colorScheme;
          final name = _span(tester, '观众 ')!.style!;
          final verb = _span(tester, '送出 ')!.style!;
          final gift = _span(tester, '小心心')!.style!;
          final count = _piece(tester, 'live-play-gift-count').style!;
          final value = _piece(tester, 'live-play-gift-value').style!;
          expect(name.fontWeight, FontWeight.w600, reason: '$reason: the name role');
          expect(verb.color, scheme.onSurfaceVariant, reason: reason);
          expect(verb.fontWeight, FontWeight.w400, reason: reason);
          expect(gift.color, scheme.tertiary, reason: reason);
          expect(gift.fontWeight, FontWeight.w600, reason: reason);
          expect(count.fontFeatures, contains(const FontFeature.tabularFigures()), reason: reason);
          expect(value.fontSize, lessThan(gift.fontSize!), reason: '$reason: one size smaller');
          for (final ink in [name.color!, verb.color!, gift.color!, count.color!, value.color!]) {
            expect(contrastRatio(ink, ground), greaterThanOrEqualTo(chatNameContrast), reason: reason);
          }
          // No background on the compact line (super chats and notices have one).
          if (style == ChatListStyle.compact) {
            expect(
              find.descendant(of: find.byType(GiftLine), matching: find.byType(DecoratedBox)),
              findsNothing,
              reason: reason,
            );
          } else {
            expect(find.byKey(const ValueKey('live-play-gift-card')), findsOneWidget, reason: reason);
          }
        }
      }
    });

    testWidgets('normal: no mark; valuable: a 2 wide tertiary mark; precious: 4 wide and the platform colour', (
      tester,
    ) async {
      for (final MapEntry(key: label, value: theme) in _themes.entries) {
        for (final style in ChatListStyle.values) {
          final reason = '$label, $style';
          final ground = _ground(theme, style);
          const room = GiftLineRoom(platform: SiteIds.bilibili);
          await _pumpLine(tester, _bilibiliGift(), style: style, theme: theme, room: room);
          expect(find.byKey(const ValueKey('live-play-gift-tier-valuable')), findsNothing, reason: reason);
          expect(find.byKey(const ValueKey('live-play-gift-tier-precious')), findsNothing, reason: reason);

          await _pumpLine(tester, _bilibiliCombo(), style: style, theme: theme, room: room);
          final valuable = find.byKey(const ValueKey('live-play-gift-tier-valuable'));
          expect(tester.getSize(valuable).width, 2, reason: reason);
          final valuableInk = (tester.widget<DecoratedBox>(valuable).decoration as BoxDecoration).color!;
          expect(valuableInk, theme.colorScheme.tertiary, reason: reason);
          expect(_span(tester, '小心心')!.style!.color, theme.colorScheme.tertiary, reason: reason);
          expect(tester.getSize(valuable).height, greaterThan(14), reason: '$reason: the height of the line');

          await _pumpLine(tester, _bilibiliGuard(), style: style, theme: theme, room: room);
          final precious = find.byKey(const ValueKey('live-play-gift-tier-precious'));
          expect(tester.getSize(precious).width, 4, reason: '$reason: twice as wide, not only another colour');
          final ink = _span(tester, '舰长')!.style!.color!;
          expect(ink, giftPlatformInk(SiteIds.bilibili, ground), reason: reason);
          expect(ink, isNot(theme.colorScheme.tertiary), reason: reason);
          expect(contrastRatio(ink, ground), greaterThanOrEqualTo(chatNameContrast), reason: reason);
          final markInk = (tester.widget<DecoratedBox>(precious).decoration as BoxDecoration).color!;
          expect(markInk, ink, reason: reason);
        }
      }
      // A platform without a colour: tertiary.
      await _pumpLine(tester, _bilibiliGuard());
      expect(_span(tester, '舰长')!.style!.color, const LiveTheme().light.colorScheme.tertiary);
    });

    testWidgets('the tier marks are named for screen readers', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpLine(tester, _bilibiliCombo());
      expect(find.bySemanticsLabel('值钱的礼物'), findsOneWidget);
      await _pumpLine(tester, _bilibiliGuard());
      expect(find.bySemanticsLabel('很值钱的礼物'), findsOneWidget);
      semantics.dispose();
    });

    test('G1: the thresholds and the table (giftUnitsPerYuan) as settled', () {
      expect((giftValuableYuan, giftPreciousYuan), (10, 100));
      expect(giftUnitsPerYuan, {
        LiveGiftUnit.fen: 100,
        LiveGiftUnit.goldSeed: 1000,
        LiveGiftUnit.diamond: 10,
        LiveGiftUnit.douyinCoin: 10,
        LiveGiftUnit.acCoin: 10,
        LiveGiftUnit.bits: 14,
        LiveGiftUnit.kicks: 14,
        LiveGiftUnit.cheese: 190,
        LiveGiftUnit.starBalloon: 1.7,
        LiveGiftUnit.point: 21,
      });
      // A combo climbs: the shown count's value decides.
      // 30 hits of 5 yuan: 150 yuan shown.
      const combo = LiveGift(name: '火箭', unitPrice: 500, unit: LiveGiftUnit.fen, totalValue: 500, comboTotal: 30);
      expect(
        (combo.tier, giftShownTier(combo), giftValueText(combo)),
        (LiveGiftTier.normal, LiveGiftTier.precious, '150 元'),
      );
      const cheap = LiveGift(name: '鱼丸', unitPrice: 10, unit: LiveGiftUnit.fen, totalValue: 10, comboTotal: 120);
      expect((giftShownTier(cheap), giftValueText(cheap)), (LiveGiftTier.valuable, '12 元'));
    });
  });

  group('c4: the combo', () {
    testWidgets('a new count changes only ×N, which grows to 1.2 and back in 200 ms', (tester) async {
      const one = DouyuGift(id: '824', name: '粉丝荧光棒', count: 1, combo: 1, comboKey: 'u:824');
      await _pumpLine(tester, _of(one));
      expect(_pulses, findsNothing, reason: 'nothing moves until the count changes');
      final words = _span(tester, '粉丝荧光棒');
      // D07.1 hands the line (same id) a message with the new count.
      await _pumpLine(tester, _of(const DouyuGift(id: '824', name: '粉丝荧光棒', count: 1, combo: 5, comboKey: 'u:824')));
      expect(_piece(tester, 'live-play-gift-count').data, '×5');
      expect(_span(tester, '粉丝荧光棒')!.style, words!.style, reason: 'the rest stays');
      final scale = find.ancestor(
        of: find.byKey(const ValueKey('live-play-gift-count')),
        matching: find.byType(ScaleTransition),
      );
      expect(scale, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<ScaleTransition>(scale).scale.value, closeTo(1.2, 0.05));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.widget<ScaleTransition>(scale).scale.value, 1);
    });

    testWidgets("D07.1's merged line (a new line, revision > 0) pulses ×N when first built", (tester) async {
      const one = DouyuGift(id: '824', name: '粉丝荧光棒', count: 1, combo: 1, comboKey: 'u:824');
      await _pumpLine(tester, _of(one));
      expect(_pulses, findsNothing);
      // The merge replaces the line: a new id, so a new widget.
      await _pumpLine(tester, _of(const DouyuGift(id: '824', name: '粉丝荧光棒', count: 1, combo: 2)), id: 2, revision: 1);
      expect(_piece(tester, 'live-play-gift-count').data, '×2');
      expect(_pulses, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<ScaleTransition>(_pulses).scale.value, closeTo(1.2, 0.05));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.widget<ScaleTransition>(_pulses).scale.value, 1);
    });

    testWidgets('with the system asking for less motion nothing moves', (tester) async {
      const one = DouyuGift(id: '824', name: '粉丝荧光棒', count: 1, combo: 1);
      await _pumpLine(tester, _of(one), still: true);
      await _pumpLine(tester, _of(const DouyuGift(id: '824', name: '粉丝荧光棒', count: 1, combo: 6)), still: true);
      expect(_piece(tester, 'live-play-gift-count').data, '×6');
      expect(_pulses, findsNothing);
    });
  });

  group('c5: "显示用户名" off', () {
    testWidgets('no name, badge or fan medal; 送出, the gift, ×N and the value stay', (tester) async {
      for (final style in ChatListStyle.values) {
        final message = _of(
          const LiveGift(name: '小心心', count: 3, totalValue: 3000, unit: LiveGiftUnit.goldSeed),
          user: '送礼人',
          fans: '小路泥',
          level: '22',
        );
        await _pumpLine(tester, message, style: style);
        expect(find.byKey(const ValueKey('live-play-chat-fans')), findsOneWidget, reason: '$style: on');
        await _pumpLine(tester, message, style: style, showName: false);
        expect(find.textContaining('送礼人', findRichText: true), findsNothing, reason: '$style');
        expect(find.byKey(const ValueKey('live-play-chat-fans')), findsNothing, reason: '$style');
        expect(_said(tester), '送出 小心心 ×33000 金瓜子', reason: '$style');
      }
    });
  });

  group('c6: the 280 column and large text', () {
    testWidgets('2x and 1.3x in 280, every theme and style: no overflow, the whole gift name, the value below', (
      tester,
    ) async {
      const long = '超级无敌豪华至尊梦幻嘉年华火箭';
      final message = _of(
        const LiveGift(name: long, count: 99, totalValue: 990000, unit: LiveGiftUnit.goldSeed),
        user: '一个非常非常长的观众昵称',
        fans: '小路泥',
        level: '22',
      );
      for (final MapEntry(key: label, value: theme) in _themes.entries) {
        for (final style in ChatListStyle.values) {
          for (final scale in [1.3, 2.0]) {
            await _pumpLine(tester, message, style: style, theme: theme, width: 280, textScale: scale);
            final reason = '$label, $style, $scale';
            expect(tester.takeException(), isNull, reason: reason);
            expect(tester.getSize(find.byType(ChatLineView)).width, 280, reason: reason);
            expect(_span(tester, long), isNotNull, reason: '$reason: the whole name');
            final rich = tester.widget<RichText>(
              find
                  .descendant(of: find.byKey(const ValueKey('live-play-gift-text')), matching: find.byType(RichText))
                  .first,
            );
            expect((rich.maxLines, rich.overflow), (null, TextOverflow.clip), reason: '$reason: wraps, never cut');
            // The value is one piece on a later line than the name's start.
            final value = tester.getRect(find.byKey(const ValueKey('live-play-gift-value')));
            final text = tester.getRect(find.byKey(const ValueKey('live-play-gift-text')));
            expect(value.top, greaterThan(text.top + 1), reason: reason);
            expect(value.right, lessThanOrEqualTo(text.right + 0.5), reason: '$reason: inside the line');
          }
        }
      }
    });

    testWidgets('the pieces scale once with the system text (a text in a WidgetSpan scaled twice)', (tester) async {
      for (final scale in [1.0, 2.0]) {
        await _pumpLine(tester, _bilibiliGift(), textScale: scale);
        final count = tester.getRect(find.byKey(const ValueKey('live-play-gift-count')));
        final body = const LiveTheme().light.textTheme.bodyLarge!;
        final line = body.fontSize! * (body.height ?? 1.5) * scale;
        expect(count.height, closeTo(line, line * 0.15), reason: '$scale');
        final icon = tester.getRect(find.byKey(const ValueKey('live-play-gift-icon')));
        expect(icon.size, const Size(16, 16), reason: '$scale: the picture keeps its size');
        final text = tester.getRect(find.byKey(const ValueKey('live-play-gift-text')));
        expect(icon.center.dy, closeTo(text.top + line / 2, 2), reason: '$scale: on the first line');
      }
    });
  });

  group('in the room', () {
    testWidgets('portrait: gifts from the adapter; long press opens the panel with the gift; double tap copies; '
        'the switch hides the lines', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final room = await _pumpRoom(tester);
      room.danmaku
        ..emit(const DanmakuReady())
        ..emit(DanmakuReceived(_bilibiliGift()))
        ..emit(DanmakuReceived(_bilibiliGuard()));
      await _frames(tester);
      expect(find.byType(GiftLine), findsNWidgets(2));
      expect(find.byKey(const ValueKey('live-play-gift-tier-precious')), findsOneWidget);
      // The room's platform colours the precious one.
      final ground = const LiveTheme().light.colorScheme.surface;
      expect(_span(tester, '舰长')!.style!.color, giftPlatformInk(SiteIds.bilibili, ground));

      await tester.longPress(_lineSaying('小心心'));
      await _settle(tester);
      final card = find.byKey(const ValueKey('live-play-message-card'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.textContaining('送出 小心心 ×3 · 3000 金瓜子', findRichText: true)),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('live-play-block-user')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('live-play-block-keyword')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('live-play-block-keyword')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('live-play-keyword-input'))).controller!.text, '小心心');
      await tester.tap(find.byKey(const ValueKey('message-panel-back')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('room-panel-close')).first);
      await tester.pumpAndSettle();

      await tester.tap(_lineSaying('舰长大人'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(_lineSaying('舰长大人'));
      await _settle(tester);
      expect(copied, '舰长大人: 开通 舰长 ×1 个月');

      await tester.runAsync(() => room.services.store.settings.set(Settings.showChatGifts, false));
      await _settle(tester);
      expect(find.byType(GiftLine), findsNothing);
      await _closeRoom(tester, room);
    });

    for (final (label, size) in [
      ('phone held sideways 869x400', const Size(869, 400)),
      ('wide 1280x800', const Size(1280, 800)),
    ]) {
      testWidgets('$label: the same line, both styles, no overflow', (tester) async {
        final room = await _pumpRoom(
          tester,
          size: size,
          platform: size.width > 1000 ? TargetPlatform.windows : TargetPlatform.android,
          settings: {Settings.danmakuListStyle: 'card'},
        );
        room.danmaku
          ..emit(const DanmakuReady())
          ..emit(DanmakuReceived(_bilibiliCombo()))
          ..emit(DanmakuReceived(_bilibiliGuard()));
        await _frames(tester);
        if (size.width < 1000) expect(find.byKey(const ValueKey('live-play-landscape-chat')), findsOneWidget);
        expect(find.byKey(const ValueKey('live-play-gift-card')), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await tester.runAsync(() => room.services.store.settings.set(Settings.danmakuListStyle, 'compact'));
        await _settle(tester);
        expect(find.byKey(const ValueKey('live-play-gift-card')), findsNothing);
        expect(find.byType(GiftLine), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await _closeRoom(tester, room);
      });
    }

    testWidgets('50 gifts: each line is built once, the list at most once a frame', (tester) async {
      final room = await _pumpRoom(tester);
      room.danmaku.emit(const DanmakuReady());
      await _frames(tester);
      var lines = 0;
      var gifts = 0;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        if (element.widget is ChatLineView) lines++;
        if (element.widget is GiftLine) gifts++;
      };
      try {
        for (var i = 0; i < 50; i++) {
          room.danmaku.emit(
            DanmakuReceived(
              _of(LiveGift(name: '礼物$i', count: i + 1, totalValue: i * 1000, unit: LiveGiftUnit.goldSeed)),
            ),
          );
          await tester.pump(const Duration(milliseconds: 8));
        }
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      expect(lines, lessThanOrEqualTo(50 + 2));
      expect(gifts, lessThanOrEqualTo(50 + 2));
      await _closeRoom(tester, room);
    });
  });
}

final class _Room {
  new(this.services, this.danmaku);

  final AppServices services;
  final FakeDanmaku danmaku;
}

Future<_Room> _pumpRoom(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  TargetPlatform platform = TargetPlatform.android,
  Map<Setting<Object>, Object> settings = const {},
}) async {
  debugDefaultTargetPlatformOverride = platform;
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(testServices))!;
  for (final MapEntry(:key, :value) in settings.entries) {
    await tester.runAsync(() => services.store.settings.set(key, value));
  }
  // Signed in: no guest hint over the list.
  await tester.runAsync(() => services.store.secrets.setCookie(SiteIds.bilibili, 'SESSDATA=a; DedeUserID=1'));
  final danmaku = FakeDanmaku();
  final previous = AppNavigator.toast;
  AppNavigator.toast = (_) {};
  addTearDown(() => AppNavigator.toast = previous);
  final site = FakeSite(liveRoom());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({SiteIds.bilibili: () => site})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: () => danmaku})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(FakeEngine())),
      ],
      child: MaterialApp(
        theme: const LiveTheme().light,
        home: LivePlayPage(
          route: RouteArgs(
            RoutePath.kLivePlay,
            arguments: LiveRoom(platform: SiteIds.bilibili, roomId: '6', nick: '主播'),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return _Room(services, danmaku);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _closeRoom(WidgetTester tester, _Room room) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(room.services.close);
  debugDefaultTargetPlatformOverride = null;
}
