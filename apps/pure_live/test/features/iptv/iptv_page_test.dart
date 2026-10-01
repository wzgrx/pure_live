import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/iptv_library.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/iptv/iptv_data.dart';
import 'package:pure_live/features/iptv/iptv_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';

const _playlistUrl = 'https://f/tv.m3u';

const _playlist = '''
#EXTM3U
#EXTINF:-1 tvg-id="cctv1" group-title="央视",CCTV-1
https://f/cctv1.m3u8
#EXTINF:-1 group-title="卫视",湖南卫视
https://f/hunan.m3u8
''';

const _guide = '''
<tv>
<channel id="cctv1"><display-name>CCTV-1 综合</display-name></channel>
<channel id="hunan"><display-name>湖南卫视</display-name></channel>
<programme channel="cctv1" start="20261001110000 +0000" stop="20261001130000 +0000"><title>新闻</title></programme>
</tv>''';

/// Answers GETs from [bodies] by URL; anything else is a 404.
final class _FakeHttp implements LiveHttp {
  final bodies = <String, String>{};
  final requests = <String>[];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request.url.toString());
    final body = bodies[request.url.toString()];
    return LiveResponse(status: body == null ? 404 : 200, bytes: utf8.encode(body ?? ''), url: request.url);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();

  @override
  void close() {}
}

final class _Harness {
  new(this.services, this.importer, this.http, this.toasts);

  final AppServices services;
  final IptvImporter importer;
  final _FakeHttp http;
  final List<String> toasts;

  IptvLibrary get library => importer.library;

  SettingsStore get settings => services.store.settings;
}

/// Pumps the page over an in-memory store; [prepare] runs before it opens.
Future<_Harness> _pump(
  WidgetTester tester, {
  Map<String, String> bodies = const {},
  bool defaultGuideDone = true,
  double width = 900,
  Future<void> Function(_Harness harness)? prepare,
}) async {
  tester.view
    ..physicalSize = Size(width, 3200)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final harness = (await tester.runAsync(() async {
    final services = await testServices();
    final directory = Directory.systemTemp.createTempSync('iptv_page_test');
    addTearDown(() => directory.deleteSync(recursive: true));
    final http = _FakeHttp()..bodies.addAll(bodies);
    final settings = services.store.settings;
    final importer = IptvImporter(
      library: StoreIptvLibrary(services.store),
      http: http,
      playlistDirectory: directory,
      selectedGuideSourceId: () => settings.get(Settings.selectedSourceId),
      autoSyncEnabled: () => settings.get(Settings.isAutoSyncEnabled),
    );
    if (defaultGuideDone) await services.store.meta.set(defaultGuideMetaKey, '1');
    final harness = _Harness(services, importer, http, []);
    await prepare?.call(harness);
    return harness;
  }))!;
  addTearDown(() => tester.runAsync(harness.services.close));
  final strings = (await tester.runAsync(loadStrings))!;
  final previousToast = AppNavigator.toast;
  AppNavigator.toast = harness.toasts.add;
  addTearDown(() => AppNavigator.toast = previousToast);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(harness.services),
        iptvImporterProvider.overrideWithValue(harness.importer),
        iptvClockProvider.overrideWithValue(() => DateTime(2026, 10, 1, 20)),
      ],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp(
          theme: const LiveTheme(primaryColor: Colors.blue).light,
          home: const IptvPage(route: RouteArgs(RoutePath.kIptv)),
        ),
      ),
    ),
  );
  await _settle(tester);
  return harness;
}

/// Lets the store's queries and imports (real async work) finish, then the
/// frames; in steps, because a spinner shown meanwhile never settles.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder);
  await _settle(tester);
}

Future<T> _run<T>(WidgetTester tester, Future<T> Function() action) async => (await tester.runAsync(action)) as T;

