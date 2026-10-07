import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/popular/popular_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';
import 'package:pure_live/shared/rooms/room_feed.dart';
import 'package:pure_live/shared/rooms/share_code.dart';

import '../../support.dart';

LiveRoom _room(String platform, int n, {int heat = 0, LiveRestriction? restriction, LiveStatus? status}) => LiveRoom(
  platform: platform,
  roomId: '$n',
  title: 'title $n',
  nick: 'anchor $n',
  popularity: '$heat',
  audienceMetricType: AudienceMetricType.popularity,
  liveStatus: status ?? LiveStatus.live,
  restriction: restriction,
);

/// Recommendations from fixed pages; [error] fails the next request.
final class _FakeSite extends LiveSite {
  new(this.id, this.pages);

  @override
  final String id;

  @override
  String get name => id;

  final List<List<LiveRoom>> pages;
  final List<int> requested = [];
  Exception? error;

  /// Holds the next answers until it completes.
  Completer<void>? gate;

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    requested.add(page);
    if (gate case final gate?) await gate.future;
    if (error case final error?) throw error;
    return page <= pages.length ? pages[page - 1] : const [];
  }
}

/// A native directory with cursors and a scope note.
final class _FakeDirectory extends LiveSite implements LiveSiteCursorDirectoryPager, LiveDirectoryNotice {
  @override
  String get id => SiteIds.bigo;

  @override
  String get name => 'Bigo';

  final List<String?> cursors = [];

  @override
  String get directoryNoticeKey => 'bigo_directory_scope';

  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) =>
      getDirectoryPageAtCursor(page: page, cancel: cancel);

  @override
  Future<LiveDirectoryPage> getDirectoryPageAtCursor({
    required int page,
    String? cursor,
    LiveArea? category,
    CancelToken? cancel,
  }) async {
    cursors.add(cursor);
    return LiveDirectoryPage(
      rooms: [for (var i = 0; i < 3; i++) _room(SiteIds.bigo, page * 10 + i, heat: i)],
      page: page,
      hasMore: page < 2,
      nextCursor: 'c$page',
    );
  }
}

Future<AppServices> _services(Map<String, LiveSite> sites, {List<String>? platforms, String? prefer}) async {
  final base = await testServices();
  await base.store.settings.set(Settings.savedMenuIds, ['popular']);
  await base.store.settings.set(Settings.showSplashPage, false);
  await base.store.settings.set(Settings.hotAreasList, platforms ?? sites.keys.toList());
  if (prefer != null) await base.store.settings.set(Settings.preferPlatform, prefer);
  return AppServices(
    store: base.store,
    cipher: base.cipher,
    http: base.http,
    proxy: base.proxy,
    cookies: base.cookies,
    sites: SiteRegistry({for (final MapEntry(:key, :value) in sites.entries) key: () => value}),
    danmaku: base.danmaku,
    launch: base.launch,
    dataRoot: base.dataRoot,
    followsReady: base.followsReady,
    mediaOpener: base.mediaOpener,
  );
}

Future<AppServices> _pump(
  WidgetTester tester,
  Map<String, LiveSite> sites, {
  double width = 400,
  double height = 900,
  List<String>? platforms,
  String? prefer,
}) async {
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(() => _services(sites, platforms: platforms, prefer: prefer)))!;
  final strings = (await tester.runAsync(loadStrings))!;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services)],
      child: PureLiveApp(strings: strings, bundle: FileAssetBundle()),
    ),
  );
  await tester.pumpAndSettle();
  // The app shows toasts as snack bars; collect them instead.
  AppNavigator.toast = _toasts.add;
  return services;
}

final List<String> _toasts = [];

/// Taps the tab [label] and lets the page load it (80 ms after it settles).
Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

