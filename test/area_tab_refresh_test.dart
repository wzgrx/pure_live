import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/model/live_category.dart';
import 'package:pure_live/modules/areas/areas_grid_view.dart';
import 'package:pure_live/modules/areas/areas_list_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Site extends LiveSite {
  int requests = 0;
  Object? failure;
  Future<void>? pending;
  List<(String, int)> catalog = [('First', 40), ('Empty', 0), ('Last', 2)];
  @override
  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    requests++;
    if (pending case final wait?) await wait;
    if (failure case final error?) throw error;
    return [
      for (final (id, count) in catalog)
        LiveCategory(
          id: id,
          name: id,
          children: [
            for (var i = 0; i < count; i++)
              LiveArea(areaId: '$id-$i', areaName: 'Fixture $i', platform: 'fixture', typeName: id),
          ],
        ),
    ];
  }
}

class _Controller extends AreasListController {
  _Controller(super.site);
  @override
  Future<bool> checkNetworkBeforeRequest() async => true;
}

class _Loader extends AssetLoader {
  const _Loader();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>;
}

Future<(_Controller, _Site)> _mount(WidgetTester tester, {Size size = const Size(400, 640)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final site = _Site();
  late _Controller controller;
  var initialized = false;
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      startLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: const _Loader(),
      child: Builder(
        builder: (context) => GetMaterialApp(
          locale: context.locale,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (_) {
                if (!initialized) {
                  initialized = true;
                  Get.put(SettingsService(), permanent: true);
                  controller = _Controller(Site(id: 'fixture', name: 'Fixture', logo: '', liveSite: site));
                  Get.put<AreasListController>(controller, tag: 'fixture');
                }
                return const AreaGridView('fixture');
              },
            ),
          ),
        ),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    Get.reset();
  });
  for (var i = 0; i < 10 && !initialized; i++) {
    await tester.pump();
  }
  expect(initialized, true);
  await controller.loadData();
  await tester.pumpAndSettle();
  expect(tester.takeException(), null);
  return (controller, site);
}

