import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/remote_receiver/remote_receiver_page.dart';
import 'package:pure_live/features/remote_receiver/remote_sync_protocol.dart';
import 'package:pure_live/features/remote_receiver/remote_sync_service.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/backup/sync_parts.dart';
import 'package:pure_live/shared/qr_scan.dart';

import '../../shared/fake_qr_camera.dart';
import '../../support.dart';

/// A service on an in-memory store; no address, so no discovery.
Future<RemoteSyncService> _service({bool allow = true}) async {
  final store = await LiveStore.memory(cipher: FakeCipher());
  final service = RemoteSyncService(store, localIps: () => const [])..confirm = (_, _) async => allow;
  addTearDown(() async {
    service.dispose();
    await store.close();
  });
  return service;
}

/// The real dart:io client: the widget-test binding answers every request
/// of its own client with 400.
final class _RealHttp extends HttpOverrides;

/// Runs [body] with real HTTP clients.
Future<void> _withRealHttp(Future<void> Function() body) => HttpOverrides.runWithHttpOverrides(body, _RealHttp());

void main() {
  test('reads 3.x QR codes and addresses', () {
    final uri = RemoteSyncProtocol.createQrUri(ip: '192.168.1.5', port: 39888, code: '012345');
    expect(uri.toString(), 'purelive://192.168.1.5:39888/sync?code=012345');
    expect(RemoteSyncProtocol.parseQr(uri.toString()), (ip: '192.168.1.5', port: 39888, code: '012345'));
    expect(RemoteSyncProtocol.parseQr('192.168.1.5'), (ip: '192.168.1.5', port: 39888, code: null));
    expect(RemoteSyncProtocol.parseQr('http://10.0.0.2:40000'), (ip: '10.0.0.2', port: 40000, code: null));
    expect(RemoteSyncProtocol.parseQr('not an address'), isNull);
    expect(RemoteSyncProtocol.pairingCodesMatch('012345', ' 012 345 '), isTrue);
    expect(RemoteSyncProtocol.pairingCodesMatch('012345', '012346'), isFalse);
    expect(RemoteSyncProtocol.pairingCodesMatch('', ''), isFalse);
  });

  test(
    'sends and receives settings with the pairing code and consent',
    () => _withRealHttp(() async {
      final target = await _service();
      final source = await _service();
      await target.start();
      expect(target.running, isTrue);
      expect(target.pairingCode, hasLength(6));

      await source.store.settings.set(Settings.showSplashPage, false);
      expect(await source.send('127.0.0.1', target.port, target.pairingCode), isTrue);
      expect(target.store.settings.get(Settings.showSplashPage), isFalse);

      await target.store.settings.set(Settings.enableAutoCheckUpdate, false);
      expect(await source.receive('127.0.0.1', target.port, target.pairingCode), isTrue);
      expect(source.store.settings.get(Settings.enableAutoCheckUpdate), isFalse);
    }),
  );

  test(
    'refuses wrong codes, changes the code after ten, and needs consent',
    () => _withRealHttp(() async {
      final target = await _service(allow: false);
      final source = await _service();
      await target.start();
      final code = target.pairingCode;
      final wrong = code == '000000' ? '111111' : '000000';
      expect(await source.send('127.0.0.1', target.port, wrong), isFalse);
      expect(target.pairingCode, code);
      for (var i = 1; i < RemoteSyncService.maxWrongCodes; i++) {
        await source.send('127.0.0.1', target.port, wrong);
      }
      expect(target.pairingCode, isNot(code));

      await source.store.settings.set(Settings.showSplashPage, false);
      expect(await source.send('127.0.0.1', target.port, target.pairingCode), isFalse);
      expect(target.store.settings.get(Settings.showSplashPage), isTrue);
    }),
  );

  group('parts (J05.1)', _partTests);

  testWidgets('shows this device with its address, code and QR code', (tester) async {
    final services = (await tester.runAsync(testServices))!;
    addTearDown(() => tester.runAsync(services.close));
    final strings = (await tester.runAsync(loadStrings))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(services),
          remoteSyncServiceProvider.overrideWithValue(
            () => RemoteSyncService(services.store, localIps: () => const ['127.0.0.1', '10.1.2.3', '192.168.7.8']),
          ),
        ],
        child: LiveUiScope(
          config: LiveUiConfig(strings: strings.ui),
          child: MaterialApp(
            theme: const LiveTheme(primaryColor: Colors.blue).light,
            home: const RemoteReceiverPage(route: RouteArgs(RoutePath.kRemoteSync)),
          ),
        ),
      ),
    );
    await _until(tester, () => find.byKey(const ValueKey('remote-sync-code')).evaluate().isNotEmpty);
    expect(find.textContaining('192.168.7.8:'), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-sync-qr')), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-sync-code')), findsOneWidget);
    expect(find.text('同步服务运行中'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('remote-sync-toggle')));
    await _until(tester, () => find.text('同步服务未运行').evaluate().isNotEmpty);
    expect(find.text('同步服务未运行'), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-sync-code')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  });

  group('page (U.11c)', _pageTests);
}

