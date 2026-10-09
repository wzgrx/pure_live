// D07.6 stage 2 (docs/D-弹幕/D07-礼物和付费消息/D07.6-已有样本的平台补礼物): AcFun's gifts
// through the real parser with the recorded gift table (S07-live line 3), as
// the app shows them. No gift signal was recorded: the signals are
// synthesized after the public protocol (the field numbers of the public
// client libraries).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:pure_live/features/live_play/danmaku/gift_line.dart';

import 'platform_gift_support.dart';

/// The table `AcfunSite` fetches, as the recording has it.
final AcfunGiftCatalog _table = AcfunApi.giftList(
  (jsonDecode(File('../../fixtures/acfun/danmaku/S07-live/frames.jsonl').readAsLinesSync()[2])
          as Map<String, Object?>)['text']!
      as String,
);

const GiftLineRoom _room = GiftLineRoom(platform: SiteIds.acfun);

// Protobuf by hand (the package's writer is not public): varints and
// length-delimited fields only.
List<int> _varint(int value) {
  final out = <int>[];
  var rest = value;
  while (rest >= 0x80) {
    out.add((rest & 0x7F) | 0x80);
    rest >>= 7;
  }
  return out..add(rest);
}

List<int> _int(int field, int value) => [..._varint(field << 3), ..._varint(value)];

List<int> _bytes(int field, List<int> value) => [..._varint(field << 3 | 2), ..._varint(value.length), ...value];

List<int> _text(int field, String value) => _bytes(field, utf8.encode(value));

/// One `CommonActionSignalGift` of 观众1 in a `ZtLiveScActionSignal`.
LiveMessage _gift(int id, {int count = 1, int combo = 1, String comboId = '', AcfunGiftCatalog? table}) {
  final signal = [
    ..._bytes(1, [..._int(1, 123456), ..._text(2, '观众1')]),
    ..._int(2, 1790000000000),
    ..._int(3, id),
    ..._int(4, count),
    ..._int(5, combo),
    if (comboId.isNotEmpty) ..._text(7, comboId),
  ];
  final signals = _bytes(1, [..._text(1, 'CommonActionSignalGift'), ..._bytes(2, signal)]);
  final message = [..._text(1, 'ZtLiveScActionSignal'), ..._bytes(3, signals)];
  return AcfunDanmakuProtocol.push(Uint8List.fromList(message), gifts: table ?? _table).messages.single;
}

void main() {
  useGiftLineTests();

  testWidgets('AcFun: 猴岛 has its picture and AC coins; a banana no value; without the table "礼物 {编号}"', (tester) async {
    await pumpGiftLine(tester, _gift(16), room: _room);
    expect(giftLineText(tester), contains('猴岛'));
    expect(giftLineValue(tester), '2888 AC币');
    expect(giftLinePicture(tester), _table['16']!.iconUrl.toString());
    expect(giftLineMarked(tester, LiveGiftTier.precious), isTrue, reason: '288.8 yuan');
    // 快乐水 ×10 is 10 AC coins: 1 yuan, no mark.
    await pumpGiftLine(tester, _gift(17, count: 10), room: _room);
    expect(giftLineValue(tester), '10 AC币');
    expect(giftLineMarked(tester, LiveGiftTier.valuable), isFalse);
    // Bananas are free: no value, the banana's picture.
    await pumpGiftLine(tester, _gift(1, count: 5), room: _room);
    expect((giftLineCount(tester), giftLineValue(tester)), ('×5', null));
    expect(giftLinePicture(tester), _table['1']!.iconUrl.toString());
    // Before the table came: the id, no value, no picture.
    await pumpGiftLine(tester, _gift(17, table: AcfunGiftCatalog.empty), room: _room);
    expect(giftLineText(tester), contains('礼物 17'));
    expect((giftLineValue(tester), giftLinePicture(tester)), (null, null));
    // "礼物价值换算成元": AC coins have a fixed rate.
    expect(giftValueText(_gift(16).gift!, inYuan: true), '288.8 元');
  });

  test("D07.1 merges a combo's sends by comboId and counts batch × combo", () {
    final lines = combinedGiftLines([
      for (var combo = 1; combo <= 3; combo++) _gift(35, count: 2, combo: combo, comboId: 'c-35'),
      _gift(35, count: 2, comboId: 'c-other'),
    ]);
    expect(lines, hasLength(2));
    final gift = lines.first.message!.gift!;
    expect((gift.count, gift.unitPrice, gift.totalValue), (6, 6, 36));
    expect(giftValueText(gift), '36 AC币');
  });
}
