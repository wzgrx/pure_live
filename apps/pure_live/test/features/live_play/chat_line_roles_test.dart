// A08.10 (docs/A-界面设计/A08-弹幕界面/A08.10-弹幕列表名字和内容分开): the sender's name and
// what was said in two roles on every line and both list styles (G1, G2),
// the platform's colours through the 4.5:1 rule (G3), one order of marks
// before the name (G5), the "显示用户名" switch (G6), on the phone held
// sideways and with large text.

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

/// The three themes the list is checked in.
final Map<String, ThemeData> _themes = {
  'light': const LiveTheme().light,
  'dark': const LiveTheme().dark,
  'pure black': const LiveTheme(pureBlack: true).dark,
};

const _red = LiveMessageColor(0xe5, 0x39, 0x35);
const _yellow = LiveMessageColor(0xff, 0xee, 0x58);

LiveMessage _chat({
  String user = '观众',
  String text = '你好',
  LiveMessageColor color = LiveMessageColor.white,
  LiveMessageColor? nameColor,
  String fans = '',
  String level = '',
  String room = '',
  List<LiveBadge> badges = const [],
  String avatar = '',
}) => LiveMessage(
  type: LiveMessageType.chat,
  userName: user,
  message: text,
  color: color,
  nameColor: nameColor,
  fansName: fans,
  fansLevel: level,
  sourceRoomId: room,
  badges: badges,
  data: avatar.isEmpty ? null : DanmakuSender(avatar: avatar),
);

/// A message with every mark: "对方", a badge, a fan medal and an avatar.
LiveMessage _marked({String user = '观众'}) => _chat(
  user: user,
  fans: '小路泥',
  level: '22',
  room: '1073619',
  badges: const [LiveBadge(url: 'https://example.invalid/badge.png')],
  avatar: 'https://example.invalid/face.jpg',
);

const _profile = LocalProfile(
  title: '听众',
  name: 'Pure Live',
  accent: 0xFF2E6FE0,
  badge: '📺',
  badgeName: '舰队等级',
  level: 1,
);

LiveMessage _local({bool gift = false}) => LiveMessage(
  type: gift ? LiveMessageType.gift : LiveMessageType.chat,
  userName: 'Pure Live',
  message: gift ? '' : '本地的话',
  color: LiveMessageColor.white,
  isLocal: true,
  data: {
    ..._profile.toData(),
    if (gift) ...{'emoji': '🌶', 'giftName': '辣条', 'big': false, 'effect': 'none'},
  },
);

