import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

import '../../support.dart';

final class _Harness {
  new(this.services, this.toasts, this.opened);

  final AppServices services;
  final List<String> toasts;
  final List<String> opened;

  SettingsStore get settings => services.store.settings;
}

/// Pumps the settings page over an in-memory store at [width]; other routes
/// show their path (so links can be checked).
Future<_Harness> _pump(
  WidgetTester tester, {
  double width = 400,
  Object? arguments,
  Future<void> Function(SettingsStore settings)? seed,
}) async {
  tester.view
    ..physicalSize = Size(width, 1600)
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
      for (final path in [RoutePath.kSettingsDanmuShield, RoutePath.kSettingsAccount, RoutePath.kBackup])
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
          theme: const LiveTheme(primaryColor: Colors.blue).light,
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

Future<void> _tapRow(WidgetTester tester, String id) async {
  await tester.ensureVisible(_row(id));
  await tester.pumpAndSettle();
  await tester.tap(_row(id));
  await _settle(tester);
}

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(
    find.descendant(of: find.byKey(const ValueKey('settings-search')), matching: find.byType(TextField)),
    text,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadStrings);

  testWidgets('phones list the sections; a section opens on its own page and switches store at once', (tester) async {
    final h = await _pump(tester);
    for (final section in SettingsSection.values) {
      expect(find.byKey(ValueKey('settings-section-${section.name}')), findsOneWidget, reason: section.name);
    }
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('弹幕样式、过滤、屏蔽和小窗弹幕'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-section-danmaku')));
    await _settle(tester);
    expect(find.widgetWithText(AppBar, '弹幕'), findsOneWidget);
    expect(_row('danmaku_show'), findsOneWidget);
    // Nothing changed yet: no "restore defaults".
    expect(find.byKey(const ValueKey('settings-section-reset')), findsNothing);

    await tester.tap(find.descendant(of: _row('danmaku_show'), matching: find.byType(Switch)));
    await _settle(tester);
    expect(h.settings.get(Settings.enableDanmakuDisplay), isFalse);

    // "Danmaku on the video" is the opposite of hideDanmaku.
    await tester.tap(find.descendant(of: _row('danmaku_on_video'), matching: find.byType(Switch)));
    await _settle(tester);
    expect(h.settings.get(Settings.hideDanmaku), isTrue);

    // The block list is a link to its own page.
    await _tapRow(tester, 'block_list');
    expect(h.opened, [RoutePath.kSettingsDanmuShield]);
  });

  testWidgets('restoring a section puts back only what changed there', (tester) async {
    final h = await _pump(
      tester,
      seed: (settings) =>
          settings.setAll({Settings.danmakuSpeed: 200.0, Settings.noEmojiMode: true, Settings.themeMode: 'Dark'}),
    );
    // The section list counts the changes.
    expect(
      find.descendant(of: find.byKey(const ValueKey('settings-section-danmaku')), matching: find.text('2')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('settings-section-danmaku')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('settings-section-reset')));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 项将恢复默认值'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-confirm')));
    await _settle(tester);
    expect(h.settings.get(Settings.danmakuSpeed), 120);
    expect(h.settings.get(Settings.noEmojiMode), isFalse);
    expect(h.settings.get(Settings.themeMode), 'Dark');
    expect(h.toasts, ['已恢复默认设置']);
    expect(find.byKey(const ValueKey('settings-section-reset')), findsNothing);
  });

  testWidgets('search finds rows across sections, every word must match, and they work in place', (tester) async {
    final h = await _pump(tester);
    await _search(tester, '代理');
    expect(find.byKey(const ValueKey('settings-search-results')), findsOneWidget);
    expect(_row('app_proxy'), findsOneWidget);
    expect(_row('player_proxy'), findsOneWidget);
    expect(find.text('网络与代理'), findsOneWidget);

    await _search(tester, '弹幕 速度');
    expect(_row('danmaku_speed'), findsOneWidget);
    expect(_row('app_proxy'), findsNothing);

    // Keywords in either language find a row.
    await _search(tester, 'HEVC');
    expect(_row('prefer_h264'), findsOneWidget);
    await tester.tap(find.descendant(of: _row('prefer_h264'), matching: find.byType(Switch)));
    await _settle(tester);
    expect(h.settings.get(Settings.preferH264), isFalse);

    await _search(tester, '完全不存在的设置');
    expect(find.byKey(const ValueKey('settings-search-empty')), findsOneWidget);
    expect(find.text('没有找到相关设置'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-search-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-section-appearance')), findsOneWidget);
  });

  testWidgets('choices, numbers with a checked custom value, and the language', (tester) async {
    final h = await _pump(tester, arguments: 'playback');
    // The arguments open the section directly.
    expect(find.widgetWithText(AppBar, '播放'), findsOneWidget);
    expect(find.descendant(of: _row('prefer_resolution'), matching: find.text('原画')), findsOneWidget);
    await _tapRow(tester, 'prefer_resolution');
    await tester.tap(find.byKey(const ValueKey('settings-choice-超清')));
    await _settle(tester);
    expect(h.settings.get(Settings.preferResolution), '超清');
    expect(find.descendant(of: _row('prefer_resolution'), matching: find.text('超清')), findsOneWidget);

    // Video fit is stored as 3.x's index.
    await _tapRow(tester, 'video_fit');
    await tester.tap(find.byKey(const ValueKey('settings-choice-3')));
    await _settle(tester);
    expect(h.settings.get(Settings.videoFitIndex), 3);
  });

  testWidgets('a number dialog checks the custom value against the range', (tester) async {
    final h = await _pump(tester, arguments: 'follows');
    await _tapRow(tester, 'history_limit');
    await tester.enterText(find.byKey(const ValueKey('settings-number-input')), '');
    await tester.tap(find.byKey(const ValueKey('settings-number-save')));
    await tester.pumpAndSettle();
    expect(find.text('可填写 0～99999'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('settings-number-200')));
    await _settle(tester);
    expect(h.settings.get(Settings.historyLimit), 200);

    // A bounded setting: refresh interval 5..360, only with auto refresh on.
    await tester.tap(find.descendant(of: _row('auto_refresh'), matching: find.byType(Switch)));
    await _settle(tester);
    await _tapRow(tester, 'refresh_interval');
    await tester.enterText(find.byKey(const ValueKey('settings-number-input')), '999');
    await tester.tap(find.byKey(const ValueKey('settings-number-save')));
    await tester.pumpAndSettle();
    expect(find.text('可填写 5～360'), findsWidgets);
    expect(h.settings.get(Settings.autoRefreshInterval), 30);
    await tester.enterText(find.byKey(const ValueKey('settings-number-input')), '75');
    await tester.tap(find.byKey(const ValueKey('settings-number-save')));
    await _settle(tester);
    expect(h.settings.get(Settings.autoRefreshInterval), 75);
    expect(find.descendant(of: _row('refresh_interval'), matching: find.text('75 分钟')), findsOneWidget);
  });

  testWidgets('language follows the system until one is picked, and can go back', (tester) async {
    final h = await _pump(tester, arguments: 'appearance');
    expect(find.descendant(of: _row('language'), matching: find.text('跟随系统')), findsOneWidget);
    await _tapRow(tester, 'language');
    await tester.tap(find.byKey(const ValueKey('settings-choice-English')));
    await _settle(tester);
    expect(h.settings.get(Settings.language), 'English');
    expect(h.settings.isSet(Settings.language), isTrue);

    await _tapRow(tester, 'language');
    await tester.tap(find.byKey(const ValueKey('settings-choice-system')));
    await _settle(tester);
    expect(h.settings.isSet(Settings.language), isFalse);

    // Theme mode is three buttons on the row.
    await tester.tap(find.byIcon(Remix.moon_line));
    await _settle(tester);
    expect(h.settings.get(Settings.themeMode), 'Dark');

    // Theme colour from 3.x's palette.
    await _tapRow(tester, 'theme_color');
    await tester.tap(find.byKey(const ValueKey('settings-color-Teal')));
    await _settle(tester);
    expect(h.settings.get(Settings.themeColorSwitch), 'FF009688');
  });

  testWidgets('wide windows show sections beside their content', (tester) async {
    final h = await _pump(tester, width: 1200);
    expect(find.byKey(const ValueKey('settings-section-view-appearance')), findsOneWidget);
    // Paging controls exist on wide screens only (3.x).
    expect(_row('page_size_selector'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-section-network')));
    await _settle(tester);
    expect(find.byKey(const ValueKey('settings-section-view-network')), findsOneWidget);

    // Turning a proxy on without an address asks for one first.
    await tester.tap(find.byKey(const ValueKey('settings-proxy-app-switch')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('settings-proxy-host')), 'http://127.0.0.1/');
    await tester.enterText(find.byKey(const ValueKey('settings-proxy-port')), '70000');
    await tester.tap(find.byKey(const ValueKey('settings-proxy-save')));
    await tester.pumpAndSettle();
    expect(find.text('请输入 1 到 65535 之间的端口'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('settings-proxy-port')), '7890');
    await tester.tap(find.byKey(const ValueKey('settings-proxy-save')));
    await _settle(tester);
    expect(h.settings.get(Settings.appProxyHost), '127.0.0.1');
    expect(h.settings.get(Settings.appProxyPort), 7890);
    expect(h.settings.get(Settings.enableAppProxy), isTrue);
    expect(h.settings.get(Settings.enableProxy), isFalse);
  });

  testWidgets('platform rows follow the operating system', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _pump(tester, arguments: 'general');
      expect(_row('window_size'), findsOneWidget);
      expect(_row('startup'), findsOneWidget);
      expect(_row('refresh_rate'), findsOneWidget);
      expect(_row('screen_keep_on'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }

    const windows = SettingsEnv(platform: TargetPlatform.windows, wide: false);
    const android = SettingsEnv(platform: TargetPlatform.android, wide: false);
    const linux = SettingsEnv(platform: TargetPlatform.linux, wide: false);
    List<String> ids(SettingsEnv env) => [
      for (final entry in settingsCatalog)
        if (entry.when(env)) entry.id,
    ];
    expect(ids(android), containsAll(['background_play', 'screen_keep_on', 'compat_mode', 'mobile_volume']));
    expect(ids(android), isNot(contains('window_size')));
    expect(ids(windows), containsAll(['rtx_vsr', 'pip_on_top', 'desktop_volume', 'new_window']));
    expect(ids(windows), isNot(contains('background_play')));
    expect(ids(linux), isNot(contains('refresh_rate')));
    expect(ids(android), isNot(contains('page_size_selector')));
    // Ids are unique and every row has words in both languages.
    expect(settingsCatalog.map((entry) => entry.id).toSet(), hasLength(settingsCatalog.length));
  });

  testWidgets('Twitch languages offer 3.x preset; home menus keep at least one', (tester) async {
    final h = await _pump(tester, arguments: 'platforms');
    expect(find.descendant(of: _row('twitch_languages'), matching: find.text('全部语言')), findsOneWidget);
    await _tapRow(tester, 'twitch_languages');
    await tester.tap(find.byKey(const ValueKey('settings-twitch-legacy')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-twitch-ja')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-twitch-save')));
    await _settle(tester);
    expect(h.settings.get(Settings.twitchLanguages), ['zh', 'ko', 'ja']);
  });

  testWidgets('home menus: switch off and on, never the last one', (tester) async {
    final h = await _pump(
      tester,
      arguments: 'general',
      seed: (s) => s.set(Settings.savedMenuIds, ['favorites', 'areas']),
    );
    await _tapRow(tester, 'home_menus');
    Finder menuSwitch(String id) =>
        find.descendant(of: find.byKey(ValueKey('settings-menu-$id')), matching: find.byType(Switch));
    await tester.tap(menuSwitch('popular'));
    await _settle(tester);
    expect(h.settings.get(Settings.savedMenuIds), ['favorites', 'areas', 'popular']);
    await tester.tap(menuSwitch('favorites'));
    await _settle(tester);
    await tester.tap(menuSwitch('areas'));
    await _settle(tester);
    expect(h.settings.get(Settings.savedMenuIds), ['popular']);
    await tester.tap(menuSwitch('popular'));
    await _settle(tester);
    expect(h.settings.get(Settings.savedMenuIds), ['popular']);
    expect(h.toasts, ['请至少保留一个底部菜单标签页。']);
  });

  testWidgets('the exit countdown runs while switched on and quits at zero', (tester) async {
    var quits = 0;
    final previousQuit = AutoExitTimer.quit;
    AutoExitTimer.quit = () => quits++;
    addTearDown(() => AutoExitTimer.quit = previousQuit);
    final h = await _pump(tester, arguments: 'general', seed: (s) => s.set(Settings.autoShutDownTime, 1));
    expect(AutoExitTimer.instance.remaining.value, isNull);
    await tester.tap(find.descendant(of: _row('auto_exit'), matching: find.byType(Switch)));
    await _settle(tester);
    expect(h.settings.get(Settings.enableAutoShutDownTime), isTrue);
    expect(AutoExitTimer.instance.remaining.value, isNotNull);
    expect(find.textContaining('剩余时间: 00:0'), findsOneWidget);
    await tester.tap(find.descendant(of: _row('auto_exit'), matching: find.byType(Switch)));
    await _settle(tester);
    expect(AutoExitTimer.instance.remaining.value, isNull);
    expect(quits, 0);
  });

  test('3.x danmaku margins are pixels and survive the registry', () {
    expect(Settings.danmakuTopArea.read(40), 40);
    expect(Settings.danmakuBottomArea.read(120.5), 120.5);
    expect(Settings.danmakuTopArea.read(900), 300);
    expect(Settings.textScaleFactor.read(5), 2);
    expect(Settings.fontSizeTitleLarge.read(10), 16);
  });

  test('search needs every word and ignores blanks', () {
    expect(searchSettings(settingsCatalog, '   '), isEmpty);
    expect(formatMinutes(30), '30 分钟');
    expect(formatMinutes(90), '1.5 小时');
    expect(formatMinutes(120), '2 小时');
  });
}
