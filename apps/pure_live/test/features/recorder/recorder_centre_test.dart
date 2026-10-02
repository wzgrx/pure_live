// The recording centre (docs/ui/compare/U.7a, confirmed): the bar, the five
// filters with counts, the cards with the live room's status card in its
// compact size, the menu, deleting, the live check's warning, the empty
// states and the columns of each form.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/home/menu_button.dart';
import 'package:pure_live/features/recorder/logic/recorder_view.dart';
import 'package:pure_live/features/recorder/recorder_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/record/record_state.dart';

import '../../support.dart';

/// FFmpeg is never started by these tests.
final class _NoFfmpeg implements FfmpegRunner {
  @override
  Future<FfmpegExecution> start(List<String> arguments) => throw UnsupportedError('no FFmpeg in tests');
}

final DateTime _now = DateTime(2026, 10, 1, 21, 30);

const int _gb = 1024 * 1024 * 1024;

RecordTask _task(String id, {RecordStatus status = RecordStatus.stopped, int minutesAgo = 0}) => RecordTask(
  taskId: 'bilibili_$id',
  roomId: id,
  platform: 'bilibili',
  title: '房间 $id',
  nick: '主播 $id',
  avatar: '',
  cover: '',
  watching: '847000',
  audienceMetricType: AudienceMetricType.popularity,
  createTime: _now.subtract(Duration(minutes: minutesAgo)),
  status: status,
);

/// The nine states of the design, set the way a running recorder would
/// after the restore (which stops what was recording): recording,
/// reconnecting, joining, preparing, queued (three slots taken), waiting,
/// failed, saved (with gaps) and not recording.
void _nineStates(AppRecording recording, String file) {
  RecordTask task(String id) => recording.recorder!.tasks.firstWhere((task) => task.roomId == id);
  task('r')
    ..status = RecordStatus.running
    ..recordingStartedAt = _now.subtract(const Duration(minutes: 12, seconds: 34))
    ..recordedSeconds = 754
    ..fileSize = 356 * 1024 * 1024
    ..bitrate = 3200
    ..selectedQuality = '原画';
  task('c')
    ..status = RecordStatus.reconnecting
    ..retryCount = 2
    ..nextRetryAt = _now.add(const Duration(seconds: 28))
    ..recordedSeconds = 2468
    ..fileSize = (1.1 * _gb).round();
  task('j')
    ..status = RecordStatus.processing
    ..recordedSeconds = 1200
    ..mergeProgress = 0.42
    ..autoRecord = false;
  task('p')
    ..status = RecordStatus.preparing
    ..autoRecord = false;
  task('q')
    ..status = RecordStatus.queued
    ..autoRecord = false;
  task('w')
    ..status = RecordStatus.waitingLive
    ..lastLiveCheckAt = DateTime(2026, 10, 1, 21, 35);
  task('f')
    ..status = RecordStatus.failed
    ..lastErrorStage = 'stream'
    ..lastError = 'timeout'
    ..retryCount = 5;
  task('s')
    ..status = RecordStatus.completed
    ..recordedSeconds = 3765
    ..fileSize = (2.1 * _gb).round()
    ..selectedQuality = '原画'
    ..lastUpdate = _now
    ..lastOutputPath = file
    ..inputCoverageIncomplete = true;
}

const _ids = ['r', 'c', 'j', 'p', 'q', 'w', 'f', 's', 'i'];

/// A file that is always there and notes how it was asked.
final class _ProbeFile implements File {
  new(this.path, this.calls);

  @override
  final String path;

  final List<String> calls;

  @override
  bool existsSync() {
    calls.add('existsSync');
    return true;
  }

  @override
  Future<bool> exists() async {
    calls.add('exists');
    return true;
  }

  @override
  Object? noSuchMethod(Invocation invocation) {
    calls.add('${invocation.memberName}');
    return super.noSuchMethod(invocation);
  }
}

/// What the page did outside the app.
final class _Outside {
  final toasts = <String>[];
  final opened = <Uri>[];
  final played = <String>[];
}

