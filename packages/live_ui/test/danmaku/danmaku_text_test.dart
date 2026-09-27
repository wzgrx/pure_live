import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:live_ui/src/danmaku/danmaku_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('display text', () {
    test('one line, trimmed', () {
      expect(danmakuDisplayText('  第一行\n第二行\r\n\t尾 ', noEmoji: false), '第一行 第二行 尾');
    });

    test('no-emoji mode strips pictographs, modifiers, joiners, flags and keycaps', () {
      expect(danmakuDisplayText('哈哈😂', noEmoji: true), '哈哈');
      expect(danmakuDisplayText('👍🏻 好', noEmoji: true), '好');
      expect(danmakuDisplayText('👨‍👩‍👧 家', noEmoji: true), '家');
      expect(danmakuDisplayText('1️⃣ 666', noEmoji: true), '1 666');
      expect(danmakuDisplayText('#1 冲 😀 冲', noEmoji: true), '#1 冲 冲');
    });

    test('emoji-only messages leave nothing', () {
      expect(danmakuDisplayText('🇨🇳🎉🎉', noEmoji: true), isEmpty);
      expect(danmakuDisplayText('🇨🇳🎉🎉', noEmoji: false), '🇨🇳🎉🎉');
    });

    test('bracketed platform emoticons are text here', () {
      expect(danmakuDisplayText('[doge]', noEmoji: true), '[doge]');
    });
  });

  group('glyph', () {
    test('measures text plus the outline', () {
      const style = DanmakuStyle(fontSize: 20, strokeWidth: 2);
      final plain = DanmakuGlyph.layout('abcd', const Color(0xFFFFFFFF), style.copyWith(stroke: false));
      final outlined = DanmakuGlyph.layout('abcd', const Color(0xFFFFFFFF), style);
      expect(plain.width, greaterThan(0));
      expect(outlined.width, plain.width + 2);
      expect(outlined.height, plain.height + 2);
    });
  });

  group('glyph cache', () {
    DanmakuGlyph glyph(String text) => DanmakuGlyph.layout(text, const Color(0xFFFFFFFF), const DanmakuStyle());

    test('hits share one glyph by text and color', () {
      final cache = DanmakuGlyphCache(4);
      final key = DanmakuGlyphCache.keyOf('666', const Color(0xFFFFFFFF));
      expect(cache.acquire(key), isNull);
      final first = cache.adopt(key, glyph('666'));
      expect(cache.acquire(key), same(first));
      expect(cache.acquire(DanmakuGlyphCache.keyOf('666', const Color(0xFFFF0000))), isNull);
    });

    test('evicts least recently used; a glyph in use is freed only when released', () {
      final cache = DanmakuGlyphCache(2);
      final a = cache.adopt('a', glyph('a'));
      final b = cache.adopt('b', glyph('b'));
      cache
        ..release(b)
        ..acquire('a')
        ..release(a);
      final c = cache.adopt('c', glyph('c'));
      expect(cache.length, 2);
      expect(b.isDisposed, isTrue, reason: 'b was least recently used and unused');
      expect(cache.acquire('b'), isNull);

      cache.capacity = 0;
      expect(cache.length, 0);
      expect(a.isDisposed, isFalse, reason: 'a is still on screen');
      expect(c.isDisposed, isFalse);
      cache
        ..release(a)
        ..release(c);
      expect(a.isDisposed, isTrue);
      expect(c.isDisposed, isTrue);
    });

    test('clear frees unused glyphs at once (REN-9)', () {
      final cache = DanmakuGlyphCache(8);
      final used = cache.adopt('a', glyph('a'));
      final idle = cache.adopt('b', glyph('b'));
      cache
        ..release(idle)
        ..clear();
      expect(idle.isDisposed, isTrue);
      expect(used.isDisposed, isFalse);
      cache.release(used);
      expect(used.isDisposed, isTrue);
    });
  });
}
