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

import '../../support.dart';

/// Pumps the page over an in-memory store holding [keywords] and [users].
Future<BlockListStore> _pump(
  WidgetTester tester, {
  List<String> keywords = const [],
  List<String> users = const [],
  Object? arguments,
}) async {
  tester.view
    ..physicalSize = const Size(420, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(() async {
    final services = await testServices();
    await services.store.blockLists.replaceAll(BlockKind.keyword, keywords);
    await services.store.blockLists.replaceAll(BlockKind.user, users);
    return services;
  }))!;
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
          home: ShieldPage(route: RouteArgs(RoutePath.kSettingsDanmuShield, arguments: arguments)),
        ),
      ),
    ),
  );
  await _settle(tester);
  return services.store.blockLists;
}

/// Lets the store's queries (real async work) finish, then the frames.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
  }
}

Future<List<String>> _list(WidgetTester tester, BlockListStore lists, BlockKind kind) async =>
    (await tester.runAsync(() => lists.list(kind)))!;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await _settle(tester);
}

void main() {
  testWidgets('adds keywords, refusing empty and repeated ones where typed', (tester) async {
    final lists = await _pump(tester);
    expect(find.text('弹幕屏蔽'), findsOneWidget);
    expect(find.text('关键词（0）'), findsOneWidget);
    expect(find.text('暂无屏蔽关键词'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('shield-add-keyword')));
    expect(find.text('请输入关键字'), findsWidgets);

    await tester.enterText(find.byKey(const ValueKey('shield-input-keyword')), ' Spoiler ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);
    expect(await _list(tester, lists, BlockKind.keyword), ['Spoiler']);
    expect(find.byKey(const ValueKey('shield-chip-keyword-Spoiler')), findsOneWidget);
    expect(find.text('关键词（1）'), findsOneWidget);
    expect(find.text('已添加 1 个关键词（点击可移除）'), findsOneWidget);

    // 3.x dropped a repeated keyword silently and cleared the input.
    await tester.enterText(find.byKey(const ValueKey('shield-input-keyword')), 'spoiler');
    await _tap(tester, find.byKey(const ValueKey('shield-add-keyword')));
    expect(find.text('“spoiler”已在列表中'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'spoiler'), findsOneWidget);
    expect(await _list(tester, lists, BlockKind.keyword), ['Spoiler']);
  });

  testWidgets('removes a keyword with a tap and puts it back in place on undo', (tester) async {
    final lists = await _pump(tester, keywords: ['a', 'b', 'c']);
    await _tap(tester, find.byKey(const ValueKey('shield-chip-keyword-b')));
    expect(await _list(tester, lists, BlockKind.keyword), ['a', 'c']);
    expect(find.text('已移除“b”'), findsOneWidget);
    await _tap(tester, find.text('撤销'));
    expect(await _list(tester, lists, BlockKind.keyword), ['a', 'b', 'c']);
  });

  testWidgets('opens on the users tab, adds a user and clears the list after asking', (tester) async {
    final lists = await _pump(tester, keywords: ['k'], users: ['Alice', 'Bob'], arguments: BlockKind.user);
    expect(find.text('用户（2）'), findsOneWidget);
    expect(find.text('已屏蔽用户（2）'), findsOneWidget);
    expect(find.byKey(const ValueKey('shield-chip-user-Alice')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('shield-input-user')), 'Carol');
    await _tap(tester, find.byKey(const ValueKey('shield-add-user')));
    expect(await _list(tester, lists, BlockKind.user), ['Alice', 'Bob', 'Carol']);

    await _tap(tester, find.byKey(const ValueKey('shield-clear-user')));
    expect(find.text('确定清空全部 3 个屏蔽用户吗？'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('shield-clear-confirm')));
    expect(await _list(tester, lists, BlockKind.user), isEmpty);
    expect(find.text('暂无屏蔽用户'), findsOneWidget);
    expect(await _list(tester, lists, BlockKind.keyword), ['k']);
    await _tap(tester, find.text('撤销'));
    expect(await _list(tester, lists, BlockKind.user), ['Alice', 'Bob', 'Carol']);
  });
}
