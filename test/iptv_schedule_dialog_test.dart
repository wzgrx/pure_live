import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/core/iptv/local/database.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/iptv_programme_policy.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/iptv_schedule_dialog.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';

late Map<String, dynamic> _english;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    _english = jsonDecode(await File('assets/translations/en.json').readAsString()) as Map<String, dynamic>;
  });

  setUp(() {
    Get.testMode = true;
    Get.put<SettingsService>(_Settings());
  });

  tearDown(() {
    Get.reset();
    Get.testMode = false;
  });

  testWidgets('schedule distinguishes loading and retryable failure at narrow large text', (tester) async {
    final controller = _ScheduleController()..scheduleLoading.value = true;
    addTearDown(controller.disposeFixture);
    await _pump(tester, controller, textScale: 3);

    expect(find.byKey(const ValueKey('iptv-schedule-loading')), findsOneWidget);
    expect(tester.takeException(), isNull);

    controller.scheduleLoading.value = false;
    controller.scheduleLoadFailed.value = true;
    await tester.pump();
    expect(find.byKey(const ValueKey('iptv-schedule-retry')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.byKey(const ValueKey('iptv-schedule-retry')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('iptv-schedule-retry')));
    await tester.pump();
    expect(controller.loadCalls, 1);
  });

  testWidgets('schedule rows stack responsively, keep the live boundary, and block duplicate catch-up taps', (
    tester,
  ) async {
    final now = DateTime(2026, 9, 12, 11);
    final controller = _ScheduleController();
    for (var index = 0; index < 12; index++) {
      final start = DateTime(2026, 9, 12, 9).add(Duration(hours: index));
      controller.currentChannelSchedule.add(
        EpgProgramme(
          id: index,
          epgChannelId: 'fixture-channel',
          sourceId: 'fixture-source',
          title: 'Programme $index with a long localized schedule title',
          start: start,
          stop: start.add(const Duration(hours: 1)),
        ),
      );
    }
    addTearDown(controller.disposeFixture);
    await _pump(tester, controller, textScale: 3, now: () => now);
    await tester.pumpAndSettle();

    expect(controller.claimedIndex, 2);
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('Programme 2 with a long localized schedule title'), findsOneWidget);
    expect(tester.takeException(), isNull);

    controller.catchUpSwitching.value = true;
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('iptv-catchup-switch-progress')), findsOneWidget);
    await tester.ensureVisible(find.text('Programme 2 with a long localized schedule title'));
    await tester.pump();
    await tester.tap(find.text('Programme 2 with a long localized schedule title'));
    await tester.pump();
    expect(controller.tappedTitles, isEmpty);

    controller.catchUpSwitching.value = false;
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(find.text('Programme 2 with a long localized schedule title'));
    await tester.pump();
    await tester.tap(find.text('Programme 2 with a long localized schedule title'));
    await tester.pump();
    expect(controller.tappedTitles, ['Programme 2 with a long localized schedule title']);
    expect(controller.closeCalls, 1);
    expect(tester.takeException(), isNull);
  });

  test('dialog source keeps the body scrollable and avoids fixed ListTile layout', () {
    final source = File('lib/modules/live_play/widgets/video_player/iptv_schedule_dialog.dart').readAsStringSync();
    expect(source, contains('SingleChildScrollView'));
    expect(source, contains('LayoutBuilder'));
    expect(source, contains('scaledBody > 22'));
    expect(source, isNot(contains('ListTile(')));
  });
}

Future<void> _pump(
  WidgetTester tester,
  _ScheduleController controller, {
  double textScale = 1,
  DateTime Function()? now,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 480);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: _Translations(_english),
      child: Builder(
        builder: (context) => GetMaterialApp(
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: Scaffold(
                body: Center(
                  child: IptvScheduleDialogContent(
                    controller: controller,
                    now: now ?? () => DateTime(2026, 9, 12, 11),
                    onClose: () => controller.closeCalls++,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
}

class _Translations extends AssetLoader {
  const _Translations(this.values);

  final Map<String, dynamic> values;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}

class _Settings extends SettingsService {
  @override
  final font = _FontSettings();

  @override
  // The fixture intentionally starts no persistence or background services.
  // ignore: must_call_super
  void onInit() {}
}

class _FontSettings implements FontSettingsController {
  @override
  final fontSizeBodySmall = 12.0.obs;
  @override
  final fontSizeBodyMedium = 13.0.obs;
  @override
  final fontSizeBodyLarge = 14.0.obs;
  @override
  final fontSizeTitleMedium = 15.0.obs;
  @override
  final fontSizeTitleLarge = 20.0.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ScheduleController implements VideoController {
  @override
  final room = LiveRoom(
    roomId: 'fixture-room',
    platform: 'iptv',
    title: 'Fixture channel',
    epgId: 'fixture-epg',
    link: 'https://fixture/live',
  );
  @override
  final currentChannelSchedule = <EpgProgramme>[].obs;
  @override
  final scheduleLoading = false.obs;
  @override
  final scheduleLoadFailed = false.obs;
  @override
  final catchUpSwitching = false.obs;
  @override
  final scheduleScrollController = ScrollController();
  @override
  bool hasScrolledToLive = false;
  @override
  PlayerStatus get status => PlayerStatus.playing;

  int loadCalls = 0;
  int closeCalls = 0;
  int? claimedIndex;
  final tappedTitles = <String>[];

  @override
  Future<void> loadFullChannelSchedule(String? epgId) async {
    loadCalls++;
  }

  @override
  bool claimInitialScheduleScroll(int liveIndex) {
    claimedIndex = liveIndex;
    if (liveIndex < 0 || hasScrolledToLive) return false;
    hasScrolledToLive = true;
    return true;
  }

  @override
  Future<IptvProgrammeSelectionResult> onProgrammeTapped(
    EpgProgramme programme, {
    DateTime? now,
    VoidCallback? closeSchedule,
    ValueChanged<String>? showMessage,
  }) async {
    tappedTitles.add(programme.title);
    closeSchedule?.call();
    return IptvProgrammeSelectionResult.catchupStarted;
  }

  void disposeFixture() {
    scheduleScrollController.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
