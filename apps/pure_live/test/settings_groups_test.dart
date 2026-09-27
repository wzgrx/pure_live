import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/settings/settings_page.dart';

/// Every settings group shows its entries (principles §4.4). Guards against
/// edits that silently fail to land, as happened to the recording and
/// accounts groups once.
void main() {
  const expected = {
    SettingsGroup.general: ['启动页', '播放时屏幕常亮'],
    SettingsGroup.appearance: ['主题', '纯黑'],
    SettingsGroup.playback: ['默认画质（Wi-Fi）', '硬件解码'],
    SettingsGroup.danmaku: ['显示弹幕', '字号'],
    SettingsGroup.recording: ['录制中心', '录制保存位置', '开播监控'],
    SettingsGroup.accounts: ['平台账号'],
    SettingsGroup.network: ['使用代理', '代理地址', '代理端口'],
    SettingsGroup.data: ['观看历史最多保留'],
  };

  for (final MapEntry(key: group, value: titles) in expected.entries) {
    testWidgets('${group.label} lists its settings', (tester) async {
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
            home: Scaffold(body: SettingsGroupBody(group: group)),
          ),
        ),
      );
      await tester.pump();
      for (final title in titles) {
        expect(find.text(title), findsWidgets, reason: '${group.label} should show $title');
      }
    });
  }
}
