import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/backup/scan_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;
  late Map<String, dynamic> english;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-scan-page-test-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    english = jsonDecode(await File('assets/translations/en.json').readAsString()) as Map<String, dynamic>;
    Hive.init(hiveDirectory.path);
    await Hive.openBox<dynamic>('app_settings', bytes: Uint8List(0));
    await HivePrefUtil.init();
  });

  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    Get.put(SettingsService());
  });

  tearDown(Get.reset);

  tearDownAll(() async {
    await Hive.close().timeout(const Duration(seconds: 10));
    await hiveDirectory.delete(recursive: true);
  });

  test('server origins are normalized without accepting request components', () {
    expect(normalizeScanSyncAddress(' HTTPS://TV.Example.com/ '), 'https://tv.example.com');
    expect(normalizeScanSyncAddress('http://192.168.1.20:8787'), 'http://192.168.1.20:8787');
    expect(normalizeScanSyncAddress('https://[2001:db8::1]:8443/'), 'https://[2001:db8::1]:8443');

    for (final value in <String?>[
      null,
      '',
      'tv.example.com',
      'https://user@tv.example.com',
      'https://tv.example.com/path',
      'https://tv.example.com?token=secret',
      'https://tv.example.com#fragment',
      'https://tv.example.com:0',
      'https://tv.example.com:65536',
      'https://tv.\nexample.com',
    ]) {
      expect(normalizeScanSyncAddress(value), isNull, reason: '$value');
    }
  });

  testWidgets('empty and null barcode payloads keep scanning without throwing', (tester) async {
    late ScanCodeDetector detect;
    var calls = 0;
    await _pumpPage(
      tester,
      english,
      page: ScanCodePage(
        scannerBuilder: (context, controller, callback) {
          detect = callback;
          return const ColoredBox(key: ValueKey('scanner'), color: Colors.black);
        },
        controllerFactory: _controllerFactory(<_TrackingScannerController>[]),
        syncSettings: (address) async {
          calls++;
          return false;
        },
      ),
    );

    await expectLater(detect(const BarcodeCapture()), completes);
    await expectLater(detect(const BarcodeCapture(barcodes: [Barcode()])), completes);
    await tester.pump();

    expect(calls, 0);
    expect(find.byKey(const ValueKey('scanner')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only an exact HTTP server origin starts synchronization', (tester) async {
    late ScanCodeDetector detect;
    final addresses = <String>[];
    await _pumpPage(
      tester,
      english,
      page: ScanCodePage(
        scannerBuilder: (context, controller, callback) {
          detect = callback;
          return const ColoredBox(key: ValueKey('scanner'), color: Colors.black);
        },
        controllerFactory: _controllerFactory(<_TrackingScannerController>[]),
        syncSettings: (address) async {
          addresses.add(address);
          return false;
        },
      ),
    );

    for (final value in [
      'Open https://tv.example.com now',
      'https://user@tv.example.com',
      'https://tv.example.com/path',
      'https://tv.example.com?token=secret',
      'ftp://tv.example.com',
    ]) {
      await detect(BarcodeCapture(barcodes: [Barcode(rawValue: value)]));
    }
    await tester.pump();
    expect(addresses, isEmpty);
    expect(find.byKey(const ValueKey('scanner')), findsOneWidget);

    await detect(
      const BarcodeCapture(
        barcodes: [
          Barcode(rawValue: 'not an origin'),
          Barcode(rawValue: ' HTTPS://TV.Example.com/ '),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(addresses, ['https://tv.example.com']);
    expect(find.text('Sync failed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated frames share one synchronization transaction', (tester) async {
    late ScanCodeDetector detect;
    final gate = Completer<bool>();
    var calls = 0;
    await _pumpPage(
      tester,
      english,
      page: ScanCodePage(
        scannerBuilder: (context, controller, callback) {
          detect = callback;
          return const ColoredBox(key: ValueKey('scanner'), color: Colors.black);
        },
        controllerFactory: _controllerFactory(<_TrackingScannerController>[]),
        syncSettings: (address) {
          calls++;
          return gate.future;
        },
      ),
    );

    final first = detect(const BarcodeCapture(barcodes: [Barcode(rawValue: 'http://192.168.1.20:8787')]));
    final duplicate = detect(const BarcodeCapture(barcodes: [Barcode(rawValue: 'http://192.168.1.20:8787')]));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Syncing...'), findsOneWidget);

    gate.complete(true);
    await Future.wait([first, duplicate]);
    await tester.pumpAndSettle();
    expect(find.text('Sync successful'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('transfer exceptions finish as a retryable failed state', (tester) async {
    late ScanCodeDetector detect;
    await _pumpPage(
      tester,
      english,
      page: ScanCodePage(
        scannerBuilder: (context, controller, callback) {
          detect = callback;
          return const ColoredBox(key: ValueKey('scanner'), color: Colors.black);
        },
        controllerFactory: _controllerFactory(<_TrackingScannerController>[]),
        syncSettings: (address) => Future<bool>.error(StateError('fixture failure')),
      ),
    );

    await expectLater(detect(const BarcodeCapture(barcodes: [Barcode(rawValue: 'https://tv.example.com')])), completes);
    await tester.pumpAndSettle();
    expect(find.text('Sync failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry and route disposal release every scanner controller', (tester) async {
    late ScanCodeDetector detect;
    final controllers = <_TrackingScannerController>[];
    final firstDisposeGate = Completer<void>();
    await _pumpPage(
      tester,
      english,
      page: ScanCodePage(
        scannerBuilder: (context, controller, callback) {
          detect = callback;
          return const ColoredBox(key: ValueKey('scanner'), color: Colors.black);
        },
        controllerFactory: _controllerFactory(controllers, firstDisposeGate: firstDisposeGate),
        syncSettings: (address) async => false,
      ),
    );

    await detect(const BarcodeCapture(barcodes: [Barcode(rawValue: 'https://tv.example.com')]));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed, isNull);
    expect(find.descendant(of: find.byType(AppBar), matching: find.byType(IconButton)), findsNothing);
    expect(controllers, hasLength(1));

    firstDisposeGate.complete();
    await tester.pump();
    expect(controllers, hasLength(2));
    expect(controllers.first.disposeCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(controllers.last.disposeCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late transfer result is ignored after the route is disposed', (tester) async {
    late ScanCodeDetector detect;
    final gate = Completer<bool>();
    final controllers = <_TrackingScannerController>[];
    await _pumpPage(
      tester,
      english,
      page: ScanCodePage(
        scannerBuilder: (context, controller, callback) {
          detect = callback;
          return const ColoredBox(key: ValueKey('scanner'), color: Colors.black);
        },
        controllerFactory: _controllerFactory(controllers),
        syncSettings: (address) => gate.future,
      ),
    );

    final pending = detect(const BarcodeCapture(barcodes: [Barcode(rawValue: 'https://tv.example.com')]));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete(true);
    await expectLater(pending, completes);
    await tester.pump();

    expect(controllers.single.disposeCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scanner starts with the torch off and keeps one action per control', (tester) async {
    MobileScannerController? observed;
    final controllers = <_TrackingScannerController>[];
    await _pumpPage(
      tester,
      english,
      page: ScanCodePage(
        scannerBuilder: (context, controller, callback) {
          observed = controller;
          return const ColoredBox(key: ValueKey('scanner'), color: Colors.black);
        },
        controllerFactory: _controllerFactory(controllers),
        syncSettings: (address) async => false,
      ),
    );

    expect(controllers.single.requestedTorchEnabled, isFalse);
    observed!.value = observed!.value.copyWith(torchState: TorchState.auto, cameraDirection: CameraFacing.back);
    await tester.pump();
    expect(find.descendant(of: find.byType(AppBar), matching: find.byType(IconButton)), findsNWidgets(2));

    await tester.tap(find.byTooltip('Toggle flashlight'));
    await tester.tap(find.byTooltip('Switch camera'));
    await tester.pump();
    expect(controllers.single.toggleTorchCount, 1);
    expect(controllers.single.switchCameraCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sync result remains usable on a compact screen with large text', (tester) async {
    late ScanCodeDetector detect;
    await _pumpPage(
      tester,
      english,
      size: const Size(280, 360),
      textScale: 3,
      page: ScanCodePage(
        scannerBuilder: (context, controller, callback) {
          detect = callback;
          return const ColoredBox(key: ValueKey('scanner'), color: Colors.black);
        },
        controllerFactory: _controllerFactory(<_TrackingScannerController>[]),
        syncSettings: (address) async => false,
      ),
    );

    await detect(const BarcodeCapture(barcodes: [Barcode(rawValue: 'https://tv.example.com')]));
    await tester.pumpAndSettle();

    expect(find.text('Sync failed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.ensureVisible(find.text('Retry'));
    await tester.pumpAndSettle();
    final retryRect = tester.getRect(find.text('Retry'));
    expect(retryRect.top, greaterThanOrEqualTo(0));
    expect(retryRect.bottom, lessThanOrEqualTo(360));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('scanner')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

ScanCodeControllerFactory _controllerFactory(
  List<_TrackingScannerController> controllers, {
  Completer<void>? firstDisposeGate,
}) {
  return ({required bool torchEnabled}) {
    final controller = _TrackingScannerController(
      requestedTorchEnabled: torchEnabled,
      disposeGate: controllers.isEmpty ? firstDisposeGate : null,
    );
    controllers.add(controller);
    return controller;
  };
}

class _TrackingScannerController extends MobileScannerController {
  _TrackingScannerController({required this.requestedTorchEnabled, this.disposeGate})
    : super(autoStart: false, torchEnabled: requestedTorchEnabled);

  final bool requestedTorchEnabled;
  final Completer<void>? disposeGate;
  int disposeCount = 0;
  int toggleTorchCount = 0;
  int switchCameraCount = 0;

  @override
  Future<void> toggleTorch() async {
    toggleTorchCount++;
  }

  @override
  Future<void> switchCamera([SwitchCameraOption option = const ToggleDirection()]) async {
    switchCameraCount++;
  }

  @override
  // The test double records ownership without opening a platform camera.
  // ignore: must_call_super
  Future<void> dispose() async {
    disposeCount++;
    await disposeGate?.future;
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  Map<String, dynamic> english, {
  required ScanCodePage page,
  Size size = const Size(320, 480),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      startLocale: const Locale('en'),
      fallbackLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: _Translations(english),
      child: Builder(
        builder: (context) => GetMaterialApp(
          locale: context.locale,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: page,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Translations extends AssetLoader {
  const _Translations(this.english);

  final Map<String, dynamic> english;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => english;
}
