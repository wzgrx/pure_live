// D07.6 stage 3 (docs/D-弹幕/D07-礼物和付费消息/D07.6-已有样本的平台补礼物): 17LIVE's gifts
// (type 13) and BIGO's (760969) through the real parsers and the recorded
// frames, as the app shows them.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:pure_live/features/live_play/danmaku/gift_line.dart';

import 'platform_gift_support.dart';

const String _fixtures = '../../fixtures';

/// The gifts of 17LIVE S06-live (room 27484154).
List<LiveMessage> _seventeen() => [
  for (final line in File('$_fixtures/17live/danmaku/S06-live/frames.jsonl').readAsLinesSync())
    if (jsonDecode(line) case {'dir': 'in', 'text': final String text})
      for (final message in SeventeenLiveDanmakuProtocol.decode(text, roomId: '27484154').messages)
        if (message.type == LiveMessageType.gift) message,
];

/// The text of BIGO S05-live's line [number] (1-based).
String _bigo(int number) =>
    (jsonDecode(File('$_fixtures/bigo/danmaku/S05-live/frames.jsonl').readAsLinesSync()[number - 1])
            as Map<String, Object?>)['text']!
        as String;

void main() {
  useGiftLineTests();

  testWidgets('17LIVE: a gift without a table is "礼物 {编号}", free (0 points): no value', (tester) async {
    final gifts = _seventeen();
    expect(gifts, hasLength(18));
    await pumpGiftLine(tester, gifts.first, room: const GiftLineRoom(platform: SiteIds.seventeenLive));
    expect(giftLineText(tester), contains('礼物 2609_jp_cp_akanya'));
    expect(giftLineText(tester), contains('观众1'));
    expect(giftLineCount(tester), '×3', reason: 'combo.count');
    expect(giftLineValue(tester), isNull);
    // D07.1: one line per combo (by the sender and the gift): 18 messages.
    final lines = combinedGiftLines(gifts);
    final combo = lines.where((line) => line.message!.userName == '观众21').single.message!;
    expect(combo.gift!.comboTotal, 3);
    expect(lines.length, lessThan(18));
  });

  testWidgets('BIGO: the Flower of S05-live line 63 is a gift line ×1', (tester) async {
    final gift = BigoDanmakuProtocol.decode(_bigo(63), roomId: '6309489689319799326').messages.single;
    await pumpGiftLine(tester, gift, room: const GiftLineRoom(platform: SiteIds.bigo));
    expect(giftLineText(tester), contains('Flower'));
    expect((giftLineCount(tester), giftLineValue(tester)), ('×1', null));
    // Its sender is in the line that follows (the connection names it).
    expect(BigoDanmakuProtocol.decode(_bigo(64), roomId: '6309489689319799326').giftSender?.name, '观众3');
  });
}