LiveRoom _room(String id) => LiveRoom(platform: 'douyu', roomId: id, title: 't$id', nick: 'n$id');

/// Follows [room], blocks [word] and sets the splash page to [splash].
Future<void> _fill(LiveStore store, {required String room, required String word, required bool splash}) async {
  await store.follows.replaceAll([_room(room)]);
  await store.blockLists.replaceAll(BlockKind.keyword, [word]);
  await store.settings.set(Settings.showSplashPage, splash);
}

Future<List<String>> _follows(LiveStore store) async => [for (final room in await store.follows.all()) room.roomId];

/// POSTs [packet] to the settings endpoint of the local [port].
Future<int> _post(int port, String code, Map<String, Object?> packet) async {
  final client = HttpClient();
  try {
    final request = await client.post('127.0.0.1', port, RemoteSyncProtocol.apiSettings);
    request.headers
      ..contentType = ContentType.json
      ..set(RemoteSyncProtocol.pairingHeader, code);
    request.write(jsonEncode(packet));
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

/// A 3.x device: its status has no parts; it keeps what it is sent.
final class _LegacyPeer {
  late final HttpServer server;
  final List<Map<String, Object?>> received = [];

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response..headers.contentType = ContentType.json;
      if (request.uri.path == RemoteSyncProtocol.apiStatus) {
        final status = {'id': 'android-3', 'name': 'PureLive Android', 'platform': 'android', 'version': '1.0.0'};
        response.write(jsonEncode({'code': 200, 'msg': 'ok', 'data': status}));
      } else {
        received.add((jsonDecode(await utf8.decoder.bind(request).join()) as Map).cast<String, Object?>());
        response.write(jsonEncode({'code': 200, 'msg': 'ok', 'data': true}));
      }
      await response.close();
    });
    addTearDown(() => server.close(force: true));
  }
}

