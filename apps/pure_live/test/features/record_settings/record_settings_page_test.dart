import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/record_settings/record_settings_dialogs.dart';
import 'package:pure_live/features/record_settings/record_settings_page.dart';
import 'package:pure_live/features/record_settings/record_settings_texts.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/record/record_actions.dart';

import '../../support.dart';

// U.7b (docs/ui/compare/U.7b): the recording settings page, its dialogs and
// the "改上限" entry.

/// FFmpeg is never started by these tests.
final class _NoFfmpeg implements FfmpegRunner {
  @override
  Future<FfmpegExecution> start(List<String> arguments) => throw UnsupportedError('no FFmpeg in tests');
}

final class _Harness {
  new(this.services, this.recording, this.folder, this.toasts);

  final AppServices services;
  final AppRecording recording;
  final Directory folder;
  final List<String> toasts;

  RecordSettings get settings => recording.settings.current;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  Map<String, Object?> legacy = const {},
  Future<String?> Function()? picker,
  Object? arguments,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = (await tester.runAsync(() async {
    final services = await testServices();
    final folder = await Directory.systemTemp.createTemp('pure_live_record_settings_');
    await services.store.meta.keepLegacyValues(legacy);
    final recording = buildAppRecording(
      store: services.store,
      sites: services.sites,
      proxy: services.proxy,
      dataRoot: folder,
      ffmpeg: _NoFfmpeg(),
    );
    await recording.loadSettings();
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
          home: RecordSettingsPage(route: RouteArgs(RoutePath.kRecordSettings, arguments: arguments)),
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
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 50));
    if (i >= 3 && find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(finder);
  await _settle(tester);
}

double _top(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dy;

/// The row widget of the settings row titled [title].
Finder _row(String title) => find.ancestor(of: find.text(title), matching: find.byType(SettingsRow)).first;

/// Whether the row titled [title] is greyed out (U.7b c4).
bool _greyed(WidgetTester tester, String title) => find
    .ancestor(of: find.text(title), matching: find.byWidgetPredicate((w) => w is Opacity && w.opacity < 1))
    .evaluate()
    .isNotEmpty;

void main() {
  test('words: units in words, sizes, what a value means', () async {
    await loadStrings();
    expect(recordDurationLabel(15), '15 秒');
    expect(recordDurationLabel(300), '5 分钟');
    expect(recordDurationLabel(330), '5.5 分钟');
    expect(recordDurationLabel(3600), '1 小时');
    expect(recordTimesLabel(5), '5 次');
    expect(recordSpaceLabel(3.5 * 1024 * 1024 * 1024), '3.5 GB');
    expect(recordSpaceLabel(1024 * 1024 * 12.34), '12.3 MB');
    expect(recordSpaceLabel(0), '0 B');
    expect(recordTimeoutMeaning(15), '响应迅速 (推荐，适合稳定网络)');
    expect(recordTimeoutMeaning(60), '保守模式 (适合极端弱网环境)');
    expect(recordQueueMeaning(2048), '原画推荐 (1080P)');
    expect(recordQueueMeaning(8192), '极致性能 (适用于 4K 录制/高负载环境)');
  });

  testWidgets('phone: five groups, every row of 3.x in order, values on the right with their meaning', (tester) async {
    tester.view
      ..physicalSize = const Size(393, 3600)
      ..devicePixelRatio = 1;
    await _pump(tester, size: const Size(393, 3600));
    expect(find.text('录制设置'), findsOneWidget);
    final groups = ['基础配置', '录制文件', '录制性能与画质', '自动重连', '开播检测'];
    final rows = [
      '默认录制清晰度',
      '使用拼音文件夹名',
      '同时录制弹幕',
      'Pure Live 录制文件目录',
      '限制录制文件总大小',
      '总大小上限',
      '已占用',
      '清空录制文件目录',
      '优先录制原画轨道',
      '录制读写超时',
      '输入缓冲队列',
      '视频切片时长',
      '最大同时录制任务数',
      '自动断线重连',
      '最大重试次数',
      '重连间隔时间',
      '启用开播检测',
      '检测间隔时间',
      '启用指数退避',
      '最大检测间隔',
      '应用启动时恢复待录任务',
    ];
    for (final (i, title) in rows.indexed) {
      expect(find.text(title), findsOneWidget, reason: title);
      if (i > 0) expect(_top(tester, title), greaterThan(_top(tester, rows[i - 1])), reason: title);
    }
    for (final (i, title) in groups.indexed) {
      if (i > 0) expect(_top(tester, title), greaterThan(_top(tester, groups[i - 1])));
    }
    expect(_top(tester, '录制文件'), lessThan(_top(tester, 'Pure Live 录制文件目录')));
    expect(_top(tester, '开播检测'), lessThan(_top(tester, '启用开播检测')));
    // 3.x's names are gone (V1).
    expect(find.text('缓存管理'), findsNothing);
    expect(find.text('挂机轮询检测'), findsNothing);

    // Icons stay 3.x's (c1).
    for (final (title, icon) in [
      ('默认录制清晰度', AppIcons.recordQuality),
      ('使用拼音文件夹名', AppIcons.recordPinyin),
      ('同时录制弹幕', AppIcons.recordDanmaku),
      ('Pure Live 录制文件目录', AppIcons.recordFolder),
      ('限制录制文件总大小', AppIcons.recordSizeLimit),
      ('总大小上限', AppIcons.recordSizeCap),
      ('已占用', AppIcons.recordUsedSpace),
      ('清空录制文件目录', AppIcons.recordClear),
      ('优先录制原画轨道', AppIcons.recordBestStream),
      ('录制读写超时', AppIcons.recordTimeout),
      ('输入缓冲队列', AppIcons.recordQueue),
      ('视频切片时长', AppIcons.recordSegment),
      ('最大同时录制任务数', AppIcons.recordMaxTasks),
      ('自动断线重连', AppIcons.recordReconnect),
      ('最大重试次数', AppIcons.recordRetries),
      ('启用开播检测', AppIcons.recordPolling),
      ('启用指数退避', AppIcons.recordBackoff),
      ('最大检测间隔', AppIcons.recordMaxInterval),
      ('应用启动时恢复待录任务', AppIcons.recordResume),
    ]) {
      expect(
        find.descendant(of: _row(title), matching: find.byIcon(icon)),
        findsOneWidget,
        reason: title,
      );
    }

    // Values on the right, the meaning under the title (c5, c6).
    expect(find.descendant(of: _row('默认录制清晰度'), matching: find.text('原画')), findsOneWidget);
    expect(find.descendant(of: _row('录制读写超时'), matching: find.text('15 秒')), findsOneWidget);
    expect(find.descendant(of: _row('录制读写超时'), matching: find.text('响应迅速 (推荐，适合稳定网络)')), findsOneWidget);
    expect(find.descendant(of: _row('输入缓冲队列'), matching: find.text('2048')), findsOneWidget);
    expect(find.descendant(of: _row('输入缓冲队列'), matching: find.text('原画推荐 (1080P)')), findsOneWidget);
    expect(
      tester.getCenter(find.text('15 秒')).dx,
      greaterThan(tester.getCenter(find.text('录制读写超时')).dx),
      reason: 'the value sits right of the title',
    );
    expect(find.text('5 分钟'), findsNWidgets(2), reason: 'segment and the longest check interval');
    expect(find.text('5 次'), findsOneWidget);
    expect(find.text('30 秒'), findsNWidgets(2), reason: 'reconnect and check intervals');
    expect(find.text('1024 MB'), findsOneWidget);
    expect(find.text('超过的任务排队，有空位自动开始（1～10）'), findsOneWidget);

    // Rows that depend on a switch grey out instead of disappearing (c4).
    expect(_greyed(tester, '总大小上限'), isTrue);
    expect(_greyed(tester, '检测间隔时间'), isTrue);
    expect(_greyed(tester, '启用指数退避'), isTrue);
    expect(_greyed(tester, '最大检测间隔'), isTrue);
    expect(_greyed(tester, '最大重试次数'), isFalse, reason: 'reconnecting is on by default');
    expect(_greyed(tester, '重连间隔时间'), isFalse);

    // Explanations wrap in full (c3).
    final danmaku = tester.widget<Text>(find.descendant(of: _row('同时录制弹幕'), matching: find.byType(Text)).at(1));
    expect(danmaku.maxLines, isNull);

    // "打开文件夹" sits at the end of the folder row (c10), not by the group title.
    final folderRow = tester.getRect(_row('Pure Live 录制文件目录'));
    final open = tester.getRect(find.byKey(const ValueKey('record-open-folder')));
    expect(folderRow.contains(open.center), isTrue);
    expect(open.right, greaterThan(folderRow.right - 64));
    expect(find.byTooltip('打开文件夹'), findsOneWidget);
    expect(find.text('打开文件夹'), findsNothing, reason: 'an icon, named on hover');
  });

  testWidgets("3.x's stored values show as they were; switching a parent on brings its rows back", (tester) async {
    tester.view.physicalSize = const Size(393, 3600);
    final harness = await _pump(
      tester,
      size: const Size(393, 3600),
      legacy: {'segmentTime': 330, 'maxTaskCount': 5, 'recorder_rw_timeout': 30},
    );
    expect(find.text('5.5 分钟'), findsOneWidget, reason: 'a 3.x value between minutes keeps its half (c11)');
    expect(find.descendant(of: _row('最大同时录制任务数'), matching: find.text('5')), findsOneWidget);
    expect(find.text('30 秒'), findsNWidgets(3));
    expect(find.text('平衡模式 (兼顾稳定与重连速度)'), findsOneWidget);

    await _tap(tester, find.text('启用开播检测'));
    expect(harness.settings.enablePolling, isTrue);
    expect(_greyed(tester, '检测间隔时间'), isFalse);
    expect(_greyed(tester, '启用指数退避'), isFalse);
    expect(_greyed(tester, '最大检测间隔'), isTrue, reason: 'back-off is still off');
    await _tap(tester, find.text('启用指数退避'));
    expect(_greyed(tester, '最大检测间隔'), isFalse);

    await _tap(tester, find.text('自动断线重连'));
    expect(harness.settings.autoReconnect, isFalse);
    expect(_greyed(tester, '最大重试次数'), isTrue);
    expect(_greyed(tester, '重连间隔时间'), isTrue, reason: '3.x left this one active although it did nothing');
  });

  testWidgets('the most recordings at once: − and + on the row, 1 to 10, saved at once (c9)', (tester) async {
    final harness = await _pump(tester);
    final plus = find.byKey(const ValueKey('record-max-tasks-increase'));
    final minus = find.byKey(const ValueKey('record-max-tasks-decrease'));
    await tester.ensureVisible(plus);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byIcon(AppIcons.decrease), findsOneWidget);
    expect(find.byIcon(AppIcons.increase), findsOneWidget);
    expect(tester.getCenter(minus).dx, lessThan(tester.getCenter(plus).dx));
    await _tap(tester, plus);
    expect(harness.settings.maxTaskCount, 4);
    expect(harness.services.store.settings.get(Settings.recordMaxTaskCount), 4);
    await _tap(tester, minus);
    await _tap(tester, minus);
    await _tap(tester, minus);
    expect(harness.settings.maxTaskCount, 1);
    expect(tester.widget<IconButton>(minus).onPressed, isNull, reason: 'one is the least');
    await tester.runAsync(() => harness.recording.settings.set(Settings.recordMaxTaskCount, 10));
    await _settle(tester);
    expect(tester.widget<IconButton>(plus).onPressed, isNull, reason: 'ten is the most');
  });

  testWidgets('"改上限" opens the page at the row and highlights it for two seconds', (tester) async {
    await _pump(tester, arguments: recordSettingsMaxTasks);
    final row = find.byKey(const ValueKey('record-max-tasks'));
    final rect = tester.getRect(row);
    expect(rect.top, greaterThan(0));
    expect(rect.bottom, lessThan(852), reason: 'scrolled into view');
    Decoration? frame() => tester
        .widget<AnimatedContainer>(find.ancestor(of: row, matching: find.byType(AnimatedContainer)).first)
        .foregroundDecoration;
    expect((frame()! as BoxDecoration).border, isNotNull);
    await tester.pump(recordLimitHighlight);
    await tester.pump(const Duration(milliseconds: 300));
    expect((frame()! as BoxDecoration).border, isNull);
  });

  testWidgets('choice dialogs: the current one in the primary colour with a tick, a tap saves and closes (c13)', (
    tester,
  ) async {
    final harness = await _pump(tester);
    await _tap(tester, find.text('录制读写超时'));
    expect(find.byType(Radio<int>), findsNothing);
    expect(find.text('15 秒'), findsNWidgets(2));
    final current = find.byKey(const ValueKey('record-option-15'));
    expect(find.descendant(of: current, matching: find.byIcon(AppIcons.selected)), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('record-option-30')), matching: find.byIcon(AppIcons.selected)),
      findsNothing,
    );
    final description = tester.widget<Text>(find.descendant(of: current, matching: find.text('响应迅速 (推荐，适合稳定网络)')));
    expect(description.style?.fontSize, 14);
    await _tap(tester, find.byKey(const ValueKey('record-option-60')));
    expect(harness.settings.rwTimeout, 60);
    expect(find.byKey(const ValueKey('record-option-60')), findsNothing, reason: 'closed');
    expect(find.text('60 秒'), findsOneWidget);
    expect(find.text('保守模式 (适合极端弱网环境)'), findsOneWidget);

    await _tap(tester, find.text('默认录制清晰度'));
    for (final quality in recordQualityPreferences) {
      expect(find.byKey(ValueKey('record-option-$quality')), findsOneWidget);
    }
    await _tap(tester, find.byKey(const ValueKey('record-option-超清')));
    expect(harness.settings.defaultQuality, '超清');
  });

