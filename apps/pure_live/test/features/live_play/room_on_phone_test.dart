// A07.17: the live room checked on the phone (docs/A-界面设计/A07-直播间界面/A07.17-直播间真机对照修正):
// the strip in one line (c1), the phone held sideways (c2), the portrait
// stream's panel (c3, c5), the narrow composers' hint (c4) and the details'
// figures, link and follow button (c6).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/layout/room_info_bar.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/logic/room_layout.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/player/player_view.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

import '../../support.dart';
import 'live_play_support.dart';

final class _Room {
  new(this.services, this.engine, this.danmaku, this.copied);

  final AppServices services;
  final FakeEngine engine;
  final FakeDanmaku danmaku;

  /// What the page put on the clipboard.
  final List<String> copied;
}

/// A Bilibili room with three figures (在线, 热度, 看过) and 6 h 45 min on
/// the air, as on the phone (V03.4-06).
LiveRoom _busyRoom() => LiveRoom(
  platform: SiteIds.bilibili,
  roomId: '6',
  nick: '主播',
  title: '永不停歇对未知疆土的检视肃清',
  area: '主机游戏',
  liveStatus: LiveStatus.live,
  onlineViewers: '10000',
  popularity: '1620000',
  totalViewers: '78000',
  startedAt: DateTime.now().subtract(const Duration(hours: 6, minutes: 45, seconds: 10)),
  link: 'https://live.bilibili.com/6',
  danmakuData: 'args-6',
);

