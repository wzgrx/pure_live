// A05.1 c1 (docs/A-界面设计/A05-无障碍/A05.1-无障碍检查): the app on an Android
// phone, light and dark, against Flutter's accessibility guidelines (48 × 48
// to tap, a label on everything tappable, WCAG AA text contrast): the home
// tabs, the pages a phone opens most, the settings pages and the live room
// (portrait, a portrait stream, fullscreen) with its panels. A failure names
// the code that built the node.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_player/live_player.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

import 'accessibility.dart';
import 'features/live_play/live_play_support.dart';
import 'support.dart';

LiveRoom _room(int n, {LiveStatus status = LiveStatus.live}) => LiveRoom(
  platform: SiteIds.bilibili,
  roomId: '$n',
  title: '房间标题 $n',
  nick: '主播 $n',
  area: '英雄联盟',
  popularity: '${n * 1000}',
  audienceMetricType: AudienceMetricType.popularity,
  liveStatus: status,
);

/// Bilibili with rooms, areas and search results; its room plays.
final class _Site extends FakeSite {
  new() : super(liveRoom(startedAt: DateTime.now().subtract(const Duration(minutes: 30))));

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async =>
      page == 1 ? [for (var i = 1; i <= 6; i++) _room(i)] : const [];

  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async => [
    LiveCategory(
      id: '1',
      name: '网游',
      children: [
        for (var i = 1; i <= 6; i++)
          LiveArea(platform: SiteIds.bilibili, areaType: '1', typeName: '网游', areaId: '$i', areaName: '分区 $i'),
      ],
    ),
  ];

  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async =>
      page == 1 ? [for (var i = 1; i <= 4; i++) _room(i)] : const [];

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async =>
      page == 1 ? [for (var i = 1; i <= 4; i++) _room(i)] : const [];
}

final class _NoFfmpeg implements FfmpegRunner {
  @override
  Future<FfmpegExecution> start(List<String> arguments) => throw UnsupportedError('no FFmpeg in tests');
}

/// The whole app in [mode] ("Light" or "Dark") with follows, history, tags
/// and a recording task; [height] tall so a page's whole list is on screen.
Future<FakeEngine> _pumpApp(WidgetTester tester, String mode, {double height = 852}) async {
  tester.view
    ..physicalSize = Size(393, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final site = _Site();
  final engine = FakeEngine();
  final (services, recording, folder) = (await tester.runAsync(() async {
    final base = await testServices();
    final store = base.store;
    await store.settings.set(Settings.showSplashPage, false);
    await store.settings.set(Settings.themeMode, mode);
    await store.settings.set(Settings.language, '简体中文');
    await store.settings.set(Settings.hotAreasList, [SiteIds.bilibili]);
    await store.settings.set(Settings.savedMenuIds, ['favorites', 'popular', 'areas', 'record']);
    for (var i = 1; i <= 4; i++) {
      await store.follows.add(_room(i, status: i.isEven ? LiveStatus.offline : LiveStatus.live));
      await store.history.record(_room(i + 10));
    }
    await store.tags.add('常看');
    await store.tags.add('游戏', description: '说明');
    final services = AppServices(
      store: store,
      cipher: base.cipher,
      http: base.http,
      proxy: base.proxy,
      cookies: base.cookies,
      sites: SiteRegistry({
        for (final id in base.sites.ids) id: () => id == SiteIds.bilibili ? site : base.sites.of(id),
      }),
      danmaku: DanmakuRegistry({SiteIds.bilibili: FakeDanmaku.new}),
      launch: base.launch,
      dataRoot: base.dataRoot,
      followsReady: base.followsReady,
      mediaOpener: base.mediaOpener,
    );
    final folder = await Directory.systemTemp.createTemp('pure_live_a05_');
    final recording = buildAppRecording(
      store: store,
      sites: services.sites,
      proxy: services.proxy,
      dataRoot: folder,
      ffmpeg: _NoFfmpeg(),
    );
    await recording.loadSettings();
    final task = RecordTask(
      taskId: 'bilibili_9',
      roomId: '9',
      platform: SiteIds.bilibili,
      title: '房间 9',
      nick: '主播 9',
      avatar: '',
      cover: '',
      watching: '847000',
      audienceMetricType: AudienceMetricType.popularity,
      createTime: DateTime(2026, 10, 2),
      status: RecordStatus.stopped,
    );
    await recording.recorder!.restore(jsonEncode([task.toJson()]));
    return (services, recording, folder);
  }))!;
  final strings = (await tester.runAsync(loadStrings))!;
  final previous = AppNavigator.toast;
  AppNavigator.toast = (_) {};
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  addTearDown(() async {
    // The room puts the system bars back after it closes (a 3 s timer).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(seconds: 5));
    AppNavigator.toast = previous;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
    await tester.runAsync(() async {
      await recording.dispose();
      await services.close();
      await folder.delete(recursive: true);
    });
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        recordingProvider.overrideWithValue(recording),
        recorderProvider.overrideWithValue(recording.recorder),
        playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(engine)),
      ],
      // The recording dot and the loading marks hold still.
      child: MediaQuery(
        data: MediaQueryData(size: Size(393, height), disableAnimations: true),
        child: PureLiveApp(strings: strings, bundle: FileAssetBundle()),
      ),
    ),
  );
  await _settle(tester);
  return engine;
}

