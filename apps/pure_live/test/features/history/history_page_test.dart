import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/history/history_page.dart';
import 'package:pure_live/features/history/history_refresh.dart';
import 'package:pure_live/features/history/history_sections.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

import '../../support.dart';

/// "Now" of every test: 2026-10-01 20:00 local time.
final DateTime _now = DateTime(2026, 10, 1, 20);

LiveRoom _room(String id, {String platform = 'douyu', String title = '', String nick = '', LiveStatus? status}) =>
    LiveRoom(
      platform: platform,
      roomId: id,
      title: title.isEmpty ? 'Title $id' : title,
      nick: nick.isEmpty ? 'Nick $id' : nick,
      watching: '',
      liveStatus: status,
    );

final class _Harness {
  new(this.services, this.toasts, this.loaded);

  final AppServices services;
  final List<String> toasts;
  final List<String> loaded;

  HistoryStore get history => services.store.history;
}

/// Pumps the page over an in-memory store holding [rooms] (newest first,
/// watched at the given times) with [load] as the refresh loader.
Future<_Harness> _pump(
  WidgetTester tester, {
  List<(LiveRoom, DateTime)> rooms = const [],
  HistoryRoomLoader? load,
  double width = 400,
  double height = 900,
}) async {
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(() async {
    final services = await testServices();
    for (final (room, at) in rooms.reversed) {
      await services.store.history.record(room, now: at);
    }
    return services;
  }))!;
  addTearDown(() => tester.runAsync(services.close));
  final strings = (await tester.runAsync(loadStrings))!;
  final toasts = <String>[];
  final previousToast = AppNavigator.toast;
  AppNavigator.toast = toasts.add;
  addTearDown(() => AppNavigator.toast = previousToast);
  final loaded = <String>[];
  // The page on a router whose live room shows the room it got.
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const HistoryPage(route: RouteArgs(RoutePath.kHistory)),
      ),
      GoRoute(
        path: RoutePath.kLivePlay,
        builder: (_, state) => Scaffold(body: Text('room ${(state.extra! as LiveRoom).roomId}')),
      ),
    ],
  );
  AppNavigator.router = router;
  addTearDown(() => AppNavigator.router = null);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        historyClockProvider.overrideWithValue(() => _now),
        historyLoaderProvider.overrideWithValue((room) async {
          loaded.add(room.roomId);
          return await (load ?? (room) async => room)(room);
        }),
      ],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp.router(
          theme: const LiveTheme(primaryColor: Colors.blue).light,
          routerConfig: router,
        ),
      ),
    ),
  );
  await _settle(tester);
  return _Harness(services, toasts, loaded);
}

/// Lets the store's queries (real async work) finish, then the frames.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
  }
}

Future<List<String>> _ids(WidgetTester tester, HistoryStore history) async => [
  for (final room in (await tester.runAsync(history.all))!) room.roomId,
];

