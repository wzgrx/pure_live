// B05 (docs/ui/compare/U.2m): the "切换直播间" panel, the same in every
// layout; v3's small cards with at least as many on screen as v3 (GitHub
// issue #37), a list style that is remembered; switching in place; the
// fullscreen menus without what their bars show.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/buttons/room_menu_button.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/logic/room_layout.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/logic/room_switch.dart';
import 'package:pure_live/features/live_play/player/player_view.dart';
import 'package:pure_live/features/live_play/switch_room/room_switch_panel.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';
import 'live_play_support.dart';

LiveRoom _room(String id, {LiveStatus status = LiveStatus.live, String online = ''}) => LiveRoom(
  platform: SiteIds.bilibili,
  roomId: id,
  nick: '主播$id',
  title: '标题$id',
  area: '分区$id',
  liveStatus: status,
  onlineViewers: online,
);

/// A platform answering every room by its id, and naming the room in its
/// lines.
class _ListSite extends FakeSite {
  new(this.rooms) : super(rooms.values.first);

  final Map<String, LiveRoom> rooms;

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async =>
      rooms[roomId] ?? _room(roomId, status: LiveStatus.offline);

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async => [
    'https://a.example/${detail.roomId}/index.m3u8',
  ];
}

final class _Room {
  new(this.services, this.engine, this.sessions, this.toasts);

  final AppServices services;
  final FakeEngine engine;
  final List<PlaybackSession> sessions;
  final List<String> toasts;
}