Future<void> _pull(WidgetTester tester, Finder target) async {
  final gesture = await tester.startGesture(tester.getCenter(target));
  for (var i = 0; i < 6; i++) {
    await gesture.moveBy(const Offset(0, 70));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
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
  });
  tearDownAll(Hive.close);

  testWidgets('category body accepts a real vertical refresh under horizontal tabs', (tester) async {
    final (_, site) = await _mount(tester);
    expect(site.requests, 1);
    await _pull(tester, find.byType(GridView).hitTestable());
    expect(site.requests, 2);
    expect(tester.takeException(), null);
  });

  testWidgets('empty category retains horizontal navigation and supports refresh', (tester) async {
    final (controller, site) = await _mount(tester);
    final firstController = controller.scrollController;
    firstController.jumpTo(300);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(TabBarView), const Offset(-380, 0));
    await tester.pumpAndSettle();
    expect(controller.tabIndex.value, 1);
    expect(find.byType(TabBarView), findsOneWidget);
    await _pull(tester, find.byType(TabBarView));
    expect(site.requests, 2);
    await tester.drag(find.byType(TabBarView), const Offset(-380, 0));
    await tester.pumpAndSettle();
    expect(controller.tabIndex.value, 2);
    await tester.tap(find.text('First'));
    await tester.pumpAndSettle();
    expect(controller.tabIndex.value, 0);
    expect(identical(controller.scrollController, firstController), true);
    expect(controller.scrollController.offset, 300);
    expect(controller.scrollController.positions, hasLength(1));
    expect(tester.takeException(), null);
  });

  for (final width in [400.0, 900.0]) {
    testWidgets('$width external selection binds paging actions to the visible category', (tester) async {
      final (controller, site) = await _mount(tester, size: Size(width, 640));
      final first = controller.scrollController;
      controller.selectCategory(2);
      await tester.pumpAndSettle();
      final grid = tester.widget<GridView>(find.byKey(const PageStorageKey('area_grid_fixture_Last')));
      expect(identical(controller.scrollController, grid.controller), true);
      expect(identical(controller.scrollController, first), false);
      expect(controller.scrollController.positions, hasLength(1));
      expect(site.requests, 1);
      expect(tester.takeException(), null);
    });

    testWidgets('$width same-count replacement retires old category scroll ownership', (tester) async {
      final (controller, site) = await _mount(tester, size: Size(width, 640));
      final old = controller.scrollController;
      site.catalog = [('New', 40), ('Empty', 0), ('Last', 2)];
      await controller.refreshData();
      await tester.pumpAndSettle();
      final grid = tester.widget<GridView>(find.byKey(const PageStorageKey('area_grid_fixture_New')));
      expect(identical(controller.scrollController, grid.controller), true);
      expect(identical(controller.scrollController, old), false);
      expect(() => old.addListener(() {}), throwsFlutterError);
      expect(tester.takeException(), null);
    });
  }

  testWidgets('reordering taxonomy retains selected identity and scroll controller', (tester) async {
    final (controller, site) = await _mount(tester);
    final first = controller.scrollController;
    first.jumpTo(300);
    await tester.pumpAndSettle();
    site.catalog = [('Last', 2), ('Empty', 0), ('First', 40)];
    await controller.refreshData();
    await tester.pumpAndSettle();
    expect(controller.tabIndex.value, 2);
    expect(tester.widget<TabBarView>(find.byType(TabBarView)).controller!.index, 2);
    final grid = tester.widget<GridView>(find.byKey(const PageStorageKey('area_grid_fixture_First')).hitTestable());
    expect(identical(grid.controller, first), true);
    expect(identical(controller.scrollController, first), true);
    expect(controller.scrollController.offset, 300);
    expect(tester.takeException(), null);
  });

  testWidgets('empty taxonomy releases old controllers and later installs new pages', (tester) async {
    final (controller, site) = await _mount(tester);
    final old = controller.scrollController;
    site.catalog = [];
    await controller.refreshData();
    await tester.pumpAndSettle();
    expect(find.byType(TabBarView), findsNothing);
    expect(identical(controller.scrollController, old), false);
    expect(() => old.addListener(() {}), throwsFlutterError);
    site.catalog = [('Restored', 40)];
    await controller.refreshData();
    await tester.pumpAndSettle();
    expect(controller.tabIndex.value, 0);
    final grid = tester.widget<GridView>(find.byKey(const PageStorageKey('area_grid_fixture_Restored')));
    expect(identical(controller.scrollController, grid.controller), true);
    expect(controller.scrollController.positions, hasLength(1));
    expect(tester.takeException(), null);
  });

  testWidgets('successive taxonomy replacements retire controllers only after children detach', (tester) async {
    final (controller, site) = await _mount(tester);
    final obsolete = <ScrollController>[];
    for (var generation = 0; generation < 4; generation++) {
      obsolete.add(controller.scrollController);
      site.catalog = [for (var index = 0; index <= generation; index++) ('Generation-$generation-$index', 40)];
      await controller.refreshData();
      // No frame between snapshots: the old visible grid is still mounted.
      expect(obsolete.first.hasClients, true);
    }
    await tester.pumpAndSettle();
    expect(tester.widget<TabBarView>(find.byType(TabBarView)).controller!.length, 4);
    expect(controller.scrollController.positions, hasLength(1));
    for (final old in obsolete) {
      expect(() => old.addListener(() {}), throwsFlutterError);
    }
    expect(tester.takeException(), null);
  });

  testWidgets('route disposal drains pending retirements without disposing twice', (tester) async {
    final (controller, site) = await _mount(tester);
    final old = controller.scrollController;
    site.catalog = [('Replacement', 40)];
    await controller.refreshData();
    final replacement = controller.scrollController;
    expect(old.hasClients, true);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(() => old.addListener(() {}), throwsFlutterError);
    expect(() => replacement.addListener(() {}), throwsFlutterError);
    expect(tester.takeException(), null);
  });

  for (final failure in ['network_disconnected', 'LoginRequired']) {
    testWidgets('empty category keeps navigation after $failure and recovers', (tester) async {
      final (controller, site) = await _mount(tester);
      await tester.drag(find.byType(TabBarView), const Offset(-380, 0));
      await tester.pumpAndSettle();
      final emptyController = controller.scrollController;
      site.failure = failure;
      await _pull(tester, find.byKey(const PageStorageKey('area_empty_fixture_Empty')));
      expect(find.byType(TabBarView), findsOneWidget);
      expect(identical(controller.scrollController, emptyController), true);
      expect(controller.scrollController.positions, hasLength(1));
      expect(find.byType(AppStatusView), findsWidgets);
      // The failed refresh must not trap horizontal navigation in this tab.
      await tester.drag(find.byType(TabBarView), const Offset(-380, 0));
      await tester.pumpAndSettle();
      expect(controller.tabIndex.value, 2);
      site.failure = null;
      await _pull(tester, find.byType(GridView).hitTestable());
      expect(site.requests, 3);
      expect(controller.pageError.value, false);
      expect(controller.notLogin.value, false);
      expect(controller.tabIndex.value, 2);
      expect(tester.takeException(), null);
    });
  }

  testWidgets('retry from retained empty error exposes pending work until the response arrives', (tester) async {
    final (controller, site) = await _mount(tester);
    controller.selectCategory(1);
    await tester.pumpAndSettle();
    site.failure = 'network_disconnected';
    await controller.refreshData();
    await tester.pumpAndSettle();
    final retry = find.text(controller.retryActionLabel);
    await tester.ensureVisible(retry);
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    site.failure = null;
    site.pending = gate.future;
    await tester.tap(retry);
    await tester.pump();
    try {
      expect(site.requests, 3);
      expect(controller.loadding.value, true);
      expect(find.byType(TabBarView), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    } finally {
      gate.complete();
      await tester.pumpAndSettle();
    }
    expect(controller.loadding.value, false);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(controller.tabIndex.value, 1);
    expect(tester.takeException(), null);
  });
}
