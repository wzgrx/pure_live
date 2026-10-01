import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/remote_receiver/remote_receiver_page.dart';
import 'package:pure_live/features/remote_receiver/remote_sync_protocol.dart';
import 'package:pure_live/features/remote_receiver/remote_sync_service.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

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
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.textContaining('192.168.7.8:'), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-sync-qr')), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-sync-code')), findsOneWidget);
    expect(find.text('同步服务运行中'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('remote-sync-toggle')));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.text('同步服务未运行'), findsOneWidget);
    expect(find.byKey(const ValueKey('remote-sync-code')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  });
}
