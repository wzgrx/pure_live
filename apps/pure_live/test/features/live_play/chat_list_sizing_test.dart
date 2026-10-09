// A08.15 (docs/A-界面设计/A08-弹幕界面/A08.15-聊天列表字号和行距): the chat list's text size
// ("列表文字大小", 12..22, 0 = the theme's) and line spacing ("行间距"). The
// defaults draw every kind of line exactly as before (the baseline was
// measured with the code before A08.15); each size and spacing step; with
// the system's 1.3x and 2x text in the 280 column; the three themes; both
// styles; gift, local and super chat lines; the line cache; the rows.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/image_cache.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/features/live_play/danmaku/chat_text.dart';
import 'package:pure_live/features/live_play/danmaku/gift_line.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/local_interaction/local_chat_line.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_interaction.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/danmaku/chat_list_settings.dart';

import '../../support.dart';
import '../settings/settings_harness.dart';
import 'live_play_support.dart';
import 'no_images.dart';

/// The three themes the list is checked in.
final Map<String, ThemeData> _themes = {
  'light': const LiveTheme().light,
  'dark': const LiveTheme().dark,
  'pure black': const LiveTheme(pureBlack: true).dark,
};

/// The theme's chat text size (LiveTheme's bodyLarge).
const double _themeSize = 14;

const _profile = LocalProfile(
  title: '听众',
  name: 'Pure Live',
  accent: 0xFF2E6FE0,
  badge: '📺',
  badgeName: '舰队等级',
  level: 1,
);

const String _longName = '一个非常非常长的观众昵称用来测试换行';

/// One line of every kind (the names are the baseline's).
Map<String, ChatLine> _lines() {
  final start = DateTime(2026, 10, 9, 20);
  return {
    'chat': ChatLine.chat(
      const LiveMessage(
        type: LiveMessageType.chat,
        userName: '观众',
        message: '你好',
        color: LiveMessageColor.white,
        fansName: '小路泥',
        fansLevel: '22',
        sourceRoomId: '1073619',
      ),
    ),
    'avatar': ChatLine.chat(
      const LiveMessage(
        type: LiveMessageType.chat,
        userName: '观众',
        message: '你好',
        color: LiveMessageColor.white,
        data: DanmakuSender(avatar: 'https://example.invalid/face.jpg'),
      ),
    ),
    'long': ChatLine.chat(
      const LiveMessage(
        type: LiveMessageType.chat,
        userName: _longName,
        message: '这是一条很长的弹幕内容，看看在横屏的窄栏里两倍字号时会不会溢出或者被截断',
        color: LiveMessageColor.white,
      ),
    ),
    'gift': ChatLine.gift(
      const LiveMessage(
        type: LiveMessageType.gift,
        userName: '送礼人',
        message: '',
        color: LiveMessageColor.white,
        data: LiveGift(name: '小心心', count: 3, totalValue: 30000, unit: LiveGiftUnit.goldSeed),
      ),
    ),
    'local': ChatLine.chat(
      LiveMessage(
        type: LiveMessageType.chat,
        userName: 'Pure Live',
        message: '本地的话',
        color: LiveMessageColor.white,
        isLocal: true,
        data: _profile.toData(),
      ),
    ),
    'localGift': ChatLine.gift(
      LiveMessage(
        type: LiveMessageType.gift,
        userName: 'Pure Live',
        message: '',
        color: LiveMessageColor.white,
        isLocal: true,
        data: {..._profile.toData(), 'emoji': '🌶', 'giftName': '辣条', 'big': false, 'effect': 'none'},
      ),
    ),
    'superChat': ChatLine.superChat(
      LiveSuperChatMessage(
        userName: '老板',
        face: '',
        message: '加油',
        price: 30,
        startTime: start,
        endTime: start.add(const Duration(minutes: 1)),
        backgroundColor: '#2A60B2',
        backgroundBottomColor: '#427D9E',
      ),
    ),
    'notice': ChatLine.notice(
      const LiveMessage(type: LiveMessageType.chat, userName: '', message: '欢迎来到直播间', color: LiveMessageColor.white),
    ),
    'system': ChatLine.system('已连接弹幕服务器'),
  };
}

