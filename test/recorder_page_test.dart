import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_manager.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_scheduler.dart';
import 'package:pure_live/recorder/models/live_record_task.dart';
import 'package:pure_live/recorder/models/record_status.dart';
import 'package:pure_live/recorder/pages/record_settings/record_settings_controller.dart';
import 'package:pure_live/recorder/pages/recorder/recorder_controller.dart';
import 'package:pure_live/recorder/pages/recorder/recorder_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  final translations = <String, Map<String, dynamic>>{};
  late _Recorder recorder;
  late LiveRecordTask task;
  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('recorder-page-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Hive.init(root.path);
    await HivePrefUtil.init();
    for (final locale in ['zh', 'en']) {
      translations[locale] =
          jsonDecode(await File('assets/translations/$locale.json').readAsString()) as Map<String, dynamic>;
    }
  });
  setUp(() {
    Get.testMode = true;
    Get.put<SettingsService>(_Settings());
    recorder = Get.put<RecorderController>(_Recorder()) as _Recorder;
    task = LiveRecordTask(
      taskId: 'fixture',
      roomId: 'fixture',
      platform: 'bilibili',
      title: 'A long live title / 测试直播间标题',
      nick: 'A long streamer name',
      avatar: '',
      cover: '',
      createTime: DateTime(2026, 9, 7, 13, 12),
      status: RecordStatus.queued,
      recordedSeconds: 711,
      fileSize: 177121160,
    )..selectedQuality = 'Original quality / 原画';
    recorder.tasks.add(task);
  });
  tearDown(Get.reset);
  tearDownAll(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });
  Future<void> open(WidgetTester tester, String locale, double width, double scale) async {
    tester.view.physicalSize = Size(width, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
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
            // A route with a back affordance avoids unrelated shell MenuButton state.
            home: const SizedBox.shrink(),
            initialRoute: '/recorder',
            getPages: [GetPage(name: '/recorder', page: () => const RecorderPage())],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final locale in ['zh', 'en']) {
    for (final status in RecordStatus.values) {
      testWidgets('recorder $status actions remain reachable in $locale at double text size', (tester) async {
        task.status = status;
        await open(tester, locale, 320, 2);
        expect(tester.takeException(), isNull);
        final key = switch (status) {
          RecordStatus.running || RecordStatus.preparing || RecordStatus.reconnecting => 'recorder_stop',
          RecordStatus.failed => 'retry',
          RecordStatus.completed => 'recorder_restart_record',
          RecordStatus.waitingLive => 'recorder_check_now',
          _ => 'recorder_start',
        };
        final button = find.widgetWithText(FilledButton, translations[locale]![key] as String);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        expect(recorder.stops, key == 'recorder_stop' ? 1 : 0);
        expect(recorder.starts, key == 'recorder_stop' ? 0 : 1);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('recorder remove confirmation cancellation retains the card in $locale', (tester) async {
      task.status = RecordStatus.stopped;
      await open(tester, locale, 320, 2);
      final remove = find.widgetWithText(TextButton, translations[locale]!['remove'] as String);
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(recorder.removals, 0);
      await tester.tap(find.widgetWithText(TextButton, translations[locale]!['cancel'] as String));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(recorder.tasks.single, same(task));
      expect(recorder.removals, 0);
      expect(tester.takeException(), isNull);
    });
    for (final width in [320.0, 900.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('recorder queued card fits $locale width=$width scale=$scale', (tester) async {
          await open(tester, locale, width, scale);
          expect(tester.takeException(), isNull);
          final cancel = find.widgetWithText(OutlinedButton, translations[locale]!['cancel'] as String);
          await tester.ensureVisible(cancel);
          await tester.pumpAndSettle();
          await tester.tap(cancel);
          expect(recorder.stops, 1);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

class _Loader extends AssetLoader {
  const _Loader(this.values);
  final Map<String, dynamic> values;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}

class _Settings extends SettingsService {
  @override
  final font = FontSettingsController();
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _Recorder extends RecorderController {
  _Recorder() : super.forTesting(settings: RecordSettingsController(), ffmpeg: _Events(), scheduler: _Scheduler());
  int stops = 0;
  int starts = 0;
  int removals = 0;
  @override
  // No native services or persistence in a page-only widget fixture.
  // ignore: must_call_super
  void onInit() {}
  @override
  // ignore: must_call_super
  void onClose() {}
  @override
  Future<void> stopTask(LiveRecordTask task) async {
    stops++;
  }

  @override
  Future<void> forceStartTask(LiveRecordTask task) async {
    starts++;
  }

  @override
  Future<void> unRecorder(LiveRecordTask task) async {
    removals++;
  }
}

class _Events implements FFmpegManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Scheduler implements FFmpegScheduler {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
