// Pictures named by the platforms for codes in chat texts (M13.16):
// CHZZK's `extras.emojis`, Bilibili's stickers and `emots`, Kuaishou's codes
// with the room page's emoji table. YouTube's channel emoji are in
// sites/youtube_test.dart (S07). Values below are the recorded ones of
// fixtures/chzzk/danmaku/S10-live and fixtures/bilibili/danmaku/S13-live.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

const _b07 = 'https://ssl.pstatic.net/static/nng/glive/icon/b_07.gif';
const _b15 = 'https://ssl.pstatic.net/static/nng/glive/icon/b_15.gif';

LiveMessage _bilibili(List<Object?> meta, String text) {
  final notice = {
    'cmd': 'DANMU_MSG',
    'info': [
      meta,
      text,
      [1, 'viewer'],
    ],
  };
  final items = BilibiliDanmakuProtocol.decode(
    BilibiliDanmakuProtocol.packet(BilibiliDanmakuProtocol.opNotice, jsonEncode(notice)),
  ).items;
  return items.whereType<BilibiliDanmakuMessage>().single.message;
}

void main() {
  test("CHZZK: the line's emojis table names its codes, each once; others stay text", () {
    final line = ChzzkDanmakuProtocol.line({
      'msg': '김남봉 화이팅!!{:d_55:}{:d_55:}{:d_47:}{:x:}',
      'uid': 'u1',
      'msgTime': 1790632293066,
      'msgTypeCode': ChzzkDanmakuProtocol.textType,
      'extras': jsonEncode({
        'emojis': {'d_55': _b15, 'd_47': _b07, 'unused': _b07, 'x': 'javascript:1'},
      }),
    })!;
    expect(line.emotes, const [LiveEmote(code: '{:d_55:}', url: _b15), LiveEmote(code: '{:d_47:}', url: _b07)]);
    expect(ChzzkDanmakuProtocol.emojis('plain', const {'d_55': _b15}), isEmpty);
    expect(ChzzkDanmakuProtocol.emojis('{:d_55:}', null), isEmpty);
  });

  test('Bilibili: a sticker is its whole text; inline codes from emots; http hdslb made https', () {
    final sticker = _bilibili([
      0, 1, 25, 16777215, 1790520023470, 1, 0, 'n1', 0, 0, 0, '', 1, //
      {
        'bulge_display': 1,
        'emoticon_unique': 'room_5050_123382',
        'url': 'http://i0.hdslb.com/bfs/live/f5c5e94344eaf7189621353701d4c8792b722bb7.png',
      },
    ], '流口水');
    expect(sticker.emotes, const [
      LiveEmote(code: '流口水', url: 'https://i0.hdslb.com/bfs/live/f5c5e94344eaf7189621353701d4c8792b722bb7.png'),
    ]);

    final inline = _bilibili([
      0, 1, 25, 16777215, 1790520023470, 2, 0, 'n2', 0, 0, 0, '', 0, '{}', '{}', //
      {
        'extra': jsonEncode({
          'emots': {
            '[dog]': {'url': 'http://i0.hdslb.com/bfs/live/dog.png'},
            '[妙]': {'url': 'https://i0.hdslb.com/bfs/live/miao.png'},
            '[absent]': {'url': 'https://i0.hdslb.com/bfs/live/x.png'},
          },
        }),
      },
    ], '[dog][dog] 好[妙]');
    expect(inline.emotes, const [
      LiveEmote(code: '[dog]', url: 'https://i0.hdslb.com/bfs/live/dog.png'),
      LiveEmote(code: '[妙]', url: 'https://i0.hdslb.com/bfs/live/miao.png'),
    ]);
    expect(_bilibili([0, 1, 25, 0, 1790520023470, 3], 'plain').emotes, isEmpty);
  });

  test("Kuaishou: the codes of a comment that the room page's table has, each once", () {
    final batch = KuaishouDanmakuProtocol.parse(
      jsonEncode({
        'result': 1,
        'liveStreamFeeds': [
          {
            'type': 'comment',
            'content': '[笑哭][笑哭]哈哈[不存在]',
            'author': {'userName': 'a', 'userId': 1},
          },
          {
            'type': 'comment',
            'content': '没有表情',
            'author': {'userName': 'b', 'userId': 2},
          },
        ],
      }),
      emotes: const {'[笑哭]': 'https://ali2.a.yximgs.com/bs2/emotion/xk.png'},
    );
    expect(batch.messages.first.emotes, const [
      LiveEmote(code: '[笑哭]', url: 'https://ali2.a.yximgs.com/bs2/emotion/xk.png'),
    ]);
    expect(batch.messages.last.emotes, isEmpty);
    expect(
      KuaishouDanmakuProtocol.parse(
        jsonEncode({
          'result': 1,
          'liveStreamFeeds': [
            {
              'type': 'comment',
              'content': '[笑哭]',
              'author': {'userName': 'a'},
            },
          ],
        }),
      ).messages.single.emotes,
      isEmpty,
      reason: 'a card gives no table',
    );
  });

  test('the runtime keeps the pictures when it cleans a text', () {
    const emote = LiveEmote(code: '[笑哭]', url: 'https://ali2.a.yximgs.com/bs2/emotion/xk.png');
    final cleaned = cleanDanmakuText(
      const LiveMessage(
        type: LiveMessageType.chat,
        userName: 'a',
        message: '￼[笑哭]',
        color: LiveMessageColor.white,
        emotes: [emote],
      ),
    );
    expect((cleaned.message, cleaned.emotes), ('[笑哭]', const [emote]));
  });
}
