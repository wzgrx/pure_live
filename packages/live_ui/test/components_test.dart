import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

// docs/A-界面设计/A02-组件/A02.1-通用组件: the common components in every state (default,
// hover, keyboard focus, pressed, disabled, busy), both themes, contrast.

const _theme = LiveTheme(primaryColor: LiveTheme.brandBlue, schemeVariant: DynamicSchemeVariant.fidelity);

Widget _app(Widget child, {bool dark = false}) => MaterialApp(
  theme: _theme.light,
  darkTheme: _theme.dark,
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  home: Scaffold(body: child),
);

double _contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// Moves the focus like a keyboard and shows focus frames.
void _keyboard(WidgetTester tester) {
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
}

Finder _frames() =>
    find.byWidgetPredicate((widget) => widget is CustomPaint && widget.foregroundPainter is FocusRingPainter);

void main() {
  group('AppStatusView (c2–c7)', () {
    testWidgets('each state has its words, icon and button; a solid circle, no pop-in', (tester) async {
      final cases = <(AppStatusType, String, IconData)>[
        (AppStatusType.empty, '暂无数据', Icons.live_tv_rounded),
        (AppStatusType.error, '加载失败', Icons.error_outline_rounded),
        (AppStatusType.restricted, '需要登录账号', Icons.lock_outline_rounded),
        (AppStatusType.offline, '没有网络连接', Icons.wifi_off_rounded),
      ];
      for (final (type, title, icon) in cases) {
        await tester.pumpWidget(_app(AppStatusView(type: type, onButtonPressed: () {})));
        // 3.x popped in with a one-second elastic bounce (P4).
        expect(tester.hasRunningAnimations, isFalse, reason: '$type');
        expect(find.text(title), findsOneWidget, reason: '$type');
        expect(find.byIcon(icon), findsOneWidget, reason: '$type');
        expect(tester.getSize(find.byIcon(icon)).width, 40);
        final circle = tester.widget<Container>(
          find.ancestor(of: find.byIcon(icon), matching: find.byType(Container)).first,
        );
        final decoration = circle.decoration! as BoxDecoration;
        expect(decoration.color, _theme.light.colorScheme.surfaceContainer);
        expect(decoration.shape, BoxShape.circle);
      }
      expect(find.text('没有网络连接'), findsOneWidget);
      expect(find.text('检查网络后重试；连上网络后会自动刷新'), findsOneWidget);

      // The restricted state's button says what it does (C1, U.4e c6).
      await tester.pumpWidget(_app(AppStatusView(type: AppStatusType.restricted, onButtonPressed: () {})));
      final button = find.byKey(const ValueKey('status-button'));
      expect(find.descendant(of: button, matching: find.text('前往登录')), findsOneWidget);
      expect(find.descendant(of: button, matching: find.byIcon(Icons.login_rounded)), findsOneWidget);
    });

    testWidgets('loading says what it waits for; the spinner follows where it is (P1, P22)', (tester) async {
      Future<double> spinner(Widget view, Size window) async {
        tester.view.physicalSize = window;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(_app(view));
        return tester.widget<DefaultLoadingIndicator>(find.byType(DefaultLoadingIndicator)).size;
      }

      addTearDown(tester.view.reset);
      const phone = Size(393, 852);
      const wide = Size(1280, 800);
      expect(await spinner(const AppStatusView(type: AppStatusType.loading), phone), 28);
      expect(find.text('加载中...'), findsOneWidget);
      expect(await spinner(const AppStatusView(type: AppStatusType.loading), wide), 32);
      // In a block or a card it stays small on any window.
      expect(await spinner(const AppStatusView(type: AppStatusType.loading, compact: true), wide), 24);
      expect(await spinner(const AppStatusView(type: AppStatusType.loading, title: '正在进入直播间…'), phone), 28);
      expect(find.text('正在进入直播间…'), findsOneWidget);
      await spinner(const AppStatusView(type: AppStatusType.loading, isMini: true), phone);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('C4: the raw error waits behind "详情", whole, selectable and copied', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      const raw = 'DioException [bad response]: status code of 412';
      await tester.pumpWidget(
        _app(
          AppStatusView(
            type: AppStatusType.error,
            subtitle: '平台拒绝了请求（412），可能是请求太频繁，稍后再试',
            details: raw,
            onButtonPressed: () {},
          ),
        ),
      );
      // The page shows the sentence, not the raw text.
      expect(find.text(raw), findsNothing);
      expect(tester.widget(find.byKey(const ValueKey('status-details-button'))), isA<TextButton>());
      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('status-details')), findsOneWidget);
      expect(find.widgetWithText(SelectableText, raw), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('status-details-copy')));
      await tester.pumpAndSettle();
      expect(copied, raw);
      expect(find.byKey(const ValueKey('status-details')), findsNothing);
      expect(find.text('已复制到剪贴板'), findsOneWidget);
    });

    testWidgets('c7: on a phone held sideways (852×393) the state lies on its side', (tester) async {
      tester.view.physicalSize = const Size(852, 393);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(AppStatusView(type: AppStatusType.error, onButtonPressed: () {})));
      final icon = tester.getRect(find.byIcon(Icons.error_outline_rounded));
      final title = tester.getRect(find.text('加载失败'));
      expect(icon.right, lessThan(title.left));
      expect(tester.getRect(find.byKey(const ValueKey('status-button'))).left, closeTo(title.left, 1));
      expect(tester.getSize(find.byIcon(Icons.error_outline_rounded)).width, 32);
      // A block stays upright.
      await tester.pumpWidget(_app(const AppStatusView(type: AppStatusType.empty, compact: true)));
      expect(
        tester.getRect(find.byIcon(Icons.live_tv_rounded)).bottom,
        lessThan(tester.getRect(find.text('暂无数据')).top),
      );
    });

    testWidgets('a block: a 32 icon in the variant ink without the circle', (tester) async {
      await tester.pumpWidget(_app(const AppStatusView(type: AppStatusType.empty, compact: true)));
      final icon = tester.widget<Icon>(find.byIcon(Icons.live_tv_rounded));
      expect(icon.size, 32);
      expect(icon.color, _theme.light.colorScheme.onSurfaceVariant);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Container && (widget.decoration as BoxDecoration?)?.shape == BoxShape.circle,
        ),
        findsNothing,
      );
    });

    testWidgets('busy: the first button spins and takes no taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(AppStatusView(type: AppStatusType.error, busy: true, onButtonPressed: () => taps++)),
      );
      expect(find.byKey(const ValueKey('status-button-busy')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('status-button')));
      expect(taps, 0);
    });

    test('the title and the reason keep 4.5:1 on the page in both themes', () {
      for (final theme in [_theme.light, _theme.dark]) {
        final colors = theme.colorScheme;
        expect(_contrast(colors.onSurface, colors.surface), greaterThan(4.5));
        expect(_contrast(colors.onSurfaceVariant, colors.surface), greaterThan(4.5));
        expect(_contrast(colors.primary, colors.surfaceContainer), greaterThan(3));
      }
    });

    testWidgets('a list skeleton is static rows (c3, no shimmer)', (tester) async {
      await tester.pumpWidget(_app(const SizedBox(height: 400, child: StatusSkeleton())));
      expect(find.byKey(const ValueKey('status-skeleton')), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('StatusBanner (c8)', () {
    testWidgets('one bar in three colours; actions under the words, ✕ 48 to tap', (tester) async {
      var never = 0;
      var closed = 0;
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              const StatusBanner(key: ValueKey('info'), kind: StatusBannerKind.info, text: 'CHZZK 只能看到正在直播的房间'),
              StatusBanner(
                key: const ValueKey('warning'),
                kind: StatusBannerKind.warning,
                text: '您当前正在使用移动蜂窝流量，请注意流量消耗。',
                actions: [(key: const ValueKey('never'), label: '不再显示', onPressed: () => never++)],
                onClose: () => closed++,
              ),
              StatusBanner(
                key: const ValueKey('error'),
                kind: StatusBannerKind.error,
                text: '刷新失败：网络连接超时，下面是上次的内容。',
                actions: [(key: null, label: '重试', onPressed: () {})],
              ),
            ],
          ),
        ),
      );
      final colors = _theme.light.colorScheme;
      Color ground(String key) => tester
          .widget<Material>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Material)).first)
          .color!;
      expect(ground('info'), colors.surfaceContainerLow);
      expect(ground('warning'), LiveSemanticColors.warningContainer(Brightness.light));
      expect(ground('error'), colors.errorContainer);
      final words = tester.getRect(find.text('您当前正在使用移动蜂窝流量，请注意流量消耗。'));
      expect(tester.getRect(find.byKey(const ValueKey('never'))).top, greaterThan(words.top));
      expect(tester.getSize(find.byKey(const ValueKey('status-banner-close'))), const Size(48, 48));
      await tester.tap(find.byKey(const ValueKey('never')));
      await tester.tap(find.byKey(const ValueKey('status-banner-close')));
      expect((never, closed), (1, 1));
      // The words keep 4.5:1 on every ground, both themes.
      for (final dark in [false, true]) {
        final scheme = (dark ? _theme.dark : _theme.light).colorScheme;
        final brightness = dark ? Brightness.dark : Brightness.light;
        expect(_contrast(scheme.onSurfaceVariant, scheme.surfaceContainerLow), greaterThan(4.5));
        expect(_contrast(scheme.onSurface, LiveSemanticColors.warningContainer(brightness)), greaterThan(4.5));
        expect(_contrast(scheme.onErrorContainer, scheme.errorContainer), greaterThan(4.5));
      }
    });

    testWidgets('an explanation keeps to two lines until tapped', (tester) async {
      await tester.pumpWidget(
        _app(const StatusBanner(kind: StatusBannerKind.info, text: '很长的说明。很长的说明。很长的说明。很长的说明。很长的说明。很长的说明。')),
      );
      Text text() => tester.widget<Text>(find.textContaining('很长的说明'));
      expect(text().maxLines, 2);
      await tester.tap(find.byType(StatusBanner));
      await tester.pump();
      expect(text().maxLines, isNull);
    });
  });

  group('CommonAvatar (c9)', () {
    testWidgets('no picture: the first letter on the secondary container; no name: a person', (tester) async {
      await tester.pumpWidget(_app(const CommonAvatar(avatarUrl: '', fallbackName: '晚风')));
      final colors = _theme.light.colorScheme;
      final disc = tester.widget<Container>(find.byKey(const ValueKey('avatar-fallback')));
      expect((disc.decoration! as BoxDecoration).color, colors.secondaryContainer);
      expect(tester.widget<Text>(find.text('晚')).style!.color, colors.onSecondaryContainer);
      // 3.x drew an empty grey disc (P7).
      await tester.pumpWidget(_app(const CommonAvatar(avatarUrl: null)));
      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    });

    testWidgets('a tappable avatar: a tap, and the keyboard frame', (tester) async {
      _keyboard(tester);
      var taps = 0;
      await tester.pumpWidget(
        _app(
          Center(
            child: CommonAvatar(avatarUrl: '', fallbackName: 'a', onTap: () => taps++, tooltip: '主播'),
          ),
        ),
      );
      expect(_frames(), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_frames(), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.tap(find.byType(CommonAvatar));
      expect(taps, 2);
    });
  });

  group('CounterControl (c10)', () {
    testWidgets('outlined, 36 high, each half 48 to tap; the limit greys its half', (tester) async {
      var steps = 0;
      await tester.pumpWidget(
        _app(
          Center(
            child: CounterControl(value: '0', onDecrease: null, onIncrease: () => steps++),
          ),
        ),
      );
      final frame = find.byKey(const ValueKey('counter-frame'));
      expect(tester.getSize(frame).height, 36);
      final decoration = tester.widget<DecoratedBox>(frame).decoration as BoxDecoration;
      expect((decoration.border! as Border).top.color, _theme.light.colorScheme.outlineVariant);
      final halves = find.byType(IconButton);
      expect(tester.getSize(halves.first), const Size(48, 48));
      expect(tester.widget<IconButton>(halves.first).onPressed, isNull, reason: 'at the lower limit');
      expect(tester.widget<Text>(find.text('0')).style!.color, _theme.light.colorScheme.primary);
      await tester.tap(halves.last);
      expect(steps, 1);
    });

    testWidgets('not usable: greyed out, not hidden (U.2f D5)', (tester) async {
      await tester.pumpWidget(
        _app(
          Center(
            child: CounterControl(value: '5', enabled: false, onDecrease: () {}, onIncrease: () {}),
          ),
        ),
      );
      for (final button in tester.widgetList<IconButton>(find.byType(IconButton))) {
        expect(button.onPressed, isNull);
      }
      expect(tester.widget<Text>(find.text('5')).style!.color!.a, closeTo(0.38, 0.01));
    });

    testWidgets('keyboard: ← and → step while the focus is on it', (tester) async {
      _keyboard(tester);
      var value = 0;
      await tester.pumpWidget(
        _app(
          Center(
            child: StatefulBuilder(
              builder: (context, setState) => CounterControl(
                value: '$value',
                onDecrease: () => setState(() => value--),
                onIncrease: () => setState(() => value++),
              ),
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(value, 1);
      // The focused half has the frame (the theme's buttons).
      final focused = tester.widgetList<IconButton>(find.byType(IconButton)).first;
      expect(focused.style, isNotNull);
    });
  });

  group('QrCodeCard (c11)', () {
    testWidgets('every state lies over the code, which never moves; white paper in the dark theme', (tester) async {
      Rect? place;
      for (final status in QrCodeStatus.values) {
        await tester.pumpWidget(
          _app(
            Center(
              child: QrCodeCard(
                data: 'https://example.com/qr',
                status: status,
                message: '二维码已失效',
                actionLabel: '刷新',
                onAction: () {},
              ),
            ),
            dark: true,
          ),
        );
        final code = tester.getRect(find.byKey(const ValueKey('qr-code')));
        place ??= code;
        expect(code, place, reason: '$status');
        expect(code.size, const Size(200, 200));
        if (status == QrCodeStatus.ready) {
          expect(find.text('二维码已失效'), findsNothing);
        } else {
          expect(find.byKey(ValueKey('qr-${status.name}')), findsOneWidget);
        }
        final paper = tester.widget<Container>(
          find.descendant(of: find.byKey(const ValueKey('qr-code')), matching: find.byType(Container)).first,
        );
        expect((paper.decoration! as BoxDecoration).color, QrColors.paper);
      }
      await tester.pumpWidget(
        _app(QrCodeCard(data: null, status: QrCodeStatus.expired, actionLabel: '刷新', onAction: () {})),
      );
      expect(find.widgetWithText(FilledButton, '刷新'), findsOneWidget);
    });
  });

  group('tabs (c12)', () {
    testWidgets('a number, a badge; the keyboard frame on the focused tab', (tester) async {
      _keyboard(tester);
      await tester.pumpWidget(
        _app(
          const DefaultTabController(
            length: 3,
            child: TabBar(
              tabs: [
                TabLabel(label: '已开播', count: 12, countKey: ValueKey('count')),
                TabLabel(label: '醒目留言', badge: '2'),
                TabLabel(label: '未开播'),
              ],
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('count')), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(_frames(), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_frames(), findsOneWidget);
      final theme = _theme.light.tabBarTheme;
      expect(theme.splashBorderRadius, BorderRadius.circular(8));
      expect(theme.overlayColor!.resolve({WidgetState.hovered}), isNot(Colors.transparent));
    });

    testWidgets('the second row: 14, the chosen one dark and semi-bold, the indicator under the tab', (tester) async {
      await tester.pumpWidget(
        _app(
          const DefaultTabController(
            length: 2,
            child: SecondaryTabBar(
              tabs: [
                TabLabel(label: '网游'),
                TabLabel(label: '手游'),
              ],
            ),
          ),
        ),
      );
      final bar = tester.widget<TabBar>(find.byType(TabBar));
      final colors = _theme.light.colorScheme;
      expect(bar.labelColor, colors.onSurface);
      expect(bar.unselectedLabelColor, colors.onSurfaceVariant);
      expect(bar.labelStyle!.fontSize, 14);
      expect(bar.labelStyle!.fontWeight, FontWeight.w600);
      expect(bar.indicatorSize, TabBarIndicatorSize.tab);
      expect(bar.dividerHeight, 1);
    });
  });

  group('AppChip (c13)', () {
    testWidgets("36 high, 8 corners; chosen: the secondary container and a tick in the logo's place", (tester) async {
      await tester.pumpWidget(
        _app(
          Wrap(
            children: [
              AppChip(key: const ValueKey('on'), label: '全部', selected: true, onSelected: () {}),
              AppChip(
                key: const ValueKey('off'),
                label: '哔哩哔哩',
                selected: false,
                leading: const Icon(Icons.live_tv, key: ValueKey('logo')),
                onSelected: () {},
              ),
              AppChip(key: const ValueKey('disabled'), label: '常看', selected: false, onSelected: null),
            ],
          ),
        ),
      );
      final chip = find.byKey(const ValueKey('on'));
      expect(tester.widget(chip), isA<ChoiceChip>());
      expect(find.descendant(of: chip, matching: find.byIcon(Icons.check_rounded)), findsOneWidget);
      expect(find.byKey(const ValueKey('logo')), findsOneWidget);
      final theme = _theme.light;
      expect(theme.chipTheme.shape, const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))));
      expect(theme.chipTheme.selectedColor, theme.colorScheme.secondaryContainer);
      final side = theme.chipTheme.side! as AppChipSide;
      expect(side.resolve({}), BorderSide(color: theme.colorScheme.outlineVariant));
      expect(side.resolve({WidgetState.selected})!.width, 0);
      // The chip itself: 36 high (48 to tap).
      final rendered = find.descendant(of: find.byKey(const ValueKey('off')), matching: find.byType(RawChip));
      expect(tester.getSize(rendered).height, 48);
      expect(
        tester
            .getSize(
              find.descendant(
                of: rendered,
                matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ChipRenderWidget'),
              ),
            )
            .height,
        appChipHeight,
      );
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('disabled'))).onSelected, isNull);
      // Android's standard density: 36 (desktops' compact density takes 4).
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  });

  group('rows and switches (c14–c17)', () {
    testWidgets('a row: title 15 regular (C3), explanation 12 in the variant ink at 4.5:1 on the card', (tester) async {
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          _app(
            SettingsGroup(
              title: '画质设置',
              children: [
                SettingsLinkRow(title: '首选清晰度', subtitle: '当进入直播播放页，首选的视频清晰度', value: '原画', choice: true, onTap: () {}),
                SettingsLinkRow(title: '竖屏直播适配', onTap: () {}),
              ],
            ),
            dark: dark,
          ),
        );
        await tester.pumpAndSettle();
        final colors = (dark ? _theme.dark : _theme.light).colorScheme;
        final title = tester.widget<Text>(find.text('首选清晰度')).style!;
        expect(title.fontSize, 15);
        expect(title.fontWeight, FontWeight.w400);
        final subtitle = tester.widget<Text>(find.text('当进入直播播放页，首选的视频清晰度')).style!;
        expect(subtitle.fontSize, 12);
        expect(subtitle.color, colors.onSurfaceVariant);
        // 3.x: hint colour at 75 %, about 3.4:1 (TASKS §7 from U.10b).
        expect(_contrast(subtitle.color!, colors.surfaceContainerLow), greaterThan(4.5));
        final group = tester.widget<Text>(find.text('画质设置')).style!;
        expect((group.fontSize, group.fontWeight, group.color), (13.0, FontWeight.w600, colors.primary));
        expect(_contrast(colors.primary, colors.surface), greaterThan(4.5));
      }
      // C2: a choice ends in ⌄, a page in ›.
      expect(find.byIcon(Icons.expand_more_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    });

    testWidgets('a switch being changed: a spinner before the greyed switch, no taps', (tester) async {
      var changes = 0;
      await tester.pumpWidget(
        _app(SettingsSwitchRow(title: '后台播放', value: true, busy: true, onChanged: (_) => changes++)),
      );
      expect(find.byKey(const ValueKey('settings-row-busy')), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
      final busy = tester.getRect(find.byKey(const ValueKey('settings-row-busy')));
      expect(busy.right, lessThanOrEqualTo(tester.getRect(find.byType(Switch)).left));
      await tester.tap(find.text('后台播放'));
      expect(changes, 0);
    });

    testWidgets("c14: one switch, Material's: the on thumb stands out from its track", (tester) async {
      for (final theme in [_theme.light, _theme.dark]) {
        // No page or theme overrides the thumb (3.x's eight activeThumbColor).
        expect(theme.switchTheme.thumbColor, isNull);
        expect(theme.switchTheme.trackColor, isNull);
        // Material 3: an on switch has an onPrimary thumb on the primary track.
        expect(_contrast(theme.colorScheme.onPrimary, theme.colorScheme.primary), greaterThan(3));
      }
    });

    testWidgets('list rows: 15 regular, 12 explanation, at least 56 high; the chosen one on the secondary container', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const ListTile(leading: Icon(Icons.copy), title: Text('复制'))));
      expect(tester.getSize(find.byType(ListTile)).height, 56);
      final theme = _theme.light.listTileTheme;
      expect(theme.titleTextStyle!.fontSize, 15);
      expect(theme.titleTextStyle!.fontWeight, FontWeight.w400);
      expect(theme.subtitleTextStyle!.fontSize, 12);
      expect(theme.selectedTileColor, _theme.light.colorScheme.secondaryContainer);
    });
  });

  group('the list shell (c20) and Esc', () {
    testWidgets('"to top" shows past 400; it looks 40 and takes 48', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          Stack(
            children: [
              ListView.builder(
                controller: controller,
                itemExtent: 100,
                itemCount: 100,
                itemBuilder: (_, i) => Text('$i'),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: ScrollJumpButtons(
                  controller: controller,
                  heroTag: 'test',
                  topTooltip: '回到顶部',
                  bottomTooltip: '到底部',
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final top = find.byKey(const ValueKey('jump-top'));
      expect(tester.widget<AnimatedScale>(find.ancestor(of: top, matching: find.byType(AnimatedScale))).scale, 0);
      controller.jumpTo(500);
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedScale>(find.ancestor(of: top, matching: find.byType(AnimatedScale))).scale, 1);
      expect(tester.getSize(top), const Size(48, 48));
      await tester.tap(top);
      await tester.pumpAndSettle();
      expect(controller.offset, 0);
    });

    testWidgets("EscapeBack: Esc does what Back does, or the page's own step first", (tester) async {
      var filterClosed = 0;
      await tester.pumpWidget(_app(const Text('home')));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator))
        ..push(
          MaterialPageRoute<void>(
            builder: (_) => const EscapeBack(child: Scaffold(body: Text('page'))),
          ),
        );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('page'), findsNothing);

      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => EscapeBack(
            onEscape: () => filterClosed++,
            child: const Scaffold(body: Text('filter')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(filterClosed, 1);
      expect(find.text('filter'), findsOneWidget);
    });
  });

  group('focus frames (c21)', () {
    testWidgets('only for the keyboard: buttons, chips and custom widgets', (tester) async {
      final frame = FocusFrame(_theme.light.colorScheme.primary);
      FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
      addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
      await tester.pump();
      expect(frame.resolve({WidgetState.focused}), isNull);
      _keyboard(tester);
      await tester.pump();
      expect(frame.resolve({WidgetState.focused}), BorderSide(color: _theme.light.colorScheme.primary, width: 2));
      expect(frame.resolve({}), isNull);
      // Rebuilt themes compare equal, so they do not animate.
      expect(_theme.light, _theme.light);
      expect(_theme.dark, _theme.dark);

      await tester.pumpWidget(
        _app(
          Center(
            child: FocusRing(
              child: TextButton(onPressed: () {}, child: const Text('重试')),
            ),
          ),
        ),
      );
      expect(_frames(), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(_frames(), findsOneWidget);
    });
  });
}
