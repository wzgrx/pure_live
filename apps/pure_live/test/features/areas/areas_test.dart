import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/area_rooms/area_rooms_page.dart';
import 'package:pure_live/features/areas/area_artwork.dart';
import 'package:pure_live/features/areas/area_catalog.dart';
import 'package:pure_live/features/areas/favorite_areas_view.dart';
import 'package:pure_live/features/hot_areas/hot_areas_page.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';
import 'package:pure_live/shared/rooms/room_feed.dart';

import '../../support.dart';

LiveArea _area(String platform, String id, String name, {String type = 't', String typeName = '分类'}) =>
    LiveArea(platform: platform, areaId: id, areaName: name, areaType: type, typeName: typeName);

LiveRoom _room(String platform, String id, {LiveRestriction? restriction}) => LiveRoom(
  platform: platform,
  roomId: id,
  title: '标题$id',
  nick: '主播$id',
  liveStatus: LiveStatus.live,
  restriction: restriction,
);

/// A platform with fixed categories and numbered pages of rooms.
final class _FakeSite extends LiveSite {
  new(this.id, this.name, this.categories, {this.pages = const {}});

  @override
  final String id;

  @override
  final String name;

  final List<LiveCategory> categories;
  final Map<int, List<LiveRoom>> pages;
  final List<(int, int)> asked = [];

  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async => categories;

  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    asked.add((page, pageSize));
    return pages[page] ?? const [];
  }
}

/// A platform with native directory pages.
final class _DirectorySite extends LiveSite implements LiveSiteCursorDirectoryPager {
  new(this.cursors);

  final List<String?> cursors;

  @override
  String get id => 'acfun';

  @override
  String get name => 'AcFun';

  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) =>
      getDirectoryPageAtCursor(page: page, category: category, cancel: cancel);

  @override
  Future<LiveDirectoryPage> getDirectoryPageAtCursor({
    required int page,
    String? cursor,
    LiveArea? category,
    CancelToken? cancel,
  }) async =>
      LiveDirectoryPage(rooms: [_room('acfun', 'c$page')], page: page, hasMore: true, nextCursor: cursors[page - 1]);
}

Future<AppServices> _services(Map<String, LiveSite> sites) async {
  final base = await testServices();
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

Future<AppServices> _pumpApp(WidgetTester tester, Map<String, LiveSite> sites, {String preferred = 'huya'}) async {
  tester.view
    ..physicalSize = const Size(400, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(() async {
    final services = await _services(sites);
    await services.store.settings.set(Settings.savedMenuIds, ['areas']);
    await services.store.settings.set(Settings.hotAreasList, ['douyu', 'huya']);
    await services.store.settings.set(Settings.preferPlatform, preferred);
    // The test device is English; the texts below are the Chinese ones.
    await services.store.settings.set(Settings.language, '简体中文');
    await services.store.settings.set(Settings.showSplashPage, false);
    return services;
  }))!;
  final strings = (await tester.runAsync(loadStrings))!;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services)],
      child: PureLiveApp(strings: strings, bundle: FileAssetBundle()),
    ),
  );
  await _settle(tester);
  return services;
}

