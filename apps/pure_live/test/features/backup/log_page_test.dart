// The log page's level row (docs/A-界面设计/A07-直播间界面/A07.23-横屏右上角菜单升级): a choice row
// with the app's option dialog, as every other choice in the settings, no
// longer Material's drop-down and its menu.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/app_log.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/backup/log_page.dart';
import 'package:pure_live/i18n/i18n.dart';

import '../../support.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  setUpAll(loadStrings);

  for (final (name, theme) in [
    ('light', const LiveTheme().light),
    ('dark', const LiveTheme().dark),
    ('pure black', const LiveTheme(pureBlack: true).dark),
  ]) {
    testWidgets('the level ($name): the value at the end, the option dialog with a tick, a pick applies', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(393, 852)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final services = (await tester.runAsync(testServices))!;
      addTearDown(() => tester.runAsync(services.close));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appServicesProvider.overrideWithValue(services)],
          child: MaterialApp(
            theme: theme,
            home: LogPage(log: AppLog()),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(DropdownButton<LogLevel>), findsNothing);
      final row = _key('log-level');
      expect(row, findsOneWidget);
      final current = LogLevel.parse(services.store.settings.get(Settings.logLevel));
      expect(find.descendant(of: row, matching: find.text(_label(current))), findsOneWidget);

      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget);
      for (final level in LogLevel.values) {
        expect(_key('log-level-${level.name}'), findsOneWidget, reason: level.name);
      }
      expect(
        find.descendant(of: _key('log-level-${current.name}'), matching: find.byIcon(AppIcons.selected)),
        findsOneWidget,
        reason: 'the current level: primary with a tick',
      );
      final other = LogLevel.values.firstWhere((level) => level != current);
      await tester.tap(_key('log-level-${other.name}'));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
      expect(services.store.settings.get(Settings.logLevel), other.name);
      expect(find.descendant(of: row, matching: find.text(_label(other))), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

String _label(LogLevel level) => i18n('settings_log_level_${level.name}');
