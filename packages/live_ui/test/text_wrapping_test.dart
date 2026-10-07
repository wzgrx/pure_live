import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

/// The characters on the last line of [text] laid out [width] wide, joiners
/// and the full stop left out.
int _lastLineLength(String text, double width, {double fontSize = 12}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(fontSize: fontSize),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width);
  addTearDown(painter.dispose);
  final line = painter.getLineBoundary(TextPosition(offset: text.length - 1));
  return text.substring(line.start, line.end).replaceAll(wordJoiner, '').replaceAll('。', '').trim().runes.length;
}

void main() {
  group('withoutOrphan (A01.4 c1)', () {
    test('joins the last two Chinese characters, before any closing punctuation', () {
      expect(withoutOrphan('当进入热门/分区，首选的直播平台'), '当进入热门/分区，首选的直播平$wordJoiner台');
      expect(withoutOrphan('在“平台显示”里隐藏和排序。'), '在“平台显示”里隐藏和排$wordJoiner序。');
      expect(withoutOrphan('例如“弹幕速度”“代理”“画质”'), '例如“弹幕速度”“代理”“画$wordJoiner质”');
      expect(withoutOrphan('第一段\n第二段'), '第一$wordJoiner段\n第二$wordJoiner段');
    });

    test('in other text the last space does not break', () {
      expect(withoutOrphan('Tap one to switch to it.'), 'Tap one to switch to it.');
      expect(withoutOrphan('登录后填写 Cookie'), '登录后填写 Cookie');
    });

    test('nothing to join: unchanged', () {
      for (final text in ['', '台', '。', 'Cookie', 'A B'.substring(0, 1), '版本 2', '共 5 个']) {
        expect(withoutOrphan(text).replaceAll(' ', ' '), text);
      }
      expect(withoutOrphan('5 分钟'), '5 分$wordJoiner钟');
    });

    test('a line break before the last character takes the one before it along', () {
      // Eleven characters, ten to a line: one alone on the second line.
      const text = '进入热门首选的直播平台';
      const width = 10.5 * 12;
      expect(_lastLineLength(text, width), 1);
      expect(_lastLineLength(withoutOrphan(text), width), 2);
      // With a full stop after it: the stop stays with the character.
      expect(_lastLineLength('$text。', width), 1);
      expect(_lastLineLength(withoutOrphan('$text。'), width), 2);
    });

    testWidgets('setting rows, notes, status pages and banners use it; titles do not', (tester) async {
      const words = '当进入热门/分区，首选的直播平台';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                SettingsLinkRow(title: words, subtitle: words, onTap: () {}),
                const SettingsNote(words),
                const SizedBox(
                  height: 400,
                  child: AppStatusView(type: AppStatusType.empty, title: words, subtitle: words),
                ),
                const StatusBanner(kind: StatusBannerKind.info, text: words),
              ],
            ),
          ),
        ),
      );
      final joined = withoutOrphan(words);
      expect(find.text(joined, findRichText: true), findsNWidgets(4));
      expect(find.text(words, findRichText: true), findsNWidgets(2));
    });
  });
}