  testWidgets('the size cap: greyed until the limit is on; its dialog explains and checks the number', (tester) async {
    final harness = await _pump(tester);
    await _tap(tester, find.text('总大小上限'));
    expect(find.byKey(const ValueKey('record-cache-limit-input')), findsNothing, reason: 'greyed out');
    await _tap(tester, find.text('限制录制文件总大小'));
    expect(harness.settings.enableCacheLimit, isTrue);
    await _tap(tester, find.text('总大小上限'));
    expect(find.text('录制文件总大小上限 (MB)'), findsOneWidget);
    expect(find.text('超过时自动删除最早的录像。正在录的文件不会被删。'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('record-cache-limit-input')), '0');
    await tester.pump();
    expect(find.text('请输入大于零的整数'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('record-cache-limit-input')), '2048');
    await _tap(tester, find.byKey(const ValueKey('record-cache-limit-confirm')));
    expect(harness.settings.maxCacheMB, 2048);
    expect(find.text('2048 MB'), findsOneWidget);
  });

  testWidgets('emptying the folder says how much goes and that it cannot come back (c8)', (tester) async {
    final harness = await _pump(tester);
    await _tap(tester, find.text('清空录制文件目录'));
    expect(find.text('清空录制文件目录？'), findsOneWidget);
    expect(find.textContaining('将删除 0 B 录像，不能恢复'), findsOneWidget);
    // The destructive button of the one dialog (U.1d c6): red.
    final button = tester.widget<DialogActionButton>(find.byKey(const ValueKey('record-clear-confirm')));
    expect(button.danger, isTrue);
    final surface = find.descendant(
      of: find.byKey(const ValueKey('record-clear-confirm')),
      matching: find.byType(Material),
    );
    final colors = Theme.of(tester.element(find.text('清空录制文件目录？'))).colorScheme;
    expect(tester.widget<Material>(surface.first).color, colors.error);
    expect(find.text('清空'), findsOneWidget);
    await _tap(tester, find.text('取消'));
    expect(harness.toasts, isEmpty);
    await _tap(tester, find.text('清空录制文件目录'));
    await _tap(tester, find.byKey(const ValueKey('record-clear-confirm')));
    expect(harness.toasts, ['录制文件已清空']);
  });

