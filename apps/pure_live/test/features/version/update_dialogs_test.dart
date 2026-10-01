import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/downloads.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/version/app_version.dart';
import 'package:pure_live/features/version/update_download.dart';
import 'package:pure_live/features/version/update_feed.dart';
import 'package:pure_live/features/version/update_prompt.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/app_prompts.dart';

import '../../support.dart';

Map<String, Object?> _versionJson() =>
    jsonDecode(File('../../assets/version.json').readAsStringSync()) as Map<String, Object?>;

final class _FakeFeed extends UpdateFeed {
  new({this.info, this.history}) : super(NoNetworkHttp(), githubOrigin: false, platform: 'android');

  UpdateInfo? info;
  List<ReleaseInfo>? history;

  @override
  Future<UpdateInfo?> latest({Duration timeout = const Duration(seconds: 10)}) async => info;

  @override
  Future<List<ReleaseInfo>?> releases({Duration timeout = const Duration(seconds: 15)}) async => history;
}

UpdateInfo _info(String version) => UpdateInfo.fromJson({
  ..._versionJson(),
  'version': version,
  'version_desc': '- 斗鱼原画不再每 5 分钟断流\n- **更快**的播放',
  'platforms': const <String, Object?>{},
}, platform: 'android');

ReleaseFile _apk(String version) => ReleaseFile(
  name: 'PureLive-$version-android-arm64-v8a-release.apk',
  size: '3mb',
  downloads: 1,
  url: 'https://github.com/wzgrx/pure_live/releases/download/v$version/PureLive-$version-android-arm64-v8a-release.apk',
);

List<ReleaseInfo> _history(String version) => [
  ReleaseInfo(version: version, date: '2027-01-01', changelog: '-', files: [_apk(version)]),
];

/// Answers every download with [body], [size] long.
final class _GatedHttp implements LiveHttp {
  new({this.size});

  final int? size;
  final StreamController<List<int>> body = StreamController();
  int opens = 0;

  @override
  Future<LiveResponse> send(LiveRequest request) async => await (await open(request)).collect();

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async {
    opens++;
    return LiveStreamedResponse(status: 200, body: body.stream, url: request.url, contentLength: size);
  }

  @override
  void close() {}
}

final class _Harness {
  new(this.services, this.toasts, this.opened, this.router);

  final AppServices services;
  final List<String> toasts;
  final List<String> opened;
  final GoRouter router;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  double width = 393,
  double height = 852,
  List<Override> overrides = const [],
  LiveRouteObserver? observer,
}) async {
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(testServices))!;
  addTearDown(() => tester.runAsync(services.close));
  final strings = (await tester.runAsync(loadStrings))!;
  final toasts = <String>[];
  final opened = <String>[];
  final previous = (AppNavigator.toast, AppNavigator.openExternal, AppNavigator.openFile);
  AppNavigator.toast = toasts.add;
  AppNavigator.openExternal = (uri) async {
    opened.add('$uri');
    return false;
  };
  AppNavigator.openFile = (path) async {
    opened.add(path);
    return false;
  };
  addTearDown(() {
    AppNavigator.toast = previous.$1;
    AppNavigator.openExternal = previous.$2;
    AppNavigator.openFile = previous.$3;
  });
  final router = GoRouter(
    observers: [?observer],
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: '/room',
        builder: (_, _) => const Scaffold(body: Text('room')),
      ),
      GoRoute(
        path: RoutePath.kVersionPage,
        builder: (_, _) => const Scaffold(body: Text('version page')),
      ),
    ],
  );
  AppNavigator.router = router;
  addTearDown(() => AppNavigator.router = null);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services), ...overrides],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp.router(
          theme: const LiveTheme(primaryColor: Colors.blue).light,
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(services, toasts, opened, router);
}

/// Lets real file and stream work run until [done] (or 50 rounds).
Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 50 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

UpdateDownloadTools _tools(LiveHttp http, Directory folder, {SettingsStore? settings, Directory? fallback}) =>
    UpdateDownloadTools(
      downloader: FileDownloader(http),
      folder: () async => folder,
      pickFastest: false,
      settings: settings,
      defaultFolder: fallback == null ? null : () async => fallback,
      pickFolder: () async => null,
    );

