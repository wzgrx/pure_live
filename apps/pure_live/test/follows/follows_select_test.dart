import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/features/follows/follows_page.dart';
import 'package:pure_live_app/features/follows/groups.dart';
import 'package:pure_live_app/features/rooms/card_marks.dart';

import '../fakes.dart';

/// A refresh that already published: rooms show as stored.
class _Done extends FollowRefreshNotifier {
  @override
  Future<FollowRefreshResult?> build() async => null;
}

/// principles §4.1, spec/product.md F-FAV-09: multi-select on the follows
/// page.
void main() {
  late LiveStore store;

  /// Pages pushed on top: the multiview page's rooms, or the room opened.
  late List<Object?> pushed;

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Live `a`–`e` on douyu, offline `x` and `y`; `a` and `x` are in 常看.
  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(393, 1400),
    bool tv = false,
    List<String> live = const ['a', 'b', 'c', 'd', 'e'],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    pushed = [];
    store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    final follows = (await tester.runAsync(() async {
      for (final (index, id) in [...live, 'x', 'y'].indexed) {
        await store.follows.follow(
          RoomSnapshot(
            ref: RoomRef('douyu', id),
            anchorName: '主播$id',
            title: '标题$id',
            audience: Audience(online: 1000 - index),
            state: live.contains(id) ? LiveState.live : LiveState.offline,
          ),
        );
      }
      final tag = await store.tags.create('常看');
      await store.tags.setTagsOf(RoomRef('douyu', 'a'), {tag.id});
      await store.tags.setTagsOf(RoomRef('douyu', 'x'), {tag.id});
      return await store.follows.all();
    }))!;
    final tags = (await tester.runAsync(store.tags.all))!;
    final router = GoRouter(
      initialLocation: '/follows',
      routes: [
        GoRoute(path: '/follows', builder: (context, state) => const FollowsPage()),
        GoRoute(
          path: '/multiview',
          builder: (context, state) {
            pushed.add(state.extra);
            return const Scaffold(body: Text('多画面页'));
          },
        ),
        GoRoute(
          path: '/room/:platform/:roomId',
          builder: (context, state) {
            pushed.add(state.pathParameters['roomId']);
            return Scaffold(body: Text('直播间 ${state.pathParameters['roomId']}'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    final app = MaterialApp.router(
      theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
      routerConfig: router,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          sitesProvider.overrideWithValue({'douyu': PlatformSite(FakeSite('douyu'))}),
          followsProvider.overrideWith((ref) => Stream.value(follows)),
          followRefreshProvider.overrideWith(_Done.new),
          tagsProvider.overrideWith((ref) => Stream.value(tags)),
          recordingRoomsProvider.overrideWith((ref) => Stream.value(const {})),
        ],
        child: tv ? TvScope(config: const TvConfig(enabled: true), child: app) : app,
      ),
    );
    await settle(tester);
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Finder card(String id) => find.byWidgetPredicate((widget) => widget is RoomCardView && widget.anchorName == '主播$id');
  Finder row(String id) => find.byWidgetPredicate((widget) => widget is OfflineRoomRow && widget.anchorName == '主播$id');

  bool marked(WidgetTester tester, String id) {
    final cards = find.ancestor(of: card(id), matching: find.byType(SelectableCard));
    if (cards.evaluate().isNotEmpty) return tester.widget<SelectableCard>(cards).selected;
    return tester.widget<SelectableRow>(find.ancestor(of: row(id), matching: find.byType(SelectableRow))).selected;
  }

  /// Long press, then 多选 in the card menu.
  Future<void> startWith(WidgetTester tester, Finder target) async {
    await tester.longPress(target);
    await tester.pumpAndSettle();
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
  }

  Future<List<String>> followed(WidgetTester tester) async => [
    for (final follow in (await tester.runAsync(store.follows.all))!) follow.ref.roomId,
  ];

  testWidgets('long press keeps the card menu (§4.2); its 多选 starts multi-select with that card', (tester) async {
    await pumpPage(tester);
    await tester.longPress(card('b'));
    await tester.pumpAndSettle();
    expect(find.text('分享'), findsOneWidget, reason: 'the menu, as on every card page');
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1'), findsOneWidget);
    expect(marked(tester, 'b'), isTrue);
    expect(marked(tester, 'a'), isFalse);

    await tester.tap(card('d'));
    await tester.tap(row('y'));
    await tester.pump();
    expect(find.text('已选 3'), findsOneWidget, reason: 'taps choose instead of opening');
    expect(pushed, isEmpty);
    await tester.tap(card('b'));
    await tester.pump();
    expect(find.text('已选 2'), findsOneWidget);
    await tester.longPress(card('a'));
    await tester.pump();
    expect(find.text('已选 3'), findsOneWidget, reason: 'a long press chooses too while selecting');

    await tester.tap(find.byTooltip('全选'));
    await tester.pump();
    expect(find.text('已选 7'), findsOneWidget);
    await tester.tap(find.byTooltip('取消多选'));
    await tester.pump();
    expect(find.text('关注'), findsOneWidget, reason: 'the page title is back');
    await tester.tap(card('a'));
    await tester.pumpAndSettle();
    expect(pushed, ['a'], reason: 'a tap opens the room again');
    await done(tester);
  });

  testWidgets('取消关注 unfollows the chosen at once, with undo and no confirmation', (tester) async {
    await pumpPage(tester);
    await startWith(tester, card('b'));
    await tester.tap(row('x'));
    await tester.pump();
    await tester.tap(find.byTooltip('取消关注'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(await followed(tester), ['a', 'c', 'd', 'e', 'y']);
    expect(find.text('已取消关注 2 个主播'), findsOneWidget);
    expect(find.text('已选 2'), findsNothing, reason: 'multi-select ends');
    await tester.tap(find.text('撤销'));
    await settle(tester);
    expect(await followed(tester), ['a', 'b', 'c', 'd', 'e', 'x', 'y'], reason: 'back in their places');
    await done(tester);
  });

  testWidgets('设置分组: a group some of them are in stays unless changed; checked adds all', (tester) async {
    await pumpPage(tester);
    await startWith(tester, card('a'));
    await tester.tap(card('c'));
    await tester.pump();
    await tester.tap(find.byTooltip('设置分组'));
    await settle(tester);
    expect(find.text('设置分组 · 已选的 2 个主播'), findsOneWidget);
    final box = find.widgetWithText(CheckboxListTile, '常看');
    expect(tester.widget<CheckboxListTile>(box).value, isNull, reason: 'a is in it, c is not');
    await tester.tap(find.text('保存'));
    await settle(tester);
    final tag = (await tester.runAsync(store.tags.all))!.single;
    expect(await tester.runAsync(() => store.tags.tagsOf(RoomRef('douyu', 'a'))), {tag.id});
    expect(await tester.runAsync(() => store.tags.tagsOf(RoomRef('douyu', 'c'))), isEmpty, reason: 'left alone');
    expect(find.text('已选 2'), findsNothing, reason: 'saving ends multi-select');

    await startWith(tester, card('b'));
    await tester.tap(card('c'));
    await tester.pump();
    await tester.tap(find.byTooltip('设置分组'));
    await settle(tester);
    await tester.tap(find.text('常看'));
    await tester.tap(find.text('保存'));
    await settle(tester);
    for (final id in ['b', 'c']) {
      expect(await tester.runAsync(() => store.tags.tagsOf(RoomRef('douyu', id))), {tag.id});
    }
    await done(tester);
  });

  testWidgets('加入多画面 fills the cells in the order chosen', (tester) async {
    await pumpPage(tester);
    await startWith(tester, card('c'));
    await tester.tap(card('a'));
    await tester.pump();
    await tester.tap(find.byTooltip('加入多画面'));
    await tester.pumpAndSettle();
    expect(pushed.single, [RoomRef('douyu', 'c'), RoomRef('douyu', 'a')]);
    expect(find.text('多画面页'), findsOneWidget);
    await done(tester);
  });

  testWidgets('加入多画面 with more than the window holds: the first ones in the order chosen, and says so', (tester) async {
    await pumpPage(tester);
    await startWith(tester, card('e'));
    for (final id in ['d', 'c', 'b', 'a']) {
      await tester.tap(card(id));
    }
    await tester.pump();
    await tester.tap(find.byTooltip('加入多画面'));
    await tester.pumpAndSettle();
    // A phone-wide window offers up to 2×2 (principles §5.2).
    expect(pushed.single, [
      for (final id in ['e', 'd', 'c', 'b']) RoomRef('douyu', id),
    ]);
    expect(find.text('多画面在这里最多放 4 路，已按选择顺序放入前 4 个'), findsOneWidget);
    await done(tester);
  });

  testWidgets('back and Esc leave multi-select before anything else', (tester) async {
    await pumpPage(tester);
    await startWith(tester, card('a'));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('已选 1'), findsNothing);
    expect(find.byType(FollowsPage), findsOneWidget, reason: 'still on the page');

    await startWith(tester, card('a'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('已选 1'), findsNothing);
    await done(tester);
  });

  testWidgets('desktop: Ctrl-click starts and toggles, Shift-click adds the range as shown', (tester) async {
    await pumpPage(tester, size: const Size(1440, 1400));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(card('b'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('已选 1'), findsOneWidget);
    expect(pushed, isEmpty, reason: 'no room opened');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(row('x'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(find.text('已选 5'), findsOneWidget, reason: 'b, c, d, e and x');
    expect(
      [
        for (final id in ['a', 'b', 'c', 'd', 'e', 'x', 'y']) marked(tester, id),
      ],
      [false, true, true, true, true, true, false],
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.text('已选 7'), findsOneWidget, reason: 'Ctrl+A');
    await done(tester);
  });

  testWidgets('TV has no multi-select: no 多选 in the menu, and OK opens the room', (tester) async {
    await pumpPage(tester, size: const Size(960, 540), tv: true);
    await tester.longPress(card('a'));
    await tester.pumpAndSettle();
    expect(find.text('分享'), findsOneWidget);
    expect(find.text('多选'), findsNothing);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(card('b'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(pushed, ['b']);
    await done(tester);
  });

  group('principles §5.2: a landscape phone', () {
    double headerHeight(WidgetTester tester) => tester.getSize(find.byType(AnimatedAlign).first).height;

    testWidgets('lets the top bar scroll away and back', (tester) async {
      await pumpPage(tester, size: const Size(852, 393), live: [for (var i = 0; i < 16; i++) 'r$i']);
      expect(find.byType(ScrollAwayHeader), findsOneWidget);
      expect(headerHeight(tester), greaterThan(0));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(headerHeight(tester), 0, reason: 'scrolling down hides the bar');
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(headerHeight(tester), greaterThan(0), reason: 'scrolling up brings it back');
      await done(tester);
    });

    testWidgets('keeps the multi-select bar in view', (tester) async {
      await pumpPage(tester, size: const Size(852, 393), live: [for (var i = 0; i < 16; i++) 'r$i']);
      await startWith(tester, card('r0'));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(headerHeight(tester), greaterThan(0));
      expect(find.text('已选 1'), findsOneWidget);
      await done(tester);
    });

    testWidgets('portrait and wide windows keep the usual bar', (tester) async {
      await pumpPage(tester, size: const Size(393, 852));
      expect(find.byType(ScrollAwayHeader), findsNothing);
      await done(tester);
    });
  });
}
