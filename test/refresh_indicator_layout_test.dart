import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/plugins/global.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final oldHeader = EasyRefresh.defaultHeaderBuilder;
  final oldFooter = EasyRefresh.defaultFooterBuilder;
  late Map<String, Map<String, dynamic>> translations;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    translations = {
      for (final locale in ['zh', 'en'])
        locale: jsonDecode(await File('assets/translations/$locale.json').readAsString()) as Map<String, dynamic>,
    };
    initRefresh();
  });
  setUp(() => Get.testMode = true);
  tearDown(() => Get.reset());
  tearDownAll(() {
    EasyRefresh.defaultHeaderBuilder = oldHeader;
    EasyRefresh.defaultFooterBuilder = oldFooter;
  });

  for (final locale in ['zh', 'en']) {
    for (final (width, paneWidth) in [(320.0, 320.0), (900.0, 900.0), (900.0, 320.0)]) {
      for (final scale in [1.0, 2.0, 3.0]) {
        testWidgets('$locale refresh text fits window $width pane $paneWidth scale $scale', (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final userOffset = ValueNotifier(false);
          addTearDown(userOffset.dispose);
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          });
          late StateSetter changeState;
          var mode = IndicatorMode.drag;
          var result = IndicatorResult.none;
          await tester.pumpWidget(
            EasyLocalization(
              supportedLocales: [Locale(locale)],
              startLocale: Locale(locale),
              saveLocale: false,
              path: 'assets/translations',
              assetLoader: _Loader(translations[locale]!),
              child: Builder(
                builder: (context) => GetMaterialApp(
                  locale: context.locale,
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: StatefulBuilder(
                      builder: (context, setState) {
                        changeState = setState;
                        final local = appRefreshIndicators(context, maxWidth: paneWidth);
                        final header = width == paneWidth
                            ? EasyRefresh.defaultHeaderBuilder() as ClassicHeader
                            : local.header;
                        final footer = width == paneWidth
                            ? EasyRefresh.defaultFooterBuilder() as ClassicFooter
                            : local.footer;
                        expect(header.showText && header.showMessage, isTrue);
                        expect(footer.showText && footer.showMessage, isTrue);
                        expect(header.triggerOffset, greaterThanOrEqualTo(70));
                        if (scale == 1 && (locale == 'zh' || paneWidth == 900)) expect(header.triggerOffset, 70);
                        if (scale > 1) expect(header.triggerOffset, greaterThan(70));
                        Widget indicator(Indicator value, bool reverse) => SizedBox(
                          key: ValueKey(reverse ? 'footer-body' : 'header-body'),
                          height: value.triggerOffset,
                          width: double.infinity,
                          child: value.build(
                            context,
                            IndicatorState(
                              indicator: value,
                              notifier: _Notifier(),
                              userOffsetNotifier: userOffset,
                              mode: mode,
                              result: result,
                              offset: value.triggerOffset,
                              safeOffset: 0,
                              axis: Axis.vertical,
                              axisDirection: reverse ? AxisDirection.up : AxisDirection.down,
                              viewportDimension: 900,
                              actualTriggerOffset: value.triggerOffset,
                            ),
                          ),
                        );
                        return Align(
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: paneWidth,
                            child: SingleChildScrollView(
                              child: Column(children: [indicator(header, false), indicator(footer, true)]),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final state in [
            (IndicatorMode.armed, IndicatorResult.none, 'refresh_release_to_load'),
            (IndicatorMode.processed, IndicatorResult.success, 'refresh_load_success'),
            (IndicatorMode.processed, IndicatorResult.fail, 'refresh_load_failed'),
            (IndicatorMode.processed, IndicatorResult.noMore, 'refresh_no_more_data'),
          ]) {
            changeState(() {
              mode = state.$1;
              result = state.$2;
            });
            await tester.pumpAndSettle();
            expect(find.text(translations[locale]![state.$3] as String), findsNWidgets(2));
            expect(tester.takeException(), isNull);
            for (final key in ['header-body', 'footer-body']) {
              final parent = find.byKey(ValueKey(key));
              final bounds = tester.getRect(parent);
              for (final element in find.descendant(of: parent, matching: find.byType(Text)).evaluate()) {
                final rect = tester.getRect(find.byWidget(element.widget));
                expect(rect.left, greaterThanOrEqualTo(bounds.left));
                expect(rect.right, lessThanOrEqualTo(bounds.right));
                expect(rect.top, greaterThanOrEqualTo(bounds.top));
                expect(rect.bottom, lessThanOrEqualTo(bounds.bottom));
                expect(MediaQuery.textScalerOf(element).scale(14), 14 * scale);
              }
            }
          }
          final labels = tester.widgetList<Text>(find.byType(Text));
          expect(labels.where((text) => text.data?.contains(':') ?? false).length, greaterThanOrEqualTo(2));
        });
      }
    }
  }
}

class _Notifier extends Fake implements IndicatorNotifier {}

class _Loader extends AssetLoader {
  _Loader(this.data);
  final Map<String, dynamic> data;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => data;
}
