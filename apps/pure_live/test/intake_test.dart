import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/intake/clipboard_rooms.dart';
import 'package:pure_live/app/intake/share_intake.dart';
import 'package:pure_live/app/intake/system_intake.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/platform/share_channel.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_prompt.dart';
import 'package:pure_live/shared/rooms/share_code.dart';

import 'support.dart';

// F.0a: share codes, the clipboard check, shares and shortcuts
// (docs/O-Android系统集成/O03-分享接收和快捷方式/O03.2-接回半成品, docs/A-界面设计/A14-系统界面/A14.1-系统界面 c10, c11, c15).

/// A navigator context for code that only checks it is there.
final class _Context extends Fake implements BuildContext {
  @override
  bool get mounted => true;
}

List<int> _str(String text) {
  final bytes = utf8.encode(text);
  return [0xa0 | bytes.length, ...bytes];
}

final LiveRoom _douyu = LiveRoom(platform: SiteIds.douyu, roomId: '8888', title: '深夜电台', nick: '主播');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(OwnClipboardTexts.clear);

  group('share codes (F.0a c1)', () {
    test('round-trip, inside other words, and codes of other encoders (3.x)', () {
      final long = LiveRoom(
        platform: SiteIds.bilibili,
        roomId: '6',
        title: '标题' * 40,
        nick: 'n',
        cover: 'https://i0.hdslb.com/${'x' * 300}.jpg',
        link: 'https://live.bilibili.com/6',
      );
      final room = decodeRoomShareCode(encodeRoomShareCode(long))!;
      expect(
        (room.platform, room.roomId, room.title, room.cover, room.link),
        (long.platform, long.roomId, long.title, long.cover, long.link),
      );
      final code = encodeRoomShareCode(_douyu);
      expect(decodeRoomShareCode('纯粹直播口令：$code 复制后打开纯粹直播')?.nick, '主播');
      // 3.x's decoder took the standard alphabet with padding; an integer id.
      final other = base64.encode([
        0x83,
        ..._str('m'),
        ..._str('pure_live'),
        ..._str('p'),
        ..._str('huya'),
        ..._str('r'),
        0xcd,
        0x30,
        0x39,
      ]);
      expect(decodeRoomShareCode(other)?.roomId, '12345');
    });

    test('needs the magic, a platform and a usable room id (3.x isUsableCommand)', () {
      String code(String magic, String roomId) => base64Url.encode([
        0x83,
        ..._str('m'),
        ..._str(magic),
        ..._str('p'),
        ..._str('douyu'),
        ..._str('r'),
        ..._str(roomId),
      ]);
      expect(decodeRoomShareCode(code('pure_live', '1')), isNotNull);
      expect(decodeRoomShareCode(code('pure_live', 'null')), isNull);
      expect(decodeRoomShareCode(code('pure_live', '0')), isNull);
      expect(decodeRoomShareCode(code('other_app', '1')), isNull);
      expect(decodeRoomShareCode('https://live.bilibili.com/6'), isNull);
      expect(decodeRoomShareCode(base64Url.encode(List.filled(40, 0xdf))), isNull, reason: 'truncated map');
      expect(decodeRoomShareCode(''), isNull);
    });
  });

  group('clipboard (F.0a c1, c2)', () {
    late AppServices services;
    setUp(() async {
      services = await testServices();
      await loadStrings();
    });
    tearDown(() => services.close());

    test('offers a share code once per run, skips own codes and links, opens on "进入房间"', () async {
      var clipboard = encodeRoomShareCode(_douyu);
      final prompts = <LiveRoom>[];
      final opened = <LiveRoom>[];
      final watcher = ClipboardRoomWatcher(
        settings: services.store.settings,
        prompt: (room) async {
          prompts.add(room);
          return RoomPromptChoice.enter;
        },
        open: (room) async => opened.add(room),
        read: () async => clipboard,
      );
      addTearDown(watcher.dispose);
      await watcher.check();
      await watcher.check();
      expect(prompts.map((room) => room.roomId), ['8888'], reason: 'the same text once (3.x)');
      expect(opened.single.nick, '主播');

      clipboard = encodeRoomShareCode(LiveRoom(platform: SiteIds.huya, roomId: '1'));
      OwnClipboardTexts.remember(clipboard);
      await watcher.check();
      clipboard = 'https://live.bilibili.com/6';
      await watcher.check();
      expect(prompts, hasLength(1), reason: 'own codes and links are not offered (3.x, X2)');
    });

    test('the switch off reads nothing; Android reads only after the clipboard changed', () async {
      var reads = 0;
      var stamp = 5;
      final prompts = <LiveRoom>[];
      final watcher = ClipboardRoomWatcher(
        settings: services.store.settings,
        prompt: (room) async {
          prompts.add(room);
          return RoomPromptChoice.dismiss;
        },
        open: (_) async {},
        read: () async {
          reads++;
          return encodeRoomShareCode(_douyu);
        },
        stamp: () async => stamp,
      );
      addTearDown(watcher.dispose);
      expect(services.store.settings.get(Settings.detectClipboardRooms), isTrue, reason: 'on by default');
      await services.store.settings.set(Settings.detectClipboardRooms, false);
      await watcher.check();
      expect(reads, 0);
      await services.store.settings.set(Settings.detectClipboardRooms, true);
      await watcher.check();
      await watcher.check();
      expect(reads, 1, reason: 'the change time did not move');
      stamp = -1;
      await watcher.check();
      expect(reads, 1, reason: 'empty clipboard');
      expect(prompts, hasLength(1));
    });

    testWidgets('a return to the app looks one second later (3.x)', (tester) async {
      var reads = 0;
      final watcher = ClipboardRoomWatcher(
        settings: services.store.settings,
        prompt: (_) async => RoomPromptChoice.dismiss,
        open: (_) async {},
        read: () async {
          reads++;
          return null;
        },
      );
      addTearDown(watcher.dispose);
      watcher.resumed();
      await tester.pump(const Duration(milliseconds: 900));
      expect(reads, 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(reads, 1);
    });
  });

  group('shares and shortcuts (F.0a c3, U.14 c10, c11, c15)', () {
    late AppServices services;
    late List<String> notes;
    late List<LiveRoom> opened;
    late List<String> routes;
    late List<Object?> arguments;
    late List<(LiveRoom, RoomPromptChoice)> prompts;
    late List<String> released;
    late ShareIntake intake;
    setUp(() async {
      services = await testServices();
      await loadStrings();
      notes = [];
      opened = [];
      routes = [];
      arguments = [];
      prompts = [];
      released = [];
      intake = ShareIntake(
        links: LinkParser(services.sites, NoNetworkHttp()),
        importer: services.iptvImporter,
        navigator: () async => _Context(),
        openRoom: (room) async => opened.add(room),
        openRoute: (route, argument) async {
          routes.add(route);
          arguments.add(argument);
        },
        notify: notes.add,
        prompt: (context, room) async {
          prompts.add((room, RoomPromptChoice.enter));
          return RoomPromptChoice.enter;
        },
        release: (path) async => released.add(path),
      );
    });
    tearDown(() => services.close());

    test('a shortcut or notification opens its page or room', () async {
      expect(await intake.ingest(const SharedPayload(route: '/record_mannager')), ShareOutcome.opened);
      expect(
        await intake.ingest(const SharedPayload(room: {'platform': 'douyu', 'roomId': '8888', 'nick': '主播'})),
        ShareOutcome.opened,
      );
      await pumpEventQueue();
      expect(routes, ['/record_mannager']);
      expect(arguments, [null]);
      expect((opened.single.platform, opened.single.roomId, opened.single.nick), ('douyu', '8888', '主播'));
    });

    test('the "录制已停止" reminder opens the recording centre at its task (F02 c2)', () async {
      expect(
        await intake.ingest(const SharedPayload(route: '/record_mannager', task: 'bilibili_6')),
        ShareOutcome.opened,
      );
      // Only the recording centre takes a task.
      expect(await intake.ingest(const SharedPayload(route: '/search', task: 'bilibili_6')), ShareOutcome.opened);
      await pumpEventQueue();
      expect(routes, ['/record_mannager', '/search']);
      expect(arguments, ['bilibili_6', null]);
    });

    test('an outside intent opens only the shortcut pages, anything else is ignored quietly', () async {
      // Any app can send the open intent (release fixes, item 6).
      for (final route in ['/settings', '/backup', '/web_dav', '/live_play', '/search/../settings']) {
        expect(await intake.ingest(SharedPayload(route: route)), ShareOutcome.unsupported, reason: route);
      }
      expect(await intake.ingest(const SharedPayload(route: '/search')), ShareOutcome.opened);
      await pumpEventQueue();
      expect(routes, ['/search']);
      expect(notes, isEmpty);
      expect(ShareIntake.openableRoutes, {'/search', '/record_mannager'});
    });

    test('a shared code asks first (U.3d dialog, as 3.x)', () async {
      expect(await intake.ingest(SharedPayload(text: '口令 ${encodeRoomShareCode(_douyu)}')), ShareOutcome.opened);
      await pumpEventQueue();
      expect(prompts.single.$1.roomId, '8888');
      expect(opened.single.title, '深夜电台');
    });

    test('a room link says "正在打开…" and opens; a dead link and a retired platform say so (c11)', () async {
      expect(await intake.ingest(const SharedPayload(text: '快来看 https://live.bilibili.com/6 。')), ShareOutcome.opened);
      await pumpEventQueue();
      expect(notes.first, '正在打开分享的直播间…');
      expect((opened.single.platform, opened.single.roomId), (SiteIds.bilibili, '6'));

      notes.clear();
      expect(await intake.ingest(const SharedPayload(text: 'https://b23.tv/AbCd12')), ShareOutcome.notFound);
      expect(notes, ['正在打开分享的直播间…', '无法解析此链接']);
      notes.clear();
      expect(await intake.ingest(const SharedPayload(text: 'https://www.huajiao.com/l/1')), ShareOutcome.notFound);
      expect(notes.last, '该平台已下线，无法再打开，可在关注列表中取消关注');
    });

    test('text without a room link and unknown files are told apart (c10)', () async {
      expect(await intake.ingest(const SharedPayload(text: '今天天气不错')), ShareOutcome.unsupported);
      expect(notes.single, '分享的内容里没有能打开的直播间链接');
      final folder = Directory.systemTemp.createTempSync('share_intake_test');
      addTearDown(() => folder.deleteSync(recursive: true));
      final file = File(p.join(folder.path, 'photo.jpg'))..writeAsBytesSync([1, 2, 3]);
      notes.clear();
      expect(await intake.ingest(SharedPayload(files: [file.path])), ShareOutcome.unsupported);
      expect(notes.single, '不支持的文件格式，仅限 M3U 或 TXT');
      expect(released, [file.path], reason: 'the copy is let go');
    });

    test('a shared playlist goes to IPTV (3.x)', () async {
      final folder = Directory.systemTemp.createTempSync('share_intake_test');
      addTearDown(() => folder.deleteSync(recursive: true));
      final file = File(p.join(folder.path, 'f0a_shared.m3u'))
        ..writeAsStringSync('#EXTM3U\n#EXTINF:-1,CCTV-1\nhttp://example.com/1.m3u8\n');
      expect(await intake.ingest(SharedPayload(files: [file.path])), ShareOutcome.imported);
      expect(notes.single, contains('f0a_shared'));
      final playlists = await services.iptvImporter!.library.playlists();
      expect(playlists.map((playlist) => playlist.name), contains('f0a_shared'));
    });
  });

  test('the launcher gets the two newest rooms, only when they change (U.14 c15)', () async {
    final history = StreamController<List<LiveRoom>>();
    final sent = <List<RecentRoomShortcut>>[];
    final subscription = recentRoomShortcuts(history.stream).listen(sent.add);
    final a = LiveRoom(platform: 'douyu', roomId: '1', nick: '甲');
    final b = LiveRoom(platform: 'huya', roomId: '2', nick: '乙');
    history
      ..add([a, b, LiveRoom(platform: 'bilibili', roomId: '3')])
      ..add([a, b])
      ..add([b, a]);
    await pumpEventQueue();
    await subscription.cancel();
    await history.close();
    expect(sent.map((rooms) => rooms.map((room) => room.roomId).toList()), [
      ['1', '2'],
      ['2', '1'],
    ]);

    const channel = MethodChannel('pure_live/share_intake');
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      ..setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    await ShareChannel(android: true).setRecentRooms(sent.last);
    expect(calls.single.method, 'setRecentRooms');
    expect((calls.single.arguments as List).first, {'platform': 'huya', 'roomId': '2', 'title': '', 'nick': '乙'});
  });

  testWidgets('a page opened from outside replaces the same page on top instead of stacking (F02 c2)', (tester) async {
    Page<void> page(GoRouterState state, String path) => MaterialPage<void>(
      key: state.pageKey,
      name: path,
      child: Scaffold(body: Text('$path ${state.extra}')),
    );
    final router = GoRouter(
      observers: [liveRouteObserver],
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('home')),
        ),
        for (final path in [RoutePath.kRecordPage, RoutePath.kSearch])
          GoRoute(path: path, pageBuilder: (_, state) => page(state, path)),
      ],
    );
    AppNavigator.router = router;
    addTearDown(() => AppNavigator.router = null);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    unawaited(openOutsidePage(RoutePath.kRecordPage, null));
    await tester.pumpAndSettle();
    expect(find.text('/record_mannager null'), findsOneWidget);
    // The reminder of a task while the centre shows: the centre at the task.
    unawaited(openOutsidePage(RoutePath.kRecordPage, 'bilibili_6'));
    await tester.pumpAndSettle();
    expect(find.text('/record_mannager bilibili_6'), findsOneWidget);
    // Another page goes on top.
    unawaited(openOutsidePage(RoutePath.kSearch, null));
    await tester.pumpAndSettle();
    expect(find.text('/search null'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('/record_mannager bilibili_6'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget, reason: 'one recording centre');
  });

  test('payloads from the channel: shares, pages and rooms', () {
    final share = SharedPayload.fromChannel(const {
      'text': ' https://live.bilibili.com/6 ',
      'files': [
        {'path': '/cache/share_intake/x/a.m3u'},
        {'path': ''},
      ],
    });
    expect(share.text, ' https://live.bilibili.com/6 ');
    expect(share.files, ['/cache/share_intake/x/a.m3u']);
    expect(SharedPayload.fromChannel(const {'route': '/search'}).route, '/search');
    expect(SharedPayload.fromChannel(const {'route': 'search'}).route, isNull, reason: 'routes start with /');
    final reminder = SharedPayload.fromChannel(const {'route': '/record_mannager', 'task': ' bilibili_6 '});
    expect((reminder.route, reminder.task), ('/record_mannager', 'bilibili_6'));
    expect(SharedPayload.fromChannel(const {'route': '/record_mannager', 'task': '  '}).task, isNull);
    expect(SharedPayload.fromChannel(const {'route': '/record_mannager', 'task': 6}).task, isNull);
    expect(
      SharedPayload.fromChannel(const {
        'room': {'platform': 'douyu', 'roomId': '1'},
      }).room?['roomId'],
      '1',
    );
    expect(SharedPayload.fromChannel('junk').isEmpty, isTrue);
  });
}