  testWidgets('the folder row opens the system picker and saves the folder; one that cannot be written says so', (
    tester,
  ) async {
    late String picked;
    final harness = await _pump(tester, picker: () async => picked);
    picked = harness.folder.path;
    await _tap(tester, find.text('Pure Live 录制文件目录'));
    expect(find.byKey(const ValueKey('record-directory-input')), findsNothing, reason: 'no dialog: the picker (3.x)');
    expect(harness.settings.savePath, picked);
    expect(find.text('$picked/PureLiveRecords'), findsOneWidget);
    expect(File('$picked/PureLiveRecords/${RecordStorage.ownershipMarkerName}').existsSync(), isTrue);

    final file = File('${harness.folder.path}/not_a_folder');
    await tester.runAsync(() => file.writeAsString('x'));
    picked = file.path;
    await _tap(tester, find.text('Pure Live 录制文件目录'));
    expect(harness.toasts.last, '这个文件夹不能写入（不存在、有非法字符或没有存储权限），请换一个');
    expect(harness.settings.savePath, harness.folder.path, reason: 'unchanged');
  });

  testWidgets('without a system picker the folder dialog takes a typed path or the default', (tester) async {
    final harness = await _pump(tester);
    await _tap(tester, find.text('Pure Live 录制文件目录'));
    expect(find.byKey(const ValueKey('record-directory-default')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('record-directory-input')), harness.folder.path);
    // The main button says what it does (U.1d; not "确认").
    expect(
      find.descendant(of: find.byKey(const ValueKey('record-directory-confirm')), matching: find.text('保存')),
      findsOneWidget,
    );
    await _tap(tester, find.byKey(const ValueKey('record-directory-confirm')));
    expect(harness.settings.savePath, harness.folder.path);
  });

  testWidgets('landscape phone: one column at most 720 wide, centred; the short window gets a 48 bar', (tester) async {
    await _pump(tester, size: const Size(852, 393));
    final card = tester.getRect(_row('默认录制清晰度'));
    expect(card.width, lessThanOrEqualTo(720));
    expect((card.left - (852 - card.right)).abs(), lessThan(1), reason: 'centred');
    expect(tester.getSize(find.byType(AppBar)).height, 48);
  });

  testWidgets('wide: one column 720 wide, centred, the title at the start (3.x)', (tester) async {
    await _pump(tester, size: const Size(1280, 800));
    final card = tester.getRect(_row('默认录制清晰度'));
    expect(card.width, 720);
    expect((card.left - (1280 - card.right)).abs(), lessThan(1));
    expect(tester.getSize(find.byType(AppBar)).height, kToolbarHeight);
    // 3.x's main.dart replaced the centred app bar theme: the start on Android.
    expect(tester.getTopLeft(find.text('录制设置')).dx, lessThan(80));
  });
}