/// An image cache without pictures: badges and avatars fail at once (tests
/// make no requests).
final class _NoImages implements BaseCacheManager {
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => Stream.error(HttpExceptionWithStatus(404, 'no pictures in tests', uri: Uri.parse(url)));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpLine(
  WidgetTester tester,
  ChatLine line, {
  ChatListStyle style = ChatListStyle.compact,
  bool showName = true,
  ThemeData? theme,
  double width = 360,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    LiveUiScope(
      config: LiveUiConfig(imageCacheManager: _NoImages()),
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
              child: ChatLineView(line: line, style: style, showName: showName),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The line's top spans: those of the rich text that holds the words
/// (`Text.rich` puts the line's span under one with the default style).
List<InlineSpan> _spans(WidgetTester tester) {
  for (final text in tester.widgetList<RichText>(
    find.descendant(of: find.byType(ChatLineView), matching: find.byType(RichText)),
  )) {
    var spans = (text.text as TextSpan).children ?? const <InlineSpan>[];
    if (spans case [TextSpan(text: null, :final children?)]) spans = children;
    if (spans.any((span) => span is WidgetSpan && _inline(span) is EmoteText)) return spans;
  }
  return const [];
}

/// What a [WidgetSpan] of a line shows ([chatInline] wraps it to scale once).
Widget _inline(WidgetSpan span) => switch (span.child) {
  ChatInline(:final child) => child,
  final child => child,
};

/// The span that says [text], or null.
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

TextStyle _words(WidgetTester tester) => tester.widget<EmoteText>(find.byType(EmoteText)).style!;

/// What each top span is: 'other', 'fans' (chips by key), 'badge', a
/// span's text, 'words'.
List<String> _shape(WidgetTester tester) => [
  for (final span in _spans(tester))
    switch (span) {
      final WidgetSpan span when _inline(span).key == const ValueKey('live-play-chat-other-room') => 'other',
      final WidgetSpan span when _inline(span).key == const ValueKey('live-play-chat-fans') => 'fans',
      final WidgetSpan span when _inline(span) is ChatBadge => 'badge',
      final WidgetSpan span when _inline(span) is EmoteText => 'words',
      TextSpan(:final text) => text ?? '',
      _ => '?',
    },
];

Color _ground(ThemeData theme, ChatListStyle style) =>
    style == ChatListStyle.card ? theme.colorScheme.surfaceContainerLowest : theme.colorScheme.surface;

void main() {
  late BaseCacheManager? images;
  setUpAll(loadStrings);
  setUp(() {
    images = AppImageCache.manager;
    AppImageCache.manager = _NoImages();
  });
  tearDown(() => AppImageCache.manager = images);

  group('G1, G2: the name and the words', () {
    testWidgets('both styles, every theme: the name semibold in the secondary ink, the words regular in the main ink, '
        'one size', (tester) async {
      for (final MapEntry(key: label, value: theme) in _themes.entries) {
        for (final style in ChatListStyle.values) {
          await _pumpLine(tester, ChatLine.chat(_chat()), style: style, theme: theme);
          final name = _span(tester, '观众：')!.style!;
          final words = _words(tester);
          final reason = '$label, $style';
          expect(name.fontWeight, FontWeight.w600, reason: reason);
          expect(name.color, theme.colorScheme.onSurfaceVariant, reason: reason);
          expect(
            contrastRatio(name.color!, _ground(theme, style)),
            greaterThanOrEqualTo(chatNameContrast),
            reason: '$reason: the secondary ink reads at 4.5:1',
          );
          expect(words.fontWeight, FontWeight.w400, reason: reason);
          expect(words.color, theme.colorScheme.onSurface, reason: reason);
          expect(name.fontSize, words.fontSize, reason: '$reason: the same size, one baseline');
          expect(name.fontSize, theme.textTheme.bodyLarge!.fontSize, reason: '$reason: the font size setting');
        }
      }
    });

    testWidgets("G3: a coloured message and a platform's name colour keep 4.5:1 in every theme and style", (
      tester,
    ) async {
      for (final MapEntry(key: label, value: theme) in _themes.entries) {
        for (final style in ChatListStyle.values) {
          for (final message in [_chat(color: _red), _chat(color: _yellow), _chat(color: _red, nameColor: _yellow)]) {
            await _pumpLine(tester, ChatLine.chat(message), style: style, theme: theme);
            final name = _span(tester, '观众：')!.style!;
            final ground = _ground(theme, style);
            final reason = '$label, $style, ${message.nameColor ?? message.color}';
            expect(name.color, chatNameColor(message.nameColor ?? message.color, ground), reason: reason);
            expect(contrastRatio(name.color!, ground), greaterThanOrEqualTo(chatNameContrast), reason: reason);
            expect(name.fontWeight, FontWeight.w600, reason: reason);
            expect(_words(tester).color, theme.colorScheme.onSurface, reason: '$reason: the words keep the main ink');
          }
        }
      }
    });

    testWidgets('G5: 对方, the badges, the fan medal, the name, the words, in that order on both styles', (tester) async {
      for (final style in ChatListStyle.values) {
        await _pumpLine(tester, ChatLine.chat(_marked()), style: style);
        expect(_shape(tester), ['other', 'badge', 'fans', '观众：', 'words'], reason: '$style');
        final medal = find.byKey(const ValueKey('live-play-chat-fans'));
        expect(find.descendant(of: medal, matching: find.text('小路泥 22')), findsOneWidget);
        // The medal is the same block as "对方".
        final chip = tester.widget<ChatChip>(medal);
        expect(chip.style?.fontSize, 12);
        expect(chip.style?.fontWeight, FontWeight.w600);
      }
    });

    testWidgets('the long-press card names the sender in the same roles', (tester) async {
      // The card is built by the panel; its rule is the list's: the
      // platform's name colour first (it took only the message's colour).
      final theme = const LiveTheme().light;
      final message = _chat(color: _red, nameColor: _yellow);
      final ground = theme.colorScheme.surfaceContainerLowest;
      expect(chatNameInk(message, ground, theme.colorScheme), chatNameColor(_yellow, ground));
      expect(chatNameInk(_chat(), ground, theme.colorScheme), theme.colorScheme.onSurfaceVariant);
    });
  });

  group('G6: "显示用户名" off', () {
    testWidgets('compact and card show only the words; 对方 stays; the card has its dot, not the avatar', (tester) async {
      for (final style in ChatListStyle.values) {
        await _pumpLine(tester, ChatLine.chat(_marked()), style: style, showName: false);
        expect(_shape(tester), ['other', 'words'], reason: '$style');
        expect(find.textContaining('观众', findRichText: true), findsNothing, reason: '$style');
        expect(find.byType(ChatBadge), findsNothing);
        expect(find.byKey(const ValueKey('live-play-chat-fans')), findsNothing);
        expect(find.byKey(const ValueKey('live-play-chat-avatar')), findsNothing);
        expect(find.text('你好', findRichText: true), findsOneWidget);
      }
      // On: the card shows the avatar again.
      await _pumpLine(tester, ChatLine.chat(_marked()), style: ChatListStyle.card);
      expect(find.byKey(const ValueKey('live-play-chat-avatar')), findsOneWidget);
    });

    testWidgets('gift, super chat and local lines leave the name out; 本地 stays', (tester) async {
      const gift = LiveMessage(
        type: LiveMessageType.gift,
        userName: '送礼人',
        message: '送出 辣条 ×1',
        color: LiveMessageColor.white,
      );
      await _pumpLine(tester, ChatLine.gift(gift));
      expect(_span(tester, '送礼人 ')!.style!.fontWeight, FontWeight.w600, reason: 'on: the name role');
      await _pumpLine(tester, ChatLine.gift(gift), showName: false);
      expect(find.textContaining('送礼人', findRichText: true), findsNothing);
      expect(find.textContaining('送出 辣条 ×1', findRichText: true), findsOneWidget);

      final start = DateTime(2026, 10, 9, 20);
      final superChat = LiveSuperChatMessage(
        userName: '老板',
        face: '',
        message: '加油',
        price: 30,
        startTime: start,
        endTime: start.add(const Duration(minutes: 1)),
        backgroundColor: '#2A60B2',
        backgroundBottomColor: '#427D9E',
      );
      await _pumpLine(tester, ChatLine.superChat(superChat));
      expect(find.textContaining('老板 · ￥30：加油', findRichText: true), findsOneWidget);
      await _pumpLine(tester, ChatLine.superChat(superChat), showName: false);
      expect(find.textContaining('老板', findRichText: true), findsNothing);
      expect(find.textContaining('￥30：加油', findRichText: true), findsOneWidget);

      final theme = const LiveTheme().light;
      await _pumpLine(tester, ChatLine.chat(_local()));
      final name = _localSpan(tester, '听众 · Pure Live：')!.style!;
      expect(name.fontWeight, FontWeight.w600, reason: 'the name role');
      expect(name.color, theme.colorScheme.onSurfaceVariant);
      expect(_localSpan(tester, '本地的话')!.style!.color, theme.colorScheme.onSurface);
      expect(find.byKey(const ValueKey('live-play-local-badge')), findsOneWidget);

      await _pumpLine(tester, ChatLine.chat(_local()), showName: false);
      expect(find.byKey(const ValueKey('live-play-local-tag')), findsOneWidget, reason: '本地 stays');
      expect(find.byKey(const ValueKey('live-play-local-badge')), findsNothing);
      expect(_localSpan(tester, '听众 · Pure Live：'), isNull);
      expect(_localSpan(tester, '本地的话'), isNotNull);

      await _pumpLine(tester, ChatLine.gift(_local(gift: true)), showName: false);
      expect(find.byKey(const ValueKey('live-play-local-tag')), findsOneWidget);
      expect(_localSpan(tester, '听众 · Pure Live：'), isNull);
      expect(_localSpan(tester, '辣条'), isNotNull);
    });
  });

  group('large text', () {
    testWidgets('2x in a 280 column (the phone held sideways): every mark, a long name, both styles, no overflow', (
      tester,
    ) async {
      const long = '一个非常非常长的观众昵称用来测试换行';
      final message = _chat(
        user: long,
        text: '这是一条很长的弹幕内容，看看在横屏的窄栏里两倍字号时会不会溢出或者被截断',
        fans: '小路泥',
        level: '22',
        room: '1073619',
      );
      for (final MapEntry(key: label, value: theme) in _themes.entries) {
        for (final style in ChatListStyle.values) {
          for (final scale in [1.3, 2.0]) {
            await _pumpLine(tester, ChatLine.chat(message), style: style, theme: theme, width: 280, textScale: scale);
            final reason = '$label, $style, $scale';
            expect(tester.takeException(), isNull, reason: reason);
            final line = tester.getSize(find.byType(ChatLineView));
            expect(line.width, 280, reason: reason);
            final oneLine = theme.textTheme.bodyLarge!.fontSize! * scale;
            expect(line.height, greaterThan(oneLine * 2), reason: '$reason: wraps, not cut');
            expect(_span(tester, '$long：'), isNotNull, reason: '$reason: the whole name');
          }
        }
      }
      await _pumpLine(tester, ChatLine.chat(_local()), width: 280, textScale: 2);
      expect(tester.takeException(), isNull, reason: 'the local line');
    });

    testWidgets('A08.11: the words and the marks scale once with the system text, as the name does', (tester) async {
      // A text inside a WidgetSpan was scaled by the span and again by its
      // own MediaQuery: at 2x the words were 4x the name's base size.
      for (final scale in [1.0, 1.3, 2.0]) {
        await _pumpLine(tester, ChatLine.chat(_marked()), textScale: scale);
        final body = const LiveTheme().light.textTheme.bodyLarge!;
        final line = body.fontSize! * (body.height ?? 1.5) * scale;
        final words = tester.getRect(find.byType(EmoteText));
        expect(words.height, closeTo(line, line * 0.15), reason: '$scale: the words, one line');
        final chip = tester.getRect(find.byKey(const ValueKey('live-play-chat-fans')));
        expect(chip.height, closeTo(18 * scale, 2), reason: '$scale: the fan medal (18 high at 1x)');
      }
      for (final scale in [1.0, 2.0]) {
        await _pumpLine(tester, ChatLine.chat(_local()), textScale: scale);
        final tag = tester.getRect(find.byKey(const ValueKey('live-play-local-tag')));
        expect(tag.height, closeTo(18 * scale, 2), reason: '$scale: 本地');
      }
    });
  });

  group('in the room', () {
    testWidgets(
      'portrait: the setting hides the names of the open list at once; the long press still names the sender',
      (tester) async {
        final room = await _pumpRoom(tester);
        await _chatLines(tester, room);
        expect(find.textContaining('观众3：', findRichText: true), findsOneWidget);
        await tester.runAsync(() => room.services.store.settings.set(Settings.showChatNames, false));
        await _settle(tester);
        expect(find.textContaining('观众3：', findRichText: true), findsNothing);
        expect(find.textContaining('第3条', findRichText: true), findsOneWidget);
        // A new line comes in without its name too.
        room.danmaku.chat('新来的', user: '后来者');
        await _settle(tester);
        expect(find.textContaining('后来者', findRichText: true), findsNothing);
        expect(find.textContaining('新来的', findRichText: true), findsOneWidget);

        await tester.longPress(find.byKey(const ValueKey('live-play-chat-line')).first);
        await _settle(tester);
        final card = find.byKey(const ValueKey('live-play-message-card'));
        expect(card, findsOneWidget);
        expect(find.descendant(of: card, matching: find.textContaining('后来者：', findRichText: true)), findsOneWidget);
        await _closeRoom(tester, room);
      },
    );

    for (final (label, size) in [
      ('phone held sideways 869x400', const Size(869, 400)),
      ('wide 1280x800', const Size(1280, 800)),
    ]) {
      testWidgets('$label: the same list follows the switch', (tester) async {
        final room = await _pumpRoom(
          tester,
          size: size,
          platform: size.width > 1000 ? TargetPlatform.windows : TargetPlatform.android,
          settings: {Settings.showChatNames: false, Settings.danmakuListStyle: 'card'},
        );
        await _chatLines(tester, room);
        if (size.width < 1000) expect(find.byKey(const ValueKey('live-play-landscape-chat')), findsOneWidget);
        expect(find.byKey(const ValueKey('live-play-chat-card')), findsWidgets);
        expect(find.textContaining('观众3', findRichText: true), findsNothing);
        expect(find.textContaining('第3条', findRichText: true), findsOneWidget);
        await tester.runAsync(() => room.services.store.settings.set(Settings.showChatNames, true));
        await _settle(tester);
        expect(find.textContaining('观众3：', findRichText: true), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _closeRoom(tester, room);
      });
    }
  });

  group('the setting', () {
    testWidgets('"显示用户名" is in "弹幕列表", after the style and before the gifts; it switches the setting', (tester) async {
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
      final names = find.byKey(const ValueKey('danmaku-switch-names'));
      expect(names, findsOneWidget);
      expect(find.text('显示用户名'), findsOneWidget);
      expectInOrder(tester, [
        find.byKey(const ValueKey('danmaku-list-style')),
        names,
        find.byKey(const ValueKey('danmaku-switch-gifts')),
      ]);
      expect(tester.widget<Switch>(names).value, isTrue, reason: 'on by default');
      await tester.tap(names);
      await tester.pump();
      expect(services.store.settings.get(Settings.showChatNames), isFalse);
      expect(tester.widget<Switch>(names).value, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(services.close);
    });
  });
}

/// The span that says [text] in the local line, or null.
TextSpan? _localSpan(WidgetTester tester, String text) {
  TextSpan? found;
  for (final widget in tester.widgetList<RichText>(
    find.descendant(of: find.byType(LocalChatLine), matching: find.byType(RichText)),
  )) {
    widget.text.visitChildren((span) {
      if (span is TextSpan && span.text == text) found = span;
      return found == null;
    });
    if (found != null) return found;
  }
  return null;
}

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

/// Three chat lines, then the frames the feed batches them in.
Future<void> _chatLines(WidgetTester tester, _Room room) async {
  room.danmaku.emit(const DanmakuReady());
  for (var i = 1; i <= 3; i++) {
    room.danmaku.chat('第$i条', user: '观众$i');
  }
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}
