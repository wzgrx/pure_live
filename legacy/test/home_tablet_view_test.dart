import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/app_settings_controller.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings/theme_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/home/tablet_view.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _Settings settings;
  late Map<String, dynamic> translations;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('home-tablet-view-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Hive.init(directory.path);
    await HivePrefUtil.init();
    translations = jsonDecode(await File('assets/translations/zh.json').readAsString()) as Map<String, dynamic>;
  });
  setUp(() {
    Get.testMode = true;
    settings = _Settings();
    Get.put<SettingsService>(settings);
    Get.put(ThemeSettingsController());
  });
  tearDown(() {
    Get.deleteAll(force: true);
    Get.reset();
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> open(
    WidgetTester tester,
    Size size, {
    double scale = 1,
    List<String> menus = const ['favorites', 'popular', 'areas'],
    int index = 0,
    bool showRecord = true,
    ValueChanged<int>? onSelected,
    Widget body = const Center(child: Text('page-body')),
    ScrollController? primaryController,
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final home = HomeTabletView(
      body: body,
      index: index,
      activeMenuIds: menus,
      showRecord: showRecord,
      onDestinationSelected: onSelected ?? (_) {},
    );
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('zh')],
        path: 'assets/translations',
        assetLoader: _MemoryAssetLoader(translations),
        child: Builder(
          builder: (context) => GetMaterialApp(
            theme: ThemeData(platform: platform),
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            getPages: [
              GetPage(
                name: '/',
                page: () => primaryController == null
                    ? home
                    : PrimaryScrollController(controller: primaryController, child: home),
              ),
              for (final route in [RoutePath.kToolbox, RoutePath.kSearch, RoutePath.kRecordPage, RoutePath.kMultiview])
                GetPage(
                  name: route,
                  page: () => Scaffold(body: Text('route:$route')),
                ),
            ],
            initialRoute: '/',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeTabletView), findsOneWidget);
  }

  Future<void> finish(WidgetTester tester) async {
    final error = tester.takeException();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(error, isNull);
  }

  final railScroll = find.descendant(of: find.byType(NavigationRail), matching: find.byType(Scrollable));

  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(target, 120, scrollable: railScroll);
    await tester.pumpAndSettle();
    expect(target.hitTestable(), findsOneWidget);
  }

  for (final size in [const Size(869, 400), const Size(900, 260), const Size(1200, 1000)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('all home rail content fits or scrolls at $size scale $scale', (tester) async {
        final selected = <int>[];
        await open(tester, size, scale: scale, onSelected: selected.add);
        await reveal(tester, find.text('分区'));
        await tester.tap(find.text('分区'));
        expect(selected, [2]);
        await tester.scrollUntilVisible(find.byTooltip('菜单'), -120, scrollable: railScroll);
        await tester.tap(find.byTooltip('菜单'));
        await tester.pumpAndSettle();
        expect(find.text('设置').hitTestable(), findsOneWidget);
        await finish(tester);
      });
    }
  }

  testWidgets('reordered and unknown IDs retain the real destination mapping', (tester) async {
    final selected = <int>[];
    await open(
      tester,
      const Size(900, 260),
      menus: ['areas', 'unknown', 'favorites', 'popular'],
      index: 2,
      onSelected: selected.add,
    );
    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex, 0);
    for (final label in ['分区', '关注', '热门']) {
      await reveal(tester, find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    expect(selected, [2, 0, 1]);
    await finish(tester);
  });

  testWidgets('a single destination and hidden current selection remain valid', (tester) async {
    final selected = <int>[];
    await open(tester, const Size(900, 260), menus: ['areas'], onSelected: selected.add);
    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex, isNull);
    await reveal(tester, find.text('分区'));
    await tester.tap(find.text('分区'));
    expect(selected, [2]);
    await finish(tester);
  });

  testWidgets('empty destinations preserve the menu and empty state', (tester) async {
    await open(tester, const Size(900, 400), menus: ['unknown'], index: -1, showRecord: false);
    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex, isNull);
    expect(find.text(translations['no_menu_title'] as String), findsOneWidget);
    expect(find.text('page-body'), findsNothing);
    await tester.tap(find.byTooltip('菜单'));
    await tester.pumpAndSettle();
    expect(find.text('设置').hitTestable(), findsOneWidget);
    await finish(tester);
  });

  testWidgets('optional action visibility updates without overflowing', (tester) async {
    await open(tester, const Size(900, 260), showRecord: false);
    expect(find.byTooltip(translations['multiview_title'] as String), findsOneWidget);
    expect(find.byTooltip('录制中心'), findsNothing);
    settings.app.enableMultiView.value = false;
    await tester.pumpAndSettle();
    expect(find.byTooltip(translations['multiview_title'] as String), findsNothing);
    await reveal(tester, find.text('分区'));
    settings.app.enableMultiView.value = true;
    await tester.pumpAndSettle();
    expect(find.byTooltip(translations['multiview_title'] as String), findsOneWidget);
    await finish(tester);
  });

  for (final (label, route) in [
    ('链接解析', RoutePath.kToolbox),
    ('搜索直播', RoutePath.kSearch),
    ('录制中心', RoutePath.kRecordPage),
    ('多画面', RoutePath.kMultiview),
  ]) {
    testWidgets('$label action remains reachable and routes after scrolling', (tester) async {
      await open(tester, const Size(900, 260));
      await reveal(tester, find.byTooltip(label));
      await tester.tap(find.byTooltip(label));
      await tester.pumpAndSettle();
      expect(find.text('route:$route'), findsOneWidget);
      await finish(tester);
    });
  }

  testWidgets('rail and body have independent scroll positions on Android', (tester) async {
    final primary = ScrollController();
    addTearDown(primary.dispose);
    await open(
      tester,
      const Size(900, 260),
      primaryController: primary,
      body: ListView.builder(primary: true, itemCount: 100, itemExtent: 48, itemBuilder: (_, i) => Text('body-$i')),
    );
    expect(primary.positions, hasLength(1));
    await reveal(tester, find.text('分区'));
    expect(primary.offset, 0);
    final railPosition = tester.state<ScrollableState>(railScroll).position;
    final offset = railPosition.pixels;
    expect(offset, greaterThan(0));
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(primary.offset, greaterThan(0));
    expect(railPosition.pixels, offset);
    await finish(tester);
  });

  testWidgets('Windows mouse wheel can reach the final destination', (tester) async {
    await open(tester, const Size(900, 260), platform: TargetPlatform.windows);
    final position = tester.state<ScrollableState>(railScroll).position;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(NavigationRail)),
        scrollDelta: const Offset(0, 1000),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    expect(find.text('分区').hitTestable(), findsOneWidget);
    await finish(tester);
  });

  testWidgets('resizing from a scrolled short window to tall keeps entries accessible', (tester) async {
    await open(tester, const Size(900, 260));
    await reveal(tester, find.text('分区'));
    tester.view.physicalSize = const Size(900, 1000);
    await tester.pumpAndSettle();
    expect(find.byTooltip('菜单').hitTestable(), findsOneWidget);
    expect(find.text('分区').hitTestable(), findsOneWidget);
    await finish(tester);
  });
}

class _MemoryAssetLoader extends AssetLoader {
  _MemoryAssetLoader(this.data);
  final Map<String, dynamic> data;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => data;
}

class _Settings extends SettingsService {
  final _app = AppSettingsController();
  final _font = FontSettingsController();
  @override
  AppSettingsController get app => _app;
  @override
  FontSettingsController get font => _font;
  @override
  // ignore: must_call_super
  void onInit() {}
}
