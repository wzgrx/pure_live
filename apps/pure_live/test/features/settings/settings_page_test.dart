import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_catalog.dart';
import 'package:pure_live/features/settings/settings_editors.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/paging.dart';

import '../../support.dart';

final class _Harness {
  new(this.services, this.toasts, this.opened);

  final AppServices services;
  final List<String> toasts;
  final List<String> opened;

  SettingsStore get settings => services.store.settings;
}

/// Pumps the settings page over an in-memory store at [width] × [height];
/// other routes show their path (so links can be checked).
Future<_Harness> _pump(
  WidgetTester tester, {
  double width = 400,
  double height = 1600,
  Object? arguments,
  Future<void> Function(SettingsStore settings)? seed,
}) async {
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(() async {
    final services = await testServices();
    await seed?.call(services.store.settings);
    return services;
  }))!;
  addTearDown(() => tester.runAsync(services.close));
  addTearDown(AutoExitTimer.instance.detach);
  final strings = (await tester.runAsync(loadStrings))!;
  final toasts = <String>[];
  final previousToast = AppNavigator.toast;
  AppNavigator.toast = toasts.add;
  addTearDown(() => AppNavigator.toast = previousToast);
  final opened = <String>[];
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => SettingsPage(route: RouteArgs(RoutePath.kSettings, arguments: arguments)),
      ),
      for (final path in [
        RoutePath.kSettingsDanmuShield,
        RoutePath.kSettingsAccount,
        RoutePath.kBackup,
        RoutePath.kIptv,
        RoutePath.kRecordSettings,
      ])
        GoRoute(
          path: path,
          builder: (_, _) {
            opened.add(path);
            return Scaffold(body: Text('page $path'));
          },
        ),
    ],
  );
  AppNavigator.router = router;
  addTearDown(() => AppNavigator.router = null);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services)],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp.router(
          theme: const LiveTheme(primaryColor: LiveTheme.brandBlue, schemeVariant: DynamicSchemeVariant.fidelity).light,
          routerConfig: router,
        ),
      ),
    ),
  );
  await _settle(tester);
  return _Harness(services, toasts, opened);
}

/// Lets the store's writes (real async work) finish, then the frames.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
  }
}

Finder _row(String id) => find.byKey(ValueKey('settings-entry-$id'));

Finder _section(SettingsSection section) => find.byKey(ValueKey('settings-section-${section.name}'));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await _settle(tester);
}

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('settings-search')), text);
  // The search waits for a pause in typing.
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

void _expectInOrder(WidgetTester tester, List<Finder> finders) {
  for (var i = 1; i < finders.length; i++) {
    expect(_top(tester, finders[i]), greaterThan(_top(tester, finders[i - 1])), reason: '$i');
  }
}

