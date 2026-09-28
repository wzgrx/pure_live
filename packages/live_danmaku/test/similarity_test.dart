import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

/// Scores of fuzzywuzzy 1.2.0's `partialRatio` (3.x's scorer), recorded with
/// that package; the second half are pairs where scoring every window (the
/// archived v4's approach) would answer differently.
const _fuzzywuzzy = <(String, String, int)>[
  ('hello world', 'hello world', 100),
  ('hello world', 'hello wor1d', 91),
  ('hello world', 'completely different', 36),
  ('Hello', 'hello', 80),
  ('哈哈哈哈', '哈哈哈哈哈哈哈', 100),
  ('666', '6666666', 100),
  ('主播好厉害', '主播好厉害啊啊啊', 100),
  ('主播好厉害', '这主播好厉害', 100),
  ('加油', '加油加油加油', 100),
  ('abcd', 'xxxxab', 50),
  ('😀😀', '😀😀😀', 100),
  ('😀', '😁', 50),
  ('a', '', 0),
  ('', 'abc', 0),
  ('x', 'x', 100),
  ('前方高能', '前方高能预警', 100),
  ('awsl', 'awslawsl', 100),
  ('上车上车', '上车', 100),
  ('ab', 'ba', 50),
  ('abc', 'cab', 67),
  ('same text', 'same text', 100),
  ('ax0qz', 'by1rw', 0),
  ('这波操作666', '这波操作777', 57),
  ('来了来了', '我来了我来了', 75),
  ('[doge][doge]', '[doge]', 100),
  ('a哈哈bb啊', 'b哈a啊b66b6666', 33),
  ('aa6aabb', '6aa哈b哈b66', 57),
  ('6啊6b啊', '啊6bba哈bb哈哈6', 40),
  ('啊6啊a啊', '6aa啊a哈6b啊哈', 40),
  ('啊啊哈6啊哈', '哈66bb6啊', 36),
  ('哈6a哈哈6', 'a6哈哈啊6啊b6a啊b6', 50),
  ('哈6b啊', 'a6b啊6啊啊b啊啊b6', 50),
  ('ababb', '哈aabb哈啊啊ab', 60),
  ('b啊哈哈哈', '6哈6a哈ba', 20),
  ('b6哈啊啊', '6啊啊啊b6a6b66', 40),
  ('b啊a6', '啊a哈b', 57),
  ('b哈啊aa', '哈abba哈6哈6b6', 40),
  ('6啊b6', '啊6baa啊b', 57),
  ('a啊6哈b', '6a6bb哈6a啊啊啊啊哈', 40),
  ('aab啊啊啊', '啊啊b哈b啊哈a哈哈啊', 33),
];

