import 'dart:async';

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
import 'package:pure_live/features/search/search_capability.dart';
import 'package:pure_live/features/search/search_history.dart';
import 'package:pure_live/features/search/search_model.dart';
import 'package:pure_live/features/search/search_ranking.dart';
import 'package:pure_live/features/search/search_scope.dart';
import 'package:pure_live/features/search/search_view.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';
import 'package:pure_live/shared/rooms/room_grid.dart';

import '../../support.dart';

/// A platform answering from fixed pages; links `https://<id>.test/<room>`
/// are its rooms.
final class FakeSite extends LiveSite with LiveSiteLinks {
  new(this.id, {this.pages = const {}, this.anchorItems = const [], this.fail = false, this.hang = false});

  @override
  final String id;

  @override
  String get name => id.toUpperCase();

  final Map<int, List<LiveRoom>> pages;
  final List<LiveAnchorItem> anchorItems;
  final bool fail;
  final bool hang;
  final List<(String, int)> calls = [];

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    calls.add((keyword, page));
    if (hang) return await Completer<List<LiveRoom>>().future;
    if (fail) throw StateError('down');
    return pages[page] ?? const [];
  }

  @override
  Future<List<LiveAnchorItem>> searchAnchors(String keyword, {int page = 1, int pageSize = 30}) async =>
      page == 1 ? anchorItems : const [];

  @override
  String? roomIdFromUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.host == '$id.test' && uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;
  }
}

LiveRoom _room(
  String platform,
  String id, {
  LiveStatus status = LiveStatus.live,
  String audience = '',
  String? title,
}) => LiveRoom(
  platform: platform,
  roomId: id,
  title: title ?? 'title $id',
  nick: 'nick $id',
  liveStatus: status,
  popularity: audience,
  audienceMetricType: AudienceMetricType.popularity,
);

SearchModel _model(List<LiveSite> sites, {Duration timeout = const Duration(seconds: 5)}) => SearchModel(
  sites: sites,
  timeout: timeout,
  audienceCompare: (a, b) =>
      LiveRoom.compareAudienceRanking(a, b, preferRealOnline: false, platformEnabled: (_) => false),
);

