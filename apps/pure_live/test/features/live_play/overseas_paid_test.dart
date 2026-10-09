// D07.6 stage 4 (docs/D-弹幕/D07-礼物和付费消息/D07.6-已有样本的平台补礼物): Twitch's Bits,
// CHZZK's subscriptions and YouTube's Super Stickers through the real
// parsers, as the app shows them. No cheer was recorded: the Twitch line is
// synthesized after the public IRC tags; CHZZK and YouTube are recorded.

import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/danmaku/gift_line.dart';
import 'package:pure_live/features/live_play/danmaku/super_chats.dart';

import 'no_images.dart';
import 'platform_gift_support.dart';

const String _fixtures = '../../fixtures';

/// Every `liveChatPaidStickerRenderer` under [node].
Iterable<Map<String, Object?>> _stickers(Object? node) sync* {
  if (node is Map<String, Object?>) {
    if (node['liveChatPaidStickerRenderer'] case final Map<String, Object?> sticker) yield sticker;
    for (final value in node.values) {
      yield* _stickers(value);
    }
  } else if (node is List) {
    for (final value in node) {
      yield* _stickers(value);
    }
  }
}

void main() {
  useGiftLineTests();

  testWidgets('Twitch: a cheer is a gift line "打赏 Bits" worth 500 Bits; its words stay a chat line', (tester) async {
    final messages = TwitchDanmakuProtocol.decode(
      '@bits=500;color=#1E90FF;display-name=Cheerer;id=c1;tmi-sent-ts=1790781000000;user-id=42 '
      ':cheerer!cheerer@cheerer.tmi.twitch.tv PRIVMSG #channel :Cheer500 nice\r\n',
    ).messages;
    expect([for (final message in messages) message.type], [LiveMessageType.gift, LiveMessageType.chat]);
    await pumpGiftLine(tester, messages.first, room: const GiftLineRoom(platform: SiteIds.twitch));
    expect(giftLineText(tester), allOf(contains('Cheerer'), contains('打赏'), contains('Bits')));
    expect(giftLineValue(tester), '500 Bits');
    expect(giftLineCount(tester), isNull, reason: 'a tip of one says its value only');
    expect(giftLineMarked(tester, LiveGiftTier.valuable), isTrue, reason: 'about 5 dollars');
    expect(messages.last.message, 'Cheer500 nice');
    // Two cheers are two lines (each its own words).
    final other = TwitchDanmakuProtocol.decode(
      '@bits=100;display-name=Cheerer;id=c2;tmi-sent-ts=1790781001000;user-id=42 '
      ':cheerer!cheerer@cheerer.tmi.twitch.tv PRIVMSG #channel :Cheer100\r\n',
    ).messages.first;
    expect(combinedGiftLines([messages.first, other]), hasLength(2));
  });

  test('CHZZK S11-recent: the subscription is a notice with its tier and months, then its message', () {
    final lines = [
      for (final line in File('$_fixtures/chzzk/danmaku/S11-recent/frames.jsonl').readAsLinesSync())
        if (jsonDecode(line) case {'dir': 'in', 'text': final String text})
          ...ChzzkDanmakuProtocol.decode(text).messages,
    ];
    final index = lines.indexWhere((message) => message.message == '나이스한 아침이야');
    final notice = lines[index - 1];
    expect((notice.type, notice.data), (LiveMessageType.notice, LiveNoticeKind.subscription));
    expect(notice.message, '观众132 订阅了「나나양 좋아」，已订阅 32 个月');
    expect(lines[index].type, LiveMessageType.chat);
  });

  testWidgets('YouTube S10: a Super Sticker is a super chat card with the sticker, the amount and its description', (
    tester,
  ) async {
    final answer = jsonDecode(
      (jsonDecode(File('$_fixtures/youtube/danmaku/S10-live-all-chat/frames.jsonl').readAsLinesSync()[1])
              as Map<String, Object?>)['text']!
          as String,
    ) as Map<String, Object?>;
    final sticker = _stickers(answer).first;
    final poll = YouTubeDanmakuProtocol.chat({
      'continuationContents': {
        'liveChatContinuation': {
          'actions': [
            {
              'addChatItemAction': {
                'item': {'liveChatPaidStickerRenderer': sticker},
              },
            },
          ],
        },
      },
    }, now: DateTime.utc(2026, 9, 30, 15));
    final paid = poll.messages.single.data! as LiveSuperChatMessage;
    final clock = ValueNotifier(paid.startTime);
    addTearDown(clock.dispose);
    await tester.pumpWidget(
      LiveUiScope(
        config: LiveUiConfig(imageCacheManager: NoImages()),
        child: MaterialApp(
          theme: const LiveTheme().light,
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: SuperChatCard(superChat: paid, clock: clock),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final image = tester.widget<Image>(find.byKey(const ValueKey('super-chat-sticker')));
    final provider = (image.image as ResizeImage).imageProvider;
    expect(
      provider is CachedNetworkImageProvider ? provider.url : (provider as NetworkImage).url,
      startsWith('https://lh3.googleusercontent.com/'),
    );
    expect(tester.widget<Text>(find.byKey(const ValueKey('super-chat-price'))).data, paid.priceText);
    expect(paid.priceText, startsWith('¥'));
    expect(find.textContaining(paid.message), findsOneWidget);
    // A super chat of text has no picture.
    await tester.pumpWidget(
      LiveUiScope(
        config: LiveUiConfig(imageCacheManager: NoImages()),
        child: MaterialApp(
          home: Scaffold(
            body: SuperChatCard(
              superChat: LiveSuperChatMessage(
                userName: 'a',
                face: '',
                message: 'text',
                price: 30,
                startTime: paid.startTime,
                endTime: paid.endTime,
                backgroundColor: '',
                backgroundBottomColor: '',
              ),
              clock: clock,
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('super-chat-sticker')), findsNothing);
  });
}
