import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/shield/shield_page.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/danmaku/masked_blocks.dart';

import '../../support.dart';

/// Pumps the page at [size] over an in-memory store holding [keywords] and
/// [users]; the toasts land in [toasts].
Future<LiveStore> _pump(
  WidgetTester tester, {
  List<String> keywords = const [],
  List<String> users = const [],
  Object? arguments,
  Size size = const Size(393, 852),
  List<String>? toasts,
  Future<void> Function(LiveStore store)? prepare,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(() async {
    final services = await testServices();
    await services.store.blockLists.replaceAll(BlockKind.keyword, keywords);
    await services.store.blockLists.replaceAll(BlockKind.user, users);
    await prepare?.call(services.store);
    return services;
  }))!;
  addTearDown(() => tester.runAsync(services.close));
  final strings = (await tester.runAsync(loadStrings))!;
  final previousToast = AppNavigator.toast;
  AppNavigator.toast = toasts?.add ?? (_) {};
  addTearDown(() => AppNavigator.toast = previousToast);
  await tester.pumpWidget(_app(services, strings, arguments));
  await _settle(tester);
  return services.store;
}

Widget _app(AppServices services, AppStrings strings, [Object? arguments]) => ProviderScope(
  overrides: [appServicesProvider.overrideWithValue(services)],
  child: LiveUiScope(
    config: LiveUiConfig(strings: strings.ui),
    child: MaterialApp(
      theme: const LiveTheme(primaryColor: Colors.blue).light,
      home: ShieldPage(route: RouteArgs(RoutePath.kSettingsDanmuShield, arguments: arguments)),
    ),
  ),
);

/// Lets the store's queries (real async work) finish, then the frames.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
  }
}

Future<List<String>> _list(WidgetTester tester, LiveStore store, BlockKind kind) async =>
    (await tester.runAsync(() => store.blockLists.list(kind)))!;

/// The vertical order of [texts] on screen.
List<String> _topDown(WidgetTester tester, List<String> texts) =>
    [...texts]..sort((a, b) => tester.getTopLeft(find.text(a)).dy.compareTo(tester.getTopLeft(find.text(b)).dy));

