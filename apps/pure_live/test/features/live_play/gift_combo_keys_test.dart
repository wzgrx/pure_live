// D07.6 stage 1 (docs/D-弹幕/D07-礼物和付费消息/D07.6-已有样本的平台补礼物): the platforms'
// combo keys (Huya `lComboSeqId`, Missevan `combo`, KilaKila `no`) through
// the real adapters and the recorded frames, as the app shows them: D07.1
// makes one line of a combo, and the A08.11 gift line shows its count and
// value.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:pure_live/features/live_play/danmaku/gift_line.dart';

import 'platform_gift_support.dart';

const String _fixtures = '../../fixtures';

List<Map<String, Object?>> _lines(String path) => [
  for (final line in File('$_fixtures/$path/frames.jsonl').readAsLinesSync())
    if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
];

/// Huya S18-gift (room 60066): every gift push.
List<LiveMessage> _huya() => [
  for (final frame in _lines('huya/danmaku/S18-gift'))
    ...HuyaDanmakuProtocol.decode(base64Decode(frame['b64']! as String)).messages,
];

/// Missevan S09-events: the gifts of the frames at [indexes].
List<LiveMessage> _missevan(List<int> indexes) {
  final frames = _lines('missevan/danmaku/S09-events');
  return [
    for (final index in indexes)
      ...MissevanDanmakuProtocol.decode(
        base64Decode(frames[index]['b64']! as String),
        roomId: frames[index]['room']! as String,
        uuid: 'u',
      ).messages,
  ];
}

/// KilaKila S10-live-gifts-questions, as the connection reports its gifts
/// (the lines that repeat a hit left out).
List<LiveMessage> _kilakila() {
  final meta = jsonDecode(
    File('$_fixtures/kilakila/danmaku/S10-live-gifts-questions/meta.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final room = (meta['danmakuKeys']! as Map<String, Object?>)['roomId']! as String;
  final combos = KilakilaGiftCombos();
  return [
    for (final frame in _lines('kilakila/danmaku/S10-live-gifts-questions'))
      for (final message in KilakilaDanmakuProtocol.decode(frame['text'], roomId: room).messages)
        if (message.type == LiveMessageType.gift && combos.report(message)) message,
  ];
}

void main() {
  useGiftLineTests();

  testWidgets("Huya: 观众2's 虎粮 combo (18 packets, one lComboSeqId) is one line ×19", (tester) async {
    final gifts = _huya();
    final lines = combinedGiftLines(gifts);
    // 27 packets: 8 combos with a sequence id, and two 虎粮 ×10 without one
    // (one sender each, so merged by sender and gift only with their own).
    expect(lines, hasLength(10));
    final combo = lines[1].message!;
    expect((combo.userName, combo.gift!.comboKey), ('观众2', '7482778489185:1790800575070'));
    await pumpGiftLine(tester, combo, room: const GiftLineRoom(platform: SiteIds.huya));
    expect(giftLineCount(tester), '×19');
    expect(giftLineText(tester), contains('虎粮'));
    expect(giftLineValue(tester), isNull, reason: '虎粮 is free; lPayTotal has no unit');
    // 观众3's two 虎粮 sends (×10, then ×5) are two combos, two lines.
    expect([for (final line in lines.sublist(2, 4)) line.message!.gift!.count], [10, 5]);
  });

  testWidgets("Missevan: the two sends of 幻彩礼炮's combo are one line ×2 with its picture", (tester) async {
    final gifts = _missevan([16, 17]);
    expect(gifts.map((gift) => gift.messageId), ['6abd2807a625be764d218212', ''], reason: 'the second has no oid');
    final lines = combinedGiftLines(gifts);
    final line = lines.single.message!;
    expect(line.gift!.comboKey, '6abd2807a625be764d218212');
    await pumpGiftLine(tester, line, room: const GiftLineRoom(platform: SiteIds.missevan));
    expect(giftLineCount(tester), '×2');
    expect(giftLinePicture(tester), 'https://static.maoercdn.com/live/gifts/icons/30087.png');
    expect(giftLineValue(tester), isNull, reason: 'price 0: free');
    // 书写星辰 (28 diamonds) is its own line with its value.
    await pumpGiftLine(tester, _missevan([18]).single);
    expect(giftLineValue(tester), '28 钻石');
  });

  testWidgets("KilaKila: a combo's hit and its line are one line; 飞天小猪 ×3 is 204 红豆", (tester) async {
    final gifts = _kilakila();
    // 桃花风车 ×7, 克拉之星 hit ×6 (its line left out), 守护灯牌, 飞天小猪
    // hit ×3 (its line left out), 天空之城.
    expect([for (final gift in gifts) gift.gift!.plainText], ['桃花风车 ×7', '克拉之星 ×6', '守护灯牌 ×1', '飞天小猪 ×3', '天空之城 ×1']);
    final lines = combinedGiftLines(gifts);
    expect(lines, hasLength(5));
    await pumpGiftLine(tester, lines[3].message!, room: const GiftLineRoom(platform: SiteIds.kilakila));
    expect(giftLineCount(tester), '×3');
    expect(giftLineValue(tester), '204 红豆');
    expect(giftLinePicture(tester), startsWith('https://'));
    // The line arriving without its hit (joined late) is the same line.
    final line = KilakilaDanmakuProtocol.decode(
      _lines('kilakila/danmaku/S10-live-gifts-questions')[7]['text'],
      roomId: '2269881372866773302',
    ).messages.single;
    final alone = combinedGiftLines([line]).single.message!;
    expect((alone.gift!.count, alone.gift!.unitPrice, alone.gift!.totalValue), (3, 68, 204));
    // Hits 1, 2 and 4 of one combo, then its line ×5 (hit 5 skipped): one
    // line ×5.
    LiveMessage hit(int count) => LiveMessage(
      type: LiveMessageType.gift,
      userName: '观众',
      userId: '7',
      message: '',
      color: LiveMessageColor.white,
      data: KilakilaGift(
        id: '15545',
        name: '飞天小猪',
        count: count,
        price: 68 * count,
        unitPrice: 68,
        comboKey: 'no-1',
        comboTotal: count,
      ),
    );
    final combo = combinedGiftLines([hit(1), hit(2), hit(4), hit(5)]).single.message!;
    expect((combo.gift!.count, combo.gift!.totalValue), (5, 340));
  });
}
