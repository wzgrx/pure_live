// XML samples are written as adjacent strings without spaces between tags.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:convert';

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

Future<AppServices> _pump(WidgetTester tester, FakeDav dav, {WebDavConfig? server}) async {
  tester.view
    ..physicalSize = const Size(500, 1000)
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
          home: const WebDavPage(route: RouteArgs(RoutePath.kWebDavPage)),
        ),
      ),
    ),
  );
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

    await tester.tap(find.text('创建新配置'));
    await _settle(tester);
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
    expect(find.text('old'), findsOneWidget);
    expect(find.text('purelive_2026-09-01T10_00_00.txt'), findsOneWidget);

    // Upload the current data to the open folder.
    await tester.runAsync(() => services.store.follows.add(_room('1')));
    await tester.tap(find.byKey(const ValueKey('webdav-upload')));
    await _settle(tester);
    final uploaded = jsonDecode(utf8.decode(dav.files['purelive_2026-10-01T20_00_00.txt']!)) as Map<String, Object?>;
    expect(((uploaded['favorite']! as Map)['favoriteRooms']! as List).single, containsPair('roomId', '1'));
    expect(_toasts, ['文件上传成功']);
    expect(find.text('purelive_2026-10-01T20_00_00.txt'), findsOneWidget);

    // Restore the old file: the preview says what changes first.
    await tester.tap(find.text('purelive_2026-09-01T10_00_00.txt'));
    await _settle(tester);
    await tester.tap(find.text('恢复全部设置'));
    await _settle(tester);
    expect(find.text('关注的直播间：1 → 1（新增 1，移除 1）'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('backup-restore-confirm')));
    await _settle(tester);
    expect([for (final room in (await tester.runAsync(services.store.follows.all))!) room.roomId], ['7']);
    expect(_toasts.last, '恢复备份成功');
  });

  testWidgets('opens folders, goes back with the breadcrumbs and deletes after asking', (tester) async {
    final dav = FakeDav()
      ..dirs.add('old')
      ..files['old/a.txt'] = utf8.encode('{}');
    await _pump(
      tester,
      dav,
      server: const WebDavConfig(name: 'home', address: 'https://dav.test/dav/', username: 'u', password: 'p'),
    );
    await tester.tap(find.text('old'));
    await _settle(tester);
    expect(find.text('a.txt'), findsOneWidget);

    await tester.tap(find.text('a.txt'));
    await _settle(tester);
    await tester.tap(find.text('删除').last);
    await _settle(tester);
    expect(find.text('确定要从 WebDAV 删除“a.txt”吗？'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('webdav-confirm')));
    await _settle(tester);
    expect(dav.files, isEmpty);
    expect(find.text('这个目录是空的'), findsOneWidget);

    await tester.tap(find.text('我的文件'));
    await _settle(tester);
    expect(find.text('old'), findsOneWidget);
  });
}