void main() {
  testWidgets('one page: "弹幕屏蔽", keywords, users, the platform and similarity filters (c2, c5)', (tester) async {
    await _pump(tester, size: const Size(393, 2000));
    expect(find.text('弹幕屏蔽'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    final order = ['弹幕关键词屏蔽', '已屏蔽用户（0）', '平台弹幕过滤', '相似弹幕过滤'];
    expect(_topDown(tester, order), order);
    // Empty: both lists say what goes there.
    expect(find.text('暂无屏蔽关键词'), findsOneWidget);
    expect(find.text('添加关键词后，包含该内容的弹幕将被自动过滤'), findsOneWidget);
    expect(find.text('还没有屏蔽的用户；长按弹幕可屏蔽发送者'), findsOneWidget);
    expect(find.text('过滤斗鱼疑似自动弹幕'), findsOneWidget);
    // The similarity sliders are greyed out while the filter is off.
    expect(tester.widget<Slider>(find.byKey(const ValueKey('danmaku-slider-similarityThreshold'))).onChanged, isNull);
    // No "clear" (M2 A).
    expect(find.text('清空'), findsNothing);
    // The input with "添加" on its right, 40 characters at most.
    final input = tester.getRect(find.byKey(const ValueKey('live-play-block-input')));
    final add = tester.getRect(find.byKey(const ValueKey('live-play-block-add')));
    expect(add.left, greaterThan(input.right));
    expect(tester.widget<TextField>(find.byKey(const ValueKey('live-play-block-input'))).maxLength, 40);
  });

  testWidgets('adds with Enter; empty and repeated keywords are refused, the repeat kept (c1, c4)', (tester) async {
    final toasts = <String>[];
    final store = await _pump(tester, toasts: toasts);
    await tester.tap(find.byKey(const ValueKey('live-play-block-add')));
    await _settle(tester);
    expect(toasts, ['请输入关键词']);

    await tester.enterText(find.byKey(const ValueKey('live-play-block-input')), ' 剧透 ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);
    expect(await _list(tester, store, BlockKind.keyword), ['剧透']);
    expect(find.byKey(const ValueKey('block-chip-keyword-剧透')), findsOneWidget);
    expect(find.text('已添加1个关键词'), findsOneWidget);

    // 3.x dropped a repeated keyword silently and cleared the input.
    await tester.enterText(find.byKey(const ValueKey('live-play-block-input')), '剧透');
    await tester.tap(find.byKey(const ValueKey('live-play-block-add')));
    await _settle(tester);
    expect(find.text('“剧透”已经在屏蔽列表里'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('live-play-block-input'))).controller!.text, '剧透');
    expect(await _list(tester, store, BlockKind.keyword), ['剧透']);
  });

  testWidgets('only the × removes; undo puts it back where it was (c3)', (tester) async {
    final store = await _pump(tester, keywords: ['a', 'b', 'c'], users: ['Alice']);
    // A tap on the word itself does nothing (3.x removed on any tap).
    await tester.tap(find.text('b'));
    await _settle(tester);
    expect(await _list(tester, store, BlockKind.keyword), ['a', 'b', 'c']);
    expect(tester.getSize(find.byKey(const ValueKey('block-chip-remove-b'))).height, 48);

    await tester.tap(find.byKey(const ValueKey('block-chip-remove-b')));
    await _settle(tester);
    expect(await _list(tester, store, BlockKind.keyword), ['a', 'c']);
    expect(find.text('已移除“b”'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await _settle(tester);
    expect(await _list(tester, store, BlockKind.keyword), ['a', 'b', 'c']);

    // Blocked viewers the same way.
    await tester.tap(find.byKey(const ValueKey('block-chip-remove-Alice')));
    await _settle(tester);
    expect(await _list(tester, store, BlockKind.user), isEmpty);
    await tester.tap(find.text('撤销'));
    await _settle(tester);
    expect(await _list(tester, store, BlockKind.user), ['Alice']);
  });

  testWidgets('opened for the blocked users, it scrolls to them', (tester) async {
    await _pump(
      tester,
      keywords: [for (var i = 0; i < 40; i++) '关键词$i'],
      users: ['Alice', 'Bob'],
      arguments: BlockKind.user,
      size: const Size(393, 600),
    );
    final title = tester.getTopLeft(find.text('已屏蔽用户（2）'));
    expect(title.dy, lessThan(600));
    expect(find.byKey(const ValueKey('block-chip-user-Alice')).hitTestable(), findsOneWidget);
  });

  testWidgets('B01 c2: after the one-time cleanup the page says how many masked names went, once', (tester) async {
    final store = await _pump(
      tester,
      users: ['路人', '观***', 'Alice', '离**'],
      prepare: (store) => MaskedNameBlocks.cleanOnce(store.blockLists, store.meta),
    );
    const text = '已清理 2 个打码昵称的屏蔽（它们会误伤其他观众）';
    expect(find.text(text), findsOneWidget);
    expect(_topDown(tester, [text, '弹幕关键词屏蔽']), [text, '弹幕关键词屏蔽'], reason: 'at the top');
    expect(find.text('已屏蔽用户（2）'), findsOneWidget);
    expect(find.byKey(const ValueKey('block-chip-user-观***')), findsNothing);
    expect(await _list(tester, store, BlockKind.user), ['路人', 'Alice']);
    await tester.tap(find.byKey(const ValueKey('block-masked-cleaned-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('block-masked-cleaned')), findsNothing);

    // Opened again: said already.
    final services = ProviderScope.containerOf(tester.element(find.byType(ShieldPage))).read(appServicesProvider);
    final strings = (await tester.runAsync(loadStrings))!;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_app(services, strings));
    await _settle(tester);
    expect(find.byType(ShieldPage), findsOneWidget);
    expect(find.byKey(const ValueKey('block-masked-cleaned')), findsNothing);
  });

  testWidgets('no masked names: no notice', (tester) async {
    await _pump(tester, users: ['路人'], prepare: (store) => MaskedNameBlocks.cleanOnce(store.blockLists, store.meta));
    expect(find.byKey(const ValueKey('block-masked-cleaned')), findsNothing);
  });

  testWidgets('landscape phone and wide window: at most 720, centred (c6)', (tester) async {
    for (final size in const [Size(852, 393), Size(1280, 800)]) {
      await _pump(tester, size: size);
      final input = tester.getRect(find.byKey(const ValueKey('live-play-block-input')));
      final add = tester.getRect(find.byKey(const ValueKey('live-play-block-add')));
      // The card is 720 wide and centred: its contents sit 12 inside it.
      expect(add.right, closeTo(size.width / 2 + 360 - 12, 0.5));
      expect(input.left, closeTo(size.width / 2 - 360 + 12, 0.5));
      expect(tester.getSize(find.byType(AppBar)).height, size.height < 480 ? 48 : kToolbarHeight);
    }
  });
}
