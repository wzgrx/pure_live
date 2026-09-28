import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/locale.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/settings/settings_page.dart';
import 'package:pure_live_app/features/settings/settings_search.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// principles §4.4: the settings search finds every setting by its title,
/// its description or its 3.x name, in each language, and shows it in its
/// group.
void main() {
  tearDown(() => applyAppLocale(AppLocale.zhHans));

  Future<LiveStore> openStore(WidgetTester tester) async {
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    return store;
  }

  Set<String> anchorsOnScreen(WidgetTester tester) => {
    for (final anchor in tester.widgetList<SettingAnchor>(find.byType(SettingAnchor, skipOffstage: false))) anchor.id,
  };

  for (final group in SettingsGroup.values) {
    testWidgets('${group.name}: the index and the tiles agree', (tester) async {
      final store = await openStore(tester);
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storeProvider.overrideWithValue(store)],
          child: MaterialApp(
            theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
            home: Scaffold(body: SettingsGroupBody(group: group)),
          ),
        ),
      );
      await tester.pump();
      final shown = anchorsOnScreen(tester);
      final indexed = {
        for (final entry in settingsIndex())
          if (entry.group == group) entry.id,
      };
      expect(indexed.difference(shown), isEmpty, reason: 'every indexed setting has a tile to show');
      expect(shown.difference(indexed), isEmpty, reason: 'every tile of the group can be found');
    });
  }

  // Each setting has one tile per device: the phone's default volume once
  // showed twice on Android (under 音量 and again at the end of 播放). The
  // host running the tests is Linux, so the Android and Windows tiles are
  // built by asking for them.
  for (final (name, android, windows) in [
    ('Android', true, false),
    ('Windows', false, true),
    ('Linux', false, false),
  ]) {
    testWidgets('$name: every playback setting shows once, and the index lists exactly those', (tester) async {
      final store = await openStore(tester);
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storeProvider.overrideWithValue(store)],
          child: MaterialApp(
            theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: playbackSettingTiles(android: android, windows: windows),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final shown = [
        for (final anchor in tester.widgetList<SettingAnchor>(find.byType(SettingAnchor, skipOffstage: false)))
          anchor.id,
      ];
      final repeated = {
        for (final id in shown)
          if (shown.where((other) => other == id).length > 1) id,
      };
      expect(repeated, isEmpty, reason: 'a setting shows twice');
      final indexed = [
        for (final entry in settingsIndex(android: android, windows: windows))
          if (entry.group == SettingsGroup.playback) entry.id,
      ];
      expect(indexed.toSet(), hasLength(indexed.length), reason: 'the index lists a setting twice');
      expect(shown.toSet(), indexed.toSet());
      expect(
        shown.where((id) => id == Settings.defaultMobileVolume.id),
        hasLength(1),
        reason: 'phones show it under 音量, desktops at the end',
      );
    });
  }

  test('every 3.x name belongs to an indexed setting', () {
    final entries = [...settingsIndex(android: true, windows: false), ...settingsIndex(android: false, windows: true)];
    for (final MapEntry(:key, value: names) in t.settings.search.legacy.entries) {
      expect(
        entries.any((entry) => entry.legacy.join('|') == names),
        isTrue,
        reason: '$key names no setting (keys are setting ids with "_" for ".")',
      );
    }
  });

  group('search', () {
    List<String> titles(String query) => [
      for (final match in searchSettings(query, settingsIndex())) match.entry.title,
    ];

    test('titles, descriptions and case-insensitive English', () {
      expect(titles('画质').take(2), ['默认画质（Wi-Fi）', '默认画质（移动网络）']);
      expect(titles('OLED'), ['纯黑'], reason: 'the description says OLED');
      expect(titles('没有这个设置'), isEmpty);
    });

    test('3.x names find the setting and say so', () {
      final match = searchSettings('首选清晰度', settingsIndex()).single;
      expect(match.entry.id, Settings.qualityWifi.id);
      expect(match.legacyName, '首选清晰度');
      expect(searchSettings('屏蔽管理', settingsIndex()).single.entry.id, blockListAnchor);
    });

    test('Traditional Chinese and English search their own text', () {
      applyAppLocale(AppLocale.zhHant);
      expect(titles('畫質'), contains('預設畫質（Wi-Fi）'));
      expect(searchSettings('首選清晰度', settingsIndex()).single.entry.id, Settings.qualityWifi.id);
      applyAppLocale(AppLocale.en);
      expect(searchSettings('low latency', settingsIndex()).first.entry.id, Settings.lowLatency.id);
      expect(searchSettings('resolution preference', settingsIndex()).single.entry.id, Settings.qualityWifi.id);
    });
  });

  testWidgets('compact: a result opens its group scrolled to the setting, lit up', (tester) async {
    final store = await openStore(tester);
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/me/settings',
      routes: [
        GoRoute(
          path: '/me/settings',
          builder: (context, state) => const SettingsPage(),
          routes: [
            GoRoute(
              path: ':group',
              builder: (context, state) => SettingsGroupPage(
                group: SettingsGroup.values.byName(state.pathParameters['group']!),
                focus: state.uri.queryParameters['focus'],
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(store)],
        child: MaterialApp.router(
          theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
          routerConfig: router,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '低延迟');
    await tester.pump();
    expect(find.text('播放 › 解码与输出'), findsOneWidget, reason: 'says where it is');
    await tester.tap(find.widgetWithText(ListTile, '低延迟'));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), '/me/settings/playback?focus=player.lowLatency');
    final anchor = find.byWidgetPredicate((widget) => widget is SettingAnchor && widget.id == Settings.lowLatency.id);
    expect(tester.state<SettingAnchorState>(anchor).lit, isTrue);
    final rect = tester.getRect(anchor);
    expect(rect.top, greaterThanOrEqualTo(kToolbarHeight));
    expect(rect.bottom, lessThanOrEqualTo(852), reason: 'scrolled into view');
    await tester.pump(const Duration(seconds: 3));
    expect(tester.state<SettingAnchorState>(anchor).lit, isFalse, reason: 'the light goes out');
  });

  testWidgets('two panes: the search sits top left and a result opens beside it', (tester) async {
    final store = await openStore(tester);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(store)],
        child: MaterialApp(
          theme: PureTheme.of(Appearance.light, platform: TargetPlatform.windows),
          home: const SettingsPage(),
        ),
      ),
    );
    final box = tester.getRect(find.byType(SearchBar));
    expect(box.left, 32, reason: 'on the page margin');
    expect(box.right, lessThanOrEqualTo(280));
    await tester.enterText(find.byType(TextField), '录制读写超时');
    await tester.pump();
    expect(find.textContaining('3.x：录制读写超时'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, '读取超时（直播流多久没有数据算断线）').first);
    await tester.pumpAndSettle();
    final anchor = find.byWidgetPredicate(
      (widget) => widget is SettingAnchor && widget.id == Settings.recordReadTimeout.id,
    );
    expect(anchor, findsOneWidget, reason: 'the recording group opened on the right');
    expect(tester.state<SettingAnchorState>(anchor).lit, isTrue);
    expect(tester.getRect(anchor).bottom, lessThanOrEqualTo(900));
    await tester.pump(const Duration(seconds: 3));
  });
}
