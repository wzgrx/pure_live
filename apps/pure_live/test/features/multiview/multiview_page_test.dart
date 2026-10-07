// docs/A-界面设计/A13-网络电视和多画面界面/A13.2-多画面: the multi-view page in portrait, landscape and wide
// windows; the order, icons and places of its controls; the cells' states;
// UI_PLAN appendix A 7 (Back and Esc) and 13 (tap, 1+3, long press, empty
// cells).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/multiview/multiview_page.dart';
import 'package:pure_live/features/multiview/widgets/cell_view.dart';
import 'package:pure_live/features/multiview/widgets/toolbar.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';

import '../../support.dart';
import '../live_play/live_play_support.dart';
import 'multiview_support.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

Future<(AppServices, RoomsSite)> _pump(
  WidgetTester tester,
  Size size, {
  List<String> rooms = const ['1', '2', '3'],
  ThemeMode theme = ThemeMode.light,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(testServices))!;
  await tester.runAsync(loadStrings);
  await tester.runAsync(() async {
    for (final id in rooms) {
      await services.store.follows.add(pickRoom(id));
    }
  });
  final site = RoomsSite();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        sitesProvider.overrideWithValue(SiteRegistry({SiteIds.bilibili: () => site})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: FakeDanmaku.new})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(FakeEngine())),
      ],
      child: MaterialApp(
        theme: const LiveTheme().light,
        darkTheme: const LiveTheme().dark,
        themeMode: theme,
        home: const MultiviewPage(route: RouteArgs(RoutePath.kMultiview)),
      ),
    ),
  );
  await _wait(tester);
  return (services, site);
}

Future<void> _wait(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

Future<void> _pick(WidgetTester tester, String id) async {
  await tester.ensureVisible(_key('multiview-pick-bilibili:$id'));
  await tester.tap(_key('multiview-pick-bilibili:$id'));
  await _wait(tester);
}

Future<void> _close(WidgetTester tester, AppServices services) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(services.close);
}

Finder _inCell(int position, Finder finder) => find.descendant(of: _key('multiview-cell-$position'), matching: finder);

MultiviewCellView _cellView(WidgetTester tester, int position) => tester.widget<MultiviewCellView>(
  find.ancestor(of: _key('multiview-cell-$position'), matching: find.byType(MultiviewCellView)),
);

void _expectLeftToRight(WidgetTester tester, List<String> keys) {
  for (var i = 1; i < keys.length; i++) {
    expect(tester.getCenter(_key(keys[i])).dx, greaterThan(tester.getCenter(_key(keys[i - 1])).dx), reason: keys[i]);
  }
}

