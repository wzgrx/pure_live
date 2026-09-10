import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/base/base_page_scroll_bone.dart';
import 'package:pure_live/common/base/live_directory_controller.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/common/widgets/room_card.dart';
import 'package:pure_live/core/site/weibo/weibo_site.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/popular/popular_grid_view.dart';
import 'package:pure_live/modules/search/search_controller.dart' as search;
import 'package:pure_live/modules/search/search_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/weibo_application_fixture.dart';

class _Directory extends LiveDirectoryController {
  _Directory(WeiboSite site) : super(directory: site);
  @override
  Future<bool> checkNetworkBeforeRequest() async => true;
}

class _Search extends search.SearchController {
  _Search(Site site) : super(searchSites: [site]);
  Future<void>? activeSearch;
  @override
  Future<bool> isWebView2Installed() async => true;
  @override
  Future<void> doSearch() => activeSearch = super.doSearch();
}

class _Loader extends AssetLoader {
  const _Loader();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>;
}

void _setView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _mount(WidgetTester tester, String lang, Size size, Widget home) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
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
          theme: ThemeData(platform: size.width < 680 ? TargetPlatform.android : TargetPlatform.windows),
          locale: context.locale,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: home,
        ),
      ),
    ),
  );
  // The directory is intentionally still loading. Its progress animation
  // cannot settle until the explicit adapter request below has completed.
  await tester.pump();
  await tester.pump();
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
    Get.put(SettingsService(), permanent: true);
  });
  tearDown(Get.reset);
  tearDownAll(Hive.close);

  for (final lang in ['zh', 'en']) {
    for (final size in [const Size(320, 640), const Size(960, 720)]) {
      testWidgets('$lang real popular grid keeps Weibo cards and scope at ${size.width}, 200% text', (tester) async {
        _setView(tester, size);
        final f = WeiboApplicationFixture();
        final c = _Directory(f.adapter);
        Get.put<BasePageScrollAndStateBone<LiveRoom>>(c, tag: 'weibo');
        await _mount(tester, lang, size, const Scaffold(body: PopularGridView('weibo')));
        await tester.runAsync(() => c.loadData().timeout(const Duration(seconds: 10)));
        await tester.pumpAndSettle();
        final labels = jsonDecode(File('assets/translations/$lang.json').readAsStringSync()) as Map;
        expect(find.text(labels['weibo_directory_scope'] as String), findsOneWidget);
        expect(find.byType(RoomCard), findsNWidgets(2));
        expect(find.byKey(const ValueKey('weibo:$weiboFixtureId')).hitTestable(), findsOneWidget);
        expect(find.byKey(const ValueKey('cover-audience-metric')), findsNothing);
        expect(c.list.every((r) => r.liveStatus == LiveStatus.unknown), isTrue);
        expect(f.directoryCalls, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      testWidgets('$lang actual search action exposes exact Weibo result at ${size.width}, 200% text', (tester) async {
        _setView(tester, size);
        final f = WeiboApplicationFixture();
        final c = _Search(f.site);
        Get.put<search.SearchController>(c);
        c.index.value = 1;
        await _mount(tester, lang, size, const SearchPage());
        await tester.enterText(find.byType(TextField), weiboFixtureId);
        // Start the UI action in the real async zone too: merely awaiting a
        // fake-zone Dio request from runAsync leaves its scheduled work stuck.
        await tester.runAsync(() async {
          await tester.tap(find.byIcon(Icons.search));
          expect(c.activeSearch, isNotNull);
          await c.activeSearch!.timeout(const Duration(seconds: 10));
        });
        await tester.pumpAndSettle();
        final labels = jsonDecode(File('assets/translations/$lang.json').readAsStringSync()) as Map;
        expect(find.text(c.capabilityText), findsOneWidget);
        expect(find.text(labels['continue_web_search'] as String), findsNothing);
        final card = find.byKey(const ValueKey('weibo:$weiboFixtureId'));
        for (var i = 0; i < 20 && card.hitTestable().evaluate().isEmpty; i++) {
          await tester.drag(find.byKey(const ValueKey('search-content')), const Offset(0, -140));
          await tester.pumpAndSettle();
        }
        expect(card.hitTestable(), findsOneWidget);
        expect(tester.widget<RoomCard>(card).room.roomId, weiboFixtureId);
        expect(c.results.single.userId, '101');
        expect(c.hasMore.value, isFalse);
        expect(f.detailCalls, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }
}
