import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/app/app.dart';
import 'package:pure_live_app/app/locale.dart';
import 'package:pure_live_app/core/recording.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/features/settings/settings_page.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

import 'fakes.dart';
import 'flutter_test_config.dart';

/// A refresh that finishes at once (see app_test.dart).
class _NoRefresh extends FollowRefreshNotifier {
  @override
  Future<FollowRefreshResult?> build() async => null;
}

void main() {
  setUpAll(() => applyAppLocale(AppLocale.zhHans));
  tearDown(() => applyAppLocale(AppLocale.zhHans));

  group('F-APP-06: follow-system matching', () {
    Locale tag(String value) {
      final parts = value.split('-');
      return switch (parts.length) {
        1 => Locale(parts[0]),
        2 when parts[1].length == 4 => Locale.fromSubtags(languageCode: parts[0], scriptCode: parts[1]),
        2 => Locale(parts[0], parts[1]),
        _ => Locale.fromSubtags(languageCode: parts[0], scriptCode: parts[1], countryCode: parts[2]),
      };
    }

    test('Traditional for zh-TW, zh-HK, zh-MO and the Hant script; Simplified for other Chinese', () {
      for (final value in ['zh-TW', 'zh-HK', 'zh-MO', 'zh-Hant', 'zh-Hant-CN']) {
        expect(localeForSystem([tag(value)]), AppLocale.zhHant, reason: value);
      }
      for (final value in ['zh', 'zh-CN', 'zh-SG', 'zh-Hans', 'zh-Hans-TW', 'zh-Hans-HK']) {
        expect(localeForSystem([tag(value)]), AppLocale.zhHans, reason: value);
      }
    });

    test('English for English and for languages the app does not have', () {
      expect(localeForSystem([tag('en-US')]), AppLocale.en);
      expect(localeForSystem([tag('en-GB')]), AppLocale.en);
      expect(localeForSystem([tag('ja-JP')]), AppLocale.en);
      expect(localeForSystem([tag('ko')]), AppLocale.en);
      expect(localeForSystem(const []), AppLocale.en);
    });

    test('the first Chinese or English language in the preference list decides', () {
      expect(localeForSystem([tag('ja-JP'), tag('zh-TW'), tag('en-US')]), AppLocale.zhHant);
      expect(localeForSystem([tag('fr-FR'), tag('en-US'), tag('zh-CN')]), AppLocale.en);
    });

    test('an explicit choice wins over the system; anything else follows it', () {
      final system = [tag('zh-TW')];
      expect(localeForSetting('zh-Hans', system), AppLocale.zhHans);
      expect(localeForSetting('en', system), AppLocale.en);
      expect(localeForSetting('zh-Hant', [tag('en')]), AppLocale.zhHant);
      expect(localeForSetting('system', system), AppLocale.zhHant);
      expect(localeForSetting('fr', system), AppLocale.zhHant);
    });

    test('Material gets Taiwan conventions for Traditional Chinese', () {
      expect(
        flutterLocaleOf(AppLocale.zhHant),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
      );
      expect(flutterLocaleOf(AppLocale.zhHans), const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'));
      expect(flutterLocaleOf(AppLocale.en), const Locale('en'));
      expect(supportedFlutterLocales, hasLength(3));
    });
  });

  group('F-APP-06: counts and times in the interface language (principles §2.3)', () {
    test('Chinese counts use 万 / 亿 (萬 / 億), English K / M', () {
      final hans = liveUiTextOf(AppLocale.zhHans.translations);
      final hant = liveUiTextOf(AppLocale.zhHant.translations);
      final en = liveUiTextOf(AppLocale.en.translations);
      expect(formatCount(12000, text: hans), '1.2万');
      expect(formatCount(340000000, text: hans), '3.4亿');
      expect(formatCount(12000, text: hant), '1.2萬');
      expect(formatCount(340000000, text: hant), '3.4億');
      expect(formatCount(12000, text: en), '12K');
      expect(formatCount(3400000, text: en), '3.4M');
      expect(formatCount(950, text: en), '950');
      expect(formatCount(9876, text: hans), '9876');
    });

    test('relative times and badges', () {
      final now = DateTime(2026, 9, 28, 12);
      final en = liveUiTextOf(AppLocale.en.translations);
      expect(formatAgo(now.subtract(const Duration(minutes: 1)), now, text: en), '1 minute ago');
      expect(formatAgo(now.subtract(const Duration(hours: 3)), now, text: en), '3 hours ago');
      expect(formatAgo(now.subtract(const Duration(days: 2)), now, text: en), '2 days ago');
      expect(en.liveFor('01:24'), 'LIVE 01:24');
      final hant = liveUiTextOf(AppLocale.zhHant.translations);
      expect(formatAgo(now.subtract(const Duration(hours: 3)), now, text: hant), '3 小時前');
      expect(hant.recording, '錄製中');
    });

    test('applying a language switches t and live_ui together', () {
      expect(applyAppLocale(AppLocale.en), isTrue);
      expect(t.app.tabs.follows, 'Following');
      expect(formatCount(12000), '12K');
      expect(applyAppLocale(AppLocale.en), isFalse);
      applyAppLocale(AppLocale.zhHant);
      expect(t.app.tabs.follows, '追蹤');
      expect(formatCount(12000), '1.2萬');
      applyAppLocale(AppLocale.zhHans);
      expect(t.app.tabs.follows, '关注');
      expect(formatCount(12000), '1.2万');
    });

    test("IPTV's ungrouped channels read in the interface language; platform areas stay as given", () {
      const ungrouped = Area(id: 'p1/', name: '未分组', categoryId: 'p1');
      const named = Area(id: 'p1/未分组', name: '未分组', categoryId: 'p1');
      applyAppLocale(AppLocale.en);
      expect(areaName(ungrouped), 'Ungrouped');
      expect(areaName(named), '未分组', reason: 'a group the playlist itself calls so');
      expect(areaName(const Area(id: '1', name: '英雄联盟', categoryId: 'game')), '英雄联盟');
      applyAppLocale(AppLocale.zhHant);
      expect(areaName(ungrouped), '未分組');
      applyAppLocale(AppLocale.zhHans);
      expect(areaName(ungrouped), '未分组');
    });
  });

  group('F-APP-06: the app follows the setting', () {
    Future<LiveStore> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => tester.platformDispatcher.localesTestValue = testSystemLocales);
      final store = (await tester.runAsync(LiveStore.inMemory))!;
      addTearDown(() => tester.runAsync(store.close));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sitesProvider.overrideWithValue({
              for (final id in platformOrder)
                id: PlatformSite(
                  FakeSite(
                    id,
                    pages: [
                      Page([FakeSite(id).card('$id-1')]),
                    ],
                  ),
                ),
            }),
            storeProvider.overrideWithValue(store),
            recordManagerProvider.overrideWithValue(fakeRecordManager()),
            followsProvider.overrideWith((ref) => Stream.value(const [])),
            followRefreshProvider.overrideWith(_NoRefresh.new),
          ],
          child: const PureLiveApp(),
        ),
      );
      await tester.pumpAndSettle();
      return store;
    }

    Future<void> choose(WidgetTester tester, LiveStore store, String value) async {
      await tester.runAsync(() => store.settings.set(Settings.locale, value));
      await tester.pumpAndSettle();
    }

    Locale materialLocale(WidgetTester tester) => Localizations.localeOf(tester.element(find.byType(NavigationBar)));

    testWidgets('changing the language rewrites the open page, keeps it, and sets Material and text styles', (
      tester,
    ) async {
      final store = await pumpApp(tester);
      expect(find.text('还没有关注的主播'), findsOneWidget);
      expect(find.text('关注'), findsWidgets);
      expect(materialLocale(tester), flutterLocaleOf(AppLocale.zhHans));

      await choose(tester, store, 'en');
      expect(find.text('You are not following anyone yet'), findsOneWidget);
      expect(find.text('Go to Discover'), findsOneWidget);
      expect(find.text('Discover'), findsOneWidget);
      expect(find.text('还没有关注的主播'), findsNothing);
      expect(materialLocale(tester), const Locale('en'));
      final context = tester.element(find.byType(NavigationBar));
      expect(Theme.of(context).textTheme.bodyMedium!.locale, const Locale('en'));
      expect(MaterialLocalizations.of(context).backButtonTooltip, 'Back');

      await choose(tester, store, 'zh-Hant');
      expect(find.text('還沒有追蹤的主播'), findsOneWidget);
      expect(find.text('探索'), findsOneWidget);
      expect(materialLocale(tester), flutterLocaleOf(AppLocale.zhHant));
      expect(
        PureTheme.isTraditionalChinese(
          Theme.of(tester.element(find.byType(NavigationBar))).textTheme.bodyMedium!.locale,
        ),
        isTrue,
      );

      // Discover in every language: the page stays open across the switches
      // and counts follow the language (FakeSite rooms have 35512 viewers).
      await tester.tap(find.text('探索'));
      await tester.pumpAndSettle();
      expect(find.text('推薦'), findsWidgets);
      expect(find.textContaining('3.6萬'), findsWidgets);
      await choose(tester, store, 'en');
      expect(find.text('Recommended'), findsWidgets);
      expect(find.textContaining('35.5K'), findsWidgets);
      await choose(tester, store, 'zh-Hans');
      expect(find.text('推荐'), findsWidgets);
      expect(find.textContaining('3.6万'), findsWidgets);
      expect(store.settings.get(Settings.locale), 'zh-Hans');
    });

    testWidgets('the general settings in English', (tester) async {
      final store = (await tester.runAsync(LiveStore.inMemory))!;
      addTearDown(() => tester.runAsync(store.close));
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      applyAppLocale(AppLocale.en);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storeProvider.overrideWithValue(store)],
          child: MaterialApp(
            theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
            home: const Scaffold(body: SettingsGroupBody(group: SettingsGroup.general)),
          ),
        ),
      );
      await tester.pump();
      for (final text in [
        'Language',
        'Follow system',
        'Start page',
        'Keep the screen on while playing',
        'TV mode',
        'Refresh interval',
        '30 minutes',
        'Live alerts',
      ]) {
        expect(find.text(text), findsWidgets, reason: text);
      }
      expect(SettingsGroup.playback.label, 'Playback');
    });

    testWidgets('follow system: the system language decides and a change applies at once', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('zh', 'TW')];
      final store = await pumpApp(tester);
      expect(store.settings.get(Settings.locale), 'system');
      expect(find.text('還沒有追蹤的主播'), findsOneWidget);

      tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
      await tester.pumpAndSettle();
      expect(find.text('You are not following anyone yet'), findsOneWidget);

      // A chosen language no longer follows the system.
      await choose(tester, store, 'zh-Hans');
      tester.platformDispatcher.localesTestValue = const [Locale('zh', 'HK')];
      await tester.pumpAndSettle();
      expect(find.text('还没有关注的主播'), findsOneWidget);
    });

    testWidgets('设置 › 通用 › 语言 offers follow-system and the three languages, each in its own name', (tester) async {
      final store = (await tester.runAsync(LiveStore.inMemory))!;
      addTearDown(() => tester.runAsync(store.close));
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storeProvider.overrideWithValue(store)],
          child: MaterialApp(
            theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
            home: const Scaffold(body: SettingsGroupBody(group: SettingsGroup.general)),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('语言'), findsOneWidget);
      expect(find.text('跟随系统'), findsOneWidget);
      await tester.tap(find.text('语言'));
      await tester.pumpAndSettle();
      for (final name in ['简体中文', '繁體中文', 'English']) {
        expect(find.text(name), findsOneWidget);
      }
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(store.settings.get(Settings.locale), 'en');
    });
  });
}
