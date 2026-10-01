import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/pages/record_settings/record_settings_dialogs.dart';
import 'package:pure_live/pages/record_settings/record_settings_page.dart';
import 'package:pure_live/pages/recorder/recorder_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';

/// FFmpeg is never started by these tests.
final class _NoFfmpeg implements FfmpegRunner {
  @override
  Future<FfmpegExecution> start(List<String> arguments) => throw UnsupportedError('no FFmpeg in tests');
}

RecordTask _task(String roomId, RecordStatus status, {String? stage, String? error, String nick = '主播'}) => RecordTask(
  taskId: 'bilibili_$roomId',
  roomId: roomId,
  platform: 'bilibili',
  title: '房间 $roomId',
  nick: nick,
  avatar: '',
  cover: '',
  createTime: DateTime(2026, 9, 1, 20, 30),
  status: status,
  lastErrorStage: stage,
  lastError: error,
);

/// The services, recording over a temporary folder (with a recorder unless
/// `withRecorder` is false) and the toasts shown.
final class _Harness {
  new(this.services, this.recording, this.folder, this.toasts);

  final AppServices services;
  final AppRecording recording;
  final Directory folder;
  final List<String> toasts;
}

Future<_Harness> _pump(
  WidgetTester tester,
  Widget Function(RouteArgs route) page, {
  bool withRecorder = true,
  List<RecordTask> tasks = const [],
  Map<String, Object?> legacy = const {},
  Future<String?> Function()? picker,
}) async {
  tester.view
    ..physicalSize = const Size(420, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = (await tester.runAsync(() async {
    final services = await testServices();
    final folder = await Directory.systemTemp.createTemp('pure_live_recorder_test_');
    await services.store.meta.keepLegacyValues(legacy);
    final recording = buildAppRecording(
      store: services.store,
      sites: services.sites,
      proxy: services.proxy,
      dataRoot: folder,
      ffmpeg: withRecorder ? _NoFfmpeg() : null,
    );
    await recording.loadSettings();
    await recording.recorder?.restore(jsonEncode([for (final task in tasks) task.toJson()]));
    return _Harness(services, recording, folder, []);
  }))!;
  addTearDown(
    () => tester.runAsync(() async {
      await harness.recording.dispose();
      await harness.services.close();
      await harness.folder.delete(recursive: true);
    }),
  );
  final strings = (await tester.runAsync(loadStrings))!;
  final previousToast = AppNavigator.toast;
  AppNavigator.toast = harness.toasts.add;
  addTearDown(() => AppNavigator.toast = previousToast);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(harness.services),
        recordingProvider.overrideWithValue(harness.recording),
        recorderProvider.overrideWithValue(harness.recording.recorder),
        if (picker != null) recordDirectoryPickerProvider.overrideWithValue(picker),
      ],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp(
          theme: const LiveTheme(primaryColor: Colors.blue).light,
          home: page(const RouteArgs(RoutePath.kRecordPage)),
        ),
      ),
    ),
  );
  await _settle(tester);
  return harness;
}

