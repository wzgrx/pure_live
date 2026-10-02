import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/tags/tags_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';

LiveRoom _room(String id) =>
    LiveRoom(platform: 'douyu', roomId: id, title: 'Title $id', nick: 'Nick $id', watching: '');

final class _Harness {
  new(this.services, this.toasts);

  final AppServices services;
  final List<String> toasts;

  TagStore get tags => services.store.tags;
}

/// Pumps the page over an in-memory store prepared by [seed].
Future<_Harness> _pump(
  WidgetTester tester, {
  Future<void> Function(LiveStore store)? seed,
  Size size = const Size(420, 900),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(() async {
    final services = await testServices();
    await seed?.call(services.store);
    return services;
  }))!;
  addTearDown(() => tester.runAsync(services.close));
  final strings = (await tester.runAsync(loadStrings))!;
  final toasts = <String>[];
  final previousToast = AppNavigator.toast;
  AppNavigator.toast = toasts.add;
  addTearDown(() => AppNavigator.toast = previousToast);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services)],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp(
          theme: const LiveTheme(primaryColor: Colors.blue).light,
          home: const TagsPage(route: RouteArgs(RoutePath.kSettingsTags)),
        ),
      ),
    ),
  );
  await _settle(tester);
  return _Harness(services, toasts);
}

/// Lets the store's queries (real async work) finish, then the frames.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
  }
}

Future<List<String>> _names(WidgetTester tester, TagStore tags) async => [
  for (final tag in (await tester.runAsync(tags.all))!) tag.name,
];

Future<StoreTag> _tag(WidgetTester tester, TagStore tags, String name) async =>
    (await tester.runAsync(tags.all))!.singleWhere((tag) => tag.name == name);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await _settle(tester);
}

