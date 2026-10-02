import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_catalog.dart';
import 'package:pure_live/platform/display_mode.dart';

import '../../support.dart';

// docs/R-性能和流畅度/R02-刷新率/R02.2-刷新率策略修正/brief.md c3: a line under "界面刷新率" while the system
// holds the app at 60 Hz.

const _limited = '系统把本应用限制在 60 Hz，可以在系统设置 → 显示 → 屏幕刷新率里调高';

void main() {
  tearDown(DisplayMode.debugReset);

  Map<String, Object> info(double current) => {
    'currentRefreshRate': current,
    'maxRefreshRate': 120.0,
    'supportedRefreshRates': [60.0, 90.0, 120.0],
  };

  testWidgets('shown while limited in balanced or performance, gone once the display runs faster', (tester) async {
    DisplayMode.debugAndroid = true;
    final services = (await tester.runAsync(testServices))!;
    await tester.runAsync(loadStrings);
    final settings = services.store.settings;
    await tester.runAsync(() => settings.set(Settings.refreshRateMode, 'balanced'));
    final entry = settingsCatalog.firstWhere((entry) => entry.id == 'refresh_rate');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: MaterialApp(
          home: Scaffold(body: Builder(builder: (context) => entry.build(context, entry))),
        ),
      ),
    );
    DisplayMode.publish(DisplayModeInfo.fromMap(info(60)));
    await tester.pump();
    expect(find.text(_limited), findsNothing);

    DisplayMode.limited.value = true;
    await tester.pump();
    expect(find.text(_limited), findsOneWidget);
    expect(find.text('当前 60 Hz，最高 120 Hz'), findsOneWidget, reason: 'the row stays as it was');

    Future<void> mode(String value) async {
      await tester.runAsync(() => settings.set(Settings.refreshRateMode, value));
      // The stored value reaches the row through the store's change stream.
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    // Power saving asks for nothing high: no line.
    await mode('powerSaving');
    expect(find.text(_limited), findsNothing);
    await mode('performance');
    expect(find.text(_limited), findsOneWidget);

    DisplayMode.publish(DisplayModeInfo.fromMap(info(120)));
    await tester.pump();
    expect(DisplayMode.limited.value, isFalse);
    expect(find.text(_limited), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(services.close);
  });

  testWidgets("the dialog explains each policy (3.x's texts, not their keys)", (tester) async {
    final services = (await tester.runAsync(testServices))!;
    await tester.runAsync(loadStrings);
    final entry = settingsCatalog.firstWhere((entry) => entry.id == 'refresh_rate');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: MaterialApp(
          home: Scaffold(body: Builder(builder: (context) => entry.build(context, entry))),
        ),
      ),
    );
    await tester.tap(find.text('界面刷新率'));
    await tester.pumpAndSettle();
    expect(find.byType(DialogOptionRow), findsNWidgets(3));
    expect(find.textContaining('_desc'), findsNothing);
    expect(find.textContaining('界面由系统动态调度'), findsOneWidget);
    expect(find.textContaining('操作结束后交还系统'), findsOneWidget);
    expect(find.textContaining('前台界面跟随当前设备或显示器上限'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(services.close);
  });
}
