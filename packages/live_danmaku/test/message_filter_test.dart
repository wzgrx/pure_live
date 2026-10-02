import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

LiveMessage _message(
  String text, {
  String user = 'viewer',
  String id = '',
  bool local = false,
  LiveMessageType type = LiveMessageType.chat,
}) => LiveMessage(
  type: type,
  userName: user,
  userId: user,
  message: text,
  messageId: id,
  color: LiveMessageColor.white,
  isLocal: local,
);

void main() {
  group('DanmakuBlockList', () {
    test('names match whole, trimmed and in any case', () {
      final list = DanmakuBlockList(users: [' Spammer ', '', '  ']);
      expect(list.blocks(_message('hi', user: 'spammer')), isTrue);
      expect(list.blocks(_message('hi', user: '  SPAMMER')), isTrue);
      expect(list.blocks(_message('hi', user: 'spammer2')), isFalse);
      expect(list.blocks(_message('hi', user: '')), isFalse, reason: 'empty entries are dropped');
    });

    test('B-1: a masked name blocks nobody, not even the same masked name', () {
      final list = DanmakuBlockList(users: ['观***', 'ab＊＊', '路人']);
      expect(list.blocks(_message('hi', user: '观***')), isFalse);
      expect(list.blocks(_message('hi', user: 'ab＊＊')), isFalse);
      expect(list.blocks(_message('hi', user: '路人')), isTrue, reason: 'a full name still blocks');
      expect(DanmakuBlockList(users: ['观***']).isEmpty, isTrue);
    });

    test('words match inside the text in any case', () {
      final list = DanmakuBlockList(keywords: [' 广告 ', 'SPAM', '']);
      expect(list.blocks(_message('这是广告位')), isTrue);
      expect(list.blocks(_message('no spam please')), isTrue);
      expect(list.blocks(_message('Spam')), isTrue);
      expect(list.blocks(_message('hello')), isFalse);
      expect(list.blocks(_message('')), isFalse, reason: 'an empty word would block everything');
    });

    test('a word with inner spaces must match them', () {
      final list = DanmakuBlockList(keywords: ['a b']);
      expect(list.blocks(_message('xa by')), isTrue);
      expect(list.blocks(_message('ab')), isFalse);
      expect(DanmakuBlockList().isEmpty, isTrue);
      expect(list.isEmpty, isFalse);
    });
  });

  group('DanmakuMessageFilter', () {
    test('defaults: only the gate and the block lists are on', () {
      const settings = DanmakuFilterSettings();
      expect(settings.collapseRepeated, isFalse);
      expect(settings.repeatedWindowSeconds, 5);
      expect(settings.similarityEnabled, isFalse);
      expect(settings.similarityThreshold, 85);
      expect(settings.similarityCacheSeconds, 3);
      expect(settings.similarityMaxCacheSize, 100);

      var now = DateTime(2026);
      final filter = DanmakuMessageFilter(clock: () => now);
      expect(filter.accepts(_message('666', user: 'a')), isTrue);
      expect(filter.accepts(_message('666', user: 'b')), isTrue, reason: 'repeats of other viewers are kept');
      expect(filter.accepts(_message('666', user: 'a')), isFalse, reason: 'the gate drops a delivery twice');
      now = now.add(const Duration(seconds: 3));
      expect(filter.accepts(_message('666', user: 'a')), isTrue);
    });

    test('blocked viewers and words are dropped', () {
      final filter = DanmakuMessageFilter(
        settings: const DanmakuFilterSettings(blockedUsers: ['Troll'], blockedKeywords: ['加群']),
      );
      expect(filter.accepts(_message('hello', user: 'troll')), isFalse);
      expect(filter.accepts(_message('快来加群')), isFalse);
      expect(filter.accepts(_message('hello')), isTrue);
    });

    test('the gate sees a message before the block list, as in 3.x', () {
      final filter = DanmakuMessageFilter(settings: const DanmakuFilterSettings(blockedKeywords: ['bad']));
      expect(filter.accepts(_message('bad', id: 'x:1')), isFalse);
      filter.settings = const DanmakuFilterSettings();
      expect(filter.accepts(_message('bad', id: 'x:1')), isFalse, reason: 'the gate remembered the blocked id');
    });

    test('repeated text is collapsed when enabled, with the window clamped to 1–30 s', () {
      var now = DateTime(2026);
      final filter = DanmakuMessageFilter(
        clock: () => now,
        settings: const DanmakuFilterSettings(collapseRepeated: true, repeatedWindowSeconds: 0),
      );
      expect(filter.accepts(_message('加油', user: 'a')), isTrue);
      now = now.add(const Duration(milliseconds: 900));
      expect(filter.accepts(_message('加油', user: 'b')), isFalse, reason: 'a window of 0 s is used as 1 s');
      now = now.add(const Duration(milliseconds: 1001));
      expect(filter.accepts(_message('加油', user: 'c')), isTrue);

      filter.settings = const DanmakuFilterSettings(collapseRepeated: true, repeatedWindowSeconds: 99);
      now = now.add(const Duration(seconds: 29));
      expect(filter.accepts(_message('加油', user: 'd')), isFalse, reason: '99 s is used as 30 s');
      now = now.add(const Duration(seconds: 31));
      expect(filter.accepts(_message('加油', user: 'e')), isTrue);
    });

    test('similar text is hidden when enabled; local messages are not compared', () {
      final filter = DanmakuMessageFilter(settings: const DanmakuFilterSettings(similarityEnabled: true));
      expect(filter.accepts(_message('hello world', user: 'a')), isTrue);
      expect(filter.accepts(_message('hello wor1d', user: 'b')), isFalse);
      expect(filter.accepts(_message('hello wor1d', user: 'me', local: true)), isTrue);
    });

    test('settings apply to the next message; turning similarity off forgets its texts', () {
      final filter = DanmakuMessageFilter(settings: const DanmakuFilterSettings(similarityEnabled: true))
        ..accepts(_message('hello world', user: 'a'));
      expect(filter.similarity.cacheSize, 1);
      filter.settings = const DanmakuFilterSettings();
      expect(filter.similarity.cacheSize, 0);
      expect(filter.accepts(_message('hello world', user: 'b')), isTrue);

      filter.settings = const DanmakuFilterSettings(
        similarityEnabled: true,
        similarityThreshold: 95,
        similarityCacheSeconds: 10,
        similarityMaxCacheSize: 20,
      );
      expect(filter.similarity.similarityThreshold, 95);
      expect(filter.similarity.cacheDuration, const Duration(seconds: 10));
      expect(filter.similarity.maxCacheSize, 20);
      expect(filter.accepts(_message('hello world', user: 'c')), isTrue);
      expect(filter.accepts(_message('hello wor1d', user: 'd')), isTrue, reason: '91 is below 95');
    });

    test('other message types pass untouched', () {
      final filter = DanmakuMessageFilter(settings: const DanmakuFilterSettings(blockedUsers: ['x']));
      for (final type in [LiveMessageType.online, LiveMessageType.superChat, LiveMessageType.gift]) {
        expect(filter.accepts(_message('', user: 'x', type: type)), isTrue);
        expect(filter.accepts(_message('', user: 'x', type: type)), isTrue);
      }
    });

    test('clear forgets the gate, repeats and similar texts (another room)', () {
      final filter = DanmakuMessageFilter(
        settings: const DanmakuFilterSettings(collapseRepeated: true, similarityEnabled: true),
      );
      expect(filter.accepts(_message('hello world', id: 'x:1')), isTrue);
      expect(filter.accepts(_message('hello world', id: 'x:1')), isFalse);
      filter.clear();
      expect(filter.accepts(_message('hello world', id: 'x:1')), isTrue);
    });
  });

  group('DanmakuNoticeThrottle', () {
    test('the same notice within 3 s is dropped without extending the window', () {
      var now = DateTime(2026);
      final throttle = DanmakuNoticeThrottle(clock: () => now);
      expect(throttle.accepts('连接中'), isTrue);
      now = now.add(const Duration(seconds: 2));
      expect(throttle.accepts('连接中'), isFalse);
      now = now.add(const Duration(seconds: 1));
      expect(throttle.accepts('连接中'), isTrue, reason: '3 s after the shown one');
      expect(throttle.accepts('已连接'), isTrue);
      expect(throttle.accepts('连接中'), isTrue, reason: 'only the last notice is remembered');
    });

    test('typed notices compare by value', () {
      final throttle = DanmakuNoticeThrottle();
      expect(throttle.accepts(const DanmakuReconnecting(DanmakuInterruption.disconnected)), isTrue);
      expect(throttle.accepts(const DanmakuReconnecting(DanmakuInterruption.disconnected)), isFalse);
      expect(throttle.accepts(const DanmakuReconnecting(DanmakuInterruption.handshakeTimeout)), isTrue);
    });
  });
}