/// The room of [arguments] (room 6 by default) on an Android device
/// [width] × [height]; [follows] followed and [history] watched before.
Future<_Room> _pump(
  WidgetTester tester, {
  double width = 393,
  double height = 852,
  Object? arguments,
  List<LiveRoom> follows = const [],
  List<(LiveRoom, Duration)> history = const [],
  Map<Setting<Object>, Object> settings = const {},
  bool portraitStream = false,
  Map<String, LiveRoom>? rooms,
}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  RoomOrientationChoice.clearSession();
  final services = (await tester.runAsync(testServices))!;
  await tester.runAsync(loadStrings);
  await tester.runAsync(() async {
    for (final MapEntry(:key, :value) in settings.entries) {
      await services.store.settings.set(key, value);
    }
    for (final room in follows) {
      await services.store.follows.add(room);
    }
    for (final (room, ago) in history) {
      await services.store.history.record(room, now: DateTime.now().subtract(ago));
    }
  });
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  const systemAccess = MethodChannel('pure_live/system_access');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(systemAccess, (call) async => true);
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(systemAccess, null));
  final toasts = <String>[];
  final previous = AppNavigator.toast;
  final previousShow = AppNavigator.showToast;
  AppNavigator.toast = toasts.add;
  AppNavigator.showToast = (toast) =>
      toasts.add('${toast.message}${toast.actionLabel == null ? '' : ' | ${toast.actionLabel}'}');
  addTearDown(() {
    AppNavigator.toast = previous;
    AppNavigator.showToast = previousShow;
  });
  final site = _ListSite(
    rooms ??
        {
          for (final id in ['5', '6', '7', '8']) id: _room(id),
        },
  );
  final engine = FakeEngine();
  final sessions = <PlaybackSession>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({SiteIds.bilibili: () => site})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: FakeDanmaku.new})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) {
          final session = PlaybackSession(engine: () async => engine, opener: MediaOpener());
          sessions.add(session);
          return session;
        }),
      ],
      child: MaterialApp(
        theme: const LiveTheme().light,
        home: LivePlayPage(route: RouteArgs(RoutePath.kLivePlay, arguments: arguments ?? _room('6'))),
      ),
    ),
  );
  await _settle(tester);
  if (portraitStream) {
    engine.emit(const EngineVideoSize(720, 1280));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
  return _Room(services, engine, sessions, toasts);
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

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(_key(key));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// The room menu's "切换直播间".
Future<void> _openFromMenu(WidgetTester tester) async {
  await _tap(tester, 'live-play-menu');
  await _tap(tester, 'room-menu-switchRoom');
  await _settle(tester);
}

/// The room the player shows.
String _shown(WidgetTester tester) => tester.widget<RoomPlayer>(find.byType(RoomPlayer)).controller.room.roomId;

/// The keys of the open menu's entries.
List<String> _menuEntries() => [
  for (final entry in RoomMenuEntry.values)
    if (_key('room-menu-${entry.name}').evaluate().isNotEmpty) entry.name,
];

// ---- 3.x's grid (play_other.dart, content_first_panel_layout.dart) ----

int _v3Columns(double width) => width - 12 >= 168 * 2 + 5 ? 2 : 1;

double _v3CardHeight(double width, double height, int columns) {
  const footer = 36.0;
  final natural = (width - 12 - 5 * (columns - 1)) / columns * 9 / 16 + footer;
  const accessible = footer + 60;
  const double maximum = 310;
  if (columns < 2) return math.max(natural, accessible).clamp(118, maximum).toDouble();
  final twoRows = (height - 12 - 5) / 2;
  final compact = math.max(math.min<double>(112, natural), math.min(natural, twoRows));
  return math.max(accessible, compact).clamp(96, maximum).toDouble();
}

/// 3.x's dialog in a [width] × [height] window (`resolveContentFirstPanelLayout`).
Size _v3Dialog(double width, double height) {
  final inset = width < 720 || height < 520 ? 8.0 : 20.0;
  final availableWidth = math.max<double>(280, width - inset * 2);
  final availableHeight = math.max<double>(240, height - inset * 2);
  return Size(
    (availableWidth * 0.5).clamp(280.0, availableWidth),
    height.clamp(240.0, 720.0).clamp(240.0, availableHeight),
  );
}

/// Cards wholly in view in a grid [height] high.
int _whole(double height, double card, int columns) {
  var count = 0;
  for (var top = 6.0; top + card <= height + 0.01; top += card + 5) {
    count += columns;
  }
  return count;
}

void main() {
  group('B05 logic', () {
    test("c3: the columns are 3.x's at every phone width; wider grids get more", () {
      for (final width in [280.0, 300.0, 352.0, 353.0, 360.0, 393.0, 418.0, 430.0, 480.0, 525.0]) {
        expect(roomSwitchColumns(width), _v3Columns(width), reason: '$width');
      }
      expect(roomSwitchColumns(526), 3);
      expect(roomSwitchColumns(800), 4);
      expect(roomSwitchColumns(0), 1);
    });

    test('c3: on every layout the grid shows at least as many cards as 3.x (issue #37)', () {
      // The window, then the new panel's grid (the panel less 132 of
      // header, groups and "正在观看", as the design drew it; the shared
      // header is 4 lower, which only leaves more room).
      const chrome = 132.0;
      final layouts = <(String, Size, Size)>[
        ('phone', const Size(393, 852), const Size(393, 852 - 36 - 56 - 221 - 16)),
        ('portrait fullscreen', const Size(393, 852), const Size(393, 852 * 0.6 - 16)),
        ('landscape', const Size(852, 393), const Size(360, 393)),
        ('narrow landscape', const Size(740, 360), const Size(360, 360)),
        ('tablet', const Size(1280, 800), const Size(360, 800 - 24 - 56)),
        ('upright tablet', const Size(800, 1280), const Size(800, 1280 - 24 - 56 - 450 - 16)),
      ];
      for (final (name, window, panel) in layouts) {
        final dialog = _v3Dialog(window.width, window.height);
        final v3Columns = _v3Columns(dialog.width);
        final v3Grid = dialog.height - 97;
        final v3 = _whole(v3Grid, _v3CardHeight(dialog.width, v3Grid, v3Columns), v3Columns);
        final columns = roomSwitchColumns(panel.width);
        final grid = panel.height - chrome;
        final now = _whole(grid, roomSwitchCardHeight(width: panel.width, height: grid, columns: columns), columns);
        expect(now, greaterThanOrEqualTo(v3), reason: '$name: $now cards, 3.x $v3');
      }
    });

    test('c3: two columns are squeezed to keep two rows in view, never under 96', () {
      expect(roomSwitchCardHeight(width: 360, height: 2000, columns: 2), closeTo(171.5 * 9 / 16 + 26, 0.01));
      expect(roomSwitchCardHeight(width: 360, height: 228, columns: 2), closeTo((228 - 17) / 2, 0.01));
      expect(roomSwitchCardHeight(width: 360, height: 100, columns: 2), 96);
      expect(roomSwitchCardHeight(width: 300, height: 100, columns: 1), closeTo(288 * 9 / 16 + 26, 0.01));
    });

    test("c5, c6, c9, X1, X3: the groups leave the room out; history takes the follow's state", () {
      final current = _room('6');
      final follows = [
        _room('1', online: '10'),
        _room('2', online: '900'),
        current,
        _room('3', status: LiveStatus.replay),
        _room('4', status: LiveStatus.offline),
      ];
      final history = [_room('4').copyWith(lastWatchedAt: 5), current, _room('9', status: LiveStatus.offline)];
      List<LiveRoom> byOnline(List<LiveRoom> rooms) => [...rooms]
        ..sort(
          (a, b) =>
              int.parse(b.onlineViewers.isEmpty ? '0' : b.onlineViewers)
                  .compareTo(int.parse(a.onlineViewers.isEmpty ? '0' : a.onlineViewers)),
        );
      final lists = roomSwitchLists(
        follows: follows,
        history: history,
        source: [_room('7'), current, _room('8')],
        current: current,
        rank: byOnline,
      );
      expect(lists.onAir.map((room) => room.roomId), ['2', '1'], reason: 'by audience, without the room');
      expect(lists.replays.map((room) => room.roomId), ['3']);
      expect(lists.source.map((room) => room.roomId), ['7', '8']);
      expect(lists.history.map((room) => room.roomId), ['4', '9']);
      expect(lists.history.first.liveStatus, LiveStatus.offline, reason: "the follow's fresher state");
      expect(lists.history.first.lastWatchedAt, 5, reason: 'and the watch time');
      expect(lists.groups, RoomSwitchGroup.values);
      expect(lists.initial(null), RoomSwitchGroup.source, reason: 'X1: the list the user was going through');
      expect(lists.initial(RoomSwitchGroup.history), RoomSwitchGroup.history);

      final fromFollows = roomSwitchLists(
        follows: follows,
        history: const [],
        source: follows,
        current: current,
        rank: byOnline,
      );
      expect(fromFollows.source, isEmpty, reason: 'X3: a follows list is the "关注在播" group already');
      expect(fromFollows.groups, isNot(contains(RoomSwitchGroup.source)));
      expect(fromFollows.initial(RoomSwitchGroup.source), RoomSwitchGroup.onAir);
    });

    test('c7: the filter matches the streamer, ignoring case; time ago', () {
      final rooms = [_room('1').copyWith(nick: 'Aki 酱'), _room('2').copyWith(nick: '星河')];
      expect(filterByStreamer(rooms, ' aki ').map((room) => room.roomId), ['1']);
      expect(filterByStreamer(rooms, ''), rooms);
      expect(filterByStreamer(rooms, '阿狸'), isEmpty);
      final now = DateTime(2026, 10, 2, 12);
      expect(agoOf(now.subtract(const Duration(seconds: 30)), now), (unit: AgoUnit.now, count: 0));
      expect(agoOf(now.subtract(const Duration(minutes: 5)), now), (unit: AgoUnit.minutes, count: 5));
      expect(agoOf(now.subtract(const Duration(hours: 2, minutes: 5)), now), (unit: AgoUnit.hours, count: 2));
      expect(agoOf(now.subtract(const Duration(days: 3)), now), (unit: AgoUnit.days, count: 3));
      expect(RoomSwitchLayout.of('list'), RoomSwitchLayout.list);
      expect(RoomSwitchLayout.of('x'), RoomSwitchLayout.grid);
    });

    test('c12: the menus on the picture leave out what their bars show', () {
      expect(menuEntriesOnBars(landscape: true, cast: true), {
        RoomMenuEntry.switchRoom,
        RoomMenuEntry.cast,
        RoomMenuEntry.videoFit,
      });
      expect(menuEntriesOnBars(landscape: false, cast: true), {RoomMenuEntry.switchRoom, RoomMenuEntry.cast});
      expect(menuEntriesOnBars(landscape: true, cast: false), {RoomMenuEntry.switchRoom, RoomMenuEntry.videoFit});
      final landscape = roomMenuGroups(
        iptv: false,
        windows: false,
        cast: true,
        onBars: menuEntriesOnBars(landscape: true, cast: true),
      );
      expect(landscape, [
        [RoomMenuEntry.timer, RoomMenuEntry.volume],
        [RoomMenuEntry.streamLink, RoomMenuEntry.share, RoomMenuEntry.external],
        <RoomMenuEntry>[],
      ]);
      expect(roomMenuGroups(iptv: false, windows: false, cast: true).first.first, RoomMenuEntry.switchRoom);
    });
  });

  group('B05 panel', () {
    tearDown(() => RoomSwitchPanel.follows = null);

    testWidgets("c1: portrait: the menu opens the panel over everything under the picture; grid of 3.x's columns", (
      tester,
    ) async {
      final room = await _pump(
        tester,
        follows: [
          _room('5', online: '1200'),
          _room('7'),
          _room('6'),
        ],
      );
      await _openFromMenu(tester);
      final panel = _key('live-play-switch-panel');
      expect(find.descendant(of: _key('live-play-below-panel'), matching: panel), findsOneWidget);
      final rect = tester.getRect(panel);
      expect(rect.top, closeTo(tester.getRect(_key('live-play-video-box')).bottom, 0.5), reason: 'from the lower edge');
      expect(rect.width, 393);
      expect(find.text('切换直播间'), findsOneWidget);
      expect(_key('switch-refresh'), findsNothing, reason: 'no follows refresh linked, no button');
      final grid = tester.widget<GridView>(_key('switch-grid'));
      expect((grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount).crossAxisCount, _v3Columns(393));
      // c6: the room being watched on top, not among the choices.
      expect(find.descendant(of: _key('switch-watching'), matching: find.textContaining('主播6')), findsOneWidget);
      expect(_key('switch-room-bilibili-6'), findsNothing);
      expect(_key('switch-room-bilibili-5'), findsOneWidget);
      expect(find.descendant(of: _key('switch-room-bilibili-5'), matching: find.text('直播中')), findsOneWidget);
      expect(find.descendant(of: _key('switch-room-bilibili-5'), matching: find.text('标题5')), findsOneWidget);
      expect(find.text('关注在播 2'), findsOneWidget, reason: 'c5: the count');
      await _tap(tester, 'room-panel-close');
      expect(panel, findsNothing);
      await _close(tester, room);
    });

    testWidgets('c1, c2: landscape fullscreen: ⇄ opens it on the right; a pick switches in place, still fullscreen', (
      tester,
    ) async {
      // The longest refresh time: the 360 wide header holds it with every button.
      final last = DateTime.now().subtract(const Duration(hours: 23));
      RoomSwitchPanel.follows = FollowsRefresher(refresh: () async => 0, lastRefreshedAt: () => last);
      final room = await _pump(tester, width: 852, height: 393, follows: [_room('5'), _room('7')]);
      await _tap(tester, 'live-play-fullscreen');
      final session = tester.widget<RoomPlayer>(find.byType(RoomPlayer)).controller.session;
      await _tap(tester, 'live-play-switch-room');
      await _settle(tester);
      final panel = _key('live-play-switch-panel');
      expect(find.descendant(of: _key('live-play-side-panel'), matching: panel), findsOneWidget);
      expect(tester.getRect(panel), const Rect.fromLTWH(852 - 360, 0, 360, 393));
      expect(roomSwitchColumns(360), _v3Columns(360));
      expect(tester.widget<Text>(_key('switch-refresh-label')).data, '23 小时前');
      expect(tester.getRect(_key('room-panel-title')).width, greaterThan(60), reason: 'the title still shows');

      await tester.tap(_key('switch-room-bilibili-7'));
      await tester.pump();
      await _settle(tester);
      expect(_shown(tester), '7');
      expect(panel, findsNothing, reason: 'the panel closes');
      expect(room.sessions, hasLength(1), reason: 'one player');
      expect(tester.widget<RoomPlayer>(find.byType(RoomPlayer)).controller.session, same(session));
      expect(tester.widget<RoomPlayer>(find.byType(RoomPlayer)).display, RoomDisplay.fullscreen);
      expect(find.byType(LivePlayPage), findsOneWidget);
      expect(room.engine.opens.last.uri.path, '/7/index.m3u8');
      await _close(tester, room);
    });

    testWidgets('c1, c2: portrait fullscreen: the bottom 60 %; the picked group becomes the swipe list', (
      tester,
    ) async {
      final room = await _pump(
        tester,
        follows: [_room('5'), _room('7'), _room('8')],
        portraitStream: true,
        settings: {Settings.portraitFullscreenSwipeSwitch: true},
      );
      await _tap(tester, 'live-play-fullscreen');
      expect(tester.widget<RoomPlayer>(find.byType(RoomPlayer)).display, RoomDisplay.portraitFullscreen);
      expect(_key('live-play-swipe-stage'), findsNothing, reason: 'a lone room has nothing to swipe to');
      await _tap(tester, 'live-play-switch-room');
      await _settle(tester);
      final panel = _key('live-play-switch-panel');
      expect(find.descendant(of: _key('live-play-bottom-panel'), matching: panel), findsOneWidget);
      expect(tester.getRect(_key('live-play-bottom-panel')).height, closeTo(852 * 0.6, 0.5));
      await tester.tap(_key('switch-room-bilibili-7'));
      await tester.pump();
      await _settle(tester);
      expect(_shown(tester), '7');
      expect(tester.widget<RoomPlayer>(find.byType(RoomPlayer)).display, RoomDisplay.portraitFullscreen);
      expect(_key('live-play-swipe-stage'), findsOneWidget, reason: 'swipes go through "关注在播" now');
      await _close(tester, room);
    });

    testWidgets('c1: a tablet: on the right, 360 wide and the full height over the chat column', (tester) async {
      final room = await _pump(tester, width: 1280, height: 800, follows: [_room('5')]);
      await _openFromMenu(tester);
      final side = tester.getRect(_key('live-play-side-panel'));
      expect(side.width, 360);
      expect(side.right, 1280);
      expect(
        find.descendant(of: _key('live-play-side-panel'), matching: _key('live-play-switch-panel')),
        findsOneWidget,
      );
      expect(roomSwitchColumns(360), 2);
      await _close(tester, room);
    });

    testWidgets("c13: the picture state's button opens the same panel", (tester) async {
      final room = await _pump(tester, rooms: {'6': _room('6', status: LiveStatus.offline)});
      await tester.tap(_key('live-play-state-switch-room'));
      await tester.pump();
      await _settle(tester);
      expect(_key('live-play-switch-panel'), findsOneWidget);
      await _close(tester, room);
    });

    testWidgets('c4: grid and list switch from the header and are remembered', (tester) async {
      final room = await _pump(tester, follows: [_room('5')]);
      expect(room.services.store.settings.get(Settings.roomSwitcherLayout), 'grid');
      await _openFromMenu(tester);
      expect(_key('switch-grid'), findsOneWidget);
      expect(
        find.descendant(of: _key('switch-layout'), matching: find.byIcon(AppIcons.switchRoomList)),
        findsOneWidget,
      );
      await _tap(tester, 'switch-layout');
      await _settle(tester);
      expect(room.services.store.settings.get(Settings.roomSwitcherLayout), 'list');
      expect(_key('switch-list'), findsOneWidget);
      expect(_key('switch-grid'), findsNothing);
      expect(find.text('哔哩哔哩 · 分区5'), findsOneWidget, reason: 'the row: platform · area');
      expect(tester.getSize(_key('switch-room-bilibili-5')).height, roomSwitchRowHeight);
      await _tap(tester, 'room-panel-close');
      await _openFromMenu(tester);
      expect(_key('switch-list'), findsOneWidget, reason: 'kept');
      await _close(tester, room);
    });

    testWidgets('c5, X1: from a list the source group opens first; groups switch and are kept on the page', (
      tester,
    ) async {
      final room = await _pump(
        tester,
        arguments: LiveRoomArgs(room: _room('6'), playlist: [_room('5'), _room('6'), _room('8')]),
        follows: [_room('7')],
        history: [(_room('8'), const Duration(hours: 1))],
      );
      await _openFromMenu(tester);
      ChoiceChip chip(String group) => tester.widget<ChoiceChip>(_key('switch-group-$group'));
      expect(chip('source').selected, isTrue);
      expect(find.text('来源列表 2'), findsOneWidget);
      expect(_key('switch-room-bilibili-5'), findsOneWidget);
      expect(_key('switch-room-bilibili-7'), findsNothing);
      await _tap(tester, 'switch-group-onAir');
      expect(_key('switch-room-bilibili-7'), findsOneWidget);
      await _tap(tester, 'switch-group-history');
      expect(_key('switch-room-bilibili-8'), findsOneWidget);
      expect(_key('switch-room-bilibili-6'), findsNothing, reason: 'the room itself is in the history too');
      await _tap(tester, 'room-panel-close');
      await _openFromMenu(tester);
      expect(chip('history').selected, isTrue, reason: 'kept while the page stays');
      expect(chip('replays').selected, isFalse);
      await _close(tester, room);
    });

    testWidgets('c9, c10: offline history dimmed with "未开播 · 上次看 X 前"; a long press opens the card dialog', (
      tester,
    ) async {
      final room = await _pump(tester, history: [(_room('8', status: LiveStatus.offline), const Duration(hours: 2))]);
      await _openFromMenu(tester);
      await _tap(tester, 'switch-group-history');
      final card = _key('switch-room-bilibili-8');
      expect(find.descendant(of: card, matching: find.text('未开播 · 上次看 2 小时前')), findsOneWidget);
      expect(find.descendant(of: card, matching: _key('switch-dim')), findsOneWidget);
      await tester.longPress(card);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(_key('room-menu'), findsOneWidget);
      expect(_shown(tester), '6', reason: 'a long press does not switch');
      await _close(tester, room);
    });

    testWidgets('c7, c11: the filter; empty groups and no match say so', (tester) async {
      final room = await _pump(tester);
      await _openFromMenu(tester);
      expect(_key('switch-empty-onAir'), findsOneWidget);
      expect(find.text('关注的主播现在都没开播'), findsOneWidget);
      await _close(tester, room);

      final again = await _pump(
        tester,
        follows: [
          _room('5').copyWith(nick: 'Aki'),
          _room('7').copyWith(nick: '星河'),
        ],
      );
      await _openFromMenu(tester);
      await _tap(tester, 'switch-search');
      await tester.enterText(_key('switch-search-field'), 'aki');
      await tester.pump();
      expect(_key('switch-room-bilibili-5'), findsOneWidget);
      expect(_key('switch-room-bilibili-7'), findsNothing);
      await tester.enterText(_key('switch-search-field'), '阿狸');
      await tester.pump();
      expect(_key('switch-no-match'), findsOneWidget);
      await _tap(tester, 'switch-search');
      expect(_key('switch-search-field'), findsNothing);
      expect(_key('switch-room-bilibili-7'), findsOneWidget, reason: 'closing the filter clears it');
      await _close(tester, again);
    });

    testWidgets('c8: the refresh shows the last time, a spinner meanwhile, and failures in red with a message', (
      tester,
    ) async {
      var calls = 0;
      var done = Completer<int>();
      final last = DateTime.now().subtract(const Duration(minutes: 5, seconds: 10));
      RoomSwitchPanel.follows = FollowsRefresher(
        refresh: () {
          calls++;
          return done.future;
        },
        lastRefreshedAt: () => last,
      );
      final room = await _pump(tester, follows: [_room('5', status: LiveStatus.offline)]);
      await _openFromMenu(tester);
      expect(tester.widget<Text>(_key('switch-refresh-label')).data, '5 分钟前');
      await tester.tap(_key('switch-refresh'));
      await tester.pump();
      expect(calls, 1);
      expect(_key('switch-refreshing'), findsOneWidget);
      await tester.tap(_key('switch-refresh'), warnIfMissed: false);
      await tester.pump();
      expect(calls, 1, reason: 'greyed while refreshing');
      // The refresh writes the fresh details; the groups follow the store.
      await tester.runAsync(() => room.services.store.follows.update([_room('5')]));
      done.complete(2);
      await _settle(tester);
      expect(_key('switch-refreshing'), findsNothing);
      expect(_key('switch-room-bilibili-5'), findsOneWidget);
      expect(tester.widget<Text>(_key('switch-refresh-label')).data, '刷新失败');
      expect(room.toasts, ['2 个直播间刷新失败，显示的是上次的状态 | 重试'], reason: "the app's toast with a retry");
      done = Completer<int>();
      await tester.tap(_key('switch-refresh'));
      await tester.pump();
      done.complete(0);
      await _settle(tester);
      expect(tester.widget<Text>(_key('switch-refresh-label')).data, '5 分钟前', reason: 'back to normal');
      await _close(tester, room);
    });

    testWidgets("c12: the fullscreen menus leave out the bars' entries; the room page's menu keeps them", (
      tester,
    ) async {
      final room = await _pump(tester, width: 852, height: 393);
      await _tap(tester, 'live-play-fullscreen');
      await _tap(tester, 'live-play-menu');
      expect(_menuEntries(), ['timer', 'volume', 'streamLink', 'share', 'external', 'localInteraction']);
      await _close(tester, room);

      final upright = await _pump(tester, portraitStream: true);
      await _tap(tester, 'live-play-menu');
      expect(_menuEntries(), contains('switchRoom'), reason: 'the room page: unchanged');
      expect(_menuEntries(), contains('cast'));
      await tester.tapAt(const Offset(10, 10));
      await tester.pump(const Duration(seconds: 1));
      await _tap(tester, 'live-play-fullscreen');
      await _tap(tester, 'live-play-menu');
      expect(_menuEntries(), ['timer', 'volume', 'videoFit', 'streamLink', 'share', 'external', 'localInteraction']);
      await _close(tester, upright);
    });
  });
}