void _partTests() {
  test(
    'a v4 device says it takes parts; only the ticked ones travel and the rest stays',
    () => _withRealHttp(() async {
      final target = await _service();
      final source = await _service();
      await target.start();
      await _fill(target.store, room: '1', word: 'spoiler', splash: true);
      await _fill(source.store, room: '2', word: 'noise', splash: false);

      expect(await source.takesParts('127.0.0.1', target.port), isTrue);
      final code = target.pairingCode;
      final wrong = code == '000000' ? '111111' : '000000';
      expect(await source.send('127.0.0.1', target.port, wrong, parts: {SyncPart.follows}), isFalse);
      expect(await _follows(target.store), ['1'], reason: 'the pairing code still guards a partial send');

      expect(await source.send('127.0.0.1', target.port, code, parts: {SyncPart.follows}), isTrue);
      expect(await _follows(target.store), ['2']);
      expect(await target.store.blockLists.list(BlockKind.keyword), ['spoiler']);
      expect(target.store.settings.get(Settings.showSplashPage), isTrue);
    }),
  );

  test(
    '3.x packets have no sections and apply whole; an upstream packet applies only its sections',
    () => _withRealHttp(() async {
      final target = await _service();
      final source = await _service();
      await target.start();
      await _fill(target.store, room: '1', word: 'spoiler', splash: true);
      await _fill(source.store, room: '2', word: 'noise', splash: false);
      final settings = await BackupService(source.store).exportAll();

      final whole = RemoteSyncProtocol.settingsPacket(settings: settings);
      expect(whole.keys, ['type', 'version', 'settings'], reason: "3.x's packet, unchanged");
      expect(await _post(target.port, target.pairingCode, whole), HttpStatus.ok);
      expect(await _follows(target.store), ['2']);
      expect(target.store.settings.get(Settings.showSplashPage), isFalse);

      // Upstream pure_live 9483ccf03 lists the top-level sections it kept.
      await _fill(target.store, room: '1', word: 'spoiler', splash: true);
      final upstream = {
        ...whole,
        'sections': const ['favorite'],
      };
      expect(await _post(target.port, target.pairingCode, upstream), HttpStatus.ok);
      expect(await _follows(target.store), ['2']);
      expect(await target.store.blockLists.list(BlockKind.keyword), ['noise']);
      expect(target.store.settings.get(Settings.showSplashPage), isTrue, reason: '"app" was not listed');
    }),
  );

  test(
    'a 3.x device does not take parts: it gets the whole packet, as before',
    () => _withRealHttp(() async {
      final peer = _LegacyPeer();
      await peer.start();
      final source = await _service();
      await _fill(source.store, room: '2', word: 'noise', splash: false);
      expect(await source.takesParts('127.0.0.1', peer.server.port), isFalse);
      expect(await source.takesParts('127.0.0.1', 1), isFalse, reason: 'no answer: treated as 3.x');

      expect(await source.send('127.0.0.1', peer.server.port, '123456'), isTrue);
      final packet = peer.received.single;
      expect(packet.keys, ['type', 'version', 'settings']);
      expect(syncPartsIn((packet['settings']! as Map).cast<String, Object?>()), [
        SyncPart.settings,
        SyncPart.follows,
        SyncPart.areas,
        SyncPart.history,
        SyncPart.tags,
        SyncPart.keywords,
        SyncPart.users,
      ]);
    }),
  );

  test(
    'everything ticked sends the 3.x packet; fewer list their sections',
    () => _withRealHttp(() async {
      final peer = _LegacyPeer();
      await peer.start();
      final source = await _service();
      expect(await source.send('127.0.0.1', peer.server.port, '123456', parts: SyncPart.values.toSet()), isTrue);
      expect(peer.received.last.keys, ['type', 'version', 'settings']);
      expect(await source.send('127.0.0.1', peer.server.port, '123456', parts: {SyncPart.keywords}), isTrue);
      expect(peer.received.last['sections'], ['favorite']);
      expect(((peer.received.last['settings']! as Map)['favorite']! as Map).keys, ['shieldList']);
    }),
  );

  test(
    'an incoming send applies only the parts the user keeps here; none refuses it',
    () => _withRealHttp(() async {
      final target = await _service();
      final source = await _service();
      await target.start();
      await _fill(target.store, room: '1', word: 'spoiler', splash: true);
      await _fill(source.store, room: '2', word: 'noise', splash: false);
      Map<String, Object?>? offered;
      target.chooseImport = (_, settings) async {
        offered = settings;
        return null;
      };
      expect(await source.send('127.0.0.1', target.port, target.pairingCode), isFalse);
      expect(syncPartsIn(offered!), contains(SyncPart.follows));
      expect(await _follows(target.store), ['1'], reason: 'refused: nothing changes');

      target.chooseImport = (_, _) async => {SyncPart.keywords};
      expect(await source.send('127.0.0.1', target.port, target.pairingCode), isTrue);
      expect(await target.store.blockLists.list(BlockKind.keyword), ['noise']);
      expect(await _follows(target.store), ['1']);
      expect(target.store.settings.get(Settings.showSplashPage), isTrue);
    }),
  );

  test(
    'remembered Bilibili sign-ins (K01.2) leave only with "同步账号 Cookie" and its part; the receiver adds them',
    () => _withRealHttp(() async {
      final target = await _service();
      final source = await _service();
      await target.start();
      await source.store.accounts.remember(SiteIds.bilibili, uid: 7, name: 'Fake Seven', cookie: 'SESSDATA=fake-7');
      await source.store.accounts.remember(SiteIds.bilibili, uid: 8, name: 'Fake Eight', cookie: 'SESSDATA=fake-8');
      await source.store.secrets.setCookie(SiteIds.bilibili, 'SESSDATA=fake-7');
      await target.store.accounts.remember(SiteIds.bilibili, uid: 3, name: 'Fake Three', cookie: 'SESSDATA=fake-3');
      await target.store.secrets.setCookie(SiteIds.bilibili, 'SESSDATA=fake-3');
      List<int> remembered() => [for (final account in target.store.accounts.of(SiteIds.bilibili)) account.uid];

      // Off by default: nothing of the sign-ins leaves the device.
      expect(jsonEncode(await source.outgoing()), isNot(contains('fake-')));
      expect(await source.send('127.0.0.1', target.port, target.pairingCode), isTrue);
      expect(remembered(), [3]);
      expect(target.store.secrets.cookieFor(SiteIds.bilibili), 'SESSDATA=fake-3');

      source.includeAccounts = true;
      final withoutAccounts = SyncPart.values.toSet()..remove(SyncPart.accounts);
      expect(await source.send('127.0.0.1', target.port, target.pairingCode, parts: withoutAccounts), isTrue);
      expect(remembered(), [3], reason: '"账号 Cookie" not ticked');

      expect(await source.send('127.0.0.1', target.port, target.pairingCode, parts: {SyncPart.accounts}), isTrue);
      expect(target.store.secrets.cookieFor(SiteIds.bilibili), 'SESSDATA=fake-7');
      expect(remembered().toSet(), {3, 7, 8});
    }),
  );

  test('a received backup applies only the ticked parts', () async {
    final target = await _service();
    final source = await _service();
    await _fill(target.store, room: '1', word: 'spoiler', splash: true);
    await _fill(source.store, room: '2', word: 'noise', splash: false);
    final settings = await BackupService(source.store).exportAll();
    expect(await target.apply(settings, parts: {SyncPart.settings, SyncPart.follows}), isTrue);
    expect(await _follows(target.store), ['2']);
    expect(target.store.settings.get(Settings.showSplashPage), isFalse);
    expect(await target.store.blockLists.list(BlockKind.keyword), ['spoiler']);
  });
}

/// The page's service with the network calls recorded (sends and fetches
/// answer what the test sets).
final class _FakeSync extends RemoteSyncService {
  new(super.store, {List<String> ips = const ['192.168.1.100']}) : super(localIps: () => ips);

  final List<(String, int, String)> sent = [];
  final List<(String, int, String)> fetched = [];
  Map<String, Object?>? remote;
  Map<String, Object?>? applied;

  /// Whether the other device takes parts (a v4 device); false is 3.x.
  bool partial = false;