void main() {
  testWidgets('shows the empty state', (tester) async {
    await _pump(tester);
    expect(find.text('0 / 50 条'), findsOneWidget);
    expect(find.text('无观看历史记录'), findsOneWidget);
    expect(find.byKey(const ValueKey('history-clear')), findsNothing);
  });

  testWidgets('shows the rooms by day with count and limit in the title', (tester) async {
    await _pump(
      tester,
      rooms: [
        (_room('1'), _now.subtract(const Duration(hours: 1))),
        (_room('2', status: LiveStatus.live), _now.subtract(const Duration(days: 1))),
        (_room('3'), _now.subtract(const Duration(days: 3))),
        (_room('4'), _now.subtract(const Duration(days: 30))),
      ],
    );
    expect(find.text('4 / 50 条'), findsOneWidget);
    for (final section in HistorySection.values) {
      expect(find.byKey(ValueKey('history-section-${section.name}')), findsOneWidget);
    }
    expect(find.text('今天 · 1'), findsOneWidget);
    expect(find.byType(LiveRoomCard), findsNWidgets(4));
    expect(find.text('Title 1'), findsOneWidget);

    // A tap opens the live room with the stored room.
    await tester.tap(find.text('Title 3'));
    await tester.pumpAndSettle();
    expect(find.text('room 3'), findsOneWidget);
    await tester.pump(AppNavigator.openGuard);
  });

  testWidgets('removes one room after asking and clears all after asking', (tester) async {
    final h = await _pump(tester, rooms: [(_room('1'), _now), (_room('2'), _now), (_room('3'), _now)]);
    // The card's delete button asks first; cancelling keeps the room.
    await tester.tap(find.byTooltip('从观看记录删除Title 2'));
    await tester.pumpAndSettle();
    expect(find.text('要从观看记录中删除“Title 2”吗？仅删除这一条记录。'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await _settle(tester);
    expect(await _ids(tester, h.history), ['1', '2', '3']);

    await tester.tap(find.byTooltip('从观看记录删除Title 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('history-confirm')));
    await _settle(tester);
    expect(await _ids(tester, h.history), ['1', '3']);
    expect(h.toasts, ['已从观看记录删除']);
    expect(find.text('2 / 50 条'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('history-clear')));
    await tester.pumpAndSettle();
    expect(find.text('确定清空这 2 条历史记录吗？此操作不可撤销。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('history-confirm')));
    await _settle(tester);
    expect(await _ids(tester, h.history), isEmpty);
    expect(find.text('无观看历史记录'), findsOneWidget);
  });

  testWidgets('the filter narrows the rooms, and clearing removes only the matches', (tester) async {
    final h = await _pump(
      tester,
      rooms: [
        (_room('1', title: 'Football night'), _now),
        (_room('2', platform: 'bilibili', title: 'Music'), _now),
        (_room('3', title: 'More football'), _now),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('history-filter')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('history-filter-field')), 'FOOTBALL');
    await tester.pumpAndSettle();
    expect(find.byType(LiveRoomCard), findsNWidgets(2));
    expect(find.text('2 条'), findsOneWidget);

    // The platform's display name matches too.
    await tester.enterText(find.byKey(const ValueKey('history-filter-field')), '哔哩');
    await tester.pumpAndSettle();
    expect(find.byType(LiveRoomCard), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('history-filter-field')), 'nothing like this');
    await tester.pumpAndSettle();
    expect(find.text('没有符合条件的观看记录'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('history-filter-field')), 'football');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('history-clear')));
    await tester.pumpAndSettle();
    expect(find.textContaining('筛选出的 2 条'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('history-confirm')));
    await _settle(tester);
    expect(await _ids(tester, h.history), ['2']);
  });

  testWidgets('refresh updates the rooms, keeps the watch time and marks failures pending', (tester) async {
    final watched = _now.subtract(const Duration(hours: 2));
    final h = await _pump(
      tester,
      rooms: [
        (_room('1', status: LiveStatus.offline), watched),
        (_room('2', status: LiveStatus.live), watched),
        (_room('3', platform: 'huajiao', status: LiveStatus.live), watched),
      ],
      load: (room) async {
        if (room.roomId == '2') throw StateError('network');
        if (room.platform == 'huajiao') throw StateError('retired');
        return room.copyWith(title: 'Fresh ${room.roomId}', liveStatus: LiveStatus.live, popularity: '25000');
      },
    );
    await tester.tap(find.byKey(const ValueKey('history-refresh')));
    await tester.pump();
    await _settle(tester);
    expect(h.loaded.toSet(), {'1', '2', '3'});
    expect(h.toasts, ['3 个直播间中有 2 个刷新失败，已标为状态未知']);
    final rooms = (await tester.runAsync(h.history.all))!;
    expect([for (final room in rooms) room.roomId], ['1', '2', '3']);
    expect(rooms[0].title, 'Fresh 1');
    expect(rooms[0].effectiveLiveStatus, LiveStatus.live);
    expect(rooms[0].lastWatchedAt, watched.millisecondsSinceEpoch);
    expect(rooms[1].title, 'Title 2');
    expect(rooms[1].effectiveLiveStatus, LiveStatus.unknown);
    expect(find.text('Fresh 1'), findsOneWidget);
    // The live room's popularity, shortened like 3.x.
    expect(find.text('2.5万'), findsOneWidget);
    expect(find.byKey(const ValueKey('history-progress')), findsNothing);
  });

  testWidgets('F.5a c3 (1-1): a carousel and a banned room are marked on their history cards', (tester) async {
    await _pump(
      tester,
      rooms: [
        (_room('1', platform: 'bilibili'), _now),
        (_room('2'), _now),
        (_room('3'), _now),
      ],
      load: (room) async => room.copyWith(
        liveStatus: switch (room.roomId) {
          '1' => LiveStatus.carousel,
          '2' => LiveStatus.banned,
          _ => LiveStatus.live,
        },
      ),
    );
    expect(find.byKey(const ValueKey('room-card-restriction')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('history-refresh')));
    await tester.pump();
    await _settle(tester);
    Finder markOf(String id) => find.descendant(
      of: find.byKey(ValueKey('history-card-${_room(id, platform: id == '1' ? 'bilibili' : 'douyu').identityKey}')),
      matching: find.byKey(const ValueKey('room-card-restriction')),
    );
    expect(find.descendant(of: markOf('1'), matching: find.text('轮播')), findsOneWidget);
    expect(find.descendant(of: markOf('2'), matching: find.text('已封禁')), findsOneWidget);
    expect(markOf('3'), findsNothing);
    // Both are off air: dimmed and marked like an offline room (U.4a c4).
    expect(find.byKey(const ValueKey('room-card-offline')), findsNWidgets(2));
  });

  testWidgets('the limit dialog warns about removed entries and trims the history', (tester) async {
    final h = await _pump(
      tester,
      rooms: [for (var i = 1; i <= 25; i++) (_room('$i'), _now.subtract(Duration(minutes: i)))],
    );
    await tester.tap(find.byKey(const ValueKey('history-limit')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '20'));
    await tester.pumpAndSettle();
    expect(find.text('保存后将删除最早的 5 条记录'), findsOneWidget);

    // A typed number is used even without pressing "apply" (3.x dropped it).
    await tester.enterText(find.byKey(const ValueKey('history-limit-custom')), '-3');
    await tester.tap(find.byKey(const ValueKey('history-limit-save')));
    await tester.pumpAndSettle();
    expect(find.text('请输入大于或等于 0 的整数。'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('history-limit-custom')), '22');
    await tester.tap(find.byKey(const ValueKey('history-limit-save')));
    await _settle(tester);
    expect(find.byType(Dialog), findsNothing);
    expect(h.services.store.settings.get(Settings.historyLimit), 22);
    expect(await _ids(tester, h.history), [for (var i = 1; i <= 22; i++) '$i']);
    expect(find.text('22 / 22 条'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('history-limit')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '不限'));
    await tester.tap(find.byKey(const ValueKey('history-limit-save')));
    await _settle(tester);
    expect(find.text('22 条 / 不限'), findsOneWidget);
  });

  testWidgets('long press opens the menu: follow, unfollow after asking, remove', (tester) async {
    final h = await _pump(tester, rooms: [(_room('7', nick: 'Streamer'), _now.subtract(const Duration(minutes: 5)))]);
    await tester.longPress(find.byType(LiveRoomCard));
    await tester.pumpAndSettle();
    expect(find.text('Streamer'), findsWidgets);
    expect(find.textContaining('房间号 7'), findsOneWidget);
    expect(find.textContaining('今天 19:55'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('room-menu-follow')));
    await _settle(tester);
    expect(await tester.runAsync(() => h.services.store.follows.contains(_room('7'))), isTrue);
    expect(h.toasts, ['已关注 Streamer']);
    expect(find.byType(Dialog), findsNothing);

    // Unfollowing asks first.
    await tester.longPress(find.byType(LiveRoomCard));
    await _settle(tester);
    expect(find.text('已关注'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('room-menu-follow')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('unfollow-confirm')));
    await _settle(tester);
    expect(await tester.runAsync(() => h.services.store.follows.contains(_room('7'))), isFalse);

    await tester.longPress(find.byType(LiveRoomCard));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('history-menu-remove')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('history-confirm')));
    await _settle(tester);
    expect(await _ids(tester, h.history), isEmpty);
  });

  testWidgets('U.5c: "观看记录" with the count under it on the left; filter, refresh, limit, clear in order', (
    tester,
  ) async {
    await _pump(
      tester,
      rooms: [
        (_room('1', platform: 'bilibili'), _now),
        (_room('2'), _now),
      ],
    );
    final title = tester.getRect(find.byKey(const ValueKey('page-title')));
    final count = tester.getRect(find.byKey(const ValueKey('page-subtitle')));
    expect(find.text('观看记录'), findsOneWidget);
    expect(find.text('2 / 50 条'), findsOneWidget);
    expect(title.left, lessThan(40), reason: 'left-aligned, not centred like 3.x');
    expect(count.left, title.left);
    expect(count.top, greaterThanOrEqualTo(title.bottom - 1));

    const buttons = [
      ('history-filter', AppIcons.filter, '筛选'),
      ('history-refresh', AppIcons.refresh, '刷新开播状态'),
      ('history-limit', AppIcons.historyLimit, '观看记录保留数量'),
      ('history-clear', AppIcons.clearHistory, '清空历史'),
    ];
    var left = title.right;
    for (final (key, icon, tooltip) in buttons) {
      final button = find.byKey(ValueKey(key));
      expect(
        find.descendant(of: button, matching: find.byIcon(icon)),
        findsOneWidget,
        reason: key,
      );
      expect(tester.widget<IconButton>(button).tooltip, tooltip);
      final rect = tester.getRect(button);
      expect(rect.left, greaterThanOrEqualTo(left), reason: '$key comes after the one before');
      expect(rect.width, greaterThanOrEqualTo(48));
      left = rect.right;
    }

    // The cards: 3.x's delete button, and the platform for a mixed list.
    final card = tester.widget<LiveRoomCard>(find.byType(LiveRoomCard).first);
    expect(card.showDelete, isTrue);
    expect(card.mixedPlatforms, isTrue);
    expect(find.byTooltip('从观看记录删除Title 1'), findsOneWidget);
  });

  for (final (width, height, columns) in [(393.0, 852.0, 2), (852.0, 393.0, 4), (1280.0, 800.0, 6)]) {
    testWidgets('U.5c c8: ${width.toInt()}×${height.toInt()} has $columns columns', (tester) async {
      await _pump(tester, width: width, height: height, rooms: [for (var i = 1; i <= 8; i++) (_room('$i'), _now)]);
      final tops = [
        for (final element in find.byType(LiveRoomCard).evaluate()) tester.getTopLeft(find.byWidget(element.widget)).dy,
      ];
      expect(tops.where((top) => top == tops.first).length, columns);
      // The day's heading lines up with the grid's edge.
      expect(tester.getTopLeft(find.byKey(const ValueKey('history-section-today'))).dx, 12);
      expect(tester.getTopLeft(find.byType(LiveRoomCard).first).dx, 6);
    });
  }

  testWidgets('U.5c: Esc and Back close the filter before leaving', (tester) async {
    await _pump(tester, rooms: [(_room('1'), _now), (_room('2'), _now)]);
    await tester.tap(find.byKey(const ValueKey('history-filter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-filter-field')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('history-filter')), matching: find.byIcon(AppIcons.filterOff)),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-filter-field')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('history-filter')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-filter-field')), findsNothing);
    expect(find.byType(HistoryPage), findsOneWidget);
  });

  testWidgets('Appendix A 14: a right click on a card opens the dialog a long press opens', (tester) async {
    await _pump(tester, rooms: [(_room('7', nick: 'Streamer'), _now)]);
    await tester.tap(find.byType(LiveRoomCard), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('room-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('history-menu-remove')), findsOneWidget);
  });

  testWidgets('U.5c: the empty page says what comes here and has no clear button', (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('history-empty')), findsOneWidget);
    expect(find.text('看过的直播间会按观看时间出现在这里'), findsOneWidget);
    expect(find.byIcon(AppIcons.historyEmpty), findsOneWidget);
    expect(find.byKey(const ValueKey('history-clear')), findsNothing);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('history-refresh'))).onPressed, isNull);
  });

  testWidgets("U.5c: the limit dialog keeps 3.x's whole-width apply button", (tester) async {
    await _pump(tester, rooms: [(_room('1'), _now)]);
    await tester.tap(find.byKey(const ValueKey('history-limit')));
    await tester.pumpAndSettle();
    final apply = find.byKey(const ValueKey('history-limit-apply'));
    final field = tester.getRect(find.byKey(const ValueKey('history-limit-custom')));
    expect(tester.getRect(apply).width, closeTo(field.width, 1));
    expect(tester.getRect(apply).height, 48);
    await tester.enterText(find.byKey(const ValueKey('history-limit-custom')), '30');
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(find.text('当前值: 30'), findsOneWidget);
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '30')).selected, isTrue);
  });

  test('card data: audience settings, restriction, platform name for a missing streamer', () async {
    await loadStrings();
    final room = LiveRoom(
      platform: 'jdlive',
      roomId: '1',
      watching: '',
      cover: '//img.example.com/a.jpg',
      liveStatus: LiveStatus.live,
      popularity: '1500',
      onlineViewers: '320',
      restriction: LiveRestriction.paid,
    );
    final data = const AudiencePolicy(preferRealOnline: false, realOnlinePlatforms: {}).cardOf(room);
    expect(data.title, '未命名直播间');
    expect(data.anchorName, '京东直播');
    expect(data.coverUrl, 'https://img.example.com/a.jpg');
    expect(data.audience, const RoomAudience(kind: RoomAudienceKind.popularity, value: '1500'));
    expect(data.restrictionLabel, '付费');
    final real = const AudiencePolicy(preferRealOnline: true, realOnlinePlatforms: {'jdlive'}).cardOf(room);
    expect(real.audience?.kind, RoomAudienceKind.onlineViewers);
    expect(readableAudience('15000'), '1.5万');
    expect(normalizeImageUrl('"null"'), '');
  });

  test('refresh runs at most the given number of requests at once and stops when cancelled', () async {
    var running = 0;
    var peak = 0;
    final rooms = [for (var i = 0; i < 9; i++) _room('$i')];
    final result = await refreshHistoryRooms(
      rooms,
      maxConcurrent: 3,
      load: (room) async {
        peak = (++running) > peak ? running : peak;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        running--;
        return room;
      },
    );
    expect(peak, 3);
    expect(result.succeeded, 9);
    expect(result.cancelled, isFalse);

    var calls = 0;
    final cancelled = await refreshHistoryRooms(
      rooms,
      maxConcurrent: 1,
      load: (room) async => room,
      onProgress: (done) => calls = done,
      isCancelled: () => calls >= 2,
    );
    expect(cancelled.cancelled, isTrue);
    expect(cancelled.rooms, hasLength(2));
  });
}
