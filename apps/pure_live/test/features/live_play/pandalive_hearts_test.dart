// D07.7 stage 2 (docs/D-弹幕/D07-礼物和付费消息/D07.7-要先录样本的平台补礼物): PandaTV's
// hearts (SponCoin, 후원) through the real parser and the recorded
// publications, as the app shows them.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:pure_live/features/live_play/danmaku/gift_line.dart';

import 'platform_gift_support.dart';

/// What PandaTV S08-hearts decodes to, in order.
List<LiveMessage> _panda() => [
  for (final line in File('../../fixtures/pandalive/danmaku/S08-hearts/frames.jsonl').readAsLinesSync())
    if ((jsonDecode(line) as Map<String, Object?>)['text'] case final String text)
      ...PandaLiveDanmakuProtocol.decode(
        text,
        channel: ((jsonDecode(text) as Map)['result'] as Map)['channel'] as String,
      ).messages,
];

void main() {
  useGiftLineTests();

  const room = GiftLineRoom(platform: SiteIds.pandaLive, streamer: '가온');

  testWidgets('PandaTV: hearts are a tip to the show member, worth their count; 10666 is precious', (tester) async {
    final messages = _panda();
    final gifts = [
      for (final m in messages)
        if (m.type == LiveMessageType.gift) m,
    ];
    expect(gifts, hasLength(15));
    await pumpGiftLine(tester, gifts.first, room: room);
    expect(giftLineText(tester), contains('打赏'));
    expect(giftLineText(tester), contains('하트'));
    expect((giftLineCount(tester), giftLineValue(tester)), ('×1063', '1063 爱心'));
    final big = gifts.firstWhere((m) => m.gift!.count == 10666);
    await pumpGiftLine(tester, big, room: room);
    expect(giftLineMarked(tester, LiveGiftTier.precious), isTrue);
    expect(giftValueText(big.gift!, inYuan: true), '1.1万 爱心', reason: 'an overseas unit is never converted');
    // The words sent with hearts are chat lines of their own.
    expect(
      [
        for (final m in messages)
          if (m.type == LiveMessageType.chat) m.message,
      ],
      ['갓조개', '노느라 깜빡했네 상처뿐인시그보여줘'],
    );
  });
}
