import 'dart:convert';

import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

// Entries in the shapes of 3.x's bundled lists (assets/emo/json).
const _bilibili = {
  '[dog]': {'emoji': '[dog]', 'url': 'http://i0.hdslb.com/bfs/live/dog.png', 'local_file': 'dog.png'},
  '[花]': {'emoji': '', 'url': 'http://i0.hdslb.com/bfs/live/flower.png', 'local_file': 'flower.png'},
};

const List<Map<String, Object>> _douyin = [
  {
    'display_name': '[微笑]',
    'emoji_url': {
      'url_list': ['https://p3.douyinpic.com/weixiao', 'https://p9.douyinpic.com/weixiao'],
    },
    'local_file': 'weixiao.png',
  },
  {'display_name': '[无图]', 'local_file': ''},
];

const _douyu = {
  '梗已老实': {'simple_name': '梗已老实', 'img_url': 'https://sta-op.douyucdn.cn/a.png', 'local_file': '梗已老实.png'},
  '[已带括号]': {'img_url': 'https://sta-op.douyucdn.cn/b.png', 'local_file': 'b.png'},
};

const _huya = [
  {'sName': '[666]', 'sEscape': '/{66', 'sUrl': 'http://huya/666.png', 'sFlexiUrl': '', 'local_file': '15.png'},
  {
    'sName': '[神金]',
    'sEscape': '',
    'sUrl': 'http://huya/a.png',
    'sFlexiUrl': 'https://huya/b.png',
    'local_file': '9.png',
  },
];

void main() {
  test('Bilibili: the emoji field, or the entry key when it is empty', () {
    final emojis = DanmakuEmoji.parseList(jsonEncode(_bilibili), 'bilibili');
    expect(emojis.map((emoji) => emoji.primaryKey), ['[dog]', '[花]']);
    expect(emojis.first.text, '[dog]');
    expect(emojis.first.url, 'http://i0.hdslb.com/bfs/live/dog.png');
    expect(emojis.first.localFile, 'dog.png');
    expect(emojis.first.secondaryKey, isNull);
  });

  test('Douyin: display name and the first image address', () {
    final emojis = DanmakuEmoji.parseList(jsonEncode(_douyin), 'douyin');
    expect(emojis.first.primaryKey, '[微笑]');
    expect(emojis.first.url, 'https://p3.douyinpic.com/weixiao');
    expect(emojis.last.url, '');
    expect(emojis.last.localFile, '');
  });

  test('Douyu: the entry key in brackets, unless it has them', () {
    final emojis = DanmakuEmoji.parseList(jsonEncode(_douyu), 'douyu');
    expect(emojis.map((emoji) => emoji.primaryKey), ['[梗已老实]', '[已带括号]']);
    expect(emojis.first.url, 'https://sta-op.douyucdn.cn/a.png');
  });

  test('Huya: the name, its escape code as a second key, the flexible image first', () {
    final emojis = DanmakuEmoji.parseList(jsonEncode(_huya), 'huya');
    expect(emojis.first.keys, ['[666]', '/{66']);
    expect(emojis.first.url, 'http://huya/666.png');
    expect(emojis.last.keys, ['[神金]']);
    expect(emojis.last.secondaryKey, isNull);
    expect(emojis.last.url, 'https://huya/b.png');
  });

  test('Kuaishou: the entry key, its address and file (M13.16; 3.x bundled the list unread)', () {
    final emojis = DanmakuEmoji.parseList(
      jsonEncode({
        '[笑哭]': {'url': 'https://ali2.a.yximgs.com/bs2/emotion/xk.png', 'local_file': '笑哭.png'},
      }),
      'kuaishou',
    );
    expect(emojis.single.keys, ['[笑哭]']);
    expect(emojis.single.url, 'https://ali2.a.yximgs.com/bs2/emotion/xk.png');
    expect(danmakuEmojiAssets('kuaishou', emojis).single.asset, 'assets/emo/images/kuaishou/笑哭.png');
  });

  test('other platforms give empty emoticons, so nothing is registered (3.x)', () {
    final emojis = DanmakuEmoji.parseList(jsonEncode(_bilibili), 'cc');
    expect(emojis, hasLength(2));
    expect(emojis.every((emoji) => emoji.keys.isEmpty && emoji.localFile.isEmpty), isTrue);
    expect(danmakuEmojiAssets('cc', emojis), isEmpty);
  });

  test('entries that are not objects are skipped; other JSON gives nothing', () {
    expect(DanmakuEmoji.parseList('[1, "x", {"sName": "[a]", "local_file": "a.png"}]', 'huya'), hasLength(1));
    expect(DanmakuEmoji.parseList('{"a": 1}', 'douyu'), isEmpty);
    expect(DanmakuEmoji.parseList('"text"', 'douyu'), isEmpty);
    expect(() => DanmakuEmoji.parseList('{', 'douyu'), throwsFormatException);
  });

  test('atlas entries: bundled images only, grouped by image in order of first use', () {
    const emojis = [
      DanmakuEmoji(primaryKey: '[a]', text: '[a]', url: '', localFile: 'x.png'),
      DanmakuEmoji(primaryKey: '[b]', text: '[b]', url: '', localFile: 'y.png'),
      DanmakuEmoji(primaryKey: '[c]', text: '[c]', url: '', localFile: 'x.png', secondaryKey: '/{c'),
      DanmakuEmoji(primaryKey: '[d]', text: '[d]', url: '', localFile: ''),
    ];
    final assets = danmakuEmojiAssets('huya', emojis);
    expect(assets.map((asset) => asset.keys), [
      ['[a]'],
      ['[c]', '/{c'],
      ['[b]'],
    ]);
    expect(assets.map((asset) => asset.id), ['x.png', 'x.png', 'y.png']);
    expect(assets.first.asset, 'assets/emo/images/huya/x.png');
    expect(danmakuEmojiListAsset('huya'), 'assets/emo/json/huya.json');
  });
}