/// A plain chat line: one line of words, no marks.
ChatLine _plain() => ChatLine.chat(
  const LiveMessage(type: LiveMessageType.chat, userName: '观众', message: '你好', color: LiveMessageColor.white),
);

Future<void> _pumpLine(
  WidgetTester tester,
  ChatLine line, {
  ChatListStyle style = ChatListStyle.compact,
  ChatSizing? sizing,
  ThemeData? theme,
  double width = 360,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    LiveUiScope(
      config: LiveUiConfig(imageCacheManager: NoImages()),
      child: MaterialApp(
        theme: theme ?? const LiveTheme().light,
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: sizing == null
                  ? ChatLineView(line: line, style: style)
                  : ChatLineView(line: line, style: style, sizing: sizing),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// What the baseline measured of the line: its size and where its pieces
/// are, relative to the line.
Map<String, Object> _measure(WidgetTester tester) {
  final line = tester.getRect(find.byType(ChatLineView));
  Map<String, double>? rect(Finder finder) {
    if (finder.evaluate().isEmpty) return null;
    final at = tester.getRect(finder.first);
    return {'l': at.left - line.left, 't': at.top - line.top, 'w': at.width, 'h': at.height};
  }

  final pieces = <String, Finder>{
    'fans': find.byKey(const ValueKey('live-play-chat-fans')),
    'other': find.byKey(const ValueKey('live-play-chat-other-room')),
    'avatar': find.byKey(const ValueKey('live-play-chat-avatar')),
    'dot': find.byKey(const ValueKey('live-play-chat-dot')),
    'giftIcon': find.byKey(const ValueKey('live-play-gift-icon')),
    'giftValue': find.byKey(const ValueKey('live-play-gift-value')),
    'localTag': find.byKey(const ValueKey('live-play-local-tag')),
    'words': find.byType(EmoteText),
  };
  return {
    'size': [line.width, line.height],
    for (final MapEntry(:key, :value) in pieces.entries) key: ?rect(value),
  };
}

/// [actual] equals [expected] (the baseline's JSON) to a hundredth.
void _expectSame(Object? actual, Object? expected, String reason) {
  switch ((actual, expected)) {
    case (final num a, final num e):
      expect(a, closeTo(e, 0.01), reason: reason);
    case (final List<Object?> a, final List<Object?> e):
      expect(a, hasLength(e.length), reason: reason);
      for (var i = 0; i < a.length; i++) {
        _expectSame(a[i], e[i], '$reason[$i]');
      }
    case (final Map<String, Object?> a, final Map<String, Object?> e):
      expect(a.keys.toSet(), e.keys.toSet(), reason: reason);
      for (final key in e.keys) {
        _expectSame(a[key], e[key], '$reason.$key');
      }
    default:
      expect(actual, expected, reason: reason);
  }
}

/// The span that says [text] in the line, or null.
TextSpan? _span(WidgetTester tester, String text) {
  TextSpan? found;
  for (final widget in tester.widgetList<RichText>(
    find.descendant(of: find.byType(ChatLineView), matching: find.byType(RichText)),
  )) {
    widget.text.visitChildren((span) {
      if (span is TextSpan && span.text == text) found = span;
      return found == null;
    });
    if (found != null) return found;
  }
  return null;
}

double? _wordsSize(WidgetTester tester) => tester.widget<EmoteText>(find.byType(EmoteText)).style?.fontSize;

double? _chipSize(WidgetTester tester, String key) =>
    tester.widget<ChatChip>(find.byKey(ValueKey(key))).style?.fontSize;

/// A chip's or a gift value's size at the list's [size] (c3: in proportion,
/// never under 12).
double _piece(double base, int size) => math.max(12, base * size / _themeSize);

void main() {
  late final Map<String, Object?> baseline;
  setUpAll(() async {
    await loadStrings();
    baseline = jsonDecode(
      File('test/features/live_play/chat_list_sizing_baseline.json').readAsStringSync(),
    ) as Map<String, Object?>;
  });
  BaseCacheManager? images;
  setUp(() {
    images = AppImageCache.manager;
    AppImageCache.manager = NoImages();
  });
  tearDown(() => AppImageCache.manager = images);

  group('c1: the defaults draw the list as before', () {
    test("ChatSizing.standard is the settings' defaults and changes no style", () {
      final theme = const LiveTheme().light;
      final sizing = ChatSizing(
        fontSize: Settings.danmakuListFontSize.defaultValue,
        spacing: ChatSpacing.of(Settings.danmakuListLineSpacing.defaultValue),
      );
      expect(sizing, ChatSizing.standard);
      final body = theme.textTheme.bodyLarge;
      expect(identical(sizing.text(body), body), isTrue);
      expect(identical(sizing.piece(body, theme), body), isTrue);
      expect(sizing.scaleIn(theme), 1);
      for (final base in [3.0, 4.0, 8.0]) {
        expect(sizing.gap(base), base);
      }
      expect(ChatText.content(theme), ChatText.content(theme, sizing: sizing));
      expect(ChatChip.styleOf(theme), ChatChip.styleOf(theme, sizing));
    });

    testWidgets('every kind of line, both styles, 360 and 280 wide, 1x, 1.3x and 2x system text, three themes: '
        'the sizes and places measured before A08.15', (tester) async {
      for (final MapEntry(key: label, value: theme) in _themes.entries) {
        for (final style in ChatListStyle.values) {
          for (final width in [360.0, 280.0]) {
            for (final scale in [1.0, 1.3, 2.0]) {
              for (final MapEntry(:key, :value) in _lines().entries) {
                final name = '${style.name} $width $scale $key';
                await _pumpLine(
                  tester,
                  value,
                  style: style,
                  theme: theme,
                  width: width,
                  textScale: scale,
                  sizing: ChatSizing.standard,
                );
                _expectSame(_measure(tester), baseline[name], '$label: $name');
              }
            }
          }
        }
      }
    });

    testWidgets("14 (the theme's own size) with the standard spacing draws as the default", (tester) async {
      for (final style in ChatListStyle.values) {
        for (final MapEntry(:key, :value) in _lines().entries) {
          await _pumpLine(tester, value, style: style, sizing: const ChatSizing(fontSize: 14));
          _expectSame(_measure(tester), baseline['${style.name} 360.0 1.0 $key'], '${style.name} $key');
        }
      }
    });
  });

  group('c2, c3: each size', () {
    testWidgets('12..22: the name and the words one size in both styles; the marks in proportion, chips never '
        'under 12; the lines grow', (tester) async {
      for (final style in ChatListStyle.values) {
        var last = 0.0;
        for (var size = 12; size <= 22; size++) {
          final sizing = ChatSizing(fontSize: size);
          final reason = '${style.name}, $size';
          await _pumpLine(tester, _lines()['chat']!, style: style, sizing: sizing);
          expect(_span(tester, '观众：')!.style!.fontSize, size, reason: reason);
          expect(_span(tester, '观众：')!.style!.fontWeight, FontWeight.w600, reason: '$reason: A08.10 weight');
          expect(_wordsSize(tester), size, reason: reason);
          expect(_chipSize(tester, 'live-play-chat-fans'), closeTo(_piece(12, size), 0.001), reason: reason);
          expect(_chipSize(tester, 'live-play-chat-other-room'), closeTo(_piece(12, size), 0.001), reason: reason);
          // Text heights come out in whole pixels.
          final medal = tester.getRect(find.byKey(const ValueKey('live-play-chat-fans')));
          expect(medal.height, closeTo(_piece(12, size) * 1.5, 1), reason: '$reason: the medal 18 high at 12');
          final height = tester.getSize(find.byType(ChatLineView)).height;
          expect(height, greaterThanOrEqualTo(last), reason: '$reason: larger text, a taller line');
          last = height;

          // Badges and the avatar (pictures fail in tests: their sizes).
          await _pumpLine(
            tester,
            ChatLine.chat(
              const LiveMessage(
                type: LiveMessageType.chat,
                userName: '观众',
                message: '你好',
                color: LiveMessageColor.white,
                badges: [LiveBadge(url: 'https://example.invalid/badge.png')],
                data: DanmakuSender(avatar: 'https://example.invalid/face.jpg'),
              ),
            ),
            style: style,
            sizing: sizing,
          );
          expect(
            tester.widget<ChatBadge>(find.byType(ChatBadge)).size,
            closeTo(16 * size / _themeSize, 0.001),
            reason: reason,
          );
          if (style == ChatListStyle.card) {
            final avatar = tester.getSize(find.byKey(const ValueKey('live-play-chat-avatar')));
            expect(avatar.height, closeTo(24 * size / _themeSize, 0.01), reason: '$reason: the avatar');
            await _pumpLine(tester, _plain(), style: style, sizing: sizing);
            // The dot's box: its margin above it, then the dot.
            final dot = tester.getSize(find.byKey(const ValueKey('live-play-chat-dot')));
            final side = 8 * size / _themeSize;
            final above = ((size * 1.5 - side) / 2).floorToDouble();
            expect(dot.height, closeTo(above + side, 0.01), reason: '$reason: the dot, on the first line');
            expect(dot.width, closeTo(side + 10, 0.01), reason: '$reason: the dot');
          }
        }
      }
    });

    testWidgets('gift, local and super chat lines follow; the gift picture grows; the system label keeps its size', (
      tester,
    ) async {
      final theme = const LiveTheme().light;
      for (final style in ChatListStyle.values) {
        for (final size in [12, 16, 22]) {
          final sizing = ChatSizing(fontSize: size);
          final reason = '${style.name}, $size';
          await _pumpLine(tester, _lines()['gift']!, style: style, sizing: sizing);
          expect(_span(tester, '送礼人 ')!.style!.fontSize, size, reason: '$reason: the gift sender');
          expect(_span(tester, '小心心')!.style!.fontSize, size, reason: '$reason: the gift name');
          final icon = tester.getSize(find.byKey(const ValueKey('live-play-gift-icon')));
          expect(icon.width, closeTo(16 * size / _themeSize, 0.01), reason: '$reason: the picture');
          final value = tester.widget<Text>(find.byKey(const ValueKey('live-play-gift-value')));
          expect(value.style!.fontSize, closeTo(_piece(13, size), 0.001), reason: '$reason: the value, a size smaller');
          expect(tester.getSize(find.byType(GiftLine)).width, 360, reason: reason);

          await _pumpLine(tester, _lines()['local']!, style: style, sizing: sizing);
          final local = find.byType(LocalChatLine);
          expect(local, findsOneWidget);
          expect(_span(tester, '听众 · Pure Live：')!.style!.fontSize, size, reason: '$reason: the local name');
          expect(_span(tester, '本地的话')!.style!.fontSize, size, reason: '$reason: the local words');
          expect(_chipSize(tester, 'live-play-local-tag'), closeTo(_piece(12, size), 0.001), reason: '$reason: 本地');
          expect(_chipSize(tester, 'live-play-local-badge'), closeTo(_piece(12, size), 0.001), reason: reason);

          await _pumpLine(tester, _lines()['localGift']!, style: style, sizing: sizing);
          expect(_span(tester, '辣条')!.style!.fontSize, size, reason: '$reason: the local gift');

          await _pumpLine(tester, _lines()['superChat']!, style: style, sizing: sizing);
          expect(_span(tester, '老板 · ')!.style!.fontSize, size, reason: '$reason: the super chat name');
          expect(_span(tester, '加油')!.style!.fontSize, size, reason: '$reason: the super chat words');

          await _pumpLine(tester, _lines()['notice']!, style: style, sizing: sizing);
          expect(
            tester.widget<Text>(find.text('欢迎来到直播间')).style!.fontSize,
            size,
            reason: '$reason: a notice is a message',
          );

          await _pumpLine(tester, _lines()['system']!, style: style, sizing: sizing);
          expect(
            tester.widget<Text>(find.text('已连接弹幕服务器')).style!.fontSize,
            theme.textTheme.bodySmall!.fontSize,
            reason: '$reason: the system label keeps its small size',
          );
        }
      }
    });
  });

  group('c1: each spacing', () {
    testWidgets('compact halves the gaps and sets the text 1.4 high; loose 1.5 times and 1.7; standard as before', (
      tester,
    ) async {
      for (final size in [0, 12, 22]) {
        final text = size == 0 ? _themeSize : size.toDouble();
        final heights = <ChatSpacing, double>{};
        for (final spacing in ChatSpacing.values) {
          final sizing = ChatSizing(fontSize: size, spacing: spacing);
          final lineHeight = spacing.textHeight ?? 1.5;
          final reason = '$size, ${spacing.name}';
          await _pumpLine(tester, _plain(), sizing: sizing);
          final compact = tester.getSize(find.byType(ChatLineView)).height;
          // Text heights come out in whole pixels.
          expect(compact, closeTo(2 * spacing.gap(4) + text * lineHeight, 1), reason: '$reason: compact line');
          heights[spacing] = compact;
          expect(_wordsSize(tester), text, reason: reason);

          await _pumpLine(tester, _plain(), style: ChatListStyle.card, sizing: sizing);
          final card = tester.getSize(find.byType(ChatLineView)).height;
          expect(
            card,
            closeTo(2 * spacing.gap(4) + 2 * spacing.gap(8) + text * lineHeight, 1),
            reason: '$reason: card',
          );

          for (final kind in ['gift', 'local', 'superChat', 'notice', 'system']) {
            await _pumpLine(tester, _lines()[kind]!, sizing: sizing);
            expect(tester.takeException(), isNull, reason: '$reason, $kind');
          }
        }
        expect(heights[ChatSpacing.compact], lessThan(heights[ChatSpacing.standard]!), reason: '$size');
        expect(heights[ChatSpacing.standard], lessThan(heights[ChatSpacing.loose]!), reason: '$size');
      }
    });

    testWidgets('a wrapped line: the spacing sets the height between its lines too', (tester) async {
      for (final spacing in ChatSpacing.values) {
        await _pumpLine(tester, _lines()['long']!, sizing: ChatSizing(spacing: spacing), width: 280);
        final words = tester.getRect(find.byType(EmoteText));
        final line = _themeSize * (spacing.textHeight ?? 1.5);
        final count = (words.height / line).round();
        expect(count, greaterThanOrEqualTo(2), reason: '${spacing.name}: wraps');
        expect(words.height, closeTo(count * line, count.toDouble()), reason: '${spacing.name}: $count lines');
      }
    });
  });

  group('c4: with the system text scale, 280 wide', () {
    testWidgets('12, 22 and the default under 1.3x and 2x: every kind, both styles, three themes, nothing overflows, '
        'the words and the marks scaled once', (tester) async {
      for (final MapEntry(key: label, value: theme) in _themes.entries) {
        for (final style in ChatListStyle.values) {
          for (final size in [0, 12, 22]) {
            for (final scale in [1.3, 2.0]) {
              for (final spacing in [ChatSpacing.compact, ChatSpacing.loose]) {
                final sizing = ChatSizing(fontSize: size, spacing: spacing);
                for (final MapEntry(:key, :value) in _lines().entries) {
                  final reason = '$label, ${style.name}, $size, $scale, ${spacing.name}, $key';
                  await _pumpLine(
                    tester,
                    value,
                    style: style,
                    theme: theme,
                    width: 280,
                    textScale: scale,
                    sizing: sizing,
                  );
                  expect(tester.takeException(), isNull, reason: reason);
                  expect(tester.getSize(find.byType(ChatLineView)).width, 280, reason: reason);
                }
                // The words: one line at the list's size times the system's,
                // once (A08.11 G14).
                await _pumpLine(
                  tester,
                  _plain(),
                  style: style,
                  theme: theme,
                  width: 280,
                  textScale: scale,
                  sizing: sizing,
                );
                final text = size == 0 ? _themeSize : size.toDouble();
                final line = text * spacing.textHeight! * scale;
                expect(
                  tester.getRect(find.byType(EmoteText)).height,
                  closeTo(line, line * 0.15),
                  reason: '$label, $size, $scale: the words scaled once',
                );
                await _pumpLine(
                  tester,
                  _lines()['chat']!,
                  style: style,
                  theme: theme,
                  width: 280,
                  textScale: scale,
                  sizing: sizing,
                );
                // "对方" (two glyphs; the medal's words may wrap in the
                // test font, whose every glyph is a square).
                final other = tester.getRect(find.byKey(const ValueKey('live-play-chat-other-room')));
                final chip = (size == 0 ? 12 : _piece(12, size)) * 1.5 * scale;
                expect(other.height, closeTo(chip, 2), reason: '$label, $size, $scale: the chip scaled once');
                await _pumpLine(
                  tester,
                  _lines()['long']!,
                  style: style,
                  theme: theme,
                  width: 280,
                  textScale: scale,
                  sizing: sizing,
                );
                expect(_span(tester, '$_longName：'), isNotNull, reason: '$label, $size, $scale: the whole name');
                expect(
                  tester.getSize(find.byType(ChatLineView)).height,
                  greaterThan(text * scale * 2),
                  reason: '$label, $size, $scale: wraps, not cut',
                );
              }
            }
          }
        }
      }
    });

    testWidgets("D08.1's \"之前发的\" chip scales once, as the other chips", (tester) async {
      final replayed = ChatLine.chat(
        LiveMessage(
          type: LiveMessageType.chat,
          userName: 'Pure Live',
          message: '之前的话',
          color: LiveMessageColor.white,
          isLocal: true,
          data: {..._profile.toData(), 'replayed': true},
        ),
      );
      for (final scale in [1.0, 2.0]) {
        await _pumpLine(tester, replayed, textScale: scale);
        final chip = tester.getRect(find.byKey(const ValueKey('live-play-local-replayed')));
        final tag = tester.getRect(find.byKey(const ValueKey('live-play-local-tag')));
        expect(chip.height, closeTo(18 * scale, 2), reason: '$scale');
        expect(chip.height, closeTo(tag.height, 0.01), reason: '$scale: as 本地');
      }
    });
  });

  group('in the room', () {
    testWidgets('the line cache: a change of size or spacing builds the shown lines again with it; new lines '
        'after it are built once', (tester) async {
      final room = await _pumpRoom(tester);
      await _chatLines(tester, room, 6);
      List<ChatLineView> shown() => tester.widgetList<ChatLineView>(find.byType(ChatLineView)).toList();
      expect(shown(), isNotEmpty);
      expect(shown().every((line) => line.sizing == ChatSizing.standard), isTrue, reason: 'the defaults');

      var builds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is ChatLineView) builds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      await tester.runAsync(() => room.services.store.settings.set(Settings.danmakuListFontSize, 20));
      await _settle(tester);
      expect(shown().every((line) => line.sizing.fontSize == 20), isTrue, reason: 'every shown line has the size');
      expect(builds, greaterThanOrEqualTo(shown().length), reason: 'built again');
      expect(_wordsSizes(tester), everyElement(20));

      await tester.runAsync(() => room.services.store.settings.set(Settings.danmakuListLineSpacing, 'loose'));
      await _settle(tester);
      expect(
        shown().every((line) => line.sizing == const ChatSizing(fontSize: 20, spacing: ChatSpacing.loose)),
        isTrue,
      );

      // Nothing changes: a new line is the only one built.
      builds = 0;
      room.danmaku.chat('新来的', user: '后来者');
      await _settle(tester);
      expect(builds, lessThanOrEqualTo(2), reason: 'the old lines come from the cache');
      expect(_wordsSizes(tester), everyElement(20));

      // Back to the defaults: as before.
      await tester.runAsync(() => room.services.store.settings.set(Settings.danmakuListFontSize, 0));
      await tester.runAsync(() => room.services.store.settings.set(Settings.danmakuListLineSpacing, 'standard'));
      await _settle(tester);
      expect(shown().every((line) => line.sizing == ChatSizing.standard), isTrue);
      expect(_wordsSizes(tester), everyElement(_themeSize));
      await _closeRoom(tester, room);
    });

    for (final (label, size, platform) in [
      ('portrait 393x852', const Size(393, 852), TargetPlatform.android),
      ('phone held sideways 869x400 (the 280 list)', const Size(869, 400), TargetPlatform.android),
      ('wide 1280x800 (the right column)', const Size(1280, 800), TargetPlatform.windows),
    ]) {
      testWidgets('$label: 22, loose, cards and 2x system text: the same list follows, nothing overflows', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final room = await _pumpRoom(
          tester,
          size: size,
          platform: platform,
          settings: {
            Settings.danmakuListFontSize: 22,
            Settings.danmakuListLineSpacing: 'loose',
            Settings.danmakuListStyle: 'card',
          },
        );
        await _chatLines(tester, room, 3);
        if (size.width < 1000 && size.width > size.height) {
          expect(find.byKey(const ValueKey('live-play-landscape-chat')), findsOneWidget);
        }
        expect(find.byKey(const ValueKey('live-play-chat-card')), findsWidgets);
        expect(_wordsSizes(tester), everyElement(22));
        expect(tester.takeException(), isNull);
        await tester.runAsync(() => room.services.store.settings.set(Settings.danmakuListStyle, 'compact'));
        await _settle(tester);
        expect(find.byKey(const ValueKey('live-play-chat-line')), findsWidgets);
        expect(_wordsSizes(tester), everyElement(22));
        expect(tester.takeException(), isNull);
        await _closeRoom(tester, room);
      });
    }
  });

  group('the rows', () {
    testWidgets('"列表文字大小" and "行间距" are under "弹幕列表样式", before "显示用户名"; the slider starts at '
        '"默认", its steps are 12..22; the spacing has three segments', (tester) async {
      final services = (await tester.runAsync(testServices))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appServicesProvider.overrideWithValue(services)],
          child: MaterialApp(
            theme: const LiveTheme().light,
            home: const Scaffold(body: SingleChildScrollView(child: ChatListSettings())),
          ),
        ),
      );
      await tester.pump();
      final slider = find.byKey(const ValueKey('danmaku-slider-listFontSize'));
      final spacing = find.byKey(const ValueKey('danmaku-list-spacing'));
      expectInOrder(tester, [
        find.byKey(const ValueKey('danmaku-list-style')),
        slider,
        spacing,
        find.byKey(const ValueKey('danmaku-switch-names')),
      ]);
      expect(find.text('列表文字大小'), findsOneWidget);
      expect(find.text('行间距'), findsOneWidget);
      expect(find.text('默认'), findsOneWidget);
      final control = tester.widget<Slider>(slider);
      expect((control.min, control.max, control.divisions, control.value), (11.0, 22.0, 11, 11.0));
      for (final text in ['紧密', '标准', '宽松']) {
        expect(
          find.descendant(of: spacing, matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
      expect(tester.widget<SegmentedButton<ChatSpacing>>(spacing).selected, {ChatSpacing.standard});

      control.onChanged!(16);
      await _settle(tester);
      expect(services.store.settings.get(Settings.danmakuListFontSize), 16);
      expect(find.text('16 px'), findsOneWidget);
      tester.widget<Slider>(slider).onChanged!(11.2);
      await _settle(tester);
      expect(services.store.settings.get(Settings.danmakuListFontSize), 0, reason: 'the left end is the default');
      expect(find.text('默认'), findsOneWidget);

      await tester.tap(find.descendant(of: spacing, matching: find.text('紧密')));
      await tester.pump();
      expect(services.store.settings.get(Settings.danmakuListLineSpacing), 'compact');
      await tester.tap(find.descendant(of: spacing, matching: find.text('宽松')));
      await tester.pump();
      expect(services.store.settings.get(Settings.danmakuListLineSpacing), 'loose');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(services.close);
    });

    test('the value text and the slider stops', () {
      expect(chatListFontSizeText(0), '默认');
      expect(chatListFontSizeText(chatListFontSizeDefaultStop), '默认');
      expect(chatListFontSizeText(12), '12 px');
      expect(chatListFontSizeOf(11), 0);
      expect(chatListFontSizeOf(11.4), 0);
      expect(chatListFontSizeOf(12), 12);
      expect(chatListFontSizeOf(21.6), 22);
      expect(ChatSpacing.of('loose'), ChatSpacing.loose);
      expect(ChatSpacing.of('nonsense'), ChatSpacing.standard);
    });
  });
}

/// The size of every line's words.
List<double?> _wordsSizes(WidgetTester tester) => [
  for (final text in tester.widgetList<EmoteText>(
    find.descendant(of: find.byType(ChatLineView), matching: find.byType(EmoteText)),
  ))
    text.style?.fontSize,
];

final class _Room {
  new(this.services, this.danmaku);

  final AppServices services;
  final FakeDanmaku danmaku;
}

Future<_Room> _pumpRoom(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  TargetPlatform platform = TargetPlatform.android,
  Map<Setting<Object>, Object> settings = const {},
}) async {
  // Reset by [_closeRoom].
  debugDefaultTargetPlatformOverride = platform;
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(testServices))!;
  for (final MapEntry(:key, :value) in settings.entries) {
    await tester.runAsync(() => services.store.settings.set(key, value));
  }
  // Signed in: no guest hint over the list.
  await tester.runAsync(() => services.store.secrets.setCookie(SiteIds.bilibili, 'SESSDATA=a; DedeUserID=1'));
  final danmaku = FakeDanmaku();
  final previous = AppNavigator.toast;
  AppNavigator.toast = (_) {};
  addTearDown(() => AppNavigator.toast = previous);
  final site = FakeSite(liveRoom());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({SiteIds.bilibili: () => site})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: () => danmaku})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(FakeEngine())),
      ],
      child: MaterialApp(
        theme: const LiveTheme().light,
        home: LivePlayPage(
          route: RouteArgs(
            RoutePath.kLivePlay,
            arguments: LiveRoom(platform: SiteIds.bilibili, roomId: '6', nick: '主播'),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return _Room(services, danmaku);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

Future<void> _closeRoom(WidgetTester tester, _Room room) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(room.services.close);
  debugDefaultTargetPlatformOverride = null;
}

/// [count] chat lines, then the frames the feed batches them in.
Future<void> _chatLines(WidgetTester tester, _Room room, int count) async {
  room.danmaku.emit(const DanmakuReady());
  for (var i = 1; i <= count; i++) {
    room.danmaku.chat('第$i条', user: '观众$i');
  }
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}
