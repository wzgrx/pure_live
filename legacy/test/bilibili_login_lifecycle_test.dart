import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/account/bilibili/qr_login_controller.dart';
import 'package:pure_live/modules/account/bilibili/qr_login_page.dart';
import 'package:pure_live/modules/account/bilibili/web_login_controller.dart';
import 'package:pure_live/modules/account/bilibili/web_login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> english;
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-bilibili-login-test-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    english = jsonDecode(await File('assets/translations/en.json').readAsString()) as Map<String, dynamic>;
    Hive.init(hiveDirectory.path);
    await HivePrefUtil.init();
  });

  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    Get.put<SettingsService>(_TestSettingsService());
  });

  tearDown(() async {
    await HivePrefUtil.flush();
    Get.reset();
  });

  tearDownAll(() async {
    await Hive.close().timeout(const Duration(seconds: 10));
    await hiveDirectory.delete(recursive: true);
  });

  test('a refreshed QR generation ignores the older in-flight poll result', () async {
    expect(const BilibiliQrCode(key: 'key', url: 'http://fixture.test/qr').isValid, isFalse);
    var codeCalls = 0;
    final oldPoll = Completer<BilibiliQrPollResult>();
    final controller = BiliBiliQRLoginController(
      qrCodeLoader: () async {
        codeCalls++;
        return BilibiliQrCode(key: 'key-$codeCalls', url: 'https://fixture.test/qr/$codeCalls');
      },
      qrPoller: (_) => oldPoll.future,
      cookieVerifier: (_) async => false,
      completeLogin: () {},
      notice: (_) {},
      pollInterval: const Duration(days: 1),
    );
    Get.put<BiliBiliQRLoginController>(controller);
    final initialLoad = controller.loadQRCode();
    expect(identical(initialLoad, controller.loadQRCode()), isTrue);
    await initialLoad;
    expect(codeCalls, 1);
    expect(controller.qrcodeKey, 'key-1');

    final stalePoll = controller.pollQRStatus();
    await controller.loadQRCode();
    expect(controller.qrcodeKey, 'key-2');
    oldPoll.complete(const BilibiliQrPollResult(apiCode: 0, statusCode: 86038));
    await stalePoll;

    expect(controller.qrcodeKey, 'key-2');
    expect(controller.qrStatus.value, QRStatus.unscanned);
  });

  test('QR polling coalesces concurrent ticks instead of overlapping requests', () async {
    final pollResult = Completer<BilibiliQrPollResult>();
    var pollCalls = 0;
    final controller = BiliBiliQRLoginController(
      qrCodeLoader: () async => const BilibiliQrCode(key: 'key', url: 'https://fixture.test/qr'),
      qrPoller: (_) {
        pollCalls++;
        return pollResult.future;
      },
      cookieVerifier: (_) async => false,
      completeLogin: () {},
      notice: (_) {},
      pollInterval: const Duration(days: 1),
    );
    Get.put<BiliBiliQRLoginController>(controller);
    await _flushAsync();

    final first = controller.pollQRStatus();
    final second = controller.pollQRStatus();
    expect(identical(first, second), isTrue);
    expect(pollCalls, 1);
    pollResult.complete(const BilibiliQrPollResult(apiCode: 0, statusCode: 86090));
    await first;
    expect(controller.qrStatus.value, QRStatus.scanned);
  });

  test('QR success verifies one normalized Cookie before completing navigation', () async {
    final verification = Completer<bool>();
    final verifiedCookies = <String>[];
    var completionCount = 0;
    final controller = BiliBiliQRLoginController(
      qrCodeLoader: () async => const BilibiliQrCode(key: 'key', url: 'https://fixture.test/qr'),
      qrPoller: (_) async => const BilibiliQrPollResult(
        apiCode: 0,
        statusCode: 0,
        cookies: [' SESSDATA=fixture ', ' bili_jct=fixture\r\n'],
      ),
      cookieVerifier: (cookie) {
        verifiedCookies.add(cookie);
        return verification.future;
      },
      completeLogin: () => completionCount++,
      notice: (_) {},
      pollInterval: const Duration(days: 1),
    );
    Get.put<BiliBiliQRLoginController>(controller);
    await _flushAsync();

    final poll = controller.pollQRStatus();
    await _flushAsync();
    expect(controller.qrStatus.value, QRStatus.verifying);
    expect(verifiedCookies, ['SESSDATA=fixture;bili_jct=fixture']);
    verification.complete(true);
    await poll;

    expect(controller.qrStatus.value, QRStatus.verified);
    expect(completionCount, 1);
  });

  test('repeated QR transport failures stop at a visible bounded retry state', () async {
    final notices = <String>[];
    var pollCalls = 0;
    final controller = BiliBiliQRLoginController(
      qrCodeLoader: () async => const BilibiliQrCode(key: 'key', url: 'https://fixture.test/qr'),
      qrPoller: (_) async {
        pollCalls++;
        throw StateError('fixture transport failure');
      },
      cookieVerifier: (_) async => false,
      completeLogin: () {},
      notice: notices.add,
      pollInterval: const Duration(days: 1),
      maxConsecutivePollFailures: 2,
    );
    Get.put<BiliBiliQRLoginController>(controller);
    await _flushAsync();

    await controller.pollQRStatus();
    expect(controller.qrStatus.value, QRStatus.unscanned);
    await controller.pollQRStatus();
    expect(pollCalls, 2);
    expect(controller.qrStatus.value, QRStatus.failed);
    expect(controller.errorMessageKey.value, 'qr_poll_failed');
    expect(notices, ['qr_poll_failed']);
  });

  test('closing the QR controller ignores a late generation response', () async {
    final generation = Completer<BilibiliQrCode>();
    final controller = BiliBiliQRLoginController(
      qrCodeLoader: () => generation.future,
      qrPoller: (_) async => const BilibiliQrPollResult(apiCode: 0, statusCode: 86101),
      cookieVerifier: (_) async => false,
      completeLogin: () {},
      notice: (_) {},
      pollInterval: const Duration(days: 1),
    );
    Get.put<BiliBiliQRLoginController>(controller);
    Get.delete<BiliBiliQRLoginController>();
    generation.complete(const BilibiliQrCode(key: 'late', url: 'https://fixture.test/late'));
    await _flushAsync();

    expect(controller.qrcodeKey, isEmpty);
    expect(controller.qrcodeUrl.value, isEmpty);
  });

  test('closing the QR controller suppresses a late successful verification', () async {
    final verification = Completer<bool>();
    var completionCount = 0;
    final controller = BiliBiliQRLoginController(
      qrCodeLoader: () async => const BilibiliQrCode(key: 'key', url: 'https://fixture.test/qr'),
      qrPoller: (_) async => const BilibiliQrPollResult(apiCode: 0, statusCode: 0, cookies: ['SESSDATA=fixture']),
      cookieVerifier: (_) => verification.future,
      completeLogin: () => completionCount++,
      notice: (_) {},
      pollInterval: const Duration(days: 1),
    );
    Get.put<BiliBiliQRLoginController>(controller);
    await _flushAsync();

    final poll = controller.pollQRStatus();
    await _flushAsync();
    expect(controller.qrStatus.value, QRStatus.verifying);
    Get.delete<BiliBiliQRLoginController>();
    verification.complete(true);
    await poll;

    expect(completionCount, 0);
    expect(controller.qrcodeKey, isEmpty);
  });

  test('web login coalesces redirect callbacks and completes only after verification', () async {
    final cookieResult = Completer<String>();
    final verification = Completer<bool>();
    final verifiedCookies = <String>[];
    var cookieCalls = 0;
    var completionCount = 0;
    final controller = BiliBiliWebLoginController(
      cookieLoader: (_) {
        cookieCalls++;
        return cookieResult.future;
      },
      cookieVerifier: (cookie) {
        verifiedCookies.add(cookie);
        return verification.future;
      },
      completeLogin: () => completionCount++,
      openQrLogin: () async {},
      transitionDelay: Duration.zero,
    );
    Get.put<BiliBiliWebLoginController>(controller);
    final uri = WebUri('https://m.bilibili.com/');

    expect(controller.navigationPolicyFor(WebUri(bilibiliWebLoginUrl)), NavigationActionPolicy.ALLOW);
    expect(controller.navigationPolicyFor(WebUri('http://m.bilibili.com/')), NavigationActionPolicy.ALLOW);
    expect(controller.navigationPolicyFor(uri), NavigationActionPolicy.CANCEL);
    final first = controller.handleLoginRedirect(uri);
    final second = controller.handleLoginRedirect(WebUri('https://www.bilibili.com/'));
    expect(identical(first, second), isTrue);
    expect(cookieCalls, 1);
    cookieResult.complete(' \r\nSESSDATA=fixture\u0000 ');
    await _flushAsync();
    expect(controller.isVerifying.value, isTrue);
    expect(verifiedCookies, ['SESSDATA=fixture']);

    verification.complete(true);
    await first;
    expect(completionCount, 1);
    expect(controller.showWebView.value, isFalse);
    expect(controller.errorMessageKey.value, isEmpty);
  });

  test('failed web identity verification keeps the browser visible with retry feedback', () async {
    var completionCount = 0;
    final controller = BiliBiliWebLoginController(
      cookieLoader: (_) async => 'SESSDATA=fixture',
      cookieVerifier: (_) async => false,
      completeLogin: () => completionCount++,
      openQrLogin: () async {},
      transitionDelay: Duration.zero,
    );
    Get.put<BiliBiliWebLoginController>(controller);

    await controller.handleLoginRedirect(WebUri('https://m.bilibili.com/'));
    expect(completionCount, 0);
    expect(controller.showWebView.value, isTrue);
    expect(controller.isVerifying.value, isFalse);
    expect(controller.errorMessageKey.value, 'bilibili_login_verification_failed');
  });

  test('QR switch coalesces taps and supersedes a pending web verification', () async {
    final verification = Completer<bool>();
    final navigation = Completer<void>();
    var completionCount = 0;
    var navigationCount = 0;
    final controller = BiliBiliWebLoginController(
      cookieLoader: (_) async => 'SESSDATA=fixture',
      cookieVerifier: (_) => verification.future,
      completeLogin: () => completionCount++,
      openQrLogin: () {
        navigationCount++;
        return navigation.future;
      },
      transitionDelay: Duration.zero,
    );
    Get.put<BiliBiliWebLoginController>(controller);

    final login = controller.handleLoginRedirect(WebUri('https://m.bilibili.com/'));
    await _flushAsync();
    final firstSwitch = controller.toQRLogin();
    final secondSwitch = controller.toQRLogin();
    expect(identical(firstSwitch, secondSwitch), isTrue);
    await _flushAsync();
    expect(navigationCount, 1);
    expect(controller.isSwitchingToQr.value, isTrue);

    verification.complete(true);
    await login;
    expect(completionCount, 0);
    navigation.complete();
    await firstSwitch;
    expect(controller.isSwitchingToQr.value, isFalse);
    expect(controller.showWebView.value, isTrue);
  });

  test('closing web login ignores a late browser Cookie response', () async {
    final cookie = Completer<String>();
    var verificationCount = 0;
    var completionCount = 0;
    final controller = BiliBiliWebLoginController(
      cookieLoader: (_) => cookie.future,
      cookieVerifier: (_) async {
        verificationCount++;
        return true;
      },
      completeLogin: () => completionCount++,
      openQrLogin: () async {},
      transitionDelay: Duration.zero,
    );
    Get.put<BiliBiliWebLoginController>(controller);

    final login = controller.handleLoginRedirect(WebUri('https://m.bilibili.com/'));
    Get.delete<BiliBiliWebLoginController>();
    cookie.complete('SESSDATA=late');
    await login;

    expect(verificationCount, 0);
    expect(completionCount, 0);
  });

  testWidgets('QR scanned state stays reachable at 320x480 with three-times English text', (tester) async {
    final controller = BiliBiliQRLoginController(
      qrCodeLoader: () async => const BilibiliQrCode(key: 'key', url: 'https://fixture.test/qr'),
      qrPoller: (_) async => const BilibiliQrPollResult(apiCode: 0, statusCode: 86101),
      cookieVerifier: (_) async => false,
      completeLogin: () {},
      notice: (_) {},
      pollInterval: const Duration(days: 1),
    );
    Get.put<BiliBiliQRLoginController>(controller);
    await tester.pump();
    controller.qrStatus.value = QRStatus.scanned;

    await _pumpLocalizedPage(tester, english, const BiliBiliQRLoginPage());
    final status = find.text('Scanned, please confirm login on your phone');
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: find.byKey(const ValueKey('bilibili-qr-scroll-view')), matching: find.byType(Scrollable)),
    );
    await _scrollUntilHitTestable(tester, status, scrollable);
    expect(status.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    Get.delete<BiliBiliQRLoginController>();
  });

  testWidgets('web login exposes a compact disabled QR action while switching at large text', (tester) async {
    final navigation = Completer<void>();
    final controller = BiliBiliWebLoginController(
      cookieLoader: (_) async => '',
      cookieVerifier: (_) async => false,
      completeLogin: () {},
      openQrLogin: () => navigation.future,
      transitionDelay: Duration.zero,
    );
    Get.put<BiliBiliWebLoginController>(controller);
    final switchTask = controller.toQRLogin();

    await _pumpLocalizedPage(tester, english, const BiliBiliWebLoginPage());
    expect(find.byKey(const ValueKey('bilibili-web-login-qr-action')), findsOneWidget);
    expect(find.byKey(const ValueKey('bilibili-web-login-switching')), findsOneWidget);
    expect(tester.takeException(), isNull);
    navigation.complete();
    await switchTask;
  });

  testWidgets('web login error feedback wraps at 320x480 with three-times English text', (tester) async {
    final controller = BiliBiliWebLoginController(
      cookieLoader: (_) async => '',
      cookieVerifier: (_) async => false,
      completeLogin: () {},
      openQrLogin: () async {},
      transitionDelay: Duration.zero,
    );
    Get.put<BiliBiliWebLoginController>(controller);
    controller.showWebView.value = false;
    controller.errorMessageKey.value = 'bilibili_web_cookie_missing';

    await _pumpLocalizedPage(tester, english, const BiliBiliWebLoginPage());
    expect(find.byKey(const ValueKey('bilibili-web-login-error')), findsOneWidget);
    expect(find.text('The sign-in page has not produced an account Cookie yet. Continue signing in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Future<void> _scrollUntilHitTestable(WidgetTester tester, Finder target, ScrollableState scrollable) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (target.hitTestable().evaluate().isNotEmpty) return;
    final position = scrollable.position;
    final next = (position.pixels + position.viewportDimension * 0.2).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (next == position.pixels) break;
    position.jumpTo(next);
    await tester.pump();
  }
  fail('QR status did not become hit-testable after bounded page scrolling.');
}

Future<void> _pumpLocalizedPage(WidgetTester tester, Map<String, dynamic> english, Widget page) async {
  tester.view.physicalSize = const Size(320, 480);
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
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(3)),
            child: child!,
          ),
          home: page,
        ),
      ),
    ),
  );
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

class _Translations extends AssetLoader {
  const _Translations(this.english);

  final Map<String, dynamic> english;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => english;
}

class _TestSettingsService extends SettingsService {
  _TestSettingsService() : _font = FontSettingsController();

  final FontSettingsController _font;

  @override
  FontSettingsController get font => _font;

  @override
  // Test fixture intentionally skips production controller registrations.
  // ignore: must_call_super
  void onInit() {}
}