Future<(AppRecording, _Outside)> _pump(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  bool inHome = false,
  Object? arguments,
  List<RecordTask> tasks = const [],
  void Function(AppRecording recording)? prepare,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final (services, recording, folder) = (await tester.runAsync(() async {
    final services = await testServices();
    final folder = await Directory.systemTemp.createTemp('pure_live_u7a_');
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
    return (services, recording, folder);
  }))!;
  addTearDown(
    () => tester.runAsync(() async {
      await recording.dispose();
      await services.close();
      await folder.delete(recursive: true);
    }),
  );
  final strings = (await tester.runAsync(loadStrings))!;
  final outside = _Outside();
  final (toast, openExternal, openFile) = (AppNavigator.toast, AppNavigator.openExternal, AppNavigator.openFile);
  AppNavigator.toast = outside.toasts.add;
  AppNavigator.openExternal = (uri) async {
    outside.opened.add(uri);
    return true;
  };
  AppNavigator.openFile = (path) async {
    outside.played.add(path);
    return true;
  };
  addTearDown(() {
    AppNavigator.toast = toast;
    AppNavigator.openExternal = openExternal;
    AppNavigator.openFile = openFile;
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        recordingProvider.overrideWithValue(recording),
        recorderProvider.overrideWithValue(recording.recorder),
      ],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp(
          theme: const LiveTheme(primaryColor: Colors.blue).light,
          // The recording dot holds still, so the frames settle.
          builder: (context, child) =>
              MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!),
          home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const SizedBox()),
            onGenerateInitialRoutes: (navigator, _) => [
              MaterialPageRoute<void>(builder: (_) => const Scaffold()),
              MaterialPageRoute<void>(
                builder: (_) => RecorderPage(
                  route: RouteArgs(RoutePath.kRecordPage, arguments: arguments, inHome: inHome),
                  now: () => _now,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return (recording, outside);
}

/// Lets real async work (the store, the file system) finish, then the frames.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  await _frames(tester);
}

/// Lets the recorder's deferred write of the task list (2 s after a change)
/// run, so no timer is left when the test ends.
Future<void> _drain(WidgetTester tester) async {
  for (var i = 0; i < 2; i++) {
    await _settle(tester);
    await tester.pump(const Duration(seconds: 3));
  }
}

/// Runs the menus' and dialogs' transitions to their end. Not
/// `pumpAndSettle`: the spinners of "准备中" and "正在整理文件" never settle.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _in(String key, Finder finder) => find.descendant(of: _key(key), matching: finder);

Finder _card(String id) => _key('recorder-card-bilibili_$id');

Finder _inCard(String id, Finder finder) => find.descendant(of: _card(id), matching: finder);

/// The nine tasks, each started a minute apart.
List<RecordTask> _nine() => [for (final (index, id) in _ids.indexed) _task(id, minutesAgo: index)];

Future<(AppRecording, _Outside, File)> _pumpNine(WidgetTester tester, {Size size = const Size(393, 852)}) async {
  final file = File(p.join(Directory.systemTemp.path, 'pure_live_u7a_saved.mp4'))..writeAsStringSync('mp4');
  addTearDown(() {
    if (file.existsSync()) file.deleteSync();
  });
  final (recording, outside) = await _pump(
    tester,
    size: size,
    tasks: _nine(),
    prepare: (recording) => _nineStates(recording, file.path),
  );
  return (recording, outside, file);
}

void main() {
  testWidgets('the bar: the home tab has the menu, the folder and the settings on the right; title centred', (
    tester,
  ) async {
    await _pump(tester, inHome: true);
    final title = tester.getCenter(find.text('录制中心'));
    // As a phone tab the bar also has search and "more" (U.3a c6): four
    // buttons on the right leave no room to centre the title on 393, so the
    // toolbar moves it left of them (centred where it fits, below).
    expect(find.byType(CommonAppBarActions), findsOneWidget);
    expect(find.byType(MenuButton), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    final menu = tester.getCenter(find.byType(MenuButton));
    final folder = tester.getCenter(_key('recorder-open-folder'));
    final settings = tester.getCenter(_key('recorder-settings'));
    expect(menu.dx, lessThan(title.dx));
    expect(folder.dx, greaterThan(title.dx));
    expect(settings.dx, greaterThan(folder.dx), reason: '3.x: folder, then settings');
    expect(_in('recorder-open-folder', find.byIcon(AppIcons.recordFolder)), findsOneWidget);
    expect(_in('recorder-settings', find.byIcon(AppIcons.recordSettings)), findsOneWidget);
    expect(find.byTooltip('打开文件夹'), findsOneWidget);
    expect(find.byTooltip('录制设置'), findsOneWidget);
  });

  testWidgets('opened from a room or the rail: back instead of the menu', (tester) async {
    await _pump(tester);
    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byType(MenuButton), findsNothing);
    expect(find.byType(CommonAppBarActions), findsNothing);
    expect(tester.getCenter(find.text('录制中心')).dx, closeTo(393 / 2, 1), reason: '3.x centres the title');
  });

  testWidgets('no task at all: how to add one; the five filters count nothing', (tester) async {
    await _pump(tester);
    expect(_key('recorder-empty'), findsOneWidget);
    expect(find.text('暂无录制任务'), findsOneWidget);
    expect(find.text('在直播间点“录制”即可添加。打开“开播检测”后，等待开播的任务会在主播开播时自动开始。'), findsOneWidget);
    for (final filter in RecorderFilter.values) {
      expect(tester.widget<Text>(_key('recorder-filter-${filter.name}-label')).textSpan!.toPlainText(), endsWith(' 0'));
    }
  });

  testWidgets('phone: five filters in one row with counts; one column of cards in the confirmed order', (tester) async {
    await _pumpNine(tester, size: const Size(393, 6000));
    final labels = [
      for (final filter in RecorderFilter.values)
        tester.widget<Text>(_key('recorder-filter-${filter.name}-label')).textSpan!.toPlainText(),
    ];
    expect(labels, ['全部 9', '进行中 5', '等待开播 1', '已保存 1', '失败 1']);
    final chips = [for (final filter in RecorderFilter.values) tester.getRect(_key('recorder-filter-${filter.name}'))];
    for (var index = 1; index < chips.length; index++) {
      expect(chips[index].top, chips[0].top, reason: 'one row');
      expect(chips[index].left, greaterThan(chips[index - 1].right));
    }
    expect(chips.first.height, kMinInteractiveDimension);
    expect(chips.last.right, lessThanOrEqualTo(393));
    final cards = [for (final id in _ids) tester.getRect(_card(id))];
    for (var index = 1; index < cards.length; index++) {
      expect(cards[index].top, greaterThan(cards[index - 1].bottom), reason: '${_ids[index]} after ${_ids[index - 1]}');
      expect(cards[index].left, cards[0].left, reason: 'one column');
    }
    expect(cards.first.width, 393 - 32);
    expect(tester.getSize(_in('recorder-card-bilibili_r', _key('recorder-card-cover'))), const Size(96, 54));
  });

  testWidgets('each card: the head, then the status card of the live room in its compact size', (tester) async {
    await _pumpNine(tester, size: const Size(393, 6000));
    // The head: nick with "自动录", title, platform and audience, "⋮".
    expect(_inCard('r', _key('recorder-card-nick')), findsOneWidget);
    expect(_inCard('r', find.text('主播 r')), findsOneWidget);
    expect(_inCard('r', _key('recorder-card-auto')), findsOneWidget);
    expect(_inCard('r', find.text('房间 r')), findsOneWidget);
    expect(_inCard('r', find.text('哔哩哔哩 · 热度 84.7万')), findsOneWidget);
    expect(_inCard('j', _key('recorder-card-auto')), findsNothing, reason: 'records once');
    expect(_inCard('w', _key('recorder-card-auto')), findsOneWidget);
    final more = tester.getRect(_inCard('r', find.byIcon(AppIcons.more)));
    expect(more.left, greaterThan(tester.getRect(_inCard('r', _key('recorder-card-nick'))).right));
    expect(_inCard('r', find.byTooltip('更多')), findsOneWidget);

    // One state each, the panel's look and buttons.
    const states = {
      'r': 'recording',
      'c': 'reconnecting',
      'j': 'processing',
      'p': 'preparing',
      'q': 'queued',
      'w': 'waiting',
      'f': 'failed',
      's': 'saved',
      'i': 'idle',
    };
    for (final MapEntry(key: id, value: state) in states.entries) {
      expect(_inCard(id, _key('record-card-$state')), findsOneWidget, reason: id);
    }
    // Recording: the clock at 24 (the panel's is 36), the figures, stop.
    final clock = tester.widget<Text>(_inCard('r', _key('record-panel-clock')));
    expect(clock.data, '00:12:34');
    expect(clock.style!.fontSize, 24);
    expect(_inCard('r', find.text('第 3 段 · 每 5 分钟一段')), findsOneWidget);
    expect(_inCard('r', find.text('已录 356 MB')), findsOneWidget);
    expect(_inCard('r', find.text('3.2 Mbps')), findsOneWidget);
    expect(_inCard('r', _key('record-panel-stop')), findsOneWidget);
    // Buttons are 40 high (the panel's 48).
    final stop = find.descendant(of: _inCard('r', _key('record-panel-stop')), matching: find.byType(Material)).first;
    expect(tester.getSize(stop).height, 40);
    // 3.x's start time, FFmpeg speed, the full bar and the line are gone (c11).
    expect(_inCard('r', find.textContaining('1.0x')), findsNothing);
    expect(_inCard('r', find.byType(LinearProgressIndicator)), findsNothing);
    expect(_inCard('r', find.textContaining('线路')), findsNothing);
    // Reconnecting.
    expect(_inCard('c', find.text('第 2 次，共 5 次')), findsOneWidget);
    expect(_inCard('c', find.text('28 秒后重试。已录的 00:41:08 · 1.1 GB 不会丢。')), findsOneWidget);
    expect(_inCard('c', _key('record-panel-stop')), findsOneWidget);
    // Joining: no button, nothing to close; how far it is (F.3a).
    expect(_inCard('j', find.text('把 4 段合成一个 MP4，完成后就能播放。')), findsOneWidget);
    expect(_inCard('j', find.byType(ButtonStyleButton)), findsNothing);
    expect(_inCard('j', find.text('42%')), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(_inCard('j', _key('record-card-merge-progress'))).value, 0.42);
    // Preparing: cancel.
    expect(_inCard('p', find.text('正在获取直播流（原画）…')), findsOneWidget);
    expect(_inCard('p', _key('record-panel-cancel')), findsOneWidget);
    // Queued (3 of 3): cancel and the limit; no "启动", which did nothing (P4).
    expect(_inCard('q', find.text('同时最多录 3 个，现在正在录 3 个；有空位就自动开始。')), findsOneWidget);
    final cancel = tester.getRect(_inCard('q', _key('record-panel-cancel')));
    final limit = tester.getRect(_inCard('q', _key('record-panel-limit')));
    expect(cancel.top, limit.top);
    expect(cancel.left, lessThan(limit.left));
    expect(_inCard('q', find.text('启动')), findsNothing);
    // Waiting, the live check off: the yellow line instead of the panel's sentence.
    expect(_inCard('w', _key('record-card-polling-off')), findsOneWidget);
    expect(_inCard('w', find.text('主播开播时自动开始录。现在想录也可以直接开始。')), findsNothing);
    expect(_inCard('w', _key('record-panel-start-now')), findsOneWidget);
    // Failed: the reason, then retry.
    expect(_inCard('f', find.text('最近失败（线路解析）：timeout（第 5 次，已不再重试）')), findsOneWidget);
    final reason = tester.getRect(_inCard('f', _key('record-panel-reason')));
    final retry = tester.getRect(_inCard('f', _key('record-panel-retry')));
    expect(reason.top, retry.top);
    expect(reason.left, lessThan(retry.left));
    // Saved: when, how long and big; play, the folder, again in one row (U3 A);
    // 3.x's warning about gaps.
    expect(_inCard('s', find.text('今天 21:30')), findsOneWidget);
    expect(_inCard('s', find.text('时长 01:02:45 · 2.1 GB · 原画')), findsOneWidget);
    final saved = [
      for (final key in ['record-panel-play', 'record-card-folder', 'record-panel-again'])
        tester.getRect(_inCard('s', _key(key))),
    ];
    expect(saved.map((rect) => rect.top).toSet(), hasLength(1), reason: 'one row');
    expect(saved[0].left, lessThan(saved[1].left));
    expect(saved[1].left, lessThan(saved[2].left));
    expect(_inCard('s', _key('record-panel-view')), findsNothing, reason: 'the centre is here already');
    expect(_inCard('s', _key('record-card-gaps')), findsOneWidget);
    expect(_inCard('s', find.textContaining('录制中已跳过缺失或过期的直播片段')), findsOneWidget);
    // Not recording: no sentence, just "开始录制".
    expect(_inCard('i', find.text('没在录制')), findsOneWidget);
    expect(_inCard('i', find.text('开始后一直录到主播下播，或你点“停止录制”。')), findsNothing);
    expect(_inCard('i', _key('record-panel-start')), findsOneWidget);
  });

  // docs/ui/compare/U.2a2 c9: the card heads draw the room bar's glyph.
  testWidgets("U.2a2: each card head draws the room bar's glyph; red only while recording", (tester) async {
    await _pumpNine(tester, size: const Size(393, 6000));
    RecordGlyphPainter painterIn(Finder glyph) =>
        tester.widget<CustomPaint>(find.descendant(of: glyph, matching: find.byType(CustomPaint))).painter!
            as RecordGlyphPainter;
    const glyphs = {
      'r': 'recording',
      'c': 'reconnecting',
      'j': 'processing',
      'p': 'preparing',
      'q': 'waiting',
      'w': 'waiting',
      'f': 'failed',
      'i': 'idle',
    };
    for (final MapEntry(key: id, value: state) in glyphs.entries) {
      final glyph = _inCard(id, _key('record-glyph-$state'));
      expect(glyph, findsOneWidget, reason: id);
      expect(painterIn(glyph).colors.contains(LiveSemanticColors.recording), state == 'recording', reason: id);
    }
    // Queued and reconnecting take the card's amber; the others its grey.
    expect(painterIn(_inCard('q', _key('record-glyph-waiting'))).ink, LiveSemanticColors.warningLight);
    expect(painterIn(_inCard('c', _key('record-glyph-reconnecting'))).warning, LiveSemanticColors.warningLight);
    final grey = painterIn(_inCard('w', _key('record-glyph-waiting'))).ink;
    expect(grey, isNot(LiveSemanticColors.warningLight));
    expect(painterIn(_inCard('i', _key('record-glyph-idle'))).ink, grey);
    // The join draws how far it is (42 %, as the bar under it).
    expect(painterIn(_inCard('j', _key('record-glyph-processing'))).progress, 0.42);
    // Saved keeps its green tick.
    expect(_inCard('s', find.byIcon(AppIcons.recordSaved)), findsOneWidget);
    expect(_inCard('s', find.byType(RecordGlyph)), findsNothing);
  });

  testWidgets('saved: play opens the file, the folder its own folder; the reason in full', (tester) async {
    final (_, outside, file) = await _pumpNine(tester, size: const Size(393, 6000));
    await tester.tap(_inCard('s', _key('record-panel-play')));
    await _settle(tester);
    expect(outside.played, [file.path]);
    await tester.tap(_inCard('s', _key('record-card-folder')));
    await _settle(tester);
    expect(outside.opened.single.toFilePath(), '${p.dirname(file.path)}/');
    await tester.tap(_inCard('f', _key('record-panel-reason')));
    await _frames(tester);
    expect(find.text('失败原因'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('B09 c6: "播放" asks the disk in the background, never synchronously', (tester) async {
    // B08 c3's rule for the room's record panel, for the centre's cards
    // (each build called File.existsSync on the UI thread).
    final missing = p.join(Directory.systemTemp.path, 'pure_live_b09_not_there.mp4');
    final (recording, _) = await _pump(
      tester,
      size: const Size(393, 2000),
      tasks: [_task('s', status: RecordStatus.completed)],
      prepare: (recording) => recording.recorder!.tasks.single
        ..recordedSeconds = 2112
        ..lastUpdate = _now
        ..lastOutputPath = missing,
    );
    expect(_inCard('s', _key('record-panel-play')), findsNothing);
    // The last real look ends first (real disk work ends only outside the
    // fake clock).
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    final calls = <String>[];
    await IOOverrides.runZoned(() async {
      final task = recording.recorder!.tasks.single..recordedSeconds = 2113;
      recording.recorder!.setTaskOptions(task);
      // The change arrives, the card builds and looks, the answer builds it again.
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
    }, createFile: (path) => _ProbeFile(path, calls));
    expect(calls, contains('exists'));
    expect(calls, isNot(contains('existsSync')), reason: 'the UI thread does not wait for the disk');
    expect(_inCard('s', _key('record-panel-play')), findsOneWidget);
    await _drain(tester);
  });

  testWidgets('filters show their tasks only; an empty one names itself', (tester) async {
    await _pumpNine(tester, size: const Size(393, 6000));
    await tester.tap(_key('recorder-filter-active'));
    await _settle(tester);
    for (final id in _ids) {
      expect(_card(id), ['r', 'c', 'j', 'p', 'q'].contains(id) ? findsOneWidget : findsNothing, reason: id);
    }
    await tester.tap(_key('recorder-filter-saved'));
    await _settle(tester);
    expect(_card('s'), findsOneWidget);
    expect(_card('i'), findsNothing, reason: '"没在录制" is only under 全部');
    await tester.tap(_key('recorder-filter-failed'));
    await _settle(tester);
    expect(_card('f'), findsOneWidget);
  });

  testWidgets('an empty filter says "没有“失败”的任务"', (tester) async {
    await _pump(tester, tasks: [_task('i')]);
    await tester.tap(_key('recorder-filter-failed'));
    await _settle(tester);
    expect(_key('recorder-empty-filter'), findsOneWidget);
    expect(find.text('没有“失败”的任务'), findsOneWidget);
    expect(find.text('暂无录制任务'), findsNothing);
  });

  testWidgets('the live check off: a warning on top with "打开"; on, the waiting card says when it checks', (
    tester,
  ) async {
    final (recording, outside, _) = await _pumpNine(tester, size: const Size(393, 6000));
    expect(_key('recorder-polling-off'), findsOneWidget);
    expect(find.text('“开播检测”关着，等待开播的任务到时不会自动开始。'), findsOneWidget);
    expect(tester.getRect(_key('recorder-polling-off')).bottom, lessThan(tester.getRect(_card('r')).top));
    await tester.tap(_key('recorder-filter-saved'));
    await _settle(tester);
    expect(_key('recorder-polling-off'), findsNothing, reason: 'no waiting task here');
    await tester.tap(_key('recorder-filter-waiting'));
    await _settle(tester);
    expect(_key('recorder-polling-off'), findsOneWidget);
    await tester.tap(_key('recorder-polling-on'));
    await _settle(tester);
    expect(recording.settings.current.enablePolling, isTrue);
    expect(outside.toasts, contains('已打开开播检测（每 30 秒检查一次）'));
    expect(_key('recorder-polling-off'), findsNothing);
    expect(_inCard('w', find.text('每 30 秒检查一次是否开播 · 上次检查 21:35')), findsOneWidget);
    await _drain(tester);
  });

  testWidgets('"⋮", a long press and a right click open the same menu; 开播自动录 there is the panel\'s', (tester) async {
    final (recording, _, _) = await _pumpNine(tester, size: const Size(393, 6000));
    Future<void> expectMenu() async {
      await _frames(tester);
      final entries = [
        for (final key in ['open', 'auto', 'delete']) tester.getRect(_key('recorder-menu-$key')),
      ];
      expect(entries[0].top, lessThan(entries[1].top));
      expect(entries[1].top, lessThan(entries[2].top));
      expect(find.text('进入直播间'), findsOneWidget);
      expect(find.text('开播自动录'), findsOneWidget);
      expect(find.text('删除任务'), findsOneWidget);
      expect(_in('recorder-menu-open', find.byIcon(AppIcons.enterRoom)), findsOneWidget);
      expect(_in('recorder-menu-auto', find.byIcon(AppIcons.autoRecord)), findsOneWidget);
      expect(_in('recorder-menu-delete', find.byIcon(AppIcons.delete)), findsOneWidget);
      expect(find.byType(PopupMenuDivider), findsOneWidget);
    }

    await tester.tap(_inCard('s', find.byIcon(AppIcons.more)));
    await expectMenu();
    final more = tester.getRect(_inCard('s', find.byIcon(AppIcons.more)));
    expect(tester.getRect(_key('recorder-menu-open')).top, greaterThan(more.top), reason: 'under the button');
    expect(tester.widget<Switch>(_key('recorder-menu-auto-switch')).value, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _frames(tester);
    expect(_key('recorder-menu-open'), findsNothing);

    // Appendix A 14: a long press or a right click is the card's menu.
    await tester.longPress(_inCard('s', find.text('房间 s')));
    await expectMenu();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _frames(tester);
    await tester.tap(_inCard('s', find.text('房间 s')), buttons: kSecondaryMouseButton, kind: PointerDeviceKind.mouse);
    await expectMenu();

    // On for a saved task: it waits for the room again, the live check on.
    await tester.tap(_key('recorder-menu-auto'));
    await _settle(tester);
    final saved = recording.recorder!.tasks.firstWhere((task) => task.roomId == 's');
    expect(saved.status, RecordStatus.waitingLive);
    expect(recording.settings.current.enablePolling, isTrue);
    expect(_inCard('s', _key('record-card-waiting')), findsOneWidget);
    expect(_inCard('s', _key('recorder-card-auto')), findsOneWidget);

    // Off again for a task that only waits: 3.x's "取消监控" (as in the panel).
    await tester.tap(_inCard('s', find.byIcon(AppIcons.more)));
    await _frames(tester);
    expect(tester.widget<Switch>(_key('recorder-menu-auto-switch')).value, isTrue);
    await tester.tap(_key('recorder-menu-auto'));
    await _settle(tester);
    expect(recording.recorder!.tasks.where((task) => task.roomId == 's'), isEmpty);
    expect(_card('s'), findsNothing);
    await _drain(tester);
  });

  testWidgets('删除任务 asks first and says what happens to the files; then the task goes', (tester) async {
    final (recording, _, _) = await _pumpNine(tester, size: const Size(393, 6000));
    await tester.tap(_inCard('i', find.byIcon(AppIcons.more)));
    await _frames(tester);
    await tester.tap(_key('recorder-menu-delete'));
    await _frames(tester);
    expect(find.text('删除“主播 i”的录制任务？'), findsOneWidget);
    expect(find.text('正在录的会先停止并保存；已经录好的文件会留在文件夹里。只想不再自动录，可以关掉“开播自动录”。'), findsOneWidget);
    // Cancel keeps it.
    await tester.tap(_in('recorder-delete-dialog', find.text('取消')));
    await _frames(tester);
    expect(recording.recorder!.tasks, hasLength(9));

    await tester.tap(_inCard('i', find.byIcon(AppIcons.more)));
    await _frames(tester);
    await tester.tap(_key('recorder-menu-delete'));
    await _frames(tester);
    await tester.tap(_key('recorder-delete-confirm'));
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(recording.recorder!.tasks, hasLength(8));
    expect(_card('i'), findsNothing);
    expect(tester.widget<Text>(_key('recorder-filter-all-label')).textSpan!.toPlainText(), '全部 8');
    await _drain(tester);
  });

  testWidgets('a phone on its side: two columns, the small cover, back at the top left', (tester) async {
    await _pumpNine(tester, size: const Size(852, 393));
    final first = tester.getRect(_card('r'));
    final second = tester.getRect(_card('c'));
    expect(second.top, first.top, reason: 'one row');
    expect(second.left, greaterThan(first.right));
    expect(first.width, greaterThanOrEqualTo(recorderMinCardWidth));
    expect(tester.getSize(_in('recorder-card-bilibili_r', _key('recorder-card-cover'))), const Size(96, 54));
    expect(find.byType(BackButton), findsOneWidget);
    // The filters stretch over the width.
    expect(tester.getRect(_key('recorder-filter-failed')).right, greaterThan(800));
  });

  testWidgets('wide (1280 × 800): three columns, the large cover, the filters no wider than a phone', (tester) async {
    await _pumpNine(tester, size: const Size(1280, 800));
    final cards = [
      for (final id in ['r', 'c', 'j']) tester.getRect(_card(id)),
    ];
    expect(cards.map((rect) => rect.top).toSet(), hasLength(1), reason: 'one row of three');
    expect(cards[0].left, 24);
    expect(cards[2].right, 1280 - 24);
    expect(
      tester.getRect(_card('p')).top,
      greaterThan(cards.map((rect) => rect.bottom).reduce((a, b) => a > b ? a : b)),
    );
    expect(tester.getSize(_in('recorder-card-bilibili_r', _key('recorder-card-cover'))), const Size(160, 90));
    expect(tester.getRect(_key('recorder-filter-failed')).right, lessThanOrEqualTo(660));
  });

  test('the filters, the order and the columns', () {
    final tasks = [
      _task('old-saved', status: RecordStatus.completed, minutesAgo: 9)..recordedSeconds = 10,
      _task('new-saved', minutesAgo: 1)..recordedSeconds = 10,
      _task('idle'),
      _task('waiting', status: RecordStatus.waitingLive),
      _task('running', status: RecordStatus.running, minutesAgo: 5),
      _task('queued', status: RecordStatus.queued),
      _task('failed', status: RecordStatus.failed),
    ];
    final states = recorderStates(tasks, capacity: 3);
    expect(states['bilibili_queued'], RecordCardState.preparing, reason: 'a free slot: the start gap');
    expect(recorderVisible(tasks, states, RecorderFilter.all).map((task) => task.roomId), [
      'running',
      'queued',
      'waiting',
      'failed',
      'new-saved',
      'old-saved',
      'idle',
    ]);
    expect(recorderVisible(tasks, states, RecorderFilter.saved).map((task) => task.roomId), ['new-saved', 'old-saved']);
    expect(recorderCounts(states), (all: 7, active: 2, waiting: 1, saved: 2, failed: 1));
    expect(recorderColumns(393 - 32), 1);
    expect(recorderColumns(852 - 32), 2);
    expect(recorderColumns(1280 - 48), 3);
    expect(recorderColumns(1920 - 48), 4);
    expect(recorderColumns(3840 - 48), 4);
  });

  test("3.x's default folder: the finished recordings move once, sub-folders kept (release fixes, item 8)", () async {
    final temp = Directory.systemTemp.createTempSync('legacy_records_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final from = p.join(temp.path, 'app_flutter', 'PURE_LIVE', 'RECORDS');
    final to = p.join(temp.path, 'external', 'Records');
    void write(String root, String path, [String text = 'x']) =>
        (File(p.join(root, path))..createSync(recursive: true)).writeAsStringSync(text);
    write(from, 'douyu/晚风/20260901_210000.mp4', 'video');
    write(from, 'douyu/晚风/20260901_210000.xml', 'chat');
    // An attempt the import's task may still finish: its parts stay.
    write(from, 'huya/星河/20260902_010000_000001.clock-v1.ts');
    write(from, 'huya/星河/20260902_010000.clock-v1.csv');
    write(from, 'huya/星河/20260902_010000.xml');
    write(from, 'huya/星河/.20260902_010000.ffconcat');
    write(from, 'huya/星河/20260902_000000.mp4.partial');
    write(from, '.pure_live_recording_root');
    write(from, 'old.mp4', 'from 3.x');
    write(to, 'old.mp4', 'already here');
    // A file that cannot go: its folder's name is taken by a file.
    write(from, 'blocked/a.mp4');
    write(to, 'blocked');
    final store = await LiveStore.memory(cipher: FakeCipher());
    addTearDown(store.close);

    final result = await moveLegacyRecordings(meta: store.meta, from: from, to: to);
    expect(result, (moved: 3, failed: 1));
    expect(File(p.join(to, 'douyu/晚风/20260901_210000.mp4')).readAsStringSync(), 'video');
    expect(File(p.join(to, 'douyu/晚风/20260901_210000.xml')).existsSync(), isTrue);
    expect(File(p.join(to, 'old.mp4')).readAsStringSync(), 'already here');
    expect(File(p.join(to, 'old-1.mp4')).readAsStringSync(), 'from 3.x');
    expect(File(p.join(from, 'douyu/晚风/20260901_210000.mp4')).existsSync(), isFalse);
    expect(File(p.join(from, 'blocked/a.mp4')).existsSync(), isTrue, reason: 'left in place');
    for (final kept in [
      'huya/星河/20260902_010000_000001.clock-v1.ts',
      'huya/星河/20260902_010000.clock-v1.csv',
      'huya/星河/20260902_010000.xml',
      'huya/星河/.20260902_010000.ffconcat',
      'huya/星河/20260902_000000.mp4.partial',
      '.pure_live_recording_root',
    ]) {
      expect(File(p.join(from, kept)).existsSync(), isTrue, reason: kept);
    }
    expect(Directory(p.join(to, 'huya')).existsSync(), isFalse);

    write(from, 'later.mp4');
    expect(
      await moveLegacyRecordings(meta: store.meta, from: from, to: to),
      isNull,
      reason: 'once',
    );
    expect(File(p.join(from, 'later.mp4')).existsSync(), isTrue);
  });

  group('opened at a task: the "录制已停止" reminder (F02 c2)', () {
    /// Twelve tasks that are not recording, newest first: t11 is far below
    /// the first screen of a phone.
    List<RecordTask> twelve() => [for (var index = 0; index < 12; index++) _task('t$index', minutesAgo: index)];

    BoxDecoration highlight(WidgetTester tester) =>
        tester.widget<DecoratedBox>(_key('recorder-task-highlight')).decoration as BoxDecoration;

    testWidgets('a phone: the list scrolls to the task and highlights it for a moment', (tester) async {
      await _pump(tester, tasks: twelve(), arguments: 'bilibili_t11');
      final list = tester.getRect(_key('recorder-list'));
      final card = tester.getRect(_card('t11'));
      expect(card.top, greaterThanOrEqualTo(list.top));
      expect(card.bottom, lessThanOrEqualTo(list.bottom));
      expect(_card('t0'), findsNothing, reason: 'scrolled away from the top');
      expect(find.descendant(of: _key('recorder-task-highlight'), matching: _card('t11')), findsOneWidget);
      expect(highlight(tester).border!.top.color.a, 1);

      // It fades within a few seconds; the card stays where it is.
      await tester.pump(const Duration(seconds: 3));
      expect(highlight(tester).border!.top.color.a, 0);
      expect(tester.getRect(_card('t11')), card);
    });

    testWidgets('a task on the first screen is highlighted where it is', (tester) async {
      await _pump(tester, tasks: twelve(), arguments: 'bilibili_t0');
      expect(find.descendant(of: _key('recorder-task-highlight'), matching: _card('t0')), findsOneWidget);
      expect(tester.getRect(_card('t0')).top, lessThan(200));
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('wide: the row of the task comes into view', (tester) async {
      await _pump(
        tester,
        size: const Size(1280, 800),
        tasks: [...twelve(), ...twelve().map((task) => _task('w${task.roomId}', minutesAgo: 20))],
        arguments: 'bilibili_t11',
      );
      final list = tester.getRect(_key('recorder-list'));
      final card = tester.getRect(_card('t11'));
      expect(card.top, greaterThanOrEqualTo(list.top));
      expect(card.bottom, lessThanOrEqualTo(list.bottom));
      expect(_key('recorder-task-highlight'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a task the recorder brings in later (still restoring) is shown when it comes', (tester) async {
      final (recording, _) = await _pump(tester, tasks: twelve(), arguments: 'bilibili_late');
      expect(_key('recorder-task-highlight'), findsNothing);
      await tester.runAsync(() => recording.recorder!.restore(jsonEncode([_task('late', minutesAgo: 30).toJson()])));
      await _settle(tester);
      final list = tester.getRect(_key('recorder-list'));
      expect(tester.getRect(_card('late')).bottom, lessThanOrEqualTo(list.bottom));
      expect(find.descendant(of: _key('recorder-task-highlight'), matching: _card('late')), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('a task that is gone: the list stays at the top, nothing is highlighted', (tester) async {
      await _pump(tester, tasks: twelve(), arguments: 'bilibili_gone');
      expect(_card('t0'), findsOneWidget);
      expect(_key('recorder-task-highlight'), findsNothing);
    });
  });

  test('the arguments name the task', () {
    expect(recorderTaskOf('bilibili_1'), 'bilibili_1');
    expect(recorderTaskOf(' bilibili_1 '), 'bilibili_1');
    expect(recorderTaskOf(''), isNull);
    expect(recorderTaskOf(null), isNull);
    expect(recorderTaskOf(42), isNull);
  });
}