void main() {
  group('partialRatio', () {
    test("gives fuzzywuzzy's scores", () {
      for (final (s1, s2, expected) in _fuzzywuzzy) {
        expect(partialRatio(s1, s2), expected, reason: '"$s1" vs "$s2"');
      }
    });

    test('is case-sensitive and compares UTF-16 code units', () {
      expect(partialRatio('ABC', 'abc'), 0);
      // One emoji is two code units; a different emoji shares the high one.
      expect(partialRatio('😀', '😁'), 50);
    });

    test('with equal lengths the second text is the shorter one', () {
      // The alignment path depends on the direction; both directions happen
      // to agree here, but the choice is 3.x's.
      expect(partialRatio('abcd', 'dcba'), partialRatio('dcba', 'abcd'));
    });
  });

  group('DanmakuSimilarityFilter', () {
    // 3.x test/danmaku_similarity_filter_test.dart.
    test('rejects exact and fuzzy repeats while retaining new text', () {
      final filter = DanmakuSimilarityFilter(similarityThreshold: 80);
      expect(filter.shouldDisplay('hello world'), isTrue);
      expect(filter.shouldDisplay('hello world'), isFalse);
      expect(filter.shouldDisplay('hello wor1d'), isFalse);
      expect(filter.shouldDisplay('completely different'), isTrue);
    });

    test('expires old references using the configured window', () {
      var now = DateTime(2026);
      // 3.x passed the 3 s default explicitly here.
      final filter = DanmakuSimilarityFilter(similarityThreshold: 100, clock: () => now);
      expect(filter.shouldDisplay('same text'), isTrue);
      now = now.add(const Duration(seconds: 2));
      expect(filter.shouldDisplay('same text'), isFalse);
      now = now.add(const Duration(seconds: 4));
      expect(filter.shouldDisplay('same text'), isTrue);
    });

    test('bounds retained cache and fuzzy comparisons independently', () {
      final filter = DanmakuSimilarityFilter(similarityThreshold: 100, maxCacheSize: 10, maxComparisons: 3);
      for (final text in const [
        'ax0qz',
        'by1rw',
        'cz2sv',
        'du3tx',
        'ev4uy',
        'fw5vz',
        'gx6wa',
        'hy7xb',
        'iz8yc',
        'ja9zd',
        'kb0ae',
      ]) {
        expect(filter.shouldDisplay(text), isTrue);
        expect(filter.lastComparisonCount, lessThanOrEqualTo(3));
      }
      expect(filter.cacheSize, 10);
      expect(filter.maxComparisons, 3);
    });

    test('empty text is ignored and clear resets the cache', () {
      final filter = DanmakuSimilarityFilter();
      expect(filter.shouldDisplay('   '), isFalse);
      expect(filter.shouldDisplay('message'), isTrue);
      filter.clear();
      expect(filter.cacheSize, 0);
      expect(filter.shouldDisplay('message'), isTrue);
    });

    // Derived from the 3.x code.
    test('defaults are 85, 3 s, 100 texts and 96 comparisons', () {
      final filter = DanmakuSimilarityFilter();
      expect(filter.similarityThreshold, 85);
      expect(filter.cacheDuration, const Duration(seconds: 3));
      expect(filter.maxCacheSize, 100);
      expect(filter.maxComparisons, 96);
    });

    test('the threshold is inclusive', () {
      // "这波操作777" scores 57 against "这波操作666".
      final at = DanmakuSimilarityFilter(similarityThreshold: 57)..shouldDisplay('这波操作666');
      expect(at.shouldDisplay('这波操作777'), isFalse);
      final above = DanmakuSimilarityFilter(similarityThreshold: 58)..shouldDisplay('这波操作666');
      expect(above.shouldDisplay('这波操作777'), isTrue);
    });

    test('texts are trimmed but keep case, emoji and inner spaces', () {
      final filter = DanmakuSimilarityFilter(similarityThreshold: 100);
      expect(filter.shouldDisplay('  哈哈😀 '), isTrue);
      expect(filter.shouldDisplay('哈哈😀'), isFalse, reason: 'trimmed to the same text');
      expect(filter.shouldDisplay('ABC'), isTrue);
      expect(filter.shouldDisplay('abc'), isTrue, reason: 'case counts');
      expect(filter.shouldDisplay('a b'), isTrue);
      expect(filter.shouldDisplay('a  b'), isTrue, reason: 'inner whitespace is kept');
    });

    test('a contained text is similar: partial matching', () {
      final filter = DanmakuSimilarityFilter()..shouldDisplay('主播好厉害');
      expect(filter.shouldDisplay('这主播好厉害啊'), isFalse);
      expect(filter.shouldDisplay('好'), isFalse, reason: 'one character inside a cached text scores 100');
    });

    test('an entry expires only after strictly more than the window', () {
      var now = DateTime(2026);
      final filter = DanmakuSimilarityFilter(clock: () => now)..shouldDisplay('x');
      now = now.add(const Duration(seconds: 3));
      expect(filter.shouldDisplay('x'), isFalse, reason: 'exactly 3 s is still inside');
      now = now.add(const Duration(seconds: 3, milliseconds: 1));
      expect(filter.shouldDisplay('x'), isTrue);
    });

    test('a hidden repeat restarts the window of the text it matched', () {
      var now = DateTime(2026);
      final filter = DanmakuSimilarityFilter(clock: () => now)..shouldDisplay('hello world');
      for (var second = 0; second < 4; second++) {
        now = now.add(const Duration(seconds: 2));
        expect(filter.shouldDisplay('hello wor1d'), isFalse);
      }
      expect(filter.cacheSize, 1, reason: 'the similar text refreshed the cached one instead of being added');
    });

    test('only the newest entries are compared; older ones are kept', () {
      final filter = DanmakuSimilarityFilter(maxComparisons: 2)
        ..shouldDisplay('hello world')
        ..shouldDisplay('ax0qz')
        ..shouldDisplay('by1rw');
      expect(filter.shouldDisplay('hello wor1d'), isTrue, reason: 'the similar text is outside the newest two');
      expect(filter.lastComparisonCount, 2);
      expect(filter.shouldDisplay('hello world'), isFalse, reason: 'an exact match is found in the whole cache');
    });

    test('the oldest entry goes when the cache is full', () {
      final filter = DanmakuSimilarityFilter(similarityThreshold: 100, maxCacheSize: 2)
        ..shouldDisplay('ax0qz')
        ..shouldDisplay('by1rw')
        ..shouldDisplay('cz2sv');
      expect(filter.cacheSize, 2);
      expect(filter.shouldDisplay('ax0qz'), isTrue);
      expect(filter.shouldDisplay('cz2sv'), isFalse);
    });

    test('settings are clamped and a smaller cache is trimmed at once', () {
      final filter = DanmakuSimilarityFilter(similarityThreshold: 150, maxCacheSize: 5000, maxComparisons: 0);
      expect(filter.similarityThreshold, 100);
      expect(filter.maxCacheSize, 1000);
      expect(filter.maxComparisons, 1);
      ['ax0qz', 'by1rw', 'cz2sv'].forEach(filter.shouldDisplay);
      filter.updateConfig(similarityThreshold: -5, maxCacheSize: 0, cacheDuration: const Duration(seconds: 9));
      expect(filter.similarityThreshold, 0);
      expect(filter.maxCacheSize, 1);
      expect(filter.cacheSize, 1);
      expect(filter.cacheDuration, const Duration(seconds: 9));
    });
  });
}