Future<_Room> _pump(
  WidgetTester tester, {
  double width = 393,
  double height = 852,
  TargetPlatform platform = TargetPlatform.android,
  bool portrait = false,
  bool signedIn = true,
  Map<Setting<Object>, Object> settings = const {},
  LiveRoom? room,
}) async {
  // Reset by [_close]: the test must end with it unset.
  debugDefaultTargetPlatformOverride = platform;
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  RoomOrientationChoice.clearSession();
  final services = (await tester.runAsync(testServices))!;
  await tester.runAsync(loadStrings);
  for (final MapEntry(:key, :value) in settings.entries) {
    await tester.runAsync(() => services.store.settings.set(key, value));
  }
  // Signed in, Bilibili shows no guest hint over the list (B06 c1): the
  // list alone, as in a Douyin room.
  if (signedIn) {
    await tester.runAsync(() => services.store.secrets.setCookie(SiteIds.bilibili, 'SESSDATA=a; DedeUserID=1'));
  }
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  final engine = FakeEngine();
  final danmaku = FakeDanmaku();
  final previous = AppNavigator.toast;
  AppNavigator.toast = (_) {};
  addTearDown(() => AppNavigator.toast = previous);
  final site = FakeSite(room ?? _busyRoom());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({SiteIds.bilibili: () => site})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: () => danmaku})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(engine)),
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
  if (portrait) {
    engine.emit(const EngineVideoSize(720, 1280));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
  return _Room(services, engine, danmaku, copied);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

Future<void> _close(WidgetTester tester, _Room room) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(room.services.close);
  debugDefaultTargetPlatformOverride = null;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _in(String key, Finder finder) => find.descendant(of: _key(key), matching: finder);

/// Twelve chat messages, then the frames the feed batches them in.
Future<void> _chat(WidgetTester tester, _Room room) async {
  room.danmaku.emit(const DanmakuReady());
  for (var i = 1; i <= 12; i++) {
    room.danmaku.chat('第$i条', user: '观众$i');
  }
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// The chat lines wholly inside the chat list.
int _visibleLines(WidgetTester tester) {
  final list = tester.getRect(_key('live-play-chat'));
  final lines = _key('live-play-chat-line');
  var count = 0;
  for (var i = 0; i < lines.evaluate().length; i++) {
    final rect = tester.getRect(lines.at(i));
    if (rect.top >= list.top - 0.5 && rect.bottom <= list.bottom + 0.5) count++;
  }
  return count;
}

/// The strip's figures sit in one line, as high as one, centred on the
/// quality button.
void _expectOneLine(WidgetTester tester, String reason) {
  final audience = tester.getRect(_key('live-play-audience'));
  expect(
    find.descendant(of: _key('live-play-audience'), matching: find.byType(Wrap)),
    findsNothing,
    reason: reason,
  );
  expect(audience.height, lessThanOrEqualTo(24), reason: reason);
  expect(tester.getRect(_key('live-play-audience-row')).height, roomFiguresRowHeight, reason: reason);
  final quality = tester.getRect(_key('live-play-quality'));
  expect((audience.center.dy - quality.center.dy).abs(), lessThan(1), reason: reason);
}

void main() {
  group('c1 the strip', () {
    testWidgets('one line at 393 and in a 300 column; fixed height, centred on the pickers', (tester) async {
      final phone = await _pump(tester);
      expect(_key('live-play-portrait-stack'), findsOneWidget);
      _expectOneLine(tester, '393');
      // Too narrow for all four: "看过" goes first, the online count stays.
      expect(_in('live-play-audience', find.byIcon(AppIcons.audienceTotal)), findsNothing);
      expect(_in('live-play-audience', find.byIcon(AppIcons.audienceOnline)), findsOneWidget);
      await _close(tester, phone);

      final wide = await _pump(tester, width: 882, height: 800, platform: TargetPlatform.windows);
      expect(tester.getSize(_key('live-play-chat-box')).width, 300);
      _expectOneLine(tester, '300 column');
      await _close(tester, wide);
    });

    testWidgets('a long time on air beside two short figures is not cut short', (tester) async {
      // K90 2026-10-08 (Bilibili, 68.6万 热度, 577 看过, 2 h 5 min): the
      // parts flexed equally, so the time on air read "2 小..." although
      // the whole line fitted.
      final room = LiveRoom(
        platform: SiteIds.bilibili,
        roomId: '7',
        nick: '主播',
        title: '乱斗',
        area: '英雄联盟',
        liveStatus: LiveStatus.live,
        popularity: '686000',
        totalViewers: '577',
        startedAt: DateTime.now().subtract(const Duration(hours: 2, minutes: 5, seconds: 10)),
        link: 'https://live.bilibili.com/7',
        danmakuData: 'args-7',
      );
      // 480 wide: the long words fit the line, but not an equal third of it.
      final phone = await _pump(tester, room: room, width: 480);
      final clock = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.descendant(of: _key('live-play-on-air'), matching: find.byType(Text)),
          matching: find.byType(RichText),
        ),
      );
      expect(clock.didExceedMaxLines, isFalse, reason: 'the time on air is never cut short when the line fits');
      await _close(tester, phone);
    });

    test('fitAudience drops 看过, shortens the time, shrinks the text, then drops from the end', () {
      const types = [AudienceMetricType.onlineViewers, AudienceMetricType.popularity, AudienceMetricType.totalViewers];
      // Each figure 60 (40 small), the time 100 long or 50 short (80, 40
      // small), 10 between. Read as (shown, short time, small text).
      (String, bool, bool) fit(double width, {List<AudienceMetricType> kinds = types, bool clock = true}) {
        final fit = fitAudience(
          types: kinds,
          figure: (index, {required small}) => small ? 40 : 60,
          clock: clock ? ({required short, required small}) => short ? (small ? 40 : 50) : (small ? 80 : 100) : null,
          spacing: 10,
          width: width,
        );
        return (fit.shown.join(','), fit.shortClock, fit.small);
      }

      expect(fit(310), ('0,1,2', false, false));
      expect(fit(240), ('0,1', false, false));
      expect(fit(190), ('0,1', true, false));
      expect(fit(140), ('0,1', true, true));
      expect(fit(90), ('0', true, true));
      expect(fit(10), ('0', true, true), reason: 'the last resort cuts the text');
      // Two figures: none dropped before the time and the text shrink.
      const two = [AudienceMetricType.onlineViewers, AudienceMetricType.popularity];
      expect(fit(190, kinds: two), ('0,1', true, false));
      expect(fit(130, kinds: two, clock: false), ('0,1', false, false));
    });

    test('the short time on air: H:MM, then days and hours', () {
      expect(shortElapsedText(const Duration(hours: 6, minutes: 45, seconds: 30)), '6:45');
      expect(shortElapsedText(const Duration(hours: 12, minutes: 13)), '12:13');
      expect(shortElapsedText(const Duration(minutes: 7)), '0:07');
      expect(shortElapsedText(const Duration(seconds: 20)), '0:01');
      expect(shortElapsedText(const Duration(days: 1, hours: 2, minutes: 5)), '1 天 2 时');
    });
  });

  group('c2 a phone held sideways', () {
    testWidgets('869 x 400: the picture at full height, a 280 chat list; the title opens the details', (tester) async {
      // A guest, as on the phone: the login hint over the list too.
      final room = await _pump(tester, width: 869, height: 400, signedIn: false);
      expect(_key('live-play-phone-landscape'), findsOneWidget);
      expect(_key('live-play-desktop-split'), findsNothing);
      expect(find.byType(AppBar), findsOneWidget, reason: 'back, follow, record and the menu stay');
      expect(tester.getSize(_key('live-play-landscape-chat')).width, phoneLandscapeChatWidth);
      final player = tester.getRect(find.byType(RoomPlayer));
      expect(player.height, 400 - 56, reason: 'the full height under the app bar');
      expect(player.left, 0);
      expect(player.right, closeTo(869 - phoneLandscapeChatWidth, 1));
      // Only the list: no strip, tabs or composer bar in the column.
      expect(_key('live-play-info'), findsNothing);
      expect(_key('live-play-tabs'), findsNothing);
      expect(_key('local-composer-bar'), findsNothing);
      await _chat(tester, room);
      expect(_key('live-play-name-hint'), findsOneWidget);
      expect(_visibleLines(tester), greaterThanOrEqualTo(5));
      // The strip folded into the picture's title: the figures under it, the
      // quality and line in the bottom bar.
      expect(_in('live-play-video-title-details', find.text('永不停歇对未知疆土的检视肃清')), findsOneWidget);
      expect(_in('live-play-video-title-details', _key('live-play-audience')), findsOneWidget);
      expect(_in('live-play-bottom-bar', _key('live-play-quality')), findsOneWidget);
      expect(_in('live-play-bottom-bar', _key('live-play-line')), findsOneWidget);
      await _tap(tester, _key('live-play-video-title-details'));
      expect(_key('live-play-details'), findsOneWidget);
      expect(tester.getRect(_key('live-play-details')).left, closeTo(869 - phoneLandscapeChatWidth, 1));
      // Back closes the details first.
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(_key('live-play-details'), findsNothing);
      expect(_key('live-play-phone-landscape'), findsOneWidget);
      await _close(tester, room);
    });

    testWidgets('a desktop window as short keeps the split (840 and wider unchanged)', (tester) async {
      final room = await _pump(tester, width: 869, height: 400, platform: TargetPlatform.windows);
      expect(_key('live-play-desktop-split'), findsOneWidget);
      expect(_key('live-play-phone-landscape'), findsNothing);
      await _close(tester, room);
    });
  });

  group('c3 c5 a portrait stream', () {
    testWidgets('the middle stop shows 5 lines; the composer is a star; the picture at the top; a deep shade', (
      tester,
    ) async {
      final room = await _pump(tester, portrait: true);
      final sheet = tester.getRect(_key('live-play-portrait-sheet'));
      expect(sheet.height, closeTo(796 * 0.44, 0.5), reason: '"均衡" starts at the middle');
      expect(_key('local-composer-bar'), findsNothing);
      // 40 to see (12 from the corner), 48 to tap (A05.1).
      final target = tester.getRect(_key('local-composer-chat-star'));
      expect(target.size, const Size.square(48));
      final star = target.deflate(4);
      final chat = tester.getRect(_key('live-play-chat-body'));
      expect(star.right, closeTo(chat.right - 12, 1));
      expect(star.bottom, closeTo(chat.bottom - 12, 1));
      // A08.13: it opens the composer, so it is not the style's star.
      expect(_in('local-composer-chat-star', find.byIcon(AppIcons.localCompose)), findsOneWidget);
      expect(find.byIcon(AppIcons.localStyle), findsNothing);
      await _chat(tester, room);
      expect(_visibleLines(tester), greaterThanOrEqualTo(5));
      // No black above the picture: it sits at the top of its area.
      expect(tester.widget<LiveVideoView>(find.byType(LiveVideoView)).alignment, Alignment.topCenter);
      // c5: the bar's shade sits on the panel and reaches well up the picture.
      final shade = tester.getRect(_key('live-play-bottom-shade'));
      expect(shade.bottom, closeTo(sheet.top, 1));
      expect(shade.height, greaterThanOrEqualTo(100));

      // The star opens the composer's row; a message sent closes it.
      await _tap(tester, _key('local-composer-chat-star'));
      expect(_in('local-composer-row', _key('local-composer-input')), findsOneWidget);
      await tester.enterText(_in('local-composer-row', _key('local-composer-input')), '你好');
      await _tap(tester, _in('local-composer-row', _key('local-composer-send')));
      await _settle(tester);
      expect(_key('local-composer-row'), findsNothing);
      await _close(tester, room);

      final immersive = await _pump(tester, portrait: true, settings: {Settings.portraitLayoutMode: 'immersive'});
      expect(
        tester.getSize(_key('live-play-portrait-sheet')).height,
        portraitPanelLeast,
        reason: '"沉浸": the lowest; no composer bar to make room for',
      );
      await _close(tester, immersive);
    });

    testWidgets('the phone stack keeps the composer bar under the list, with the long hint', (tester) async {
      final room = await _pump(tester);
      expect(_key('local-composer-bar'), findsOneWidget);
      expect(_key('local-composer-chat-star'), findsNothing);
      expect(_in('local-composer-bar', find.text('发送本地弹幕，只有你看得到')), findsOneWidget);
      await _close(tester, room);
    });
  });

  testWidgets('c4: the portrait fullscreen field says the short hint', (tester) async {
    final room = await _pump(tester, portrait: true);
    await _tap(tester, _key('live-play-fullscreen'));
    expect(_in('live-play-bottom-first-row', find.text('发送一条本地字幕')), findsOneWidget);
    expect(_in('live-play-bottom-first-row', find.text('发送本地弹幕，只有你看得到')), findsNothing);
    await _close(tester, room);
  });

  group('c6 the details', () {
    testWidgets('the time on air short in a narrow cell; the link without https://; follow filled', (tester) async {
      final room = await _pump(tester);
      await _tap(tester, _key('live-play-info'));
      expect(_key('live-play-details'), findsOneWidget);
      expect(_in('live-play-details-figures', find.text('6:45')), findsOneWidget);
      expect(_in('live-play-details-figures', find.text('6 小时 45 分')), findsNothing);
      expect(_in('live-play-details', find.text('live.bilibili.com/6')), findsOneWidget);
      expect(_in('live-play-details', find.text('https://live.bilibili.com/6')), findsNothing);
      await tester.ensureVisible(_key('live-play-details-copy-link'));
      await _tap(tester, _key('live-play-details-copy-link'));
      expect(room.copied.last, 'https://live.bilibili.com/6', reason: 'the copy is the whole address');

      // Not followed: filled with the theme colour like the app bar's.
      final scheme = Theme.of(tester.element(_key('live-play-details'))).colorScheme;
      Color? background() =>
          tester.widget<ButtonStyleButton>(_key('live-play-details-follow')).style?.backgroundColor?.resolve({});
      await tester.ensureVisible(_key('live-play-details-follow'));
      expect(background(), scheme.primary);
      expect(_in('live-play-details-follow', find.text('关注')), findsOneWidget);
      await _tap(tester, _key('live-play-details-follow'));
      await _settle(tester);
      expect(_in('live-play-details-follow', find.text('已关注')), findsOneWidget);
      expect(background(), scheme.secondaryContainer, reason: 'followed: light in both places');
      await _close(tester, room);
    });

    testWidgets('the clock keeps the long words where they fit', (tester) async {
      await tester.runAsync(loadStrings);
      final started = DateTime(2026, 10, 8, 12);
      final now = DateTime(2026, 10, 8, 18, 45);
      Future<void> clock(double width) => tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: SizedBox(
                width: width,
                child: OnAirClock(startedAt: started, now: () => now, fitWidth: width),
              ),
            ),
          ),
        ),
      );
      await clock(400);
      expect(find.text('6 小时 45 分'), findsOneWidget);
      await clock(60);
      expect(find.text('6:45'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
