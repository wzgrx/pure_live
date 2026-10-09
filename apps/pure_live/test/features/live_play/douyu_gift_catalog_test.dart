// D07.3 (docs/D-弹幕/D07-礼物和付费消息/D07.3-斗鱼礼物目录和字段): Douyu's gifts
// through the real adapter with the recorded catalogue (betard S05-offline,
// the gift list S17, the prop table S18), as the app shows them: the A08.11
// gift line has the picture, the value in yuan and the tier mark; the free
// backpack props show no value; D07.1's combos still merge.

import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/image_cache.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/features/live_play/danmaku/gift_line.dart';
import 'package:pure_live/features/live_play/logic/gift_combiner.dart';

import '../../support.dart';
import 'no_images.dart';

const String _fixtures = '../../fixtures/douyu';

/// The catalogue `DouyuSite` builds from the recorded answers.
final DouyuGiftCatalog _catalogue = DouyuApi.roomGifts(File('$_fixtures/S05-offline/body.json').readAsStringSync())
    .merge(DouyuApi.giftList(File('$_fixtures/S17-gift-list/body.json').readAsStringSync()))
    .merge(DouyuApi.propGifts(File('$_fixtures/S18-prop-config/body.txt').readAsStringSync()));

const GiftLineRoom _room = GiftLineRoom(platform: SiteIds.douyu, streamer: '若若跑的贼快');

/// S15-gifts (room 9263298) decoded with [gifts].
List<LiveMessage> _s15({DouyuGiftCatalog gifts = DouyuGiftCatalog.empty}) {
  final sample =
      jsonDecode(File('$_fixtures/danmaku/S15-gifts/packets.json').readAsStringSync()) as Map<String, Object?>;
  final frame = [
    for (final body in sample['packets']! as List<Object?>)
      ...DouyuDanmakuProtocol.packet(body! as String, type: DouyuDanmakuProtocol.serverPacketType),
  ];
  return DouyuDanmakuProtocol.decode(frame, roomId: sample['roomId']! as String, gifts: gifts);
}

/// One `dgb` of room 9263298 as the server frames it, decoded with the
/// catalogue.
LiveMessage _dgb(String fields) => DouyuDanmakuProtocol.decode(
  DouyuDanmakuProtocol.packet(
    'type@=dgb/rid@=9263298/uid@=7/nn@=观众/level@=12/receive_nn@=若若跑的贼快/$fields',
    type: DouyuDanmakuProtocol.serverPacketType,
  ),
  roomId: '9263298',
  gifts: _catalogue,
).single;

/// The recorded S13-live frames coming in, with their time in ms.
List<({int t, Uint8List bytes})> _s13() => [
  for (final line in File('$_fixtures/danmaku/S13-live/frames.jsonl').readAsLinesSync())
    if (jsonDecode(line) case {'dir': 'in', 't': final int t, 'b64': final String b64})
      (t: t, bytes: base64Decode(b64)),
];

