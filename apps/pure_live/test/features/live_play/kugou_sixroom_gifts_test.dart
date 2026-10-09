// D07.7 stage 1 (docs/D-弹幕/D07-礼物和付费消息/D07.7-要先录样本的平台补礼物): Kugou Live's
// gifts (601) and Six Rooms' (201) through the real parsers and the recorded
// frames, as the app shows them.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:pure_live/features/live_play/danmaku/gift_line.dart';

import 'platform_gift_support.dart';

const String _fixtures = '../../fixtures';

/// The gifts of Kugou S12-gifts (room 3249275), in order.
List<LiveMessage> _kugou() => [
  for (final line in File('$_fixtures/kugoulive/danmaku/S12-gifts/frames.jsonl').readAsLinesSync())
    ...KugouLiveDanmakuProtocol.decode(
      base64.decode((jsonDecode(line) as Map<String, Object?>)['b64']! as String),
      roomId: '3249275',
    ).messages,
];

/// The gifts of Six Rooms S08-gifts, in order.
List<LiveMessage> _sixRoom() => [
  for (final line in File('$_fixtures/sixroom/danmaku/S08-gifts/frames.jsonl').readAsLinesSync())
    ...SixRoomDanmakuProtocol.decode((jsonDecode(line) as Map<String, Object?>)['text']).messages,
];

void main() {
  useGiftLineTests();

  const kugouRoom = GiftLineRoom(platform: SiteIds.kugouLive, streamer: 'v范可欣');
  const sixRoom = GiftLineRoom(platform: SiteIds.sixRoom, streamer: '︶薀昕下午播ぃ');

  testWidgets('Kugou: name, picture and star coins; the broadcaster gives too; 520 yuan is precious', (tester) async {
    final gifts = _kugou();
    expect(gifts, hasLength(17));
    await pumpGiftLine(tester, gifts[1], room: kugouRoom);
    expect(giftLineText(tester), contains('灵羽仙珠'));
    expect(giftLineText(tester), contains('观众2'));
    expect((giftLineCount(tester), giftLineValue(tester)), ('×10', '200 星币'));
    expect(giftLinePicture(tester), startsWith('https://s4fx.kgimg.com/fxstatic/images/giftres/31329/'));
    // The broadcaster's own gift to a viewer names the viewer.
    await pumpGiftLine(tester, gifts[2], room: kugouRoom);
    expect(giftLineText(tester), contains('送给 观众3'));
    expect(giftLineValue(tester), '5.2万 星币');
    expect(giftLineMarked(tester, LiveGiftTier.precious), isTrue);
    expect(giftValueText(gifts[2].gift!, inYuan: true), '520 元', reason: 'a hundred star coins to a yuan');
  });

  test('Kugou: each send its own combo id, one line each; the gifts without one merge by sender and gift', () {
    final lines = combinedGiftLines(_kugou());
    final viewer = [
      for (final line in lines)
        if (line.message!.userName == '观众14') line.message!.gift!.name,
    ];
    expect(viewer, ['爱恋相机', '玫瑰', '心心', '水晶玫瑰']);
    // The broadcaster's ten 亲亲 (no combo id) go to ten viewers: one line
    // each, each naming its receiver (the fallback combo key counts the
    // receiver, D07.7's combiner need 1).
    final kisses = [
      for (final line in lines)
        if (line.message!.gift!.name == '亲亲') line.message!.gift!,
    ];
    expect(kisses, hasLength(10));
    expect({for (final kiss in kisses) kiss.receiverName}, hasLength(10));
    expect(kisses.every((kiss) => kiss.count == 1), isTrue);
  });

  testWidgets('Six Rooms: a combo of three sends is one line ×3 of 300 six coins; a stock gift has no value', (
    tester,
  ) async {
    final gifts = _sixRoom();
    expect(gifts, hasLength(9));
    final lines = combinedGiftLines(gifts);
    final battery = lines.where((line) => line.message!.gift!.comboKey == '10003039:1791528881947').single;
    await pumpGiftLine(tester, battery.message!, room: sixRoom);
    expect(giftLineText(tester), contains('心动电池'));
    expect((giftLineCount(tester), giftLineValue(tester)), ('×3', '300 六币'));
    expect(giftLinePicture(tester), isNull, reason: "Six Rooms' table is not read");
    await pumpGiftLine(tester, gifts[1], room: sixRoom);
    expect(giftLineText(tester), contains('无限火力'));
    expect(giftLineValue(tester), isNull);
    // Six coins have no rate: never converted, never ranked.
    expect(giftValueText(gifts[0].gift!, inYuan: true), '1000 六币');
    expect(gifts[0].gift!.tier, LiveGiftTier.normal);
  });
}
