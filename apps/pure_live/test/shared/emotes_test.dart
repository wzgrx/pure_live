import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/shared/danmaku/emotes.dart';

import '../support.dart';

LiveMessage _chat(String text, [List<LiveEmote> emotes = const []]) => LiveMessage(
  type: LiveMessageType.chat,
  userName: 'u',
  message: text,
  color: LiveMessageColor.white,
  emotes: emotes,
);

void main() {
  group('bundled lists (3.x assets/emo)', () {
    test('five platforms load; every code has its picture in the app; pubspec lists the folders', () async {
      final library = EmoteLibrary(bundle: FileAssetBundle());
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final sizes = <String, int>{};
      for (final platform in EmoteLibrary.platforms) {
        final table = await library.load(platform);
        sizes[platform] = table.codes.length;
        expect(identical(library.tableOf(platform), table), isTrue);
        for (final MapEntry(key: code, value: emote) in table.codes.entries) {
          expect(File(emote.asset).existsSync(), isTrue, reason: '$platform $code ${emote.asset}');
        }
        expect(pubspec, contains('- assets/emo/images/$platform/'));
      }
      // Huya's escapes (`/{dx`) are codes too.
      expect(sizes, {'bilibili': 127, 'douyin': 349, 'douyu': 364, 'huya': 606, 'kuaishou': 207});
      expect(library.tableOf(SiteIds.kuaishou).codes['[笑哭]'], (
        asset: 'assets/emo/images/kuaishou/笑哭.png',
        url: 'https://ali2.a.yximgs.com/bs2/emotion/1704771554781third_party_s1296699971.png',
      ));
      expect((await library.load(SiteIds.cc)).codes, isEmpty, reason: 'no chat, no list');
      expect((await library.load(SiteIds.chzzk)).codes, isEmpty);
    });

    test('an unreadable list is empty, not an error', () async {
      final library = EmoteLibrary(bundle: _Missing());
      expect((await library.load(SiteIds.douyu)).codes, isEmpty);
    });
  });

  group('chatSegments', () {
    final table = EmoteTable.of(const {
      '[笑哭]': (asset: 'assets/emo/images/kuaishou/笑哭.png', url: 'https://k/xk.png'),
      '/{dx': (asset: 'assets/emo/images/huya/1.png', url: ''),
      '/{dxx': (asset: 'assets/emo/images/huya/2.png', url: ''),
    });

    test('bundled codes become pictures, the bundled one first; unknown codes stay text', () {
      expect(chatSegments(_chat('哈[笑哭][不存在]/{dxx!'), table), const [
        ChatTextSegment('哈'),
        ChatEmoteSegment(url: 'https://k/xk.png', alt: '[笑哭]', asset: 'assets/emo/images/kuaishou/笑哭.png'),
        ChatTextSegment('[不存在]'),
        ChatEmoteSegment(url: '', alt: '/{dxx', asset: 'assets/emo/images/huya/2.png'),
        ChatTextSegment('!'),
      ]);
      expect(chatSegments(_chat('plain'), table), const [ChatTextSegment('plain')]);
      expect(chatSegments(_chat('[笑哭]')), const [ChatTextSegment('[笑哭]')], reason: 'no table, nothing named');
    });

    test('B09 c7: one parse per message and table, shared by the chat list and the flying layer', () {
      final message = _chat('哈[笑哭]');
      final first = chatSegments(message, table);
      expect(identical(chatSegments(message, table), first), isTrue, reason: 'the flying layer gets the same list');
      expect(() => first.add(const ChatTextSegment('x')), throwsUnsupportedError, reason: 'shared, so fixed');
      // Another table (the list loaded later) parses again.
      final other = EmoteTable.of(const {'[笑哭]': (asset: '', url: 'https://other/xk.png')});
      final again = chatSegments(message, other);
      expect(identical(again, first), isFalse);
      expect(again.last, const ChatEmoteSegment(url: 'https://other/xk.png', alt: '[笑哭]'));
      // A message of the same words is a message of its own.
      expect(identical(chatSegments(_chat('哈[笑哭]'), table), first), isFalse);
      expect(chatSegments(_chat('哈[笑哭]'), table), first);
    });

    test("the message's own pictures (CHZZK, YouTube, a Bilibili sticker); a bundled picture still comes first", () {
      expect(
        chatSegments(
          _chat('{:d_55:}{:d_55:} 화이팅', const [
            LiveEmote(code: '{:d_55:}', url: 'https://ssl.pstatic.net/static/nng/glive/icon/b_15.gif'),
          ]),
        ),
        const [
          ChatEmoteSegment(url: 'https://ssl.pstatic.net/static/nng/glive/icon/b_15.gif', alt: '{:d_55:}'),
          ChatEmoteSegment(url: 'https://ssl.pstatic.net/static/nng/glive/icon/b_15.gif', alt: '{:d_55:}'),
          ChatTextSegment(' 화이팅'),
        ],
      );
      expect(chatSegments(_chat('流口水', const [LiveEmote(code: '流口水', url: 'https://i0.hdslb.com/s.png')])), const [
        ChatEmoteSegment(url: 'https://i0.hdslb.com/s.png', alt: '流口水'),
      ]);
      expect(chatSegments(_chat('[笑哭]', const [LiveEmote(code: '[笑哭]', url: 'https://page/xk.png')]), table), const [
        ChatEmoteSegment(url: 'https://page/xk.png', alt: '[笑哭]', asset: 'assets/emo/images/kuaishou/笑哭.png'),
      ]);
    });
  });
}

final class _Missing extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => throw StateError('missing $key');
}