Future<void> _withPlatform(TargetPlatform platform, Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  setUpAll(loadStrings);

  group('overview (U.6a)', () {
    testWidgets('five groups and the 3.x rows in their new order, with their icons', (tester) async {
      await _pump(tester, height: 2600);
      _expectInOrder(tester, [
        for (final title in ['界面', '直播来源', '播放', '通用和网络', '数据']) find.text(title),
      ]);
      _expectInOrder(tester, [for (final section in SettingsSection.values) _section(section)]);
      expect(SettingsSection.values.map((section) => section.name), [
        'appearance',
        'navigation',
        'platforms',
        'refresh',
        'iptv',
        'video',
        'danmaku',
        'pipDanmaku',
        'playerKernel',
        'recording',
        'general',
        'network',
        'localInteraction',
        'cache',
        'backup',
        'configPreview',
      ]);
      // "主题定制" is "外观"; "配置预览" left the app bar for the data group.
      expect(find.descendant(of: _section(SettingsSection.appearance), matching: find.text('外观')), findsOneWidget);
      expect(find.text('本地配置预览'), findsOneWidget);
      expect(find.widgetWithText(AppBar, '设置'), findsOneWidget);
      expect(find.byTooltip('配置预览'), findsNothing);
      // The icons of 3.x's rows; danmaku is 3.x's picture.
      for (final (section, icon) in [
        (SettingsSection.appearance, AppIcons.settingsAppearance),
        (SettingsSection.iptv, AppIcons.settingsIptv),
        (SettingsSection.video, AppIcons.settingsVideo),
        (SettingsSection.recording, AppIcons.settingsRecording),
        (SettingsSection.backup, AppIcons.settingsBackup),
      ]) {
        expect(find.descendant(of: _section(section), matching: find.byIcon(icon)), findsOneWidget);
      }
      expect(
        find.descendant(of: _section(SettingsSection.danmaku), matching: find.byType(DanmakuIcon)),
        findsOneWidget,
      );
      // Explanations show up to two lines (3.x cut them at one).
      final explanation = tester.widget<HighlightedText>(
        find.descendant(of: _section(SettingsSection.appearance), matching: find.byType(HighlightedText)).last,
      );
      expect(explanation.maxLines, 2);
    });

    testWidgets('a row opens its page; back returns to the overview; route pages open their route', (tester) async {
      final h = await _pump(tester);
      await _tap(tester, _section(SettingsSection.video));
      expect(find.byKey(const ValueKey('settings-page-video')), findsOneWidget);
      expect(_row('prefer_resolution'), findsOneWidget);
      // The danmaku of floating windows has one entry, in the overview.
      expect(_row('pip_danmaku'), findsNothing);
      await tester.tap(find.byType(BackButton));
      await _settle(tester);
      expect(find.byKey(const ValueKey('settings-overview')), findsOneWidget);

      for (final (section, route) in [
        (SettingsSection.iptv, RoutePath.kIptv),
        (SettingsSection.recording, RoutePath.kRecordSettings),
        (SettingsSection.backup, RoutePath.kBackup),
      ]) {
        await _tap(tester, _section(section));
        expect(h.opened.last, route);
        AppNavigator.router.pop();
        await _settle(tester);
      }
    });

    testWidgets('the system back closes the open page before leaving (back chain)', (tester) async {
      await _pump(tester, arguments: 'appearance');
      expect(find.byKey(const ValueKey('settings-page-appearance')), findsOneWidget);
      await _tap(tester, _row('room_card'));
      expect(find.text('应用到'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(find.byKey(const ValueKey('settings-page-appearance')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(find.byKey(const ValueKey('settings-overview')), findsOneWidget);
    });

    testWidgets('840 wide and up: the overview at 360 and the page beside it; sub-pages stay there', (tester) async {
      await _pump(tester, width: 1280, height: 1400);
      expect(tester.getSize(find.byKey(const ValueKey('settings-overview'))).width, settingsOverviewWidth);
      final page = find.byKey(const ValueKey('settings-page-appearance'));
      expect(page, findsOneWidget);
      expect(tester.getTopLeft(page).dx, greaterThan(settingsOverviewWidth));
      // The open page is marked in the overview.
      final selected = tester.widget<SettingsLinkRow>(_section(SettingsSection.appearance));
      expect(selected.selected, isTrue);
      // The page body keeps at most 720 at the start.
      expect(
        tester.getSize(find.byKey(const ValueKey('settings-section-view-appearance'))).width,
        lessThanOrEqualTo(1280 - settingsOverviewWidth),
      );

      await _tap(tester, _row('room_card'));
      expect(find.byKey(const ValueKey('settings-room-card-preview')), findsOneWidget);
      expect(tester.getTopLeft(find.text('应用到')).dx, greaterThan(settingsOverviewWidth));
      expect(find.byKey(const ValueKey('settings-overview')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(page, findsOneWidget);

      await _tap(tester, _section(SettingsSection.network));
      expect(find.byKey(const ValueKey('settings-page-network')), findsOneWidget);
      expect(tester.widget<SettingsLinkRow>(_section(SettingsSection.network)).selected, isTrue);
    });

    testWidgets('a landscape phone gets two panes and a compact bar; 600–839 one column at most 720', (tester) async {
      await _pump(tester, width: 852, height: 393);
      expect(find.byKey(const ValueKey('settings-overview')), findsOneWidget);
      expect(tester.getSize(find.byType(AppBar).first).height, 48);

      await _pump(tester, width: 760, height: 1000);
      expect(find.widgetWithText(AppBar, '设置'), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('settings-search'))).width, lessThanOrEqualTo(720));
      expect(tester.getSize(find.byType(AppBar).first).height, kToolbarHeight);
    });

    testWidgets('resizing across 840 keeps the open page', (tester) async {
      await _pump(tester, width: 1280, height: 1400);
      await _tap(tester, _section(SettingsSection.general));
      tester.view.physicalSize = const Size(500, 1000);
      await _settle(tester);
      expect(find.byKey(const ValueKey('settings-page-general')), findsOneWidget);
      tester.view.physicalSize = const Size(1280, 1400);
      await _settle(tester);
      expect(find.byKey(const ValueKey('settings-page-general')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-overview')), findsOneWidget);
    });
  });

  group('search (U.6a c8)', () {
    testWidgets('results are the rows under "page › group" with the words marked', (tester) async {
      final h = await _pump(tester);
      await _search(tester, '字体');
      expect(find.byKey(const ValueKey('settings-search-results')), findsOneWidget);
      expect(find.text('外观 › 字体和字号'), findsOneWidget);
      expect(_row('app_font'), findsOneWidget);
      expect(_row('text_scale'), findsOneWidget);
      expect(_row('danmaku_font'), findsOneWidget);
      expect(tester.widget<SettingsHighlight>(find.byType(SettingsHighlight)).words, ['字体']);

      // A switch works in place.
      await _search(tester, 'HEVC');
      await tester.tap(_row('prefer_h264'));
      await _settle(tester);
      expect(h.settings.get(Settings.preferH264), isFalse);

      // Every word must match.
      await _search(tester, '弹幕 速度');
      expect(_row('danmaku_speed'), findsOneWidget);
      expect(_row('app_proxy'), findsNothing);

      await _search(tester, '完全不存在的设置');
      expect(find.byKey(const ValueKey('settings-search-empty')), findsOneWidget);
      expect(find.text('没有找到相关设置'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-search-clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-overview')), findsOneWidget);
    });

    testWidgets('a result that opens a page goes to its page and highlights the row', (tester) async {
      await _pump(tester);
      await _search(tester, '字体');
      await _tap(tester, _row('app_font'));
      expect(find.byKey(const ValueKey('settings-page-appearance')), findsOneWidget);
      // The font page itself did not open.
      expect(find.text('系统字体'), findsNothing);
      expect(_row('app_font'), findsOneWidget);
      // Back returns to the results.
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(find.byKey(const ValueKey('settings-search-results')), findsOneWidget);
    });

    testWidgets('Ctrl+F goes to the field, Esc clears it', (tester) async {
      await _pump(tester, width: 1280, height: 800);
      await tester.tap(_row('theme_mode'));
      await tester.pumpAndSettle();
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byKey(const ValueKey('settings-search')));
      expect(field.focusNode!.hasFocus, isTrue);
      await _search(tester, '代理');
      expect(find.byKey(const ValueKey('settings-search-results')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(field.controller!.text, isEmpty);
      expect(find.byKey(const ValueKey('settings-overview')), findsOneWidget);
    });
  });

  group('appearance (U.6b)', () {
    testWidgets('four groups, rows in order, values on the rows', (tester) async {
      await _withPlatform(TargetPlatform.android, () async {
        await _pump(tester, arguments: 'appearance', height: 2200);
        _expectInOrder(tester, [
          for (final title in ['主题', '房间卡片和列表', '语言和界面', '字体和字号']) find.text(title),
        ]);
        _expectInOrder(tester, [
          for (final id in [
            'theme_mode',
            'pure_black',
            'theme_color',
            'dynamic_color',
            'loading_style',
            'room_card',
            'cross_spacing',
            'main_spacing',
            'page_scroll_top',
            'language',
            'ui_mode',
            'app_font',
            'text_scale',
            'font_sizes',
          ])
            _row(id),
        ]);
        expect(find.descendant(of: _row('theme_mode'), matching: find.text('跟随系统')), findsOneWidget);
        expect(find.descendant(of: _row('language'), matching: find.text('简体中文')), findsOneWidget);
        expect(find.descendant(of: _row('cross_spacing'), matching: find.text('6 px')), findsOneWidget);
        expect(find.descendant(of: _row('text_scale'), matching: find.text('100%')), findsOneWidget);
        expect(find.descendant(of: _row('app_font'), matching: find.text('系统默认')), findsOneWidget);
        expect(find.text('Default'), findsNothing);
        // The pager is on computers only (3.x showed it wider than 680).
        expect(_row('page_settings'), findsNothing);
        expect(find.byKey(const ValueKey('settings-text-size-preview')), findsOneWidget);
      });
    });

    testWidgets('theme mode and language: a dialog without buttons; the pick is stored', (tester) async {
      final h = await _pump(tester, arguments: 'appearance');
      await _tap(tester, _row('theme_mode'));
      expect(find.byType(RadioListTile<String>), findsNWidgets(3));
      _expectInOrder(tester, [find.text('跟随系统').last, find.text('深色模式'), find.text('浅色模式')]);
      expect(find.text('取消'), findsNothing);
      await _tap(tester, find.text('深色模式'));
      expect(h.settings.get(Settings.themeMode), 'Dark');
      expect(find.descendant(of: _row('theme_mode'), matching: find.text('深色模式')), findsOneWidget);

      await _tap(tester, _row('language'));
      expect(find.text('跟随系统'), findsNothing);
      await _tap(tester, find.byKey(const ValueKey('settings-choice-English')));
      expect(h.settings.get(Settings.language), 'English');
    });

    testWidgets('pure black: off by default, unusable in light mode with the reason', (tester) async {
      final h = await _pump(tester, arguments: 'appearance');
      await tester.tap(find.descendant(of: _row('pure_black'), matching: find.byType(Switch)));
      await _settle(tester);
      expect(h.settings.get(Settings.pureBlackTheme), isTrue);
      await tester.runAsync(() => h.settings.set(Settings.themeMode, 'Light'));
      await _settle(tester);
      expect(find.text('浅色模式下不起作用：先把主题模式换成深色或跟随系统'), findsOneWidget);
      await tester.tap(_row('pure_black'), warnIfMissed: false);
      await _settle(tester);
      expect(h.settings.get(Settings.pureBlackTheme), isTrue);
    });

    testWidgets('theme colour: previews while picking, cancel puts it back, the code is checked', (tester) async {
      final h = await _pump(tester, arguments: 'appearance', seed: (s) => s.set(Settings.themeColorSwitch, 'FF009688'));
      await _tap(tester, _row('theme_color'));
      // "推荐" first, the brand blue first in it.
      expect(find.text('推荐'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('color-recommended-0')));
      expect(h.settings.get(Settings.themeColorSwitch), 'FF2E6FE0');
      await _tap(tester, find.byKey(const ValueKey('settings-color-cancel')));
      expect(h.settings.get(Settings.themeColorSwitch), 'FF009688');

      await _tap(tester, _row('theme_color'));
      await _tap(tester, find.byKey(const ValueKey('color-tab-1')));
      await _tap(tester, find.byKey(const ValueKey('color-primary-0')));
      await tester.enterText(find.byKey(const ValueKey('color-code')), '#12');
      await _tap(tester, find.byKey(const ValueKey('settings-color-apply')));
      expect(find.text('请输入 6 位 RGB 或 8 位 ARGB 十六进制颜色代码'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('color-code')), '#F44336');
      await _tap(tester, find.byKey(const ValueKey('settings-color-apply')));
      expect(h.settings.get(Settings.themeColorSwitch), 'FFF44336');

      // Dynamic colour decides while on: the row says so and is not usable.
      await tester.runAsync(() => h.settings.set(Settings.enableDynamicTheme, true));
      await _settle(tester);
      expect(find.text('动态取色开着，颜色来自壁纸；关掉动态取色后才能选'), findsOneWidget);
    });

    testWidgets('spacing: − and + by 1 px; the number opens the checked dialog', (tester) async {
      final h = await _pump(tester, arguments: 'appearance');
      await _tap(tester, find.byKey(const ValueKey('settings-spacing-plus-crossAxisSpacing')));
      expect(h.settings.get(Settings.crossAxisSpacing), 7);
      await _tap(tester, find.byKey(const ValueKey('settings-spacing-minus-mainAxisSpacing')));
      expect(h.settings.get(Settings.mainAxisSpacing), 5);

      await _tap(tester, find.byKey(const ValueKey('settings-spacing-value-crossAxisSpacing')));
      await tester.enterText(find.byKey(const ValueKey('settings-spacing-input')), '99');
      await _tap(tester, find.byKey(const ValueKey('settings-spacing-save')));
      expect(find.text('请输入 0 到 64 之间的间距'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('settings-spacing-preset-12')));
      await _tap(tester, find.byKey(const ValueKey('settings-spacing-save')));
      expect(h.settings.get(Settings.crossAxisSpacing), 12);
    });

    testWidgets('computers: the pager page, its go-to switch and the page sizes', (tester) async {
      await _withPlatform(TargetPlatform.windows, () async {
        final h = await _pump(tester, arguments: 'appearance');
        await _tap(tester, _row('page_settings'));
        expect(find.byKey(const ValueKey('settings-section-view-paging')), findsOneWidget);
        expect(find.text('分页条（电脑）'), findsOneWidget);
        await tester.tap(find.descendant(of: _row('page_goto'), matching: find.byType(Switch)));
        await _settle(tester);
        expect(h.settings.get(Settings.pageShowGotoButton), isFalse);

        await _tap(tester, _row('page_size_options'));
        // Nothing chosen yet: the recommended sizes for this width.
        expect(find.byKey(const ValueKey('settings-page-size-12')), findsOneWidget);
        await tester.enterText(find.byKey(const ValueKey('settings-page-size-input')), '24');
        await _tap(tester, find.byKey(const ValueKey('settings-page-size-add')));
        expect(find.text('该单页数量已在列表中'), findsOneWidget);
        await tester.enterText(find.byKey(const ValueKey('settings-page-size-input')), '0');
        await _tap(tester, find.byKey(const ValueKey('settings-page-size-add')));
        expect(find.text('请输入 1 至 100 的整数'), findsOneWidget);
        await tester.enterText(find.byKey(const ValueKey('settings-page-size-input')), '30');
        await _tap(tester, find.byKey(const ValueKey('settings-page-size-add')));
        await _tap(tester, find.byKey(const ValueKey('settings-page-sizes-save')));
        expect(h.settings.get(Settings.pageSizeOptions), '12,24,30,36,48');
      });
    });

    testWidgets('text sizes: an example per size; reset asks first', (tester) async {
      final h = await _pump(tester, arguments: 'appearance', seed: (s) => s.set(Settings.fontSizeBodySmall, 14));
      await _tap(tester, _row('font_sizes'));
      final sample = tester.widget<Text>(find.byKey(const ValueKey('settings-font-sample-font_body_small')));
      expect(sample.style!.fontSize, 14);
      await _tap(tester, find.byKey(const ValueKey('settings-font-sizes-reset')));
      expect(find.text('将五项精细字号全部恢复为默认值？'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('settings-confirm')));
      expect(h.settings.get(Settings.fontSizeBodySmall), 12);
      expect(h.toasts, ['恢复默认']);
    });

    testWidgets('loading animation: three columns on a phone; restore asks first', (tester) async {
      final h = await _pump(tester, arguments: 'appearance', seed: (s) => s.set(Settings.loadingStyle, 'wave'));
      // The gallery keeps playing: frames by time instead of settling.
      Future<void> frames() async {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(seconds: 1));
        }
      }

      await tester.tap(_row('loading_style'));
      await frames();
      final keys = LoadingStyles.keys;
      Offset at(int index) => tester.getTopLeft(find.byKey(ValueKey('settings-loading-style-${keys[index]}')));
      expect(at(1).dy, at(0).dy);
      expect(at(2).dy, at(0).dy);
      expect(at(3).dy, greaterThan(at(0).dy));
      expect(find.textContaining('现在：跟随主题色'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-loading-restore')));
      await frames();
      expect(find.text('恢复默认？'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-confirm')));
      await frames();
      await frames();
      expect(h.settings.get(Settings.loadingStyle), 'default');
    });

    testWidgets('room cards: names the devices, reset asks first, a change makes it custom', (tester) async {
      await _withPlatform(TargetPlatform.android, () async {
        final h = await _pump(tester, arguments: 'appearance');
        await _tap(tester, _row('room_card'));
        expect(find.text('移动端（手机、平板）'), findsOneWidget);
        expect(find.text('桌面端（电脑）'), findsOneWidget);
        expect(find.text('改了下面任何一项，就显示“当前：自定义”，点一个预设回到它的样子。'), findsOneWidget);
        await _tap(tester, find.byKey(const ValueKey('settings-room-card-avatar')));
        expect(find.text('当前：自定义。点一个预设回到它的样子。'), findsOneWidget);
        await _tap(tester, find.byKey(const ValueKey('settings-room-card-reset')));
        expect(find.text('“移动端（手机、平板）”的卡片恢复成“标准”预设。'), findsOneWidget);
        await _tap(tester, find.byKey(const ValueKey('settings-confirm')));
        expect(h.settings.isSet(Settings.roomCardMobilePreset), isFalse);
      });
    });
  });

  group('navigation (U.6b)', () {
    testWidgets('multi-view on every platform; hidden pages last, at least one stays', (tester) async {
      await _withPlatform(TargetPlatform.android, () async {
        final h = await _pump(
          tester,
          arguments: 'navigation',
          seed: (s) => s.set(Settings.savedMenuIds, ['favorites', 'areas']),
        );
        await tester.tap(find.descendant(of: _row('multiview'), matching: find.byType(Switch)));
        await _settle(tester);
        expect(h.settings.get(Settings.enableMultiView), isFalse);

        Finder menu(String id) => find.byKey(ValueKey('settings-menu-$id'));
        _expectInOrder(tester, [menu('favorites'), menu('areas'), menu('popular'), menu('record')]);
        expect(find.descendant(of: menu('popular'), matching: find.text('已隐藏')), findsOneWidget);
        expect(find.byKey(const ValueKey('settings-menu-handle-popular')), findsNothing);
        expect(find.byKey(const ValueKey('settings-menu-handle-favorites')), findsOneWidget);
        expect(find.text('按住右侧把手上下拖动可以调整顺序；隐藏的排在最后，至少保留一个。'), findsOneWidget);

        await _tap(tester, find.descendant(of: menu('popular'), matching: find.byType(Switch)));
        expect(h.settings.get(Settings.savedMenuIds), ['favorites', 'areas', 'popular']);
        await _tap(tester, menu('favorites'));
        await _tap(tester, menu('areas'));
        await _tap(tester, menu('popular'));
        expect(h.settings.get(Settings.savedMenuIds), ['popular']);
        expect(h.toasts, ['请至少保留一个底部菜单标签页。']);
      });
    });
  });

  group('the other pages keep their rows until U.6c–U.6e', () {
    testWidgets('choices and numbers with a checked custom value', (tester) async {
      final h = await _pump(tester, arguments: 'video');
      expect(find.descendant(of: _row('prefer_resolution'), matching: find.text('原画')), findsOneWidget);
      await _tap(tester, _row('prefer_resolution'));
      await _tap(tester, find.byKey(const ValueKey('settings-choice-超清')));
      expect(h.settings.get(Settings.preferResolution), '超清');

      await _pump(tester, arguments: 'refresh');
      await _tap(tester, _row('history_limit'));
      await tester.enterText(find.byKey(const ValueKey('settings-number-input')), '');
      await _tap(tester, find.byKey(const ValueKey('settings-number-save')));
      expect(find.text('可填写 0～99999'), findsWidgets);
    });

    testWidgets('platform rows follow the operating system', (tester) async {
      await _withPlatform(TargetPlatform.windows, () async {
        await _pump(tester, arguments: 'general');
        expect(_row('window_size'), findsOneWidget);
        expect(_row('startup'), findsOneWidget);
        expect(_row('screen_keep_on'), findsNothing);
      });
      const windows = SettingsEnv(platform: TargetPlatform.windows);
      const android = SettingsEnv(platform: TargetPlatform.android);
      const ios = SettingsEnv(platform: TargetPlatform.iOS);
      List<String> ids(SettingsEnv env) => [
        for (final entry in settingsCatalog)
          if (entry.when(env)) entry.id,
      ];
      expect(ids(android), containsAll(['background_play', 'screen_keep_on', 'compat_mode', 'mobile_volume']));
      expect(ids(android), isNot(contains('page_size_selector')));
      expect(ids(windows), containsAll(['rtx_vsr', 'pip_on_top', 'desktop_volume', 'new_window', 'page_goto']));
      expect(ids(ios), isNot(contains('dynamic_color')));
      // Ids are unique; the platform accounts row is named "平台账号" (U.10a K1).
      expect(settingsCatalog.map((entry) => entry.id).toSet(), hasLength(settingsCatalog.length));
      expect(settingsCatalog.firstWhere((entry) => entry.id == 'accounts').titleText, '平台账号');
    });

    testWidgets('the exit countdown runs while switched on', (tester) async {
      final h = await _pump(tester, arguments: 'general', seed: (s) => s.set(Settings.autoShutDownTime, 1));
      expect(AutoExitTimer.instance.remaining.value, isNull);
      await _tap(tester, find.descendant(of: _row('auto_exit'), matching: find.byType(Switch)));
      expect(h.settings.get(Settings.enableAutoShutDownTime), isTrue);
      expect(AutoExitTimer.instance.remaining.value, isNotNull);
      await _tap(tester, find.descendant(of: _row('auto_exit'), matching: find.byType(Switch)));
      expect(AutoExitTimer.instance.remaining.value, isNull);
    });

    test('local interaction opens its own page (U.2k)', () {
      expect(SettingsSection.localInteraction.route, RoutePath.kLocalInteraction);
    });
  });

  testWidgets('the go-to switch reaches the pager (3.x stored it but never read it, U.6b c7)', (tester) async {
    Future<void> bar({required bool showGoto}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaginationBar(
            page: 1,
            lastPage: 5,
            canNext: true,
            busy: false,
            pageSize: 20,
            pageSizes: const [20, 40],
            showGoto: showGoto,
            onPage: (_) {},
            onPageSize: (_) {},
            onRefresh: () {},
          ),
        ),
      ),
    );
    await bar(showGoto: true);
    expect(find.byKey(const ValueKey('pager-goto')), findsOneWidget);
    await bar(showGoto: false);
    expect(find.byKey(const ValueKey('pager-goto')), findsNothing);
  });

  test('search needs every word and ignores blanks', () {
    expect(searchSettings(settingsCatalog, '   '), isEmpty);
    expect(formatMinutes(30), '30 分钟');
    expect(formatMinutes(90), '1.5 小时');
    expect(formatMinutes(120), '2 小时');
    expect(SettingsSection.byName('network'), SettingsSection.network);
    expect(SettingsSection.byName(SettingsSection.danmaku), SettingsSection.danmaku);
    expect(SettingsSection.byName('nothing'), isNull);
  });
}
