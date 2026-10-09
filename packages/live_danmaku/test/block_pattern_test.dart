import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

LiveMessage _message(String text, {bool local = false, List<LiveEmote> emotes = const []}) => LiveMessage(
  type: LiveMessageType.chat,
  userName: 'viewer',
  userId: 'viewer',
  message: text,
  color: LiveMessageColor.white,
  isLocal: local,
  emotes: emotes,
);

/// D02.2: block words written `/…/` are patterns; the emoticon-only and
/// length blocks; what hid a message.
void main() {
  group('patterns in the block list (c1)', () {
    test(r'/^\d+$/ blocks the all-digit messages only', () {
      final list = DanmakuBlockList(keywords: [r'/^\d+$/']);
      expect(list.blocks(_message('666')), isTrue);
      expect(list.blocks(_message('6 6 6')), isFalse);
      expect(list.blocks(_message('主播666')), isFalse);
      expect(list.isEmpty, isFalse);
    });

    test('a pattern ignores case, and its source is not lower-cased', () {
      final list = DanmakuBlockList(keywords: ['/abc/', r'/^\D+$/']);
      expect(list.blocks(_message('xxABCxx')), isTrue);
      expect(list.blocks(_message('xxAbcxx')), isTrue);
      expect(list.blocks(_message('哈哈')), isTrue, reason: r'\D stays "not a digit" (lower-casing made it \d)');
      expect(list.blocks(_message('12')), isFalse);
    });

    test('a plain word still blocks what contains it; slashes inside do not make a pattern', () {
      final list = DanmakuBlockList(keywords: ['广告', 'a/b', '/', '//', '/x']);
      expect(list.blocks(_message('这是广告位')), isTrue);
      expect(list.blocks(_message('see a/b here')), isTrue);
      expect(list.blocks(_message('1/2')), isTrue, reason: '"/" alone is a plain word');
      expect(list.blocks(_message('http://')), isTrue, reason: '"//" is a plain word');
      expect(list.blocks(_message('/xyz')), isTrue);
      expect(DanmakuBlockPattern.isPattern('/'), isFalse);
      expect(DanmakuBlockPattern.isPattern('//'), isFalse);
      expect(DanmakuBlockPattern.isPattern(' /a/ '), isTrue);
    });

    test('a pattern that does not compile is skipped, never thrown', () {
      late DanmakuBlockList list;
      expect(() => list = DanmakuBlockList(keywords: ['/[/', '/a{2,1}/', '/(/']), returnsNormally);
      expect(list.isEmpty, isTrue);
      expect(list.blocks(_message('[')), isFalse, reason: 'not taken as the plain word "/[/" either');
      expect(DanmakuBlockPattern.compile('/[/'), isNull);
    });

    test('only the first 200 characters are matched', () {
      final list = DanmakuBlockList(keywords: ['/广告/']);
      expect(list.blocks(_message('${'哈' * 198}广告')), isTrue);
      expect(list.blocks(_message('${'哈' * 199}广告')), isFalse);
      // A plain word still looks at the whole text (3.x).
      expect(DanmakuBlockList(keywords: ['广告']).blocks(_message('${'哈' * 500}广告')), isTrue);
    });

    test('a pattern over 200 characters, or a repeated group that repeats, blocks nothing', () {
      final long = '/${'a' * 199}/';
      expect(long.length, 201);
      expect(DanmakuBlockPattern.compile(long), isNull);
      expect(DanmakuBlockPattern.compile('/${'a' * 198}/'), isNotNull);
      for (final pattern in ['/(a+)+b/', '/(a|aa)*b/', r'/(\w*)*$/', '/((ab)+c)*/', '/(.*x){5}/', '/(?:a+)+/']) {
        expect(DanmakuBlockPattern.compile(pattern), isNull, reason: pattern);
        expect(DanmakuBlockList(keywords: [pattern]).isEmpty, isTrue, reason: pattern);
      }
    });

    test('matchesText: the words alone, for taking matching lines off the list', () {
      final list = DanmakuBlockList(users: ['spammer'], keywords: [r'/^[0-9]+$/', 'ad']);
      expect(list.matchesText('123'), isTrue);
      expect(list.matchesText('AD here'), isTrue);
      expect(list.matchesText('spammer'), isFalse);
    });
  });

  group('DanmakuBlockPattern.check (adding by hand)', () {
    test('plain words and good patterns pass', () {
      for (final word in [
        '广告',
        '/',
        r'/^\d+$/',
        '/abc/',
        '/(qq|vx|微信)/',
        '/[ab]+c?/',
        '/加.*群/',
        '/a{2,5}/',
        '/(ab)?c/',
      ]) {
        expect(DanmakuBlockPattern.check(word), isNull, reason: word);
      }
    });

    test('each problem is told apart', () {
      expect(DanmakuBlockPattern.check('/[/'), DanmakuBlockPatternProblem.invalid);
      expect(DanmakuBlockPattern.check('/${'a' * 199}/'), DanmakuBlockPatternProblem.tooLong);
      expect(DanmakuBlockPattern.check('/(a+)+b/'), DanmakuBlockPatternProblem.nestedRepeat);
      expect(DanmakuBlockPattern.check('/(哈|呵)+/'), DanmakuBlockPatternProblem.nestedRepeat);
      expect(DanmakuBlockPattern.check(r'/(\d{2}){3}/'), DanmakuBlockPatternProblem.nestedRepeat);
    });

    test('escaped and bracketed quantifiers and brackets are not counted', () {
      for (final word in [r'/(a\+)+/', '/([+*])+/', r'/(\(x\))*/', '/(?=a)b/', '/(?<n>a)b/', '/(a{,})+/']) {
        expect(DanmakuBlockPattern.check(word), isNull, reason: word);
      }
    });

    test('a polynomial pattern that takes too long is refused, quickly', () {
      final watch = Stopwatch()..start();
      expect(DanmakuBlockPattern.check('/.*.*.*.*.*.*x/'), DanmakuBlockPatternProblem.tooSlow);
      watch.stop();
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)), reason: 'the texts grow in steps');
    });
  });

  group('the emoticon-only and length blocks (c3)', () {
    test('shape: Unicode emoji, the codes a message names, spaces', () {
      expect(danmakuTextShape('😂😂'), (length: 2, emoteOnly: true));
      expect(danmakuTextShape(' 👍🏻 ❤️ ').emoteOnly, isTrue);
      expect(danmakuTextShape('🇨🇳').emoteOnly, isTrue);
      expect(danmakuTextShape('哈😂').emoteOnly, isFalse, reason: 'a character among them');
      expect(danmakuTextShape('123').emoteOnly, isFalse, reason: 'digits are keycap parts, not emoji');
      expect(danmakuTextShape('   ').emoteOnly, isFalse, reason: 'nothing at all');
      expect(danmakuTextShape('', emotes: 2), (length: 2, emoteOnly: true));
      expect(danmakuTextShape('哈', emotes: 2), (length: 3, emoteOnly: false));
      final named = _message(
        ':smile::smile: ',
        emotes: const [LiveEmote(code: ':smile:', url: 'https://example.invalid/s.png')],
      );
      expect(danmakuMessageShape(named), (length: 2, emoteOnly: true));
      expect(danmakuMessageShape(_message('[笑哭][笑哭]')).emoteOnly, isFalse, reason: 'bundled lists are the app’s');
    });

    DanmakuMessageFilter filter(DanmakuFilterSettings settings) =>
        DanmakuMessageFilter(settings: settings, clock: () => DateTime.utc(2026, 10, 9));

    test('off by default: everything passes as before', () {
      const settings = DanmakuFilterSettings();
      expect(settings.blockEmoteOnly, isFalse);
      expect(settings.blockLong, isFalse);
      expect(settings.blockLongLength, 30);
      final plain = filter(settings);
      expect(plain.accepts(_message('😂😂😂')), isTrue);
      expect(plain.accepts(_message('长' * 300)), isTrue);
    });

    test('emoticon-only: a message of emoticons is hidden, one with a character is not', () {
      final only = filter(const DanmakuFilterSettings(blockEmoteOnly: true));
      expect(only.judge(_message('😂😂😂')), DanmakuVerdict.blocked);
      expect(only.judge(_message('哈😂')), DanmakuVerdict.shown);
      expect(only.judge(_message('😂', local: true)), DanmakuVerdict.shown, reason: 'local danmaku are not blocked');
    });

    test('length: over N characters is hidden; N is used clamped to 10..100', () {
      final long = filter(const DanmakuFilterSettings(blockLong: true, blockLongLength: 12));
      expect(long.accepts(_message('一' * 12)), isTrue);
      expect(long.judge(_message('二' * 13)), DanmakuVerdict.blocked);
      final low = filter(const DanmakuFilterSettings(blockLong: true, blockLongLength: 1));
      expect(low.accepts(_message('三' * 10)), isTrue);
      expect(low.accepts(_message('四' * 11)), isFalse);
      final high = filter(const DanmakuFilterSettings(blockLong: true, blockLongLength: 500));
      expect(high.accepts(_message('五' * 100)), isTrue);
      expect(high.accepts(_message('六' * 101)), isFalse);
    });

    test("the app's shaper decides what an emoticon is", () {
      final only = filter(const DanmakuFilterSettings(blockEmoteOnly: true))
        ..shapeOf = (message) => danmakuTextShape(message.message.replaceAll('[笑哭]', ''), emotes: 1);
      expect(only.accepts(_message('[笑哭][笑哭]')), isFalse);
      expect(only.accepts(_message('好[笑哭]')), isTrue);
    });
  });

  test('judge tells what hid a message (c4 counts "blocked" only)', () {
    var now = DateTime.utc(2026, 10, 9);
    final filter = DanmakuMessageFilter(
      settings: const DanmakuFilterSettings(blockedKeywords: [r'/^[0-9]+$/'], collapseRepeated: true),
      clock: () => now,
    );
    expect(filter.judge(_message('123')), DanmakuVerdict.blocked);
    expect(filter.judge(_message('hello')), DanmakuVerdict.shown);
    now = now.add(const Duration(seconds: 3));
    expect(filter.judge(_message('hello')), DanmakuVerdict.repeated);
    const copy = LiveMessage(
      type: LiveMessageType.chat,
      userName: 'a',
      message: 'x',
      messageId: 'm1',
      color: LiveMessageColor.white,
    );
    expect(filter.judge(copy), DanmakuVerdict.shown);
    expect(filter.judge(copy), DanmakuVerdict.duplicate);
    expect(
      filter.judge(
        const LiveMessage(type: LiveMessageType.online, userName: '', message: '1', color: LiveMessageColor.white),
      ),
      DanmakuVerdict.shown,
    );
  });
}