  /// The parts of the last send and apply; null for a whole one.
  Set<SyncPart>? sentParts;
  Set<SyncPart>? appliedParts;

  @override
  Future<bool> takesParts(String ip, int port) async => partial;

  @override
  Future<bool> send(String ip, int port, String code, {Set<SyncPart>? parts}) async {
    sent.add((ip, port, code));
    sentParts = parts;
    return true;
  }

  @override
  Future<Map<String, Object?>?> fetch(String ip, int port, String code) async {
    fetched.add((ip, port, code));
    return remote;
  }

  @override
  Future<bool> apply(Map<String, Object?> settings, {Set<SyncPart>? parts}) async {
    applied = settings;
    appliedParts = parts;
    return true;
  }
}

final RemoteSyncDevice _windows = RemoteSyncDevice(
  id: 'windows-1',
  name: 'PureLive Windows',
  platform: 'windows',
  version: '4',
  ip: '192.168.1.101',
  port: 39888,
  lastSeen: _seen,
);

final RemoteSyncDevice _legacy = RemoteSyncDevice(
  id: 'android-1',
  name: 'PureLive Android',
  platform: 'android',
  version: '1.0.0',
  ip: '192.168.1.102',
  port: 39888,
  lastSeen: _seen,
  viaMdns: true,
);

final DateTime _seen = DateTime.utc(2026, 10);

List<String> _toasts = [];

Future<_FakeSync> _pumpPage(
  WidgetTester tester, {
  Size size = const Size(393, 1600),
  List<String> ips = const ['192.168.1.100'],
  List<RemoteSyncDevice> devices = const [],
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = (await tester.runAsync(testServices))!;
  addTearDown(() => tester.runAsync(services.close));
  final strings = (await tester.runAsync(loadStrings))!;
  final toasts = <String>[];
  final previous = AppNavigator.toast;
  AppNavigator.toast = toasts.add;
  addTearDown(() => AppNavigator.toast = previous);
  _toasts = toasts;
  _FakeSync? service;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appServicesProvider.overrideWithValue(services),
        remoteSyncServiceProvider.overrideWithValue(() => service = _FakeSync(services.store, ips: ips)),
      ],
      child: LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp(
          theme: const LiveTheme(primaryColor: Colors.blue).light,
          home: const RemoteReceiverPage(route: RouteArgs(RoutePath.kRemoteSync)),
        ),
      ),
    ),
  );
  // The service opens real sockets: wait until it serves, however busy the
  // machine is (a fixed 250 ms lost the heard devices under load), then
  // let its discovery start.
  await _until(tester, () => service?.running ?? false);
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
  final started = service!;
  devices.forEach(started.heard);
  await tester.pump();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  });
  return started;
}

/// Lets the real work behind the page (its sockets, the store) finish,
/// pumping between short real waits, for up to 10 s; fixed budgets were
/// lost when the machine was busy.
Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(done(), isTrue, reason: 'still waiting after 10 s');
}

