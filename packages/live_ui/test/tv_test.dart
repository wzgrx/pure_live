import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

/// TV mode of spec/design/principles.md §5.3 and §6.3.
void main() {
  group('gridStep: single-axis moves by row and column', () {
    GridStep step(int index, TraversalDirection direction, {int count = 10, int columns = 4, int? column}) =>
        gridStep(index: index, direction: direction, count: count, columns: columns, column: column);

    test('left and right stay in the row; the first column leaves, the row end holds', () {
      expect(step(5, TraversalDirection.left), const GridFocus(4, 0));
      expect(step(4, TraversalDirection.left), const GridExit(), reason: 'to the rail');
      expect(step(5, TraversalDirection.right), const GridFocus(6, 2));
      expect(step(7, TraversalDirection.right), const GridHold(), reason: 'no wrap into the next row');
      expect(step(9, TraversalDirection.right), const GridHold(), reason: 'the last card');
    });

    test('up and down keep the column; the first row leaves upwards, the last row downwards', () {
      expect(step(6, TraversalDirection.up), const GridFocus(2, 2));
      expect(step(2, TraversalDirection.up), const GridExit(), reason: 'to the filters above');
      expect(step(2, TraversalDirection.down), const GridFocus(6, 2));
      expect(step(9, TraversalDirection.down), const GridExit(), reason: 'to the footer');
    });

    test('a shorter last row lands on its last card and the column comes back', () {
      // 10 cards: the last row holds 8 and 9.
      final down = step(7, TraversalDirection.down) as GridFocus;
      expect(down, const GridFocus(9, 3));
      expect(step(down.index, TraversalDirection.up, column: down.column), const GridFocus(7, 3));
      // Without the remembered column the move up would follow the card's own column.
      expect(step(9, TraversalDirection.up), const GridFocus(5, 1));
    });

    test('a two-column grid (TV multiview) moves between the four cells', () {
      GridStep cell(int index, TraversalDirection d) => gridStep(index: index, direction: d, count: 4, columns: 2);
      expect(cell(0, TraversalDirection.right), const GridFocus(1, 1));
      expect(cell(1, TraversalDirection.down), const GridFocus(3, 1));
      expect(cell(3, TraversalDirection.left), const GridFocus(2, 0));
      expect(cell(2, TraversalDirection.up), const GridFocus(0, 0));
      expect(cell(1, TraversalDirection.right), const GridHold());
      expect(cell(0, TraversalDirection.up), const GridExit());
    });
  });

  group('TV theme and canvas', () {
    test('dark or black only, type one step up with body text at least 14 sp', () {
      final phone = PureTheme.of(Appearance.dark, platform: TargetPlatform.android);
      final tv = PureTheme.tv(Appearance.light, platform: TargetPlatform.android);
      expect(tv.brightness, Brightness.dark, reason: 'no light theme on TV');
      expect(PureTheme.tv(Appearance.black).colorScheme.surface, const Color(0xFF000000));
      final roles = {
        'bodySmall': (phone.textTheme.bodySmall!, tv.textTheme.bodySmall!),
        'bodyMedium': (phone.textTheme.bodyMedium!, tv.textTheme.bodyMedium!),
        'bodyLarge': (phone.textTheme.bodyLarge!, tv.textTheme.bodyLarge!),
        'labelSmall': (phone.textTheme.labelSmall!, tv.textTheme.labelSmall!),
        'labelMedium': (phone.textTheme.labelMedium!, tv.textTheme.labelMedium!),
        'labelLarge': (phone.textTheme.labelLarge!, tv.textTheme.labelLarge!),
        'titleSmall': (phone.textTheme.titleSmall!, tv.textTheme.titleSmall!),
        'titleMedium': (phone.textTheme.titleMedium!, tv.textTheme.titleMedium!),
        'titleLarge': (phone.textTheme.titleLarge!, tv.textTheme.titleLarge!),
        'headlineSmall': (phone.textTheme.headlineSmall!, tv.textTheme.headlineSmall!),
        'displayLarge': (phone.textTheme.displayLarge!, tv.textTheme.displayLarge!),
      };
      for (final MapEntry(key: role, value: (small, large)) in roles.entries) {
        expect(large.fontSize, greaterThan(small.fontSize!), reason: '$role is one step larger');
        expect(large.fontSize, greaterThanOrEqualTo(14), reason: role);
        expect(large.height! * large.fontSize!, greaterThanOrEqualTo(large.fontSize! * 1.4), reason: '$role line');
      }
      expect(tv.iconTheme.size, Sizes.iconLg);
      expect(tv.extension<LiveTheme>()!.focusRing, tv.colorScheme.onSurface, reason: 'near-white ring');
    });

    test('the canvas scale fits 960×540 into the screen', () {
      expect(tvCanvasScale(const Size(960, 540)), 1);
      expect(tvCanvasScale(const Size(961, 541)), 1, reason: 'rounding noise is not scaled');
      expect(tvCanvasScale(const Size(1920, 1080)), 2);
      expect(tvCanvasScale(const Size(1280, 720)), closeTo(4 / 3, 1e-9));
      expect(tvCanvasScale(const Size(1024, 768)), closeTo(1024 / 960, 1e-9), reason: '4:3 fits the width');
    });

    testWidgets('a 1920×1080 screen lays out at 960×540 with the overscan margins as padding', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late MediaQueryData seen;
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => TvRoot(config: const TvConfig(enabled: true), child: child!),
          home: Builder(
            builder: (context) {
              seen = MediaQuery.of(context);
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: 100, height: 100, child: GestureDetector(onTap: () => taps++)),
              );
            },
          ),
        ),
      );
      expect(seen.size, const Size(960, 540));
      expect(seen.devicePixelRatio, 2);
      expect(seen.padding, const EdgeInsets.symmetric(horizontal: 48, vertical: 28));
      // Hits go through the scale: the 100×100 box covers 200×200 physical pixels.
      await tester.tapAt(const Offset(190, 190));
      expect(taps, 1);
      await tester.tapAt(const Offset(210, 210));
      expect(taps, 1);
    });
  });

  group('focus', () {
    Widget host(Widget child, {bool tv = true}) => MaterialApp(
      theme: PureTheme.tv(Appearance.dark, platform: TargetPlatform.android),
      builder: (context, content) => TvScope(
        config: TvConfig(enabled: tv),
        child: content!,
      ),
      home: Scaffold(body: child),
    );

    testWidgets('OK opens a card, a long OK opens its menu, held OK does not repeat', (tester) async {
      var opens = 0;
      var menus = 0;
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox(
              width: 200,
              child: RoomCardView(
                platformId: 'douyu',
                anchorName: '主播',
                title: '标题',
                isLive: true,
                focusNode: node,
                onTap: () => opens++,
                onMenu: () => menus++,
              ),
            ),
          ),
        ),
      );
      node.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect((opens, menus), (1, 0));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      expect((opens, menus), (1, 1), reason: 'the menu, and no open on release');

      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      expect(menus, 2, reason: 'the menu key of older remotes');
    });

    testWidgets('a focused card grows 1.05× on TV; performance mode keeps the ring only', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      Future<double> scaleWith(TvConfig config) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: PureTheme.tv(Appearance.dark),
            builder: (context, content) => TvScope(config: config, child: content!),
            home: Material(
              child: Center(
                child: SizedBox(
                  width: 200,
                  child: RoomCardView(
                    platformId: 'douyu',
                    anchorName: '主播',
                    title: '标题',
                    isLive: true,
                    focusNode: node,
                  ),
                ),
              ),
            ),
          ),
        );
        FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
        node.requestFocus();
        await tester.pumpAndSettle();
        final scales = tester.widgetList<AnimatedScale>(find.byType(AnimatedScale));
        return scales.isEmpty ? 1 : scales.single.scale;
      }

      addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
      expect(await scaleWith(const TvConfig(enabled: true)), TvMetrics.focusScale);
      node.unfocus();
      await tester.pump();
      expect(await scaleWith(const TvConfig(enabled: true, focusGrowth: false)), 1);
      expect(await scaleWith(TvConfig.off), 1, reason: 'desktops keep the ring only');
    });

    testWidgets('D-pad moves by row and column, and focus comes back to the card after a page', (tester) async {
      const count = 10;
      final grid = TvGridFocus();
      addTearDown(grid.dispose);
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisExtent: 220),
              itemCount: count,
              itemBuilder: (context, index) => RoomCardView(
                platformId: 'douyu',
                anchorName: '主播$index',
                title: '标题',
                isLive: true,
                focusNode: grid.node(index),
                onFocusChange: (focused) {
                  if (focused) grid.focused(index);
                },
                onKeyEvent: (node, event) => grid.handleKey(index, event, count: count, columns: 4),
                onTap: () =>
                    Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('直播间')))),
              ),
            ),
          ),
        ),
      );
      grid.node(0).requestFocus();
      await tester.pump();
      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }

      await press(LogicalKeyboardKey.arrowRight);
      await press(LogicalKeyboardKey.arrowRight);
      await press(LogicalKeyboardKey.arrowRight);
      expect(grid.node(3).hasPrimaryFocus, isTrue);
      await press(LogicalKeyboardKey.arrowRight);
      expect(grid.node(3).hasPrimaryFocus, isTrue, reason: 'the row end holds');
      await press(LogicalKeyboardKey.arrowDown);
      await press(LogicalKeyboardKey.arrowDown);
      expect(grid.node(9).hasPrimaryFocus, isTrue, reason: 'the short last row takes its last card');
      await press(LogicalKeyboardKey.arrowUp);
      expect(grid.node(7).hasPrimaryFocus, isTrue, reason: 'column memory');
      await press(LogicalKeyboardKey.arrowLeft);
      expect(grid.lastIndex, 6);

      await press(LogicalKeyboardKey.select);
      expect(find.text('直播间'), findsOneWidget);
      expect(grid.node(6).hasFocus, isFalse);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(grid.node(6).hasPrimaryFocus, isTrue, reason: 'back on the card the room was opened from');
    });
  });

  testWidgets('a dialog opened by remote gets its first control focused', (tester) async {
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    await tester.pumpWidget(
      MaterialApp(
        theme: PureTheme.tv(Appearance.dark),
        builder: (context, child) => TvRoot(config: const TvConfig(enabled: true), child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              autofocus: true,
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('选择'),
                  actions: [
                    TextButton(onPressed: () {}, child: const Text('第一')),
                    TextButton(onPressed: () {}, child: const Text('第二')),
                  ],
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    final primary = FocusManager.instance.primaryFocus!;
    expect(primary, isNot(isA<FocusScopeNode>()), reason: 'a control, not the route scope');
    final focused = find.byWidget(primary.context!.widget);
    expect(find.descendant(of: focused, matching: find.text('第一')), findsOneWidget);
    expect(find.descendant(of: focused, matching: find.text('第二')), findsNothing);
  });

  testWidgets('list rows get the 3 dp ring, inside the row and its viewport; buttons in a row keep theirs', (
    tester,
  ) async {
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    tester.view
      ..physicalSize = const Size(960, 540)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final theme = PureTheme.tv(Appearance.dark);
    final ringColor = theme.extension<LiveTheme>()!.focusRing;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => TvRoot(config: const TvConfig(enabled: true), child: child!),
        home: Scaffold(
          body: ListView(
            children: [
              ListTile(autofocus: true, title: const Text('通用'), onTap: () {}),
              SwitchListTile(title: const Text('开关'), value: true, onChanged: (_) {}),
              ListTile(
                title: const Text('带按钮'),
                trailing: IconButton(icon: const LiveIcon(LiveIcons.more), onPressed: () {}),
                onTap: () {},
              ),
              for (var i = 0; i < 20; i++) ListTile(title: Text('行 $i'), onTap: () {}),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final rings = find.byType(TvListFocusRings);
    Rect row(String text) => tester.getRect(find.ancestor(of: find.text(text), matching: find.byType(ListTile)));
    // Any stroke of 3 dp in the ring colour along the row's inside edge.
    PaintPattern ringOn(String text) {
      final expected = row(text).deflate(1.5);
      return paints..something((method, arguments) {
        if (method != #drawRect) return false;
        final paint = arguments[1] as Paint;
        return arguments[0] == expected &&
            paint.style == PaintingStyle.stroke &&
            paint.strokeWidth == 3 &&
            // Paint keeps 32-bit floats: compare the 8-bit channels.
            paint.color.toARGB32() == ringColor.toARGB32();
      });
    }

    // The focus fill alone was all a focused row had (1.9:1 on the sofa).
    expect(rings, ringOn('通用'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(rings, ringOn('开关'), reason: 'a switch row');
    expect(rings, isNot(ringOn('通用')));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(rings, ringOn('带按钮'));
    Focus.of(tester.element(_icon(LiveIcons.more))).requestFocus();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus!.context!.findAncestorWidgetOfExactType<IconButton>(), isNotNull);
    expect(rings, isNot(ringOn('带按钮')), reason: 'the button shows its own ring');

    // Far down the list the ring follows the scrolled row.
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final focused = FocusManager.instance.primaryFocus!.context!.findAncestorWidgetOfExactType<ListTile>()!;
    final text = (focused.title! as Text).data!;
    expect(rings, ringOn(text));
  });

  testWidgets("the D-pad reaches a row's trailing buttons and comes back (principles §5.3)", (tester) async {
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    final row = FocusNode(debugLabel: 'row');
    final first = FocusNode(debugLabel: 'first');
    final second = FocusNode(debugLabel: 'second');
    final below = FocusNode(debugLabel: 'below');
    addTearDown(() {
      for (final node in [row, first, second, below]) {
        node.dispose();
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: PureTheme.tv(Appearance.dark),
        builder: (context, child) => TvRoot(config: const TvConfig(enabled: true), child: child!),
        home: Scaffold(
          body: ListView(
            children: [
              ListTile(
                focusNode: row,
                autofocus: true,
                title: const Text('带两个按钮的行'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(focusNode: first, icon: const LiveIcon(LiveIcons.refresh), onPressed: () {}),
                    IconButton(focusNode: second, icon: const LiveIcon(LiveIcons.more), onPressed: () {}),
                  ],
                ),
                onTap: () {},
              ),
              ListTile(focusNode: below, title: const Text('下一行'), onTap: () {}),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(row.hasPrimaryFocus, isTrue);
    Future<FocusNode?> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
      return FocusManager.instance.primaryFocus;
    }

    // The framework alone never left the row: its buttons lie inside it.
    expect(await press(LogicalKeyboardKey.arrowRight), first);
    expect(await press(LogicalKeyboardKey.arrowRight), second);
    expect(await press(LogicalKeyboardKey.arrowLeft), first);
    expect(await press(LogicalKeyboardKey.arrowLeft), row);
    expect(await press(LogicalKeyboardKey.arrowDown), below, reason: 'up and down move by row as before');
  });

  testWidgets('a focused segment of a segmented button gets the ring too', (tester) async {
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    tester.view
      ..physicalSize = const Size(960, 540)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: PureTheme.tv(Appearance.dark),
        builder: (context, child) => TvRoot(config: const TvConfig(enabled: true), child: child!),
        home: Scaffold(
          body: Center(
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('暂停')),
                ButtonSegment(value: 1, label: Text('退出')),
              ],
              selected: const {0},
              onSelectionChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    Focus.of(tester.element(find.text('退出'))).requestFocus();
    await tester.pump();
    final segment = tester.getRect(find.ancestor(of: find.text('退出'), matching: find.byType(TextButton)));
    expect(
      find.byType(TvListFocusRings),
      paints..something((method, arguments) {
        if (method != #drawRect) return false;
        final paint = arguments[1] as Paint;
        return arguments[0] == segment.deflate(1.5) && paint.style == PaintingStyle.stroke && paint.strokeWidth == 3;
      }),
    );
  });

  testWidgets('a focused tab gets the ring too', (tester) async {
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    tester.view
      ..physicalSize = const Size(960, 540)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final theme = PureTheme.tv(Appearance.dark);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => TvRoot(config: const TvConfig(enabled: true), child: child!),
        home: DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              bottom: const TabBar(
                tabs: [
                  Tab(text: '关注'),
                  Tab(text: '历史'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Focus.of(tester.element(find.text('历史'))).requestFocus();
    await tester.pump();
    final tab = tester.getRect(find.ancestor(of: find.text('历史'), matching: find.byType(InkWell)).first);
    expect(
      find.byType(TvListFocusRings),
      paints..something((method, arguments) {
        if (method != #drawRect) return false;
        final paint = arguments[1] as Paint;
        return arguments[0] == tab.deflate(1.5) && paint.style == PaintingStyle.stroke && paint.strokeWidth == 3;
      }),
    );
  });

  group('TvNavScaffold', () {
    const destinations = [
      NavDestination(icon: LiveIcons.follows, label: '关注'),
      NavDestination(icon: LiveIcons.discover, label: '发现'),
    ];

    testWidgets('the rail expands on focus; right enters the page where it left; left and back return', (tester) async {
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var selected = 0;
      final cards = [FocusNode(debugLabel: 'a'), FocusNode(debugLabel: 'b')];
      addTearDown(() {
        for (final node in cards) {
          node.dispose();
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: PureTheme.tv(Appearance.dark),
          builder: (context, child) => TvRoot(config: const TvConfig(enabled: true), child: child!),
          home: StatefulBuilder(
            builder: (context, setState) => TvNavScaffold(
              destinations: destinations,
              selectedIndex: selected,
              onSelected: (index) => setState(() => selected = index),
              body: Scaffold(
                appBar: AppBar(title: const Text('页面')),
                body: Row(
                  children: [
                    for (final node in cards)
                      SizedBox(
                        width: 200,
                        height: 120,
                        child: FocusFrame(focusNode: node, onActivate: () {}, child: const Text('卡片')),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final shell = tester.state<TvNavScaffoldState>(find.byType(TvNavScaffold));
      expect(shell.railFocused, isTrue, reason: 'the remote starts on the rail');
      expect(find.text('关注'), findsOneWidget, reason: 'expanded: labels show');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(cards[0].hasPrimaryFocus, isTrue, reason: 'the first card below the app bar');
      expect(shell.railFocused, isFalse);
      expect(find.text('关注'), findsNothing, reason: 'collapsed: icons only');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(cards[1].hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(shell.railFocused, isTrue, reason: 'left from the left edge');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(cards[0].hasPrimaryFocus, isTrue, reason: 'back where focus was');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      // Back on a top-level page moves focus to the rail instead of leaving.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(shell.railFocused, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(cards[1].hasPrimaryFocus, isTrue, reason: 'the rail remembers the card');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(selected, 1, reason: 'OK on a rail item opens it');
    });
  });
}

/// The [LiveIcon] showing [icon].
Finder _icon(LiveIcons icon) => find.byWidgetPredicate((widget) => widget is LiveIcon && widget.icon == icon);
