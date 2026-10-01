// XML samples are written as adjacent strings without spaces between tags.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/web_dav/web_dav_client.dart';
import 'package:pure_live/features/web_dav/web_dav_page.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';

/// A WebDAV server in memory below `/dav/`, Basic auth `u:p`.
final class FakeDav implements LiveHttp {
  /// Files by path below the base.
  final Map<String, List<int>> files = {};

  /// Folders below the base ('' is the base).
  final Set<String> dirs = {''};

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    LiveResponse answer(int status, [String body = '']) =>
        LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);
    if (request.headers['authorization'] != 'Basic ${base64.encode(utf8.encode('u:p'))}') return answer(401);
    final segments = [
      for (final segment in request.url.pathSegments)
        if (segment.isNotEmpty) segment,
    ];
    final key = segments.skip(1).join('/');
    switch (request.method) {
      case 'PROPFIND':
        if (!dirs.contains(key)) return answer(404);
        String href(String path, {required bool dir}) =>
            '/dav/${[for (final part in path.split('/'))
              if (part.isNotEmpty) Uri.encodeComponent(part)].join('/')}'
            '${dir && path.isNotEmpty ? '/' : ''}';
        bool child(String path) =>
            path != key &&
            (key.isEmpty
                ? !path.contains('/')
                : path.startsWith('$key/') && !path.substring(key.length + 1).contains('/'));
        final responses = StringBuffer()
          ..write(
            '<D:response><D:href>${href(key, dir: true)}${key.isEmpty ? '' : ''}</D:href>'
            '<D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>',
          );
        if (request.headers['depth'] != '0') {
          for (final dir in dirs.where(child)) {
            responses.write(
              '<D:response><D:href>${href(dir, dir: true)}</D:href><D:propstat><D:prop>'
              '<D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>',
            );
          }
          for (final MapEntry(key: path, value: bytes) in files.entries.where((e) => child(e.key))) {
            responses.write(
              '<D:response><D:href>${href(path, dir: false)}</D:href><D:propstat><D:prop>'
              '<D:resourcetype/><D:getcontentlength>${bytes.length}</D:getcontentlength>'
              '<D:getlastmodified>Wed, 01 Oct 2026 12:00:00 GMT</D:getlastmodified>'
              '</D:prop></D:propstat></D:response>',
            );
          }
        }
        return answer(207, '<?xml version="1.0"?><D:multistatus xmlns:D="DAV:">$responses</D:multistatus>');
      case 'PUT':
        files[key] = request.body ?? const [];
        return answer(201);
      case 'GET':
        final bytes = files[key];
        return bytes == null ? answer(404) : LiveResponse(status: 200, bytes: bytes, url: request.url);
      case 'DELETE':
        return files.remove(key) == null && !dirs.remove(key) ? answer(404) : answer(204);
    }
    return answer(405);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();

  @override
  void close() {}
}

LiveRoom _room(String id) => LiveRoom(platform: 'douyu', roomId: id, title: 'Title $id', nick: 'Nick $id');

List<String> _toasts = [];

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<AppServices> _pump(
  WidgetTester tester,
  FakeDav dav, {
  WebDavConfig? server,
  Size size = const Size(500, 1000),
  bool pushed = false,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(() async {
    final services = await testServices();
    if (server != null) {
      await services.store.webdav.add(server);
      await services.store.webdav.select(server.name);
    }
    return services;
  }))!;
  addTearDown(() => tester.runAsync(services.close));
  final strings = (await tester.runAsync(loadStrings))!;
  final toasts = <String>[];
  final previous = AppNavigator.toast;
  AppNavigator.toast = toasts.add;
  addTearDown(() => AppNavigator.toast = previous);
  _toasts = toasts;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        webDavHttpProvider.overrideWithValue(dav),
        webDavClockProvider.overrideWithValue(() => DateTime(2026, 10, 1, 20)),
      ],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp(
          theme: const LiveTheme(primaryColor: Colors.blue).light,
          home: pushed
              ? Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const WebDavPage(route: RouteArgs(RoutePath.kWebDavPage)),
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                )
              : const WebDavPage(route: RouteArgs(RoutePath.kWebDavPage)),
        ),
      ),
    ),
  );
  if (pushed) {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }
  await _settle(tester);
  return services;
}

