// D07.7 stage 3 (docs/D-弹幕/D07-礼物和付费消息/D07.7-要先录样本的平台补礼物): SHOWROOM's
// gifts (t 2) named by the room's gift table, through the real parsers and
// the recorded events, as the app shows them.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:pure_live/features/live_play/danmaku/gift_line.dart';

import 'platform_gift_support.dart';

const String _fixtures = '../../fixtures/showroom';

/// What SHOWROOM S07-gifts decodes to with the S06 gift table, in order.
List<LiveMessage> _showroom({bool table = true}) {
  final gifts = table
      ? ShowroomApi.giftList(File('$_fixtures/S06-gift-list/body.json').readAsStringSync())
      : ShowroomGiftCatalog.empty;
  return [
    for (final line in File('$_fixtures/danmaku/S07-gifts/frames.jsonl').readAsLinesSync())
      if ((jsonDecode(line) as Map<String, Object?>)['text'] case final String text)
        ...ShowroomDanmakuProtocol.decode(text, key: text.split('\t')[1], gifts: gifts),
  ];
}

void main() {
  useGiftLineTests();

  const room = GiftLineRoom(platform: SiteIds.showroom);

  testWidgets('SHOWROOM: a paid gift in points with its picture; free stars have no value and merge', (tester) async {
    final gifts = _showroom();
    await pumpGiftLine(tester, gifts.last, room: room);
    expect(giftLineText(tester), contains('Cream soda(anime)'));
    expect(giftLineText(tester), contains('視聴者10'));
    expect((giftLineCount(tester), giftLineValue(tester)), ('×1', '500 点'));
    expect(giftLinePicture(tester), 'https://static.showroom-live.com/image/gift/3001833_m.png?v=21');
    expect(giftLineMarked(tester, LiveGiftTier.valuable), isTrue);
    await pumpGiftLine(tester, gifts.first, room: room);
    expect(giftLineText(tester), contains('Twinkle star'));
    expect((giftLineCount(tester), giftLineValue(tester)), ('×10', null));
    // 視聴者1's five sends of 10 stars come seconds apart (here 0.5 s): one line ×50.
    final stars = combinedGiftLines(gifts.where((m) => m.userName == '視聴者1'));
    expect(stars.single.message!.gift!.count, 50);
  });

  testWidgets('SHOWROOM: before the table came a gift is "礼物 {编号}" with its picture', (tester) async {
    await pumpGiftLine(tester, _showroom(table: false).last, room: room);
    expect(giftLineText(tester), contains('礼物 3001833'));
    expect(giftLinePicture(tester), 'https://static.showroom-live.com/image/gift/3001833_s.png');
    expect(giftLineValue(tester), isNull);
  });
}
