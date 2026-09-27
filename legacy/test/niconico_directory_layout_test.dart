import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/base/base_page_view.dart';
import 'package:pure_live/common/base/live_directory_controller.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/site/niconico/niconico_api.dart';
import 'package:pure_live/core/site/niconico/niconico_site.dart';
import 'package:pure_live/get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Directory extends LiveDirectoryController {
  _Directory(NiconicoSite site) : super(directory: site);
  @override
  Future<bool> checkNetworkBeforeRequest() async => true;
}

class _Loader extends AssetLoader {
  const _Loader();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await Hive.openBox<dynamic>('app_settings', bytes: Uint8List(0));
    await HivePrefUtil.init();
  });
  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    Get.put(SettingsService());
  });
  tearDown(Get.reset);
  tearDownAll(Hive.close);
  for (final lang in ['zh', 'en']) {
    for (final size in [const Size(320, 640), const Size(960, 720)]) {
      testWidgets('$lang scope and empty state remain visible at ${size.width} with 200% text', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var requests = 0;
        final c = _Directory(
          NiconicoSite(
            api: NiconicoApi(
              request: (_, _) async {
                requests++;
                return (status: 200, body: '{"meta":{"statusCode":200,"errorCode":"OK","totalCount":0},"data":[]}');
              },
            ),
          ),
        );
        addTearDown(c.onClose);
        // The transport owns real stream-subscription cleanup; do not await it
        // under the widget fake clock before pumping the first frame.
        await tester.runAsync(() => c.loadData().timeout(const Duration(seconds: 10)));
        final labels = jsonDecode(File('assets/translations/$lang.json').readAsStringSync()) as Map;
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: [Locale(lang)],
            startLocale: Locale(lang),
            fallbackLocale: Locale(lang),
            saveLocale: false,
            path: 'assets/translations',
            assetLoader: const _Loader(),
            child: Builder(
              builder: (context) => GetMaterialApp(
                locale: context.locale,
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
                home: Scaffold(
                  body: BasePageView<LiveDirectoryController, LiveRoom>(
                    controller: c,
                    showScrollToTopBtn: false,
                    emptyBuilder: (_) => const Text('EMPTY'),
                    contentBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(labels['niconico_directory_scope'] as String), findsOneWidget);
        expect(find.text('EMPTY'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(requests, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }
}
