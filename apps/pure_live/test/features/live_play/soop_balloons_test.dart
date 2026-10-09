// D07.7 stage 2 (docs/D-弹幕/D07-礼物和付费消息/D07.7-要先录样本的平台补礼物): SOOP's star
// and ad balloons (18, 87) and subscriptions (91, 93) through the real parser
// and the recorded packets, as the app shows them.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:pure_live/features/live_play/danmaku/gift_line.dart';

import 'platform_gift_support.dart';

/// What SOOP S10-balloons decodes to, in order.
List<LiveMessage> _soop() => [
  for (final line in File('../../fixtures/soop/danmaku/S10-balloons/frames.jsonl').readAsLinesSync())
    ...SoopDanmakuProtocol.decode(base64.decode((jsonDecode(line) as Map<String, Object?>)['b64']! as String)),
];

void main() {
  useGiftLineTests();

  const room = GiftLineRoom(platform: SiteIds.soop, streamer: 'gosegu2');

  testWidgets('SOOP: a star balloon is a tip worth its count; 100 of them are valuable; ad balloons have no value', (
    tester,
  ) async {
    final messages = _soop();
    final gifts = [
      for (final m in messages)
        if (m.type == LiveMessageType.gift) m,
    ];
    expect(gifts, hasLength(17));
    await pumpGiftLine(tester, gifts[1], room: room);
    expect(giftLineText(tester), contains('打赏'));
    expect(giftLineText(tester), contains('별풍선'));
    expect(giftLineText(tester), contains('시청자2'));
    expect((giftLineCount(tester), giftLineValue(tester)), ('×10', '10 星气球'));
    await pumpGiftLine(tester, gifts[8], room: room);
    expect((giftLineCount(tester), giftLineValue(tester)), ('×100', '100 星气球'));
    expect(giftLineMarked(tester, LiveGiftTier.valuable), isTrue);
    // Overseas units are not converted to yuan.
    expect(giftValueText(gifts[8].gift!, inYuan: true), '100 星气球');
    await pumpGiftLine(tester, gifts.first, room: room);
    expect(giftLineText(tester), contains('애드벌룬'));
    expect(giftLineValue(tester), isNull);
    expect(giftLinePicture(tester), 'https://res.sooplive.com/new_player/items/img_adballoon.png');
    // The subscriptions are notices, not gift lines.
    expect([
      for (final m in messages)
        if (m.type == LiveMessageType.notice) m.data,
    ], List.filled(5, LiveNoticeKind.subscription));
  });

  test('SOOP: balloons of one viewer within the window count on one line', () {
    final gifts = [
      for (final m in _soop())
        if (m.type == LiveMessageType.gift) m,
    ];
    // 시청자17 sends 10 twice, 110 s apart in the room (here 0.5 s): one line ×20.
    final lines = combinedGiftLines(gifts.where((m) => m.userName == '시청자17'));
    expect(lines.single.message!.gift!.count, 20);
  });
}
