import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings/iptv_settings_controller.dart';
import 'package:pure_live/common/services/settings/theme_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/services/utils/hive_rx.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/iptv/local/database.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/iptv/iptv_page.dart';
import 'package:pure_live/plugins/db_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Map<String, dynamic> translations;
  late Map<String, dynamic> english;
  late _Settings settings;
  late _Database db;
  final imports = <(bool, String, String, Completer<bool>)>[];
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('iptv-settings-page-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Hive.init(dir.path);
    await HivePrefUtil.init();
    translations = jsonDecode(await File('assets/translations/zh.json').readAsString()) as Map<String, dynamic>;
    english = jsonDecode(await File('assets/translations/en.json').readAsString()) as Map<String, dynamic>;
  });
  setUp(() {
    imports.clear();
    Get.testMode = true;
    settings = Get.put<SettingsService>(_Settings()) as _Settings;
    settings.iptv.customIptvUserAgent.v = 'Original-Agent';
    settings.iptv.isAutoSyncEnabled.v = false;
    settings.iptv.autoSyncHoursInterval.v = 24;
    settings.iptv.selectedSourceId.v = 'fixture';
    Get.put(ThemeSettingsController());
    db = _Database();
    final service = DbService();
    service.db = db;
    Get.put(service);
  });
  tearDown(() async {
    Get.deleteAll(force: true);
    Get.reset();
    await db.close();
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(360, 780),
    double scale = 1,
    String language = 'zh',
  }) async {
    final strings = language == 'en' ? english : translations;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('zh'), Locale('en')],
        startLocale: Locale(language),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: _Translations(strings),
        child: Builder(
          builder: (context) => GetMaterialApp(
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: FlutterSmartDialog.init()(context, child),
            ),
            home: IptvPage(
              importFromNetwork: (epg, url, name) {
                final pending = Completer<bool>();
                imports.add((epg, url, name, pending));
                return pending.future;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final f = find.text(translations[key] as String);
    if (f.evaluate().isEmpty) await tester.scrollUntilVisible(f, 150);
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  testWidgets('focused UA cancel disposes only after dialog subtree unmounts', (tester) async {
    await open(tester);
    await tap(tester, 'custom_ua_title');
    await tester.enterText(find.byType(TextField), 'discarded');
    await tap(tester, 'cancel');
    expect(settings.iptv.customIptvUserAgent.v, 'Original-Agent');
    await finish(tester);
  });
  testWidgets('UA save updates the existing settings tile immediately', (tester) async {
    await open(tester);
    await tap(tester, 'custom_ua_title');
    await tester.enterText(find.byType(TextField), '  Saved-Agent  ');
    await tap(tester, 'confirm');
    expect(settings.iptv.customIptvUserAgent.v, 'Saved-Agent');
    expect(find.text('Saved-Agent'), findsOneWidget);
    expect(find.text('Original-Agent'), findsNothing);
    await finish(tester);
  });
  testWidgets('UA editing fits narrow large-text window', (tester) async {
    await open(tester, size: const Size(320, 480), scale: 2);
    await tap(tester, 'custom_ua_title');
    expect(tester.takeException(), isNull);
    await tap(tester, 'cancel');
    await finish(tester);
  });
  testWidgets('all sync intervals remain reachable in short large-text window', (tester) async {
    settings.iptv.isAutoSyncEnabled.v = true;
    await open(tester, size: const Size(320, 480), scale: 2);
    await tap(tester, 'sync_interval_title');
    expect(tester.takeException(), isNull);
    final last = find.text('72 ${translations['hours']}');
    await tester.ensureVisible(last);
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(settings.iptv.autoSyncHoursInterval.v, 72);
    await finish(tester);
  });
  testWidgets('UA draft clear and barrier dismissal preserve saved value and reopen cleanly', (tester) async {
    await open(tester);
    await tap(tester, 'custom_ua_title');
    await tester.enterText(find.byType(TextField), 'draft');
    await tester.tap(find.descendant(of: find.byType(TextField), matching: find.byType(IconButton)));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(settings.iptv.customIptvUserAgent.v, 'Original-Agent');
    await tap(tester, 'custom_ua_title');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Original-Agent');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await finish(tester);
  });
  testWidgets('empty UA is an explicit saved reset rather than cancellation', (tester) async {
    await open(tester);
    await tap(tester, 'custom_ua_title');
    await tester.enterText(find.byType(TextField), '   ');
    await tap(tester, 'confirm');
    expect(settings.iptv.customIptvUserAgent.v, isEmpty);
    await tap(tester, 'custom_ua_title');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    await tap(tester, 'cancel');
    await finish(tester);
  });
  testWidgets('external settings update refreshes the visible full UA text', (tester) async {
    await open(tester);
    const value = 'Example-Agent-with-a-long-value-and-a-different-suffix';
    settings.iptv.customIptvUserAgent.v = value;
    await tester.pumpAndSettle();
    expect(find.text(value), findsOneWidget);
    expect(find.text('Original-Agent'), findsNothing);
    await finish(tester);
  });
  testWidgets('interval dismissal preserves saved setting and every choice commits', (tester) async {
    settings.iptv.isAutoSyncEnabled.v = true;
    await open(tester);
    await tap(tester, 'sync_interval_title');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(settings.iptv.autoSyncHoursInterval.v, 24);
    for (final hours in [2, 6, 12, 24, 48, 72]) {
      await tap(tester, 'sync_interval_title');
      final f = find.text('$hours ${translations['hours']}');
      await tester.ensureVisible(f);
      await tester.tap(f);
      await tester.pumpAndSettle();
      expect(settings.iptv.autoSyncHoursInterval.v, hours);
      expect(find.byType(AlertDialog), findsNothing);
    }
    await finish(tester);
  });
  for (final language in ['zh', 'en']) {
    testWidgets('UA text resize and keyboard insets remain usable in $language', (tester) async {
      await open(tester, size: const Size(320, 640), scale: 2, language: language);
      final strings = language == 'en' ? english : translations;
      final entry = find.text(strings['custom_ua_title'] as String);
      await tester.ensureVisible(entry);
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 180);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'Keyboard-Agent');
      final drag = find.byWidgetPredicate((w) => w is GestureDetector && w.onVerticalDragUpdate != null).last;
      await tester.ensureVisible(drag);
      await tester.drag(drag, const Offset(0, 100));
      await tester.pumpAndSettle();
      expect(MediaQuery.textScalerOf(tester.element(field)).scale(10), 20);
      expect(tester.takeException(), isNull);
      final confirm = find.text(strings['confirm'] as String);
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(settings.iptv.customIptvUserAgent.v, 'Keyboard-Agent');
      await finish(tester);
    });
    testWidgets('IPTV EPG import tile has a translated label in $language', (tester) async {
      await open(tester, language: language);
      final strings = language == 'en' ? english : translations;
      expect(strings['import_epg_source'], isA<String>());
      final label = find.text(strings['import_epg_source'] as String);
      await tester.scrollUntilVisible(label, 150);
      expect(label, findsOneWidget);
      expect(find.text('import_epg_source'), findsNothing);
      await finish(tester);
    });
  }
  Future<void> openImport(WidgetTester tester, {bool epg = false}) async {
    await tap(tester, epg ? 'import_epg_source' : 'import_playlist');
    await tap(tester, 'network_import');
  }

  Future<void> enterImport(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField).at(0), '  https://example.test/list.m3u  ');
    await tester.enterText(find.byType(TextField).at(1), '  Network fixture  ');
  }

  testWidgets('network import focused cancellation retains route-owned controllers', (tester) async {
    await open(tester);
    await openImport(tester);
    await enterImport(tester);
    await tap(tester, 'cancel');
    expect(find.byType(TextField), findsNothing);
    expect(imports, isEmpty);
    await finish(tester);
  });
  testWidgets('network import fits small large-text window', (tester) async {
    await open(tester, size: const Size(320, 480), scale: 2);
    await openImport(tester);
    expect(tester.takeException(), isNull);
    await tap(tester, 'cancel');
    await finish(tester);
  });
  testWidgets('pending import accepts only one submission and failure preserves draft for retry', (tester) async {
    await open(tester);
    await openImport(tester);
    await enterImport(tester);
    final button = find.text(translations['confirm'] as String);
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    final count = imports.length;
    for (final entry in imports) {
      entry.$4.complete(false);
    }
    await tester.pumpAndSettle();
    expect(count, 1);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text, '  Network fixture  ');
    await tester.tap(button);
    await tester.pump();
    expect(imports, hasLength(2));
    imports.last.$4.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(IptvPage), findsOneWidget);
    await finish(tester);
  });
  testWidgets('closing pending import does not pop a later dialog and blocks duplicate import', (tester) async {
    await open(tester);
    await openImport(tester);
    await enterImport(tester);
    await tester.tap(find.text(translations['confirm'] as String));
    await tester.pump();
    expect(find.text(translations['iptv_import_close_hint'] as String), findsOneWidget);
    await tester.tap(find.text(translations['close'] as String));
    await tester.pumpAndSettle();
    await openImport(tester);
    expect(find.byType(TextField), findsNothing);
    expect(imports, hasLength(1));
    await tap(tester, 'custom_ua_title');
    await tester.enterText(find.byType(TextField), 'unrelated draft');
    imports.single.$4.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'unrelated draft');
    await tap(tester, 'cancel');
    await openImport(tester);
    expect(find.byType(TextField), findsNWidgets(2));
    await tap(tester, 'cancel');
    await finish(tester);
  });
  testWidgets('success under a newer route removes only the owned import dialog', (tester) async {
    await open(tester);
    await openImport(tester);
    await enterImport(tester);
    await tester.tap(find.text(translations['confirm'] as String));
    await tester.pump();
    final navigator = Navigator.of(tester.element(find.byType(AlertDialog)));
    unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Newer route')))));
    await tester.pumpAndSettle();
    imports.single.$4.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Newer route'), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(IptvPage), findsOneWidget);
    await finish(tester);
  });
  testWidgets('thrown import failure releases the gate and retains a usable draft', (tester) async {
    await open(tester);
    await openImport(tester, epg: true);
    await enterImport(tester);
    await tester.tap(find.text(translations['confirm'] as String));
    await tester.pump();
    expect(imports.single.$1, isTrue);
    expect(imports.single.$2, 'https://example.test/list.m3u');
    expect(imports.single.$3, 'Network fixture');
    imports.single.$4.completeError(StateError('fixture failure'));
    await tester.pumpAndSettle();
    expect(find.text(translations['network_import_failed'] as String), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField).at(0)).readOnly, isFalse);
    await tester.tap(find.text(translations['confirm'] as String));
    await tester.pump();
    imports.last.$4.complete(true);
    await tester.pumpAndSettle();
    expect(imports, hasLength(2));
    expect(find.byType(AlertDialog), findsNothing);
    await finish(tester);
  });
  testWidgets('invalid or missing import fields create no request and keep both drafts', (tester) async {
    await open(tester);
    await openImport(tester);
    await tap(tester, 'confirm');
    expect(find.text(translations['enter_download_link'] as String), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'not a URL');
    await tap(tester, 'confirm');
    expect(find.text(translations['invalid_download_link'] as String), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'https://example.test/list.xml');
    await tap(tester, 'confirm');
    expect(find.text(translations['enter_file_name'] as String), findsOneWidget);
    expect(imports, isEmpty);
    await tap(tester, 'cancel');
    await finish(tester);
  });
  testWidgets('completed import is not relabelled failed when only refreshing the list fails', (tester) async {
    await open(tester);
    await openImport(tester);
    await enterImport(tester);
    await tester.tap(find.text(translations['confirm'] as String));
    await tester.pump();
    db.failProviderRead = true;
    imports.single.$4.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(imports, hasLength(1));
    expect(find.text(translations['network_import_failed'] as String), findsNothing);
    await finish(tester);
  });
  testWidgets('leaving the page before import completion does not refresh disposed UI', (tester) async {
    await open(tester);
    await openImport(tester);
    await enterImport(tester);
    await tester.tap(find.text(translations['confirm'] as String));
    await tester.pump();
    final reads = db.providerReads;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    imports.single.$4.complete(true);
    await tester.pumpAndSettle();
    expect(db.providerReads, reads);
    expect(tester.takeException(), isNull);
  });
}

class _Translations extends AssetLoader {
  const _Translations(this.values);
  final Map<String, dynamic> values;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}

class _Settings extends SettingsService {
  final _font = FontSettingsController();
  final _iptv = IptvSettingsController();
  @override
  FontSettingsController get font => _font;
  @override
  IptvSettingsController get iptv => _iptv;
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _Database extends AppDatabase {
  _Database() : super.forTesting(NativeDatabase.memory());
  bool failProviderRead = false;
  int providerReads = 0;
  @override
  Future<List<Provider>> getAllProviders() async {
    providerReads++;
    if (failProviderRead) throw StateError('fixture read failed');
    return [];
  }

  @override
  Future<List<EpgSource>> getAllEpgSources() async => [
    EpgSource(
      id: 'fixture',
      name: 'Fixture',
      url: 'https://example.test/epg.xml',
      enabled: true,
      refreshIntervalHours: 24,
      createdAt: DateTime(2026),
      isAutoUpdate: false,
    ),
  ];
}
