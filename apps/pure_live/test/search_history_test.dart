import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/rooms/card_marks.dart';
import 'package:pure_live_app/features/search/search_history.dart';
import 'package:pure_live_app/features/search/search_page.dart';

import 'fakes.dart';

/// spec/product.md F-SRC-06, principles §4.1: the recent searches under a
/// focused, empty search box.
void main() {
  late LiveStore store;

  Future<void> open(WidgetTester tester) async {
    store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
  }

  Future<void> settle(WidgetTester tester) async {
    // Store writes and the history stream complete outside the fake clock.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    await tester.pump();
  }

  /// Lets the snack bar with 撤销 slide in.
  Future<void> snackBar(WidgetTester tester) async {
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  Future<List<String>> stored(WidgetTester tester) async => [
    for (final entry in (await tester.runAsync(store.searchHistory.all))!) entry.keyword,
  ];

  Future<void> seed(WidgetTester tester, List<String> newestLast) => tester.runAsync(() async {
    for (final (index, keyword) in newestLast.indexed) {
      await store.searchHistory.record(keyword, at: DateTime.utc(2026, 9, 1, 0, index));
    }
  });

  Future<void> pumpSearch(WidgetTester tester, {Size size = const Size(393, 852)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final douyu = FakeSite(
      'douyu',
      pages: [
        Page([RoomCard(ref: RoomRef('douyu', 'd1'), title: '标题', anchorName: '主播d1', state: LiveState.live)]),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          sitesProvider.overrideWithValue({'douyu': PlatformSite(douyu)}),
          enabledPlatformsProvider.overrideWithValue(['douyu']),
          recordingRoomsProvider.overrideWith((ref) => Stream.value(const {})),
          linkResolverProvider.overrideWithValue((input) async => RoomRef('douyu', '288016')),
        ],
        child: MaterialApp(
          theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
          home: const SearchPage(),
        ),
      ),
    );
    await settle(tester);
  }

  /// Unmounts the app so the history stream's closing timer runs.
  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
  }

  Future<void> focusEmptyBox(WidgetTester tester) async {
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '');
    await settle(tester);
  }

  List<String> shown(WidgetTester tester) => [
    for (final tile in tester.widgetList<ListTile>(
      find.descendant(of: find.byType(SearchHistoryList), matching: find.byType(ListTile)),
    ))
      (tile.title! as Text).data!,
  ];

  testWidgets('keywords are remembered, newest first; links are not', (tester) async {
    await open(tester);
    await pumpSearch(tester);
    await search(tester, '英雄联盟');
    await search(tester, '原神');
    await search(tester, 'https://www.douyu.com/288016');
    await search(tester, '  英雄联盟 ');
    expect(await stored(tester), ['英雄联盟', '原神']);
    await done(tester);
  });

  testWidgets('a focused, empty box lists them; a tap searches again and moves it to the top', (tester) async {
    await open(tester);
    await seed(tester, ['英雄联盟', '原神', '王者荣耀']);
    await pumpSearch(tester);
    expect(find.byType(SearchHistoryList), findsNothing, reason: 'the box is not focused yet');

    await focusEmptyBox(tester);
    expect(find.text('最近搜索'), findsOneWidget);
    expect(shown(tester), ['王者荣耀', '原神', '英雄联盟']);

    await tester.tap(find.text('原神'));
    await settle(tester);
    expect(find.byType(SearchHistoryList), findsNothing, reason: 'the results replace the list');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '原神');
    expect(find.widgetWithText(RoomCardView, '主播d1'), findsOneWidget);
    expect(await stored(tester), ['原神', '王者荣耀', '英雄联盟']);
    await done(tester);
  });

  testWidgets('desktop: clicking an entry or its remove button keeps the list (the box keeps the focus)', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await open(tester);
    await seed(tester, ['英雄联盟', '原神', '王者荣耀']);
    await pumpSearch(tester, size: const Size(1440, 900));
    await tester.tap(find.byType(TextField), kind: PointerDeviceKind.mouse);
    await settle(tester);
    expect(shown(tester), ['王者荣耀', '原神', '英雄联盟']);
    await tester.tap(find.byTooltip('从搜索历史中删除').first, kind: PointerDeviceKind.mouse);
    await snackBar(tester);
    expect(shown(tester), ['原神', '英雄联盟'], reason: 'a click outside a text field would otherwise unfocus it');
    await tester.tap(find.text('英雄联盟'), kind: PointerDeviceKind.mouse);
    await settle(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '英雄联盟');
    expect(find.widgetWithText(RoomCardView, '主播d1'), findsOneWidget);
    await done(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('typing hides the list; emptying the box brings it back', (tester) async {
    await open(tester);
    await seed(tester, ['原神']);
    await pumpSearch(tester);
    await focusEmptyBox(tester);
    expect(find.byType(SearchHistoryList), findsOneWidget);
    await tester.enterText(find.byType(TextField), '王');
    await tester.pump();
    expect(find.byType(SearchHistoryList), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.byType(SearchHistoryList), findsOneWidget);
    await done(tester);
  });

  testWidgets('one entry can be removed, with undo', (tester) async {
    await open(tester);
    await seed(tester, ['英雄联盟', '原神']);
    await pumpSearch(tester);
    await focusEmptyBox(tester);
    await tester.tap(find.byTooltip('从搜索历史中删除').first);
    await snackBar(tester);
    expect(shown(tester), ['英雄联盟']);
    expect(find.text('已从搜索历史中删除“原神”'), findsOneWidget);
    expect(find.byType(SearchHistoryList), findsOneWidget, reason: 'the box keeps the focus');

    await tester.tap(find.text('撤销'));
    await settle(tester);
    expect(shown(tester), ['原神', '英雄联盟']);
    await done(tester);
  });

  testWidgets('清空 removes them all without asking, with undo', (tester) async {
    await open(tester);
    await seed(tester, ['英雄联盟', '原神']);
    await pumpSearch(tester);
    await focusEmptyBox(tester);
    await tester.tap(find.text('清空'));
    await snackBar(tester);
    expect(find.byType(AlertDialog), findsNothing, reason: 'undo, not a confirmation (F-HIS-01)');
    expect(find.byType(SearchHistoryList), findsNothing);
    expect(await stored(tester), isEmpty);
    await tester.tap(find.text('撤销'));
    await settle(tester);
    expect(await stored(tester), ['原神', '英雄联盟']);
    expect(shown(tester), ['原神', '英雄联盟']);
    await done(tester);
  });

  testWidgets('with search history off nothing is listed or remembered', (tester) async {
    await open(tester);
    await seed(tester, ['原神']);
    await tester.runAsync(() => store.settings.set(Settings.recordSearchHistory, false));
    await pumpSearch(tester);
    await focusEmptyBox(tester);
    expect(find.byType(SearchHistoryList), findsNothing);
    await search(tester, '王者荣耀');
    expect(await stored(tester), ['原神'], reason: 'only what was there before');
    await done(tester);
  });

  // The tile sits in 设置 › 数据与同步; settings_search_test checks that the
  // group shows every indexed setting, this one included.
  testWidgets('设置 › 数据与同步: turning it off clears the history with undo, which turns it on again', (tester) async {
    await open(tester);
    await seed(tester, ['英雄联盟', '原神']);
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(store)],
        child: MaterialApp(
          theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
          home: const Scaffold(body: SearchHistorySettingTile()),
        ),
      ),
    );
    await settle(tester);
    final tile = find.widgetWithText(SwitchListTile, '记录搜索历史');
    expect(tester.widget<SwitchListTile>(tile).value, isTrue, reason: 'on by default');

    await tester.tap(tile);
    await snackBar(tester);
    expect(store.settings.get(Settings.recordSearchHistory), isFalse);
    expect(await stored(tester), isEmpty);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
    expect(find.text('已关闭并清空搜索历史'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await settle(tester);
    expect(store.settings.get(Settings.recordSearchHistory), isTrue);
    expect(await stored(tester), ['原神', '英雄联盟']);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    await done(tester);
  });

  test('the provider: changes go through the notifier and the state follows', () async {
    final live = await LiveStore.inMemory();
    addTearDown(live.close);
    final container = ProviderContainer(overrides: [storeProvider.overrideWithValue(live)]);
    addTearDown(container.dispose);
    List<String> state() => [for (final entry in container.read(searchHistoryProvider).value!) entry.keyword];
    final notifier = container.read(searchHistoryProvider.notifier);
    expect(await container.read(searchHistoryProvider.future), isEmpty);

    expect(await notifier.record('原神'), isTrue);
    await live.searchHistory.record('王者荣耀', at: DateTime.utc(2026));
    expect(await notifier.record('LOL'), isTrue);
    expect(state(), ['LOL', '原神', '王者荣耀'], reason: 'each change reads the list again');
    final removed = await notifier.remove('lol');
    expect(state(), ['原神', '王者荣耀']);
    await notifier.restore([removed!]);
    expect(state(), ['LOL', '原神', '王者荣耀']);
    final cleared = await notifier.clear();
    expect(state(), isEmpty);
    await notifier.restore(cleared);
    expect(state(), hasLength(3));

    expect(container.read(recordSearchHistorySetting), isTrue);
    await live.settings.set(Settings.recordSearchHistory, false);
    await pumpEventQueue();
    expect(container.read(recordSearchHistorySetting), isFalse);
    expect(await notifier.record('不记'), isFalse, reason: 'off: nothing is recorded');
    expect(state(), hasLength(3));
  });
}
