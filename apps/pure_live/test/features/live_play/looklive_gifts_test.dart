// D07.7 stage 1 (docs/D-弹幕/D07-礼物和付费消息/D07.7-要先录样本的平台补礼物): LOOK's gifts
// (custom message 102) through the real parser and the recorded frames, as
// the app shows them.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:pure_live/features/live_play/danmaku/gift_line.dart';

import 'platform_gift_support.dart';

/// What LOOK S06-gifts decodes to, in order.
List<LiveMessage> _look() => [
  for (final line in File('../../fixtures/looklive/danmaku/S06-gifts/frames.jsonl').readAsLinesSync())
    ...LookLiveDanmakuProtocol.decode((jsonDecode(line) as Map<String, Object?>)['text']).messages,
];

void main() {
  useGiftLineTests();

  const room = GiftLineRoom(platform: SiteIds.lookLive);

  testWidgets('LOOK: a gift with its picture and its worth in notes, never ranked or converted', (tester) async {
    final gifts = _look();
    expect(gifts, hasLength(4));
    await pumpGiftLine(tester, gifts.last, room: room);
    expect(giftLineText(tester), contains('旋转木马'));
    expect(giftLineText(tester), contains('观众4'));
    expect((giftLineCount(tester), giftLineValue(tester)), ('×1', '100 音符'));
    expect(giftLinePicture(tester), startsWith('https://p1.music.126.net/'));
    expect(gifts.last.gift!.tier, LiveGiftTier.normal, reason: 'notes have no rate');
    expect(giftLineMarked(tester, LiveGiftTier.valuable), isFalse);
    expect(giftValueText(gifts.last.gift!, inYuan: true), '100 音符');
  });
}
