import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_catalog.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/platform/display_mode.dart';

import '../../support.dart';

// docs/T14/T14b/T14b.1 c2, c6: "播放时匹配视频帧率" under the refresh rate.

void main() {
  tearDown(DisplayMode.debugReset);

  testWidgets('c2: right under the refresh rate, Android only, on by default; c6: greyed with one rate', (
    tester,
  ) async {
    final ids = [for (final entry in settingsCatalog) entry.id];
    expect(ids.indexOf('match_video_frame_rate'), ids.indexOf('refresh_rate') + 1);
    final entry = settingsCatalog.firstWhere((entry) => entry.id == 'match_video_frame_rate');
    expect(entry.when(const SettingsEnv(platform: TargetPlatform.android)), isTrue);
    expect(entry.when(const SettingsEnv(platform: TargetPlatform.windows)), isFalse);

    final services = (await tester.runAsync(testServices))!;
    await tester.runAsync(loadStrings);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: MaterialApp(
          home: Scaffold(body: Builder(builder: (context) => entry.build(context, entry))),
        ),
      ),
    );
    expect(services.store.settings.get(Settings.matchVideoFrameRate), isTrue);
    expect(find.text('播放时匹配视频帧率'), findsOneWidget);
    expect(tester.widget<SettingsSwitchRow>(find.byType(SettingsSwitchRow)).enabled, isTrue);

    DisplayMode.publish(
      DisplayModeInfo.fromMap(const {
        'currentRefreshRate': 60.0,
        'maxRefreshRate': 60.0,
        'supportedRefreshRates': [60.0],
      }),
    );
    await tester.pump();
    final row = tester.widget<SettingsSwitchRow>(find.byType(SettingsSwitchRow));
    expect(row.enabled, isFalse);
    expect(row.disabledReason, '这台设备只有 60 Hz，用不上');

    DisplayMode.publish(
      DisplayModeInfo.fromMap(const {
        'currentRefreshRate': 60.0,
        'maxRefreshRate': 120.0,
        'supportedRefreshRates': [60.0, 120.0],
      }),
    );
    await tester.pump();
    await tester.tap(find.byType(Switch));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(services.store.settings.get(Settings.matchVideoFrameRate), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(services.close);
  });
}
