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

  Future<void> openPage(WidgetTester tester, {Size size = const Size(360, 640), double textScale = 1}) async {
    tester.view.physicalSize = size;
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
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: FlutterSmartDialog.init()(context, child),
            ),
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

  Future<void> openCreateDialog(WidgetTester tester) async {
    await tester.tap(find.text('创建新配置'));
    await tester.pumpAndSettle();
  }

  Future<void> enterConfig(WidgetTester tester, String address) async {
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '  Form fixture  ');
    await tester.enterText(fields.at(1), address);
    await tester.enterText(fields.at(2), '  fixture-user  ');
    await tester.enterText(fields.at(3), ' fixture-password ');
  }

  Future<void> completeReads(WidgetTester tester) async {
    for (final read in service.reads) {
      if (!read.isCompleted) read.complete([]);
    }
    await tester.pumpAndSettle();
  }

  void reloadStoredSelection(String raw, List<WebDAVConfig> configs) {
    Get.delete<WebDavPageController>(force: true);
    final settings = Get.find<WebDavController>();
    settings.currentWebDavConfig.v = raw;
    settings.webDavConfigs.v = configs;
    controller = Get.put(WebDavPageController(serviceFactory: (_) => service));
  }

  testWidgets('orphan selection keeps a usable creation entry and warning after refresh with large text', (
    tester,
  ) async {
    final raw = jsonEncode(
      const WebDAVConfig(name: 'orphan', address: 'https://example.test', username: '', password: '').toJson(),
    );
    reloadStoredSelection(raw, []);
    await openPage(tester, size: const Size(320, 480), textScale: 2);
    await controller.loadFiles();
    await tester.pumpAndSettle();
    expect(find.text(translations['webdav_saved_selection_invalid']), findsOneWidget);
    expect(service.reads, isEmpty);
    expect(Get.find<WebDavController>().currentWebDavConfig.v, raw);
    await tester.ensureVisible(find.text('创建新配置'));
    await openCreateDialog(tester);
    expect(find.byType(TextFormField), findsNWidgets(4));
    await tester.tap(find.text('取消'));
    await finish(tester);
  });

  testWidgets('damaged selection offers the existing list and explicit selection clears the warning', (tester) async {
    const saved = WebDAVConfig(name: 'fixture', address: 'http://127.0.0.1', username: '', password: '');
    reloadStoredSelection('{broken', [saved]);
    await openPage(tester);
    expect(find.text(translations['webdav_saved_selection_invalid']), findsOneWidget);
    expect(service.reads, isEmpty);
    await tester.tap(find.text(translations['webdav_open_config_list']));
    await tester.pumpAndSettle();
    await tester.tap(find.text('fixture').last);
    await completeReads(tester);
    expect(controller.currentConfig.value, same(saved));
    expect(controller.configurationIssueKey.value, isEmpty);
    expect(find.text(translations['webdav_saved_selection_invalid']), findsNothing);
    expect(service.reads, hasLength(1));
    expect(jsonDecode(Get.find<WebDavController>().currentWebDavConfig.v), saved.toJson());
    await finish(tester);
  });

  testWidgets('cancelling a focused config form keeps its controllers alive through the route transition', (
    tester,
  ) async {
    await openPage(tester);
    await openCreateDialog(tester);
    await tester.enterText(find.byType(TextFormField).first, 'discarded fixture');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(controller.configs, isEmpty);
    expect(service.reads, isEmpty);
    await openCreateDialog(tester);
    expect(tester.widget<TextFormField>(find.byType(TextFormField).first).controller!.text, isEmpty);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await finish(tester);
  });

  testWidgets('malformed WebDAV address stays in the form without saving or creating a request', (tester) async {
    await openPage(tester);
    await openCreateDialog(tester);
    await enterConfig(tester, 'not-a-url');
    await tester.tap(find.text('添加'));
    await tester.pump();
    final saved = controller.configs.length;
    final requests = service.reads.length;
    final formVisible = find.byType(TextFormField).evaluate().isNotEmpty;
    if (formVisible) await tester.tap(find.text('取消'));
    await completeReads(tester);
    await finish(tester);
    expect(saved, 0);
    expect(requests, 0);
    expect(formVisible, isTrue);
  });

  testWidgets('valid config save normalizes labels but preserves password bytes', (tester) async {
    await openPage(tester);
    await openCreateDialog(tester);
    await enterConfig(tester, '  https://example.test/dav/  ');
    await tester.tap(find.text('添加'));
    await completeReads(tester);
    final saved = controller.configs.single;
    expect(saved.name, 'Form fixture');
    expect(saved.address, 'https://example.test/dav/');
    expect(saved.username, 'fixture-user');
    expect(saved.password, ' fixture-password ');
    expect(service.reads, hasLength(1));
    expect(jsonDecode(Get.find<WebDavController>().currentWebDavConfig.value), saved.toJson());
    await finish(tester);
  });

  testWidgets('configuration validation remains usable in a small large-text window', (tester) async {
    await openPage(tester, size: const Size(320, 480), textScale: 2);
    await openCreateDialog(tester);
    await enterConfig(tester, 'not-a-url');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(controller.configs, isEmpty);
    expect(find.text(translations['webdav_address_invalid'] as String), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await finish(tester);
  });

  testWidgets('duplicate configuration names are rejected against the live list', (tester) async {
    await openPage(tester);
    await openCreateDialog(tester);
    await enterConfig(tester, 'https://example.test/dav/');
    const existing = WebDAVConfig(
      name: 'Form fixture',
      address: 'https://previous.test/',
      username: 'u',
      password: 'p',
    );
    controller.configs.add(existing);
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.text(translations['webdav_config_name_exists'] as String), findsOneWidget);
    expect(controller.configs.single, same(existing));
    expect(service.reads, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await finish(tester);
  });

  testWidgets('editing a configuration replaces it without creating a duplicate', (tester) async {
    await openPage(tester);
    selectConfig();
    await completeReads(tester);
    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开配置列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    expect(tester.widget<TextFormField>(fields.first).enabled, isFalse);
    await tester.enterText(fields.at(1), 'https://edited.test/dav/');
    await tester.enterText(fields.at(2), 'edited-user');
    await tester.enterText(fields.at(3), ' edited-password ');
    await tester.tap(find.text('更新'));
    await completeReads(tester);
    expect(controller.configs, hasLength(1));
    expect(controller.currentConfig.value!.address, 'https://edited.test/dav/');
    expect(controller.currentConfig.value!.password, ' edited-password ');
    expect(service.reads, hasLength(2));
    await finish(tester);
  });

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
