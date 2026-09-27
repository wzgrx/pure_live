import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/follows/follow_order_page.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/features/follows/follows_page.dart';
import 'package:pure_live_app/features/follows/groups.dart';
import 'package:pure_live_app/features/rooms/card_marks.dart';

import '../fakes.dart';

/// A first refresh the test finishes by hand.
class _Pending extends FollowRefreshNotifier {
  final result = Completer<FollowRefreshResult?>();

  @override
  Future<FollowRefreshResult?> build() => result.future;
}

/// A refresh that already published [value].
class _Done extends FollowRefreshNotifier {
  new(this.value);

  final FollowRefreshResult? value;

  @override
  Future<FollowRefreshResult?> build() async => value;
}

final DateTime _now = DateTime.now().toUtc();

FollowedRoom _follow(
  String platform,
  String id, {
  LiveState state = LiveState.live,
  int online = 100,
  Set<String> tags = const {},
  int order = 0,
}) => FollowedRoom(
  room: StoredRoom(
    ref: RoomRef(platform, id),
    anchorName: '主播$id',
    title: '标题$id',
    updatedAt: _now,
    audience: Audience(online: online),
    lastState: state,
  ),
  followedAt: _now,
  order: order,
  tagIds: tags,
);

void main() {
  late LiveStore store;

  Future<void> pumpPage(
    WidgetTester tester, {
    required List<FollowedRoom> follows,
    required FollowRefreshNotifier Function() refresh,
    List<Tag> tags = const [],
    Set<String> recording = const {},
  }) async {
    tester.view.physicalSize = const Size(393, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    final router = GoRouter(
      initialLocation: '/follows',
      routes: [
        GoRoute(
          path: '/follows',
          builder: (context, state) => const FollowsPage(),
          routes: [GoRoute(path: 'order', builder: (context, state) => const Text('调整顺序页'))],
        ),
        GoRoute(
          path: '/room/:platform/:roomId',
          builder: (context, state) => Text('直播间 ${state.pathParameters['roomId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          sitesProvider.overrideWithValue({
            for (final id in ['bilibili', 'douyu', 'huya']) id: PlatformSite(FakeSite(id)),
          }),
          followsProvider.overrideWith((ref) => Stream.value(follows)),
          followRefreshProvider.overrideWith(refresh),
          tagsProvider.overrideWith((ref) => Stream.value(tags)),
          recordingRoomsProvider.overrideWith((ref) => Stream.value(recording)),
        ],
        child: MaterialApp.router(
          theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
  }

  List<String> cardNames(WidgetTester tester) => [
    for (final card in tester.widgetList<RoomCardView>(find.byType(RoomCardView))) card.anchorName,
  ];

  testWidgets('F-FAV-03: nothing shows as live until the first refresh publishes, then all at once', (tester) async {
    final refresh = _Pending();
    await pumpPage(
      tester,
      follows: [
        _follow('douyu', 'a'),
        _follow('douyu', 'b', state: LiveState.offline),
        _follow('huajiao', 'c', state: LiveState.offline),
      ],
      refresh: () => refresh,
    );
    expect(find.text('正在检查开播状态'), findsWidgets);
    expect(find.byType(RoomCardView), findsNothing, reason: 'the stored live state is from an earlier run');
    expect(find.text('全部关注 3'), findsOneWidget);
    expect(find.text('未支持'), findsOneWidget, reason: 'known without the network (F-FAV-08)');

    refresh.result.complete(
      FollowRefreshResult(checked: 2, failedPlatforms: const {}, skipped: const {'huajiao:c'}, at: _now),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('正在检查开播状态'), findsNothing);
    expect(cardNames(tester), ['主播a']);
    expect(find.text('未开播 2'), findsOneWidget);
    expect(find.text('开播 1'), findsOneWidget);
  });

  testWidgets('F-FAV-03: a room whose refresh failed shows 状态未知 and the banner names the platform', (tester) async {
    await pumpPage(
      tester,
      follows: [_follow('douyu', 'a'), _follow('huya', 'b')],
      refresh: () =>
          _Done(FollowRefreshResult(checked: 1, failedPlatforms: const {'huya'}, failed: const {'huya:b'}, at: _now)),
    );
    await tester.pump();
    expect(cardNames(tester), ['主播a']);
    expect(find.text('状态未知'), findsOneWidget);
    expect(find.textContaining('虎牙 刷新失败'), findsOneWidget);
  });

  testWidgets('F-FAV-08: an unsupported platform says so instead of opening the room', (tester) async {
    await pumpPage(
      tester,
      follows: [_follow('huajiao', 'c', state: LiveState.offline)],
      refresh: () => _Done(null),
    );
    await tester.pump();
    await tester.tap(find.text('主播c'));
    await tester.pump();
    expect(find.textContaining('花椒已下线或这个版本还不支持'), findsOneWidget);
    expect(find.textContaining('直播间'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('F-FAV-01: recording rooms carry 录制中', (tester) async {
    await pumpPage(
      tester,
      follows: [
        _follow('douyu', 'a'),
        _follow('douyu', 'b', state: LiveState.offline),
      ],
      refresh: () => _Done(null),
      recording: const {'douyu:a', 'douyu:b'},
    );
    await tester.pump();
    expect(find.byType(RecordingBadge), findsOneWidget, reason: 'on the live card');
    expect(find.text('录制中'), findsNWidgets(2), reason: 'card and row');
  });

  testWidgets('F-FAV-01: the order menu applies and remembers the choice', (tester) async {
    await pumpPage(
      tester,
      follows: [
        _follow('douyu', 'a', online: 50, order: 1),
        _follow('bilibili', 'b', online: 10, order: 2),
        _follow('huya', 'c', online: 90),
      ],
      refresh: () => _Done(null),
    );
    await tester.pump();
    expect(cardNames(tester), ['主播c', '主播a', '主播b'], reason: 'by audience by default');

    Future<void> choose(String label) async {
      await tester.tap(find.byTooltip('排序'));
      await tester.pumpAndSettle();
      // The item's own tap target covers the label.
      await tester.tap(find.text(label), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }

    await choose('按平台');
    expect(store.settings.get(Settings.followSort), FollowSort.platform);
    expect(cardNames(tester), ['主播b', '主播a', '主播c'], reason: 'bilibili, douyu, huya');

    await choose('自定义顺序');
    expect(cardNames(tester), ['主播c', '主播a', '主播b']);

    await choose('按人数');
    await choose('调整自定义顺序');
    expect(find.text('调整顺序页'), findsOneWidget);
    expect(store.settings.get(Settings.followSort), FollowSort.custom, reason: 'the page edits the custom order');
  });

  testWidgets('F-FAV-01: dragging on the order page stores the custom order', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    await tester.runAsync(() async {
      for (final id in ['1', '2', '3']) {
        await store.follows.follow(RoomSnapshot(ref: RoomRef('douyu', id), anchorName: '主播$id'));
      }
    });
    final follows = (await tester.runAsync(store.follows.all))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          followsProvider.overrideWith((ref) => Stream.value(follows)),
        ],
        child: MaterialApp(
          theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
          home: const FollowOrderPage(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('主播1'), findsOneWidget);

    // Long press lifts the row on touch screens; drop it below the second.
    final gesture = await tester.startGesture(tester.getCenter(find.text('主播1')));
    await tester.pump(const Duration(seconds: 1));
    await gesture.moveBy(const Offset(0, 180));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    final stored = (await tester.runAsync(store.follows.all))!;
    expect([for (final follow in stored) follow.ref.roomId], ['2', '1', '3']);
  });

  testWidgets('F-FAV-05: the group view has a section per group with its description, then 未分组', (tester) async {
    await pumpPage(
      tester,
      follows: [
        _follow('douyu', 'a', tags: const {'t1'}),
        _follow('douyu', 'b', state: LiveState.offline, tags: const {'t1'}),
        _follow('douyu', 'c', state: LiveState.offline),
      ],
      refresh: () => _Done(null),
      tags: const [
        Tag(id: 't1', name: '常看', description: '晚上看的', order: 0),
        Tag(id: 't2', name: '空组', order: 1),
      ],
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, '分组'));
    await tester.pump();
    // The groups arrive with the next frame.
    await tester.pump();
    expect(find.text('常看 · 2'), findsOneWidget);
    expect(find.text('晚上看的'), findsOneWidget);
    expect(find.text('空组 · 0'), findsOneWidget);
    expect(find.text('这个分组还没有主播'), findsOneWidget);
    expect(find.text('未分组 · 1'), findsOneWidget);
    expect(cardNames(tester), ['主播a']);
  });
}
