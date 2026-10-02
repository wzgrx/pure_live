import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
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

/// The page's and the importer's clock in these tests.
final DateTime _pageNow = DateTime(2026, 10, 1, 20);

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

/// Answers GETs from [bodies] by URL; anything else is a 404. While [gate]
/// is set, answers wait for it.
final class _FakeHttp implements LiveHttp {
  final bodies = <String, String>{};
  final requests = <String>[];
  Completer<void>? gate;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request.url.toString());
    await gate?.future;
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
  Size size = const Size(900, 3200),
  List<Override> overrides = const [],
  Future<void> Function(_Harness harness)? prepare,
}) async {
  tester.view
    ..physicalSize = size
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
      // The page's clock: an import stamps "updated" with this time, so the
      // cards read "今天" whatever day the test runs on.
      now: () => _pageNow,
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
        iptvClockProvider.overrideWithValue(() => _pageNow),
        ...overrides,
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

/// Imports one network playlist and one network guide before the page opens.
Future<void> _withSources(_Harness h) async {
  await h.importer.importPlaylistFromUrl(_playlistUrl);
  await h.importer.importGuideFromUrl('https://f/guide.xml');
}

const Map<String, String> _bodies = {_playlistUrl: _playlist, 'https://f/guide.xml': _guide};

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

/// The button inside a card's sync or delete control.
ButtonStyleButton _button(WidgetTester tester, String key) => tester.widget<ButtonStyleButton>(
  find.descendant(of: find.byKey(ValueKey(key)), matching: find.byWidgetPredicate((widget) => widget is TextButton)),
);

void main() {
  testWidgets('one page: counts, playlists, guides, then sync and playback, in this order', (tester) async {
    late IptvPlaylist playlist;
    late EpgSource guide;
    await _pump(
      tester,
      size: const Size(393, 3200),
      bodies: _bodies,
      prepare: (h) async {
        await _withSources(h);
        playlist = (await h.library.playlists()).single;
        guide = (await h.library.guideSources()).single;
      },
    );
    expect(find.text('IPTV 设置'), findsOneWidget);
    // The title bar's sync (3.x refresh_line, same place).
    final syncAll = find.byKey(const ValueKey('iptv-sync-all'));
    expect(find.descendant(of: syncAll, matching: find.byIcon(AppIcons.syncAll)), findsOneWidget);

    final order = [
      find.byKey(const ValueKey('iptv-stats')),
      find.text('播放列表').last,
      find.byKey(const ValueKey('iptv-import-playlist')),
      find.byKey(ValueKey('iptv-card-${playlist.id}')),
      find.text('节目单').last,
      find.byKey(const ValueKey('iptv-import-guide')),
      find.byKey(const ValueKey('iptv-active-guide')),
      find.byKey(ValueKey('iptv-card-${guide.id}')),
      find.text('同步和播放'),
      find.text('启动时全自动同步'),
      find.text('自定义直播源请求头'),
    ];
    for (var i = 1; i < order.length; i++) {
      expect(_top(tester, order[i]), greaterThan(_top(tester, order[i - 1])), reason: '$i');
    }
    // Counts: playlists, channels, guides.
    expect(
      find.descendant(of: find.byKey(const ValueKey('iptv-stat-channels')), matching: find.text('2')),
      findsOneWidget,
    );
    expect(find.text('M3U / TXT 文件、订阅地址，或粘贴文本'), findsOneWidget);
    expect(find.text('XML / GZ / JSON 文件或订阅地址'), findsOneWidget);
    // v3's icons.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('iptv-import-playlist')),
        matching: find.byIcon(AppIcons.importPlaylist),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const ValueKey('iptv-import-guide')), matching: find.byIcon(AppIcons.importGuide)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(ValueKey('iptv-card-${playlist.id}')), matching: find.byIcon(AppIcons.playlist)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(ValueKey('iptv-card-${guide.id}')), matching: find.byIcon(AppIcons.guide)),
      findsOneWidget,
    );
    expect(find.text('M3U'), findsOneWidget);
    expect(find.text('XML'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^2 个频道 · 今天 \d\d:\d\d 更新$')), findsNWidgets(2));

    // The guide in use: a tag on its card, no "use" button (H3 A).
    expect(find.byKey(ValueKey('iptv-in-use-${guide.id}')), findsOneWidget);
    expect(find.text('使用'), findsNothing);
    // Phone: sync and delete side by side, the switch under them (c6).
    expect(find.byKey(ValueKey('iptv-actions-column-${playlist.id}')), findsOneWidget);
    final sync = tester.getRect(find.byKey(ValueKey('iptv-sync-${playlist.id}')));
    final delete = tester.getRect(find.byKey(ValueKey('iptv-remove-${playlist.id}')));
    final auto = tester.getRect(find.byKey(ValueKey('iptv-auto-${playlist.id}')));
    expect(sync.left, lessThan(delete.left));
    expect(sync.top, delete.top);
    expect(auto.top, greaterThan(sync.bottom));
    expect(sync.height, greaterThanOrEqualTo(48));
    expect(
      find.descendant(of: find.byKey(ValueKey('iptv-sync-${playlist.id}')), matching: find.byIcon(AppIcons.syncOne)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(ValueKey('iptv-remove-${playlist.id}')), matching: find.byIcon(AppIcons.delete)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(1280, 800), Size(852, 393)]) {
    testWidgets('${size.width.toInt()}×${size.height.toInt()}: one column at most 720 wide, card buttons in one row', (
      tester,
    ) async {
      late IptvPlaylist playlist;
      await _pump(
        tester,
        size: size,
        bodies: _bodies,
        prepare: (h) async {
          await _withSources(h);
          playlist = (await h.library.playlists()).single;
        },
      );
      final card = tester.getRect(find.byKey(ValueKey('iptv-card-${playlist.id}')));
      expect(card.width, lessThanOrEqualTo(720));
      expect(card.center.dx, closeTo(size.width / 2, 1));
      expect(find.byKey(ValueKey('iptv-actions-row-${playlist.id}')), findsOneWidget);
      final sync = tester.getRect(find.byKey(ValueKey('iptv-sync-${playlist.id}')));
      final auto = tester.getRect(find.byKey(ValueKey('iptv-auto-${playlist.id}')));
      final delete = tester.getRect(find.byKey(ValueKey('iptv-remove-${playlist.id}')));
      expect(sync.right, lessThan(auto.left));
      expect(auto.right, lessThan(delete.left));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the more menu opens or copies the address; a right click opens it too; tapping the card does nothing', (
    tester,
  ) async {
    late IptvPlaylist playlist;
    final h = await _pump(
      tester,
      bodies: _bodies,
      prepare: (h) async {
        await _withSources(h);
        playlist = (await h.library.playlists()).single;
      },
    );
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final opened = <Uri>[];
    final previousOpen = AppNavigator.openExternal;
    AppNavigator.openExternal = (uri) async {
      opened.add(uri);
      return true;
    };
    addTearDown(() => AppNavigator.openExternal = previousOpen);

    // 3.x opened the address on any tap of the card.
    await _tap(tester, find.text('tv'));
    expect(opened, isEmpty);

    await _tap(tester, find.byKey(ValueKey('iptv-more-${playlist.id}')));
    expect(find.text('在浏览器中打开'), findsOneWidget);
    expect(find.text('复制地址'), findsOneWidget);
    expect(_top(tester, find.text('在浏览器中打开')), lessThan(_top(tester, find.text('复制地址'))));
    await _tap(tester, find.text('复制地址'));
    expect(copied, _playlistUrl);
    expect(h.toasts.last, '地址已复制');

    final card = find.byKey(ValueKey('iptv-card-${playlist.id}'));
    await tester.tap(
      find.descendant(of: card, matching: find.text('tv')),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await _settle(tester);
    await _tap(tester, find.text('在浏览器中打开'));
    expect(opened, [Uri.parse(_playlistUrl)]);
  });

  testWidgets('the first visit imports the default guide once and selects it', (tester) async {
    final h = await _pump(tester, bodies: {IptvImporter.defaultGuideUrl: _guide}, defaultGuideDone: false);

    expect(h.http.requests, [IptvImporter.defaultGuideUrl]);
    final guide = (await _run(tester, h.library.guideSources)).single;
    expect(h.settings.get(Settings.selectedSourceId), guide.id);
    expect(h.settings.get(Settings.selectedSourceName), IptvImporter.hotName);
    expect(await _run(tester, () => h.services.store.meta.get(defaultGuideMetaKey)), '1');
    expect(h.toasts, ['已导入默认节目单']);
    // The "in use" row and the card; the empty playlist state.
    expect(find.text('默认节目单'), findsNWidgets(2));
    expect(find.text('使用中'), findsOneWidget);
    expect(find.text('XML.GZ'), findsOneWidget);
    expect(find.byKey(const ValueKey('iptv-no-playlists')), findsOneWidget);
    expect(find.text('还没有播放列表'), findsOneWidget);

    // Deleting the guide in use says so and clears the selection (3.x kept
    // the deleted one selected).
    await _tap(tester, find.byKey(ValueKey('iptv-remove-${guide.id}')));
    expect(find.text('删除节目单？'), findsOneWidget);
    expect(find.textContaining('这是当前使用的节目单，删除后将改用下一个节目单'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('iptv-delete-confirm')));
    expect(await _run(tester, h.library.guideSources), isEmpty);
    expect(h.settings.get(Settings.selectedSourceId), '');
    expect(find.text('还没有节目单'), findsOneWidget);
    expect(find.text('点击选择一个节目单'), findsOneWidget);
    expect(h.http.requests, hasLength(1));
  });

  testWidgets('the default guide is not downloaded again; the empty state offers it', (tester) async {
    final h = await _pump(tester, bodies: {IptvImporter.defaultGuideUrl: _guide});
    expect(h.http.requests, isEmpty);
    expect(find.byKey(const ValueKey('iptv-no-guides')), findsOneWidget);
    expect(find.text('节目单用来在直播间显示正在播放和接下来的节目，并支持回看。'), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('iptv-empty-default-guide')));
    expect(h.http.requests, [IptvImporter.defaultGuideUrl]);
    expect(await _run(tester, h.library.guideSources), hasLength(1));
  });

  testWidgets('import dialogs keep 3.x order and add pasted text and the default guide', (tester) async {
    await _pump(tester);
    await _tap(tester, find.byKey(const ValueKey('iptv-import-playlist')));
    expect(find.text('导入播放列表 (M3U / TXT)'), findsOneWidget);
    final playlistOrigins = [
      find.byKey(const ValueKey('iptv-origin-file')),
      find.byKey(const ValueKey('iptv-origin-network')),
      find.byKey(const ValueKey('iptv-origin-text')),
    ];
    for (var i = 1; i < playlistOrigins.length; i++) {
      expect(_top(tester, playlistOrigins[i]), greaterThan(_top(tester, playlistOrigins[i - 1])));
    }
    expect(find.text('选择 M3U / M3U8 / TXT 文件'), findsOneWidget);
    expect(find.text('填订阅地址，以后可以同步'), findsOneWidget);
    expect(find.text('粘贴 M3U 或 TXT 列表的内容'), findsOneWidget);
    // No buttons: a choice or a tap outside (3.x).
    expect(find.text('取消'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.byKey(const ValueKey('iptv-origin-file')), findsNothing);

    await _tap(tester, find.byKey(const ValueKey('iptv-import-guide')));
    expect(find.text('导入电视节目单 (XML / GZ / JSON)'), findsOneWidget);
    expect(find.text('选择 XML / GZ / JSON 文件'), findsOneWidget);
    expect(find.byKey(const ValueKey('iptv-origin-defaultGuide')), findsOneWidget);
    expect(find.byKey(const ValueKey('iptv-origin-text')), findsNothing);
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
    expect(find.text('从网络导入播放列表'), findsOneWidget);
    expect(find.text('订阅地址'), findsOneWidget);
    expect(find.text('名称（可选）'), findsOneWidget);
    expect(find.text('留空时用地址里的文件名；已有同名的列表会先问你是否替换'), findsOneWidget);
    // The name defaults to the file name of the address.
    expect(find.text('tv'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('iptv-import-submit')));
    expect(find.byKey(const ValueKey('iptv-import-url')), findsNothing);
    expect(h.toasts.last, '已导入播放列表“tv”');
    final playlist = (await _run(tester, h.library.playlists)).single;
    expect(playlist.name, 'tv');
    expect(find.byKey(ValueKey('iptv-card-${playlist.id}')), findsOneWidget);

    // Same name: asked first; declining keeps the dialog with a hint, not a
    // failure (3.x reported "download or parse failed").
    await openNetworkImport(_playlistUrl);
    await _tap(tester, find.byKey(const ValueKey('iptv-import-submit')));
    expect(find.text('已有同名播放列表'), findsOneWidget);
    expect(find.text('已有名为“tv”的播放列表。替换后会用新内容更新它的频道，已关注的频道尽量保留。'), findsOneWidget);
    await _tap(tester, find.widgetWithText(TextButton, '取消').last);
    expect(find.text('已保留同名的原有数据。可以换一个名称再导入。'), findsOneWidget);
    expect(find.widgetWithText(DialogActionButton, '导入'), findsOneWidget);

    // A failed download says why under the address and offers a retry.
    await tester.enterText(find.byKey(const ValueKey('iptv-import-url')), 'https://f/missing.m3u');
    await _tap(tester, find.byKey(const ValueKey('iptv-import-submit')));
    expect(find.text('下载失败，请检查地址和网络后重试'), findsOneWidget);
    expect(find.widgetWithText(DialogActionButton, '重试'), findsOneWidget);
    // An address that is not http(s) is rejected before any request.
    await tester.enterText(find.byKey(const ValueKey('iptv-import-url')), 'ftp://f/tv.m3u');
    await _tap(tester, find.byKey(const ValueKey('iptv-import-submit')));
    expect(find.text('请输入正确的下载链接'), findsOneWidget);
    await _tap(tester, find.widgetWithText(TextButton, '取消'));
    expect(await _run(tester, h.library.playlists), hasLength(1));
    expect(h.toasts, hasLength(1));
  });

  testWidgets('a running network import shows its bar; closing the dialog lets it finish', (tester) async {
    final h = await _pump(tester, bodies: {_playlistUrl: _playlist});
    h.http.gate = Completer<void>();
    await _tap(tester, find.byKey(const ValueKey('iptv-import-playlist')));
    await _tap(tester, find.byKey(const ValueKey('iptv-origin-network')));
    await tester.enterText(find.byKey(const ValueKey('iptv-import-url')), _playlistUrl);
    await _tap(tester, find.byKey(const ValueKey('iptv-import-submit')));
    expect(find.text('正在下载和导入。关闭窗口不会中止导入，完成后会提示结果。'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('iptv-import-submit'))).onPressed, isNull);
    // Another import meanwhile is refused.
    await _tap(tester, find.widgetWithText(TextButton, '关闭'));
    await _tap(tester, find.byKey(const ValueKey('iptv-import-playlist')));
    expect(h.toasts.last, '已有导入正在进行，请等待完成。');
    h.http.gate!.complete();
    await _settle(tester);
    expect(h.toasts.last, '已导入播放列表“tv”');
  });

  testWidgets('pasted text and a local file import playlists; local cards only delete', (tester) async {
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
    expect(find.text('选择播放列表文件'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('iptv-file-path')), '"${file.path}"');
    // The main button says what it does (U.1d; not "确认").
    expect(
      find.descendant(of: find.byKey(const ValueKey('iptv-file-path-confirm')), matching: find.text('导入')),
      findsOneWidget,
    );
    await _tap(tester, find.byKey(const ValueKey('iptv-file-path-confirm')));
    expect(h.toasts.last, '已导入播放列表“local”');

    final playlists = await _run(tester, h.library.playlists);
    expect(playlists.map((playlist) => playlist.name), unorderedEquals(['pasted', 'local']));
    expect(playlists.every((playlist) => !playlist.isRemote), isTrue);
    for (final playlist in playlists) {
      expect(find.byKey(ValueKey('iptv-sync-${playlist.id}')), findsNothing);
      expect(find.byKey(ValueKey('iptv-auto-${playlist.id}')), findsNothing);
      expect(find.byKey(ValueKey('iptv-remove-${playlist.id}')), findsOneWidget);
    }
    expect(find.text('本地'), findsNWidgets(2));
    expect(find.text('TXT'), findsOneWidget);
  });

  testWidgets('syncs one source or all of them with progress, switches automatic sync and deletes', (tester) async {
    late IptvPlaylist playlist;
    final h = await _pump(
      tester,
      bodies: _bodies,
      prepare: (h) async {
        await _withSources(h);
        playlist = (await h.library.playlists()).single;
      },
    );
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
    // playlist, its automatic sync is off); the counts give way to the
    // progress and the cards wait.
    h.http.requests.clear();
    h.http.gate = Completer<void>();
    await _tap(tester, find.byKey(const ValueKey('iptv-sync-all')));
    expect(find.byKey(const ValueKey('iptv-sync-progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('iptv-stats')), findsNothing);
    expect(find.text('正在同步网络来源'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(_button(tester, 'iptv-sync-${playlist.id}').onPressed, isNull);
    h.http.gate!.complete();
    h.http.gate = null;
    await _settle(tester);
    expect(h.http.requests, [_playlistUrl, 'https://f/guide.xml']);
    expect(h.toasts.last, '已同步 2 个网络来源');
    expect(find.byKey(const ValueKey('iptv-stats')), findsOneWidget);

    h.http.bodies.remove(_playlistUrl);
    await _tap(tester, find.byKey(ValueKey('iptv-sync-${playlist.id}')));
    expect(h.toasts.last, '“tv”同步失败：下载失败，请检查地址和网络后重试');

    await _tap(tester, find.byKey(ValueKey('iptv-remove-${playlist.id}')));
    expect(find.text('删除播放列表？'), findsOneWidget);
    expect(find.text('将删除“tv”及其 2 个频道，关注和历史里的这些频道将无法播放，此操作不可撤销。'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('iptv-delete-confirm')));
    expect(await _run(tester, h.library.playlists), isEmpty);
    expect(h.toasts.last, '已删除“tv”');
    expect(find.text('还没有播放列表'), findsOneWidget);
  });

  testWidgets('the guide is switched only from "当前使用的节目单"; deleting it moves to the next', (tester) async {
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
    final a = guides.firstWhere((guide) => guide.name == 'a');
    final b = guides.firstWhere((guide) => guide.name == 'b');
    expect(h.settings.get(Settings.selectedSourceId), a.id);
    for (final guide in guides) {
      expect(find.byKey(ValueKey('iptv-use-${guide.id}')), findsNothing);
    }

    await _tap(tester, find.byKey(const ValueKey('iptv-active-guide')));
    expect(find.text('选择节目单'), findsOneWidget);
    // One way out at the bottom (3.x had a close button too).
    expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
    expect(find.byIcon(AppIcons.close), findsNothing);
    await _tap(tester, find.byKey(ValueKey('iptv-choose-${b.id}')));
    expect(h.settings.get(Settings.selectedSourceId), b.id);
    expect(h.settings.get(Settings.selectedSourceName), 'b');
    expect(h.toasts.last, '已改用“b”');
    expect(find.byKey(ValueKey('iptv-in-use-${b.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('iptv-in-use-${a.id}')), findsNothing);

    await _tap(tester, find.byKey(ValueKey('iptv-remove-${b.id}')));
    await _tap(tester, find.byKey(const ValueKey('iptv-delete-confirm')));
    expect(h.settings.get(Settings.selectedSourceId), a.id);
    expect(h.settings.get(Settings.selectedSourceName), 'a');
  });

  testWidgets('settings: enabling IPTV, automatic sync, interval and User-Agent', (tester) async {
    final h = await _pump(tester, prepare: (h) => h.settings.set(Settings.hotAreasList, const [SiteIds.bilibili]));
    expect(find.text('IPTV 没有启用'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('iptv-enable')));
    expect(h.settings.get(Settings.hotAreasList), [SiteIds.bilibili, SiteIds.iptv]);
    expect(find.byKey(const ValueKey('iptv-not-enabled')), findsNothing);

    expect(find.text('自动同步检查间隔'), findsNothing);
    await _tap(tester, find.text('启动时全自动同步'));
    expect(h.settings.get(Settings.isAutoSyncEnabled), isTrue);
    await _tap(tester, find.text('自动同步检查间隔'));
    expect(find.text('自动同步间隔'), findsOneWidget);
    for (final hours in [2, 6, 12, 24, 48, 72]) {
      expect(find.text('$hours 小时'), findsOneWidget);
    }
    // The current one: the primary colour and a tick (U.1d c3).
    expect(
      find.descendant(of: find.byKey(const ValueKey('iptv-interval-24')), matching: find.byIcon(AppIcons.selected)),
      findsOneWidget,
    );
    await _tap(tester, find.byKey(const ValueKey('iptv-interval-6')));
    expect(h.settings.get(Settings.autoSyncHoursInterval), 6);
    expect(find.text('当前每隔 6 小时进行一次同步'), findsOneWidget);

    expect(find.text('未设置（使用默认请求头）'), findsOneWidget);
    await _tap(tester, find.text('自定义直播源请求头'));
    expect(find.text('修改请求头 (User-Agent)'), findsOneWidget);
    expect(find.textContaining('px'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('iptv-user-agent')), 'old');
    await _tap(tester, find.byKey(const ValueKey('iptv-user-agent-clear')));
    expect(tester.widget<TextField>(find.byKey(const ValueKey('iptv-user-agent'))).controller!.text, isEmpty);
    await tester.enterText(find.byKey(const ValueKey('iptv-user-agent')), '  UA/1  ');
    await _tap(tester, find.byKey(const ValueKey('iptv-user-agent-save')));
    expect(h.settings.get(Settings.customIptvUserAgent), 'UA/1');
    expect(h.toasts.last, '已保存请求头');
    expect(find.text('UA/1'), findsOneWidget);
  });

  testWidgets('loading shows a still skeleton', (tester) async {
    final pending = StreamController<IptvOverview>();
    addTearDown(pending.close);
    await _pump(tester, overrides: [iptvOverviewProvider.overrideWith((ref) => pending.stream)]);
    expect(find.byKey(const ValueKey('iptv-skeleton')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // The settings are there while the lists load.
    expect(find.text('同步和播放'), findsOneWidget);
  });

  testWidgets('a read failure explains and retries', (tester) async {
    await _pump(
      tester,
      overrides: [iptvOverviewProvider.overrideWith((ref) => Stream<IptvOverview>.error(StateError('test')))],
    );
    expect(find.byKey(const ValueKey('iptv-load-failed')), findsOneWidget);
    expect(find.text('读取失败'), findsOneWidget);
    expect(find.text('读取 IPTV 配置失败。原有设置已保留，请重试。'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '重试'), findsOneWidget);
  });

  testWidgets('fits a narrow phone with large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(tester, size: const Size(340, 3200), bodies: _bodies, prepare: _withSources);
    expect(find.text('tv'), findsOneWidget);
    expect(find.text('guide'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
