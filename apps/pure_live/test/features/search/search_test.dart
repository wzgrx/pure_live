import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:pure_live/features/search/web_search_view.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/room_cards.dart';

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

  group('page', () {
    late List<String> toasts;
    late List<LiveRoom> opened;
    late AppServices services;

    setUp(() {
      toasts = [];
      opened = [];
      AppNavigator.toast = toasts.add;
    });

    Future<void> pump(WidgetTester tester, List<FakeSite> sites, {Future<bool> Function(Uri)? openExternal}) async {
      tester.view
        ..physicalSize = const Size(800, 1200)
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
              child: SearchView(openRoom: opened.add, openExternal: openExternal),
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

    testWidgets('M13.16: overseas failures suggest a proxy; the scope leaves them out and is remembered', (
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
      expect(find.text('搜索范围 3/3'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('search-failure-scope')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('search-scope-domestic')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('search-scope-save')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-failure-banner')), findsNothing);
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('搜索范围 1/3'), findsOneWidget);
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
      expect(find.text('搜索范围 1/3'), findsOneWidget);
      expect(twitch.calls, [('hello', 1)], reason: 'the first search of the new page leaves it out');
    });

    testWidgets('a pasted room link opens the room without a search', (tester) async {
      final bili = FakeSite('bilibili');
      await pump(tester, [bili]);
      await tester.enterText(find.byKey(const ValueKey('search-field')), '看这个 https://bilibili.test/99 。');
      await tester.pump();
      expect(find.byKey(const ValueKey('search-link-banner')), findsOneWidget);
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
      await submit(tester, 'a');
      expect(find.text('Anchor'), findsOneWidget);
      await tester.tap(find.text('Anchor'));
      expect(opened.single.roomId, '5');

      await tester.tap(find.byKey(const ValueKey('search-platform-2')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.byKey(const ValueKey('search-unsupported')), findsOneWidget);
    });

    testWidgets('web search opens the browser for the chosen platform', (tester) async {
      final uris = <Uri>[];
      await pump(
        tester,
        [FakeSite('huya')],
        openExternal: (uri) async {
          uris.add(uri);
          return true;
        },
      );
      await tester.tap(find.byKey(const ValueKey('search-platform-1')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('search-field')), 'lol');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('search-web')));
      await tester.pump();
      expect(uris.single.toString(), 'https://www.huya.com/search?hsk=lol');
      expect(toasts.last, contains('浏览器'));
    });
  });

  testWidgets("web search route: 3.x's arguments, invalid ones refused", (tester) async {
    final uris = <Uri>[];
    Future<void> show(Object? arguments) => tester.pumpWidget(
      MaterialApp(
        home: WebSearchView(
          key: UniqueKey(),
          arguments: arguments,
          openExternal: (uri) async {
            uris.add(uri);
            return true;
          },
        ),
      ),
    );
    await show({'url': 'ftp://x.test/', 'platform': 'huya'});
    expect(find.byKey(const ValueKey('web-search-invalid')), findsOneWidget);
    expect(WebSearchRequest.parse({'url': 'https://u:p@x.test/', 'platform': 'huya'}), isNull);

    await show({'url': 'https://www.huya.com/search?hsk=a', 'platform': 'HUYA'});
    await tester.tap(find.byKey(const ValueKey('web-search-open-external')));
    await tester.pump();
    expect(uris.single.host, 'www.huya.com');
  });
}