Future<void> _pumpLine(WidgetTester tester, LiveMessage message) async {
  final line = ChatLine.gift(message)..id = 1;
  await tester.pumpWidget(
    LiveUiScope(
      config: LiveUiConfig(imageCacheManager: NoImages()),
      child: MaterialApp(
        theme: const LiveTheme().light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              child: ChatLineView(key: const ValueKey(1), line: line, giftRoom: _room),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

String? _value(WidgetTester tester) {
  final value = find.byKey(const ValueKey('live-play-gift-value'));
  return value.evaluate().isEmpty ? null : tester.widget<Text>(value).data;
}

/// The address the line's picture asks for, or null without one.
String? _picture(WidgetTester tester) {
  final image = find.byKey(const ValueKey('live-play-gift-image'));
  if (image.evaluate().isEmpty) return null;
  final provider = (tester.widget<Image>(image).image as ResizeImage).imageProvider;
  return provider is CachedNetworkImageProvider ? provider.url : (provider as NetworkImage).url;
}

bool _marked(WidgetTester tester, LiveGiftTier tier) =>
    find.byKey(ValueKey('live-play-gift-tier-${tier.name}')).evaluate().isNotEmpty;

void main() {
  late BaseCacheManager? images;
  setUpAll(loadStrings);
  setUp(() {
    images = AppImageCache.manager;
    AppImageCache.manager = NoImages();
  });
  tearDown(() => AppImageCache.manager = images);

  group('the gift line (A08.11) of a catalogued Douyu gift', () {
    testWidgets('火箭: its picture, 500 元 and the precious mark', (tester) async {
      await _pumpLine(tester, _dgb('gfid@=20004/gfn@=火箭/gfcnt@=1/hits@=1/'));
      expect(_picture(tester), 'https://gfs-op.douyucdn.cn/dygift/2019/02/18/8bab2f98ab4d3429ffe00472a1a817e5.png');
      expect(_value(tester), '500 元');
      expect(_marked(tester, LiveGiftTier.precious), isTrue);
    });

    testWidgets('赞 ×100: 10 元 and the valuable mark; 小心心 ×3: 0.3 元, no mark', (tester) async {
      await _pumpLine(tester, _dgb('gfid@=20006/gfn@=赞/gfcnt@=100/'));
      expect(_value(tester), '10 元');
      expect(_marked(tester, LiveGiftTier.valuable), isTrue);
      await _pumpLine(tester, _dgb('gfid@=24491/gfn@=小心心/gfcnt@=3/'));
      expect(_value(tester), '0.3 元');
      expect(_marked(tester, LiveGiftTier.valuable) || _marked(tester, LiveGiftTier.precious), isFalse);
    });

    testWidgets('S15-gifts: 国庆快乐 ×9 is 0.9 元 with its picture; 粉丝荧光棒 has a picture and no value', (tester) async {
      final gifts = _s15(gifts: _catalogue);
      await _pumpLine(tester, gifts.firstWhere((m) => m.gift!.name == '国庆快乐'));
      expect(_value(tester), '0.9 元');
      expect(_picture(tester), startsWith('https://gfs-op.douyucdn.cn/dygift/2025/09/30/'));
      await _pumpLine(tester, gifts.firstWhere((m) => m.gift!.name == '粉丝荧光棒'));
      expect(_value(tester), isNull, reason: 'a free prop from the backpack');
      expect(_picture(tester), 'https://gfs-op.douyucdn.cn/dygift/1705/7d724fb3d7e7d4a463a3e74e9929b919.png');
      // 100鱼丸 is paid in 鱼丸: free, no value.
      await _pumpLine(tester, _dgb('gfid@=20000/gfn@=100鱼丸/gfcnt@=1/'));
      expect(_value(tester), isNull);
    });

    testWidgets('a gift no catalogue knows (精英宝典), and no catalogue at all: the line as before', (tester) async {
      final book = _s15(gifts: _catalogue).first;
      expect(book.gift!.name, '精英宝典');
      await _pumpLine(tester, book);
      expect(_value(tester), isNull);
      expect(_picture(tester), isNull);
      expect(find.byKey(const ValueKey('live-play-gift-icon')), findsOneWidget);
      await _pumpLine(tester, _s15().firstWhere((m) => m.gift!.name == '国庆快乐'));
      expect(_value(tester), isNull, reason: 'no catalogue, no price');
      expect(_picture(tester), isNull);
    });
  });

  group("D07.1's merging with the catalogue", () {
    test('S13-live: the same 26 lines as without it, the backpack props still merged and free', () {
      List<ChatLine> lines(DouyuGiftCatalog gifts) {
        var now = DateTime(2026, 10, 9, 20);
        final start = now;
        final feed = ChatFeed(giftCapacity: GiftCombiner.maxGiftLines, schedule: (_) {});
        final combiner = GiftCombiner(feed: feed, clock: () => now);
        for (final frame in _s13()) {
          now = start.add(Duration(milliseconds: frame.t));
          for (final message in DouyuDanmakuProtocol.decode(frame.bytes, roomId: '9999', gifts: gifts)) {
            if (message.type == LiveMessageType.gift) combiner.add(message);
          }
        }
        expect(combiner.dropped, 0);
        return [
          for (final line in feed.lines)
            if (line.kind == ChatLineKind.gift) line,
        ];
      }

      final plain = lines(DouyuGiftCatalog.empty);
      final priced = lines(_catalogue);
      expect(priced, hasLength(26));
      expect([for (final line in priced) line.text], [for (final line in plain) line.text]);
      final sticks = [for (final line in priced) line.message!.gift!].where((gift) => gift.id == '824');
      expect(sticks.every((gift) => gift.free && gift.iconUrl != null && gift.totalValue == null), isTrue);
    });

    test('a paid combo (火箭 hits 1, 2, 3) is one line worth 1500 元', () {
      var now = DateTime(2026, 10, 9, 20);
      final feed = ChatFeed(giftCapacity: GiftCombiner.maxGiftLines, schedule: (_) {});
      final combiner = GiftCombiner(feed: feed, clock: () => now);
      for (var hits = 1; hits <= 3; hits++) {
        now = now.add(const Duration(seconds: 1));
        combiner.add(_dgb('gfid@=20004/gfn@=火箭/gfcnt@=1/hits@=$hits/'));
      }
      final gift = feed.lines.single.message!.gift!;
      expect((gift.count, gift.totalValue, gift.unit, gift.tier), (3, 150000, LiveGiftUnit.fen, LiveGiftTier.precious));
      expect(giftValueText(gift), '1500 元');
      expect(gift.comboKey, '7:20004');
    });
  });
}
