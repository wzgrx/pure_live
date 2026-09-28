import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_media/testing.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/engine.dart';
import 'package:pure_live_app/core/network.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/danmaku/danmaku_preferences.dart';
import 'package:pure_live_app/features/danmaku/danmaku_source.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/features/me/history_page.dart';
import 'package:pure_live_app/features/multiview/multiview_cell.dart';
import 'package:pure_live_app/features/multiview/multiview_controller.dart';
import 'package:pure_live_app/features/multiview/multiview_page.dart';
import 'package:pure_live_app/features/multiview/multiview_sheets.dart';

import 'danmaku/fake_danmaku.dart';
import 'fakes.dart';
import 'icon_finder.dart';
import 'multiview_fakes.dart';

/// The multiview page (spec/modules/multiview.md §2, §5, §9, §10) on fake
/// engines and fake chats; storage is replaced, so the fake clock drives
/// everything.
void main() {
  late FakeDanmakuSource chats;
  late MemoryRoomVolumes volumes;
  late List<FakeEngine> engines;
  late List<bool> fullscreen;

  final follow = FollowedRoom(
    room: StoredRoom(
      ref: RoomRef('douyu', '7'),
      anchorName: '主播7',
      title: '标题7',
      updatedAt: DateTime(2026),
      lastState: LiveState.live,
    ),
    followedAt: DateTime(2026),
    order: 0,
  );

  /// Opens the page in a router (so leaving pops) at [size].
  Future<ProviderContainer> open(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    List<RoomRef> rooms = const [],
    bool danmakuEnabled = true,
    List<FollowedRoom>? follows,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    if (!danmakuEnabled) await tester.runAsync(() => store.settings.set(Settings.danmakuEnabled, false));
    chats = FakeDanmakuSource();
    volumes = MemoryRoomVolumes();
    engines = [];
    fullscreen = [];
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: TextButton(onPressed: () => context.push('/multiview'), child: const Text('首页')),
          ),
        ),
        GoRoute(
          path: '/multiview',
          builder: (context, state) => MultiviewPage(rooms: rooms),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          sitesProvider.overrideWithValue({'douyu': PlatformSite(FakeSite('douyu'))}),
          engineFactoryProvider.overrideWithValue(() {
            final engine = FakeEngine();
            engines.add(engine);
            return engine;
          }),
          networkKindProvider.overrideWith((ref) => Stream.value(NetworkKind.unmetered)),
          danmakuSourceProvider.overrideWithValue(chats),
          blockRulesProvider.overrideWith((ref) => Stream.value(const [])),
          roomVolumesProvider.overrideWithValue(volumes),
          followsProvider.overrideWith((ref) => Stream.value(follows ?? [follow])),
          historyProvider.overrideWith((ref) => Stream.value(const [])),
          multiviewSystemFullscreenProvider.overrideWithValue(
            ({required enabled, required phone}) async => fullscreen.add(enabled),
          ),
        ],
        child: MaterialApp.router(theme: PureTheme.of(Appearance.light), routerConfig: router),
      ),
    );
    unawaited(router.push('/multiview'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return ProviderScope.containerOf(tester.element(find.byType(MultiviewPage)));
  }

  MultiviewState stateOf(ProviderContainer container) => container.read(multiviewProvider);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Finder cellAt(int index) => find.byWidgetPredicate((widget) => widget is MultiviewCellView && widget.index == index);

  group('picker (F-MV-02, LYT-7, CEL-4)', () {
    testWidgets('wide windows keep a side panel; a free cell only becomes the target, a pick fills it', (tester) async {
      final container = await open(tester);
      expect(find.byType(MultiviewRoomPicker), findsOneWidget);
      expect(find.text('选择直播间 · 放到第 1 格'), findsOneWidget);

      await tester.tap(find.descendant(of: cellAt(2), matching: find.text('添加直播间')));
      await settle(tester);
      expect(find.byType(BottomSheet), findsNothing, reason: 'no sheet next to the panel');
      expect(stateOf(container).target, 2);
      expect(find.text('选择直播间 · 放到第 3 格'), findsOneWidget);

      await tester.tap(find.text('主播7'));
      await settle(tester);
      expect(stateOf(container).cells[2].room, RoomRef('douyu', '7'));
      expect(stateOf(container).cells[2].status, CellStatus.playing);
      expect(stateOf(container).target, 3, reason: 'the target moved on to the next free cell');
      await close(tester);
    });

    testWidgets('a row ends with its state only: 直播 or 未开播, never the platform (the logo says it)', (tester) async {
      final offline = FollowedRoom(
        room: StoredRoom(
          ref: RoomRef('douyu', '8'),
          anchorName: '主播8',
          title: '标题8',
          updatedAt: DateTime(2026),
          lastState: LiveState.offline,
        ),
        followedAt: DateTime(2026),
        order: 1,
      );
      await open(tester, follows: [follow, offline]);
      ListTile row(String name) =>
          tester.widget<ListTile>(find.ancestor(of: find.text(name), matching: find.byType(ListTile)));
      expect(row('主播7').trailing, isA<LiveBadge>());
      expect((row('主播8').trailing! as Text).data, '未开播', reason: 'it said 斗鱼 here');
      expect(find.text('斗鱼'), findsNothing);
      await close(tester);
    });

    testWidgets('AUD-4: the pick target has a text badge; on the sound-focus cell both marks show', (tester) async {
      final container = await open(tester, rooms: [RoomRef('douyu', '1')]);
      await settle(tester);
      final scheme = Theme.of(tester.element(cellAt(0))).colorScheme;
      Iterable<Color> borders(int index) => tester
          .widgetList<DecoratedBox>(find.descendant(of: cellAt(index), matching: find.byType(DecoratedBox)))
          .map((box) => box.decoration)
          .whereType<BoxDecoration>()
          .map((decoration) => decoration.border)
          .whereType<Border>()
          .map((border) => border.top.color);
      Finder badge(int index) =>
          find.descendant(of: cellAt(index), matching: find.byKey(const ValueKey('multiview-target')));

      // Cell 1 is free and the target: tertiary border and the words.
      expect(stateOf(container).target, 1);
      expect(badge(1), findsOneWidget);
      expect(find.descendant(of: badge(1), matching: find.text('放到这里')), findsOneWidget);
      expect(borders(1), contains(scheme.tertiary));
      expect(borders(2), isEmpty, reason: 'no 1 px lines between cells: the 2 dp black gap parts them');

      // The panel's picks now go to the playing cell with the sound: it was
      // drawn with the focus border only, and the target vanished.
      container.read(multiviewProvider.notifier).setTarget(0);
      await settle(tester);
      expect(stateOf(container).audioFocus, 0);
      expect(badge(0), findsOneWidget);
      expect(borders(0), containsAll([scheme.primary, scheme.tertiary]));
      expect(find.text('选择直播间 · 放到第 1 格'), findsOneWidget);

      final first = tester.getRect(cellAt(0));
      final second = tester.getRect(cellAt(1));
      expect(second.left - first.right, 2, reason: 'principles §7 rule 4: a 2 dp gap');
      await close(tester);
    });

    testWidgets('compact windows pick in a bottom sheet', (tester) async {
      final container = await open(tester, size: const Size(393, 852));
      expect(stateOf(container).layout, MultiviewLayout.two, reason: 'phones start with 1×2 (ENT-3)');
      expect(find.byType(MultiviewRoomPicker), findsNothing);
      await tester.tap(find.descendant(of: cellAt(1), matching: find.text('添加直播间')));
      await settle(tester);
      expect(find.byType(MultiviewRoomPicker), findsOneWidget);
      await tester.tap(find.text('主播7'));
      await settle(tester);
      expect(find.byType(MultiviewRoomPicker), findsNothing);
      expect(stateOf(container).cells[1].room, RoomRef('douyu', '7'));
      await close(tester);
    });

    testWidgets('ENT-3: rooms brought along that 1×2 cannot show open 2×2 on a phone, in their order', (tester) async {
      final rooms = [
        for (final id in ['3', '1', '2']) RoomRef('douyu', id),
      ];
      final container = await open(tester, size: const Size(393, 852), rooms: rooms);
      expect(stateOf(container).layout, MultiviewLayout.four);
      expect([for (final cell in stateOf(container).cells) cell.room], [...rooms, null]);
      await close(tester);
    });

    testWidgets('ENT-3: rooms beyond what the window shows are left out, never put in hidden cells', (tester) async {
      final rooms = [for (var i = 1; i <= 6; i++) RoomRef('douyu', '$i')];
      final container = await open(tester, size: const Size(393, 852), rooms: rooms);
      expect(stateOf(container).layout, MultiviewLayout.four);
      expect([for (final cell in stateOf(container).cells) cell.room], rooms.take(4));
      await close(tester);
    });
  });

  testWidgets('the cell menu pauses and resumes; the volume panel sets and stores the volume (F-MV-03, F-MV-04)', (
    tester,
  ) async {
    final container = await open(tester, rooms: [RoomRef('douyu', '1'), RoomRef('douyu', '2')]);
    expect(stateOf(container).cells.map((c) => c.status).take(2), everyElement(CellStatus.playing));
    final focus = stateOf(container).audioFocus;

    await tester.longPress(cellAt(focus));
    await settle(tester);
    for (final item in ['换房', '暂停', '画质', '音量', '刷新', '关闭']) {
      expect(find.text(item), findsOneWidget, reason: item);
    }
    await tester.tap(find.text('暂停'));
    await settle(tester);
    expect(stateOf(container).cells[focus].paused, isTrue);
    expect(stateOf(container).cells[focus].session!.state.phase, PlaybackPhase.paused);
    expect(find.descendant(of: cellAt(focus), matching: findIcon(LiveIcons.paused)), findsOneWidget);

    await tester.longPress(cellAt(focus));
    await settle(tester);
    await tester.tap(find.text('继续'));
    await settle(tester);
    expect(stateOf(container).cells[focus].paused, isFalse);

    await tester.tap(find.byTooltip('所选画面音量'));
    await settle(tester);
    await tester.drag(find.byType(Slider), const Offset(-2000, 0));
    await settle(tester);
    final room = stateOf(container).cells[focus].room!;
    expect(volumes.stored[room], 0, reason: 'stored for the room when the drag ends');
    expect(engines[focus].volume, 0);
    await close(tester);
  });

  group('danmaku (F-MV-05)', () {
    testWidgets('the page switch connects the selected cell only and draws there; focus moves it', (tester) async {
      final container = await open(tester, rooms: [RoomRef('douyu', '1'), RoomRef('douyu', '2')]);
      expect(chats.feeds, isEmpty);
      expect(find.byType(DanmakuView), findsNothing);
      await tester.tap(find.byTooltip('开启弹幕'));
      await settle(tester);
      final focus = stateOf(container).audioFocus;
      expect(chats.feeds.single.room.ref, stateOf(container).cells[focus].room);
      expect(find.descendant(of: cellAt(focus), matching: find.byType(DanmakuView)), findsOneWidget);

      final other = 1 - focus;
      await tester.sendKeyEvent(other == 0 ? LogicalKeyboardKey.digit1 : LogicalKeyboardKey.digit2);
      await settle(tester);
      expect(stateOf(container).audioFocus, other);
      expect(chats.feeds.first.closed, isTrue);
      expect(chats.feeds.last.room.ref, stateOf(container).cells[other].room);
      expect(find.descendant(of: cellAt(other), matching: find.byType(DanmakuView)), findsOneWidget);
      expect(find.byType(DanmakuView), findsOneWidget);
      await close(tester);
    });

    testWidgets('no switch while "显示弹幕" is off (F-DM-01)', (tester) async {
      await open(tester, rooms: [RoomRef('douyu', '1')], danmakuEnabled: false);
      expect(find.byTooltip('开启弹幕'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await settle(tester);
      expect(chats.feeds, isEmpty);
      await close(tester);
    });
  });

  group('display modes (F-MV-07, OPS-5, EXT-1, EXT-3)', () {
    testWidgets('immersive hides the bars and the panel; its button and Esc bring them back', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('沉浸模式'));
      await settle(tester);
      expect(find.text('多画面'), findsNothing);
      expect(find.byTooltip('布局'), findsNothing);
      expect(find.byType(MultiviewRoomPicker), findsNothing, reason: 'no panel outside normal mode');
      expect(fullscreen, isEmpty, reason: 'immersive leaves the system UI alone');
      await tester.tap(find.byTooltip('退出沉浸模式'));
      await settle(tester);
      expect(find.text('多画面'), findsOneWidget);

      await tester.tap(find.byTooltip('沉浸模式'));
      await settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.text('多画面'), findsOneWidget, reason: 'Esc returns to normal before leaving');
      expect(find.byType(MultiviewPage), findsOneWidget);
      await close(tester);
    });

    testWidgets('fullscreen asks the system; back and F leave it; removal restores it', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('全屏'));
      await settle(tester);
      expect(fullscreen, [true]);
      expect(find.byTooltip('退出全屏'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(fullscreen, [true, false]);
      expect(find.text('多画面'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await settle(tester);
      expect(fullscreen, [true, false, true]);
      await close(tester);
      expect(fullscreen, [true, false, true, false], reason: 'EXT-3: destroyed in fullscreen');
    });

    testWidgets('back in normal mode empties the cells and leaves (EXT-2)', (tester) async {
      final container = await open(tester, rooms: [RoomRef('douyu', '1')]);
      expect(stateOf(container).cells.first.status, CellStatus.playing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(LiveVideoView), findsNothing, reason: 'videos unmount before the pop');
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(MultiviewPage), findsNothing);
      expect(find.text('首页'), findsOneWidget);
      expect(engines.single.disposed, isTrue);
      await close(tester);
    });
  });

  testWidgets('keys: 1–9 move the sound, M mutes all, Space pauses the selected cell, D flips danmaku (AUD-5)', (
    tester,
  ) async {
    final container = await open(tester, rooms: [RoomRef('douyu', '1'), RoomRef('douyu', '2')]);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(stateOf(container).audioFocus, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(stateOf(container).muteAll, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(stateOf(container).cells[0].paused, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await settle(tester);
    expect(stateOf(container).danmaku, isTrue);
    expect(chats.feeds, hasLength(1));
    await close(tester);
  });

  testWidgets('1+N: a tap on the big cell shows its bar; a small cell is promoted and the bar resets (OPS-1, OPS-3)', (
    tester,
  ) async {
    final container = await open(tester, rooms: [RoomRef('douyu', '1'), RoomRef('douyu', '2')]);
    await tester.tap(find.byTooltip('布局'));
    await settle(tester);
    await tester.tap(find.widgetWithText(CheckedMenuItem<MultiviewLayout>, '一大多小'));
    await settle(tester);
    final state = stateOf(container);
    expect(state.layout, MultiviewLayout.onePlusN);
    expect(state.big, state.audioFocus, reason: 'LYT-4: the big cell is the sound focus');

    await tester.tap(cellAt(state.big));
    await settle(tester);
    expect(find.byType(MultiviewControlBar), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(MultiviewControlBar), matching: find.byTooltip('暂停')));
    await settle(tester);
    expect(stateOf(container).cells[state.big].paused, isTrue);

    final small = 1 - state.big;
    await tester.tap(cellAt(small));
    await settle(tester);
    expect(stateOf(container).big, small);
    expect(find.byType(MultiviewControlBar), findsNothing);
    await close(tester);
  });

  testWidgets('1+N at the capacity: adding says why (LYT-1)', (tester) async {
    final container = await open(tester);
    container.read(multiviewProvider.notifier).setLayout(MultiviewLayout.onePlusN);
    await settle(tester);
    while (container.read(multiviewProvider.notifier).canAddCell) {
      await tester.tap(find.byTooltip('添加画面'));
      await tester.pump();
    }
    expect(stateOf(container).cells, hasLength(multiviewCapacity()));
    await tester.tap(findIcon(LiveIcons.add));
    await settle(tester);
    expect(find.textContaining('最多同时播放'), findsOneWidget);
    await close(tester);
  });

  testWidgets('an opaque page on top suspends every cell but the sound focus (RS-3)', (tester) async {
    final container = await open(tester, rooms: [RoomRef('douyu', '1'), RoomRef('douyu', '2')]);
    final state = stateOf(container);
    final other = 1 - state.audioFocus;
    final navigator = Navigator.of(tester.element(find.byType(MultiviewPage)))
      ..push(MaterialPageRoute<void>(builder: (context) => const Scaffold(body: Text('上层'))));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.cells[other].session!.state.phase, PlaybackPhase.suspended);
    expect(state.cells[state.audioFocus].session!.state.phase, isNot(PlaybackPhase.suspended));
    navigator.pop();
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.cells[other].session!.state.phase, isNot(PlaybackPhase.suspended));
    await close(tester);
  });
}
