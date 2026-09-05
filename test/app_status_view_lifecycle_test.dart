import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/base/base_page_scroll_bone.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings/page_settings_controller.dart';
import 'package:pure_live/common/services/settings/theme_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/common/widgets/app_status_view.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/popular/popular_controller.dart';
import 'package:pure_live/modules/popular/popular_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _StatusSettings settings;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pure-live-status-lifecycle-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Hive.init(directory.path);
    await HivePrefUtil.init();
  });
  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    settings = _StatusSettings();
  });
  tearDown(Get.reset);
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> mountLoading(WidgetTester tester, {Widget? child}) async {
    await tester.pumpWidget(
      GetMaterialApp(
        home: Builder(
          builder: (context) {
            if (!Get.isRegistered<SettingsService>()) Get.put<SettingsService>(settings);
            return child ?? const AppStatusView(type: AppStatusType.loading);
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('custom to default style starts the visible rotation immediately', (tester) async {
    settings.theme.loadingStyle.value = 'wave';
    await mountLoading(tester);
    settings.theme.loadingStyle.value = 'default';
    await tester.pump();
    final rotation = tester.widget<RotationTransition>(find.byType(RotationTransition));
    final start = rotation.turns.value;
    await tester.pump(const Duration(milliseconds: 250));
    expect(rotation.turns.value, isNot(start));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('switching away from default leaves only the selected animation ticking', (tester) async {
    settings.theme.loadingStyle.value = 'wave';
    await mountLoading(tester);
    final coldCustomTicks = tester.binding.transientCallbackCount;
    await tester.pumpWidget(const SizedBox.shrink());
    settings.theme.loadingStyle.value = 'default';
    await mountLoading(tester);
    settings.theme.loadingStyle.value = 'wave';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, coldCustomTicks);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unknown restored style has an animated default fallback', (tester) async {
    settings.theme.loadingStyle.value = 'removed-style';
    await mountLoading(tester);
    final rotation = tester.widget<RotationTransition>(find.byType(RotationTransition));
    final start = rotation.turns.value;
    await tester.pump(const Duration(milliseconds: 250));
    expect(rotation.turns.value, isNot(start));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('loading completion and unmount retire all animation callbacks', (tester) async {
    final type = ValueNotifier(AppStatusType.loading);
    addTearDown(type.dispose);
    await mountLoading(
      tester,
      child: ValueListenableBuilder<AppStatusType>(
        valueListenable: type,
        builder: (context, value, _) => AppStatusView(type: value),
      ),
    );
    expect(tester.binding.transientCallbackCount, 1);
    type.value = AppStatusType.empty;
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    type.value = AppStatusType.loading;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('default spinner respects ancestor ticker muting and resumes', (tester) async {
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    await mountLoading(
      tester,
      child: ValueListenableBuilder<bool>(
        valueListenable: enabled,
        builder: (context, value, _) => TickerMode(
          enabled: value,
          child: const AppStatusView(type: AppStatusType.loading),
        ),
      ),
    );
    enabled.value = false;
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.binding.transientCallbackCount, 0);
    enabled.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final rotation = tester.widget<RotationTransition>(find.byType(RotationTransition));
    final start = rotation.turns.value;
    await tester.pump(const Duration(milliseconds: 250));
    expect(rotation.turns.value, isNot(start));
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('color changes reuse the visible spinner without resetting its phase', (tester) async {
    await mountLoading(tester);
    final before = tester.widget<RotationTransition>(find.byType(RotationTransition));
    final phase = before.turns.value;
    settings.theme.loadingStyleColorSwitch.value = '#00FF00';
    await tester.pump();
    final after = tester.widget<RotationTransition>(find.byType(RotationTransition));
    expect(after.turns, same(before.turns));
    expect(after.turns.value, phase);
    expect(tester.binding.transientCallbackCount, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('popular page retires loading tickers after returning to a settled tab', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late PopularController popular;
    await tester.pumpWidget(
      GetMaterialApp(
        home: Builder(
          builder: (context) {
            if (!Get.isRegistered<SettingsService>()) Get.put<SettingsService>(settings);
            popular = Get.isRegistered<PopularController>()
                ? Get.find<PopularController>()
                : Get.put<PopularController>(_StatusPopularController());
            return const PopularPage();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    popular.tabController.animateTo(1);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final loading = find.byWidgetPredicate((widget) => widget is AppStatusView && widget.type == AppStatusType.loading);
    expect(find.descendant(of: loading, matching: find.byType(RotationTransition)), findsOneWidget);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    popular.tabController.animateTo(0);
    await tester.pump();
    // Advance real frame-sized steps: a single one-second pump can mount the
    // empty-state entrance tween at its end, not simulate its first second.
    await tester.pumpAndSettle(
      const Duration(milliseconds: 16),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 3),
    );
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _StatusSettings extends SettingsService {
  @override
  final theme = ThemeSettingsController();
  @override
  final page = PageSettingsController();
  @override
  final font = FontSettingsController();

  @override
  // This fixture owns its settings and deliberately skips service bootstrap.
  // ignore: must_call_super
  void onInit() {}
}

class _StatusPopularController extends PopularController {
  @override
  // Only fixture sites are mounted; production bootstrap performs network IO.
  // ignore: must_call_super
  void onInit() {
    for (var i = 0; i < 2; i++) {
      final id = 'fixture-$i';
      sites.add(Site(id: id, name: 'Platform $i', logo: '', liveSite: LiveSite()));
      Get.put<BasePageScrollAndStateBone<LiveRoom>>(_StatusGridController()..pageEmpty.value = i == 0, tag: id);
    }
    tabController = TabController(length: 2, vsync: this);
  }

  @override
  void onClose() {
    tabController.dispose();
    super.onClose();
  }
}

class _StatusGridController extends BasePageScrollAndStateBone<LiveRoom> {
  @override
  Future<void> loadData() async {}
  @override
  Future<void> refreshData() async {}
  @override
  Future<void> goToPage(int page) async {}
  @override
  void setPageSize(int? newSize) {}
}