/// Lets the store's real I/O finish, then the frames.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('areas', () {
    test('the filter matches every word in the name, short name or category', () {
      final areas = [_area('huya', '1', '英雄联盟', typeName: '网游'), _area('huya', '2', '原神', typeName: '单机')];
      expect(filterAreas(areas, '英雄').single.areaId, '1');
      expect(filterAreas(areas, '单机 原').single.areaId, '2');
      expect(filterAreas(areas, '  '), hasLength(2));
      expect(filterAreas(areas, 'xyz'), isEmpty);
    });

    test('borrowed pictures: same name, alias, containing name; two-state icons are not lent', () async {
      final pictures = AreaPictures(null);
      await pictures.learn([
        LiveCategory(
          id: 'c',
          name: 'c',
          children: const [
            LiveArea(platform: 'douyu', areaId: '1', areaName: '英雄联盟', areaPic: 'https://a/lol.png'),
            LiveArea(platform: 'douyu', areaId: '2', areaName: '原神', areaPic: 'https://a/ys.png'),
            LiveArea(
              platform: 'missevan',
              areaId: '3',
              areaName: '声优',
              areaPic: 'https://static.maoercdn.com/live/catalog/icon/104.png',
            ),
          ],
        ),
      ]);
      expect(pictures.borrow('英雄联盟'), 'https://a/lol.png');
      expect(pictures.borrow('MOBA'), 'https://a/lol.png');
      expect(pictures.borrow('原神 4.0'), 'https://a/ys.png');
      expect(pictures.borrow('声优'), '');
      expect(pictures.pictureFor(const LiveArea(areaName: '原神', areaPic: 'own')), 'own');
      expect(
        categoryArtworkAlignment('https://static.maoercdn.com/live/catalog/icon/104-web.png'),
        Alignment.topCenter,
      );
      expect(categoryArtworkAlignment('https://static.maoercdn.com/live/catalog/icon/104.png'), Alignment.bottomCenter);
      expect(categoryArtworkAlignment('https://a/lol.png'), Alignment.center);
    });

    test('a refresh keeps the selected category by id and the old areas when it fails', () async {
      var fail = false;
      var categories = [
        LiveCategory(id: 'a', name: 'A', children: [_area('huya', '1', 'one')]),
        LiveCategory(id: 'b', name: 'B', children: [_area('huya', '2', 'two')]),
      ];
      final site = _CallbackSite(() => fail ? throw const RateLimited('huya') : categories);
      final catalog = AreaCatalog(site);
      await catalog.ensureLoaded();
      catalog.select(1);
      categories = [categories[1], categories[0]];
      await catalog.refresh();
      expect(catalog.categories[catalog.selected].id, 'b');
      fail = true;
      await catalog.refresh();
      expect(catalog.error, isA<RateLimited>());
      expect(catalog.categories, hasLength(2));
    });

    testWidgets('platform tabs from the list, preferred first; category tabs, the area menu, followed areas', (
      tester,
    ) async {
      final huya = _FakeSite('huya', '虎牙直播', [
        LiveCategory(id: 'net', name: '网游', children: [_area('huya', '1', '英雄联盟'), _area('huya', '2', '原神')]),
        LiveCategory(id: 'pc', name: '单机', children: [_area('huya', '3', '只狼')]),
      ]);
      final douyu = _FakeSite('douyu', '斗鱼直播', [
        LiveCategory(id: 'x', name: '娱乐', children: [_area('douyu', '9', '颜值')]),
      ]);
      final services = await _pumpApp(tester, {'huya': huya, 'douyu': douyu});
      final toasts = <String>[];
      AppNavigator.toast = toasts.add;

      expect(find.text('斗鱼'), findsOneWidget);
      expect(find.text('虎牙'), findsOneWidget);
      expect(find.text('英雄联盟'), findsOneWidget);
      // P02: pull to refresh with 3.x's bounce and classic header.
      expect(find.byType(RefreshIndicator), findsNothing);
      expect(
        find.ancestor(of: find.byKey(const ValueKey('area-grid')), matching: find.byType(AppRefreshView)),
        findsWidgets,
      );

      // U.4d c2: the categories in the secondary style; c3: the cards name only the area.
      // The shared second row of tabs (U.1c c12).
      expect(tester.widget(find.byKey(const ValueKey('area-category-tabs'))), isA<SecondaryTabBar>());
      final categories = tester.widget<TabBar>(
        find.descendant(of: find.byKey(const ValueKey('area-category-tabs')), matching: find.byType(TabBar)),
      );
      expect(categories.indicatorSize, TabBarIndicatorSize.tab);
      expect(categories.tabAlignment, TabAlignment.start);
      expect(find.byKey(const ValueKey('area-card-caption')), findsNothing);
      expect(find.byKey(const ValueKey('areas-filter-toggle')), findsNothing);

      await tester.tap(find.text('单机'));
      await _settle(tester);
      expect(find.text('只狼'), findsOneWidget);
      await tester.tap(find.text('网游'));
      await _settle(tester);

      // c6, X3 (as changed on 2026-10-01): a long press opens the room card's dialog: the
      // area, "platform · category", then "关注分区".
      await tester.longPress(find.text('原神'));
      await _settle(tester);
      final dialog = find.byKey(const ValueKey('area-menu'));
      expect(find.descendant(of: dialog, matching: find.text('原神')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('虎牙 · 分类')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('关注分区')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('area-menu-follow')));
      await _settle(tester);
      expect(await tester.runAsync(services.store.followAreas.all), hasLength(1));
      expect(find.byKey(const ValueKey('area-card-followed')), findsOneWidget);
      expect(find.text('关注分区'), findsOneWidget);
      expect(toasts.single, '已关注分区“原神”');

      // Followed: the menu offers "unfollow", which asks first (3.x's dialog).
      await tester.longPress(find.text('原神'));
      await _settle(tester);
      expect(find.descendant(of: dialog, matching: find.text('取消关注')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('area-menu-follow')));
      await _settle(tester);
      expect(find.text('确定要取消关注原神吗？'), findsOneWidget);
      // The button says what it does (U.1d D2).
      expect(find.widgetWithText(DialogActionButton, '取消关注'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await _settle(tester);
      expect(await tester.runAsync(services.store.followAreas.all), hasLength(1));

      await tester.tap(find.byKey(const ValueKey('areas-followed-button')));
      await _settle(tester);
      expect(find.byType(FavoriteAreasView), findsOneWidget);
      // U.4f c4: "all" and the platforms with followed areas only; c3: "platform · category" in "all".
      final tabs = find.byKey(const ValueKey('favorite-areas-platform-tabs'));
      expect(find.descendant(of: tabs, matching: find.text('全部')), findsOneWidget);
      expect(find.descendant(of: tabs, matching: find.text('虎牙')), findsOneWidget);
      expect(find.descendant(of: tabs, matching: find.text('斗鱼')), findsNothing);
      expect(find.text('原神'), findsOneWidget);
      expect(find.text('虎牙 · 分类'), findsOneWidget);
      await tester.runAsync(services.close);
    });

    test('the followed-areas tab survives a list change by id', () {
      expect(resolveFavoriteAreaSiteIndex(siteIds: ['all', 'huya'], selectedSiteId: 'huya', fallback: 0), 1);
      expect(resolveFavoriteAreaSiteIndex(siteIds: ['all'], selectedSiteId: 'huya', fallback: 3), 0);
    });
  });

  group('area rooms', () {
    test('pages are shown whole and end at a page with nothing new; unplayable rooms are hidden', () async {
      final pages = {
        1: [_room('douyu', '1'), _room('douyu', '2', restriction: LiveRestriction.paid), _room('douyu', '3')],
        2: [_room('douyu', '3'), _room('douyu', '4', restriction: LiveRestriction.needsLogin)],
        3: [_room('douyu', '4')],
      };
      final site = _FakeSite('douyu', '斗鱼', const [], pages: pages);
      var show = false;
      final feed = RoomFeed(
        platform: 'douyu',
        source: AreaRoomSource(areaRoomLoader(site, _area('douyu', 'a', '英雄联盟')), areaName: '英雄联盟'),
        // Signed in: the login room plays here, the paid one does not.
        visible: (room) => show || !cannotPlayHere(room, signedIn: true),
      );
      await feed.refresh(count: 1);
      expect(feed.rooms.map((room) => room.roomId), ['1', '3']);
      expect(feed.hiddenCount, 1);
      expect(feed.rooms.first.area, '英雄联盟');
      await feed.loadMore();
      expect(feed.rooms.map((room) => room.roomId), ['1', '3', '4']);
      expect(feed.hasMore, isTrue);
      await feed.loadMore();
      expect(feed.hasMore, isFalse);
      show = true;
      feed.visibilityChanged();
      expect(feed.rooms, hasLength(4));
      expect(site.asked.map((entry) => entry.$2).toSet(), {30});
      expect(cannotPlayHere(pages[2]![1], signedIn: false), isTrue);
    });

    test('SOOP and TwitCasting ask 60 a page; cursor directories stop when the cursor stalls', () async {
      final soop = _FakeSite(
        'soop',
        'SOOP',
        const [],
        pages: {
          1: [_room('soop', '1')],
        },
      );
      await areaRoomLoader(soop, _area('soop', 'a', 'a'))(1, null, CancelToken());
      expect(soop.asked.single, (1, 60));

      final load = areaRoomLoader(_DirectorySite(['n1', 'n1']), _area('acfun', 'a', 'a'));
      final first = await load(1, null, CancelToken());
      expect((first.hasMore, first.nextCursor), (true, 'n1'));
      final second = await load(2, 'n1', CancelToken());
      expect(second.hasMore, isFalse);
    });

    test('a failed refresh keeps the rooms; retry refreshes again', () async {
      var fail = false;
      final feed = RoomFeed(
        platform: 'douyu',
        source: AreaRoomSource(
          (page, cursor, cancel) async => fail
              ? throw const TransportFailure('douyu', TransportReason.timeout)
              : (rooms: [_room('douyu', '$page')], hasMore: true, nextCursor: null),
        ),
        visible: (room) => true,
      );
      await feed.refresh(count: 1);
      fail = true;
      await feed.refresh(count: 1);
      expect(feed.rooms, hasLength(1));
      expect(feed.errorOnRefresh, isTrue);
      expect(feed.error, isA<TransportFailure>());
      fail = false;
      await feed.retry(count: 1);
      expect(feed.errorOnRefresh, isFalse);
      expect(feed.error, isNull);
    });

    testWidgets('an area opens its rooms: hidden rooms can be shown, the area followed', (tester) async {
      final huya = _FakeSite(
        'huya',
        '虎牙直播',
        [
          LiveCategory(id: 'net', name: '网游', children: [_area('huya', '1', '英雄联盟')]),
        ],
        pages: {
          1: [_room('huya', '11'), _room('huya', '12', restriction: LiveRestriction.password)],
        },
      );
      final services = await _pumpApp(tester, {'huya': huya});
      final toasts = <String>[];
      AppNavigator.toast = toasts.add;

      await tester.tap(find.text('英雄联盟'));
      await _settle(tester);
      expect(find.byType(AreaRoomsView), findsOneWidget);
      expect(find.text('标题11'), findsOneWidget);
      expect(find.text('标题12'), findsNothing);
      expect(find.textContaining('已隐藏 1 个'), findsOneWidget);
      expect(find.text('没有更多数据了'), findsOneWidget);
      // U.4e c2: "platform · category" under the name.
      expect(find.text('虎牙 · 分类'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('area-rooms-show-hidden')));
      await _settle(tester);
      expect(find.text('标题12'), findsOneWidget);
      expect(find.text('密码房'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('follow-area-button')));
      await _settle(tester);
      expect((await tester.runAsync(services.store.followAreas.all))!.single.areaId, '1');
      expect(toasts.last, contains('英雄联盟'));

      // U.2b2 c1: a card opens its room with the area's rooms, in order.
      await tester.tap(find.text('标题12'));
      await _settle(tester);
      final args = tester.widget<LivePlayPage>(find.byType(LivePlayPage)).route.arguments! as LiveRoomArgs;
      expect(args.room.roomId, '12');
      expect(args.playlist.map((room) => room.roomId), ['11', '12']);
      AppNavigator.back();
      await _settle(tester);
      await tester.pump(AppNavigator.openGuard);
      await tester.runAsync(services.close);
    });
  });

  group('platform display', () {
    testWidgets('switches hide and show platforms, never the last; the preferred one follows', (tester) async {
      final services = await _pumpApp(tester, {
        'huya': _FakeSite('huya', '虎牙直播', const []),
        'douyu': _FakeSite('douyu', '斗鱼直播', const []),
      }, preferred: 'douyu');
      final toasts = <String>[];
      AppNavigator.toast = toasts.add;
      AppNavigator.toNamed<void>(RoutePath.kSettingsHotAreas).ignore();
      await _settle(tester);
      expect(find.text('显示（2）'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('platform-switch-douyu')));
      await _settle(tester);
      expect(services.store.settings.get(Settings.hotAreasList), ['huya']);
      expect(services.store.settings.get(Settings.preferPlatform), 'huya');
      expect(find.text('隐藏（1）'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('platform-switch-huya')));
      await _settle(tester);
      expect(services.store.settings.get(Settings.hotAreasList), ['huya']);
      expect(toasts.single, '请至少保留一个可见直播平台。');

      await tester.tap(find.byKey(const ValueKey('platform-switch-douyu')));
      await _settle(tester);
      expect(services.store.settings.get(Settings.hotAreasList), ['huya', 'douyu']);
      await tester.runAsync(services.close);
    });

    test('show, hide (never the last), move, and the preferred platform follows', () {
      expect(toggleHotArea(['a', 'b'], 'c', show: true), ['a', 'b', 'c']);
      expect(toggleHotArea(['a', 'b'], 'a', show: false), ['b']);
      expect(toggleHotArea(['a'], 'a', show: false), isNull);
      expect(reorderHotAreas(['a', 'b', 'c'], 0, 2), ['b', 'c', 'a']);
      expect(reorderHotAreas(['a', 'b', 'c'], 2, 0), ['c', 'a', 'b']);
      expect(preferredAfter(['b'], 'a'), 'b');
      expect(preferredAfter(['a', 'b'], 'b'), 'b');
    });
  });

  group('U.4d–U.4f layouts', () {
    testWidgets('Douyin has category tabs like the rest; one category shows no category tabs', (tester) async {
      final douyin = _FakeSite('douyin', '抖音', [
        LiveCategory(
          id: 'g',
          name: '游戏',
          children: [_area('douyin', '1', '王者荣耀', typeName: 'MOBA')],
        ),
        LiveCategory(
          id: 'f',
          name: '娱乐',
          children: [_area('douyin', '2', '颜值', typeName: '娱乐')],
        ),
      ]);
      final picarto = _FakeSite('picarto', 'Picarto', [
        LiveCategory(id: 'all', name: '公开直播', children: [_area('picarto', '3', 'Art')]),
      ]);
      final services = await (() async {
        tester.view
          ..physicalSize = const Size(393, 852)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final services = (await tester.runAsync(() async {
          final services = await _services({'douyin': douyin, 'picarto': picarto});
          await services.store.settings.set(Settings.savedMenuIds, ['areas']);
          await services.store.settings.set(Settings.hotAreasList, ['douyin', 'picarto']);
          await services.store.settings.set(Settings.preferPlatform, 'douyin');
          await services.store.settings.set(Settings.language, '简体中文');
          await services.store.settings.set(Settings.showSplashPage, false);
          return services;
        }))!;
        final strings = (await tester.runAsync(loadStrings))!;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appServicesProvider.overrideWithValue(services)],
            child: PureLiveApp(strings: strings, bundle: FileAssetBundle()),
          ),
        );
        await _settle(tester);
        return services;
      })();
      // Douyin: a tab per category, not 3.x's single grid (C-12 put ~156
      // game areas under "游戏"); the cards name only the area (U.4d c3).
      expect(find.byKey(const ValueKey('area-category-tabs')), findsOneWidget);
      expect(find.text('王者荣耀'), findsOneWidget);
      expect(find.text('MOBA'), findsNothing);
      await tester.tap(
        find.descendant(of: find.byKey(const ValueKey('area-category-tabs')), matching: find.text('娱乐')),
      );
      await _settle(tester);
      expect(find.text('颜值'), findsOneWidget);

      await tester.tap(find.text('Picarto'));
      await _settle(tester);
      expect(find.text('Art'), findsOneWidget);
      expect(find.byKey(const ValueKey('area-category-tabs')), findsNothing);
      expect(find.text('公开直播'), findsNothing);
      await tester.runAsync(services.close);
    });

    testWidgets('U.4f c5: with nothing followed the page says how and leads to the areas', (tester) async {
      final services = await _pumpApp(tester, {'huya': _FakeSite('huya', '虎牙直播', const [])});
      await tester.tap(find.byKey(const ValueKey('areas-followed-button')));
      await _settle(tester);
      expect(find.byType(FavoriteAreasView), findsOneWidget);
      expect(find.byKey(const ValueKey('favorite-areas-platform-tabs')), findsNothing);
      expect(find.text('未发现分区'), findsOneWidget);
      expect(find.text('在分区页长按分区卡片，或打开分区后点右上角的“关注”'), findsOneWidget);
      await tester.tap(find.text('去分区'));
      await _settle(tester);
      expect(find.byType(FavoriteAreasView), findsNothing);
      await tester.runAsync(services.close);
    });

    testWidgets('U.4f c7, c9, c10: 720 wide at most; a six-dot handle, none on hidden rows; two groups', (
      tester,
    ) async {
      final services = await _pumpApp(tester, {
        'huya': _FakeSite('huya', '虎牙直播', const []),
        'douyu': _FakeSite('douyu', '斗鱼直播', const []),
        'bilibili': _FakeSite('bilibili', '哔哩哔哩', const []),
      });
      tester.view.physicalSize = const Size(1280, 800);
      await tester.runAsync(() => services.store.settings.set(Settings.hotAreasList, ['huya', 'douyu']));
      AppNavigator.toNamed<void>(RoutePath.kSettingsHotAreas).ignore();
      await _settle(tester);
      expect(tester.getSize(find.byKey(const ValueKey('hot-areas-content'))).width, hotAreasMaxWidth);
      expect(find.text('显示（2）'), findsOneWidget);
      expect(find.text('隐藏（1）'), findsOneWidget);
      expect(find.byKey(const ValueKey('platform-drag-huya')), findsOneWidget);
      expect(find.byKey(const ValueKey('platform-drag-bilibili')), findsNothing);
      expect(find.byIcon(AppIcons.dragHandle), findsNWidgets(2));
      // The switches line up: the hidden row keeps the handle's place.
      final shown = tester.getCenter(find.byKey(const ValueKey('platform-switch-huya'))).dx;
      final hidden = tester.getCenter(find.byKey(const ValueKey('platform-switch-bilibili'))).dx;
      expect(hidden, closeTo(shown, 0.5));
      expect(find.textContaining('这里的顺序和开关用于热门、分区、关注和搜索的平台标签'), findsOneWidget);
      await tester.runAsync(services.close);
    });
  });
}

final class _CallbackSite extends LiveSite {
  new(this.answer);

  final List<LiveCategory> Function() answer;

  @override
  String get id => 'huya';

  @override
  String get name => '虎牙';

  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async => answer();
}
