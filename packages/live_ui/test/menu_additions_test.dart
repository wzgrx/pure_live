// The small menu's description lines, title row and footer, and the option
// row's trailing slot (docs/A-界面设计/A07-直播间界面/A07.12-直播间子弹窗统一: the room menu, the unfollow
// and orientation menus, the cast receivers).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view
    ..physicalSize = const Size(393, 852)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: const LiveTheme().light,
      home: Scaffold(
        body: Align(alignment: Alignment.topRight, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('a title row on top and a second line under an entry; the button tells when it opens and closes', (
    tester,
  ) async {
    final events = <String>[];
    await _pump(
      tester,
      AppMenuButton<int>(
        tooltip: '菜单',
        icon: const Icon(Icons.menu),
        onMenu: (open) => events.add(open ? 'open' : 'closed'),
        onSelected: (value) => events.add('chose $value'),
        entries: () => const [
          AppMenuEntry(key: ValueKey('timer'), value: 1, icon: Icons.timer, label: '定时关闭', description: '28 分钟后暂停'),
          AppMenuEntry(key: ValueKey('share'), value: 2, icon: Icons.share, label: '分享'),
        ],
      ),
    );
    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    expect(events, ['open']);
    final scheme = Theme.of(tester.element(find.byKey(const ValueKey('timer')))).colorScheme;
    final line = tester.widget<Text>(find.text('28 分钟后暂停'));
    expect(line.style?.color, scheme.onSurfaceVariant);
    expect(line.style?.fontSize, 12);
    expect(tester.getTopLeft(find.text('28 分钟后暂停')).dy, greaterThan(tester.getBottomLeft(find.text('定时关闭')).dy - 1));
    expect(tester.getRect(find.byKey(const ValueKey('timer'))).height, greaterThanOrEqualTo(48));
    await tester.tap(find.text('分享'));
    await tester.pumpAndSettle();
    expect(events, ['open', 'closed', 'chose 2']);
  });

  testWidgets('showAppMenu: a title that is not a choice over a red danger entry', (tester) async {
    bool? chosen;
    await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => chosen = await showAppMenu<bool>(
            context,
            title: '主播 · 哔哩哔哩',
            entries: const [
              AppMenuEntry(
                key: ValueKey('unfollow'),
                value: true,
                icon: Icons.heart_broken,
                label: '取消关注',
                danger: true,
              ),
            ],
          ),
          child: const Text('已关注'),
        ),
      ),
    );
    await tester.tap(find.text('已关注'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-menu-title')), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('app-menu-title'))).bottom,
      lessThanOrEqualTo(tester.getRect(find.byKey(const ValueKey('unfollow'))).top),
    );
    final scheme = Theme.of(tester.element(find.byKey(const ValueKey('unfollow')))).colorScheme;
    expect(tester.widget<Text>(find.text('取消关注')).style?.color, scheme.error);
    // The title takes no tap.
    await tester.tap(find.byKey(const ValueKey('app-menu-title')));
    await tester.pumpAndSettle();
    expect(find.text('取消关注'), findsOneWidget);
    await tester.tap(find.text('取消关注'));
    await tester.pumpAndSettle();
    expect(chosen, isTrue);
  });

  testWidgets('showSmallMenu: a footer under a line applies at once and leaves the menu open', (tester) async {
    var remember = false;
    int? chosen;
    await _pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => chosen = await showSmallMenu(
            context,
            entries: const ['自动识别', '强制竖屏'],
            current: 0,
            footer: StatefulBuilder(
              builder: (context, setState) => SwitchListTile(
                key: const ValueKey('remember'),
                title: const Text('记住'),
                value: remember,
                onChanged: (value) => setState(() => remember = value),
              ),
            ),
          ),
          child: const Text('方向'),
        ),
      ),
    );
    await tester.tap(find.text('方向'));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuDivider), findsOneWidget);
    expect(
      tester.getRect(find.byType(PopupMenuDivider)).top,
      greaterThanOrEqualTo(tester.getRect(find.byKey(const ValueKey('stream-menu-item-1'))).bottom),
    );
    await tester.tap(find.byKey(const ValueKey('remember')));
    await tester.pumpAndSettle();
    expect(remember, isTrue);
    expect(find.byKey(const ValueKey('stream-menu-item-1')), findsOneWidget, reason: 'still open');
    await tester.tap(find.byKey(const ValueKey('stream-menu-item-1')));
    await tester.pumpAndSettle();
    expect(chosen, 1);
  });

  testWidgets('DialogOptionRow: a trailing widget takes the place of the tick', (tester) async {
    await _pump(
      tester,
      const Column(
        children: [
          DialogOptionRow(key: ValueKey('a'), label: '客厅电视', selected: true, onTap: null),
          DialogOptionRow(
            key: ValueKey('b'),
            label: '书房投影',
            selected: true,
            onTap: null,
            trailing: SizedBox.square(key: ValueKey('spinner'), dimension: 20),
          ),
        ],
      ),
    );
    expect(
      find.descendant(of: find.byKey(const ValueKey('a')), matching: find.byIcon(AppIcons.selected)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const ValueKey('b')), matching: find.byIcon(AppIcons.selected)),
      findsNothing,
    );
    expect(
      find.descendant(of: find.byKey(const ValueKey('b')), matching: find.byKey(const ValueKey('spinner'))),
      findsOne,
    );
  });
}
