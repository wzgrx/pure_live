import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/follows/follow_actions.dart';
import 'package:pure_live_app/features/follows/groups.dart';

void main() {
  /// Lets drift finish writes started by the widgets.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }

  testWidgets('F-FAV-05: a group gets a description, shown under its name', (tester) async {
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    final first = (await tester.runAsync(() => store.tags.create('常看')))!;
    await tester.runAsync(() => store.tags.create('其它'));
    final tags = StreamController<List<Tag>>();
    addTearDown(tags.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(store), tagsProvider.overrideWith((ref) => tags.stream)],
        child: MaterialApp(
          theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
          home: const GroupsPage(),
        ),
      ),
    );
    tags.add([first]);
    await tester.pump();

    await tester.tap(find.byTooltip('改名和描述'));
    await tester.pumpAndSettle();
    expect(find.text('编辑分组'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '描述（可选）'), '晚上看的');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await settle(tester);
    final stored = (await tester.runAsync(store.tags.all))!;
    expect(stored.first.description, '晚上看的');
    expect(stored.first.name, '常看', reason: 'the name did not change');

    tags.add(stored.take(1).toList());
    await tester.pump();
    await tester.pump();
    expect(find.text('晚上看的'), findsOneWidget);

    // A taken name is refused and said; the description is left alone.
    await tester.tap(find.byTooltip('改名和描述'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '分组名称'), '其它');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.text('已经有叫“其它”的分组了'), findsOneWidget);
    expect((await tester.runAsync(store.tags.all))!.first.name, '常看');
  });

  testWidgets('F-FAV-02: a follow that cannot be written is said, and nothing changes', (tester) async {
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    await tester.runAsync(store.close);
    late WidgetRef widgetRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(store)],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                widgetRef = ref;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    final context = tester.element(find.byType(SizedBox).last);
    final followed = await tester.runAsync(
      () => followWithNotice(context, widgetRef, RoomSnapshot(ref: RoomRef('douyu', '1'))),
    );
    await tester.pump();
    expect(followed, isFalse);
    expect(find.text('关注失败，没有保存，请重试'), findsOneWidget);

    // The first notice goes away before the next one shows.
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    final removed = await tester.runAsync(() => unfollowWithNotice(context, widgetRef, RoomRef('douyu', '1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(removed, isNull);
    expect(find.text('取消关注失败，关注还在，请重试'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