void main() {
  setUpAll(loadStrings);

  group('capabilities', () {
    test('every platform has an entry; YY and TwitCasting keywords find live rooms only (A-5)', () {
      for (final id in SiteIds.supported) {
        expect(SearchCapabilities.of(id).native, isTrue, reason: id);
      }
      expect(SearchCapabilities.of(SiteIds.yy).coverage, SearchCoverage.liveOnly);
      expect(SearchCapabilities.of(SiteIds.twitcasting).coverage, SearchCoverage.liveOnly);
      expect(SearchCapabilities.of(SiteIds.youtube).paged, isTrue);
      expect(SearchCapabilities.of('huajiao').native, isFalse);
      expect(
        [
          for (final id in SiteIds.supported)
            if (SearchCapabilities.of(id).anchors) id,
        ],
        [SiteIds.bilibili, SiteIds.douyu, SiteIds.huya, SiteIds.kuaishou, SiteIds.cc, SiteIds.yy, SiteIds.acfun],
      );
      for (final id in SiteIds.supported) {
        expect(webSearchUrl(id, 'a b') != null, SearchCapabilities.of(id).webSearch, reason: id);
      }
      expect(webSearchUrl(SiteIds.huya, 'a b').toString(), 'https://www.huya.com/search?hsk=a%20b');
      expect(searchCoverageText(SearchCapabilities.of(SiteIds.yy), 'YY'), 'YY：只能搜到正在直播的房间。');
    });

    test('ranking: live, then replays, then offline; hiding offline keeps replays', () {
      final rooms = [
        _room('huya', 'off', status: LiveStatus.offline),
        _room('huya', 'rep', status: LiveStatus.replay),
        _room('huya', 'small', audience: '10'),
        _room('bilibili', 'big', audience: '900'),
      ];
      int audience(LiveRoom a, LiveRoom b) =>
          LiveRoom.compareAudienceRanking(a, b, preferRealOnline: false, platformEnabled: (_) => false);
      List<String> order(SearchSortMode mode, {bool offline = true}) => [
        for (final room in SearchRanking.apply(
          rooms: rooms,
          mode: mode,
          includeOffline: offline,
          platformOrder: const ['huya', 'bilibili'],
          audienceCompare: audience,
        ))
          room.roomId,
      ];
      expect(order(SearchSortMode.smart), ['big', 'small', 'rep', 'off']);
      expect(order(SearchSortMode.platform), ['small', 'big', 'rep', 'off']);
      expect(order(SearchSortMode.smart, offline: false), ['big', 'small', 'rep']);
    });

    test('cards: audience in short form, restriction label, protocol-relative images', () {
      final data = const AudiencePolicy(preferRealOnline: false, realOnlinePlatforms: {}).cardOf(
        LiveRoom(
          platform: 'twitcasting',
          roomId: 'c',
          cover: '//img.test/a.jpg',
          liveStatus: LiveStatus.live,
          popularity: '123456',
          audienceMetricType: AudienceMetricType.popularity,
          restriction: LiveRestriction.private,
        ),
      );
      expect(data.anchorName, 'TwitCasting');
      expect(data.coverUrl, 'https://img.test/a.jpg');
      expect(data.audience, const RoomAudience(kind: RoomAudienceKind.popularity, value: '12.3万'));
      expect(data.restrictionLabel, '私密');
      expect(data.isLive, isTrue);
    });
  });

  group('model', () {
    test('all platforms: answers merged and ranked, failures named, paging until a page adds nothing', () async {
      final bili = FakeSite(
        'bilibili',
        pages: {
          1: [_room('bilibili', '1', audience: '5'), _room('bilibili', '2', status: LiveStatus.offline)],
          2: [_room('bilibili', '3', audience: '50')],
        },
      );
      final huya = FakeSite('huya', fail: true);
      final tiktok = FakeSite(
        'tiktok',
        pages: {
          1: [_room('tiktok', 'one')],
        },
      );
      final model = _model([bili, huya, tiktok]);
      addTearDown(model.dispose);

      await model.search('  game ');
      expect(model.keyword, 'game');
      expect([for (final room in model.results) room.roomId], ['1', 'one', '2']);
      expect(model.failed, ['huya']);
      expect(model.hasMore, isTrue);

      await model.loadMore();
      expect([for (final room in model.results) room.roomId], ['3', '1', 'one', '2']);
      // TikTok is a lookup without pages and Huya failed: only Bilibili was asked again.
      expect(bili.calls, [('game', 1), ('game', 2)]);
      expect(tiktok.calls, [('game', 1)]);
      expect(huya.calls, [('game', 1)]);
      await model.loadMore();
      await model.loadMore();
      expect(model.hasMore, isFalse);

      model.setIncludeOffline(value: false);
      expect([for (final room in model.results) room.roomId], ['3', '1', 'one']);
    });

    test('a platform past the deadline counts as failed; choosing a platform searches the draft there', () async {
      final slow = FakeSite('huya', hang: true);
      final bili = FakeSite(
        'bilibili',
        pages: {
          1: [_room('bilibili', '1')],
        },
      );
      final model = _model([bili, slow], timeout: const Duration(milliseconds: 50));
      addTearDown(model.dispose);
      await model.search('x');
      expect(model.failed, ['huya']);
      expect(model.results, hasLength(1));

      model.select(1, draft: 'y');
      await pumpEventQueue();
      expect(model.selectedSite, bili);
      expect(bili.calls.last, ('y', 1));

      // Clearing the draft clears the old results.
      model.select(2);
      expect(model.searched, isFalse);
      expect(model.results, isEmpty);
    });

    test('M13.16: "all" leaves out the excluded platforms and searches again; leaving out all keeps all', () async {
      final bili = FakeSite(
        'bilibili',
        pages: {
          1: [_room('bilibili', '1')],
        },
      );
      final twitch = FakeSite('twitch', fail: true);
      final model = _model([bili, twitch]);
      addTearDown(model.dispose);
      await model.search('x');
      expect(model.failed, ['twitch']);

      model.setExcluded({'twitch'}, draft: 'x');
      await pumpEventQueue();
      expect(model.allScope, [bili]);
      expect(model.failed, isEmpty);
      expect(twitch.calls, [('x', 1)], reason: 'not asked again');
      expect(bili.calls, [('x', 1), ('x', 1)]);

      model.setExcluded({'twitch', 'bilibili'});
      expect(model.allScope, [bili, twitch]);
      // Choosing a left-out platform on its own still searches it.
      model.setExcluded({'twitch'});
      await model.search('x');
      model.select(2, draft: 'y');
      await pumpEventQueue();
      expect(twitch.calls.last, ('y', 1));
    });

    test('streamers: only platforms with streamer search; a single one without it is named', () async {
      final bili = FakeSite(
        'bilibili',
        anchorItems: const [
          LiveAnchorItem(roomId: '7', avatar: '', userName: 'A', liveStatus: false),
          LiveAnchorItem(roomId: '8', avatar: '', userName: 'B', liveStatus: true),
        ],
      );
      final douyin = FakeSite('douyin');
      final model = _model([bili, douyin]);
      addTearDown(model.dispose);
      model.setMode(SearchMode.anchors);
      await model.search('a');
      expect([for (final result in model.anchors) result.item.userName], ['B', 'A']);
      expect(model.anchors.first.toRoom().isLiveNow, isTrue);

      model.select(2, draft: 'a');
      await pumpEventQueue();
      expect(model.unsupported, douyin);
      expect(model.resultCount, 0);
    });
  });

  test('history: newest first, case-insensitive duplicates, limit, kept in the store', () async {
    final store = await LiveStore.memory(cipher: FakeCipher());
    addTearDown(store.close);
    final history = SearchHistory(store.meta);
    for (var i = 0; i < 25; i++) {
      await history.add('w$i');
    }
    await history.add(' W3 ');
    expect(history.words.first, 'W3');
    expect(history.words, hasLength(SearchHistory.limit));
    expect(history.words.where((word) => word.toLowerCase() == 'w3'), hasLength(1));
    await history.remove('W3');

    final again = SearchHistory(store.meta);
    await again.load();
    expect(again.words, history.words);
    await again.clear();
    await history.load();
    expect(history.words, isEmpty);
  });

  test('U.5a c6: every platform has a short scope line without its name', () {
    for (final id in SiteIds.supported) {
      final text = searchCoverageShortText(SearchCapabilities.of(id));
      expect(text, isNot(contains('search_')), reason: id);
      expect(text, isNot(contains('：')), reason: id);
    }
    expect(searchCoverageShortText(SearchCapabilities.of(SiteIds.huya)), '只能搜到正在直播的房间');
    expect(searchCoverageShortText(SearchCapabilities.of(SiteIds.youtube)), '关键词只能搜到正在直播的频道');
  });

  group('page', () {
    late List<String> toasts;
    late List<LiveRoom> opened;
    late List<Map<String, String>> webSearches;
    late AppServices services;

    setUp(() {
      toasts = [];
      opened = [];
      webSearches = [];
      AppNavigator.toast = toasts.add;
    });

    Future<void> pump(
      WidgetTester tester,
      List<FakeSite> sites, {
      Size size = const Size(800, 1200),
      Future<bool> Function(Uri)? openExternal,
      bool webView2Missing = false,
      String? initialKeyword,
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      services = (await tester.runAsync(testServices))!;
      final registry = SiteRegistry({for (final site in sites) site.id: () => site});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appServicesProvider.overrideWithValue(services), sitesProvider.overrideWithValue(registry)],
          child: MaterialApp(
            theme: const LiveTheme(primaryColor: Colors.indigo).light,
            home: LiveUiScope(
              config: const LiveUiConfig(),
              child: SearchView(
                initialKeyword: initialKeyword,
                openRoom: opened.add,
                openExternal: openExternal,
                webView2Missing: webView2Missing,
                openWebSearch: (arguments) async => webSearches.add(arguments),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> submit(WidgetTester tester, String text) async {
      await tester.enterText(find.byKey(const ValueKey('search-field')), text);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('search-submit')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    FakeSite manyRooms(String id, int count, {LiveStatus status = LiveStatus.live}) => FakeSite(
      id,
      pages: {
        1: [for (var i = 0; i < count; i++) _room(id, '$i', status: status, title: '$id room $i')],
      },
    );

    testWidgets('search shows cards, the failure banner and a history chip; a card opens its room', (tester) async {
      await pump(tester, [
        FakeSite(
          'bilibili',
          pages: {
            1: [_room('bilibili', '42', title: 'Hello')],
          },
        ),
        FakeSite('huya', fail: true),
      ]);
      expect(find.text('搜索全平台直播'), findsOneWidget);

      await submit(tester, 'hello');
      expect(find.text('Hello'), findsOneWidget);
      expect(find.byKey(const ValueKey('search-failure-banner')), findsOneWidget);
      // A quiet count; the names on request (M13.16).
      expect(find.text('有 1 个平台连接失败'), findsOneWidget);
      expect(find.byKey(const ValueKey('search-failure-proxy')), findsNothing, reason: 'Huya is no overseas platform');
      await tester.tap(find.byKey(const ValueKey('search-failure-details')));
      await tester.pump();
      expect(
        find.descendant(of: find.byKey(const ValueKey('search-failure-names')), matching: find.text('虎牙')),
        findsOneWidget,
      );

      await tester.tap(find.text('Hello'));
      expect(opened.single.roomId, '42');

      // Long press: the room menu follows the room.
      await tester.longPress(find.text('Hello'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('room-menu')), findsOneWidget);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('room-menu-follow')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(() => services.store.follows.contains(_room('bilibili', '42'))), isTrue);
      expect(toasts.where((text) => text.startsWith('已关注')), isNotEmpty);
      expect(find.byKey(const ValueKey('room-menu')), findsNothing);

      // The word is in the history once the platform is chosen afresh.
      await tester.tap(find.byKey(const ValueKey('search-platform-1')));
      await tester.enterText(find.byKey(const ValueKey('search-field')), '');
      await tester.tap(find.byKey(const ValueKey('search-platform-0')));
      await tester.pump();
      expect(find.byKey(const ValueKey('search-history')), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'hello'), findsOneWidget);
    });

    testWidgets('U.2b2 c1: without its own opener a card opens the room with the results in their order', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(800, 1200)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      services = (await tester.runAsync(testServices))!;
      final opened = <Object?>[];
      final router = AppNavigator.router = GoRouter(
        initialLocation: RoutePath.kInitial,
        routes: [
          GoRoute(
            path: RoutePath.kInitial,
            builder: (context, state) => const LiveUiScope(config: LiveUiConfig(), child: SearchView()),
          ),
          GoRoute(
            path: RoutePath.kLivePlay,
            builder: (context, state) {
              opened.add(state.extra);
              return const SizedBox.shrink();
            },
          ),
        ],
      );
      addTearDown(() => AppNavigator.router = null);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appServicesProvider.overrideWithValue(services),
            sitesProvider.overrideWithValue(
              SiteRegistry({
                'bilibili': () => FakeSite(
                  'bilibili',
                  pages: {
                    1: [_room('bilibili', '1', title: 'One'), _room('bilibili', '2', title: 'Two')],
                  },
                ),
              }),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await submit(tester, 'x');
      final shown = tester.widgetList<RoomGridCard>(find.byType(RoomGridCard)).map((card) => card.room.roomId);
      expect(shown, hasLength(2));
      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();
      final args = opened.last! as LiveRoomArgs;
      expect(args.room.roomId, '2');
      expect(args.playlist.map((room) => room.roomId), shown);
      await tester.pump(AppNavigator.openGuard);
      await tester.runAsync(services.close);
    });

    testWidgets('M13.16: overseas failures suggest a proxy; the scope panel leaves them out and is remembered', (
      tester,
    ) async {
      final twitch = FakeSite('twitch', fail: true);
      final youtube = FakeSite('youtube', fail: true);
      final sites = [
        FakeSite(
          'bilibili',
          pages: {
            1: [_room('bilibili', '42', title: 'Hello')],
          },
        ),
        twitch,
        youtube,
      ];
      await pump(tester, sites);
      await submit(tester, 'hello');
      expect(find.text('有 2 个平台连接失败，海外平台可能需要在设置里配置代理'), findsOneWidget);
      expect(find.byKey(const ValueKey('search-failure-proxy')), findsOneWidget);
      expect(find.text('同时搜索 3 个平台，各平台能搜到的范围不同，点此查看。'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('search-failure-scope')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-scope-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('side-panel')), findsOneWidget, reason: 'on the right of a wide page');
      await tester.tap(find.byKey(const ValueKey('search-scope-domestic')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('panel-close')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-failure-banner')), findsNothing);
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('同时搜索 1 个平台（共 3 个，已排除 2 个），点此查看或修改。'), findsOneWidget);
      expect((twitch.calls.length, youtube.calls.length), (1, 1), reason: 'not searched again');
      expect(await tester.runAsync(() => SearchScopeStore(services.store.meta).load()), {'twitch', 'youtube'});

      // The next search page starts with the remembered scope.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appServicesProvider.overrideWithValue(services),
            sitesProvider.overrideWithValue(SiteRegistry({for (final site in sites) site.id: () => site})),
          ],
          child: MaterialApp(
            theme: const LiveTheme(primaryColor: Colors.indigo).light,
            home: const LiveUiScope(
              config: LiveUiConfig(),
              child: SearchView(initialKeyword: 'again'),
            ),
          ),
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.textContaining('已排除 2 个'), findsOneWidget);
      expect(twitch.calls, [('hello', 1)], reason: 'the first search of the new page leaves it out');
    });

    testWidgets('Appendix A 14: a right click on a result opens the card dialog', (tester) async {
      await pump(tester, [manyRooms('bilibili', 1)]);
      await submit(tester, 'a');
      await tester.tap(find.byType(RoomGridCard), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('room-menu')), findsOneWidget);
      expect(opened, isEmpty);
    });

    testWidgets('a pasted room link opens the room without a search', (tester) async {
      final bili = FakeSite('bilibili');
      await pump(tester, [bili]);
      await tester.enterText(find.byKey(const ValueKey('search-field')), '看这个 https://bilibili.test/99 。');
      await tester.pump();
      expect(find.byKey(const ValueKey('search-link-banner')), findsOneWidget);
      expect(find.text('识别到直播链接'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('search-link-open')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(opened.single.platform, 'bilibili');
      expect(opened.single.roomId, '99');
      expect(bili.calls, isEmpty);
    });

    testWidgets('streamer mode lists streamers; a platform without it says so', (tester) async {
      await pump(tester, [
        FakeSite(
          'huya',
          anchorItems: const [LiveAnchorItem(roomId: '5', avatar: '', userName: 'Anchor', liveStatus: true)],
        ),
        FakeSite('douyin'),
      ]);
      await tester.tap(find.text('主播'));
      await tester.pump();
      expect(find.byKey(const ValueKey('search-sort-selector')), findsNothing, reason: 'streamers have no order');
      await submit(tester, 'a');
      expect(find.text('Anchor'), findsOneWidget);
      expect(find.text('虎牙 · 房间号 5'), findsOneWidget);
      await tester.tap(find.text('Anchor'));
      expect(opened.single.roomId, '5');

      await tester.tap(find.byKey(const ValueKey('search-platform-2')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.byKey(const ValueKey('search-unsupported')), findsOneWidget);
    });

    testWidgets('U.5a c2: the field keeps its round corners when focused; clear and paste swap; Enter searches', (
      tester,
    ) async {
      await pump(tester, [FakeSite('huya')], size: const Size(393, 852));
      final field = tester.widget<TextField>(find.byKey(const ValueKey('search-field')));
      expect(field.textInputAction, TextInputAction.search);
      expect(field.decoration?.hintText, '搜索直播间、主播或粘贴链接');
      final focused = field.decoration!.focusedBorder! as OutlineInputBorder;
      final enabled = field.decoration!.enabledBorder! as OutlineInputBorder;
      expect(focused.borderRadius, BorderRadius.circular(24));
      expect(enabled.borderRadius, BorderRadius.circular(24));
      expect(focused.borderSide.width, 2);

      // Back, the field, paste, search; with words: clear instead of paste.
      final back = tester.getCenter(find.byKey(const ValueKey('search-back')));
      final paste = tester.getCenter(find.byKey(const ValueKey('search-paste')));
      final submitButton = tester.getCenter(find.byKey(const ValueKey('search-submit')));
      expect(back.dx, lessThan(paste.dx));
      expect(paste.dx, lessThan(submitButton.dx));
      expect(
        find.descendant(of: find.byKey(const ValueKey('search-back')), matching: find.byIcon(AppIcons.back)),
        findsOneWidget,
      );
      expect(find.byIcon(AppIcons.paste), findsOneWidget);
      expect(find.byIcon(AppIcons.submitSearch), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('search-field')), 'lol');
      await tester.pump();
      expect(find.byKey(const ValueKey('search-paste')), findsNothing);
      expect(tester.getCenter(find.byKey(const ValueKey('search-clear'))).dx, closeTo(paste.dx, 1));
      await tester.tap(find.byKey(const ValueKey('search-clear')));
      await tester.pump();
      expect(find.text('lol'), findsNothing);
    });

    testWidgets('U.5a portrait: field, platforms, filters (wrapping), then the scope line under them', (tester) async {
      await pump(tester, [FakeSite('bilibili'), FakeSite('huya')], size: const Size(393, 852));
      final field = tester.getRect(find.byKey(const ValueKey('search-field')));
      final strip = tester.getRect(find.byKey(const ValueKey('search-platform-strip')));
      final options = tester.getRect(find.byKey(const ValueKey('search-options')));
      expect(strip.top, greaterThanOrEqualTo(field.bottom));
      expect(options.top, greaterThanOrEqualTo(strip.bottom - 1));
      expect(field.width, greaterThan(393 - 40));
      // P02 (research S10): the platform strip stretches at its ends like
      // the other strips.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('search-platform-strip')),
          matching: find.byType(StretchingOverscrollIndicator),
        ),
        findsOneWidget,
      );

      // Rooms / streamers, offline, order — in 3.x's order, nothing off the edge.
      final mode = tester.getRect(find.byKey(const ValueKey('search-mode')));
      final offline = tester.getRect(find.byKey(const ValueKey('search-include-offline')));
      final sort = tester.getRect(find.byKey(const ValueKey('search-sort-selector')));
      expect(mode.left, lessThan(offline.left));
      expect(offline.left, lessThan(sort.left));
      expect(sort.right, lessThanOrEqualTo(393));
      final coverage = tester.getRect(find.byKey(const ValueKey('search-coverage')));
      expect(coverage.top, greaterThanOrEqualTo(sort.bottom - 8));
      expect(find.text('同时搜索 2 个平台，各平台能搜到的范围不同，点此查看。'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('search-coverage-text'))).maxLines, 2);

      // A09.12 c4 (A09.7 v4-phone): "全部" shows its grid when chosen, no
      // tick; a chosen platform still swaps its logo for the tick.
      final all = find.byKey(const ValueKey('search-platform-0'));
      expect(find.descendant(of: all, matching: find.byIcon(AppIcons.allPlatforms)), findsOneWidget);
      expect(find.descendant(of: all, matching: find.byIcon(Icons.check_rounded)), findsNothing);

      // One platform with a web search: "继续网页搜索" wraps onto the next line (c3).
      await tester.tap(find.byKey(const ValueKey('search-platform-1')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: all, matching: find.byIcon(AppIcons.allPlatforms)), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('search-platform-1')),
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      final web = tester.getRect(find.byKey(const ValueKey('search-web')));
      expect(web.right, lessThanOrEqualTo(393));
      expect(web.top, greaterThan(sort.top));
      expect(tester.getRect(find.byKey(const ValueKey('search-coverage'))).top, greaterThanOrEqualTo(web.bottom - 8));
      expect(find.text('哔哩哔哩：能搜到直播中和部分未开播的房间，可用“包含未开播”筛选。'), findsOneWidget);
    });

    for (final (size, fieldWidth) in [(const Size(852, 393), 323.76), (const Size(1280, 800), 480.0)]) {
      testWidgets('U.5a c12, c13: ${size.width.toInt()} wide puts field and platforms on one line', (tester) async {
        await pump(tester, [manyRooms('bilibili', 20), manyRooms('huya', 20)], size: size);
        final field = tester.getRect(find.byKey(const ValueKey('search-field')));
        final strip = tester.getRect(find.byKey(const ValueKey('search-platform-strip')));
        expect(field.width, closeTo(fieldWidth, 0.5));
        expect(strip.left, greaterThan(field.right));
        expect(strip.center.dy, closeTo(field.center.dy, 4));
        // The scope line beside the filters, in one line.
        final sort = tester.getRect(find.byKey(const ValueKey('search-sort-selector')));
        final coverage = tester.getRect(find.byKey(const ValueKey('search-coverage')));
        expect(coverage.left, greaterThan(sort.right));
        expect(coverage.center.dy, closeTo(sort.center.dy, 4));
        expect(tester.widget<Text>(find.byKey(const ValueKey('search-coverage-text'))).maxLines, 1);
        // Hovering the order button names it.
        expect(tester.widget<ActionChip>(find.byKey(const ValueKey('search-sort-selector'))).tooltip, '排序');
      });
    }

    for (final (size, columns) in [(const Size(393, 852), 2), (const Size(852, 393), 4), (const Size(1280, 800), 6)]) {
      testWidgets('U.5a c13: ${size.width.toInt()} wide has $columns columns; "all" cards name their platform', (
        tester,
      ) async {
        await pump(tester, [manyRooms('bilibili', 10), manyRooms('huya', 10)], size: size);
        await submit(tester, 'a');
        final cards = find.byType(RoomGridCard);
        final tops = [for (final element in cards.evaluate()) tester.getTopLeft(find.byWidget(element.widget)).dy];
        expect(tops.where((top) => top == tops.first).length, columns);
        expect(tester.widget<RoomGridCard>(cards.first).mixedPlatforms, isTrue);

        await tester.tap(find.byKey(const ValueKey('search-platform-1')));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        expect(tester.widget<RoomGridCard>(find.byType(RoomGridCard).first).mixedPlatforms, isFalse);
      });
    }

    testWidgets('U.5a X1: scrolling down slides the platforms and filters away, scrolling up brings them back', (
      tester,
    ) async {
      await pump(tester, [manyRooms('bilibili', 30)], size: const Size(393, 852));
      await submit(tester, 'a');
      final field = tester.getRect(find.byKey(const ValueKey('search-field')));
      await tester.drag(find.byKey(const ValueKey('search-content')), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const ValueKey('search-field'))), field, reason: 'the field stays');
      expect(find.byKey(const ValueKey('search-platform-0')).hitTestable(), findsNothing);
      expect(find.byKey(const ValueKey('search-options')).hitTestable(), findsNothing);
      await tester.drag(find.byKey(const ValueKey('search-content')), const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-options')).hitTestable(), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('search-platform-strip'))).top,
        greaterThanOrEqualTo(field.bottom),
      );
    });

    testWidgets('U.5a c4: "综合 ⌄" opens the four orders, the current one in the primary colour with a tick', (
      tester,
    ) async {
      await pump(tester, [FakeSite('huya')], size: const Size(393, 852));
      expect(
        find.descendant(of: find.byKey(const ValueKey('search-sort-selector')), matching: find.text('综合')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('search-sort-selector')),
          matching: find.byIcon(AppIcons.dropDown),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('search-sort-selector')));
      await tester.pumpAndSettle();
      final rows = [
        for (final mode in SearchSortMode.values) tester.getRect(find.byKey(ValueKey('search-sort-${mode.name}'))),
      ];
      for (var i = 1; i < rows.length; i++) {
        expect(rows[i].top, greaterThanOrEqualTo(rows[i - 1].bottom - 0.5));
      }
      expect(find.text('综合：直播→观众→粉丝'), findsOneWidget);
      final current = find.byKey(const ValueKey('search-sort-smart'));
      expect(find.descendant(of: current, matching: find.byIcon(AppIcons.selected)), findsOneWidget);
      final scheme = Theme.of(tester.element(current)).colorScheme;
      expect(tester.widget<Text>(find.text('综合：直播→观众→粉丝')).style?.color, scheme.primary);
      // One tick in the menu (the chosen platform chip has its own, U.1c c13).
      for (final mode in SearchSortMode.values) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('search-sort-${mode.name}')),
            matching: find.byIcon(AppIcons.selected),
          ),
          mode == SearchSortMode.smart ? findsOneWidget : findsNothing,
          reason: mode.name,
        );
      }
      await tester.tap(find.text('观众优先'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byKey(const ValueKey('search-sort-selector')), matching: find.text('观众优先')),
        findsOneWidget,
      );
    });

    testWidgets('U.5a c6: the scope panel rises from the bottom on phones; the last platform stays chosen', (
      tester,
    ) async {
      await pump(tester, [FakeSite('bilibili'), FakeSite('twitch')], size: const Size(393, 852));
      await tester.tap(find.byKey(const ValueKey('search-coverage')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-scope-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('side-panel')), findsNothing);
      expect(find.text('“全部”搜索哪些平台'), findsOneWidget);
      // Domestic first, then overseas, each with how many are chosen.
      expect(tester.getTopLeft(find.text('国内平台')).dy, lessThan(tester.getTopLeft(find.text('海外平台')).dy));
      expect(find.text('已选 1 / 1'), findsNWidgets(2));
      // Bilibili: streamers and web search; Twitch: web search.
      final bili = find.byKey(const ValueKey('search-scope-bilibili'));
      expect(find.descendant(of: bili, matching: find.text('主播')), findsOneWidget);
      expect(find.descendant(of: bili, matching: find.text('网页')), findsOneWidget);
      expect(find.descendant(of: bili, matching: find.text('能搜到直播中和部分未开播的房间')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('search-scope-twitch')));
      await tester.pump();
      expect(find.text('已选 0 / 1'), findsOneWidget);
      // Bilibili is the last one: it cannot be left out.
      await tester.tap(find.byKey(const ValueKey('search-scope-bilibili')));
      await tester.pump();
      expect(tester.widget<Checkbox>(find.descendant(of: bili, matching: find.byType(Checkbox))).value, isTrue);
      await tester.tap(find.byKey(const ValueKey('search-scope-all')));
      await tester.pump();
      expect(find.text('已选 1 / 1'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('search-scope-domestic')));
      await tester.pump();
      await tester.tapAt(const Offset(200, 40));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-scope-panel')), findsNothing);
      expect(find.textContaining('已排除 1 个'), findsOneWidget);
    });

    testWidgets('U.5a c8, c10: skeleton cards while waiting; each empty state says why, with its own button', (
      tester,
    ) async {
      final slow = FakeSite('huya', hang: true);
      await pump(tester, [slow, FakeSite('douyu'), manyRooms('bilibili', 2, status: LiveStatus.offline)]);
      await tester.tap(find.byKey(const ValueKey('search-platform-3')));
      await submit(tester, 'x');
      expect(find.byKey(const ValueKey('search-skeleton')), findsOneWidget);
      expect(find.text('还有 1 个平台在搜索…'), findsOneWidget);

      // Nothing on one platform: why, and its web search.
      await tester.tap(find.byKey(const ValueKey('search-platform-2')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.byKey(const ValueKey('search-empty')), findsOneWidget);
      expect(find.text(withoutOrphan('换个关键词试试，或者切换到其他平台。')), findsOneWidget);
      final button = find.byKey(const ValueKey('status-button'));
      expect(find.descendant(of: button, matching: find.byIcon(AppIcons.webSearch)), findsOneWidget);
      expect(find.descendant(of: button, matching: find.text('继续网页搜索')), findsOneWidget);

      // Only offline rooms with "include offline" off: show them.
      await tester.tap(find.byKey(const ValueKey('search-platform-1')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('search-include-offline')));
      await tester.pump();
      expect(find.byKey(const ValueKey('search-all-offline')), findsOneWidget);
      expect(find.text(withoutOrphan('找到的都是未开播的房间，已被“包含未开播”筛选隐藏。')), findsOneWidget);
      expect(find.descendant(of: button, matching: find.byIcon(AppIcons.showHidden)), findsOneWidget);
      await tester.tap(button);
      await tester.pump();
      expect(find.byType(RoomGridCard), findsNWidgets(2));
      // The end of the list: "加载更多结果", then "已加载全部结果".
      await tester.tap(find.byKey(const ValueKey('search-load-more')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.byKey(const ValueKey('search-all-loaded')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('web search opens the web search route with the platform and the words', (tester) async {
      await pump(tester, [FakeSite('huya')]);
      await tester.tap(find.byKey(const ValueKey('search-platform-1')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('search-field')), 'lol');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('search-web')));
      await tester.pump();
      expect(webSearches.single, {'url': 'https://www.huya.com/search?hsk=lol', 'platform': 'huya', 'keyword': 'lol'});
    });

    testWidgets('U.5a c15: without WebView2 the web search asks first; a tap outside closes the question', (
      tester,
    ) async {
      final uris = <Uri>[];
      await pump(
        tester,
        [FakeSite('huya')],
        webView2Missing: true,
        openExternal: (uri) async {
          uris.add(uri);
          return true;
        },
      );
      expect(find.byKey(const ValueKey('webview2-dialog')), findsNothing, reason: 'not on opening the page');
      await tester.tap(find.byKey(const ValueKey('search-platform-1')));
      await tester.enterText(find.byKey(const ValueKey('search-field')), 'lol');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('search-web')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('webview2-dialog')), findsOneWidget);
      expect(find.byIcon(AppIcons.componentMissing), findsOneWidget);
      final cancel = tester.getCenter(find.text('取消'));
      final download = tester.getCenter(find.byKey(const ValueKey('webview2-download')));
      final browser = tester.getCenter(find.byKey(const ValueKey('webview2-browser')));
      expect(cancel.dx, lessThan(download.dx));
      expect(download.dx, lessThan(browser.dx));
      expect(find.widgetWithText(DialogActionButton, '用系统浏览器打开'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('webview2-dialog')), findsNothing);
      expect(webSearches, isEmpty);

      await tester.tap(find.byKey(const ValueKey('search-web')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('webview2-download')));
      await tester.pumpAndSettle();
      expect(uris.single.host, 'developer.microsoft.com');
      expect(webSearches, isEmpty);

      await tester.tap(find.byKey(const ValueKey('search-web')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('webview2-browser')));
      await tester.pumpAndSettle();
      expect(webSearches.single['platform'], 'huya');
    });

    testWidgets('U.5a c16: a mouse wheel scrolls the platform row sideways', (tester) async {
      await pump(tester, [for (final id in SiteIds.supported.take(20)) FakeSite(id)], size: const Size(393, 852));
      final strip = find.byKey(const ValueKey('search-platform-strip'));
      final list = tester.widget<ListView>(strip);
      expect(list.controller!.offset, 0);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(tester.getCenter(strip)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
      await tester.pump();
      expect(list.controller!.offset, 120);
    });

    testWidgets('Esc leaves the search page like Back', (tester) async {
      services = (await tester.runAsync(testServices))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appServicesProvider.overrideWithValue(services),
            sitesProvider.overrideWithValue(SiteRegistry({'huya': () => FakeSite('huya')})),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LiveUiScope(config: LiveUiConfig(), child: SearchView()),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchView), findsOneWidget);
      // The keyboard comes up with the page (3.x).
      final field = tester.widget<TextField>(find.byKey(const ValueKey('search-field')));
      expect(field.focusNode!.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SearchView), findsNothing);

      // After a search the field lets go of the focus; Esc still leaves.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('search-field')), 'a');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const ValueKey('search-field'))).focusNode!.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SearchView), findsNothing);
    });
  });
}
