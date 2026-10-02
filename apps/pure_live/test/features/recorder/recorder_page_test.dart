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
import 'package:pure_live/shared/record/record_look.dart';
import 'package:pure_live/shared/record/record_state.dart';

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

  // U.2a2 (problem 02: "现在这个看起来像在录制"): one glyph per state of the
  // task, red only while a file is written; the mark on the picture names
  // recording, reconnecting and joining, and nothing else.
  testWidgets('U.2a2: the room bar shows each recording state; only running is red; the marks name the state', (
    tester,
  ) async {
    const ids = ['1', '2', '3', '4', '5', '6', '7', '8'];
    final rooms = {for (final id in ids) id: LiveRoom(platform: 'bilibili', roomId: id)};
    DateTime now() => DateTime(2026, 9, 1, 20, 42, 34);
    await _pump(
      tester,
      (_) => Builder(
        // The glyphs hold still, so the frames settle.
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: Scaffold(
            body: ListView(
              children: [
                Wrap(
                  children: [
                    for (final id in ids) RecordButton(key: ValueKey('b$id'), room: rooms[id]!),
                    RecordButton(key: const ValueKey('timed'), room: rooms['4']!, showTime: true, now: now),
                  ],
                ),
                for (final id in ids) RoomRecordingBadge(key: ValueKey('m$id'), room: rooms[id]!, now: now),
                RoomRecordingBadge(key: const ValueKey('hidden'), room: rooms['4']!, showsRecording: false, now: now),
              ],
            ),
          ),
        ),
      ),
      tasks: [for (final id in ids.skip(1)) _task(id, RecordStatus.stopped)],
      prepare: (recording) {
        RecordTask task(String id) => recording.taskFor(rooms[id]!)!;
        task('2').status = RecordStatus.waitingLive;
        task('3').status = RecordStatus.preparing;
        task('4').status = RecordStatus.running;
        task('5').status = RecordStatus.reconnecting;
        task('6')
          ..status = RecordStatus.processing
          ..mergeProgress = 0.45;
        task('7').status = RecordStatus.failed;
        task('8').status = RecordStatus.completed;
      },
    );
    Finder inside(String key, Finder finder) => find.descendant(of: find.byKey(ValueKey(key)), matching: finder);
    const glyphs = {
      '1': 'idle',
      '2': 'waiting',
      '3': 'preparing',
      '4': 'recording',
      '5': 'reconnecting',
      '6': 'processing',
      '7': 'failed',
      '8': 'idle',
    };
    for (final MapEntry(key: id, value: state) in glyphs.entries) {
      final glyph = inside('b$id', find.byKey(ValueKey('record-glyph-$state')));
      expect(glyph, findsOneWidget, reason: 'room $id is $state');
      final painter =
          tester.widget<CustomPaint>(find.descendant(of: glyph, matching: find.byType(CustomPaint))).painter!
              as RecordGlyphPainter;
      expect(
        painter.colors.contains(LiveSemanticColors.recording),
        state == 'recording',
        reason: 'red only while recording ($id)',
      );
    }
    // The words of each state (tooltips; "自动录" is the pill's own text).
    expect(find.byTooltip('录制'), findsNWidgets(2));
    expect(inside('b2', find.text('自动录')), findsOneWidget);
    expect(find.byTooltip('准备中'), findsOneWidget);
    expect(find.byTooltip('录制中'), findsNWidgets(2));
    expect(find.byTooltip('重连中'), findsOneWidget);
    expect(find.byTooltip('合成中'), findsOneWidget);
    expect(find.byTooltip('录制失败'), findsOneWidget);
    // The join draws its progress.
    final join =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: inside('b6', find.byKey(const ValueKey('record-glyph-processing'))),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as RecordGlyphPainter;
    expect(join.progress, 0.45);
    // c8: the landscape bar's form carries the time (started 20:30, now 20:42:34).
    expect(inside('timed', find.text('12:34')), findsOneWidget);

    // c7: the marks — recording on red, reconnecting and joining on a dark
    // pill; nothing while not recording, preparing or failed.
    expect(inside('m4', find.text('录制中 12:34')), findsOneWidget);
    expect(inside('m5', find.text('重连中 12:34')), findsOneWidget);
    expect(inside('m6', find.text('合成中 45%')), findsOneWidget);
    for (final id in ['1', '2', '3', '7', '8']) {
      expect(inside('m$id', find.byType(RecordingBadge)), findsNothing, reason: 'room $id');
    }
    expect(inside('m4', find.byKey(const ValueKey('recording-badge-recording'))), findsOneWidget);
    expect(inside('m5', find.byKey(const ValueKey('recording-badge-reconnecting'))), findsOneWidget);
    expect(inside('m6', find.byKey(const ValueKey('recording-badge-processing'))), findsOneWidget);
    expect(inside('hidden', find.byType(RecordingBadge)), findsNothing, reason: 'the landscape bar shows it');
  });

  test('U.2a2: every card state has its glyph and words; queued waits like waiting, saved is idle', () {
    expect(
      {for (final state in RecordCardState.values) state: recordGlyphState(state)},
      {
        RecordCardState.idle: RecordGlyphState.idle,
        RecordCardState.waiting: RecordGlyphState.waiting,
        RecordCardState.preparing: RecordGlyphState.preparing,
        RecordCardState.queued: RecordGlyphState.waiting,
        RecordCardState.recording: RecordGlyphState.recording,
        RecordCardState.reconnecting: RecordGlyphState.reconnecting,
        RecordCardState.processing: RecordGlyphState.processing,
        RecordCardState.saved: RecordGlyphState.idle,
        RecordCardState.failed: RecordGlyphState.failed,
      },
    );
    expect(recordBadgeState(null), isNull);
    expect([for (final status in RecordStatus.values) recordBadgeState(_task('1', status))].nonNulls.toList(), [
      RecordGlyphState.recording,
      RecordGlyphState.reconnecting,
      RecordGlyphState.processing,
    ], reason: 'preparing is not "录制中" any more');
    expect(recordJoinProgress(_task('1', RecordStatus.processing)..mergeProgress = double.nan), isNull);
    expect(recordJoinProgress(_task('1', RecordStatus.processing)..mergeProgress = 1.2), 1);
  });

  testWidgets('without FFmpeg the centre says recording is unavailable', (tester) async {
    await _pump(tester, (route) => RecorderPage(route: route), withRecorder: false);
    expect(find.text('录制中心'), findsOneWidget);
    expect(find.text('录制不可用'), findsOneWidget);
    expect(find.byKey(const ValueKey('recorder-settings')), findsOneWidget);
  });
}
