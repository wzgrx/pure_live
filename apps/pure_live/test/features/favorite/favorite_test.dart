import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/favorite/favorite_controller.dart';
import 'package:pure_live/features/favorite/favorite_page.dart';
import 'package:pure_live/features/favorite/favorite_rules.dart';
import 'package:pure_live/features/favorite/follow_refresher.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_grid.dart';

import '../../support.dart';

/// A platform that answers from [details] (a missing room fails) and
/// counts its requests.
final class FakeSite extends LiveSite {
  new(this.id, this.details, {this.delay});

  @override
  final String id;

  @override
  String get name => id;

  final Map<String, LiveRoom> details;
  final Duration? delay;
  final List<String> requested = [];
  int _active = 0;
  int maxActive = 0;

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    requested.add(roomId);
    _active++;
    if (_active > maxActive) maxActive = _active;
    try {
      if (delay case final delay?) await Future<void>.delayed(delay);
      return details[roomId] ?? (throw StateError('no room $roomId'));
    } finally {
      _active--;
    }
  }
}

LiveRoom room(
  String platform,
  String id, {
  String nick = '',
  String title = '',
  LiveStatus? status,
  String popularity = '',
  LiveRestriction? restriction,
}) => LiveRoom(
  platform: platform,
  roomId: id,
  nick: nick,
  title: title,
  liveStatus: status,
  popularity: popularity,
  restriction: restriction,
);

Future<LiveStore> memoryStore() => LiveStore.memory(cipher: FakeCipher());

const _order = FollowOrder(preferRealOnline: false, realOnlinePlatforms: {}, tags: []);