void main() {
  late List<String> toasts;
  setUp(() {
    toasts = [];
    AppNavigator.toast = toasts.add;
  });

  testWidgets('portrait: toolbar, 16:9 cells above, the selected cell and the picker below', (tester) async {
    final (services, _) = await _pump(tester, const Size(393, 852));
    expect(find.text('多画面'), findsOneWidget);

    // c10: one row; the words alone on a phone; the live room's danmaku
    // pictures; no saver outside 1+3.
    _expectLeftToRight(tester, [
      'multiview-layout-single',
      'multiview-layout-dual',
      'multiview-layout-quad',
      'multiview-layout-focus',
      'multiview-danmaku',
      'multiview-danmaku-settings',
      'multiview-mute-all',
    ]);
    expect(tester.getCenter(_key('multiview-layout-single')).dy, tester.getCenter(_key('multiview-mute-all')).dy);
    expect(find.descendant(of: _key('multiview-layouts'), matching: find.byType(Icon)), findsNothing);
    expect(
      tester
          .widget<DanmakuIcon>(find.descendant(of: _key('multiview-danmaku'), matching: find.byType(DanmakuIcon)))
          .kind,
      DanmakuIconKind.off,
    );
    expect(
      tester
          .widget<DanmakuIcon>(
            find.descendant(of: _key('multiview-danmaku-settings'), matching: find.byType(DanmakuIcon)),
          )
          .kind,
      DanmakuIconKind.settings,
    );
    expect(find.descendant(of: _key('multiview-mute-all'), matching: find.byIcon(AppIcons.muteAll)), findsOneWidget);
    expect(_key('multiview-saver'), findsNothing);

    // c2, c6, c7: numbered 16:9 cells in a 2×2 wall, black in a light theme;
    // the first empty cell is the picker's target.
    for (var position = 1; position <= 4; position++) {
      final size = tester.getSize(_key('multiview-cell-$position'));
      expect(size.width / size.height, moreOrLessEquals(16 / 9, epsilon: 0.02));
      expect(_key('multiview-cell-number-$position'), findsOneWidget);
    }
    expect(tester.getTopLeft(_key('multiview-cell-2')).dx, greaterThan(tester.getTopLeft(_key('multiview-cell-1')).dx));
    expect(tester.getTopLeft(_key('multiview-cell-3')).dy, greaterThan(tester.getTopLeft(_key('multiview-cell-1')).dy));
    final ground = tester.widget<ColoredBox>(
      find.ancestor(of: _key('multiview-cell-4'), matching: find.byType(ColoredBox)).first,
    );
    expect(ground.color, OnVideoColors.ground);
    expect(_inCell(1, find.text('正在为这一格选台')), findsOneWidget);
    expect(_inCell(1, _key('multiview-pick-frame')), findsOneWidget);
    expect(find.text('点击选台'), findsNWidgets(3));
    expect(find.text('为第 1 格选台'), findsOneWidget);
    expect(find.text('点直播间放进这一格'), findsOneWidget);
    expect(
      tester.getTopLeft(_key('multiview-picker-title')).dy,
      greaterThan(tester.getBottomLeft(_key('multiview-cell-3')).dy),
    );

    // Picking fills the cell, the next empty one becomes the target.
    await _pick(tester, '1');
    expect(_inCell(1, find.text('主播1')), findsOneWidget);
    expect(_inCell(1, _key('multiview-audio-badge')), findsOneWidget);
    expect(_inCell(1, _key('multiview-audio-outline')), findsOneWidget);
    expect(_inCell(1, find.text('声音来源')), findsOneWidget);
    expect(find.text('为第 2 格选台'), findsOneWidget);
    expect(_inCell(2, _key('multiview-pick-frame')), findsOneWidget);

    // c4: the selected cell's controls under the picture: the room, "原画 ⌄"
    // "线路1 ⌄" on its row; pause, refresh, change, open, close; the volume.
    expect(_key('multiview-cell-controls-1'), findsOneWidget);
    expect(find.descendant(of: _key('multiview-controls-number'), matching: find.text('1')), findsOneWidget);
    expect(find.text('哔哩哔哩 · 标题1'), findsOneWidget);
    _expectLeftToRight(tester, ['multiview-quality', 'multiview-line']);
    expect(find.descendant(of: _key('multiview-quality'), matching: find.text('原画')), findsOneWidget);
    expect(find.descendant(of: _key('multiview-line'), matching: find.text('线路1')), findsOneWidget);
    final buttons = [
      'multiview-control-play',
      'multiview-control-refresh',
      'multiview-control-change',
      'multiview-control-room',
      'multiview-control-close',
    ];
    _expectLeftToRight(tester, [...buttons, 'multiview-volume-slider']);
    final icons = [
      AppIcons.cellPause,
      AppIcons.cellRefresh,
      AppIcons.changeRoom,
      AppIcons.enterRoom,
      AppIcons.closeCell,
    ];
    for (final (index, key) in buttons.indexed) {
      expect(
        find.descendant(of: _key(key), matching: find.byIcon(icons[index])),
        findsOneWidget,
        reason: key,
      );
    }
    expect(tester.getCenter(_key('multiview-quality')).dy, lessThan(tester.getCenter(_key(buttons.first)).dy));
    expect(
      tester.getBottomLeft(_key('multiview-cell-controls-1')).dy,
      lessThan(tester.getTopLeft(_key('multiview-picker-title')).dy),
    );

    // W4: a room in a cell is marked, listed last, and selects its cell.
    expect(_key('multiview-shown-bilibili:1'), findsOneWidget);
    expect(
      tester.getTopLeft(_key('multiview-pick-bilibili:1')).dy,
      greaterThan(tester.getTopLeft(_key('multiview-pick-bilibili:3')).dy),
    );
    await _pick(tester, '1');
    expect(toasts, ['这个直播间已在第 1 格播放']);
    expect(_inCell(2, find.text('点击选台')), findsNothing, reason: 'still the target');

    // A 13: the new cell takes the sound; a tap gives it back; a long press
    // shows a cell's controls without moving the sound.
    await _pick(tester, '2');
    expect(_inCell(2, _key('multiview-audio-badge')), findsOneWidget);
    expect(_key('multiview-cell-controls-2'), findsOneWidget);
    await tester.tap(_key('multiview-cell-1'));
    await _wait(tester);
    expect(_inCell(1, _key('multiview-audio-badge')), findsOneWidget);
    expect(_inCell(2, _key('multiview-audio-badge')), findsNothing);
    expect(_key('multiview-cell-controls-1'), findsOneWidget);
    await tester.longPress(_key('multiview-cell-2'));
    await _wait(tester);
    expect(_key('multiview-cell-controls-2'), findsOneWidget);
    expect(_inCell(1, _key('multiview-audio-badge')), findsOneWidget);

    // U.2f's quality menu.
    await tester.tap(_key('multiview-quality'));
    await tester.pumpAndSettle();
    expect(_key('multiview-quality-item-1'), findsOneWidget);
    expect(
      tester.getTopLeft(_key('multiview-quality-item-0')).dy,
      greaterThan(tester.getBottomLeft(_key('multiview-quality')).dy),
    );
    await tester.tap(_key('multiview-quality-item-1'));
    await tester.pumpAndSettle();
    await _wait(tester);
    expect(find.descendant(of: _key('multiview-quality'), matching: find.text('超清')), findsOneWidget);

    // c8: a paused cell says so; the button plays it again.
    await tester.tap(_key('multiview-control-play'));
    await _wait(tester);
    expect(_inCell(2, _key('multiview-paused')), findsOneWidget);
    expect(_inCell(2, find.text('已暂停')), findsOneWidget);
    expect(
      find.descendant(of: _key('multiview-control-play'), matching: find.byIcon(AppIcons.cellPlay)),
      findsOneWidget,
    );

    // 换台 makes the cell the target; 关闭这一格 empties it.
    await tester.tap(_key('multiview-control-change'));
    await _wait(tester);
    expect(find.text('第 2 格换台'), findsOneWidget);
    expect(find.text('点直播间换掉“主播2”'), findsOneWidget);
    await tester.tap(_key('multiview-control-close'));
    await _wait(tester);
    expect(_inCell(2, find.text('主播2')), findsNothing);
    expect(_key('multiview-cell-controls-1'), findsOneWidget, reason: 'back to the audible cell');

    // c11: the danmaku settings under the picture, U.2f's content.
    await tester.tap(_key('multiview-danmaku-settings'));
    await tester.pumpAndSettle();
    final panel = tester.getRect(_key('multiview-danmaku-panel'));
    expect(panel.top, greaterThanOrEqualTo(tester.getBottomLeft(_key('multiview-cell-4')).dy));
    expect(panel.bottom, 852);
    expect(find.text('只在声音来源这一格显示 · 改动立即生效'), findsOneWidget);
    expect(find.text('观看模板'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_key('multiview-danmaku-panel'), findsNothing, reason: 'Back closes the panel first');
    expect(find.text('多画面'), findsOneWidget);

    // c12: immersive: the cells alone, the exit in the top-left corner; Back
    // returns (A 7).
    await tester.tap(_key('multiview-immersive'));
    await tester.pump();
    expect(find.text('多画面'), findsNothing);
    expect(tester.getTopLeft(_key('multiview-immersive-exit')), const Offset(12, 12));
    expect(
      find.descendant(of: _key('multiview-immersive-exit'), matching: find.byIcon(AppIcons.exitImmersive)),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('多画面'), findsOneWidget);

    await _close(tester, services);
  });

  testWidgets('B02 c3: the danmaku stand while their cell is paused, or fly on as "暂停时的弹幕" says', (tester) async {
    final (services, _) = await _pump(tester, const Size(393, 852));
    await _pick(tester, '1');
    await tester.tap(_key('multiview-danmaku'));
    await _wait(tester);
    DanmakuOverlay overlay() => tester.widget<DanmakuOverlay>(_inCell(1, find.byType(DanmakuOverlay)));
    expect(overlay().running, isTrue);
    await tester.tap(_key('multiview-control-play'));
    await _wait(tester);
    expect(_inCell(1, _key('multiview-paused')), findsOneWidget);
    expect(overlay().running, isFalse, reason: 'with the video, the default');
    await tester.runAsync(() => services.store.settings.set(Settings.danmakuPausedBehavior, 'continue'));
    await _wait(tester);
    expect(overlay().running, isTrue);
    await tester.tap(_key('multiview-control-play'));
    await _wait(tester);
    expect(overlay().running, isTrue);
    await _close(tester, services);
  });

  testWidgets('tap targets (UI_PLAN 5.4): 48 around the 40 buttons and the 38 switches in every arrangement', (
    tester,
  ) async {
    const toggles = ['multiview-danmaku', 'multiview-danmaku-settings', 'multiview-mute-all'];
    const buttons = [
      'multiview-control-play',
      'multiview-control-refresh',
      'multiview-control-change',
      'multiview-control-room',
      'multiview-control-close',
    ];
    Rect circle(String key) => tester.getRect(find.descendant(of: _key(key), matching: find.byType(Material)).first);
    // Each 48 square around its circle, side by side without overlapping,
    // on one row.
    void expectTargets(List<String> keys, double visible) {
      for (final (index, key) in keys.indexed) {
        final target = tester.getRect(_key(key));
        expect(target.size, const Size.square(48), reason: key);
        expect(circle(key).size, Size.square(visible), reason: key);
        expect(circle(key).center, target.center, reason: key);
        if (index == 0) continue;
        final previous = tester.getRect(_key(keys[index - 1]));
        expect(target.left, greaterThanOrEqualTo(previous.right), reason: key);
        expect(target.center.dy, previous.center.dy, reason: key);
      }
    }

    // Narrower segments where the row is short (the words then keep about
    // their size: each segment 48 instead of 56 with a phone's font).
    bool dense() => tester.widget<LayoutSegments>(find.byType(LayoutSegments)).dense;

    // Portrait 393: the circles where they were (12 in, 8 from the end, the
    // toolbar 56 high), the volume after the buttons.
    var (services, _) = await _pump(tester, const Size(393, 852));
    await _pick(tester, '1');
    expectTargets(toggles, 38);
    expectTargets(buttons, 40);
    expect(circle(buttons.first).left, 12);
    expect(circle(toggles.last).right, 393 - 8);
    expect(tester.getSize(_key('multiview-toolbar')).height, 56);
    expect(dense(), isFalse);
    expect(tester.getCenter(_key('multiview-volume-slider')).dy, tester.getCenter(_key(buttons.first)).dy);
    expect(tester.getRect(_key('multiview-volume-slider')).left - circle(buttons.last).right, greaterThanOrEqualTo(8));
    // A tap between the circle and the target's edge counts.
    await tester.tapAt(tester.getRect(_key('multiview-mute-all')).centerLeft + const Offset(2, 0));
    await _wait(tester);
    expect(find.descendant(of: _key('multiview-mute-all'), matching: find.byIcon(AppIcons.mutedAll)), findsOneWidget);
    await tester.tapAt(tester.getRect(_key('multiview-control-play')).topLeft + const Offset(2, 2));
    await _wait(tester);
    expect(_inCell(1, _key('multiview-paused')), findsOneWidget);

    // 1+3: the saver's target too, so narrower segments.
    await tester.tap(_key('multiview-layout-focus'));
    await _wait(tester);
    expectTargets([...toggles, 'multiview-saver'], 38);
    expect(dense(), isTrue);
    await _close(tester, services);

    // Portrait 360: the volume takes a row of its own rather than a slider
    // too short to use; narrower segments.
    (services, _) = await _pump(tester, const Size(360, 780));
    await _pick(tester, '1');
    expectTargets(toggles, 38);
    expectTargets(buttons, 40);
    expect(dense(), isTrue);
    expect(
      tester.getRect(_key('multiview-volume-slider')).top,
      greaterThan(tester.getRect(_key(buttons.first)).bottom),
    );
    await _close(tester, services);

    // A narrow landscape phone: the column fits the five targets on a row.
    (services, _) = await _pump(tester, const Size(740, 360));
    await _pick(tester, '1');
    await tester.tap(_key('multiview-cell-1'));
    await _wait(tester);
    final column = tester.getRect(_key('multiview-column'));
    expect(column.width, 256);
    expectTargets(toggles, 38);
    expectTargets(buttons, 40);
    expect(circle(buttons.first).left, column.left + 12);
    expect(tester.getRect(_key(buttons.last)).right, lessThanOrEqualTo(column.right));
    await _close(tester, services);

    // Wide: the same targets; the last circle 16 from the end as before.
    (services, _) = await _pump(tester, const Size(1280, 800));
    await _pick(tester, '1');
    expectTargets(toggles, 38);
    expectTargets(buttons, 40);
    expect(circle(toggles.last).right, 1280 - 16);
    await _close(tester, services);
  });

  testWidgets('portrait 1+3: the large cell above, three small ones in a row; the saver marks them', (tester) async {
    final (services, _) = await _pump(tester, const Size(393, 852));
    await _pick(tester, '1');
    await _pick(tester, '2');
    await _pick(tester, '3');
    await tester.tap(_key('multiview-layout-focus'));
    await _wait(tester);
    _expectLeftToRight(tester, ['multiview-mute-all', 'multiview-saver']);
    final large = tester.getRect(_key('multiview-cell-3'));
    expect(large.width, moreOrLessEquals(393 - 6, epsilon: 1));
    for (final position in [1, 2, 4]) {
      final small = tester.getRect(_key('multiview-cell-$position'));
      expect(small.top, greaterThan(large.bottom));
      expect(small.width / small.height, moreOrLessEquals(16 / 9, epsilon: 0.02));
    }
    _expectLeftToRight(tester, ['multiview-cell-1', 'multiview-cell-2', 'multiview-cell-4']);
    // W3: no control bar on the large cell outside immersive and fullscreen.
    await tester.tap(_key('multiview-cell-3'));
    await _wait(tester);
    expect(_key('multiview-control-bar'), findsNothing);

    await tester.tap(_key('multiview-saver'));
    await _wait(tester);
    expect(_key('multiview-saver-mark'), findsNWidgets(2));
    expect(_inCell(3, _key('multiview-saver-mark')), findsNothing);

    // A 13: a tap on a small cell makes it the large one.
    await tester.tap(_key('multiview-cell-1'));
    await _wait(tester);
    expect(tester.getRect(_key('multiview-cell-1')).width, moreOrLessEquals(393 - 6, epsilon: 1));
    expect(_inCell(1, _key('multiview-audio-badge')), findsOneWidget);

    // No cell decodes video while the app is out of sight (UI_PLAN §9.3).
    expect(_cellView(tester, 1).cell.offscreen, isFalse);
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await _wait(tester);
    for (final position in [1, 2, 3, 4]) {
      expect(_cellView(tester, position).cell.offscreen, isTrue);
    }
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _wait(tester);
    expect(_cellView(tester, 1).cell.offscreen, isFalse);
    expect(_cellView(tester, 1).cell.session!.state.audioOnly, isFalse);
    await _close(tester, services);
  });

  testWidgets('A01.4 c5: a small empty cell says "点击选台" at 12 with a 20 icon, not shrunk to fit', (tester) async {
    final (services, _) = await _pump(tester, const Size(393, 852));
    await tester.tap(_key('multiview-layout-focus'));
    await _wait(tester);
    final hints = find.byKey(const ValueKey('multiview-cell-hint'));
    expect(hints, findsNWidgets(3));
    for (final hint in hints.evaluate()) {
      final text = hint.widget as Text;
      expect(text.style!.fontSize, 12);
      // Drawn at its size: nothing scales it down.
      expect(tester.getSize(find.byWidget(text)).height, greaterThanOrEqualTo(12));
    }
    expect(find.text('点击选台'), findsNWidgets(3));
    final icons = find.descendant(of: _key('multiview-cell-2'), matching: find.byIcon(AppIcons.addCell));
    expect(tester.getSize(icons).width, 20);
    await _close(tester, services);
  });

  testWidgets('landscape phone: toolbar in the app bar, the column on the right, the picker in turn', (tester) async {
    final (services, _) = await _pump(tester, const Size(852, 393));
    // c10: the toolbar joins the app bar.
    expect(find.descendant(of: find.byType(AppBar), matching: _key('multiview-layouts')), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: _key('multiview-mute-all')), findsOneWidget);
    _expectLeftToRight(tester, [
      'multiview-layouts',
      'multiview-mute-all',
      'multiview-immersive',
      'multiview-fullscreen',
    ]);

    final column = tester.getRect(_key('multiview-column'));
    expect(column.left, greaterThanOrEqualTo(tester.getRect(_key('multiview-cell-2')).right));
    expect(column.right, 852);
    expect(column.width, inInclusiveRange(240, 360));
    expect(find.text('为第 1 格选台'), findsOneWidget);
    expect(_key('multiview-picker-close'), findsNothing, reason: 'nothing to go back to');

    // Picking goes on while cells are empty.
    await _pick(tester, '1');
    expect(find.text('为第 2 格选台'), findsOneWidget);
    expect(_key('multiview-picker-close'), findsOneWidget);
    // A tap on a playing cell shows its controls.
    await tester.tap(_key('multiview-cell-1'));
    await _wait(tester);
    expect(_key('multiview-cell-controls-1'), findsOneWidget);
    expect(_key('multiview-picker-title'), findsNothing);
    // Compact: the quality and line on a row of their own, under the room.
    expect(tester.getCenter(_key('multiview-quality')).dy, greaterThan(tester.getCenter(find.text('主播1').last).dy));

    // An empty cell: the picker in the column, ✕ and Back return.
    await tester.tap(_key('multiview-cell-4'));
    await _wait(tester);
    expect(find.text('为第 4 格选台'), findsOneWidget);
    expect(_inCell(4, _key('multiview-pick-frame')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _wait(tester);
    expect(_key('multiview-cell-controls-1'), findsOneWidget);
    expect(_inCell(4, _key('multiview-pick-frame')), findsNothing);

    // 22: the column folds away and back.
    await tester.tap(_key('multiview-fold'));
    await _wait(tester);
    expect(_key('multiview-column'), findsNothing);
    expect(find.descendant(of: _key('multiview-fold'), matching: find.byIcon(AppIcons.unfoldLeft)), findsOneWidget);
    await tester.tap(_key('multiview-fold'));
    await _wait(tester);
    expect(_key('multiview-column'), findsOneWidget);

    // c12, c13: fullscreen; the same exit place; a long press opens the
    // cell's panel on the right; Esc closes it, then leaves.
    await tester.tap(_key('multiview-fullscreen'));
    await _wait(tester);
    expect(tester.getTopLeft(_key('multiview-fullscreen-exit')), const Offset(12, 12));
    expect(
      tester.getTopLeft(_key('multiview-cell-1')).dx,
      greaterThan(12 + 48),
      reason: 'the exit button sits in the black side',
    );
    await tester.longPress(_key('multiview-cell-1'));
    await _wait(tester);
    final panel = tester.getRect(_key('multiview-cell-panel'));
    expect(panel, const Rect.fromLTRB(852 - 360, 0, 852, 393));
    expect(find.descendant(of: _key('multiview-cell-panel'), matching: find.text('第 1 格')), findsOneWidget);
    expect(
      find.descendant(of: _key('multiview-cell-panel'), matching: _key('multiview-control-close')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _wait(tester);
    expect(_key('multiview-cell-panel'), findsNothing);
    expect(_key('multiview-fullscreen-exit'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _wait(tester);
    expect(find.text('多画面'), findsOneWidget);
    await _close(tester, services);
  });

  testWidgets('wide: icons on the layouts, a 360 column; 1+3 grows; the large cell bar in fullscreen', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final processors = MultiviewPage.processors;
    MultiviewPage.processors = () => 8;
    addTearDown(() => MultiviewPage.processors = processors);
    final (services, _) = await _pump(tester, const Size(1280, 800));
    expect(find.descendant(of: _key('multiview-layouts'), matching: find.byIcon(AppIcons.layoutFocus)), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: _key('multiview-layouts')), findsNothing);
    final column = tester.getRect(_key('multiview-column'));
    expect(column.width, 360);
    expect(column.right, 1280);
    expect(find.text('为第 1 格选台'), findsOneWidget);

    await _pick(tester, '1');
    await _pick(tester, '2');
    // The controls above the picker in the same column.
    expect(
      tester.getBottomLeft(_key('multiview-cell-controls-2')).dy,
      lessThan(tester.getTopLeft(_key('multiview-picker-title')).dy),
    );
    expect(tester.getTopLeft(_key('multiview-cell-controls-2')).dx, greaterThanOrEqualTo(column.left));

    await tester.tap(_key('multiview-layout-focus'));
    await _wait(tester);
    // Desktops add cells up to their limit (3.x: 9).
    expect(_key('multiview-add-cell'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tester.ensureVisible(_key('multiview-add-cell'));
      await tester.tap(_key('multiview-add-cell'));
      await _wait(tester);
    }
    expect(_key('multiview-add-cell'), findsNothing);
    expect(_key('multiview-cell-9'), findsOneWidget);
    // Cells scrolled out of the rail decode no video (UI_PLAN §9.3).
    // The rail ends with cells 7 to 9 in sight; the large cell is cell 2.
    expect(_cellView(tester, 1).cell.offscreen, isTrue);
    expect(_cellView(tester, 6).cell.offscreen, isTrue);
    expect(_cellView(tester, 9).cell.offscreen, isFalse);
    expect(_cellView(tester, 2).cell.offscreen, isFalse);
    await tester.drag(_key('multiview-rail'), const Offset(2000, 0));
    await _wait(tester);
    expect(_cellView(tester, 1).cell.offscreen, isFalse);
    expect(_cellView(tester, 9).cell.offscreen, isTrue);

    await tester.tap(_key('multiview-fullscreen'));
    await _wait(tester);
    await tester.tap(_key('multiview-cell-2'));
    await _wait(tester);
    // c14: the large cell's bar, U.2f's quality and line buttons in it.
    _expectLeftToRight(tester, [
      'multiview-bar-play',
      'multiview-bar-refresh',
      'multiview-bar-danmaku',
      'multiview-bar-danmaku-settings',
      'multiview-bar-quality',
      'multiview-bar-line',
      'multiview-bar-volume',
      'multiview-bar-fullscreen',
    ]);
    await tester.tap(_key('multiview-bar-volume'));
    await _wait(tester);
    expect(_key('multiview-cell-panel'), findsOneWidget);
    expect(_key('multiview-volume-slider'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _wait(tester);
    await tester.tap(_key('multiview-bar-danmaku-settings'));
    await _wait(tester);
    expect(tester.getRect(_key('multiview-danmaku-panel')).width, 360);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _wait(tester);
    expect(find.text('多画面'), findsOneWidget);
    await _close(tester, services);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('cells: offline and failed say why on black in a dark theme', (tester) async {
    final (services, site) = await _pump(tester, const Size(393, 852), theme: ThemeMode.dark);
    site
      ..offline.add('2')
      ..failing.add('3');
    await _pick(tester, '2');
    expect(_inCell(1, find.text('该直播间未开播')), findsOneWidget);
    expect(_inCell(1, find.text('点击此格可重新选台')), findsOneWidget);
    expect(_inCell(1, find.byIcon(AppIcons.roomOffline)), findsOneWidget);
    await _pick(tester, '3');
    expect(_inCell(2, find.text('播放失败')), findsOneWidget);
    expect(_inCell(2, find.text('重试')), findsOneWidget);
    expect(tester.widget<Icon>(_inCell(2, find.byIcon(AppIcons.cellFailed))).color, OnVideoColors.error);
    // A 13: tapping an offline cell picks for it again.
    await tester.tap(_key('multiview-cell-1'));
    await _wait(tester);
    expect(find.text('第 1 格换台'), findsOneWidget);
    expect(_inCell(1, _key('multiview-pick-frame')), findsOneWidget);
    // Its controls are a long press away (close, refresh).
    await tester.longPress(_key('multiview-cell-2'));
    await _wait(tester);
    expect(_key('multiview-cell-controls-2'), findsOneWidget);
    site.failing.clear();
    await tester.tap(_key('multiview-control-refresh'));
    await _wait(tester);
    expect(_inCell(2, find.text('播放失败')), findsNothing);
    await _close(tester, services);
  });
}