Directory _temp() {
  final dir = Directory.systemTemp.createTempSync('u3d_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// The text's left edge (for the order of a button row).
double _x(WidgetTester tester, String text) => tester.getCenter(find.text(text)).dx;

void main() {
  group('new version (U.3d c2–c5)', () {
    testWidgets('title, installed version, the link that keeps the dialog, notes, buttons in order', (tester) async {
      final h = await _pump(tester);
      final context = tester.element(find.text('home'));
      final feed = _FakeFeed(info: _info('9.0.0'), history: _history('9.0.0'));
      unawaited(
        checkForUpdateOnStartup(context, settings: h.services.store.settings, feed: feed, prompts: AppPrompts()),
      );
      await tester.pumpAndSettle();

      expect(find.text('发现新版本 v9.0.0'), findsOneWidget);
      expect(find.text('当前 v$appVersion'), findsOneWidget);
      expect(find.text('更新内容'), findsOneWidget);
      expect(find.textContaining('断流'), findsOneWidget);
      // 3.x's title and its link button that closed the dialog.
      expect(find.text('检查更新'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('new-version-open-project')));
      await tester.pumpAndSettle();
      expect(h.opened.single, projectUrl.toString());
      expect(find.byKey(const ValueKey('new-version-dialog')), findsOneWidget);

      // Narrow: the skip box on its own row above the buttons.
      final skip = tester.getRect(find.byKey(const ValueKey('new-version-skip')));
      final buttons = tester.getRect(find.byKey(const ValueKey('new-version-update')));
      expect(skip.bottom, lessThanOrEqualTo(buttons.top));
      expect(_x(tester, '其他下载方式'), lessThan(_x(tester, '取消')));
      expect(_x(tester, '取消'), lessThan(_x(tester, '下载并安装')));
      for (final label in ['其他下载方式', '取消', '下载并安装', '不再提醒这个版本']) {
        expect(tester.renderObject<RenderParagraph>(find.text(label)).text.style?.fontSize, 14, reason: label);
      }

      // "其他下载方式" goes to the version page.
      await tester.tap(find.text('其他下载方式'));
      await tester.pumpAndSettle();
      expect(find.text('version page'), findsOneWidget);
    });

    testWidgets('wide: the skip box at the left of the button row; Enter is the main button, Esc cancels', (
      tester,
    ) async {
      final h = await _pump(tester, width: 1280, height: 800);
      final context = tester.element(find.text('home'));
      // No package for this device: the main button is "更新" (the version page).
      final feed = _FakeFeed(info: _info('9.0.0'));
      unawaited(
        checkForUpdateOnStartup(context, settings: h.services.store.settings, feed: feed, prompts: AppPrompts()),
      );
      await tester.pumpAndSettle();
      final dialog = tester.getRect(
        find.descendant(of: find.byKey(const ValueKey('new-version-dialog')), matching: find.byType(Material)).first,
      );
      expect(dialog.width, lessThanOrEqualTo(560 + 0.5));
      final skip = tester.getCenter(find.byKey(const ValueKey('new-version-skip')));
      final update = tester.getCenter(find.byKey(const ValueKey('new-version-update')));
      expect((skip.dy - update.dy).abs(), lessThan(4));
      expect(skip.dx, lessThan(_x(tester, '取消')));
      expect(find.text('其他下载方式'), findsNothing);
      expect(find.text('更新'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('new-version-dialog')), findsNothing);

      unawaited(
        checkForUpdateOnStartup(context, settings: h.services.store.settings, feed: feed, prompts: AppPrompts()),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('version page'), findsOneWidget);
    });

    testWidgets('landscape phone: a long log scrolls on its own, the buttons stay on screen', (tester) async {
      final h = await _pump(tester, width: 852, height: 393);
      final context = tester.element(find.text('home'));
      final long = UpdateInfo.fromJson({
        ..._versionJson(),
        'version': '9.0.0',
        'version_desc': [for (var i = 0; i < 30; i++) '- 第 $i 条改动'].join('\n'),
        'platforms': const <String, Object?>{},
      }, platform: 'android');
      unawaited(
        checkForUpdateOnStartup(
          context,
          settings: h.services.store.settings,
          feed: _FakeFeed(info: long, history: _history('9.0.0')),
          prompts: AppPrompts(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final update = tester.getRect(find.byKey(const ValueKey('new-version-update')));
      expect(update.bottom, lessThanOrEqualTo(393));
      expect(find.text('发现新版本 v9.0.0'), findsOneWidget);
      final log = find.byKey(const ValueKey('new-version-log'));
      expect(tester.getRect(log).bottom, lessThanOrEqualTo(update.top));
      await tester.drag(log, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const ValueKey('new-version-update'))), update);
    });

    testWidgets('"不再提醒这个版本" silences this version only', (tester) async {
      final h = await _pump(tester);
      final context = tester.element(find.text('home'));
      final settings = h.services.store.settings;
      final feed = _FakeFeed(info: _info('9.0.0'));
      unawaited(checkForUpdateOnStartup(context, settings: settings, feed: feed, prompts: AppPrompts()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('不再提醒这个版本'));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(settings.get(Settings.skippedUpdateVersion), '9.0.0');

      await checkForUpdateOnStartup(context, settings: settings, feed: feed, prompts: AppPrompts());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('new-version-dialog')), findsNothing);

      feed.info = _info('9.0.1');
      unawaited(checkForUpdateOnStartup(context, settings: settings, feed: feed, prompts: AppPrompts()));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 v9.0.1'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    });

    testWidgets('waits while another page is on top and opens when home is back (U.3c c7, K2)', (tester) async {
      final observer = LiveRouteObserver();
      final h = await _pump(tester, observer: observer);
      final prompts = AppPrompts(listenRoutes: observer.addListener);
      final context = tester.element(find.text('home'));
      unawaited(h.router.push<void>('/room'));
      await tester.pumpAndSettle();
      final feed = _FakeFeed(info: _info('9.0.0'));
      unawaited(checkForUpdateOnStartup(context, settings: h.services.store.settings, feed: feed, prompts: prompts));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('new-version-dialog')), findsNothing);
      expect(prompts.waiting, 1);

      h.router.pop();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(find.byKey(const ValueKey('new-version-dialog')), findsOneWidget);
    });
  });

  group('download (U.3d c7–c10)', () {
    testWidgets('downloading, done, open failed, folder failed: titles, lines and buttons', (tester) async {
      final folder = _temp();
      final http = _GatedHttp(size: 3 * 1024 * 1024);
      final h = await _pump(tester, overrides: [updateDownloadToolsProvider.overrideWithValue(_tools(http, folder))]);
      final context = tester.element(find.text('home'));
      unawaited(showUpdateDownload(context, file: _apk('9.0.0'), sources: [_apk('9.0.0').url], version: '9.0.0'));
      await tester.pump();
      await tester.pump();
      expect(find.text('正在下载 v9.0.0'), findsOneWidget);
      expect(find.text('准备中...'), findsOneWidget);
      expect(find.text('…'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('关闭'), findsNothing);
      // No toast repeating the title (D5).
      expect(h.toasts, isEmpty);

      await _until(tester, () => http.opens > 0);
      http.body.add(List.filled(1024 * 1024, 1));
      await _until(tester, () => find.text('33%').evaluate().isNotEmpty);
      expect(find.text('1.0 MB / 3.0 MB'), findsOneWidget);

      http.body.add(List.filled(2 * 1024 * 1024, 2));
      unawaited(http.body.close());
      await _until(tester, () => find.text('v9.0.0 已下载').evaluate().isNotEmpty);
      expect(find.text('下载完成'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      // Close at the left, then open folder and install.
      expect(_x(tester, '关闭'), lessThan(_x(tester, '打开文件夹')));
      expect(_x(tester, '打开文件夹'), lessThan(_x(tester, '立即安装')));
      expect(find.byIcon(AppIcons.downloadDone), findsOneWidget);

      // The installer does not open: the reason and "重新打开".
      await tester.tap(find.text('立即安装'));
      await tester.pumpAndSettle();
      expect(find.text('文件已下载，但打开失败。'), findsOneWidget);
      expect(find.text('重新打开'), findsOneWidget);
      expect(find.byIcon(AppIcons.downloadFailed), findsOneWidget);
      expect(h.opened.last, endsWith('.apk'));

      // Back closes a finished download (the file stays).
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('update-download-dialog')), findsNothing);
      expect(File('${folder.path}/${_apk('9.0.0').name}').existsSync(), isTrue);
    });

    testWidgets('unknown size, then a failure: the line, retry, browser and close', (tester) async {
      final folder = _temp();
      final http = _GatedHttp();
      await _pump(tester, overrides: [updateDownloadToolsProvider.overrideWithValue(_tools(http, folder))]);
      final context = tester.element(find.text('home'));
      unawaited(showUpdateDownload(context, file: _apk('9.0.0'), sources: [_apk('9.0.0').url], version: '9.0.0'));
      await _until(tester, () => http.opens > 0);
      http.body.add(List.filled(1024 * 1024, 1));
      await _until(tester, () => find.text('已下载: 1.0 MB').evaluate().isNotEmpty);
      expect(find.text('…'), findsOneWidget);
      http.body.addError(const TransportFailure('update', TransportReason.connect, 'cut'));
      await _until(tester, () => find.text('下载没有完成').evaluate().isNotEmpty);
      expect(find.text('下载中断，已下载的部分会保留，重试时接着下载'), findsOneWidget);
      expect(_x(tester, '关闭'), lessThan(_x(tester, '在浏览器中下载')));
      expect(_x(tester, '在浏览器中下载'), lessThan(_x(tester, '重试')));
      final scheme = Theme.of(tester.element(find.text('下载没有完成'))).colorScheme;
      expect(
        tester.renderObject<RenderParagraph>(find.byKey(const ValueKey('update-download-message'))).text.style?.color,
        scheme.error,
      );
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('update-download-dialog')), findsNothing);
    });

    testWidgets('cancel while downloading keeps the part; Back is the same cancel', (tester) async {
      final folder = _temp();
      final http = _GatedHttp(size: 3 * 1024 * 1024);
      final h = await _pump(tester, overrides: [updateDownloadToolsProvider.overrideWithValue(_tools(http, folder))]);
      final context = tester.element(find.text('home'));
      unawaited(showUpdateDownload(context, file: _apk('9.0.0'), sources: [_apk('9.0.0').url], version: '9.0.0'));
      await _until(tester, () => http.opens > 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('update-download-dialog')), findsNothing);
      expect(h.toasts.single, '已取消下载，下次会接着已下载的部分继续');

      // Esc on a computer is the same cancel (a tap outside does nothing).
      final again = _GatedHttp(size: 3 * 1024 * 1024);
      final folder2 = _temp();
      await tester.pumpWidget(const SizedBox.shrink());
      final h2 = await _pump(
        tester,
        width: 1280,
        height: 800,
        overrides: [updateDownloadToolsProvider.overrideWithValue(_tools(again, folder2))],
      );
      unawaited(
        showUpdateDownload(
          tester.element(find.text('home')),
          file: _apk('9.0.0'),
          sources: [_apk('9.0.0').url],
          version: '9.0.0',
        ),
      );
      await _until(tester, () => again.opens > 0);
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      expect(find.byKey(const ValueKey('update-download-dialog')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('update-download-dialog')), findsNothing);
      expect(h2.toasts.single, '已取消下载，下次会接着已下载的部分继续');
    });
  });

  group('download folder (U.3d c6)', () {
    testWidgets('asked when never answered and the default is missing; cancel, Esc and outside cancel the download', (
      tester,
    ) async {
      final folder = _temp();
      final missing = Directory('${folder.path}/missing');
      final http = _GatedHttp(size: 10);
      late SettingsStore settings;
      final h = await _pump(
        tester,
        overrides: [
          updateDownloadToolsProvider.overrideWith(
            (ref) => _tools(http, folder, settings: ref.watch(appServicesProvider).store.settings, fallback: missing),
          ),
        ],
      );
      settings = h.services.store.settings;
      final context = tester.element(find.text('home'));
      Future<void> start() async {
        unawaited(showUpdateDownload(context, file: _apk('9.0.0'), sources: [_apk('9.0.0').url], version: '9.0.0'));
        await _until(tester, () => find.byKey(const ValueKey('download-directory-dialog')).evaluate().isNotEmpty);
      }

      await start();
      expect(find.text('选择下载目录'), findsOneWidget);
      expect(find.textContaining(missing.path), findsOneWidget);
      expect(_x(tester, '取消'), lessThan(_x(tester, '使用默认目录')));
      expect(_x(tester, '使用默认目录'), lessThan(_x(tester, '选择目录')));
      await tester.tap(find.text('取消'));
      await _until(tester, () => h.toasts.isNotEmpty);
      expect(h.toasts.last, '未选择下载目录，已取消下载');
      expect(find.byKey(const ValueKey('update-download-dialog')), findsNothing);

      await start();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _until(tester, () => h.toasts.length > 1);
      expect(h.toasts.last, '未选择下载目录，已取消下载');

      await start();
      await tester.tapAt(const Offset(10, 10));
      await _until(tester, () => h.toasts.length > 2);
      expect(h.toasts.last, '未选择下载目录，已取消下载');

      // The default folder: remembered, the download starts, no more asking.
      await start();
      await tester.tap(find.text('使用默认目录'));
      await _until(tester, () => find.byKey(const ValueKey('update-download-dialog')).evaluate().isNotEmpty);
      expect(settings.get(Settings.downloadDirectoryDecisionMade), isTrue);
      expect(settings.get(Settings.downloadDirectoryPath), '');
    });
  });
}