void main() {
  group('rules', () {
    test('tabs: live (restricted too), playable replays, everything else offline (UPGRADES 1-1, 3-1)', () {
      expect(groupOf(room('bilibili', '1', status: LiveStatus.live)), FollowGroup.live);
      expect(
        groupOf(room('tiktok', '2', status: LiveStatus.live, restriction: LiveRestriction.paid)),
        FollowGroup.live,
      );
      expect(groupOf(room('weibo', '3', status: LiveStatus.replay)), FollowGroup.replay);
      expect(
        groupOf(room('huya', '4', status: LiveStatus.replay, restriction: LiveRestriction.unplayable)),
        FollowGroup.offline,
      );
      expect(groupOf(room('bilibili', '5', status: LiveStatus.carousel)), FollowGroup.offline);
      expect(groupOf(room('douyu', '6', status: LiveStatus.unknown)), FollowGroup.offline);
      // A retired platform's stored "live" is stale: it can no longer be checked.
      expect(groupOf(room('huajiao', '7', status: LiveStatus.live)), FollowGroup.offline);
    });

    test('platforms: the platform list order, then the others, retired last; only platforms with follows', () {
      final rooms = [room('huajiao', 'a'), room('huya', 'b'), room('douyu', 'c'), room('bilibili', 'd')];
      expect(platformTabs(rooms, ['douyu', 'huya']), ['all', 'douyu', 'huya', 'bilibili', 'huajiao']);
    });

    test('live follows by audience (tag rank first with a tag), offline in the user order, tag filter', () {
      final rooms = [
        room('douyu', 'small', status: LiveStatus.live, popularity: '10'),
        room('douyu', 'off2', status: LiveStatus.offline),
        room('douyu', 'big', status: LiveStatus.live, popularity: '9000'),
        room('douyu', 'off1', status: LiveStatus.offline),
      ];
      List<String> ids(FollowGroup group, {String tag = allTags, Map<String, List<String>> tags = const {}}) => [
        for (final r in roomsOf(rooms, group: group, platform: 'all', tagId: tag, assignments: tags, order: _order))
          r.roomId,
      ];
      expect(ids(FollowGroup.live), ['big', 'small']);
      expect(ids(FollowGroup.offline), ['off2', 'off1']);
      final assignments = {
        'douyu:small': ['t1'],
        'douyu:off1': ['t2'],
      };
      expect(ids(FollowGroup.live, tag: 't1', tags: assignments), ['small']);
      expect(
        tagsOf(
          rooms,
          group: FollowGroup.offline,
          platform: 'all',
          tags: const [
            StoreTag(id: 't1', name: 'A'),
            StoreTag(id: 't2', name: 'B'),
          ],
          assignments: assignments,
        ).map((tag) => tag.id),
        ['t2'],
      );
      expect(groupCounts(rooms, 'douyu'), {FollowGroup.live: 2, FollowGroup.replay: 0, FollowGroup.offline: 2});
    });
  });

  group('refresh', () {
    test('merges into the stored follow: empty names keep the stored ones, failures become pending', () async {
      final store = await memoryStore();
      addTearDown(store.close);
      await store.follows.add(room('douyu', '1', nick: 'Stored', title: 'Old', status: LiveStatus.live));
      await store.follows.add(room('douyu', '2', nick: 'Two', status: LiveStatus.live, popularity: '50'));
      await store.follows.add(room('huajiao', '3', nick: 'Retired', status: LiveStatus.live));
      final douyu = FakeSite('douyu', {
        // A placeholder-free answer without a name (JD Live, UPGRADES 28-2).
        '1': room('douyu', '1', title: 'New', status: LiveStatus.offline),
      });
      final refresher = FollowRefresher(sites: SiteRegistry({'douyu': () => douyu}));

      final result = await refresher.refresh(await store.follows.all(), concurrency: 4);
      await store.follows.update(result.rooms);

      expect(douyu.requested, ['1', '2']); // one request per room; the retired platform is not asked
      expect(result.failed, 1);
      final one = (await store.follows.find('douyu', '1'))!;
      expect((one.nick, one.title, one.effectiveLiveStatus), ('Stored', 'New', LiveStatus.offline));
      final two = (await store.follows.find('douyu', '2'))!;
      expect((two.nick, two.effectiveLiveStatus, two.popularity), ('Two', LiveStatus.unknown, '50'));
      expect((await store.follows.find('huajiao', '3'))!.effectiveLiveStatus, LiveStatus.live);
    });

    test('I03.2 c6: a platform without an adapter is skipped like a retired one, not failed', () async {
      final douyu = FakeSite('douyu', {'1': room('douyu', '1', status: LiveStatus.live)});
      final refresher = FollowRefresher(sites: SiteRegistry({'douyu': () => douyu}));
      final stored = room('huya', '2', status: LiveStatus.live);
      final progress = <int>[];
      final result = await refresher.refresh(
        [room('douyu', '1'), stored],
        concurrency: 2,
        onProgress: (_, total) => progress.add(total),
      );
      expect(result.failed, 0);
      expect(result.rooms.map((r) => r.roomId), ['1'], reason: 'the other room is kept as stored');
      expect(progress, [1]);
    });

    test('at most the concurrency setting at a time; a failed room waits out the cooldown', () async {
      var now = DateTime(2026, 10);
      final site = FakeSite('huya', {
        for (var i = 0; i < 6; i++) '$i': room('huya', '$i', status: LiveStatus.live),
      }, delay: const Duration(milliseconds: 5));
      final refresher = FollowRefresher(sites: SiteRegistry({'huya': () => site}), now: () => now);
      final rooms = [for (var i = 0; i < 7; i++) room('huya', '$i')];

      final progress = <int>[];
      await refresher.refresh(rooms, concurrency: 2, onProgress: (done, _) => progress.add(done));
      expect(site.maxActive, 2);
      expect(progress, [1, 2, 3, 4, 5, 6, 7]);

      site.requested.clear();
      now = now.add(const Duration(minutes: 1));
      await refresher.refresh(rooms, concurrency: 2);
      expect(site.requested, isNot(contains('6'))); // failed a minute ago
      await refresher.refresh(rooms, concurrency: 2, bypassCooldown: true);
      expect(site.requested.where((id) => id == '6'), hasLength(1));
    });

    test('an answer under another id is bound to the follow (3.x bindFavoriteRefreshResultToRequest)', () {
      final bound = bindToFollow(room('douyin', 'webrid'), room('douyin', '7123456789012345678', nick: 'N'));
      expect((bound.roomId, bound.nick), ('webrid', 'N'));
    });
  });

  group('controller', () {
    test('checks every follow at start after the identity move, marks them verifying meanwhile', () async {
      final store = await memoryStore();
      addTearDown(store.close);
      await store.follows.add(room('douyu', '1', nick: 'A', status: LiveStatus.offline));
      final ready = Completer<void>();
      final site = FakeSite('douyu', {'1': room('douyu', '1', status: LiveStatus.live, popularity: '9')});
      final controller = FavoriteController(
        store: store,
        refresher: FollowRefresher(sites: SiteRegistry({'douyu': () => site})),
        followsReady: ready.future,
      )..start();
      addTearDown(controller.dispose);

      await pumpEventQueue();
      expect(controller.verifying, isTrue);
      expect(site.requested, isEmpty);
      ready.complete();
      await pumpEventQueue();
      expect(site.requested, ['1']);
      expect(controller.verifying, isFalse);
      expect(controller.roomsFor(FollowGroup.live, allPlatforms).single.nick, 'A');
      expect(controller.lastFullRefreshAt, isNotNull);
    });

    test('selecting follows again refreshes the shown platform; a resume refreshes all, at most every 15 s', () async {
      final store = await memoryStore();
      addTearDown(store.close);
      await store.follows.add(room('douyu', '1'));
      await store.follows.add(room('huya', '2'));
      final douyu = FakeSite('douyu', {'1': room('douyu', '1', status: LiveStatus.live)});
      final huya = FakeSite('huya', {'2': room('huya', '2', status: LiveStatus.live)});
      var now = DateTime(2026, 10);
      final controller = FavoriteController(
        store: store,
        refresher: FollowRefresher(sites: SiteRegistry({'douyu': () => douyu, 'huya': () => huya})),
        now: () => now,
      )..start();
      addTearDown(controller.dispose);
      await pumpEventQueue();
      expect((douyu.requested.length, huya.requested.length), (1, 1));

      controller.selectPlatform('huya');
      HomeSignals.favoritesReselected.value++;
      await pumpEventQueue();
      expect((douyu.requested.length, huya.requested.length), (1, 2));

      HomeSignals.resumedAfterBackground.value = (HomeMenu.popular, 1);
      await pumpEventQueue();
      expect(douyu.requested, hasLength(1)); // the start pass was just now
      now = now.add(const Duration(seconds: 20));
      HomeSignals.resumedAfterBackground.value = (HomeMenu.popular, 2);
      await pumpEventQueue();
      expect((douyu.requested.length, huya.requested.length), (2, 3));

      await store.settings.set(Settings.refreshFavoriteOnResume, false);
      now = now.add(const Duration(minutes: 1));
      HomeSignals.resumedAfterBackground.value = (HomeMenu.popular, 3);
      await pumpEventQueue();
      expect(douyu.requested, hasLength(2));
    });
  });

  group('live alerts (O01.1, V01.1)', () {
    var resumes = 100;
    Future<void> resume() async {
      HomeSignals.resumedAfterBackground.value = (HomeMenu.popular, ++resumes);
      await pumpEventQueue();
    }

    test('the start check and a pull only record; a resume posts a room that began, once; off posts nothing', () async {
      final store = await memoryStore();
      addTearDown(store.close);
      await store.settings.set(Settings.liveAlertEnabled, true);
      await store.follows.add(room('douyu', '1', nick: 'A', status: LiveStatus.offline));
      await store.follows.add(room('douyu', '2', nick: 'B', status: LiveStatus.offline));
      await store.follows.add(room('douyu', '3', nick: 'C', status: LiveStatus.offline));
      final details = {
        '1': room('douyu', '1', status: LiveStatus.offline),
        '2': room('douyu', '2', status: LiveStatus.live),
        '3': room('douyu', '3', status: LiveStatus.offline),
      };
      final site = FakeSite('douyu', details);
      var now = DateTime(2026, 10, 8, 20);
      final posted = <LiveRoom>[];
      final controller = FavoriteController(
        store: store,
        refresher: FollowRefresher(sites: SiteRegistry({'douyu': () => site})),
        now: () => now,
        postLiveAlert: (room) async => posted.add(room),
      )..start();
      addTearDown(controller.dispose);
      await pumpEventQueue();
      expect(posted, isEmpty, reason: 'what is live at the start check is not news');

      details['3'] = room('douyu', '3', status: LiveStatus.live);
      await controller.refreshVisible();
      expect(posted, isEmpty, reason: 'a pull: the user sees it');
      details['3'] = room('douyu', '3', status: LiveStatus.offline);

      details['1'] = room('douyu', '1', nick: 'A', title: 'T', status: LiveStatus.live);
      now = now.add(const Duration(minutes: 20));
      await resume();
      expect([for (final room in posted) (room.roomId, room.nick, room.title)], [('1', 'A', 'T')]);
      now = now.add(const Duration(minutes: 20));
      await resume();
      expect(posted, hasLength(1), reason: 'the same broadcast');

      // The room switcher's refresh button is the user's too.
      details['3'] = room('douyu', '3', status: LiveStatus.live);
      await controller.refreshAll(visible: false, alert: false);
      expect(posted, hasLength(1));

      await store.settings.set(Settings.liveAlertEnabled, false);
      details['2'] = room('douyu', '2', status: LiveStatus.offline);
      now = now.add(const Duration(minutes: 20));
      await resume();
      details['2'] = room('douyu', '2', status: LiveStatus.live);
      now = now.add(const Duration(minutes: 20));
      await resume();
      expect(posted, hasLength(1), reason: 'switched off');
    });

    test("the recorder's check posts first; the follows' pass of the same broadcast does not repeat it", () async {
      final store = await memoryStore();
      addTearDown(store.close);
      await store.settings.set(Settings.liveAlertEnabled, true);
      await store.follows.add(room('douyu', '1', nick: 'A', status: LiveStatus.offline));
      final details = {'1': room('douyu', '1', status: LiveStatus.offline)};
      var now = DateTime(2026, 10, 8, 20);
      final posted = <String>[];
      final controller = FavoriteController(
        store: store,
        refresher: FollowRefresher(sites: SiteRegistry({'douyu': () => FakeSite('douyu', details)})),
        now: () => now,
        postLiveAlert: (room) async => posted.add(room.roomId),
      )..start();
      addTearDown(controller.dispose);
      await pumpEventQueue();

      final followed = RecordTask.fromRoom(room('douyu', '1', nick: 'A'), now: now);
      final other = RecordTask.fromRoom(room('douyu', '8', nick: 'X'), now: now);
      controller.recorderChanged([followed, other]);
      for (final task in [followed, other]) {
        task
          ..lastLiveCheckAt = now
          ..liveStatus = LiveStatus.offline;
      }
      controller.recorderChanged([followed, other]);
      for (final task in [followed, other]) {
        task
          ..lastLiveCheckAt = now.add(const Duration(minutes: 1))
          ..liveStatus = LiveStatus.live;
      }
      controller.recorderChanged([followed, other]);
      await pumpEventQueue();
      expect(posted, ['1'], reason: 'not followed: no alert');

      details['1'] = room('douyu', '1', status: LiveStatus.live);
      now = now.add(const Duration(minutes: 20));
      await resume();
      expect(posted, ['1']);
    });

    test('without "关注自动刷新" a timer checks only the covered follows (tags chosen)', () async {
      final store = await memoryStore();
      addTearDown(store.close);
      await store.follows.add(room('douyu', '1', nick: 'A', status: LiveStatus.offline));
      await store.follows.add(room('douyu', '2', nick: 'B', status: LiveStatus.offline));
      final tag = (await store.tags.add('提醒'))!;
      await store.tags.setTagsOf(room('douyu', '1'), [tag.id]);
      await store.settings.set(Settings.liveAlertTagIds, [tag.id]);
      final details = {
        '1': room('douyu', '1', status: LiveStatus.offline),
        '2': room('douyu', '2', status: LiveStatus.offline),
      };
      final site = FakeSite('douyu', details);
      final posted = <String>[];
      final controller = FavoriteController(
        store: store,
        refresher: FollowRefresher(sites: SiteRegistry({'douyu': () => site})),
        postLiveAlert: (room) async => posted.add(room.roomId),
        liveAlertCheckInterval: const Duration(seconds: 1),
      )..start();
      addTearDown(controller.dispose);
      await pumpEventQueue();
      expect(site.requested, ['1', '2']);

      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(site.requested, ['1', '2'], reason: 'off: no timer');

      await store.settings.set(Settings.liveAlertEnabled, true);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(site.requested, ['1', '2', '1'], reason: 'only the tagged follow');
      details['1'] = room('douyu', '1', status: LiveStatus.live);
      details['2'] = room('douyu', '2', status: LiveStatus.live);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(site.requested, ['1', '2', '1', '1']);
      expect(posted, ['1']);
      expect([for (final room in controller.liveAlertTargets) room.roomId], ['1']);

      // "关注自动刷新" takes over with its own interval (30 minutes).
      await store.settings.set(Settings.autoRefreshFavorite, true);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(site.requested, hasLength(4));
    });
  });

  group('page', () {
    Future<(AppServices, FavoriteController, FakeSite)> pumpPage(
      WidgetTester tester, {
      List<LiveRoom> follows = const [],
      Map<String, LiveRoom> details = const {},
      bool inHome = false,
      double width = 400,
      List<Object?>? opened,
    }) async {
      tester.view
        ..physicalSize = Size(width, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final douyu = FakeSite('douyu', details);
      final sites = SiteRegistry({'douyu': () => douyu, 'huya': () => FakeSite('huya', const {})});
      final services = (await tester.runAsync(() async {
        final services = await testServices();
        for (final follow in follows) {
          await services.store.follows.add(follow);
        }
        return services;
      }))!;
      final strings = (await tester.runAsync(loadStrings))!;
      final controller = FavoriteController(
        store: services.store,
        refresher: FollowRefresher(sites: sites),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appServicesProvider.overrideWithValue(services),
            sitesProvider.overrideWithValue(sites),
            favoriteControllerProvider.overrideWith((ref) {
              ref.onDispose(controller.dispose);
              return controller..start();
            }),
          ],
          child: opened == null
              ? MaterialApp(
                  theme: const LiveTheme(primaryColor: Colors.blue).light,
                  home: LiveUiScope(
                    config: LiveUiConfig(strings: strings.ui),
                    child: FavoritePage(route: RouteArgs(RoutePath.kFavorite, inHome: inHome)),
                  ),
                )
              // The rooms it opens are noted instead of shown (U.2b2).
              : MaterialApp.router(
                  theme: const LiveTheme(primaryColor: Colors.blue).light,
                  routerConfig: AppNavigator.router = GoRouter(
                    initialLocation: RoutePath.kInitial,
                    routes: [
                      GoRoute(
                        path: RoutePath.kInitial,
                        builder: (context, state) => LiveUiScope(
                          config: LiveUiConfig(strings: strings.ui),
                          child: FavoritePage(route: RouteArgs(RoutePath.kFavorite, inHome: inHome)),
                        ),
                      ),
                      GoRoute(
                        path: RoutePath.kLivePlay,
                        builder: (context, state) {
                          opened.add(state.extra);
                          return const SizedBox.shrink();
                        },
                      ),
                    ],
                  ),
                ),
        ),
      );
      if (opened != null) addTearDown(() => AppNavigator.router = null);
      await tester.pumpAndSettle();
      return (services, controller, douyu);
    }

    testWidgets('no follows: the empty page leads to search, with a search icon', (tester) async {
      final (services, _, _) = await pumpPage(tester);
      expect(find.text(i18n('empty_favorite_title')), findsOneWidget);
      expect(find.text(i18n('search_live')), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const ValueKey('status-button')), matching: find.byIcon(AppIcons.search)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      await tester.runAsync(services.close);
    });

    testWidgets('tabs, counts, platforms, marks and the offline shortcut', (tester) async {
      final (services, controller, douyu) = await pumpPage(
        tester,
        follows: [
          room('douyu', '1', nick: '主播一', status: LiveStatus.offline),
          room('douyu', '2', nick: '主播二', status: LiveStatus.live),
          room('huya', '3', nick: '主播三', status: LiveStatus.offline),
          room('huajiao', '4', nick: '旧平台', status: LiveStatus.live),
        ],
        details: {
          '1': room('douyu', '1', status: LiveStatus.live, popularity: '12345', restriction: LiveRestriction.paid),
          '2': room('douyu', '2', status: LiveStatus.carousel),
        },
      );
      expect(douyu.requested, unorderedEquals(['1', '2']));
      // P02: 3.x's bounce and classic header, also here (3.x had the
      // Material circle on this page).
      expect(find.byType(RefreshIndicator), findsNothing);
      expect(find.byType(AppRefreshView), findsWidgets);
      // P03: the platform pages turn like Android's ViewPager.
      expect(tester.widget<TabBarView>(find.byType(TabBarView)).physics, isA<PureLivePageScrollPhysics>());
      // Live: the paid room, marked; its audience shortened as 3.x did.
      expect(find.text('主播一'), findsOneWidget);
      expect(find.text(i18n('room_mark_paid')), findsOneWidget);
      expect(find.text('1.2万'), findsOneWidget);
      expect(find.text('主播二'), findsNothing);
      // Platform rail: all, then the platforms with follows, the retired one last.
      expect(controller.platforms, ['all', 'douyu', 'huya', 'huajiao']);

      await tester.tap(find.textContaining(i18n('offline_room_title')));
      await tester.pumpAndSettle();
      expect(find.text('主播二'), findsOneWidget);
      expect(find.text(i18n('room_mark_carousel')), findsOneWidget);
      // Huya failed: kept, pending. Kick is retired: marked, not pending.
      expect(find.text('主播三'), findsOneWidget);
      expect(find.text(i18n('favorite_status_unknown')), findsOneWidget);
      expect(find.text(i18n('room_mark_retired')), findsOneWidget);

      // A platform without live follows offers its offline ones.
      await tester.tap(find.textContaining(i18n('online_room_title')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(i18n('site_huya')));
      await tester.pumpAndSettle();
      expect(find.text(i18n('favorite_show_offline')), findsOneWidget);
      await tester.tap(find.text(i18n('favorite_show_offline')));
      await tester.pumpAndSettle();
      expect(controller.group, FollowGroup.offline);
      expect(find.text('主播三'), findsOneWidget);
      await tester.runAsync(services.close);
    });

    testWidgets('the status tabs show their whole label and count on a phone', (tester) async {
      final (services, _, _) = await pumpPage(
        tester,
        inHome: true,
        width: 360,
        follows: [for (var i = 1; i <= 12; i++) room('douyu', '$i', nick: '主播$i', status: LiveStatus.live)],
        details: {for (var i = 1; i <= 12; i++) '$i': room('douyu', '$i', status: LiveStatus.live)},
      );
      final bar = find.byKey(const ValueKey('favorite-status-tabs'));
      for (final label in [i18n('online_room_title'), i18n('recording_room_title'), i18n('offline_room_title')]) {
        final text = find.descendant(of: bar, matching: find.text(label));
        expect(text, findsOneWidget);
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(paragraph.didExceedMaxLines, isFalse, reason: '$label is cut');
        expect(paragraph.size.width, greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(double.infinity) - 0.5));
      }
      final count = find.descendant(of: bar, matching: find.text('12'));
      expect(count, findsOneWidget);
      final tab = find.ancestor(of: count, matching: find.byType(Tab));
      final tabRect = tester.getRect(tab);
      final countRect = tester.getRect(count);
      expect(countRect.right, lessThanOrEqualTo(tabRect.right + 0.5));
      expect(countRect.left, greaterThanOrEqualTo(tabRect.left - 0.5));
      // The label and the count fit without shrinking much (the test font's
      // digits are as wide as a CJK character, twice a real font's). The
      // bar's right side has two buttons since U.3a c4 (search, more), so on
      // a 360 phone the tabs have 48 less than with 3.x's one search menu.
      final content = find.descendant(of: tab, matching: find.byType(Row)).first;
      final box = find.descendant(of: tab, matching: find.byType(FittedBox));
      expect(tester.getSize(box).width / tester.getSize(content).width, greaterThan(0.7));
      await tester.runAsync(services.close);
    });

    testWidgets('tags filter the grid; the card menu sets tags and unfollows with undo', (tester) async {
      final (services, controller, _) = await pumpPage(
        tester,
        follows: [
          room('douyu', '1', nick: '甲', status: LiveStatus.live),
          room('douyu', '2', nick: '乙', status: LiveStatus.live),
        ],
        details: {
          '1': room('douyu', '1', status: LiveStatus.live, popularity: '20'),
          '2': room('douyu', '2', status: LiveStatus.live, popularity: '10'),
        },
      );
      expect(find.byKey(const ValueKey('favorite-tag-strip')), findsNothing);

      // Long press → tags → create "常看" → save.
      await tester.longPress(find.byKey(const ValueKey('douyu:1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('room-menu-tags')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      // No tags yet: the form is open; "确认" makes the typed tag, then saves (U.4a c13).
      await tester.enterText(find.byKey(const ValueKey('room-tags-name')), '常看');
      await tester.tap(find.byKey(const ValueKey('room-tags-save')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('favorite-tag-strip')), findsOneWidget);
      await tester.tap(find.text('常看'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('douyu:1')), findsOneWidget);
      expect(find.byKey(const ValueKey('douyu:2')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('favorite-tag-all')));
      await tester.pumpAndSettle();
      expect(controller.tagId, allTags);

      // Unfollow 乙 and undo it.
      await tester.longPress(find.byKey(const ValueKey('douyu:2')));
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('room-menu-follow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('unfollow-confirm')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('douyu:2')), findsNothing);
      expect(await tester.runAsync(services.store.follows.count), 1);
      await tester.tap(find.text(i18n('room_undo')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      final restored = (await tester.runAsync(services.store.follows.all))!;
      expect(restored.map((r) => r.roomId), ['1', '2']); // back in its place
      await tester.pump(const Duration(seconds: 5)); // let the snack bar go
      await tester.pumpAndSettle();
      await tester.runAsync(services.close);
    });
    testWidgets('U.4c c3, c4: phones show the platform tabs as a second row; from 840 they join the status tabs', (
      tester,
    ) async {
      final follows = [
        room('douyu', '1', nick: '甲', status: LiveStatus.live),
        room('huya', '2', nick: '乙', status: LiveStatus.live),
        room('huya', '3', nick: '丙', status: LiveStatus.offline),
      ];
      final details = {'1': room('douyu', '1', status: LiveStatus.live)};
      var (services, _, _) = await pumpPage(tester, follows: follows, details: details);
      final status = find.byKey(const ValueKey('favorite-status-tabs'));
      final platforms = find.byKey(const ValueKey('favorite-platform-tabs'));
      expect(tester.getTopLeft(platforms).dy, greaterThan(tester.getBottomLeft(status).dy - 1));
      // Numbers after the labels: the platform numbers follow the status shown.
      expect(find.descendant(of: platforms, matching: find.text('全部')), findsOneWidget);
      expect(tester.widget<TabBar>(status).tabAlignment, TabAlignment.fill);
      await tester.runAsync(services.close);

      (services, _, _) = await pumpPage(tester, follows: follows, details: details, width: 1000);
      expect(tester.getCenter(platforms).dy, closeTo(tester.getCenter(status).dy, 1));
      expect(tester.getTopLeft(platforms).dx, greaterThan(tester.getTopRight(status).dx - 1));
      expect(tester.widget<TabBar>(status).isScrollable, isTrue);
      await tester.runAsync(services.close);
    });

    testWidgets('U.4c c5, c10: "all" cards name their platform; offline follows are rows with the logo', (
      tester,
    ) async {
      final (services, _, _) = await pumpPage(
        tester,
        follows: [
          room('douyu', '1', nick: '甲', status: LiveStatus.live),
          room('huya', '2', nick: '乙', status: LiveStatus.live),
          room('douyu', '3', nick: '丙', status: LiveStatus.offline),
        ],
        details: {
          '1': room('douyu', '1', status: LiveStatus.live),
          '3': room('douyu', '3', status: LiveStatus.offline, title: '上次的标题'),
        },
      );
      // "All" mixes platforms: the badge; the grid has popular's padding (c6).
      expect(find.byKey(const ValueKey('room-card-platform-badge')), findsWidgets);
      expect(find.byType(LiveRoomCard), findsWidgets);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('favorite-platform-tabs')),
          matching: find.text(i18n('site_douyu')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('room-card-platform-badge')), findsNothing);

      await tester.tap(find.textContaining(i18n('offline_room_title')));
      await tester.pumpAndSettle();
      expect(find.byType(RoomRow), findsOneWidget);
      expect(find.byType(LiveRoomCard), findsNothing);
      expect(find.text('丙'), findsWidgets); // the name and the avatar's letter
      expect(find.text('上次的标题'), findsOneWidget);
      expect(tester.getSize(find.byType(RoomRow)).height, greaterThanOrEqualTo(RoomRow.height));
      await tester.runAsync(services.close);
    });

    testWidgets("U.2b2 c1: a card opens its room with the group's rooms in their order; an offline row too", (
      tester,
    ) async {
      final opened = <Object?>[];
      final (services, _, _) = await pumpPage(
        tester,
        opened: opened,
        follows: [
          room('douyu', '1', nick: '甲', status: LiveStatus.live),
          room('douyu', '2', nick: '乙', status: LiveStatus.live),
          room('douyu', '3', nick: '丙', status: LiveStatus.offline),
          room('douyu', '4', nick: '丁', status: LiveStatus.offline),
        ],
        details: {
          '1': room('douyu', '1', nick: '甲', status: LiveStatus.live, popularity: '10'),
          '2': room('douyu', '2', nick: '乙', status: LiveStatus.live, popularity: '20'),
          '3': room('douyu', '3', nick: '丙', status: LiveStatus.offline),
          '4': room('douyu', '4', nick: '丁', status: LiveStatus.offline),
        },
      );
      final shown = tester.widgetList<RoomGridCard>(find.byType(RoomGridCard)).map((card) => card.room.roomId);
      expect(shown, hasLength(2));
      await tester.tap(find.byWidgetPredicate((widget) => widget is RoomGridCard && widget.room.roomId == '1'));
      await tester.pumpAndSettle();
      final live = opened.last! as LiveRoomArgs;
      expect(live.room.roomId, '1');
      expect(live.playlist.map((item) => item.roomId), shown);
      AppNavigator.back();
      await tester.pumpAndSettle();
      await tester.pump(AppNavigator.openGuard);

      await tester.tap(find.textContaining(i18n('offline_room_title')));
      await tester.pumpAndSettle();
      final rows = tester.widgetList<RoomRow>(find.byType(RoomRow)).map((row) => row.data.title).toList();
      expect(rows, hasLength(2));
      await tester.tap(find.byType(RoomRow).last);
      await tester.pumpAndSettle();
      final offline = opened.last! as LiveRoomArgs;
      expect(offline.playlist.map((item) => item.roomId).toSet(), {'3', '4'});
      AppNavigator.back();
      await tester.pumpAndSettle();
      await tester.pump(AppNavigator.openGuard);
      await tester.runAsync(services.close);
    });

    testWidgets('U.4c c8: none of the follows is live says so; "view offline" and a text button "refresh"', (
      tester,
    ) async {
      final (services, controller, _) = await pumpPage(
        tester,
        follows: [room('douyu', '1', nick: '甲', status: LiveStatus.offline)],
        details: {'1': room('douyu', '1', status: LiveStatus.offline)},
      );
      expect(find.text(withoutOrphan('关注的 1 个直播间现在都没有开播')), findsOneWidget);
      expect(find.text(i18n('favorite_show_offline')), findsOneWidget);
      expect(tester.widget(find.byKey(const ValueKey('status-secondary-button'))), isA<TextButton>());
      expect(find.text('刷新'), findsOneWidget);
      // Recording: the hint for phones.
      await tester.tap(find.textContaining(i18n('recording_room_title')));
      await tester.pumpAndSettle();
      expect(find.text(withoutOrphan('可以左右滑动切换平台，或下拉刷新')), findsOneWidget);
      expect(controller.group, FollowGroup.replay);
      await tester.runAsync(services.close);
    });
  });
}
