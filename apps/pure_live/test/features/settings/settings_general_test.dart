// U.6d: general, platforms, refresh and network (docs/ui/compare/U.6d).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/settings/settings_dialogs.dart';
import 'package:pure_live/features/settings/settings_editors.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';
import 'settings_harness.dart';

Finder _text(String text) => find.text(text);

Finder _inRow(String id, Finder matching) => find.descendant(of: settingsRow(id), matching: matching);

SettingsRow _rowWidget(WidgetTester tester, String id) =>
    tester.widget<SettingsRow>(find.descendant(of: settingsRow(id), matching: find.byType(SettingsRow)).first);

void main() {
  setUpAll(loadStrings);

  group('general (d2–d6)', () {
    testWidgets('phones: display, start-up, updates, exit timer; the policy on the right', (tester) async {
      final h = await pumpSettings(tester, arguments: 'general');
      expectInOrder(tester, [
        for (final title in ['显示', '启动', '更新', '定时退出']) _text(title),
      ]);
      expect(_text('窗口'), findsNothing);
      expectInOrder(tester, [
        for (final id in ['refresh_rate', 'splash', 'auto_update', 'github_updates', 'auto_exit', 'auto_exit_minutes'])
          settingsRow(id),
      ]);
      expect(settingsRow('windows_display'), findsNothing);
      expect(_inRow('refresh_rate', _text('省电')), findsOneWidget);
      expect(_inRow('refresh_rate', _text('当前 60 Hz，最高 60 Hz')), findsOneWidget);
      // The dialog: each policy with its energy use and explanation.
      await tapSettings(tester, settingsRow('refresh_rate'));
      expect(_text('省电（默认） · 低耗电'), findsOneWidget);
      expect(find.byType(SettingsChoiceRow), findsNWidgets(3));
      await tapSettings(tester, find.byKey(const ValueKey('settings-choice-balanced')));
      expect(h.settings.get(Settings.refreshRateMode), 'balanced');
      expect(_inRow('refresh_rate', _text('均衡')), findsOneWidget);
    });

    testWidgets('the exit timer: the time left on the length row; a quick pick applies', (tester) async {
      final h = await pumpSettings(tester, arguments: 'general');
      expect(_inRow('auto_exit_minutes', _text('120 分钟')), findsOneWidget);
      await tapSettings(tester, settingsRow('auto_exit'));
      expect(h.settings.get(Settings.enableAutoShutDownTime), isTrue);
      expect(_inRow('auto_exit_minutes', find.textContaining('剩余时间')), findsOneWidget);
      await tapSettings(tester, settingsRow('auto_exit_minutes'));
      expect(_text('自定义时长'), findsOneWidget);
      expect(_text('输入 1～525600 分钟'), findsOneWidget);
      await tapSettings(tester, find.byKey(const ValueKey('settings-number-30')));
      expect(h.settings.get(Settings.autoShutDownTime), 30);
      await tapSettings(tester, settingsRow('auto_exit'));
      expect(AutoExitTimer.instance.remaining.value, isNull);
    });

    testWidgets('Windows: start-up, window size, closing the window, new windows', (tester) async {
      await withPlatform(TargetPlatform.windows, () async {
        final h = await pumpSettings(tester, width: 1280, height: 1400, arguments: 'general');
        expectInOrder(tester, [
          for (final title in ['显示', '启动', '更新', '窗口', '定时退出']) _text(title).last,
        ]);
        expectInOrder(tester, [
          for (final id in ['refresh_rate', 'startup', 'window_size', 'splash', 'close_window', 'new_window'])
            settingsRow(id),
        ]);
        expect(settingsRow('dont_ask_exit'), findsNothing);
        expect(_inRow('close_window', _text('每次询问')), findsOneWidget);
        expect(_inRow('new_window', _text('首页菜单和直播间菜单里显示“在新窗口打开”')), findsOneWidget);

        // Closing the window: three options in 3.x's two keys (d5).
        await tapSettings(tester, settingsRow('close_window'));
        expect(_text('缩到托盘，直播照常'), findsOneWidget);
        await tapSettings(tester, find.byKey(const ValueKey('settings-choice-minimize')));
        expect(h.settings.get(Settings.dontAskExit), isTrue);
        expect(h.settings.get(Settings.exitChoose), 'minimize');
        expect(_inRow('close_window', _text('最小化到托盘')), findsOneWidget);
        await tapSettings(tester, settingsRow('close_window'));
        await tapSettings(tester, find.byKey(const ValueKey('settings-choice-ask')));
        expect(h.settings.get(Settings.dontAskExit), isFalse);

        // Window size: the current preset highlighted, a checked size, "应用".
        expect(_inRow('window_size', _text('1280 × 720')), findsOneWidget);
        await tapSettings(tester, settingsRow('window_size'));
        expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('settings-window-size-1280'))).selected, isTrue);
        expect(_text('1280 × 720 (720P · 默认)'), findsOneWidget);
        expect(find.textContaining('点“应用”后窗口立即变成这个大小'), findsOneWidget);
        await tester.enterText(find.byKey(const ValueKey('settings-window-height')), '100');
        await tapSettings(tester, find.byKey(const ValueKey('settings-window-size-apply')));
        expect(_text('请输入支持范围内的窗口尺寸'), findsOneWidget);
        await tapSettings(tester, find.byKey(const ValueKey('settings-window-size-1600')));
        await tapSettings(tester, find.byKey(const ValueKey('settings-window-size-apply')));
        expect(h.settings.get(Settings.windowWidth), 1600);
        expect(h.settings.get(Settings.windowHeight), 900);
        expect(h.toasts, ['设置已应用']);
      });
    });

    test('the refresh rate shows on iPhones with ProMotion only (U.17a)', () {
      expect(const SettingsEnv(platform: TargetPlatform.iOS).hasRefreshRate, isFalse);
      expect(const SettingsEnv(platform: TargetPlatform.iOS, fastDisplay: true).hasRefreshRate, isTrue);
      expect(const SettingsEnv(platform: TargetPlatform.linux).hasRefreshRate, isFalse);
    });
  });

  group('platforms (d8, d9)', () {
    testWidgets('two groups; the preferred platform with its logo; the dialog filters', (tester) async {
      final h = await pumpSettings(tester, arguments: 'platforms');
      expectInOrder(tester, [
        for (final title in ['平台', '账号和标签']) _text(title),
      ]);
      expectInOrder(tester, [
        for (final id in ['platform_list', 'prefer_platform', 'accounts', 'tags']) settingsRow(id),
      ]);
      expect(_inRow('prefer_platform', find.byType(PlatformLogo)), findsOneWidget);
      expect(_inRow('prefer_platform', _text('哔哩哔哩')), findsOneWidget);
      await tapSettings(tester, settingsRow('prefer_platform'));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('settings-platform-bilibili')),
          matching: find.byIcon(AppIcons.selected),
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const ValueKey('settings-platform-filter')), 'zzzz');
      await tester.pump();
      expect(_text('没有匹配的平台'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('settings-platform-filter')), '斗鱼');
      await tester.pump();
      await tapSettings(tester, find.byKey(const ValueKey('settings-platform-douyu')));
      expect(h.settings.get(Settings.preferPlatform), 'douyu');

      await tapSettings(tester, settingsRow('tags'));
      expect(h.opened, [RoutePath.kSettingsTags]);
    });
  });

  group('refresh (d10–d12)', () {
    testWidgets('intervals follow their switch; follows wording; parallel tasks counted in the row', (tester) async {
      final h = await pumpSettings(tester, arguments: 'refresh');
      expectInOrder(tester, [
        for (final title in ['关注列表', '直播缩略图']) _text(title),
      ]);
      expectInOrder(tester, [
        for (final id in ['auto_refresh', 'refresh_interval', 'refresh_on_resume', 'refresh_concurrency'])
          settingsRow(id),
        for (final id in ['refresh_covers', 'cover_interval']) settingsRow(id),
      ]);
      expect(_inRow('refresh_on_resume', _text('返回应用时刷新关注')), findsOneWidget);
      expect(_rowWidget(tester, 'refresh_interval').enabled, isFalse);
      expect(_inRow('refresh_interval', _text('打开“开启关注自动刷新”后生效')), findsOneWidget);
      await tapSettings(tester, settingsRow('auto_refresh'));
      expect(_rowWidget(tester, 'refresh_interval').enabled, isTrue);
      await tapSettings(tester, settingsRow('refresh_interval'));
      expect(find.byType(SettingsChoiceRow), findsNWidgets(12));
      await tapSettings(tester, find.byKey(const ValueKey('settings-choice-90')));
      expect(h.settings.get(Settings.autoRefreshInterval), 90);
      expect(_inRow('refresh_interval', _text('1.5 小时')), findsOneWidget);

      final before = h.settings.get(Settings.maxConcurrentRefresh);
      await tapSettings(tester, find.byKey(const ValueKey('settings-entry-refresh_concurrency-increase')));
      expect(h.settings.get(Settings.maxConcurrentRefresh), before + 1);
      await tapSettings(tester, find.byKey(const ValueKey('settings-entry-refresh_concurrency-decrease')));
      await tapSettings(tester, find.byKey(const ValueKey('settings-entry-refresh_concurrency-decrease')));
      expect(h.settings.get(Settings.maxConcurrentRefresh), before - 1);
    });

    testWidgets('a held + repeats', (tester) async {
      final h = await pumpSettings(tester, arguments: 'refresh', seed: (s) => s.set(Settings.maxConcurrentRefresh, 1));
      final plus = find.byKey(const ValueKey('settings-entry-refresh_concurrency-increase'));
      await tester.ensureVisible(plus);
      final gesture = await tester.startGesture(tester.getCenter(plus));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await settleSettings(tester);
      expect(h.settings.get(Settings.maxConcurrentRefresh), greaterThan(2));
    });
  });

  group('network (d13, d14)', () {
    testWidgets('fields stay while off (greyed out); typing is stored; a bad port is red', (tester) async {
      final h = await pumpSettings(tester, arguments: 'network');
      expectInOrder(tester, [settingsRow('app_proxy'), settingsRow('player_proxy')]);
      final host = find.byKey(const ValueKey('settings-proxy-player-host'));
      final port = find.byKey(const ValueKey('settings-proxy-player-port'));
      expect(tester.widget<TextField>(host).enabled, isFalse);
      // Narrow: the address above the port.
      expect(tester.getTopLeft(port).dy, greaterThan(tester.getTopLeft(host).dy));
      await tapSettings(tester, find.byKey(const ValueKey('settings-proxy-player-switch')));
      expect(h.settings.get(Settings.enableProxy), isTrue);
      expect(tester.widget<TextField>(host).enabled, isTrue);
      await tester.enterText(host, '10.0.0.2');
      await tester.enterText(port, '70000');
      await tester.pump();
      expect(_text('请输入 1 到 65535 之间的端口'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await settleSettings(tester);
      expect(h.settings.get(Settings.proxyHost), '10.0.0.2');
      expect(h.settings.get(Settings.proxyPort), 7897);
      await tester.enterText(port, '1080');
      await tester.pump(const Duration(seconds: 1));
      await settleSettings(tester);
      expect(h.settings.get(Settings.proxyPort), 1080);
    });

    testWidgets('from 420 wide the address and the port sit side by side', (tester) async {
      await pumpSettings(tester, width: 760, arguments: 'network');
      final host = find.byKey(const ValueKey('settings-proxy-app-host'));
      final port = find.byKey(const ValueKey('settings-proxy-app-port'));
      expect(tester.getTopLeft(port).dy, tester.getTopLeft(host).dy);
      expect(tester.getSize(host).width, greaterThan(tester.getSize(port).width));
    });
  });
}