void main() {
  testWidgets('the first visit imports the default guide once and selects it', (tester) async {
    final h = await _pump(tester, bodies: {IptvImporter.defaultGuideUrl: _guide}, defaultGuideDone: false);

    expect(h.http.requests, [IptvImporter.defaultGuideUrl]);
    final guide = (await _run(tester, h.library.guideSources)).single;
    expect(h.settings.get(Settings.selectedSourceId), guide.id);
    expect(h.settings.get(Settings.selectedSourceName), IptvImporter.hotName);
    expect(await _run(tester, () => h.services.store.meta.get(defaultGuideMetaKey)), '1');
    expect(h.toasts, ['已导入默认节目单']);
    // The tile, the card; the empty playlist hint.
    expect(find.text('默认节目单'), findsNWidgets(2));
    expect(find.text('使用中'), findsOneWidget);
    expect(find.text('还没有播放列表'), findsOneWidget);
    expect(find.textContaining('2 个节目单频道 · 更新于'), findsOneWidget);

    // Deleting it clears the selection (3.x kept the deleted one selected).
    await _tap(tester, find.byKey(ValueKey('iptv-remove-${guide.id}')));
    expect(find.textContaining('这是当前使用的节目单'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('iptv-delete-confirm')));
    expect(await _run(tester, h.library.guideSources), isEmpty);
    expect(h.settings.get(Settings.selectedSourceId), '');
    expect(find.text('还没有节目单'), findsOneWidget);
    expect(find.text('点击选择一个节目单源'), findsOneWidget);
    expect(h.http.requests, hasLength(1));
  });

  testWidgets('the default guide is not downloaded again after it was imported once', (tester) async {
    final h = await _pump(tester, bodies: {IptvImporter.defaultGuideUrl: _guide});
    expect(h.http.requests, isEmpty);
    expect(find.text('还没有节目单'), findsOneWidget);

    // Still one tap away.
    await _tap(tester, find.widgetWithText(TextButton, '默认节目单'));
    expect(h.http.requests, [IptvImporter.defaultGuideUrl]);
    expect(await _run(tester, h.library.guideSources), hasLength(1));
  });

  testWidgets('imports a network playlist, asks before replacing it and explains failures', (tester) async {
    final h = await _pump(tester, bodies: {_playlistUrl: _playlist});

    Future<void> openNetworkImport(String url) async {
      await _tap(tester, find.byKey(const ValueKey('iptv-import-playlist')));
      await _tap(tester, find.byKey(const ValueKey('iptv-origin-network')));
      await tester.enterText(find.byKey(const ValueKey('iptv-import-url')), url);
      await tester.pump();
    }

    await openNetworkImport(_playlistUrl);
    // The name defaults to the file name of the address.
    expect(find.text('tv'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('iptv-import-submit')));
    expect(find.byKey(const ValueKey('iptv-import-url')), findsNothing);
    expect(h.toasts.last, '已导入播放列表“tv”');
    final playlist = (await _run(tester, h.library.playlists)).single;
    expect(playlist.name, 'tv');
    expect(find.byKey(ValueKey('iptv-card-${playlist.id}')), findsOneWidget);
    expect(find.textContaining('2 个频道'), findsOneWidget);
    expect(find.text('播放列表（1）'), findsOneWidget);

    // Same name: asked first; declining keeps the dialog open with a hint
    // (3.x reported "download or parse failed").
    await openNetworkImport(_playlistUrl);
    await _tap(tester, find.byKey(const ValueKey('iptv-import-submit')));
    expect(find.text('该订阅名称已存在'), findsOneWidget);
    await _tap(tester, find.widgetWithText(TextButton, '取消').last);
    expect(find.byKey(const ValueKey('iptv-import-message')), findsOneWidget);
    expect(find.text('已保留同名的原有数据。可以换一个名称再导入。'), findsOneWidget);

    // A failed download says so and keeps the dialog.
    await tester.enterText(find.byKey(const ValueKey('iptv-import-url')), 'https://f/missing.m3u');
    await _tap(tester, find.byKey(const ValueKey('iptv-import-submit')));
    expect(find.text('下载失败，请检查地址和网络后重试'), findsOneWidget);
    // An address that is not http(s) is rejected before any request.
    await tester.enterText(find.byKey(const ValueKey('iptv-import-url')), 'ftp://f/tv.m3u');
    await _tap(tester, find.byKey(const ValueKey('iptv-import-submit')));
    expect(find.text('请输入正确的下载链接'), findsOneWidget);
    await _tap(tester, find.widgetWithText(TextButton, '取消'));
    expect(await _run(tester, h.library.playlists), hasLength(1));
    expect(h.toasts, hasLength(1));
  });

  testWidgets('pasted text and a local file path import playlists', (tester) async {
    final h = await _pump(tester);
    final file = File(p.join(Directory.systemTemp.createTempSync('iptv_page_file').path, 'local.txt'))
      ..writeAsStringSync('本地,#genre#\n凤凰,https://f/fh.m3u8\n');
    addTearDown(() => file.parent.deleteSync(recursive: true));

    await _tap(tester, find.byKey(const ValueKey('iptv-import-playlist')));
    await _tap(tester, find.byKey(const ValueKey('iptv-origin-text')));
    await tester.enterText(find.byKey(const ValueKey('iptv-import-text')), _playlist);
    await tester.enterText(find.byKey(const ValueKey('iptv-import-text-name')), 'pasted');
    await _tap(tester, find.byKey(const ValueKey('iptv-import-text-submit')));
    expect(h.toasts.last, '已导入播放列表“pasted”');

    await _tap(tester, find.byKey(const ValueKey('iptv-import-playlist')));
    await _tap(tester, find.byKey(const ValueKey('iptv-origin-file')));
    await tester.enterText(find.byKey(const ValueKey('iptv-file-path')), '"${file.path}"');
    await _tap(tester, find.widgetWithText(FilledButton, '确认'));
    expect(h.toasts.last, '已导入播放列表“local”');

    final playlists = await _run(tester, h.library.playlists);
    expect(playlists.map((playlist) => playlist.name), ['pasted', 'local']);
    expect(playlists.every((playlist) => !playlist.isRemote), isTrue);
    // Local playlists have no sync and no automatic sync.
    expect(find.byKey(ValueKey('iptv-sync-${playlists.first.id}')), findsNothing);
    expect(find.text('本地'), findsNWidgets(2));
    expect(find.text('TXT'), findsOneWidget);
  });

  testWidgets('syncs one source or all of them, switches automatic sync and deletes', (tester) async {
    late IptvPlaylist playlist;
    final h = await _pump(
      tester,
      bodies: {_playlistUrl: _playlist, 'https://f/guide.xml': _guide},
      prepare: (h) async {
        await h.importer.importPlaylistFromUrl(_playlistUrl);
        await h.importer.importGuideFromUrl('https://f/guide.xml');
        playlist = (await h.library.playlists()).single;
      },
    );
    expect(find.text('播放列表（1）'), findsOneWidget);
    expect(find.text('节目单（1）'), findsOneWidget);
    // The guide got selected on the way in.
    expect(h.settings.get(Settings.selectedSourceName), 'guide');

    await _tap(tester, find.byKey(ValueKey('iptv-sync-${playlist.id}')));
    expect(h.toasts.last, '“tv”已同步');

    // New network playlists follow the global switch (off here, 3.x).
    expect(playlist.autoUpdate, isFalse);
    await _tap(tester, find.byKey(ValueKey('iptv-auto-${playlist.id}')));
    expect((await _run(tester, () => h.library.playlist(playlist.id)))!.autoUpdate, isTrue);
    expect(h.toasts.last, '已开启自动同步');
    await _tap(tester, find.byKey(ValueKey('iptv-auto-${playlist.id}')));
    expect((await _run(tester, () => h.library.playlist(playlist.id)))!.autoUpdate, isFalse);
    expect(h.toasts.last, '已关闭自动同步');

    // All network sources, automatic sync on or off (3.x skipped the
    // playlist, its automatic sync is off).
    h.http.requests.clear();
    await _tap(tester, find.byKey(const ValueKey('iptv-sync-all')));
    expect(h.http.requests, [_playlistUrl, 'https://f/guide.xml']);
    expect(h.toasts.last, '已同步 2 个网络来源');

    h.http.bodies.remove(_playlistUrl);
    await _tap(tester, find.byKey(ValueKey('iptv-sync-${playlist.id}')));
    expect(h.toasts.last, '“tv”同步失败：下载失败，请检查地址和网络后重试');

    await _tap(tester, find.byKey(ValueKey('iptv-remove-${playlist.id}')));
    expect(find.textContaining('将删除“tv”及其 2 个频道'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('iptv-delete-confirm')));
    expect(await _run(tester, h.library.playlists), isEmpty);
    expect(h.toasts.last, '已删除“tv”');
    expect(find.text('还没有播放列表'), findsOneWidget);
  });

  testWidgets('switching or deleting the guide in use', (tester) async {
    late List<EpgSource> guides;
    final h = await _pump(
      tester,
      bodies: {'https://f/a.xml': _guide, 'https://f/b.xml': _guide},
      prepare: (h) async {
        await h.importer.importGuideFromUrl('https://f/a.xml');
        await h.importer.importGuideFromUrl('https://f/b.xml');
        guides = await h.library.guideSources();
      },
    );
    expect(h.settings.get(Settings.selectedSourceId), guides.first.id);

    await _tap(tester, find.byKey(ValueKey('iptv-use-${guides.last.id}')));
    expect(h.settings.get(Settings.selectedSourceId), guides.last.id);
    expect(h.settings.get(Settings.selectedSourceName), 'b');
    expect(h.toasts.last, '电子节目单源切换成功');

    // The selection dialog of the "active guide" row (3.x).
    await _tap(tester, find.text('当前启用的 EPG 数据源'));
    await _tap(tester, find.byKey(ValueKey('iptv-choose-${guides.first.id}')));
    expect(h.settings.get(Settings.selectedSourceId), guides.first.id);

    await _tap(tester, find.byKey(ValueKey('iptv-remove-${guides.first.id}')));
    await _tap(tester, find.byKey(const ValueKey('iptv-delete-confirm')));
    expect(h.settings.get(Settings.selectedSourceId), guides.last.id);
    expect(h.settings.get(Settings.selectedSourceName), 'b');
  });

  testWidgets('settings: enabling IPTV, automatic sync, interval and User-Agent', (tester) async {
    final h = await _pump(tester, prepare: (h) => h.settings.set(Settings.hotAreasList, const [SiteIds.bilibili]));
    expect(find.byKey(const ValueKey('iptv-not-enabled')), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('iptv-enable')));
    expect(h.settings.get(Settings.hotAreasList), [SiteIds.bilibili, SiteIds.iptv]);
    expect(find.byKey(const ValueKey('iptv-not-enabled')), findsNothing);

    expect(find.text('自动同步检查间隔'), findsNothing);
    await _tap(tester, find.text('启动时自动同步'));
    expect(h.settings.get(Settings.isAutoSyncEnabled), isTrue);
    await _tap(tester, find.text('自动同步检查间隔'));
    await _tap(tester, find.byKey(const ValueKey('iptv-interval-6')));
    expect(h.settings.get(Settings.autoSyncHoursInterval), 6);
    expect(find.text('当前每隔 6 小时进行一次同步'), findsOneWidget);

    expect(find.text('未设置（使用默认请求头）'), findsOneWidget);
    await _tap(tester, find.text('自定义直播源请求头'));
    await tester.enterText(find.byKey(const ValueKey('iptv-user-agent')), '  UA/1  ');
    await _tap(tester, find.byKey(const ValueKey('iptv-user-agent-save')));
    expect(h.settings.get(Settings.customIptvUserAgent), 'UA/1');
    expect(h.toasts.last, '请求头已保存');
    expect(find.text('UA/1'), findsOneWidget);
  });

  testWidgets('fits a narrow phone with large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(
      tester,
      width: 340,
      bodies: {_playlistUrl: _playlist, 'https://f/guide.xml': _guide},
      prepare: (h) async {
        await h.importer.importPlaylistFromUrl(_playlistUrl);
        await h.importer.importGuideFromUrl('https://f/guide.xml');
      },
    );
    expect(find.text('tv'), findsOneWidget);
    expect(find.text('guide'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