void main() {
  final toasts = _toasts;
  setUp(toasts.clear);

  group('feed', () {
    RoomFeed feed(RoomSource source, {bool Function(LiveRoom)? visible}) => RoomFeed(
      platform: 'x',
      source: source,
      rank: (_, rooms) => const AudiencePolicy(preferRealOnline: false, realOnlinePlatforms: {}).rank(rooms),
      visible: visible ?? (_) => true,
    );

    test('pages without repeats, each ranked; an empty page ends the list', () async {
      final site = _FakeSite(SiteIds.bilibili, [
        [_room('bilibili', 1, heat: 5), _room('bilibili', 2, heat: 9)],
        [_room('bilibili', 2, heat: 9), _room('bilibili', 3, heat: 1)],
      ]);
      final rooms = feed(popularSourceFor(site));
      await rooms.ensure(2);
      expect(rooms.rooms.map((room) => room.roomId), ['2', '1']);
      await rooms.ensure(10);
      expect(rooms.rooms.map((room) => room.roomId), ['2', '1', '3']);
      expect(rooms.hasMore, isFalse);
      expect(site.requested, [1, 2, 3]);
    });

    test("3.x's window sizes: a short window is the last one; one answer for IPTV and Kuaishou", () async {
      expect(popularSourceFor(_FakeSite(SiteIds.huya, [])), isA<WindowSource>());
      expect(popularSourceFor(_FakeSite(SiteIds.kuaishou, [])), isA<SingleSource>());
      final site = _FakeSite(SiteIds.douyu, [
        [for (var i = 0; i < 40; i++) _room('douyu', i)],
        [_room('douyu', 99)],
      ]);
      final rooms = feed(popularSourceFor(site));
      await rooms.ensure(50);
      expect(rooms.rooms, hasLength(41));
      expect(rooms.hasMore, isFalse);
      expect(site.requested, [1, 2]);
    });

    test('native directories follow their cursor; hidden rooms do not count toward a page', () async {
      final directory = _FakeDirectory();
      final rooms = feed(popularSourceFor(directory), visible: (room) => room.roomId != '10');
      await rooms.ensure(3);
      expect(directory.cursors, [null, 'c1']);
      expect(rooms.rooms, hasLength(5));
      expect(rooms.hiddenCount, 1);
      expect(rooms.hasMore, isFalse);
    });

    test('a failed refresh keeps the rooms; a failed first load has none', () async {
      final site = _FakeSite(SiteIds.bilibili, [
        [_room('bilibili', 1)],
      ]);
      final rooms = feed(popularSourceFor(site));
      await rooms.ensure(1);
      site.error = const NetworkFailure('bilibili');
      await rooms.refresh(count: 20);
      expect(rooms.rooms, hasLength(1));
      expect(rooms.error, isA<NetworkFailure>());
      expect(rooms.errorOnRefresh, isTrue);

      final failing = feed(popularSourceFor(_FakeSite(SiteIds.bilibili, [])..error = const NeedsLogin('bilibili')));
      await failing.ensure(20);
      expect(failing.rooms, isEmpty);
      expect(failing.error, isA<NeedsLogin>());
    });
  });

  test('cards: audience as 3.x formats it, restriction marks, hidden when it cannot play here', () async {
    await loadStrings();
    const policy = AudiencePolicy(preferRealOnline: false, realOnlinePlatforms: {});
    final card = policy.cardOf(_room('huya', 1, heat: 123456, restriction: LiveRestriction.paid));
    expect(card.audience, const RoomAudience(kind: RoomAudienceKind.popularity, value: '12.3万'));
    expect(card.restrictionLabel, '付费');
    expect(cannotPlayHere(_room('huya', 1, restriction: LiveRestriction.paid), signedIn: true), isTrue);
    expect(cannotPlayHere(_room('huya', 1, restriction: LiveRestriction.needsLogin), signedIn: true), isFalse);
    expect(cannotPlayHere(_room('huya', 1, restriction: LiveRestriction.needsLogin), signedIn: false), isTrue);
    expect(cannotPlayHere(_room('bilibili', 1, status: LiveStatus.carousel), signedIn: false), isTrue);
    expect(cannotPlayHere(_room('huya', 1), signedIn: false), isFalse);
    expect(normalizeImageUrl('//i0.hdslb.com/a.jpg'), 'https://i0.hdslb.com/a.jpg');
  });

  test("the share code is 3.x's MessagePack map in URL-safe Base64", () {
    final code = encodeRoomShareCode(LiveRoom(platform: 'douyu', roomId: '9999', title: '标题', nick: 'n'));
    final bytes = base64Url.decode(base64Url.normalize(code));
    expect(bytes.first, 0x88);
    expect(utf8.decode(bytes, allowMalformed: true), allOf(contains('pure_live'), contains('9999'), contains('标题')));
    expect(code, isNot(contains('=')));
    expect(encodeRoomShareCode(LiveRoom(platform: 'douyu', roomId: ' ')), isEmpty);
  });

  testWidgets('phone: preferred platform first, ranked cards, hidden rooms on request, a card opens its room', (
    tester,
  ) async {
    final bilibili = _FakeSite(SiteIds.bilibili, [
      [_room('bilibili', 1)],
    ]);
    final huya = _FakeSite(SiteIds.huya, [
      [
        _room('huya', 1, heat: 10),
        _room('huya', 2, heat: 30000),
        _room('huya', 3, heat: 5, restriction: LiveRestriction.paid),
      ],
    ]);
    final services = await _pump(tester, {SiteIds.bilibili: bilibili, SiteIds.huya: huya}, prefer: SiteIds.huya);
    // U.4b c1: the platform tabs take the title's place (3.x).
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.byKey(const ValueKey('popular-platform-tabs'))),
      findsOneWidget,
    );
    expect(find.text('哔哩哔哩'), findsOneWidget);
    expect(find.text('虎牙'), findsOneWidget);
    expect(huya.requested, [1]);

    final cards = tester.widgetList<LiveRoomCard>(find.byType(LiveRoomCard)).map((card) => card.data.title).toList();
    expect(cards, ['title 2', 'title 1']);
    expect(find.text('3.0万'), findsOneWidget);
    expect(find.textContaining('已隐藏 1 个'), findsOneWidget);

    await tester.tap(find.text('显示'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(find.byType(LiveRoomCard), findsNWidgets(3));
    expect(find.text('付费'), findsOneWidget);

    final shown = tester.widgetList<LiveRoomCard>(find.byType(LiveRoomCard)).map((card) => card.data.title).toList();
    await tester.tap(find.text('title 2'));
    await tester.pumpAndSettle();
    expect(find.byType(LivePlayPage), findsOneWidget);
    // U.2b2 c1: the feed's rooms go along, in its order.
    final args = tester.widget<LivePlayPage>(find.byType(LivePlayPage)).route.arguments! as LiveRoomArgs;
    expect(args.room.roomId, '2');
    expect(args.playlist.map((room) => room.title), shown);
    AppNavigator.back();
    await tester.pumpAndSettle();
    await tester.pump(AppNavigator.openGuard);
    await tester.runAsync(services.close);
  });

  testWidgets('M13.16: a platform tab tapped where it rests while the room closes switches at once', (tester) async {
    final bilibili = _FakeSite(SiteIds.bilibili, [
      [_room('bilibili', 1, heat: 3)],
    ]);
    final huya = _FakeSite(SiteIds.huya, [
      [_room('huya', 2, heat: 3)],
    ]);
    final services = await _pump(tester, {SiteIds.bilibili: bilibili, SiteIds.huya: huya}, prefer: SiteIds.huya);
    // Where the finger goes: the tabs' resting places.
    final rest = {
      for (final name in ['哔哩哔哩', '虎牙']) name: tester.getCenter(find.text(name)),
    };
    const delays = [
      Duration.zero,
      Duration(milliseconds: 60),
      Duration(milliseconds: 150),
      Duration(milliseconds: 300),
    ];
    final results = <String>[];
    for (final (index, delay) in delays.indexed) {
      final target = index.isOdd ? '虎牙' : '哔哩哔哩';
      final other = target == '虎牙' ? '哔哩哔哩' : '虎牙';
      // On the other tab, open its room and close it again.
      await _openTab(tester, other);
      await tester.tap(find.text(other == '虎牙' ? 'title 2' : 'title 1'));
      await tester.pumpAndSettle();
      expect(find.byType(LivePlayPage), findsOneWidget);
      AppNavigator.back();
      await tester.pump();
      await tester.pump(delay);
      // The page under the closing room stays where it rests (with the
      // Material transition it slid in from a quarter screen to the left).
      expect(tester.getCenter(find.text(target)), rest[target]);
      await tester.tapAt(rest[target]!);
      await tester.pumpAndSettle();
      await tester.pump(AppNavigator.openGuard);
      final tabs = tester.widget<TabBar>(find.byType(TabBar)).controller!;
      results.add('${delay.inMilliseconds}ms ${tabs.index == (target == '虎牙' ? 1 : 0) ? 'switched' : 'missed'}');
    }
    // Before the fix: [0ms missed, 60ms missed, 150ms switched, 300ms switched].
    expect(results, ['0ms switched', '60ms switched', '150ms switched', '300ms switched']);
    await tester.runAsync(services.close);
  });

  testWidgets('phone: errors show their state; retry loads; the platform list change keeps the tab', (tester) async {
    final huya = _FakeSite(SiteIds.huya, [
      [_room('huya', 1)],
    ])..error = const NeedsLogin(SiteIds.huya);
    final douyu = _FakeSite(SiteIds.douyu, [
      [_room('douyu', 1)],
    ])..error = const NetworkFailure(SiteIds.douyu);
    final services = await _pump(tester, {SiteIds.huya: huya, SiteIds.douyu: douyu}, prefer: SiteIds.douyu);
    // U.1c c4: "加载失败" with the reason; the raw error behind "详情".
    expect(find.text('加载失败'), findsOneWidget);
    expect(find.byKey(const ValueKey('status-details-button')), findsOneWidget);
    douyu.error = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('title 1'), findsOneWidget);

    await _openTab(tester, '虎牙');
    expect(find.text('需要登录账号'), findsOneWidget);

    // Douyu shown; the list loses Huya: Douyu stays.
    await _openTab(tester, '斗鱼');
    await tester.runAsync(() => services.store.settings.set(Settings.hotAreasList, [SiteIds.douyu]));
    await tester.pumpAndSettle();
    expect(find.text('title 1'), findsOneWidget);

    await tester.runAsync(() => services.store.settings.set(Settings.hotAreasList, <String>[]));
    await tester.pumpAndSettle();
    expect(find.text('没有要显示的平台'), findsOneWidget);
    await tester.runAsync(services.close);
  });

  testWidgets('phone: more rooms at the end of the list; the scope note of a partial directory', (tester) async {
    final bilibili = _FakeSite(SiteIds.bilibili, [
      [for (var i = 0; i < 30; i++) _room('bilibili', i, heat: 100 - i)],
      [for (var i = 30; i < 40; i++) _room('bilibili', i, heat: 100 - i)],
    ]);
    final services = await _pump(tester, {SiteIds.bilibili: bilibili, SiteIds.bigo: _FakeDirectory()});
    expect(bilibili.requested, [1]);
    await tester.drag(find.byKey(const ValueKey('popular-grid')), const Offset(0, -20000));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const ValueKey('popular-grid')), const Offset(0, -20000));
    await tester.pumpAndSettle();
    expect(bilibili.requested, [1, 2, 3]);
    await tester.dragUntilVisible(
      find.text('没有更多数据了'),
      find.byKey(const ValueKey('popular-grid')),
      const Offset(0, -300),
    );
    expect(find.text('没有更多数据了'), findsOneWidget);
    expect(find.text('title 39'), findsOneWidget);

    await _openTab(tester, 'Bigo Live');
    expect(find.textContaining('Bigo Live 官网推荐的一部分直播'), findsOneWidget);
    await tester.runAsync(services.close);
  });

  testWidgets('P02: the phone grid bounces like 3.x with the classic header, no stretch', (tester) async {
    final bilibili = _FakeSite(SiteIds.bilibili, [
      [for (var i = 0; i < 30; i++) _room('bilibili', i, heat: 100 - i)],
    ]);
    final services = await _pump(tester, {SiteIds.bilibili: bilibili});
    final grid = find.byKey(const ValueKey('popular-grid'));
    expect(find.byType(RefreshIndicator), findsNothing);
    expect(find.ancestor(of: grid, matching: find.byType(AppRefreshView)), findsOneWidget);
    expect(find.descendant(of: grid, matching: find.byType(StretchingOverscrollIndicator)), findsNothing);
    // P03: the platform pages turn like Android's ViewPager.
    expect(tester.widget<TabBarView>(find.byType(TabBarView)).physics, isA<PureLivePageScrollPhysics>());

    final gesture = await tester.startGesture(tester.getCenter(grid));
    for (var i = 0; i < 40; i++) {
      await gesture.moveBy(const Offset(0, 5));
      await tester.pump(const Duration(milliseconds: 8));
      if (i == 4) expect(find.text('下拉刷新'), findsOneWidget);
    }
    expect(find.text('松开刷新'), findsOneWidget);
    await gesture.up();
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(bilibili.requested, [1, 1]);
    expect(find.text('刷新成功'), findsOneWidget);
    // The result shows for a second, then the header springs back.
    await tester.pump(AppRefreshView.resultDuration);
    await tester.pumpAndSettle();
    expect(find.text('刷新成功'), findsNothing);

    // A failure says so in the header too.
    bilibili.error = Exception('down');
    final again = await tester.startGesture(tester.getCenter(grid));
    for (var i = 0; i < 40; i++) {
      await again.moveBy(const Offset(0, 5));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await again.up();
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(find.text('刷新失败'), findsOneWidget);
    await tester.pump(AppRefreshView.resultDuration);
    await tester.pumpAndSettle();
    // The cards stay.
    expect(find.text('title 1'), findsOneWidget);
    await tester.runAsync(services.close);
  });

  group('P05: loading indicators only while their load runs, each in its own layer', () {
    final line = find.byKey(const ValueKey('popular-progress'));
    final footerSpinner = find.byKey(const ValueKey('popular-load-more-busy'));
    final grid = find.byKey(const ValueKey('popular-grid'));
    Future<void> frames(WidgetTester tester, [int count = 20]) async {
      for (var i = 0; i < count; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    testWidgets('at rest nothing moves; a pull refresh runs the line, the footer does not spin', (tester) async {
      // A short list: the footer is on screen and says the list ended.
      final short = _FakeSite(SiteIds.bilibili, [
        [for (var i = 0; i < 4; i++) _room('bilibili', i)],
      ]);
      final services = await _pump(tester, {SiteIds.bilibili: short});
      // At rest nothing moves: the app settled (no frame asked for).
      expect(line, findsNothing);
      expect(footerSpinner, findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(find.text('没有更多数据了'), findsOneWidget);

      // A pull's refresh: the header turns and the line runs; the footer does
      // not spin, as no more rooms are loading (it did before).
      short.gate = Completer();
      final pull = await tester.startGesture(tester.getCenter(grid));
      for (var i = 0; i < 40; i++) {
        await pull.moveBy(const Offset(0, 5));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await pull.up();
      await frames(tester, 60);
      expect(find.text('正在刷新...'), findsOneWidget);
      expect(find.descendant(of: line, matching: find.byType(LinearProgressIndicator)), findsOneWidget);
      expect(tester.renderObject(line).isRepaintBoundary, isTrue);
      expect(footerSpinner, findsNothing);
      expect(find.text('没有更多数据了'), findsOneWidget);
      short.gate!.complete();
      await frames(tester);
      await tester.pump(AppRefreshView.resultDuration);
      await tester.pumpAndSettle();
      expect(line, findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.runAsync(services.close);
    });

    testWidgets('more rooms at the end: the footer spinner and the line while the page loads, then neither', (
      tester,
    ) async {
      final long = _FakeSite(SiteIds.bilibili, [
        [for (var i = 0; i < 30; i++) _room('bilibili', i, heat: 100 - i)],
        [for (var i = 30; i < 40; i++) _room('bilibili', i, heat: 100 - i)],
      ]);
      final services = await _pump(tester, {SiteIds.bilibili: long});
      expect(line, findsNothing);
      long.gate = Completer();
      await tester.drag(grid, const Offset(0, -20000));
      await frames(tester);
      expect(long.requested, [1, 2]);
      expect(find.descendant(of: footerSpinner, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      expect(tester.renderObject(footerSpinner).isRepaintBoundary, isTrue);
      expect(line, findsOneWidget);
      long.gate!.complete();
      await tester.pumpAndSettle();
      expect(line, findsNothing);
      expect(footerSpinner, findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.runAsync(services.close);
    });
  });

  testWidgets('desktop: numbered pages, page size, refresh failure keeps the cards', (tester) async {
    final bilibili = _FakeSite(SiteIds.bilibili, [
      [for (var i = 0; i < 30; i++) _room('bilibili', i, heat: 100 - i)],
    ]);
    final services = await _pump(tester, {SiteIds.bilibili: bilibili}, width: 1000, height: 3200);
    // 20 a page above 960 px (3.x).
    expect(find.byType(LiveRoomCard), findsNWidgets(20));
    expect(find.byKey(const ValueKey('pager')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pager-page-2')));
    await tester.pumpAndSettle();
    expect(find.byType(LiveRoomCard), findsNWidgets(10));
    expect(find.text('title 20'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pager-size')));
    await tester.pumpAndSettle();
    // The small menu (U.1d, B03), the current size ticked.
    expect(find.byType(PopupMenuButton<int>), findsNothing);
    expect(find.byIcon(AppIcons.selected), findsOneWidget);
    await tester.tap(find.text('40').last);
    await tester.pumpAndSettle();
    expect(find.byType(LiveRoomCard), findsNWidgets(30));

    bilibili.error = const RateLimited(SiteIds.bilibili);
    await tester.tap(find.widgetWithText(OutlinedButton, '刷新'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('popular-refresh-error')), findsOneWidget);
    expect(find.byType(LiveRoomCard), findsNWidgets(30));
    await tester.runAsync(services.close);
  });

  testWidgets('the card menu: follow, then share copies the code', (tester) async {
    final huya = _FakeSite(SiteIds.huya, [
      [_room('huya', 7)],
    ]);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    final services = await _pump(tester, {SiteIds.huya: huya});
    await tester.longPress(find.text('title 7'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('room-menu')), findsOneWidget);
    expect(find.text('虎牙 · 房间号 7'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('room-menu-follow')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => services.store.follows.contains(_room('huya', 7))), isTrue);
    expect(toasts, contains('已关注 anchor 7'));

    await tester.longPress(find.text('title 7'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('room-menu-share')));
    await tester.pumpAndSettle();
    expect(copied, encodeRoomShareCode(_room('huya', 7)));
    expect(toasts.last, '已复制到剪贴板');
    await tester.runAsync(services.close);
  });
  testWidgets('U.4b c2: the ⌄ after the tabs opens "all platforms": logos and names, the current one ticked', (
    tester,
  ) async {
    final bilibili = _FakeSite(SiteIds.bilibili, [
      [_room('bilibili', 1)],
    ]);
    final huya = _FakeSite(SiteIds.huya, [
      [_room('huya', 2)],
    ]);
    final services = await _pump(tester, {SiteIds.bilibili: bilibili, SiteIds.huya: huya}, prefer: SiteIds.huya);
    // The ⌄ sits right of the platform tabs, in the app bar.
    final picker = find.byKey(const ValueKey('popular-all-platforms'));
    expect(find.descendant(of: find.byType(AppBar), matching: picker), findsOneWidget);
    expect(
      tester.getCenter(picker).dx,
      greaterThan(tester.getRect(find.byKey(const ValueKey('popular-platform-tabs'))).right - 1),
    );
    await tester.tap(picker);
    await tester.pumpAndSettle();
    // Phones: from the bottom.
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('点一个直接切过去；在“平台显示”里隐藏和排序'), findsOneWidget);
    // Two platforms fit: the panel is as tall as they are.
    expect(find.byKey(const ValueKey('panel-docked')), findsNothing);
    final selected = find.byKey(const ValueKey('popular-platform-selected'));
    expect(
      find.descendant(of: find.byKey(const ValueKey('popular-platform-huya')), matching: selected),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('popular-platform-settings')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('popular-platform-bilibili')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('title 1'), findsOneWidget);
    await tester.runAsync(services.close);
  });

  testWidgets('U.4b c2: on a wide window "all platforms" is the same panel on the right', (tester) async {
    final bilibili = _FakeSite(SiteIds.bilibili, [
      [_room('bilibili', 1)],
    ]);
    final services = await _pump(tester, {SiteIds.bilibili: bilibili}, width: 1280, height: 800);
    await tester.tap(find.byKey(const ValueKey('popular-all-platforms')));
    await tester.pumpAndSettle();
    final panel = tester.getRect(find.byKey(const ValueKey('side-panel')));
    expect(panel.width, sidePanelWidth);
    expect(panel.right, 1280);
    expect(find.byKey(const ValueKey('popular-platform-picker')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('panel-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('side-panel')), findsNothing);
    await tester.runAsync(services.close);
  });

  for (final (size, columns) in [(const Size(393, 852), 2), (const Size(852, 393), 4), (const Size(1280, 800), 5)]) {
    testWidgets('U.4b c8, U.4a c15: ${size.width.toInt()}×${size.height.toInt()} shows $columns columns', (
      tester,
    ) async {
      final bilibili = _FakeSite(SiteIds.bilibili, [
        [for (var i = 0; i < 20; i++) _room('bilibili', i, heat: 100 - i)],
      ]);
      final services = await _pump(tester, {SiteIds.bilibili: bilibili}, width: size.width, height: size.height);
      final cards = find.byType(LiveRoomCard);
      final top = tester.getTopLeft(cards.first).dy;
      final firstRow = [
        for (final element in cards.evaluate())
          if (tester.getTopLeft(find.byWidget(element.widget)).dy == top) element,
      ];
      expect(firstRow, hasLength(columns));
      // The grid's padding is 6 on every side (U.4a c15).
      final grid = tester.getRect(find.byKey(const ValueKey('popular-grid')));
      expect(tester.getTopLeft(cards.first).dx - grid.left, 6);
      await tester.runAsync(services.close);
    });
  }

  group('A09.12 on a 393 phone', () {
    const ids = [
      SiteIds.bilibili,
      SiteIds.douyu,
      SiteIds.huya,
      SiteIds.douyin,
      SiteIds.kuaishou,
      SiteIds.cc,
      SiteIds.twitch,
      SiteIds.soop,
      SiteIds.yy,
      SiteIds.acfun,
      SiteIds.picarto,
      SiteIds.twitcasting,
      SiteIds.missevan,
      SiteIds.inke,
      SiteIds.kilakila,
      SiteIds.xiaohongshu,
      SiteIds.niconico,
      SiteIds.weibo,
      SiteIds.showroom,
      SiteIds.chzzk,
      SiteIds.kick,
      SiteIds.liveMe,
      SiteIds.tiktok,
      SiteIds.youtube,
    ];
    Map<String, LiveSite> sites() => {
      for (final id in ids)
        id: _FakeSite(id, [
          [for (var i = 0; i < 20; i++) _room(id, i, heat: 100 - i)],
        ]),
    };

    testWidgets('c1, c2: the tab cut by ⌄ fades; no jump buttons before the list moves', (tester) async {
      final services = await _pump(tester, sites(), width: 393, height: 852);
      final strip = find.byKey(const ValueKey('popular-platform-tabs'));
      expect(tester.state<ScrollableTabBarState>(strip).fadesEnd, isTrue);
      expect(tester.getRect(find.byKey(const ValueKey('tab-strip-fade'))).right, tester.getRect(strip).right);
      double scale(String key) => tester
          .widget<AnimatedScale>(
            find.ancestor(of: find.byKey(ValueKey(key)), matching: find.byType(AnimatedScale)).first,
          )
          .scale;
      expect(scale('jump-bottom'), 0);
      expect(scale('jump-top'), 0);
      await tester.drag(find.byType(LiveRoomCard).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(scale('jump-bottom'), 1);
      // At the strip's end nothing lies beyond: no fade.
      await tester.drag(find.text('斗鱼'), const Offset(-3000, 0));
      await tester.pumpAndSettle();
      expect(tester.state<ScrollableTabBarState>(strip).fadesEnd, isFalse);
      await tester.runAsync(services.close);
    });

    testWidgets('c3: "all platforms" opens at the design height, drags up to the full height; the hint is one line', (
      tester,
    ) async {
      final services = await _pump(tester, sites(), width: 393, height: 852);
      await tester.tap(find.byKey(const ValueKey('popular-all-platforms')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('panel-docked')), findsOneWidget);
      final sheet = find.byType(BottomSheet);
      // A09.2 v4-phone-picker: the top at about 29% (3.x-era 85% cap: 15%).
      expect(tester.getRect(sheet).top, closeTo(852 * (1 - platformPickerOpenHeight), 2));
      final hint = find.byKey(const ValueKey('popular-platform-hint'));
      expect(tester.getSize(hint).height, lessThan(13 * 2));
      await tester.drag(find.byKey(const ValueKey('popular-platform-douyu')), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.getRect(sheet).top, lessThan(852 * 0.1));
      await tester.tap(find.byKey(const ValueKey('popular-platform-douyu')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      await tester.runAsync(services.close);
    });
  });

  testWidgets('U.4b c4: an empty platform says what to do; the button refreshes', (tester) async {
    final bilibili = _FakeSite(SiteIds.bilibili, [const []]);
    final services = await _pump(tester, {SiteIds.bilibili: bilibili});
    expect(find.text('未发现直播'), findsOneWidget);
    expect(find.text('这个平台暂时没有直播。左右滑动或点上方的平台名切换平台，也可以下拉刷新'), findsOneWidget);
    expect(find.byIcon(AppIcons.emptyPopular), findsOneWidget);
    await tester.tap(find.text('刷新'));
    await tester.pumpAndSettle();
    expect(bilibili.requested.length, greaterThan(1));
    await tester.runAsync(services.close);
  });
}
