import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';

/// Settings sliders (design review M): no tick marks, the value in a
/// fixed-width slot on the track's line.
void main() {
  Widget themed(Widget child) => MaterialApp(
    theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
    home: Scaffold(body: child),
  );

  testWidgets('sliders: every track is as long, whatever the value says; the value sits on the track line', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [storeProvider.overrideWithValue(store)],
        child: themed(
          Column(
            children: [
              SliderSettingTile(
                setting: Settings.defaultMobileVolume,
                title: '默认音量',
                min: 0,
                max: 1,
                divisions: 20,
                format: (value) => '4',
              ),
              SliderSettingTile(
                setting: Settings.recordMaxRetries,
                title: '重试次数',
                min: 1,
                max: 20,
                divisions: 19,
                format: (value) => '1000 entries',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final sliders = find.byType(Slider);
    expect(sliders, findsNWidgets(2));
    expect(tester.getSize(sliders.at(0)).width, tester.getSize(sliders.at(1)).width);
    final values = find.byKey(const ValueKey('setting-slider-value'));
    expect(tester.getSize(values.at(0)).width, SettingSlider.valueWidth);
    expect(tester.getCenter(values.at(0)).dy, moreOrLessEquals(tester.getCenter(sliders.at(0)).dy, epsilon: 1));
    expect(find.byType(ListTile).evaluate().map((e) => (e.widget as ListTile).trailing), everyElement(isNull));
    final theme = Theme.of(tester.element(sliders.first));
    expect(theme.sliderTheme.tickMarkShape, SliderTickMarkShape.noTickMark);
  });
}
