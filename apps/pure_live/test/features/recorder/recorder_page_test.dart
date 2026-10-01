import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/buttons/record_button.dart';
import 'package:pure_live/features/live_play/player/recording_badge.dart';
import 'package:pure_live/features/recorder/recorder_page.dart';
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
  void Function(AppRecording recording)? prepare,
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
    prepare?.call(recording);
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

  // U.2a change 13 replaces M13.16's glyph with an orange dot: a grey ring
  // around a red dot, "⏱ 自动录" for a room that records when it goes live,
  // a white dot on red while recording, and the "● 录制中 12:34" mark.
  testWidgets('U.2a: the room bar records as a ring, "自动录" or a red disc; the picture shows the time', (tester) async {
    final rooms = [
      for (final id in ['1', '2', '3']) LiveRoom(platform: 'bilibili', roomId: id),
    ];
    await _pump(
      tester,
      (_) => Builder(
        // The recording dot holds still, so the frames settle.
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: Scaffold(
            appBar: AppBar(
              actions: [
                RecordButton(key: const ValueKey('idle'), room: rooms[0]),
                RecordButton(key: const ValueKey('monitored'), room: rooms[1]),
                RecordButton(key: const ValueKey('recording'), room: rooms[2]),
              ],
            ),
            body: Center(
              child: RoomRecordingBadge(room: rooms[2], now: () => DateTime(2026, 9, 1, 20, 42, 34)),
            ),
          ),
        ),
      ),
      tasks: [_task('2', RecordStatus.stopped), _task('3', RecordStatus.stopped)],
      // U.2f: "自动录" means the task waits for the room ("开播自动录"); a
      // stopped one is a plain ring now.
      prepare: (recording) {
        recording.taskFor(rooms[1])!.status = RecordStatus.waitingLive;
        recording.taskFor(rooms[2])!.status = RecordStatus.running;
      },
    );
    Finder inside(String key, Finder finder) => find.descendant(of: find.byKey(ValueKey(key)), matching: finder);
    expect(inside('idle', find.byKey(const ValueKey('record-glyph-idle'))), findsOneWidget);
    expect(find.byTooltip('录制'), findsOneWidget);
    expect(inside('monitored', find.text('自动录')), findsOneWidget);
    expect(inside('monitored', find.byIcon(AppIcons.autoRecord)), findsOneWidget);
    expect(inside('recording', find.byKey(const ValueKey('record-glyph-recording'))), findsOneWidget);
    expect(find.byTooltip('录制中'), findsOneWidget);
    // Started 20:30 (the task's start), now 20:42:34.
    expect(find.text('录制中 12:34'), findsOneWidget);
  });

  testWidgets('without FFmpeg the centre says recording is unavailable', (tester) async {
    await _pump(tester, (route) => RecorderPage(route: route), withRecorder: false);
    expect(find.text('录制中心'), findsOneWidget);
    expect(find.text('录制不可用'), findsOneWidget);
    expect(find.byKey(const ValueKey('recorder-settings')), findsOneWidget);
  });
}
