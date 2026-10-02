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

/// The page's service with the network calls recorded (sends and fetches
/// answer what the test sets).
final class _FakeSync extends RemoteSyncService {
  new(super.store, {List<String> ips = const ['192.168.1.100']}) : super(localIps: () => ips);

  final List<(String, int, String)> sent = [];
  final List<(String, int, String)> fetched = [];
  Map<String, Object?>? remote;
  Map<String, Object?>? applied;

  @override
  Future<bool> send(String ip, int port, String code) async {
    sent.add((ip, port, code));
    return true;
  }

  @override
  Future<Map<String, Object?>?> fetch(String ip, int port, String code) async {
    fetched.add((ip, port, code));
    return remote;
  }

  @override
  Future<bool> apply(Map<String, Object?> settings) async {
    applied = settings;
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
    await _frames(tester);
    expect(find.text('确定要将当前设备的全部配置发送到“PureLive Windows”吗？对方确认后会覆盖它的配置。'), findsOneWidget);
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
    expect(_toasts, ['配置发送成功']);
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
    expect(find.textContaining('接收会替换上面列出的内容，无法撤销'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remote-sync-receive-confirm')));
    await _frames(tester);
    expect(service.applied, isNotNull);
    expect(_toasts, ['配置接收成功']);
  });

  testWidgets('another device asks: its name, "拒绝" / "允许", no closing outside (c8)', (tester) async {
    final service = await _pumpPage(tester, devices: [_windows]);
    final answer = service.confirm!('import', '192.168.1.101');
    await _frames(tester);
    expect(find.text('设备 192.168.1.101（PureLive Windows）请求用它的设置覆盖本机设置，是否允许？'), findsOneWidget);
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
