// D02.2 benchmark: 200 chat messages a second through the room's filter
// with the similarity filter on (3.x's defaults: 85, 3 s, 100 texts), with
// no block words, 20 plain words, 20 patterns, and 20 patterns plus the
// emoticon-only and length blocks. Prints the time per simulated second
// and per message; record.md keeps the numbers (compare runs with each
// other: this is the test host, not a phone).
//
// The default run is 5 simulated seconds; a longer one:
//   BLOCK_BENCH_SECONDS=60 dart test test/block_benchmark_test.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:test/test.dart';

final int _seconds = int.tryParse(Platform.environment['BLOCK_BENCH_SECONDS'] ?? '') ?? 5;
const int _rate = 200;

const List<String> _texts = [
  '666',
  '这波团战打得漂亮',
  '前排',
  '主播今天状态不错啊，这把能赢吗',
  '哈哈哈哈哈哈',
  '😂😂😂',
  'GG',
  '有没有人知道这个皮肤叫什么名字？',
  '加我微信 abc12345 送福利',
  '1111111111',
];

/// 20 plain words and 20 patterns of the kinds people block.
final List<String> _words = [for (var i = 0; i < 20; i++) '屏蔽词$i'];
final List<String> _patterns = [
  r'/^\d+$/',
  r'/^[0-9]+$/',
  '/(qq|vx|微信|薇信)/',
  '/加.*群/',
  r'/\d{6,}/',
  r'/^(哈)+$/',
  '/[a-z]{3}[0-9]{4}/',
  '/福利.*领/',
  r'/^.{50,}$/',
  r'/(.)\1{5}/',
  '/代练|代打/',
  r'/https?:\/\//',
  r'/^[?？!！]+$/',
  '/菜.{0,4}主播/',
  '/[一二三四五六七八九十]{4}/',
  r'/^gg$/',
  r'/\b(fuck|shit)\b/',
  '/抽奖.*私信/',
  r'/^\s*$/',
  '/(刷|送).*(礼物|火箭)/',
];

String _text(math.Random random, int i) {
  final base = _texts[random.nextInt(_texts.length)];
  // One in twenty is long (a pasted paragraph), as busy rooms have.
  if (i % 20 == 0) return '$base ${'复制粘贴的长段文字' * (10 + random.nextInt(25))}';
  return '$base#${random.nextInt(50)}';
}

/// The fastest of three runs (the first ones warm the compiler up).
({Duration total, int blocked}) _best(DanmakuFilterSettings settings) {
  final runs = [for (var i = 0; i < 3; i++) _run(settings)]..sort((a, b) => a.total.compareTo(b.total));
  return runs.first;
}

/// The block list alone over the same messages: what the patterns cost on
/// every message, blocked or not.
Duration _blockListOnly(List<String> keywords) {
  final random = math.Random(42);
  final list = DanmakuBlockList(keywords: keywords);
  final texts = [for (var i = 0; i < _seconds * _rate; i++) _text(random, i)];
  var best = const Duration(days: 1);
  for (var run = 0; run < 3; run++) {
    final watch = Stopwatch()..start();
    texts.forEach(list.matchesText);
    watch.stop();
    if (watch.elapsed < best) best = watch.elapsed;
  }
  return best;
}

({Duration total, int blocked}) _run(DanmakuFilterSettings settings) {
  final random = math.Random(42);
  var now = DateTime.utc(2026, 10, 9);
  final filter = DanmakuMessageFilter(settings: settings, clock: () => now);
  final watch = Stopwatch();
  var blocked = 0;
  for (var i = 0; i < _seconds * _rate; i++) {
    now = now.add(const Duration(milliseconds: 1000 ~/ _rate));
    final message = LiveMessage(
      type: LiveMessageType.chat,
      userName: 'viewer${random.nextInt(500)}',
      userId: 'u$i',
      messageId: 'm$i',
      message: _text(random, i),
      color: LiveMessageColor.white,
    );
    watch.start();
    if (filter.judge(message) == DanmakuVerdict.blocked) blocked++;
    watch.stop();
  }
  return (total: watch.elapsed, blocked: blocked);
}

void main() {
  test('20 patterns with the similarity filter, 200 messages a second for $_seconds s', () {
    const similarity = DanmakuFilterSettings(similarityEnabled: true);
    final runs = {
      'similarity only': similarity,
      '+ 20 plain words': DanmakuFilterSettings(similarityEnabled: true, blockedKeywords: _words),
      '+ 20 patterns': DanmakuFilterSettings(similarityEnabled: true, blockedKeywords: _patterns),
      '+ 20 patterns, emoticon-only, length 30': DanmakuFilterSettings(
        similarityEnabled: true,
        blockedKeywords: _patterns,
        blockEmoteOnly: true,
        blockLong: true,
      ),
    };
    final results = {for (final MapEntry(:key, :value) in runs.entries) key: _best(value)};
    String perSecond(Duration total) => (total.inMicroseconds / _seconds / 1000).toStringAsFixed(2);
    String perMessage(Duration total) => (total.inMicroseconds / (_seconds * _rate)).toStringAsFixed(1);
    final lines = [
      for (final MapEntry(key: name, value: (:total, :blocked)) in results.entries)
        '$name: ${perSecond(total)} ms per second, ${perMessage(total)} µs per message, $blocked blocked',
      for (final (name, keywords) in [('20 plain words', _words), ('20 patterns', _patterns)])
        'block list alone, $name: ${perMessage(_blockListOnly(keywords))} µs per message',
    ];
    // The numbers are the benchmark's output (record.md).
    // ignore: avoid_print
    print('D02.2 filter benchmark (${_seconds * _rate} messages)\n${lines.join('\n')}');
    final patterns = results['+ 20 patterns, emoticon-only, length 30']!;
    expect(patterns.blocked, greaterThan(0));
    // Generous for a loaded test host: a fifth of every second.
    expect(patterns.total.inMicroseconds / _seconds, lessThan(200000));
  });

  test('checking a pattern by hand takes little time', () {
    final watch = Stopwatch()..start();
    for (final pattern in _patterns) {
      expect(DanmakuBlockPattern.check(pattern), isNull, reason: pattern);
    }
    watch.stop();
    // The benchmark's output.
    // ignore: avoid_print
    print('D02.2 check of ${_patterns.length} patterns: ${watch.elapsedMilliseconds} ms');
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });
}
