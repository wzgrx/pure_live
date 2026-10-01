import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/pages/area_rooms/area_rooms_page.dart';
import 'package:pure_live/pages/areas/area_artwork.dart';
import 'package:pure_live/pages/areas/area_catalog.dart';
import 'package:pure_live/pages/areas/favorite_areas_view.dart';
import 'package:pure_live/pages/hot_areas/hot_areas_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';
import 'package:pure_live/shared/rooms/room_feed.dart';

import 'support.dart';

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

    testWidgets('platform tabs from the list, preferred first; categories, filter, follow, followed areas', (
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

      await tester.tap(find.text('单机'));
      await _settle(tester);
      expect(find.text('只狼'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('areas-filter-toggle')));
      await _settle(tester);
      await tester.enterText(find.byKey(const ValueKey('areas-filter-field')), '原');
      await _settle(tester);
      expect(find.text('原神'), findsOneWidget);
      expect(find.text('只狼'), findsNothing);

      // A long press follows; the card gets a heart and the button a count.
      await tester.longPress(find.text('原神'));
      await _settle(tester);
      expect(await tester.runAsync(services.store.followAreas.all), hasLength(1));
      expect(find.byKey(const ValueKey('area-card-followed')), findsOneWidget);
      expect(find.text('关注分区 · 1'), findsOneWidget);
      expect(toasts.single, '已关注分区“原神”');

      await tester.tap(find.byKey(const ValueKey('areas-followed-button')));
      await _settle(tester);
      expect(find.byType(FavoriteAreasView), findsOneWidget);
      expect(find.text('全部 1'), findsOneWidget);
      expect(find.text('原神'), findsOneWidget);
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
      expect(find.text('已经到底了'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('area-rooms-show-hidden')));
      await _settle(tester);
      expect(find.text('标题12'), findsOneWidget);
      expect(find.text('密码房'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('follow-area-button')));
      await _settle(tester);
      expect((await tester.runAsync(services.store.followAreas.all))!.single.areaId, '1');
      expect(toasts.last, contains('英雄联盟'));
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
      expect(find.text('首页显示的平台（2 / 2）'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('platform-switch-douyu')));
      await _settle(tester);
      expect(services.store.settings.get(Settings.hotAreasList), ['huya']);
      expect(services.store.settings.get(Settings.preferPlatform), 'huya');
      expect(find.text('未显示的平台'), findsOneWidget);

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