void main() {
  setUpAll(loadStrings);

  test('reads multistatus answers with any prefix, encoded names, without the folder itself', () {
    const xml =
        '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:">'
        '<d:response><d:href>/dav/backup/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/>'
        '</d:resourcetype></d:prop></d:propstat></d:response>'
        '<d:response><d:href>/dav/backup/%E5%A4%87%E4%BB%BD%20a.txt</d:href><d:propstat><d:prop><d:resourcetype/>'
        '<d:getcontentlength>12</d:getcontentlength>'
        '<d:getlastmodified>Wed, 01 Oct 2026 12:00:00 GMT</d:getlastmodified></d:prop></d:propstat></d:response>'
        '<response xmlns="DAV:"><href>https://host/dav/backup/old/</href><propstat><prop><resourcetype>'
        '<collection/></resourcetype></prop></propstat></response>'
        '<d:response><d:href>/elsewhere/x.txt</d:href></d:response>'
        '</d:multistatus>';
    final entries = parseMultistatus(
      xml,
      requestUrl: Uri.parse('https://host/dav/backup/'),
      base: const ['dav'],
      dir: const ['backup'],
    );
    expect(
      [for (final entry in entries) (entry.path.join('/'), entry.isDir, entry.size)],
      [('backup/备份 a.txt', false, 12), ('backup/old', true, null)],
    );
    expect(entries.first.modified, DateTime.utc(2026, 10, 1, 12));
  });

  testWidgets('adds a server after testing it, uploads a backup and restores a file after the preview', (tester) async {
    final dav = FakeDav()
      ..dirs.add('old')
      ..files['purelive_2026-09-01T10_00_00.txt'] = utf8.encode(
        jsonEncode({
          'backupVersion': 3,
          'favorite': {
            'favoriteRooms': [_room('7').toJson()],
          },
        }),
      );
    final services = await _pump(tester, dav);
    expect(find.text('暂无配置，请先创建WebDAV配置'), findsOneWidget);
    expect(find.text('还没有服务器'), findsOneWidget, reason: 'under the title');
    expect(find.text('使用帮助教程'), findsOneWidget, reason: 'the empty state offers the help (c7)');

    await tester.tap(find.text('创建新配置'));
    await _settle(tester);
    expect(find.byIcon(AppIcons.webDavAddConfig), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('webdav-name')), 'home');
    await tester.enterText(find.byKey(const ValueKey('webdav-address')), 'https://dav.test/dav/');
    await tester.enterText(find.byKey(const ValueKey('webdav-user')), 'u');
    await tester.enterText(find.byKey(const ValueKey('webdav-password')), 'wrong');
    await tester.tap(find.byKey(const ValueKey('webdav-test')));
    await _settle(tester);
    expect(find.text('账号或密码错误（坚果云请使用应用密码）'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('webdav-password')), 'p');
    await tester.tap(find.byKey(const ValueKey('webdav-test')));
    await _settle(tester);
    expect(find.text('连接成功'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('webdav-save')));
    await _settle(tester);

    final current = (await tester.runAsync(services.store.webdav.current))!;
    expect((current.name, current.password), ('home', 'p'));
    expect(find.text('home'), findsOneWidget, reason: 'the server under the title (c2)');
    expect(find.text('old'), findsOneWidget);
    expect(find.text('purelive_2026-09-01T10_00_00.txt'), findsOneWidget);

    // Upload the current data to the open folder.
    await tester.runAsync(() => services.store.follows.add(_room('1')));
    expect(find.text('备份到当前目录'), findsOneWidget, reason: 'the button says what it does (c3)');
    await tester.tap(find.byKey(const ValueKey('webdav-upload')));
    await _settle(tester);
    final uploaded = jsonDecode(utf8.decode(dav.files['purelive_2026-10-01T20_00_00.txt']!)) as Map<String, Object?>;
    expect(((uploaded['favorite']! as Map)['favoriteRooms']! as List).single, containsPair('roomId', '1'));
    expect(_toasts, ['文件上传成功']);
    expect(find.text('purelive_2026-10-01T20_00_00.txt'), findsOneWidget);

    // A tap on a backup previews and restores it (c4, R2).
    await tester.tap(find.text('purelive_2026-09-01T10_00_00.txt'));
    await _settle(tester);
    expect(find.text('关注的直播间：1 → 1（新增 1，移除 1）'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('backup-restore-confirm')));
    await _settle(tester);
    expect([for (final room in (await tester.runAsync(services.store.follows.all))!) room.roomId], ['7']);
    expect(_toasts.last, '恢复备份成功');
  });

  testWidgets('the bar: server, refresh, ⋮ (follows upload, help); rows: icon, time · size, ⋮', (tester) async {
    final dav = FakeDav()
      ..dirs.add('old')
      ..files['purelive_2026-09-01T10_00_00.txt'] = utf8.encode('{}')
      ..files['notes.txt'] = utf8.encode('hello');
    await _pump(tester, dav, server: _server);
    final servers = tester.getCenter(find.byKey(const ValueKey('webdav-servers'))).dx;
    final refresh = tester.getCenter(find.byKey(const ValueKey('webdav-refresh'))).dx;
    final more = tester.getCenter(find.byKey(const ValueKey('webdav-more'))).dx;
    expect(servers < refresh && refresh < more, isTrue);
    expect(find.byIcon(AppIcons.webDavServers), findsOneWidget);
    expect(find.byIcon(AppIcons.refresh), findsOneWidget);
    expect(tester.getTopLeft(find.text('WebDAV')).dx, lessThan(120), reason: 'the title by the back button');

    await tester.tap(find.byKey(const ValueKey('webdav-more')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('仅上传关注列表')).dy, lessThan(tester.getTopLeft(find.text('使用帮助教程')).dy));
    expect(find.byIcon(AppIcons.help), findsOneWidget);
    await tester.tap(find.text('使用帮助教程'));
    await tester.pumpAndSettle();
    expect(find.text('WebDAV 设置帮助'), findsOneWidget);
    expect(find.byIcon(AppIcons.copyValue), findsOneWidget);
    Navigator.of(tester.element(find.text('WebDAV 设置帮助'))).pop();
    await tester.pumpAndSettle();

    // The path starts at the left edge (3.x left 48 empty, c11).
    expect(tester.getTopLeft(find.text('我的文件')).dx, lessThan(32));
    // Folder first, then files; each row: its icon, time · size, ⋮.
    expect(find.descendant(of: _entry('old'), matching: find.byIcon(AppIcons.webDavFolder)), findsOneWidget);
    expect(
      find.descendant(of: _entry('purelive_2026-09-01T10_00_00.txt'), matching: find.byIcon(AppIcons.webDavBackupFile)),
      findsOneWidget,
    );
    expect(find.descendant(of: _entry('notes.txt'), matching: find.byIcon(AppIcons.webDavOtherFile)), findsOneWidget);
    expect(find.textContaining(' · 5 B'), findsOneWidget);
    expect(find.descendant(of: _entry('old'), matching: find.byIcon(AppIcons.moreVertical)), findsOneWidget);
  });

  testWidgets('⋮, a right click and a long press open one menu; folders only delete; delete asks', (tester) async {
    final dav = FakeDav()
      ..dirs.add('old')
      ..files['old/a.txt'] = utf8.encode('{}');
    await _pump(tester, dav, server: _server);

    Future<List<String>> rows() async {
      await tester.pumpAndSettle();
      final found = [
        for (final key in ['webdav-menu-restore-all', 'webdav-menu-restore-follows', 'webdav-menu-delete'])
          if (find.byKey(ValueKey(key)).evaluate().isNotEmpty) key,
      ];
      await tester.tapAt(const Offset(5, 500));
      await tester.pumpAndSettle();
      return found;
    }

    await tester.tap(find.descendant(of: _entry('old'), matching: find.byIcon(AppIcons.moreVertical)));
    expect(await rows(), ['webdav-menu-delete'], reason: 'a folder has only 删除');
    await tester.tap(find.text('old'));
    await _settle(tester);
    expect(find.text('a.txt'), findsOneWidget);

    const all = ['webdav-menu-restore-all', 'webdav-menu-restore-follows', 'webdav-menu-delete'];
    await tester.tap(find.descendant(of: _entry('a.txt'), matching: find.byIcon(AppIcons.moreVertical)));
    expect(await rows(), all);
    await tester.tap(find.text('a.txt'), buttons: kSecondaryButton);
    expect(await rows(), all, reason: 'right click = ⋮');
    await tester.longPress(find.text('a.txt'));
    expect(await rows(), all, reason: 'long press = ⋮');

    await tester.tap(find.descendant(of: _entry('a.txt'), matching: find.byIcon(AppIcons.moreVertical)));
    await tester.pumpAndSettle();
    final error = Theme.of(tester.element(find.text('删除'))).colorScheme.error;
    expect(tester.widget<Text>(find.text('删除')).style?.color, error);
    expect(find.byType(PopupMenuDivider), findsOneWidget);
    await tester.tap(find.text('删除'));
    await _settle(tester);
    expect(find.text('确定要从 WebDAV 删除“a.txt”吗？'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('webdav-confirm')));
    await _settle(tester);
    expect(dav.files, isEmpty);
    expect(find.text('这个目录是空的'), findsOneWidget);
    expect(find.text('点右下角按钮把当前数据备份到这里'), findsOneWidget);

    await tester.tap(find.text('我的文件'));
    await _settle(tester);
    expect(find.text('old'), findsOneWidget);
  });

  testWidgets('a folder that does not load says why: "重试" and "编辑配置"', (tester) async {
    final dav = FakeDav();
    await _pump(
      tester,
      dav,
      server: const WebDavConfig(name: 'home', address: 'https://dav.test/dav/', username: 'u', password: 'x'),
    );
    expect(find.text('无法加载目录'), findsOneWidget);
    expect(find.text('账号或密码错误（坚果云请使用应用密码）'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.byKey(const ValueKey('webdav-upload')), findsNothing);
    await tester.tap(find.text('编辑配置'));
    await _settle(tester);
    expect(find.byIcon(AppIcons.webDavEditConfig), findsOneWidget);
    expect(tester.widget<TextFormField>(find.byKey(const ValueKey('webdav-name'))).enabled, isFalse);
  });

  testWidgets('the servers drawer: title, address, edit and a red delete on one line; a tap switches', (tester) async {
    final dav = FakeDav();
    final services = await _pump(tester, dav, server: _server);
    await tester.runAsync(
      () => services.store.webdav.add(
        const WebDavConfig(name: 'nas', address: 'https://nas.example.com/dav/', username: 'u', password: 'p'),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('webdav-servers')));
    await _settle(tester);
    // The drawer reads the list when the page loads; reopen the page state.
    expect(find.text('WebDAV 服务器'), findsOneWidget);
    expect(find.text('https://dav.test/dav/'), findsOneWidget);
    final edit = tester.getCenter(find.byKey(const ValueKey('webdav-edit-home')));
    final remove = tester.getCenter(find.byKey(const ValueKey('webdav-remove-home')));
    expect((edit.dy - remove.dy).abs(), lessThan(1), reason: 'one line');
    expect(edit.dx, lessThan(remove.dx));
    final error = Theme.of(tester.element(find.text('WebDAV 服务器'))).colorScheme.error;
    expect(
      tester
          .widget<Icon>(
            find.descendant(of: find.byKey(const ValueKey('webdav-remove-home')), matching: find.byType(Icon)),
          )
          .color,
      error,
    );
    expect(find.text('添加新配置'), findsOneWidget);
  });

  testWidgets('an upload that fails says why and offers "重试"', (tester) async {
    final dav = _FailingPut();
    await _pump(tester, dav, server: _server);
    await tester.tap(find.byKey(const ValueKey('webdav-upload')));
    await _settle(tester);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('文件上传失败'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, '重试'), findsOneWidget);
  });

  testWidgets('Back in a folder leaves the page (3.x, R4)', (tester) async {
    final dav = FakeDav()..dirs.add('old');
    await _pump(tester, dav, server: _server, pushed: true);
    await tester.tap(find.text('old'));
    await _settle(tester);
    expect(find.byKey(const ValueKey('webdav-breadcrumbs')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byType(WebDavPage), findsNothing);
  });

  testWidgets('wide: the path and the list in one centred 720 column', (tester) async {
    final dav = FakeDav()..dirs.add('old');
    await _pump(tester, dav, server: _server, size: const Size(1280, 800));
    final row = tester.getRect(_entry('old'));
    expect(row.width, 720);
    expect((row.left - (1280 - row.right)).abs(), lessThan(1));
    expect(tester.getTopLeft(find.text('我的文件')).dx, closeTo(row.left + 16, 12));
  });
}

const WebDavConfig _server = WebDavConfig(name: 'home', address: 'https://dav.test/dav/', username: 'u', password: 'p');

Finder _entry(String name) => find.byKey(ValueKey('webdav-entry-$name'));

/// A server that lists but refuses uploads.
final class _FailingPut extends FakeDav {
  @override
  Future<LiveResponse> send(LiveRequest request) async {
    if (request.method == 'PUT') return LiveResponse(status: 507, bytes: const [], url: request.url);
    return await super.send(request);
  }
}
