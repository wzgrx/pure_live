// The live room's popups of U.2f (docs/ui/compare/U.2f/README.md): the
// quality and line menus, the record panel, the danmaku settings panel, the
// room menu and the long press on a message.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/buttons/room_menu_button.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/logic/record_state.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/features/live_play/player/player_view.dart';
import 'package:pure_live/features/live_play/record/record_panel.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';
import 'live_play_support.dart';

/// FFmpeg is never started by these tests.
final class _NoFfmpeg implements FfmpegRunner {
  @override
  Future<FfmpegExecution> start(List<String> arguments) => throw UnsupportedError('no FFmpeg in tests');
}

/// A platform whose second quality resolves only when [gate] opens.
class _GatedSite extends FakeSite {
  new(super.room);

  final Completer<void> gate = Completer();

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    if (quality.id == 250) await gate.future;
    return await super.getPlayUrls(detail: detail, quality: quality);
  }
}

final class _Room {
  new(this.services, this.engine, this.danmaku, this.toasts, this.recording, this.folder);

  final AppServices services;
  final FakeEngine engine;
  final FakeDanmaku danmaku;
  final List<String> toasts;
  final AppRecording? recording;
  final Directory folder;
}

RecordTask _task(RecordStatus status) => RecordTask(
  taskId: 'bilibili_6',
  roomId: '6',
  platform: 'bilibili',
  title: '今晚开黑',
  nick: '主播',
  avatar: '',
  cover: '',
  createTime: DateTime(2026, 10, 1, 21),
  status: status,
);

/// A recording over a temporary folder with [tasks] (restored as 3.x's
/// JSON; [prepare] then sets what a running recorder would).
Future<AppRecording> _recording(
  AppServices services,
  Directory folder, {
  List<RecordTask> tasks = const [],
  void Function(AppRecording recording)? prepare,
}) async {
  final recording = buildAppRecording(
    store: services.store,
    sites: services.sites,
    proxy: services.proxy,
    dataRoot: folder,
    ffmpeg: _NoFfmpeg(),
  );
  await recording.loadSettings();
  await recording.recorder!.restore(jsonEncode([for (final task in tasks) task.toJson()]));
  prepare?.call(recording);
  return recording;
}