/// Lets the store and the fake platform answer, then the frames.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _open(WidgetTester tester, String path, {Object? arguments}) async {
  // ignore: unawaited_futures, the page stays until [_back]
  AppNavigator.toNamed<void>(path, arguments: arguments);
  await _settle(tester);
}

Future<void> _back(WidgetTester tester) async {
  AppNavigator.back<void>();
  await _settle(tester);
}

/// Shows the room's controls (a tap on the picture at [at]).
Future<void> _controls(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Taps the room's button [key], first bringing the controls with a tap
/// at [at] when they are hidden.
Future<void> _press(WidgetTester tester, String key, Offset at) async {
  final button = find.byKey(ValueKey(key)).hitTestable();
  if (button.evaluate().isEmpty) await _controls(tester, at);
  await tester.tap(button.first);
  await _settle(tester);
}

Future<void> _check(WidgetTester tester, String screen) =>
    expectAccessible(tester, screen, known: knownAccessibilityFailures);

void main() {
  for (final mode in ['Light', 'Dark']) {
    testWidgets('$mode: the home tabs and the pages a phone opens', (tester) async {
      // Tall, so each page's whole list is checked without scrolling.
      await _pumpApp(tester, mode, height: 2000);
      await _check(tester, 'home: follows');
      for (final tab in ['热门', '分区', '录制中心']) {
        await tester.tap(find.widgetWithText(NavigationDestination, tab).last);
        await _settle(tester);
        await _check(tester, 'home: $tab');
      }
      for (final path in [
        RoutePath.kSearch,
        RoutePath.kHistory,
        RoutePath.kSettingsTags,
        RoutePath.kToolbox,
        RoutePath.kFavoriteAreas,
        RoutePath.kSettings,
        RoutePath.kRecordSettings,
        RoutePath.kDanmakuSettings,
        RoutePath.kSettingsDanmuShield,
        RoutePath.kSettingsHotAreas,
        RoutePath.kSettingsAccount,
        RoutePath.kBackup,
        RoutePath.kRemoteSync,
        RoutePath.kLogs,
        RoutePath.kWebDavPage,
        RoutePath.kIptv,
        RoutePath.kLocalInteraction,
        RoutePath.kAbout,
        RoutePath.kVersionPage,
        RoutePath.kVersionHistory,
      ]) {
        await _open(tester, path);
        await _check(tester, path);
        await _back(tester);
      }
      for (final section in SettingsSection.values) {
        if (section.route != null) continue;
        await _open(tester, RoutePath.kSettings, arguments: section.name);
        await _check(tester, 'settings: ${section.name}');
        await _back(tester);
      }
    });

    testWidgets('$mode: the room in portrait, a portrait stream and fullscreen, with its panels', (tester) async {
      final engine = await _pumpApp(tester, mode);
      // ignore: unawaited_futures, the room stays open
      AppNavigator.toLiveRoomDetail(liveRoom: _room(6));
      await _settle(tester);
      await _check(tester, 'room');
      await _controls(tester, const Offset(196, 150));
      await _check(tester, 'room: controls');
      for (final key in [
        'live-play-quality',
        'live-play-line',
        'live-play-menu',
        'live-play-danmaku-settings',
        'live-play-record',
        'live-play-info',
      ]) {
        await _press(tester, key, const Offset(196, 150));
        await _check(tester, 'room: $key');
        await tester.binding.handlePopRoute();
        await _settle(tester);
      }

      engine.emit(const EngineVideoSize(720, 1280));
      await _settle(tester);
      await _check(tester, 'room: portrait stream');
      await _controls(tester, const Offset(196, 200));
      await _check(tester, 'room: portrait stream, controls');

      engine.emit(const EngineVideoSize(1280, 720));
      await _settle(tester);
      await _press(tester, 'live-play-fullscreen', const Offset(196, 150));
      tester.view.physicalSize = const Size(852, 393);
      await _settle(tester);
      await _check(tester, 'room: fullscreen');
      await _controls(tester, const Offset(426, 196));
      await _check(tester, 'room: fullscreen, controls');
      for (final key in ['live-play-menu', 'live-play-switch-room']) {
        await _press(tester, key, const Offset(426, 196));
        await _check(tester, 'room: fullscreen, $key');
        await tester.binding.handlePopRoute();
        await _settle(tester);
      }
    });
  }
}