/// Lets the store's and the file system's work (real async) finish, then
/// the frames.
Future<void> _settle(WidgetTester tester) async {
  // File and database work completes outside the fake clock: give it real
  // time, step by step, until no spinner is left.
  for (var i = 0; i < 60; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
    if (i >= 3 && find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await _settle(tester);
}

void main() {
  group('RecordSettingsStore', () {
    test('moves the values kept before M8.1 into the store once: v4 meta first, then 3.x parked values', () async {
      final services = await testServices();
      addTearDown(services.close);
      await services.store.meta.keepLegacyValues({
        'segmentTime': 600,
        'maxTaskCount': '5',
        'enable_polling': true,
        'recorder_rw_timeout': 31,
        'default_quality': '超清',
        'recordSavePath': ' /old/records ',
      });
      await services.store.meta.set(
        RecordSettingsStore.legacyStorageKey,
        jsonEncode({'maxTaskCount': '7', 'recorder_folder_naming_strategy': 1}),
      );
      final settings = RecordSettingsStore(services.store);
      await settings.load();
      expect(settings.current.maxTaskCount, 7, reason: "the user's v4 value wins over 3.x's");
      expect(settings.current.usePinyinForFolder, isTrue);
      expect(settings.current.segmentTime, 600);
      expect(settings.current.enablePolling, isTrue);
      expect(settings.current.rwTimeout, 15, reason: '3.x normalized unsupported timeouts to 15 s');
      expect(settings.current.defaultQuality, '超清');
      expect(settings.current.savePath, '/old/records');
      expect(await services.store.meta.get(RecordSettingsStore.legacyStorageKey), isNull);
      expect(await services.store.meta.legacyValue('segmentTime'), isNull);
      expect(services.store.settings.get(Settings.recordMaxTaskCount), 7);

      final changes = <int>[];
      final subscription = settings.changes.listen((value) => changes.add(value.maxTaskCount));
      await settings.set(Settings.recordMaxTaskCount, 99);
      expect(settings.current.maxTaskCount, 10);
      await Future<void>.delayed(Duration.zero);
      expect(changes, [10]);
      await subscription.cancel();

      final backup = await BackupService(services.store).exportAll();
      expect((backup['recorder']! as Map)['maxTaskCount'], 10, reason: 'backups carry the recorder settings');
    });
  });

  test("Android folder addresses: shared storage opens in the file manager, the app's own folder does not", () {
    expect(
      androidDocumentFolderUri('/storage/emulated/0/Download/PureLiveRecords/').toString(),
      'content://com.android.externalstorage.documents/document/primary%3ADownload%2FPureLiveRecords',
    );
    expect(
      androidDocumentFolderUri('/storage/emulated/0/Android/data/com.mystyle.purelive.v4dev/files/Records'),
      isNull,
    );
    expect(androidDocumentFolderUri('/data/user/0/com.mystyle.purelive.v4dev/files'), isNull);
    expect(androidDocumentFolderUri('/storage/emulated/0'), isNull);
  });

  testWidgets('without FFmpeg the centre says recording is unavailable', (tester) async {
    await _pump(tester, (route) => RecorderPage(route: route), withRecorder: false);
    expect(find.text('录制中心'), findsOneWidget);
    expect(find.text('录制不可用'), findsOneWidget);
    expect(find.byKey(const ValueKey('recorder-settings')), findsOneWidget);
  });

  testWidgets('lists the tasks by status with counts, explains failures and removes after asking', (tester) async {
    final harness = await _pump(
      tester,
      (route) => RecorderPage(route: route),
      tasks: [
        _task('1', RecordStatus.failed, stage: 'ffmpeg.storageFull', error: 'No space left on device', nick: '甲'),
        _task('2', RecordStatus.stopped, nick: '乙'),
        _task('3', RecordStatus.completed, nick: '丙'),
      ],
    );
    expect(find.text('全部 3'), findsOneWidget);
    expect(find.text('失败 1'), findsOneWidget);
    expect(find.text('录制中'), findsOneWidget, reason: 'an empty status shows no count');
    expect(find.text('房间 1'), findsOneWidget);
    expect(find.text('哔哩哔哩'), findsWidgets);
    expect(find.textContaining('录制已停止：存储空间已满'), findsOneWidget);
    expect(find.text('No space left on device'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('重新录制'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('recorder-status-7')));
    expect(find.text('房间 1'), findsOneWidget);
    expect(find.text('房间 2'), findsNothing);

    await _tap(tester, find.byKey(const ValueKey('recorder-status-1')));
    expect(find.text('没有“录制中”的任务'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('recorder-status-0')));
    await _tap(tester, find.byKey(const ValueKey('recorder-remove')).first);
    expect(find.textContaining('确定停止监控'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('recorder-remove-confirm')));
    await tester.pump(const Duration(seconds: 3));
    await _settle(tester);
    expect(harness.recording.recorder!.tasks, hasLength(2));
    expect(find.text('全部 2'), findsOneWidget);
  });

  testWidgets('the folder dialog saves the folder from the system picker (M12.3)', (tester) async {
    late Directory picked;
    final harness = await _pump(tester, (route) => RecordSettingsPage(route: route), picker: () async => picked.path);
    picked = harness.folder;
    await _tap(tester, find.text('Pure Live 录制文件目录'));
    expect(find.byKey(const ValueKey('record-directory-default')), findsOneWidget, reason: 'the default stays');
    await _tap(tester, find.byKey(const ValueKey('record-directory-browse')));
    await _settle(tester);
    expect(harness.recording.settings.current.savePath, picked.path);
    expect(find.byKey(const ValueKey('record-directory-input')), findsNothing, reason: 'saved and closed');
  });

  testWidgets('the settings page shows imported values and saves changes', (tester) async {
    final harness = await _pump(
      tester,
      (route) => RecordSettingsPage(route: route),
      legacy: {'segmentTime': 600, 'maxTaskCount': 5, 'recorder_rw_timeout': 30},
    );
    expect(find.text('录制设置'), findsOneWidget);
    expect(find.text('10m'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('30s'), findsOneWidget);
    expect(find.textContaining('PureLiveRecords').evaluate().isEmpty, isTrue, reason: 'the default folder is used');

    await _tap(tester, find.text('Pure Live 录制文件目录'));
    final parent = harness.folder.path;
    await tester.enterText(find.byKey(const ValueKey('record-directory-input')), parent);
    await _tap(tester, find.byKey(const ValueKey('record-directory-confirm')));
    expect(harness.recording.settings.current.savePath, parent);
    expect(find.text('$parent/PureLiveRecords'), findsOneWidget);
    expect(File('$parent/PureLiveRecords/${RecordStorage.ownershipMarkerName}').existsSync(), isTrue);

    await _tap(tester, find.text('最大同时录制任务数'));
    await tester.enterText(find.byKey(const ValueKey('record-max-tasks-input')), '11');
    await tester.pump();
    expect(find.text('请输入 1 到 10 的整数'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('record-max-tasks-quick-4')));
    await _tap(tester, find.byKey(const ValueKey('record-max-tasks-confirm')));
    expect(harness.recording.settings.current.maxTaskCount, 4);
    expect(harness.services.store.settings.get(Settings.recordMaxTaskCount), 4);

    await _tap(tester, find.text('录制读写超时'));
    await _tap(tester, find.byKey(const ValueKey('record-option-60')));
    expect(harness.recording.settings.current.rwTimeout, 60);

    await _tap(tester, find.text('启用开播检测'));
    expect(harness.recording.settings.current.enablePolling, isTrue);
    expect(find.text('检测间隔时间'), findsOneWidget);
  });
}
