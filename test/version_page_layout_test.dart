import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/app_settings_controller.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings/theme_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/common/utils/version_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/version/version_controller.dart';
import 'package:pure_live/modules/version/version_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-version-page-test-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Hive.init(hiveDirectory.path);
    await HivePrefUtil.init();
  });

  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    final settings = _TestSettingsService();
    settings.app.useGitHubOriginForUpdates.value = true;
    Get.put<SettingsService>(settings);
  });

  tearDown(Get.reset);

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('Windows update actions remain reachable at 320x480 with 3x text', (tester) async {
    if (!Platform.isWindows) return;
    String? clipboardText;
    String? downloadedUrl;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final controller = _TestVersionController()
      ..loading.value = false
      ..windowsSetupUrl.value = 'https://example.test/PureLive-3.2.0-5000-windows-x64-setup.exe'
      ..windowsPortableUrl.value = 'https://example.test/PureLive-3.2.0-5000-windows-x64-portable.zip';
    Get.put<VersionController>(controller);
    VersionUtil.latestUpdateLog = '# Changes\n\nResponsive update-page fixture.';

    await _pumpPage(
      tester,
      size: const Size(320, 480),
      textScale: 3,
      downloadRelease: (url, {fileName}) async => downloadedUrl = url,
    );
    final sourceAction = find.byKey(const ValueKey('version-source-EXE Installer-0'));
    final pageScroll = find
        .descendant(of: find.byKey(const ValueKey('version-update-scroll')), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(sourceAction, -200, scrollable: pageScroll, maxScrolls: 20);
    await tester.pumpAndSettle();
    expect(sourceAction.hitTestable(), findsOneWidget);
    await tester.tap(sourceAction);
    await tester.pumpAndSettle();

    final copyAction = find.byKey(const ValueKey('version-source-copy'));
    expect(copyAction, findsOneWidget);
    expect(find.byKey(const ValueKey('version-source-download')), findsOneWidget);
    expect(find.byKey(const ValueKey('version-source-cancel')), findsOneWidget);
    await tester.ensureVisible(copyAction);
    await tester.pumpAndSettle();
    expect(copyAction.hitTestable(), findsOneWidget);
    await tester.tap(copyAction);
    await tester.pumpAndSettle();
    expect(clipboardText, 'https://example.test/PureLive-3.2.0-5000-windows-x64-setup.exe');
    expect(find.text('Copied to clipboard'), findsOneWidget);

    await tester.tap(sourceAction);
    await tester.pumpAndSettle();
    final downloadAction = find.byKey(const ValueKey('version-source-download'));
    await tester.ensureVisible(downloadAction);
    await tester.pumpAndSettle();
    await tester.tap(downloadAction);
    await tester.pumpAndSettle();
    expect(downloadedUrl, 'https://example.test/PureLive-3.2.0-5000-windows-x64-setup.exe');
    expect(tester.takeException(), isNull);
  });

  testWidgets('update failure remains readable and retryable at 320x480 with 3x text', (tester) async {
    final controller = _TestVersionController()
      ..loading.value = false
      ..error.value = true;
    Get.put<VersionController>(controller);

    await _pumpPage(tester, size: const Size(320, 480), textScale: 3);

    expect(find.text('Update information is unavailable'), findsOneWidget);
    expect(find.text('Check the network and update source, then try again.'), findsOneWidget);
    final retry = find.byKey(const ValueKey('version-update-retry'));
    final errorScroll = find
        .descendant(of: find.byKey(const ValueKey('version-update-error')), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(retry, -120, scrollable: errorScroll, maxScrolls: 10);
    await tester.pumpAndSettle();
    expect(retry.hitTestable(), findsOneWidget);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(controller.checkCalls, 1);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
  VersionDownloadHandler? downloadRelease,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      startLocale: const Locale('en'),
      fallbackLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: const _Translations(),
      child: Builder(
        builder: (context) => GetMaterialApp(
          locale: context.locale,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: VersionPage(downloadRelease: downloadRelease),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _TestVersionController extends VersionController {
  int checkCalls = 0;

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> checkNewVersion() async {
    checkCalls++;
  }
}

class _TestSettingsService extends SettingsService {
  _TestSettingsService()
    : _app = AppSettingsController(),
      _font = FontSettingsController(),
      _theme = ThemeSettingsController();

  final AppSettingsController _app;
  final FontSettingsController _font;
  final ThemeSettingsController _theme;

  @override
  AppSettingsController get app => _app;

  @override
  FontSettingsController get font => _font;

  @override
  ThemeSettingsController get theme => _theme;

  @override
  // Test fixture intentionally skips production service registrations.
  // ignore: must_call_super
  void onInit() {}
}

class _Translations extends AssetLoader {
  const _Translations();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => const {
    'version_update': 'Version Update',
    'windows_desc': 'For Windows desktop OS',
    'exe_installer': 'EXE Installer',
    'msix_installer': 'MSIX Installer',
    'portable_package': 'Portable ZIP',
    'update_log': 'Update Log',
    'github_origin_source': 'GitHub origin',
    'download_source': 'Source {num}',
    'download': 'Download',
    'copy_link': 'Copy Link',
    'cancel': 'Cancel',
    'done': 'Done',
    'copied_to_clipboard': 'Copied to clipboard',
    'version_update_failed_title': 'Update information is unavailable',
    'version_update_failed_subtitle': 'Check the network and update source, then try again.',
    'retry': 'Retry',
  };
}
