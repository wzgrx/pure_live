// B08 c1, c2: the chat feed tells its listeners at most once a frame, the
// line parses its emoticons once, and the names read at 4.5:1.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/shared/danmaku/emotes.dart';

LiveMessage _chat(String text, {String id = '', String user = 'u', LiveMessageColor? color}) => LiveMessage(
  type: LiveMessageType.chat,
  userName: user,
  userId: user,
  message: text,
  color: color ?? LiveMessageColor.white,
  messageId: id,
);

/// A scheduler run by hand: the flushes wait in [due].
final class _Frames {
  final List<VoidCallback> due = [];

  void schedule(VoidCallback flush) => due.add(flush);

  void frame() {
    final now = [...due];
    due.clear();
    for (final flush in now) {
      flush();
    }
  }
}

void main() {
  group('the feed (c1)', () {
    test('any number of changes between two frames: one schedule, one notification', () {
      final frames = _Frames();
      final feed = ChatFeed(schedule: frames.schedule);
      addTearDown(feed.dispose);
      var heard = 0;
      feed.addListener(() => heard++);
      for (var i = 0; i < 50; i++) {
        feed.add(ChatLine.chat(_chat('第 $i 条')));
      }
      expect(feed.length, 50, reason: 'the lines change at once');
      expect(feed.added, 50);
      expect(frames.due, hasLength(1));
      expect(feed.pending, isTrue);
      expect(heard, 0, reason: 'nobody hears before the frame');
      frames.frame();
      expect(heard, 1);
      expect(feed.pending, isFalse);
      frames.frame();
      expect(heard, 1, reason: 'nothing new, nothing to hear');

      // The next frame's batch.
      feed
        ..add(ChatLine.chat(_chat('a')))
        ..retract(const LiveRetraction.message('none'))
        ..add(ChatLine.chat(_chat('b')));
      expect(frames.due, hasLength(1));
      frames.frame();
      expect(heard, 2);
    });

    test('a line composed here is heard at once; the frame then has nothing left', () {
      final frames = _Frames();
      final feed = ChatFeed(schedule: frames.schedule);
      addTearDown(feed.dispose);
      var heard = 0;
      feed
        ..addListener(() => heard++)
        ..add(ChatLine.chat(_chat('本地')))
        ..flush();
      expect(heard, 1);
      frames.frame();
      expect(heard, 1);
    });

    test('taken-back lines are marked; the removals are kept for a list holding older lines', () {
      final frames = _Frames();
      final feed = ChatFeed(capacity: 3, schedule: frames.schedule);
      addTearDown(feed.dispose);
      final lines = [for (var i = 0; i < 4; i++) ChatLine.chat(_chat('$i', id: 'm$i', user: 'u$i'))]..forEach(feed.add);
      expect(feed.lines.map((line) => line.text), ['1', '2', '3']);
      expect(lines.first.removed, isFalse, reason: 'dropped by the capacity, not taken back');
      expect(feed.removals, 0);
      expect(feed.removalsSince(0), isEmpty);
      feed.retract(const LiveRetraction.message('m2'));
      expect(lines[2].removed, isTrue);
      expect(feed.removals, 1);
      // Line 0 left the feed already; a list that still shows it learns of
      // its retraction from the test.
      feed.retract(const LiveRetraction.message('m0'));
      expect(feed.removals, 2);
      final tests = feed.removalsSince(1)!;
      expect(tests, hasLength(1));
      expect(tests.single(lines[0]), isTrue);
      expect(tests.single(lines[1]), isFalse);
      feed.removeWhere((line) => line.text == '3');
      expect(lines[3].removed, isTrue);
      expect(feed.removals, 3);
      expect(feed.removalsSince(0), hasLength(3));
      expect(feed.lines.map((line) => line.text), ['1']);
      for (var i = 0; i < 70; i++) {
        feed.removeWhere((_) => false);
      }
      expect(feed.removalsSince(0), isNull, reason: 'only the last 64 are kept');
      expect(feed.removalsSince(feed.removals - 64), hasLength(64));
    });

    test('a disposed feed tells nobody', () {
      final frames = _Frames();
      final feed = ChatFeed(schedule: frames.schedule)..add(ChatLine.chat(_chat('x')));
      var heard = 0;
      feed
        ..addListener(() => heard++)
        ..dispose();
      frames.frame();
      expect(heard, 0);
    });

    test('the emoticons of a line are parsed once per table', () {
      final table = EmoteTable.of(const {'[笑哭]': (asset: 'assets/emo/images/bilibili/xk.png', url: '')});
      final line = ChatLine.chat(_chat('哈[笑哭]'));
      final first = line.segments(table);
      expect(first, const [
        ChatTextSegment('哈'),
        ChatEmoteSegment(url: '', alt: '[笑哭]', asset: 'assets/emo/images/bilibili/xk.png'),
      ]);
      expect(line.segments(table), same(first), reason: 'cached on the line');
      // B09 c7: the flying layer asks for the same message and gets the
      // same parse.
      expect(chatSegments(line.message!, table), same(first));
      final plain = line.segments(EmoteTable.empty);
      expect(plain, const [ChatTextSegment('哈[笑哭]')], reason: 'another table parses again');
      expect(line.segments(EmoteTable.empty), same(plain));
      expect(ChatLine.system('连接中').segments(table), const [ChatTextSegment('连接中')]);
    });
  });

  group('name colours (c2, audit B-5)', () {
    // Platform colours as they come: the fixed palettes of Bilibili, Douyu
    // and Huya and the odd ones (light, dark, greys).
    const colors = [
      LiveMessageColor(255, 255, 0),
      LiveMessageColor(255, 215, 0),
      LiveMessageColor(255, 165, 0),
      LiveMessageColor(255, 102, 0),
      LiveMessageColor(255, 0, 0),
      LiveMessageColor(254, 0, 2),
      LiveMessageColor(255, 105, 180),
      LiveMessageColor(255, 192, 203),
      LiveMessageColor(255, 0, 255),
      LiveMessageColor(204, 0, 255),
      LiveMessageColor(128, 0, 128),
      LiveMessageColor(0, 0, 255),
      LiveMessageColor(0, 0, 128),
      LiveMessageColor(30, 144, 255),
      LiveMessageColor(137, 213, 255),
      LiveMessageColor(0, 255, 255),
      LiveMessageColor(0, 205, 0),
      LiveMessageColor(0, 255, 0),
      LiveMessageColor(127, 255, 0),
      LiveMessageColor(144, 238, 144),
      LiveMessageColor(34, 139, 34),
      LiveMessageColor(1, 1, 1),
      LiveMessageColor(60, 60, 60),
      LiveMessageColor(128, 128, 128),
      LiveMessageColor(200, 200, 200),
      LiveMessageColor(250, 250, 250),
    ];
    final themes = {
      'light': const LiveTheme().light,
      'dark': const LiveTheme().dark,
      'light, brand blue': const LiveTheme(
        primaryColor: LiveTheme.brandBlue,
        schemeVariant: DynamicSchemeVariant.fidelity,
      ).light,
      'dark, brand blue': const LiveTheme(
        primaryColor: LiveTheme.brandBlue,
        schemeVariant: DynamicSchemeVariant.fidelity,
      ).dark,
      'pure black': const LiveTheme(
        primaryColor: LiveTheme.brandBlue,
        schemeVariant: DynamicSchemeVariant.fidelity,
        pureBlack: true,
      ).dark,
      'light, orange': const LiveTheme(primaryColor: Color(0xFFFF9800)).light,
      'dark, orange': const LiveTheme(primaryColor: Color(0xFFFF9800)).dark,
    };

    test('every colour reads at 4.5:1 on the lines and the cards, in both themes', () {
      for (final MapEntry(key: name, value: theme) in themes.entries) {
        final scheme = theme.colorScheme;
        for (final background in [scheme.surface, scheme.surfaceContainerLowest]) {
          for (final color in colors) {
            final ink = chatNameColor(color, background)!;
            expect(
              contrastRatio(ink, background),
              greaterThanOrEqualTo(chatNameContrast),
              reason: '$name: (${color.r}, ${color.g}, ${color.b}) on $background gives $ink',
            );
          }
        }
      }
    });

    test('a colour that already reads stays as sent; the others only change their lightness', () {
      const white = Color(0xFFFFFFFF);
      const black = Color(0xFF000000);
      expect(chatNameColor(const LiveMessageColor(0, 0, 255), white), const Color(0xFF0000FF));
      expect(chatNameColor(const LiveMessageColor(255, 255, 0), black), const Color(0xFFFFFF00));
      // Yellow on white was 1.6:1 with 3.x's fixed lightness.
      final yellow = chatNameColor(const LiveMessageColor(255, 255, 0), white)!;
      expect(contrastRatio(yellow, white), inInclusiveRange(4.5, 5.2), reason: 'darkened only as far as needed');
      expect(HSLColor.fromColor(yellow).hue, closeTo(60, 1));
      // Navy on black is lightened.
      final navy = chatNameColor(const LiveMessageColor(0, 0, 128), black)!;
      expect(contrastRatio(navy, black), greaterThanOrEqualTo(4.5));
      expect(HSLColor.fromColor(navy).hue, closeTo(240, 1));
      expect(HSLColor.fromColor(navy).lightness, greaterThan(0.25));
    });

    test("white and black messages take the theme's colours", () {
      expect(chatNameColor(LiveMessageColor.white, const Color(0xFFFFFFFF)), isNull);
      expect(chatNameColor(const LiveMessageColor(0, 0, 0), const Color(0xFF000000)), isNull);
    });
  });
}
