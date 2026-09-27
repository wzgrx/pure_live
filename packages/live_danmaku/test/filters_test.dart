import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

final _t0 = DateTime.utc(2026, 9, 27, 12);

DanmakuChat _chat(
  String text, {
  String? id,
  String user = 'u',
  String name = 'Name',
  DateTime? sentAt,
  bool local = false,
  bool bot = false,
}) => DanmakuChat(
  room: 'douyu:1',
  session: 0,
  receivedAt: 0,
  id: id,
  sentAt: sentAt,
  userId: user,
  userName: name,
  text: text,
  isLocal: local,
  suspectedBot: bot,
);

void main() {
  group('FLT-1 gate', () {
    test('drops backlog older than 45 s and timestamps over 10 min ahead', () {
      final gate = DanmakuGate();
      expect(gate.accepts(_chat('a', sentAt: _t0.subtract(const Duration(seconds: 46))), _t0), isFalse);
      expect(gate.accepts(_chat('b', sentAt: _t0.subtract(const Duration(seconds: 44))), _t0), isTrue);
      expect(gate.accepts(_chat('c', sentAt: _t0.add(const Duration(minutes: 11))), _t0), isFalse);
      expect(gate.accepts(_chat('d', sentAt: _t0.add(const Duration(minutes: 9))), _t0), isTrue);
    });

    test('an id is accepted once in 10 min (REG-DANMAKU-009)', () {
      final gate = DanmakuGate();
      expect(gate.accepts(_chat('a', id: 'x'), _t0), isTrue);
      expect(gate.accepts(_chat('other text', id: 'x'), _t0.add(const Duration(minutes: 9))), isFalse);
      expect(gate.accepts(_chat('a', id: 'x'), _t0.add(const Duration(minutes: 10, seconds: 1))), isTrue);
    });

    test('without an id the same user and text only within 2.5 s (REG-DANMAKU-008)', () {
      final gate = DanmakuGate();
      expect(gate.accepts(_chat('哈哈'), _t0), isTrue);
      expect(gate.accepts(_chat('哈哈'), _t0.add(const Duration(seconds: 2))), isFalse);
      expect(gate.accepts(_chat('哈哈', user: 'v'), _t0.add(const Duration(seconds: 2))), isTrue);
      expect(gate.accepts(_chat('哈哈'), _t0.add(const Duration(seconds: 5))), isTrue);
    });

    test('keeps at most maxEntries keys, oldest out first; clear forgets', () {
      final gate = DanmakuGate(maxEntries: 2);
      for (final id in ['a', 'b', 'c']) {
        gate.accepts(_chat('t', id: id), _t0);
      }
      expect(gate.accepts(_chat('t', id: 'a'), _t0), isTrue);
      expect(gate.accepts(_chat('t', id: 'c'), _t0), isFalse);
      gate.clear();
      expect(gate.accepts(_chat('t', id: 'c'), _t0), isTrue);
    });
  });

  group('FLT-2 block list', () {
    test('users exactly and words as substrings, case-insensitive on both sides (REG-DANMAKU-002)', () {
      final blocks = DanmakuBlockList(users: [' SomeOne '], words: ['SPAM', '  ', '广告']);
      expect(blocks.matches(_chat('hello', name: 'someone')), isTrue);
      expect(blocks.matches(_chat('hello', name: 'someone2')), isFalse);
      expect(blocks.matches(_chat('buy Spam now')), isTrue);
      expect(blocks.matches(_chat('看广告')), isTrue);
      expect(blocks.matches(_chat('fine')), isFalse);
      expect(blocks.matches(_chat('spam', local: true)), isFalse);
      const gift = DanmakuGift(room: 'r', session: 0, receivedAt: 0, userName: 'SOMEONE', giftName: 'spam');
      expect(blocks.matches(gift), isTrue);
      expect(DanmakuBlockList().isEmpty, isTrue);
    });
  });

  group('FLT-3 repeat merge', () {
    test('whitespace and case folded; the window slides with the last occurrence', () {
      final filter = RepeatFilter();
      const window = Duration(seconds: 5);
      expect(filter.accepts('Hello  World', _t0, window), isTrue);
      expect(filter.accepts(' hello world ', _t0.add(const Duration(seconds: 4)), window), isFalse);
      expect(filter.accepts('HELLO WORLD', _t0.add(const Duration(seconds: 8)), window), isFalse);
      expect(filter.accepts('hello world', _t0.add(const Duration(seconds: 14)), window), isTrue);
    });
  });

  group('FLT-4 similarity', () {
    test('partial ratio', () {
      expect(partialRatio('abc', 'abc'), 100);
      expect(partialRatio('abc', 'xxabcxx'), 100);
      expect(partialRatio('abcd', 'abxd'), 75);
      expect(partialRatio('', 'abc'), 0);
      expect(partialRatio('主播好厉害', '主播真厉害'), 80);
      expect(partialRatio('哈哈哈哈哈', '呵呵呵呵呵'), 0);
      expect(partialRatio('a' * 80, '${'a' * 79}b'), 99);
    });

    test('isSimilar agrees with partialRatio at every threshold', () {
      const pairs = [
        ('主播好厉害', '主播真厉害啊'),
        ('666', '6666666'),
        ('今天天气不错', '明天天气也不错'),
        ('hello world', 'help word'),
        ('abc', 'xyz'),
      ];
      for (final (a, b) in pairs) {
        for (var threshold = 50; threshold <= 100; threshold += 5) {
          expect(isSimilar(a, b, threshold), partialRatio(a, b) >= threshold, reason: '$a / $b @ $threshold');
        }
      }
    });

    test('filter: exact repeats, similar text, cache time and budget', () {
      final filter = SimilarityFilter(maxComparisons: 2);
      bool accepts(String text, int seconds) => filter.accepts(
        text,
        _t0.add(Duration(seconds: seconds)),
        threshold: 85,
        window: const Duration(seconds: 3),
        capacity: 100,
      );
      expect(accepts('主播好厉害啊', 0), isTrue);
      expect(accepts('主播好厉害啊', 1), isFalse);
      expect(accepts('主播好厉害', 1), isFalse);
      expect(accepts('完全不同的话', 1), isTrue);
      expect(accepts('主播好厉害啊', 10), isTrue);
      accepts('一', 11);
      accepts('二', 11);
      accepts('三', 11);
      expect(filter.lastComparisons, 2);
    });
  });

  group('SMP sampler', () {
    test('keeps everything within budget', () {
      final sampler = DensitySampler();
      expect(sampler.pick(3, const Duration(milliseconds: 64), 100), [0, 1, 2]);
    });

    test('spreads the kept candidates evenly over the batch (SMP-2)', () {
      final sampler = DensitySampler();
      // 30 per second over 100 ms: 3 of 30.
      expect(sampler.pick(30, const Duration(milliseconds: 100), 30), [5, 15, 25]);
    });

    test('fractional budgets accumulate; a zero budget keeps nothing', () {
      final sampler = DensitySampler();
      var kept = 0;
      for (var i = 0; i < 100; i++) {
        kept += sampler.pick(10, const Duration(milliseconds: 64), DanmakuScreenBudget.pip.perSecond).length;
      }
      // 100 × 64 ms = 6.4 s at ≈4.29 per second.
      expect(kept, inInclusiveRange(26, 28));
      expect(sampler.pick(10, const Duration(seconds: 1), 0), isEmpty);
    });

    test('budgets from the emit interval with the 1.5 margin', () {
      expect(DanmakuScreenBudget.room.perSecond, closeTo(30, 1e-9));
      expect(DanmakuScreenBudget.emitting(const Duration(milliseconds: 100), margin: 1).perSecond, 10);
    });
  });

  group('model', () {
    test('super chat equality (§1, REG-DANMAKU-018)', () {
      DanmakuSuperChat sc({String? id, String name = 'a', String text = 't', int price = 30, int start = 0}) =>
          DanmakuSuperChat(
            room: 'r',
            session: 0,
            receivedAt: 0,
            id: id,
            userName: name,
            text: text,
            price: price,
            startAt: DateTime.fromMillisecondsSinceEpoch(start),
            endAt: DateTime.fromMillisecondsSinceEpoch(start + 60000),
          );
      expect(sc(id: '1'), sc(id: '1', text: 'other'));
      expect(sc(id: '1') == sc(id: '2'), isFalse);
      expect(sc(), sc(start: 5000));
      expect(sc() == sc(price: 50), isFalse);
      expect(sc(id: '1') == sc(), isFalse);
      expect({sc(), sc(start: 9)}, hasLength(1));
    });

    test('colours: numbers keep RGB, strings accept 4, 6 and 8 hex digits', () {
      expect(DanmakuColors.fromNumber(0xFF123456), 0x123456);
      expect(DanmakuColors.fromNumber(0xFF), 0xFF);
      expect(DanmakuColors.parse('#EDF5FF'), 0xEDF5FF);
      expect(DanmakuColors.parse('0x80EDF5FF'), 0xEDF5FF);
      expect(DanmakuColors.parse('F5FF'), 0x00F5FF);
      expect(DanmakuColors.parse('nope'), isNull);
      expect(DanmakuColors.parse(''), isNull);
    });

    test('reconnect waits (CONN-3)', () {
      const policy = ReconnectPolicy();
      expect([for (var n = 1; n <= 8; n++) policy.delay(n, 1).inSeconds], [2, 3, 4, 5, 6, 6, 6, 6]);
      expect([for (var n = 1; n <= 6; n++) policy.delay(n, 2).inSeconds], [1, 2, 2, 3, 3, 4]);
      expect(policy.exhausted(8), isFalse);
      expect(policy.exhausted(9), isTrue);
    });
  });
}
