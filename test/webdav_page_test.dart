import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/backup_controller.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings/theme_settings_controller.dart';
import 'package:pure_live/common/services/settings/web_dav_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/services/utils/hive_rx.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/web_dav/web_dav_controller.dart';
import 'package:pure_live/modules/web_dav/web_dav_page.dart';
import 'package:pure_live/modules/web_dav/webdav_config.dart';
import 'package:pure_live/modules/web_dav/webdav_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Map<String, dynamic> translations;
  late WebDavPageController controller;
  late _Service service;
  late _BackupController backup;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('webdav-page-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Hive.init(directory.path);
    await HivePrefUtil.init();
    translations = jsonDecode(await File('assets/translations/zh.json').readAsString()) as Map<String, dynamic>;
  });

  setUp(() {
    Get.testMode = true;
    final settings = Get.put(WebDavController());
    settings.currentWebDavConfig.v = '';
    settings.webDavConfigs.v = [];
    backup = _BackupController();
    Get.put<BackupController>(backup);
    Get.put<SettingsService>(_SettingsService());
    Get.put(ThemeSettingsController());
    service = _Service();
    controller = Get.put(WebDavPageController(serviceFactory: (_) => service));
  });

  tearDown(() {
    Get.deleteAll(force: true);
    Get.reset();
    service.close();
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> openPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('zh')],
        path: 'assets/translations',
        assetLoader: _MemoryAssetLoader(translations),
        child: Builder(
          builder: (context) => GetMaterialApp(
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            builder: FlutterSmartDialog.init(),
            home: const WebDavPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    final exception = tester.takeException();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(exception, isNull);
  }

  void selectConfig() {
    const config = WebDAVConfig(name: 'fixture', address: 'http://127.0.0.1', username: '', password: '');
    controller.configs.assignAll([config]);
    controller.currentConfig.value = config;
    controller.initializeWebDAV();
  }

  testWidgets('no-config menu refresh preserves the create action and starts no network request', (tester) async {
    await openPage(tester);
    expect(find.text('创建新配置'), findsOneWidget);
    expect(tester.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed, isNull);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('刷新'));
    await tester.pumpAndSettle();
    expect(find.text('创建新配置'), findsOneWidget);
    expect(controller.errorMessage.value, isEmpty);
    expect(service.reads, isEmpty);
    await finish(tester);
  });

  testWidgets('empty successful directory has an explicit normal state', (tester) async {
    await openPage(tester);
    selectConfig();
    await tester.pump();
    expect(controller.isLoading.value, isTrue);
    service.reads.single.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('暂无数据'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    await finish(tester);
  });

  testWidgets('directory error exposes a working inline retry', (tester) async {
    await openPage(tester);
    selectConfig();
    service.reads.single.completeError(StateError('fixture failure'));
    await tester.pumpAndSettle();
    expect(find.textContaining('fixture failure'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(service.reads, hasLength(2));
    service.reads.last.complete([]);
    await tester.pumpAndSettle();
    expect(find.textContaining('fixture failure'), findsNothing);
    expect(find.text('暂无数据'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('removing the selected configuration clears its error and restores setup', (tester) async {
    await openPage(tester);
    selectConfig();
    service.reads.single.completeError(StateError('fixture failure'));
    await tester.pumpAndSettle();
    controller.currentConfig.value = null;
    controller.configs.clear();
    controller.initializeWebDAV();
    await tester.pumpAndSettle();
    expect(find.text('创建新配置'), findsOneWidget);
    expect(find.textContaining('fixture failure'), findsNothing);
    await finish(tester);
  });

  testWidgets('active download waits for local restore before showing success', (tester) async {
    await openPage(tester);
    selectConfig();
    service.reads.single.complete([]);
    await tester.pumpAndSettle();
    var operationFinished = false;
    unawaited(
      controller.downloadFile(webdav.File(path: '/backup.txt', isDir: false)).then((_) => operationFinished = true),
    );
    await tester.pump();
    expect(backup.restores, [
      {'backupVersion': 3},
    ]);
    expect(find.text('同步成功'), findsNothing);
    backup.restore.complete();
    await tester.pumpAndSettle();
    final successCount = find.text('同步成功').evaluate().length;
    await finish(tester);
    expect(operationFinished, isTrue);
    expect(successCount, 1);
  });
}

class _MemoryAssetLoader extends AssetLoader {
  _MemoryAssetLoader(this.data);
  final Map<String, dynamic> data;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => data;
}

class _SettingsService extends SettingsService {
  final _font = FontSettingsController();

  @override
  FontSettingsController get font => _font;

  @override
  // Only the font used by the real page is needed; avoid app-wide startup IO.
  // ignore: must_call_super
  void onInit() {}
}

class _Service extends WebDAVService {
  _Service() : super(url: 'http://127.0.0.1', username: '', password: '');
  final reads = <Completer<List<webdav.File>>>[];

  @override
  Future<List<webdav.File>> readDirectory(String path) {
    final pending = Completer<List<webdav.File>>();
    reads.add(pending);
    return pending.future;
  }

  @override
  Future<List<int>> readFile(String path) async => utf8.encode('{"backupVersion":3}');
}

class _BackupController extends BackupController {
  final restores = <Map<String, dynamic>>[];
  late Completer<void> restore;

  @override
  Future<void> restoreAllSettings(Map<String, dynamic> data) {
    restores.add(data);
    // Create the future in the widget test's clock, not setUp's root zone.
    restore = Completer<void>();
    return restore.future;
  }
}