void main() {
  testWidgets('adds tags from the empty state, refusing empty and repeated names', (tester) async {
    final h = await _pump(tester);
    expect(find.byKey(const ValueKey('tags-empty')), findsOneWidget);
    expect(find.textContaining('暂无自定义标签'), findsOneWidget);

    await _tap(tester, find.descendant(of: find.byKey(const ValueKey('tags-empty')), matching: find.text('添加标签')));
    expect(find.text('添加标签'), findsWidgets);
    await _tap(tester, find.byKey(const ValueKey('tag-editor-confirm')));
    expect(find.text('标签名称不能为空'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('tag-editor-name')), ' Game ');
    await tester.enterText(find.byKey(const ValueKey('tag-editor-description')), '常看的游戏区');
    await _tap(tester, find.byKey(const ValueKey('tag-editor-confirm')));
    expect(find.byKey(const ValueKey('tag-editor-name')), findsNothing);
    expect(h.toasts, ['已添加标签“Game”']);
    expect(find.text('Game'), findsOneWidget);
    expect(find.text('常看的游戏区'), findsOneWidget);
    expect(find.text('0 个直播间'), findsOneWidget);

    // Names are unique without regard to case.
    await _tap(tester, find.byKey(const ValueKey('tags-add')));
    await tester.enterText(find.byKey(const ValueKey('tag-editor-name')), 'game');
    await _tap(tester, find.byKey(const ValueKey('tag-editor-confirm')));
    expect(find.text('已存在同名标签'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('tag-editor-name')), '音乐');
    await _tap(tester, find.byKey(const ValueKey('tag-editor-confirm')));
    expect(await _names(tester, h.tags), ['Game', '音乐']);
    expect(find.text('暂无描述'), findsOneWidget);
  });

  testWidgets('shows room counts, details, and edits, pins and deletes tags', (tester) async {
    final h = await _pump(
      tester,
      seed: (store) async {
        final a = (await store.tags.add('A'))!;
        final b = (await store.tags.add('B', description: '说明'))!;
        final c = (await store.tags.add('C'))!;
        await store.follows.add(_room('1'));
        await store.follows.add(_room('2'));
        await store.tags.setTagsOf(_room('1'), [b.id]);
        await store.tags.setTagsOf(_room('2'), [b.id, c.id]);
        // Not followed: not counted.
        await store.tags.setTagsOf(_room('3'), [a.id, b.id]);
      },
    );
    final a = await _tag(tester, h.tags, 'A');
    final b = await _tag(tester, h.tags, 'B');
    final c = await _tag(tester, h.tags, 'C');
    String rooms(StoreTag tag) => tester.widget<Text>(find.byKey(ValueKey('tag-rooms-${tag.id}'))).data!;
    expect(rooms(a), '0 个直播间');
    expect(rooms(b), '2 个直播间');
    expect(rooms(c), '1 个直播间');

    // Details, then edit from there.
    await _tap(tester, find.byKey(ValueKey('tag-open-${b.id}')));
    expect(find.text('标签详情'), findsOneWidget);
    expect(find.text('说明'), findsWidgets);
    await _tap(tester, find.byKey(const ValueKey('tag-details-edit')));
    await tester.enterText(find.byKey(const ValueKey('tag-editor-name')), 'B2');
    await _tap(tester, find.byKey(const ValueKey('tag-editor-confirm')));
    expect(h.toasts.last, '已保存标签“B2”');
    expect(await _names(tester, h.tags), ['A', 'B2', 'C']);

    // The first tag cannot be pinned again; others move to the top.
    expect(tester.widget<IconButton>(find.byKey(ValueKey('tag-pin-${a.id}'))).onPressed, isNull);
    await _tap(tester, find.byKey(ValueKey('tag-pin-${c.id}')));
    expect(await _names(tester, h.tags), ['C', 'A', 'B2']);

    // Deleting asks, says how many followed rooms lose it, and clears it
    // from every room.
    await _tap(tester, find.byKey(ValueKey('tag-delete-${b.id}')));
    expect(find.text('确定要永久删除标签“B2”吗？'), findsOneWidget);
    expect(find.byKey(const ValueKey('tag-delete-rooms')), findsOneWidget);
    expect(find.textContaining('2 个关注的直播间'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('tag-delete-cancel')));
    expect(await _names(tester, h.tags), ['C', 'A', 'B2']);
    await _tap(tester, find.byKey(ValueKey('tag-delete-${b.id}')));
    await _tap(tester, find.byKey(const ValueKey('tag-delete-confirm')));
    expect(h.toasts.last, '已删除标签“B2”');
    expect(await _names(tester, h.tags), ['C', 'A']);
    expect(await tester.runAsync(h.tags.assignments), {
      _room('2').identityKey: [c.id],
      _room('3').identityKey: [a.id],
    });
  });

  testWidgets('reorders by dragging the handle', (tester) async {
    final h = await _pump(
      tester,
      seed: (store) async {
        for (final name in ['A', 'B', 'C']) {
          await store.tags.add(name);
        }
      },
    );
    final a = await _tag(tester, h.tags, 'A');
    final handle = find.descendant(of: find.byKey(ValueKey('tag-${a.id}')), matching: find.byIcon(AppIcons.dragHandle));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 25));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await _settle(tester);
    expect(await _names(tester, h.tags), ['B', 'C', 'A']);
    expect(find.byKey(const ValueKey('tags-busy')), findsNothing);
  });

  testWidgets('portrait: one line of tip, one tag a row; handle, text, then pin, edit, delete (c2, c3)', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      size: const Size(393, 852),
      seed: (store) async {
        await store.tags.add('常看', description: '每天都会看的直播间');
        await store.tags.add('游戏');
      },
    );
    final first = await _tag(tester, h.tags, '常看');
    final second = await _tag(tester, h.tags, '游戏');
    // No repeated group title, no tinted box: the tip is a line above.
    expect(find.text('标签管理'), findsOneWidget);
    final tip = tester.getRect(find.byKey(const ValueKey('tags-tip')));
    final card = tester.getRect(find.byKey(ValueKey('tag-${first.id}')));
    expect(tip.bottom, lessThanOrEqualTo(card.top));
    expect(card.left, 16);
    expect(card.width, 393 - 32);
    // One a row.
    expect(tester.getRect(find.byKey(ValueKey('tag-${second.id}'))).top, greaterThan(card.bottom - 8));
    // Handle | name, description, rooms | pin, edit, delete; 48 targets.
    final handle = tester.getRect(find.byKey(ValueKey('tag-handle-${first.id}')));
    final name = tester.getRect(find.byKey(ValueKey('tag-name-${first.id}')));
    final pin = tester.getRect(find.byKey(ValueKey('tag-pin-${first.id}')));
    final edit = tester.getRect(find.byKey(ValueKey('tag-edit-${first.id}')));
    final delete = tester.getRect(find.byKey(ValueKey('tag-delete-${first.id}')));
    expect(
      [handle.left, name.left, pin.left, edit.left, delete.left],
      orderedEquals(
        [
          ...[handle.left, name.left, pin.left, edit.left, delete.left],
        ]..sort(),
      ),
    );
    for (final button in [pin, edit, delete]) {
      expect(button.width, greaterThanOrEqualTo(48));
      expect(button.height, greaterThanOrEqualTo(48));
    }
    expect(tester.widget<Text>(find.byKey(ValueKey('tag-name-${first.id}'))).style!.fontWeight, FontWeight.w600);
    final description = tester.widget<Text>(find.byKey(ValueKey('tag-description-${second.id}')));
    expect(description.data, '暂无描述');
    expect(description.style!.fontSize, greaterThanOrEqualTo(12));
    // 3.x's icons; the first tag's pin is filled (and does nothing), the
    // others are outlined.
    Finder icon(String key, IconData data) =>
        find.descendant(of: find.byKey(ValueKey(key)), matching: find.byIcon(data));
    expect(icon('tag-pin-${first.id}', AppIcons.pinned), findsOneWidget);
    expect(icon('tag-pin-${second.id}', AppIcons.unpinned), findsOneWidget);
    expect(icon('tag-edit-${first.id}', AppIcons.edit), findsOneWidget);
    expect(icon('tag-delete-${first.id}', AppIcons.delete), findsOneWidget);
    expect(icon('tag-handle-${first.id}', AppIcons.dragHandle), findsOneWidget);
    final pinned = tester.widget<IconButton>(find.byKey(ValueKey('tag-pin-${first.id}')));
    expect(pinned.onPressed, isNull);
    expect(pinned.disabledColor, isNotNull);
  });

  testWidgets('details: rooms, "编辑标签" and "关闭"; editor: labels on the field, counts, errors under it (c6, c7)', (
    tester,
  ) async {
    final h = await _pump(tester, seed: (store) => store.tags.add('音乐', description: '唱歌'));
    final tag = await _tag(tester, h.tags, '音乐');
    await _tap(tester, find.byKey(ValueKey('tag-open-${tag.id}')));
    expect(find.text('关注中带此标签的直播间'), findsOneWidget);
    // U.1d: "关闭" first, the main button ("编辑标签") at the end.
    final edit = tester.getRect(find.byKey(const ValueKey('tag-details-edit')));
    final close = tester.getRect(find.byKey(const ValueKey('tag-details-close')));
    expect(close.right, lessThan(edit.left));
    expect(
      find.descendant(of: find.byKey(const ValueKey('tag-details-close')), matching: find.text('关闭')),
      findsOneWidget,
    );
    await _tap(tester, find.byKey(const ValueKey('tag-details-close')));
    expect(find.byKey(const ValueKey('tag-details')), findsNothing);

    await _tap(tester, find.byKey(const ValueKey('tags-add')));
    expect(find.text('标签名称'), findsOneWidget);
    expect(find.text('备注描述'), findsOneWidget);
    expect(find.text('0/15'), findsOneWidget);
    expect(find.text('0/40'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('tag-editor-name')), '音乐');
    await _tap(tester, find.byKey(const ValueKey('tag-editor-confirm')));
    final error = tester.getRect(find.text('已存在同名标签'));
    final field = tester.getRect(find.byKey(const ValueKey('tag-editor-name')));
    expect(error.top, greaterThan(field.top));
    expect(error.top, lessThan(tester.getRect(find.byKey(const ValueKey('tag-editor-description'))).top));
    final cancel = tester.getRect(find.byKey(const ValueKey('tag-editor-cancel')));
    final confirm = tester.getRect(find.byKey(const ValueKey('tag-editor-confirm')));
    expect(cancel.right, lessThan(confirm.left));
  });

  testWidgets('landscape phone and wide window: one column at most 720, centred (J1 A)', (tester) async {
    for (final size in const [Size(852, 393), Size(1280, 800)]) {
      final h = await _pump(tester, size: size, seed: (store) => store.tags.add('A'));
      final tag = await _tag(tester, h.tags, 'A');
      final card = tester.getRect(find.byKey(ValueKey('tag-${tag.id}')));
      expect(card.width, 720);
      expect(card.center.dx, size.width / 2);
      expect(tester.getSize(find.byType(AppBar)).height, size.height < 480 ? 48 : kToolbarHeight);
    }
  });

  testWidgets('does not overwrite a tag changed elsewhere while editing', (tester) async {
    final h = await _pump(tester, seed: (store) => store.tags.add('A'));
    final a = await _tag(tester, h.tags, 'A');
    await _tap(tester, find.byKey(ValueKey('tag-edit-${a.id}')));
    await tester.runAsync(() => h.tags.update(a.id, name: 'Elsewhere'));
    await tester.enterText(find.byKey(const ValueKey('tag-editor-name')), 'Mine');
    await _tap(tester, find.byKey(const ValueKey('tag-editor-confirm')));
    expect(find.text('编辑期间此标签已发生变化。请关闭弹窗后重试。'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('tag-editor-confirm'))).onPressed, isNull);
    await _tap(tester, find.byKey(const ValueKey('tag-editor-cancel')));
    expect(await _names(tester, h.tags), ['Elsewhere']);
  });
}
