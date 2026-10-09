// D07.7 stage 3 (docs/D-弹幕/D07-礼物和付费消息/D07.7-要先录样本的平台补礼物): TwitCasting's
// gifts (アイテム, `gift=1`) through the real parser and the recorded events,
// as the app shows them.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:pure_live/features/live_play/danmaku/gift_line.dart';

import 'platform_gift_support.dart';

/// What TwitCasting S09-gifts decodes to, in order.
List<LiveMessage> _twitcasting() => [
  for (final line in File('../../fixtures/twitcasting/danmaku/S09-gifts/frames.jsonl').readAsLinesSync())
    ...TwitcastingDanmakuProtocol.decode((jsonDecode(line) as Map<String, Object?>)['text']),
];

void main() {
  useGiftLineTests();

  const room = GiftLineRoom(platform: SiteIds.twitcasting, streamer: 'ちょびつき');

  testWidgets('TwitCasting: an item with its picture and no value; three teas of one viewer count on one line', (
    tester,
  ) async {
    final messages = _twitcasting();
    final gifts = [
      for (final m in messages)
        if (m.type == LiveMessageType.gift) m,
    ];
    expect(gifts, hasLength(12));
    await pumpGiftLine(tester, gifts[5], room: room);
    expect(giftLineText(tester), contains('お茶ｘ10'));
    expect(giftLineText(tester), contains('視聴者6'));
    expect((giftLineCount(tester), giftLineValue(tester)), ('×1', null));
    expect(giftLinePicture(tester), 'https://s01.twitcasting.tv/img/item_tea_10.autumn.png');
    // 視聴者8's three お茶 within 40 s of the room (here 0.5 s apart): one line ×3.
    final teas = combinedGiftLines(gifts.where((m) => m.userName == '視聴者8'));
    expect(teas.single.message!.gift!.count, 3);
    // The words that came with a gift are chat lines of their own.
    expect([
      for (final m in messages)
        if (m.type == LiveMessageType.chat) m.message,
    ], hasLength(5));
  });
}