Future<_Room> _pump(
  WidgetTester tester, {
  FakeSite? site,
  double width = 400,
  double height = 900,
  bool withRecorder = false,
  List<RecordTask> tasks = const [],
  void Function(AppRecording recording)? prepare,
}) async {
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  RoomOrientationChoice.clearSession();
  final (services, recording, folder) = (await tester.runAsync(() async {
    final services = await testServices();
    final folder = await Directory.systemTemp.createTemp('pure_live_u2f_');
    final recording = withRecorder ? await _recording(services, folder, tasks: tasks, prepare: prepare) : null;
    return (services, recording, folder);
  }))!;
  await tester.runAsync(loadStrings);
  final engine = FakeEngine();
  final danmaku = FakeDanmaku();
  final toasts = <String>[];
  final previous = AppNavigator.toast;
  AppNavigator.toast = toasts.add;
  addTearDown(() => AppNavigator.toast = previous);
  final platform = site ?? FakeSite(liveRoom(startedAt: DateTime.now().subtract(const Duration(minutes: 30))));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        if (recording != null) recordingProvider.overrideWithValue(recording),
        if (recording != null) recorderProvider.overrideWithValue(recording.recorder),
        sitesProvider.overrideWithValue(SiteRegistry({SiteIds.bilibili: () => platform})),
        danmakuProvider.overrideWithValue(DanmakuRegistry({SiteIds.bilibili: () => danmaku})),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(engine)),
      ],
      child: MaterialApp(
        theme: const LiveTheme().light,
        // The recording dot holds still, so the frames settle.
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
        home: LivePlayPage(
          route: RouteArgs(
            RoutePath.kLivePlay,
            arguments: LiveRoom(platform: SiteIds.bilibili, roomId: '6', nick: '主播'),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return _Room(services, engine, danmaku, toasts, recording, folder);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

Future<void> _close(WidgetTester tester, _Room room) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(() async {
    await room.recording?.dispose();
    await room.services.close();
    await room.folder.delete(recursive: true);
  });
}

/// The recorder announces its changes on a stream: one frame delivers the
/// event, the next draws it.
Future<void> _refresh(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Finder _in(String key, Finder finder) => find.descendant(of: find.byKey(ValueKey(key)), matching: finder);

/// The visible keys of [keys], top to bottom.
List<String> _column(WidgetTester tester, List<String> keys) => [
  for (final key in keys)
    if (find.byKey(ValueKey(key)).evaluate().isNotEmpty) key,
]..sort((a, b) => tester.getCenter(find.byKey(ValueKey(a))).dy.compareTo(tester.getCenter(find.byKey(ValueKey(b))).dy));

void main() {
  group('quality and line', () {
    testWidgets('portrait: each button opens its small menu under it; a tick marks the current; a choice closes it', (
      tester,
    ) async {
      final room = await _pump(tester);
      final button = find.byKey(const ValueKey('live-play-quality'));
      await tester.tap(button);
      await tester.pumpAndSettle();
      final items = [for (var i = 0; i < 3; i++) find.byKey(ValueKey('live-play-quality-item-$i'))];
      for (final item in items) {
        expect(item, findsOneWidget);
        expect(tester.getSize(item).height, 48);
      }
      expect(tester.getSize(items.first).width, greaterThanOrEqualTo(128));
      expect(tester.getRect(items.first).top, greaterThan(tester.getRect(button).bottom), reason: 'under the button');
      // The current entry: primary, bold, with the tick; 14-point text.
      final current = tester.widget<Text>(find.descendant(of: items.first, matching: find.text('原画')));
      expect(current.style?.fontSize, 14);
      expect(current.style?.fontWeight, FontWeight.w600);
      expect(current.style?.color, Theme.of(tester.element(button)).colorScheme.primary);
      expect(find.descendant(of: items.first, matching: find.byIcon(AppIcons.selected)), findsOneWidget);
      expect(find.descendant(of: items[1], matching: find.byIcon(AppIcons.selected)), findsNothing);
      expect(_in('live-play-quality', find.byIcon(AppIcons.foldUp)), findsOneWidget, reason: 'the mark points up');

      await tester.tap(items[1]);
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(items[1], findsNothing, reason: 'the menu closes');
      expect(_in('live-play-quality', find.text('超清')), findsOneWidget);
      expect(_in('live-play-quality', find.byIcon(AppIcons.dropDown)), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('live-play-line')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live-play-line-item-0')), findsOneWidget);
      expect(_in('live-play-line-item-0', find.byIcon(AppIcons.selected)), findsOneWidget);
      expect(_in('live-play-line-item-1', find.text('线路2')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('live-play-line-item-1')));
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live-play-line-item-1')), findsNothing);
      expect(_in('live-play-line', find.text('线路2')), findsOneWidget);
      expect(room.engine.opens.last.toString(), contains('b.example'));
      await _close(tester, room);
    });

    testWidgets('switching: the button spins and takes no taps; the old stream keeps playing', (tester) async {
      final site = _GatedSite(liveRoom());
      final room = await _pump(tester, site: site);
      final opened = room.engine.opens.length;
      await tester.tap(find.byKey(const ValueKey('live-play-quality')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('live-play-quality-item-1')));
      await _settle(tester);
      // The spinner turns for ever: no settling from here.
      expect(_in('live-play-quality', find.byKey(const ValueKey('stream-menu-busy'))), findsOneWidget);
      expect(room.engine.opens, hasLength(opened), reason: 'nothing reopened yet');
      await tester.tap(find.byKey(const ValueKey('live-play-quality')));
      await tester.tap(find.byKey(const ValueKey('live-play-line')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('live-play-quality-item-0')), findsNothing);
      expect(find.byKey(const ValueKey('live-play-line-item-0')), findsNothing);

      site.gate.complete();
      await _settle(tester);
      expect(find.byKey(const ValueKey('stream-menu-busy')), findsNothing);
      expect(_in('live-play-quality', find.text('超清')), findsOneWidget);
      await _close(tester, room);
    });

    testWidgets('fullscreen: the same two buttons and menus, above the buttons; no "原画 · 线路1"', (tester) async {
      final room = await _pump(tester, width: 852, height: 393);
      await tester.tap(find.byKey(const ValueKey('live-play-fullscreen')));
      await _settle(tester);
      final bar = find.byKey(const ValueKey('live-play-bottom-bar'));
      expect(find.descendant(of: bar, matching: find.byKey(const ValueKey('live-play-quality'))), findsOneWidget);
      expect(find.descendant(of: bar, matching: find.byKey(const ValueKey('live-play-line'))), findsOneWidget);
      expect(find.textContaining('原画 · 线路'), findsNothing);

      final button = tester.getRect(find.byKey(const ValueKey('live-play-quality')));
      await tester.tap(find.byKey(const ValueKey('live-play-quality')));
      await tester.pumpAndSettle();
      final last = tester.getRect(find.byKey(const ValueKey('live-play-quality-item-2')));
      expect(last.bottom, lessThanOrEqualTo(button.top), reason: 'above the button, where it fits');
      expect(_in('live-play-quality-item-0', find.byIcon(AppIcons.selected)), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live-play-quality-item-0')), findsNothing, reason: 'Esc closes it');
      expect(find.byKey(const ValueKey('live-play-bottom-bar')), findsOneWidget, reason: 'still in fullscreen');

      await tester.tap(find.byKey(const ValueKey('live-play-line')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live-play-line-item-1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('live-play-line-item-1')));
      await _settle(tester);
      await tester.pumpAndSettle();
      expect(_in('live-play-line', find.text('线路2')), findsOneWidget);
      await _close(tester, room);
    });
  });

  testWidgets('desktop keys: arrows move in the menu, Enter picks, as in every Material menu', (tester) async {
    final room = await _pump(tester, width: 1280, height: 800);
    await tester.tap(find.byKey(const ValueKey('live-play-line')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-play-line-item-0')), findsNothing);
    expect(_in('live-play-line', find.text('线路2')), findsOneWidget);
    await _close(tester, room);
  });

  group('record panel', () {
    final now = DateTime(2026, 10, 1, 21, 30);

    Future<AppRecording> panel(
      WidgetTester tester, {
      List<RecordTask> tasks = const [],
      void Function(AppRecording recording)? prepare,
    }) async {
      tester.view
        ..physicalSize = const Size(400, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final (services, recording, folder) = (await tester.runAsync(() async {
        final services = await testServices();
        final folder = await Directory.systemTemp.createTemp('pure_live_u2f_');
        return (services, await _recording(services, folder, tasks: tasks, prepare: prepare), folder);
      }))!;
      addTearDown(
        () => tester.runAsync(() async {
          await recording.dispose();
          await services.close();
          await folder.delete(recursive: true);
        }),
      );
      await tester.runAsync(loadStrings);
      final previous = AppNavigator.toast;
      AppNavigator.toast = (_) {};
      addTearDown(() => AppNavigator.toast = previous);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appServicesProvider.overrideWithValue(services),
            recordingProvider.overrideWithValue(recording),
            recorderProvider.overrideWithValue(recording.recorder),
          ],
          child: MaterialApp(
            theme: const LiveTheme().light,
            home: Scaffold(
              body: RoomRecordPanel(
                room: () => LiveRoom(platform: 'bilibili', roomId: '6', nick: '主播'),
                qualities: () => const [
                  LivePlayQuality(quality: '原画', id: 10000),
                  LivePlayQuality(quality: '蓝光', id: 400),
                  LivePlayQuality(quality: '超清', id: 250),
                ],
                onClose: () {},
                now: () => now,
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      return recording;
    }

    void expectCard(String state, List<String> buttons, {List<String> absent = const []}) {
      expect(find.byKey(ValueKey('record-card-$state')), findsOneWidget, reason: state);
      for (final key in buttons) {
        expect(_in('record-card-$state', find.byKey(ValueKey(key))), findsOneWidget, reason: '$state: $key');
      }
      for (final key in absent) {
        expect(find.byKey(ValueKey(key)), findsNothing, reason: '$state has no $key');
      }
    }

    testWidgets('not recording: "开始录制"; the room\'s qualities with the default chosen; the header links', (
      tester,
    ) async {
      await panel(tester);
      expect(find.text('录制'), findsOneWidget);
      expect(find.byKey(const ValueKey('record-panel-centre')), findsOneWidget);
      expect(find.byKey(const ValueKey('room-panel-close')), findsOneWidget);
      expectCard('idle', ['record-panel-start'], absent: ['record-panel-stop']);
      expect(find.text('没在录制'), findsOneWidget);
      // The settings' 原画 picks the room's 原画; the chips are the room's.
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('record-quality-原画'))).selected, isTrue);
      expect(find.byKey(const ValueKey('record-quality-蓝光')), findsOneWidget);
      expect(find.text('默认值在录制设置里改'), findsOneWidget);
      expect(tester.widget<Switch>(find.byKey(const ValueKey('record-panel-auto'))).value, isFalse);
      expect(find.byKey(const ValueKey('record-panel-settings')), findsOneWidget);
      expect(find.byKey(const ValueKey('record-panel-polling')), findsNothing);
    });

    testWidgets('recording: the clock, size, rate, quality, segment and "停止录制"; this recording is read-only', (
      tester,
    ) async {
      await panel(
        tester,
        tasks: [_task(RecordStatus.stopped)],
        prepare: (recording) {
          final task = recording.recorder!.tasks.single
            ..status = RecordStatus.running
            ..recordingStartedAt = now.subtract(const Duration(minutes: 12, seconds: 34))
            ..recordedSeconds = 754
            ..fileSize = 356 * 1024 * 1024
            ..bitrate = 3200
            ..selectedQuality = '原画';
          recording.recorder!.setTaskOptions(task, autoRecord: true);
        },
      );
      expectCard('recording', ['record-panel-stop'], absent: ['record-panel-start']);
      expect(find.text('00:12:34'), findsOneWidget);
      expect(find.text('已录 356 MB'), findsOneWidget);
      expect(find.text('3.2 Mbps'), findsOneWidget);
      expect(find.text('第 3 段 · 每 5 分钟一段'), findsOneWidget);
      final clock = tester.widget<Text>(find.byKey(const ValueKey('record-panel-clock')));
      expect(clock.style?.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(find.text('原画（录制中不能改）'), findsOneWidget);
      expect(find.byKey(const ValueKey('record-panel-qualities')), findsNothing);
      expect(tester.widget<Switch>(find.byKey(const ValueKey('record-panel-danmaku'))).onChanged, isNull);
      expect(tester.widget<Switch>(find.byKey(const ValueKey('record-panel-auto'))).value, isTrue);
    });

    testWidgets('waiting for the stream: "现在就录"; the choices still apply to it', (tester) async {
      final recording = await panel(
        tester,
        tasks: [_task(RecordStatus.stopped)],
        prepare: (recording) => recording.recorder!.tasks.single.status = RecordStatus.waitingLive,
      );
      expectCard('waiting', ['record-panel-start-now']);
      expect(find.text('等待开播'), findsOneWidget);
      expect(tester.widget<Switch>(find.byKey(const ValueKey('record-panel-auto'))).value, isTrue);
      // R4: the live check is off by default, so the room would never start.
      expect(find.byKey(const ValueKey('record-panel-polling-off')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('record-quality-蓝光')));
      await _refresh(tester);
      expect(recording.recorder!.tasks.single.qualityOverride, '蓝光');
      expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('record-quality-蓝光'))).selected, isTrue);
    });

    testWidgets('queued, preparing, reconnecting and joining: their own words and buttons', (tester) async {
      final other = RecordTask.fromJson({
        ..._task(RecordStatus.stopped).toJson(),
        'taskId': 'bilibili_7',
        'roomId': '7',
      });
      final recording = await panel(
        tester,
        tasks: [_task(RecordStatus.stopped), other],
        prepare: (recording) {
          final tasks = recording.recorder!.tasks;
          tasks.last.status = RecordStatus.running;
          tasks.first.status = RecordStatus.queued;
        },
      );
      // 3 slots, 1 used: a queued task only waits for the start gap.
      expectCard('preparing', ['record-panel-cancel']);
      await tester.runAsync(() => recording.settings.set(Settings.recordMaxTaskCount, 1));
      await _refresh(tester);
      expectCard('queued', ['record-panel-cancel', 'record-panel-limit']);
      expect(find.text('同时最多录 1 个，现在正在录 1 个；有空位就自动开始。'), findsOneWidget);

      final task = recording.recorder!.tasks.first
        ..status = RecordStatus.reconnecting
        ..retryCount = 2
        ..recordedSeconds = 754
        ..fileSize = 356 * 1024 * 1024
        ..nextRetryAt = now.add(const Duration(seconds: 28));
      recording.recorder!.setTaskOptions(task);
      await _refresh(tester);
      expectCard('reconnecting', ['record-panel-stop']);
      expect(find.text('第 2 次，共 5 次'), findsOneWidget);
      expect(find.text('28 秒后重试。已录的 00:12:34 · 356 MB 不会丢。'), findsOneWidget);

      task.status = RecordStatus.processing;
      recording.recorder!.setTaskOptions(task);
      await _refresh(tester);
      expectCard('processing', [], absent: ['record-panel-stop', 'record-panel-start']);
      expect(find.text('把 3 段合成一个 MP4，完成后就能播放。可以关掉这里，不影响整理。'), findsOneWidget);
    });

    testWidgets('saved: duration, size, quality; play, the recording centre, record again', (tester) async {
      final file = File('${Directory.systemTemp.path}/pure_live_u2f_saved.mp4')..writeAsStringSync('mp4');
      addTearDown(file.deleteSync);
      await panel(
        tester,
        tasks: [
          _task(RecordStatus.completed)
            ..recordedSeconds = 2112
            ..fileSize = 1288490189
            ..selectedQuality = '原画'
            ..lastUpdate = now
            ..lastOutputPath = file.path,
        ],
      );
      expectCard('saved', ['record-panel-play', 'record-panel-view', 'record-panel-again']);
      expect(find.text('今天 21:30'), findsOneWidget);
      expect(find.text('时长 00:35:12 · 1.2 GB · 原画'), findsOneWidget);
      expect(tester.widget<Switch>(find.byKey(const ValueKey('record-panel-auto'))).value, isFalse);
    });

    testWidgets('failed: where and why; the reason in full and a retry', (tester) async {
      await panel(
        tester,
        tasks: [
          _task(RecordStatus.failed)
            ..lastErrorStage = 'stream'
            ..lastError = 'timeout'
            ..retryCount = 5,
        ],
      );
      expectCard('failed', ['record-panel-reason', 'record-panel-retry']);
      expect(find.textContaining('最近失败（线路解析）：timeout（第 5 次，已不再重试）'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('record-panel-reason')));
      await tester.pumpAndSettle();
      expect(find.text('失败原因'), findsOneWidget);
    });

    testWidgets('开播自动录 turns the live check on with it, or offers to (F2, R4)', (tester) async {
      final recording = await panel(tester);
      final previous = AppNavigator.toast;
      final toasts = <String>[];
      AppNavigator.toast = toasts.add;
      addTearDown(() => AppNavigator.toast = previous);
      await tester.tap(find.byKey(const ValueKey('record-quality-超清')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('record-panel-auto')));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(recording.settings.current.enablePolling, isTrue);
      expect(toasts, contains('已打开开播检测（每 30 秒检查一次）'));
      final task = recording.recorder!.tasks.single;
      expect(task.status, RecordStatus.waitingLive);
      expect(task.autoRecord, isTrue);
      expect(task.qualityOverride, '超清', reason: "this recording's choice goes with the task");
      expectCard('waiting', ['record-panel-start-now']);
      expect(find.text('每 30 秒检查一次是否开播'), findsOneWidget);

      // The user switches the live check off in the settings later.
      await tester.runAsync(() => recording.settings.set(Settings.recordEnablePolling, false));
      await _refresh(tester);
      expect(find.text('“开播检测”关着，到时不会自动开始。'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('record-panel-polling-on')));
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(recording.settings.current.enablePolling, isTrue);
      expect(find.byKey(const ValueKey('record-panel-polling-off')), findsNothing);

      // Off: 3.x's "取消监控" for a waiting task.
      await tester.tap(find.byKey(const ValueKey('record-panel-auto')));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(recording.recorder!.tasks, isEmpty);
      expectCard('idle', ['record-panel-start']);

      // The recorder's 2 s write-behind timer is a fake one when the last
      // change landed on a pump, but a real one when an earlier change in
      // runAsync armed it less than 2 s of wall time ago; flutter_test checks
      // fake timers before the tear-downs run, so end the recorder here.
      await tester.runAsync(recording.recorder!.dispose);
    });
  });

  group('panels in the room', () {
    testWidgets('portrait: under the picture, all the height below it; Back and ✕ close it; the picture stays', (
      tester,
    ) async {
      final room = await _pump(tester, withRecorder: true);
      final video = tester.getRect(find.byKey(const ValueKey('live-play-video-box')));
      await tester.tap(find.byKey(const ValueKey('live-play-record')));
      await tester.pumpAndSettle();
      final panel = find.byKey(const ValueKey('live-play-record-panel'));
      expect(panel, findsOneWidget);
      expect(tester.getRect(panel).top, moreOrLessEquals(video.bottom));
      expect(tester.getRect(panel).bottom, 900);
      expect(find.byType(ModalBarrier), findsNWidgets(1), reason: "only the route's own barrier, no dimming");
      // Back closes the panel first and stays in the room.
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(find.byType(RoomPlayer), findsOneWidget);

      // The danmaku settings take the same place; a tap on the picture
      // shows or hides the controls and leaves the panel open (F1).
      await tester.tap(find.byKey(const ValueKey('live-play-danmaku-settings')));
      await tester.pumpAndSettle();
      final settings = find.byKey(const ValueKey('live-play-danmaku-panel'));
      expect(tester.getRect(settings).top, moreOrLessEquals(video.bottom));
      expect(_in('live-play-danmaku-panel', find.text('改动立即生效')), findsOneWidget);
      await tester.tapAt(video.center);
      await tester.pumpAndSettle();
      expect(settings, findsOneWidget);
      // A pull down on the header closes it.
      await tester.drag(find.byKey(const ValueKey('room-panel-drag')), const Offset(0, 200));
      await tester.pumpAndSettle();
      expect(settings, findsNothing);
      await _close(tester, room);
    });

    testWidgets('fullscreen: on the right, 360 wide and the full height, never over the left half', (tester) async {
      final room = await _pump(
        tester,
        width: 852,
        height: 393,
        withRecorder: true,
        tasks: [_task(RecordStatus.stopped)],
        prepare: (recording) => recording.recorder!.tasks.single
          ..status = RecordStatus.running
          ..recordingStartedAt = DateTime.now(),
      );
      await tester.tap(find.byKey(const ValueKey('live-play-fullscreen')));
      await _settle(tester);
      // The "● 录制中" mark opens the record panel.
      await tester.tap(find.byKey(const ValueKey('live-play-recording-mark')));
      await tester.pumpAndSettle();
      final panel = tester.getRect(find.byKey(const ValueKey('live-play-record-panel')));
      expect(panel.width, 360);
      expect(panel.left, greaterThanOrEqualTo(852 / 2));
      expect(panel.top, 0);
      expect(panel.bottom, 393);
      await tester.tap(find.byKey(const ValueKey('room-panel-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('live-play-danmaku-settings')));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const ValueKey('live-play-danmaku-panel'))), panel);
      // Back closes the panel before leaving fullscreen.
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live-play-danmaku-panel')), findsNothing);
      expect(find.byKey(const ValueKey('live-play-back')), findsOneWidget, reason: 'still fullscreen');
      await _close(tester, room);
    });

    testWidgets('wide window: over the chat column', (tester) async {
      final room = await _pump(tester, width: 1280, height: 800, withRecorder: true);
      final chat = tester.getRect(find.byKey(const ValueKey('live-play-tabs')));
      await tester.tap(find.byKey(const ValueKey('live-play-record')));
      await tester.pumpAndSettle();
      final panel = tester.getRect(find.byKey(const ValueKey('live-play-record-panel')));
      expect(panel.width, 360);
      expect(panel.right, 1280);
      expect(panel.overlaps(chat), isTrue);
      expect(panel.left, greaterThan(1280 / 2));
      await _close(tester, room);
    });
  });

  testWidgets('danmaku settings: every 3.x setting in the confirmed groups; dependent ones grey out', (tester) async {
    final room = await _pump(tester, height: 4200);
    await tester.tap(find.byKey(const ValueKey('live-play-danmaku-settings')));
    await tester.pumpAndSettle();
    final panel = find.byKey(const ValueKey('live-play-danmaku-panel'));
    expect(_in('live-play-danmaku-panel', find.text('弹幕设置')), findsOneWidget);
    // 3.x `DanmakuSettingsContent` (pages/danmaku_settings_page.dart:195-420),
    // item by item, in the groups of U.2f.
    const groups = ['观看模板', '显示范围', '样式', '重复弹幕', '画面弹幕交互', '流畅度'];
    final titles = [for (final group in groups) find.descendant(of: panel, matching: find.text(group))];
    for (final title in titles) {
      expect(title, findsOneWidget);
    }
    final tops = [for (final title in titles) tester.getTopLeft(title).dy];
    expect(tops, [...tops]..sort(), reason: 'in this order');
    final title = tester.widget<Text>(titles.first);
    expect(title.style?.fontSize, 13);
    expect(title.style?.color, Theme.of(tester.element(panel)).colorScheme.primary);
    for (final key in ['danmaku_template_best', 'danmaku_template_comfort', 'danmaku_template_dense', 'reset']) {
      expect(find.byKey(ValueKey('danmaku-template-$key')), findsOneWidget, reason: key);
    }
    expect(find.text('顶部 20% · 均衡'), findsOneWidget);
    expect(find.byKey(const ValueKey('danmaku-template-save')), findsOneWidget);
    expect(find.text('把当前设置存为我的模板'), findsOneWidget);
    expect(find.text('用我的模板'), findsOneWidget);
    const items = {
      'area': '画面顶部占用高度',
      'top': '顶部留白（像素）',
      'bottom': '区域底部留白（像素）',
      'opacity': '透明度',
      'speed': '滚动速度（像素/秒）',
      'fontSize': '字体大小',
      'fontWeight': '字体粗细',
      'stroke': '弹幕描边',
      'strokeWidth': '描边宽度',
      'noEmoji': '纯文字模式（隐藏表情）',
      'collapse': '合并短时间内的相同弹幕',
      'repeatWindow': '相同内容合并时间（秒）',
      'tap': '点击画面弹幕查看操作',
      'longPress': '长按画面弹幕打开屏蔽操作',
      'autoFps': '弹幕帧率跟随界面刷新率',
      'fps': '弹幕帧率',
    };
    for (final MapEntry(:key, :value) in items.entries) {
      expect(_in('danmaku-setting-$key', find.text(value)), findsOneWidget, reason: key);
    }
    // 3.x's ranges.
    final speed = tester.widget<Slider>(find.byKey(const ValueKey('danmaku-slider-speed')));
    expect((speed.min, speed.max), (20, 400));
    final size = tester.widget<Slider>(find.byKey(const ValueKey('danmaku-slider-fontSize')));
    expect((size.min, size.max), (10, 30));
    expect(
      tester.widget<Slider>(find.byKey(const ValueKey('danmaku-slider-fps'))).onChanged,
      isNull,
      reason: 'follows the display: greyed, with the rate in use',
    );
    expect(_in('danmaku-setting-fps', find.text('60 FPS')), findsOneWidget);

    // D4: the stroke width greys out (stays) while the stroke is off.
    expect(tester.widget<Slider>(find.byKey(const ValueKey('danmaku-slider-strokeWidth'))).onChanged, isNotNull);
    await tester.tap(find.byKey(const ValueKey('danmaku-switch-stroke')));
    await _settle(tester);
    expect(room.services.store.settings.get(Settings.enableDanmakuStroke), isFalse);
    expect(find.byKey(const ValueKey('danmaku-setting-strokeWidth')), findsOneWidget);
    expect(tester.widget<Slider>(find.byKey(const ValueKey('danmaku-slider-strokeWidth'))).onChanged, isNull);
    // D5: the merge window greys out while merging is off (the default).
    expect(
      tester
          .widget<IgnorePointer>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('danmaku-setting-repeatWindow')),
                  matching: find.byType(IgnorePointer),
                )
                .first,
          )
          .ignoring,
      isTrue,
    );

    // D2: the line under the templates follows the chosen one.
    await tester.tap(find.byKey(const ValueKey('danmaku-template-danmaku_template_comfort')));
    await _settle(tester);
    expect(room.services.store.settings.get(Settings.danmakuArea), 0.35);
    expect(
      tester.widget<ChoiceChip>(find.byKey(const ValueKey('danmaku-template-danmaku_template_comfort'))).selected,
      isTrue,
    );
    expect(find.text('弹幕占画面顶部约 35%，字稍大、速度稍慢，看着更轻松。'), findsOneWidget);
    await _close(tester, room);
  });

  testWidgets('room menu: three groups in order with 3.x\'s icons; "在<平台>打开"', (tester) async {
    final room = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('live-play-menu')));
    await tester.pumpAndSettle();
    expect(
      _column(tester, [
        'room-menu-switchRoom',
        'room-menu-timer',
        'room-menu-volume',
        'room-menu-videoFit',
        'room-menu-divider-1',
        'room-menu-cast',
        'room-menu-streamLink',
        'room-menu-share',
        'room-menu-external',
        'room-menu-newWindow',
        'room-menu-divider-2',
        'room-menu-localInteraction',
      ]),
      [
        'room-menu-switchRoom',
        'room-menu-timer',
        'room-menu-volume',
        'room-menu-videoFit',
        'room-menu-divider-1',
        'room-menu-cast',
        'room-menu-streamLink',
        'room-menu-share',
        'room-menu-external',
        // U.2k: the third group, the local interaction (on by default).
        'room-menu-divider-2',
        'room-menu-localInteraction',
      ],
    );
    const icons = {
      'switchRoom': AppIcons.switchRoom,
      'timer': AppIcons.sleepTimer,
      'volume': AppIcons.roomVolume,
      'videoFit': AppIcons.aspectRatio,
      'cast': AppIcons.cast,
      'streamLink': AppIcons.streamLink,
      'share': AppIcons.share,
      'external': AppIcons.openExternal,
    };
    for (final MapEntry(:key, :value) in icons.entries) {
      expect(_in('room-menu-$key', find.byIcon(value)), findsOneWidget, reason: key);
    }
    expect(_in('room-menu-external', find.text('在哔哩哔哩打开')), findsOneWidget);
    expect(find.text('打开直播间'), findsNothing);
    // Windows adds "在新窗口打开" at the end of the second group; the local
    // interaction is the third group only while it is on (U.2k).
    expect(roomMenuGroups(iptv: false, windows: true)[1].last, RoomMenuEntry.newWindow);
    expect(roomMenuGroups(iptv: false, windows: false)[2], isEmpty);
    expect(roomMenuGroups(iptv: false, windows: false, local: true)[2], [RoomMenuEntry.localInteraction]);
    expect(roomMenuGroups(iptv: true, windows: false)[1], [RoomMenuEntry.cast, RoomMenuEntry.streamLink]);
    await _close(tester, room);
  });

  testWidgets('long press on a message: the message in a card; copy, block the viewer, block a word (filled in)', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final room = await _pump(tester);
    room.danmaku.chat('剧透警告', user: '路人');
    await tester.pump();
    await tester.longPress(find.byKey(const ValueKey('live-play-chat-line')).last);
    await tester.pumpAndSettle();
    final sheet = find.byKey(const ValueKey('live-play-message-sheet'));
    expect(find.descendant(of: sheet, matching: find.text('弹幕')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-play-message-close')), findsOneWidget);
    expect(_in('live-play-message-card', find.textContaining('路人：剧透警告', findRichText: true)), findsOneWidget);
    expect(_column(tester, ['live-play-copy-message', 'live-play-block-user', 'live-play-block-keyword']), [
      'live-play-copy-message',
      'live-play-block-user',
      'live-play-block-keyword',
    ]);
    expect(_in('live-play-block-user', find.text('屏蔽此用户')), findsOneWidget);
    expect(_in('live-play-block-user', find.text('路人 的弹幕都不再显示')), findsOneWidget);
    expect(_in('live-play-block-keyword', find.text('屏蔽关键词…')), findsOneWidget);
    expect(_in('live-play-block-keyword', find.text('输入一个词，含这个词的弹幕都不再显示')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('live-play-copy-message')));
    await tester.pumpAndSettle();
    expect(copied, '路人: 剧透警告');

    await tester.longPress(find.byKey(const ValueKey('live-play-chat-line')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('live-play-block-keyword')));
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(find.byKey(const ValueKey('live-play-keyword-input')));
    expect(input.controller?.text, '剧透警告', reason: 'filled with the message, to cut down to the word');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await _close(tester, room);
  });

  group('record state', () {
    RecordTask task(RecordStatus status, {bool? autoRecord, int seconds = 0}) => _task(status)
      ..autoRecord = autoRecord
      ..recordedSeconds = seconds;

    test('the card follows the nine states; a queue without a full house is only the start gap', () {
      expect(recordCardState(null), RecordCardState.idle);
      expect(recordCardState(task(RecordStatus.stopped)), RecordCardState.idle);
      expect(recordCardState(task(RecordStatus.stopped, seconds: 5)), RecordCardState.saved);
      expect(recordCardState(task(RecordStatus.completed)), RecordCardState.saved);
      expect(recordCardState(task(RecordStatus.waitingLive)), RecordCardState.waiting);
      expect(recordCardState(task(RecordStatus.queued), running: 1, capacity: 3), RecordCardState.preparing);
      expect(recordCardState(task(RecordStatus.queued), running: 3, capacity: 3), RecordCardState.queued);
      expect(recordCardState(task(RecordStatus.reconnecting)), RecordCardState.reconnecting);
      expect(recordCardState(task(RecordStatus.failed)), RecordCardState.failed);
    });

    test('开播自动录 is on while the task waits for the room or will afterwards', () {
      expect(autoRecordOn(null), isFalse);
      expect(autoRecordOn(task(RecordStatus.waitingLive)), isTrue);
      expect(autoRecordOn(task(RecordStatus.running)), isTrue, reason: '3.x: a task is a monitor');
      expect(autoRecordOn(task(RecordStatus.running, autoRecord: false)), isFalse);
      expect(autoRecordOn(task(RecordStatus.stopped, autoRecord: true)), isFalse);
      expect(autoRecordOn(task(RecordStatus.failed)), isFalse);
      expect(recordBusy(task(RecordStatus.queued)), isTrue);
      expect(recordBusy(task(RecordStatus.waitingLive)), isFalse);
    });

    test('qualities, figures and the danmaku frame rate in use', () {
      expect(recordQualityChoices(const []), recordQualityPreferences);
      expect(
        recordQualityChoices(const [LivePlayQuality(quality: '原画', id: 1), LivePlayQuality(quality: '流畅', id: 2)]),
        ['原画', '流畅'],
      );
      expect(recordDefaultQuality(const [], '超清'), '超清');
      expect(recordSegmentNumber(754, 300), 3);
      expect(recordSegmentCount(754, 300), 3);
      expect(recordClockText(const Duration(minutes: 12, seconds: 34)), '00:12:34');
      expect(recordShortSize(356 * 1024 * 1024), '356 MB');
      expect(recordShortSize(1288490189), '1.2 GB');
      expect(groupedNumber(1284), '1,284');
      expect(resolvedDanmakuFps(automatic: false, configured: 90, mode: 'balanced'), 90);
      expect(resolvedDanmakuFps(automatic: true, configured: 90, mode: 'balanced', maxRefreshRate: 120), 60);
      expect(resolvedDanmakuFps(automatic: true, configured: 90, mode: 'performance', maxRefreshRate: 120), 120);
      expect(recordSlotsInUse([task(RecordStatus.running), task(RecordStatus.reconnecting)]), 1);
    });
  });
}
