import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/shield/shield_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/danmaku/block_manager.dart';

import '../../support.dart';

/// D02.2 in the block list (the settings page and the room's tab are one
/// component, A08.3): pattern words checked when added, "按内容屏蔽", and
/// the room's "本场已屏蔽 N 条".
Future<LiveStore> _pump(WidgetTester tester, {Widget? home, Size size = const Size(393, 2400)}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(testServices))!;
  addTearDown(() => tester.runAsync(services.close));
  final strings = (await tester.runAsync(loadStrings))!;
  final previousToast = AppNavigator.toast;
  AppNavigator.toast = (_) {};
  addTearDown(() => AppNavigator.toast = previousToast);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services)],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp(
          theme: const LiveTheme(primaryColor: Colors.blue).light,
          home: home ?? const ShieldPage(route: RouteArgs(RoutePath.kSettingsDanmuShield)),
        ),
      ),
    ),
  );
  await _settle(tester);
  return services.store;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
  }
}

Future<List<String>> _keywords(WidgetTester tester, LiveStore store) async =>
    (await tester.runAsync(() => store.blockLists.list(BlockKind.keyword)))!;

final Finder _input = find.byKey(const ValueKey('live-play-block-input'));

Future<void> _add(WidgetTester tester, String word) async {
  await tester.enterText(_input, word);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('live-play-block-add')));
  await _settle(tester);
}

void main() {
  testWidgets('a good pattern is added; a bad one is said under the field and kept there (c1)', (tester) async {
    final store = await _pump(tester);
    expect(find.text(r'以 / 开头和结尾的按正则匹配（不分大小写），如 /^[0-9]+$/'), findsOneWidget);

    await _add(tester, '/[/');
    expect(find.text('正则写法不对，没有加进去'), findsOneWidget);
    expect(tester.widget<TextField>(_input).controller!.text, '/[/');
    expect(await _keywords(tester, store), isEmpty);

    // Typing clears the message.
    await tester.enterText(_input, '/[0-9]/');
    await tester.pumpAndSettle();
    expect(find.text('正则写法不对，没有加进去'), findsNothing);

    await _add(tester, '/(a+)+b/');
    expect(find.textContaining('这样写可能很慢，没有加进去'), findsOneWidget);
    await _add(tester, '/.*.*.*.*.*.*x/');
    expect(find.textContaining('这个正则太慢'), findsOneWidget);
    expect(await _keywords(tester, store), isEmpty);

    await _add(tester, r'/^[0-9]+$/');
    expect(await _keywords(tester, store), [r'/^[0-9]+$/']);
    expect(find.byKey(const ValueKey(r'block-chip-keyword-/^[0-9]+$/')), findsOneWidget);
    expect(tester.widget<TextField>(_input).controller!.text, isEmpty);
  });

  testWidgets('a pattern may be 200 long, a word stays at 40', (tester) async {
    final store = await _pump(tester);
    expect(tester.widget<TextField>(_input).maxLength, 40);
    await tester.enterText(_input, '/abc');
    await tester.pump();
    expect(tester.widget<TextField>(_input).maxLength, 200);
    expect(find.text('4/200'), findsOneWidget);
    final long = '/${'a' * 198}/';
    await _add(tester, long);
    expect(await _keywords(tester, store), [long]);
    expect(tester.widget<TextField>(_input).maxLength, 40, reason: 'the field is empty again');
    expect(blockKeywordMaxLengthOf('广告'), 40);
    expect(blockKeywordMaxLengthOf(' /x'), 200);
  });

  testWidgets('"按内容屏蔽" after the viewers: off by default, the length greys out while off (c3)', (tester) async {
    final store = await _pump(tester);
    final order = ['已屏蔽用户（0）', '按内容屏蔽', '平台弹幕过滤', '相似弹幕过滤'];
    expect(
      [...order]..sort((a, b) => tester.getTopLeft(find.text(a)).dy.compareTo(tester.getTopLeft(find.text(b)).dy)),
      order,
    );
    expect(find.text('屏蔽只有表情的弹幕'), findsOneWidget);
    expect(find.text('超过 30 个字的弹幕不显示（一个表情算一个字）'), findsOneWidget);
    final slider = find.byKey(const ValueKey('danmaku-slider-blockLongLength'));
    expect(tester.widget<Slider>(slider).onChanged, isNull);
    expect(find.text('30 字'), findsOneWidget);

    await tester.tap(find.text('屏蔽只有表情的弹幕'));
    await tester.tap(find.text('屏蔽超长弹幕'));
    await _settle(tester);
    expect(store.settings.get(Settings.blockEmoteOnlyDanmaku), isTrue);
    expect(store.settings.get(Settings.blockLongDanmaku), isTrue);
    expect(tester.widget<Slider>(slider).onChanged, isNotNull);
    tester.widget<Slider>(slider).onChanged!(55);
    await _settle(tester);
    expect(store.settings.get(Settings.blockLongDanmakuLength), 55);
    expect(find.text('超过 55 个字的弹幕不显示（一个表情算一个字）'), findsOneWidget);
  });

  testWidgets('in a room the first line says how many the blocks hid; the settings page has none (c4)', (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('block-session-count')), findsNothing);

    final count = ValueNotifier(0);
    addTearDown(count.dispose);
    await _pump(
      tester,
      home: Scaffold(body: DanmakuBlockManager(blockedCount: count)),
    );
    expect(find.text('本场已屏蔽 0 条'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('本场已屏蔽 0 条')).dy,
      lessThan(tester.getTopLeft(find.text('弹幕关键词屏蔽')).dy),
      reason: 'the first line',
    );
    count.value = 12;
    await tester.pump();
    expect(find.text('本场已屏蔽 12 条'), findsOneWidget);
  });
}
