// U.6e: cache and data, the configuration preview (docs/A-界面设计/A11-设置界面/A11.5-数据);
// the log row of the overview's data group (U.11a Q1).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/settings/data_tools.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';
import 'settings_harness.dart';

Finder _text(String text) => find.text(text);

Finder _inRow(String id, Finder matching) => find.descendant(of: settingsRow(id), matching: matching);

SettingsRow _rowWidget(WidgetTester tester, String id) => tester.widget<SettingsRow>(
  find.descendant(of: settingsRow(id), matching: find.byType(SettingsRow), matchRoot: true).first,
);

void main() {
  setUpAll(loadStrings);

  group('cache and data (e2–e7)', () {
    testWidgets('cache and download groups; actions without chevrons, red clearing; the folder note', (tester) async {
      final h = await pumpSettings(
        tester,
        arguments: 'cache',
        overrides: [downloadDirectoryPickerProvider.overrideWithValue(() async => Directory.systemTemp.path)],
      );
      expectInOrder(tester, [
        for (final title in ['缓存', '下载']) _text(title),
      ]);
      expectInOrder(tester, [
        for (final id in ['cache_size', 'refresh_covers_now', 'clear_cache', 'download_directory', 'download_reset'])
          settingsRow(id),
      ]);
      expect(settingsRow('log'), findsNothing);
      expect(settingsRow('reset_all'), findsNothing);
      expect(_inRow('cache_size', _text('临时缩略图和表情文件；点一下重新计算')), findsOneWidget);
      expect(_inRow('cache_size', find.byIcon(AppIcons.settingsRecount)), findsOneWidget);
      for (final id in ['refresh_covers_now', 'clear_cache']) {
        expect(_inRow(id, find.byIcon(Icons.chevron_right_rounded)), findsNothing, reason: id);
      }
      expect(
        _rowWidget(tester, 'clear_cache').titleColor,
        Theme.of(tester.element(settingsRow('clear_cache'))).colorScheme.error,
      );
      expect(_inRow('download_directory', _text('默认')), findsOneWidget);
      expect(_text('下载目录用于安装包、下载的文件和字体；录制文件的位置在录制设置里。'), findsOneWidget);
      // The default folder is in use: its restore is greyed out (e6).
      expect(_rowWidget(tester, 'download_reset').enabled, isFalse);
      expect(_inRow('download_reset', _text('现在用的就是默认目录')), findsOneWidget);

      await tapSettings(tester, settingsRow('download_directory'));
      // The folder is checked for writing (real file work).
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pumpAndSettle();
      }
      expect(h.settings.get(Settings.downloadDirectoryPath), Directory.systemTemp.path);
      expect(_inRow('download_directory', _text('自定义')), findsOneWidget);
      expect(_rowWidget(tester, 'download_reset').enabled, isTrue);
      await tapSettings(tester, settingsRow('download_reset'));
      expect(h.settings.get(Settings.downloadDirectoryPath), '');
      expect(h.toasts, ['下载目录已更新', '下载目录已更新']);
    });

    testWidgets('clearing asks first and says what stays', (tester) async {
      await pumpSettings(tester, arguments: 'cache');
      await tapSettings(tester, settingsRow('clear_cache'));
      expect(_text('确认清空本地缓存？'), findsOneWidget);
      expect(find.textContaining('录制、下载、字体和 IPTV 数据会完整保留'), findsOneWidget);
      await tapSettings(tester, find.text('取消'));
      expect(_text('确认清空本地缓存？'), findsNothing);
    });

    test('sizes read like 3.x', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(12939428), '12.34 MB');
    });
  });

  group('configuration preview (e8–e12)', () {
    testWidgets('a title, the counts, the tree scrolling with the page; branches open and close', (tester) async {
      await pumpSettings(tester, height: 1200, arguments: 'configPreview');
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
      }
      expect(find.widgetWithText(AppBar, '本地配置预览'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-config-backup')), findsOneWidget);
      for (final label in ['favorites', 'history', 'tags', 'config_modules']) {
        expect(find.byKey(ValueKey('settings-config-stat-$label')), findsOneWidget);
      }
      expect(find.textContaining('这里不显示账号 Cookie 和 WebDAV 设置'), findsOneWidget);
      // One scroll: the tree is part of the page.
      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('json-tree-app')),
          matching: find.byKey(const ValueKey('settings-config-scroll')),
        ),
        findsOneWidget,
      );
      // Two levels open: a section's settings show; a tap closes the section.
      expect(find.byKey(const ValueKey('json-tree-app')), findsOneWidget);
      expect(find.byKey(const ValueKey('json-tree-app/autoRefreshTime')), findsOneWidget);
      await tapSettings(tester, find.byKey(const ValueKey('json-tree-app')));
      expect(find.byKey(const ValueKey('json-tree-app/autoRefreshTime')), findsNothing);
      // The tree has no account data.
      expect(find.byKey(const ValueKey('json-tree-cookie')), findsNothing);
    });

    testWidgets('the app bar opens backup and restore (e12)', (tester) async {
      final h = await pumpSettings(tester, arguments: 'configPreview');
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
      }
      await tapSettings(tester, find.byKey(const ValueKey('settings-config-backup')));
      expect(h.opened, [RoutePath.kBackup]);
    });

    testWidgets('the tree on its own: types and colours from the theme', (tester) async {
      final data = <String, Object?>{
        'backupVersion': 4,
        'app': {
          'name': 'x',
          'on': true,
          'list': ['a', 'b'],
        },
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(slivers: [JsonTreeSliver(data: data)]),
          ),
        ),
      );
      expect(find.text('backupVersion: 4', findRichText: true), findsOneWidget);
      expect(find.text('list: Array<String>[2]', findRichText: true), findsOneWidget);
      expect(find.byKey(const ValueKey('json-tree-app/list/0')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('json-tree-app/list')));
      await tester.pump();
      expect(find.byKey(const ValueKey('json-tree-app/list/0')), findsOneWidget);
    });
  });

  testWidgets("the overview's data group ends with the log, which opens its page (U.11a Q1)", (tester) async {
    await pumpSettings(tester, height: 2600);
    expectInOrder(tester, [
      settingsSection(SettingsSection.cache),
      settingsSection(SettingsSection.backup),
      settingsSection(SettingsSection.configPreview),
      settingsSection(SettingsSection.log),
    ]);
    // The log page lives with the backup (U.11a) and opens by its route.
    expect(SettingsSection.log.route, RoutePath.kLogs);
  });
}