double _y(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

void _pageTests() {
  testWidgets('A04.1: with 2× text the address stays on one line', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pumpPage(tester, devices: [_windows, _legacy]);
    final address = find.byKey(const ValueKey('remote-sync-address'));
    final line = tester.getRect(address).height;
    final style = tester.widget<SelectableText>(address).style!;
    expect(line, lessThan(style.fontSize! * 2 * 2), reason: 'one line, not two');
    expect(
      tester.getRect(address).right,
      lessThanOrEqualTo(tester.getTopLeft(find.byKey(const ValueKey('remote-sync-copy'))).dx),
    );
  });

  testWidgets('phone: the note, three groups with titles outside the cards, this device, the switch', (tester) async {
    await _pumpPage(tester, devices: [_windows, _legacy]);
    expect(find.text('请确保两台设备连接到同一个局域网'), findsOneWidget);
    final groups = ['我的设备', '发现的设备', '手动输入'];
    for (var i = 1; i < groups.length; i++) {
      expect(_y(tester, find.text(groups[i])), greaterThan(_y(tester, find.text(groups[i - 1]))));
    }
    expect(_y(tester, find.text('我的设备')), lessThan(_y(tester, find.byKey(const ValueKey('remote-sync-qr')))));
    expect(
      tester.widget<SelectableText>(find.byKey(const ValueKey('remote-sync-address'))).data,
      startsWith('192.168.1.100:'),
    );
    expect(find.byKey(const ValueKey('remote-sync-copy')), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-sync-code')), findsOneWidget);
    expect(find.text('同步账号 Cookie'), findsOneWidget);
    expect(find.text('同步服务运行中'), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-sync-searching')), findsOneWidget);
    // The bar: no scanner here (no camera), start / stop.
    expect(find.byKey(const ValueKey('remote-sync-scan-bar')), findsNothing);
    expect(find.byIcon(AppIcons.syncStop), findsOneWidget);
    // The title at the start, as 3.x showed it on Android.
    expect(tester.getTopLeft(find.text('设备同步')).dx, lessThan(80));

    // Devices: platform icon, name, "address · version" (c7), a line between.
    expect(find.text('192.168.1.101:39888 · v4'), findsOneWidget);
    expect(find.text('192.168.1.102:39888 · 3.x 版本的设备'), findsOneWidget);
    final windows = find.byKey(const ValueKey('remote-sync-device-windows-1'));
    final android = find.byKey(const ValueKey('remote-sync-device-android-1'));
    expect(find.descendant(of: windows, matching: find.byIcon(AppIcons.deviceComputer)), findsOneWidget);
    expect(find.descendant(of: android, matching: find.byIcon(AppIcons.devicePhone)), findsOneWidget);
    // Every pair: receive (outlined) left, send (filled) right (c4).
    final receives = find.byKey(const ValueKey('remote-sync-receive'));
    final sends = find.byKey(const ValueKey('remote-sync-send'));
    expect(receives, findsNWidgets(3));
    expect(sends, findsNWidgets(3));
    for (var i = 0; i < 3; i++) {
      expect(tester.getCenter(receives.at(i)).dx, lessThan(tester.getCenter(sends.at(i)).dx));
      expect((tester.getCenter(receives.at(i)).dy - tester.getCenter(sends.at(i)).dy).abs(), lessThan(1));
    }
    expect(find.descendant(of: receives.first, matching: find.byIcon(AppIcons.receive)), findsOneWidget);
    expect(find.descendant(of: sends.first, matching: find.byIcon(AppIcons.send)), findsOneWidget);
  });

  testWidgets('no address: say why and what to do; stopped: the status in the error colour', (tester) async {
    await _pumpPage(tester, ips: const []);
    expect(find.byKey(const ValueKey('remote-sync-no-address')), findsOneWidget);
    expect(find.text('未获取到本机地址'), findsOneWidget);
    expect(find.textContaining('请连接 Wi-Fi 或有线网络'), findsOneWidget);
    expect(find.text('使用另一台设备扫描此二维码'), findsNothing, reason: 'nothing to scan (L4)');

    await tester.tap(find.byKey(const ValueKey('remote-sync-toggle')));
    await _until(tester, () => find.text('同步服务未运行').evaluate().isNotEmpty);
    expect(find.text('同步服务未运行'), findsOneWidget);
    final error = Theme.of(tester.element(find.text('同步服务未运行'))).colorScheme.error;
    expect(tester.widget<Text>(find.text('同步服务未运行')).style?.color, error);
    expect(find.byIcon(AppIcons.syncStart), findsOneWidget);
    expect(find.text('未发现其他设备'), findsOneWidget);
  });

  testWidgets('send: names the device and what happens, then its code in six boxes (c3)', (tester) async {
    final service = await _pumpPage(tester, devices: [_windows]);
    await tester.tap(find.byKey(const ValueKey('remote-sync-send')).first);
    await _until(tester, () => find.byType(Checkbox).evaluate().isNotEmpty);
    await _frames(tester);
    expect(find.text('确定要将当前设备的全部配置发送到“PureLive Windows”吗？对方确认后会覆盖它的配置。'), findsOneWidget);
    // A device that does not take parts (3.x): every box ticked and fixed (J05.1).
    expect(find.text('对方是 3.x 或较早的版本（或者暂时没有回应），只能发送全部内容。'), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-sync-part-all')), findsNothing);
    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(boxes, hasLength(7));
    expect(boxes.every((box) => box.value == true && box.onChanged == null), isTrue);
    await tester.tap(find.text('发送'));
    await _frames(tester);
    expect(find.text('输入“PureLive Windows”上显示的 6 位配对码'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('remote-sync-code-field')), '4829');
    await tester.pump();
    expect(find.text('4'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('remote-sync-code-field')), '482916');
    // The main button says what it does (U.1d; not "确认").
    expect(
      find.descendant(of: find.byKey(const ValueKey('remote-sync-code-ok')), matching: find.text('发送')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('remote-sync-code-ok')));
    await _frames(tester);
    expect(service.sent, [('192.168.1.101', 39888, '482916')]);
    expect(service.sentParts, isNull, reason: 'the whole packet, as 3.x expects');
    expect(_toasts, ['配置发送成功']);
  });

  testWidgets('send to a v4 device: each part ticked with its count; "全选" clears them (J05.1)', (tester) async {
    final service = await _pumpPage(tester, devices: [_windows])
      ..partial = true;
    await tester.runAsync(() async {
      await service.store.follows.replaceAll([_room('1'), _room('2')]);
      await service.store.blockLists.replaceAll(BlockKind.keyword, ['spoiler']);
    });
    await tester.tap(find.byKey(const ValueKey('remote-sync-send')).first);
    await _until(tester, () => find.byKey(const ValueKey('remote-sync-part-all')).evaluate().isNotEmpty);
    await _frames(tester);
    expect(find.text('勾选要发送到“PureLive Windows”的内容。对方确认后，勾选的内容会替换它原有的，没勾的保持不变。'), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-sync-parts-note')), findsNothing);
    expect(find.text('关注的直播间（2）'), findsOneWidget);
    expect(find.text('屏蔽词（1）'), findsOneWidget);
    expect(find.textContaining('设置（'), findsOneWidget);
    expect(find.text('账号 Cookie（0）'), findsNothing, reason: 'accounts only with "同步账号 Cookie"');
    Checkbox box(String part) => tester.widget<Checkbox>(
      find.descendant(of: find.byKey(ValueKey('remote-sync-part-$part')), matching: find.byType(Checkbox)),
    );
    // Rows from the top: settings, then the lists in the backup's order.
    expect(
      _y(tester, find.byKey(const ValueKey('remote-sync-part-settings'))),
      lessThan(_y(tester, find.byKey(const ValueKey('remote-sync-part-follows')))),
    );
    for (final part in ['settings', 'follows', 'areas', 'history', 'tags', 'keywords', 'users']) {
      expect(box(part).value, isTrue, reason: '$part ticked to start with');
    }
    DialogActionButton send() => tester.widget<DialogActionButton>(find.byKey(const ValueKey('remote-sync-confirm')));

    await tester.tap(find.byKey(const ValueKey('remote-sync-part-all')));
    await tester.pump();
    expect(box('follows').value, isFalse);
    expect(send().onPressed, isNull, reason: 'nothing to send');
    await tester.tap(find.byKey(const ValueKey('remote-sync-part-follows')));
    await tester.pump();
    expect(box('follows').value, isTrue);
    expect(
      tester
          .widget<Checkbox>(
            find.descendant(of: find.byKey(const ValueKey('remote-sync-part-all')), matching: find.byType(Checkbox)),
          )
          .value,
      isNull,
      reason: 'some ticked',
    );
    await tester.tap(find.byKey(const ValueKey('remote-sync-confirm')));
    await _frames(tester);
    await tester.enterText(find.byKey(const ValueKey('remote-sync-code-field')), '482916');
    await tester.tap(find.byKey(const ValueKey('remote-sync-code-ok')));
    await _frames(tester);
    expect(service.sent, [('192.168.1.101', 39888, '482916')]);
    expect(service.sentParts, {SyncPart.follows});
  });

  testWidgets('D08.1 c4: the local history is offered unticked; left so, the rest goes whole', (tester) async {
    final service = await _pumpPage(tester, devices: [_windows])
      ..partial = true;
    await tester.runAsync(() async {
      await service.store.follows.replaceAll([_room('1')]);
      await service.store.localEvents.add(
        LocalEvent(at: DateTime(2026, 10, 9, 20), kind: LocalEventKind.recharge, coins: 500),
      );
    });
    await tester.tap(find.byKey(const ValueKey('remote-sync-send')).first);
    await _until(tester, () => find.byKey(const ValueKey('remote-sync-part-all')).evaluate().isNotEmpty);
    await _frames(tester);
    Checkbox box(String part) => tester.widget<Checkbox>(
      find.descendant(of: find.byKey(ValueKey('remote-sync-part-$part')), matching: find.byType(Checkbox)),
    );
    expect(find.text('本地互动记录（1）'), findsOneWidget);
    expect(box('localEvents').value, isFalse, reason: "this device's own unless ticked");
    expect(box('follows').value, isTrue);
    await tester.tap(find.byKey(const ValueKey('remote-sync-confirm')));
    await _frames(tester);
    await tester.enterText(find.byKey(const ValueKey('remote-sync-code-field')), '482916');
    await tester.tap(find.byKey(const ValueKey('remote-sync-code-ok')));
    await _frames(tester);
    expect(service.sentParts, isNotNull);
    expect(service.sentParts, isNot(contains(SyncPart.localEvents)));
    expect(service.sentParts, containsAll([SyncPart.settings, SyncPart.follows, SyncPart.history]));
  });

  testWidgets('landscape phone with 1.3× text: the parts scroll, the buttons stay on screen (J05.1)', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    (await _pumpPage(tester, size: const Size(852, 393), devices: [_windows])).partial = true;
    await tester.ensureVisible(find.byKey(const ValueKey('remote-sync-send')).first);
    await tester.tap(find.byKey(const ValueKey('remote-sync-send')).first);
    await _until(tester, () => find.byKey(const ValueKey('remote-sync-part-all')).evaluate().isNotEmpty);
    await _frames(tester);
    expect(tester.takeException(), isNull);
    final button = tester.getRect(find.byKey(const ValueKey('remote-sync-confirm')));
    expect(button.bottom, lessThanOrEqualTo(393));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('remote-sync-part-users')),
      50,
      scrollable: find.descendant(of: find.byType(AppDialog), matching: find.byType(Scrollable)).first,
    );
    expect(tester.getRect(find.byKey(const ValueKey('remote-sync-part-users'))).bottom, lessThan(button.top));
  });

  testWidgets('send to a v4 device with every box ticked sends everything; cancel sends nothing', (tester) async {
    final service = await _pumpPage(tester, devices: [_windows])
      ..partial = true;
    await tester.tap(find.byKey(const ValueKey('remote-sync-send')).first);
    await _until(tester, () => find.byKey(const ValueKey('remote-sync-part-all')).evaluate().isNotEmpty);
    await _frames(tester);
    await tester.tap(find.text('取消'));
    await _frames(tester);
    expect(service.sent, isEmpty);

    await tester.tap(find.byKey(const ValueKey('remote-sync-send')).first);
    await _until(tester, () => find.byKey(const ValueKey('remote-sync-part-all')).evaluate().isNotEmpty);
    await _frames(tester);
    await tester.tap(find.byKey(const ValueKey('remote-sync-confirm')));
    await _frames(tester);
    await tester.enterText(find.byKey(const ValueKey('remote-sync-code-field')), '482916');
    await tester.tap(find.byKey(const ValueKey('remote-sync-code-ok')));
    await _frames(tester);
    expect(service.sentParts, containsAll(syncPartsIn(await tester.runAsync(service.outgoing) ?? const {})));
  });

  testWidgets('receive: the code, then what changes, then it applies (c2, S1)', (tester) async {
    final service = await _pumpPage(tester, devices: [_windows]);
    service.remote = {
      'backupVersion': 3,
      'favorite': {
        'favoriteRooms': [LiveRoom(platform: 'douyu', roomId: '9', title: 't', nick: 'n').toJson()],
      },
    };
    await tester.tap(find.byKey(const ValueKey('remote-sync-receive')).first);
    await _frames(tester);
    expect(find.text('输入“PureLive Windows”上显示的 6 位配对码'), findsOneWidget, reason: 'no question before the code');
    await tester.enterText(find.byKey(const ValueKey('remote-sync-code-field')), '123456');
    // The main button says what it does (U.1d; not "确认").
    expect(
      find.descendant(of: find.byKey(const ValueKey('remote-sync-code-ok')), matching: find.text('接收')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('remote-sync-code-ok')));
    await _until(tester, () => find.byKey(const ValueKey('remote-sync-preview')).evaluate().isNotEmpty);
    await _frames(tester);
    expect(service.fetched, [('192.168.1.101', 39888, '123456')]);
    expect(service.applied, isNull, reason: 'nothing changes before the preview is accepted');
    expect(find.byKey(const ValueKey('remote-sync-preview')), findsOneWidget);
    expect(find.text('来自 PureLive Windows'), findsOneWidget);
    expect(find.text('192.168.1.101:39888 · v4'), findsNWidgets(2));
    expect(find.text('接收后会这样变化：'), findsOneWidget);
    expect(find.text('关注的直播间：0 → 1（新增 1，移除 0）'), findsOneWidget);
    expect(find.text('账号：对方没有开“同步账号 Cookie”，本机账号不变'), findsOneWidget);
    expect(find.textContaining('接收会替换勾选的内容，没勾的保持不变'), findsOneWidget);
    // One part: its box, no "全选" (J05.1).
    expect(find.byKey(const ValueKey('remote-sync-part-all')), findsNothing);
    expect(find.byKey(const ValueKey('remote-sync-part-follows')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remote-sync-receive-confirm')));
    await _frames(tester);
    expect(service.applied, isNotNull);
    expect(service.appliedParts, {SyncPart.follows});
    expect(_toasts, ['配置接收成功']);
  });

  testWidgets('receive: every part the other device sent has a box; only the ticked ones apply (J05.1)', (
    tester,
  ) async {
    final service = await _pumpPage(tester, devices: [_windows]);
    final source = (await tester.runAsync(() => LiveStore.memory(cipher: FakeCipher())))!;
    addTearDown(() => tester.runAsync(source.close));
    service.remote = await tester.runAsync(() async {
      await _fill(source, room: '9', word: 'noise', splash: false);
      return await BackupService(source).exportAll(includeSensitiveData: true);
    });
    await tester.tap(find.byKey(const ValueKey('remote-sync-receive')).first);
    await _frames(tester);
    await tester.enterText(find.byKey(const ValueKey('remote-sync-code-field')), '123456');
    await tester.tap(find.byKey(const ValueKey('remote-sync-code-ok')));
    await _until(tester, () => find.byKey(const ValueKey('remote-sync-preview')).evaluate().isNotEmpty);
    await _frames(tester);
    for (final part in ['all', 'settings', 'follows', 'keywords', 'users', 'webdav', 'accounts']) {
      expect(find.byKey(ValueKey('remote-sync-part-$part')), findsOneWidget, reason: part);
    }
    expect(find.text('账号：对方没有登录信息，接收后本机的平台登录会被清空'), findsOneWidget);
    expect(find.text('账号：对方没有开“同步账号 Cookie”，本机账号不变'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('remote-sync-part-keywords')));
    await tester.tap(find.byKey(const ValueKey('remote-sync-part-accounts')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('remote-sync-receive-confirm')));
    await _frames(tester);
    expect(service.appliedParts, isNot(contains(SyncPart.keywords)));
    expect(service.appliedParts, isNot(contains(SyncPart.accounts)));
    expect(service.appliedParts, containsAll([SyncPart.settings, SyncPart.follows, SyncPart.webdav]));
  });

  testWidgets('another device sends: what changes, a box per part, "拒绝" / "允许" (J05.1)', (tester) async {
    final service = await _pumpPage(tester, devices: [_windows]);
    final settings = {
      'backupVersion': 4,
      'app': {'showSplashPage': false},
      'favorite': {
        'favoriteRooms': [_room('9').toJson()],
        'shieldList': ['noise'],
      },
    };
    var answer = service.chooseImport!('192.168.1.101', settings);
    await _until(tester, () => find.byKey(const ValueKey('remote-sync-incoming')).evaluate().isNotEmpty);
    await _frames(tester);
    expect(find.text('设备 192.168.1.101（PureLive Windows）请求用它的设置覆盖本机设置，是否允许？'), findsOneWidget);
    expect(find.text('关注的直播间：0 → 1（新增 1，移除 0）'), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-sync-part-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-sync-part-keywords')), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await _frames(tester);
    expect(
      find.byKey(const ValueKey('remote-sync-incoming')),
      findsOneWidget,
      reason: 'a tap outside does not close it',
    );
    await tester.tap(find.byKey(const ValueKey('remote-sync-reject')));
    await _frames(tester);
    expect(await answer, isNull);

    answer = service.chooseImport!('192.168.1.101', settings);
    await _until(tester, () => find.byKey(const ValueKey('remote-sync-incoming')).evaluate().isNotEmpty);
    await _frames(tester);
    await tester.tap(find.byKey(const ValueKey('remote-sync-part-settings')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('remote-sync-allow')));
    await _frames(tester);
    expect(await answer, {SyncPart.follows, SyncPart.keywords});
  });

  testWidgets('another device asks: its name, "拒绝" / "允许", no closing outside (c8)', (tester) async {
    final service = await _pumpPage(tester, devices: [_windows]);
    final answer = service.confirm!('export', '192.168.1.101');
    await _frames(tester);
    expect(find.text('设备 192.168.1.101（PureLive Windows）请求读取本机设置，是否允许？'), findsOneWidget);
    expect(tester.getCenter(find.text('拒绝')).dx, lessThan(tester.getCenter(find.text('允许')).dx));
    await tester.tapAt(const Offset(5, 5));
    await _frames(tester);
    expect(
      find.byKey(const ValueKey('remote-sync-incoming')),
      findsOneWidget,
      reason: 'a tap outside does not close it',
    );
    await tester.tap(find.text('拒绝'));
    await _frames(tester);
    expect(await answer, isFalse);
  });

  testWidgets('phones: the bar scans the other device, then asks which way (3.x)', (tester) async {
    FakeQrCamera.install();
    addTearDown(FakeQrCamera.uninstall);
    final service = await _pumpPage(tester);
    final scan = find.byKey(const ValueKey('remote-sync-scan-bar'));
    expect(tester.getCenter(scan).dx, lessThan(tester.getCenter(find.byKey(const ValueKey('remote-sync-toggle'))).dx));
    await tester.tap(scan);
    await _frames(tester);
    expect(find.text('扫描另一台设备“设备同步”页上的二维码'), findsOneWidget);
    expect(find.text('手动输入地址'), findsOneWidget);
    FakeQrCamera.last!.read('purelive://192.168.1.5:39888/sync?code=012345');
    await _frames(tester);
    expect(find.byKey(const ValueKey('remote-sync-direction')), findsOneWidget);
    expect(find.text('选择同步操作'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remote-sync-direction-send')));
    await _until(tester, () => find.text('发送').evaluate().isNotEmpty);
    await _frames(tester);
    await tester.tap(find.text('发送'));
    await _frames(tester);
    expect(service.sent, [('192.168.1.5', 39888, '012345')], reason: 'the code came with the QR code');

    // "手动输入地址" goes back to the field.
    await tester.tap(scan);
    await _frames(tester);
    await tester.tap(find.text('手动输入地址'));
    await _frames(tester);
    expect(find.byType(QrScanPage), findsNothing);
    final field = tester.widget<TextField>(find.byKey(const ValueKey('remote-sync-target')));
    expect(field.focusNode?.hasFocus, isTrue);
  });

  testWidgets('wide: two columns, this device on the left (S2)', (tester) async {
    await _pumpPage(tester, size: const Size(1280, 800), devices: [_windows]);
    final mine = tester.getTopLeft(find.text('我的设备'));
    final found = tester.getTopLeft(find.text('发现的设备'));
    expect(found.dx, greaterThan(mine.dx + 400));
    expect((found.dy - mine.dy).abs(), lessThan(1));
    expect(_y(tester, find.text('手动输入')), greaterThan(found.dy));
  });

  testWidgets('landscape phone: one column at most 720, a 48 bar', (tester) async {
    await _pumpPage(tester, size: const Size(852, 393));
    final mine = tester.getTopLeft(find.text('我的设备'));
    final found = tester.getTopLeft(find.text('发现的设备'));
    expect((found.dx - mine.dx).abs(), lessThan(1));
    expect(found.dy, greaterThan(mine.dy));
    expect(tester.getSize(find.byType(AppBar)).height, 48);
  });
}

/// Frames for half a second (the search spinner never settles).
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
