import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

import 'fixture.dart';

final _context = DecodeContext(room: 'kuaishou:Kslala666', session: 1, receivedAt: 1, now: DateTime.utc(2026, 9, 27));

Map<String, Object?> _feed({List<Map<String, Object?>> feeds = const [], Object? result = 1}) => {
  'result': result,
  'cursor': 'next',
  'pullCycleSeconds': 20,
  'currentWatchingCount': '5.6w',
  'liveStreamFeeds': feeds,
};

void main() {
  group('feed (§7)', () {
    test('URL, cursor and headers', () {
      final url = KuaishouProtocol.url(KuaishouProtocol.endpoints.first, 'abc', '');
      expect(url.toString(), 'https://livev.m.chenzhongtech.com/wap/live/feed?liveStreamId=abc');
      expect(KuaishouProtocol.url(KuaishouProtocol.endpoints.last, 'abc', 'c1').queryParameters['cursor'], 'c1');
      expect(KuaishouProtocol.headers()['Referer'], 'https://livev.m.chenzhongtech.com/');
      expect(KuaishouProtocol.headers().containsKey('cookie'), isFalse);
      expect(KuaishouProtocol.headers(cookie: 'did=1')['cookie'], 'did=1');
    });

    test('bodies encoded one to three times, with or without data (REG-KUAISHOU-012)', () {
      final plain = jsonEncode(_feed());
      for (final body in [
        plain,
        jsonEncode(plain),
        jsonEncode(jsonEncode(plain)),
        jsonEncode({'data': _feed()}),
      ]) {
        final feed = KuaishouProtocol.parse(body, context: _context);
        expect(feed.cursor, 'next');
        expect(feed.pullDelay, const Duration(seconds: 10));
        expect((feed.events.single as DanmakuOnline).value, 56000);
      }
    });

    test('result != 1 is a failure (REG-KUAISHOU-013)', () {
      expect(() => KuaishouProtocol.parse(jsonEncode(_feed(result: 2)), context: _context), throwsFormatException);
      expect(() => KuaishouProtocol.parse('[]', context: _context), throwsFormatException);
    });

    test('comments: trimmed text, default name, id or sha1 fallback; other types dropped', () {
      final feed = KuaishouProtocol.parse(
        jsonEncode(
          _feed(
            feeds: [
              {
                'type': 'COMMENT',
                'id': 'x1',
                'content': ' 你好 ',
                'time': 1790520023470,
                'author': {'userName': '观众', 'userId': 1},
              },
              {
                'type': 'comment',
                'content': 'hi',
                'time': 5,
                'author': {'userName': '', 'userId': 2},
              },
              {'type': 'gift', 'content': 'x'},
              {'type': 'comment', 'content': '  '},
            ],
          ),
        ),
        context: _context,
      );
      final chats = feed.events.whereType<DanmakuChat>().toList();
      expect(chats.map((chat) => chat.text), ['你好', 'hi']);
      expect(chats.first.id, 'kuaishou:x1');
      expect(chats.first.sentAt, DateTime.fromMillisecondsSinceEpoch(1790520023470));
      expect(chats.last.userName, '快手用户');
      expect(chats.last.id, 'kuaishou:${sha1.convert(utf8.encode('5\u00002\u0000hi'))}');
    });
  });

  group('recorded polls (fixtures/kuaishou/danmaku/S16-live)', () {
    final fixture = DanmakuFixture.load('kuaishou', 'S16-live');
    final feeds = [
      for (final frame in fixture.incoming) KuaishouProtocol.parse(frame.text!, context: fixture.context(frame)),
    ];

    test('the first poll has no cursor, each later one sends the previous cursor', () {
      final urls = [for (final frame in fixture.incoming) frame.url!];
      expect(urls.first.queryParameters.containsKey('cursor'), isFalse);
      for (var i = 1; i < urls.length; i++) {
        expect(urls[i].queryParameters['cursor'], feeds[i - 1].cursor);
      }
      expect(urls.every((url) => url.host == 'livev.m.chenzhongtech.com'), isTrue);
    });

    test('comments and online figures decode; the pull interval is the server one', () {
      final events = [for (final feed in feeds) ...feed.events];
      expect(events.whereType<DanmakuChat>(), hasLength(42));
      expect(events.whereType<DanmakuOnline>().map((online) => online.value).first, 56000);
      expect(feeds.every((feed) => feed.pullDelay == const Duration(seconds: 3)), isTrue);
      final chats = events.whereType<DanmakuChat>();
      expect(chats.every((chat) => chat.id!.startsWith('kuaishou:') && chat.sentAt != null), isTrue);
    });
  });
}
