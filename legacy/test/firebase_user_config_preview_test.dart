import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings/theme_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/auth/components/user_detail_main_page.dart';
import 'package:pure_live/modules/auth/models/user_config_model.dart';
import 'package:pure_live/modules/auth/utils/firebase_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;
  late Map<String, dynamic> english;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('firebase-config-preview-test-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Hive.init(hiveDirectory.path);
    await HivePrefUtil.init();
    english = jsonDecode(await File('assets/translations/en.json').readAsString()) as Map<String, dynamic>;
  });

  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    Get.put<SettingsService>(_FixtureSettingsService());
  });

  tearDown(() async {
    await HivePrefUtil.flush();
  });

  tearDownAll(() async {
    await Hive.close().timeout(const Duration(seconds: 10));
    await hiveDirectory.delete(recursive: true);
  });

  test('legacy creation field and malformed scalar metadata are normalized', () {
    final createdAt = DateTime.utc(2024, 2, 3, 4, 5, 6);
    final model = UserFullModel.fromFirestore({
      'email': 42,
      'createdAt': createdAt,
      'update_at': <String>['bad'],
      'version': <String>['bad'],
    });

    expect(model.email, isEmpty);
    expect(model.createdAt, createdAt);
    expect(model.updateAt, isNull);
    expect(model.version, isNull);
  });

  test('malformed backup sections are isolated instead of rejecting the profile', () {
    final model = UserFullModel.fromFirestore({
      'email': 'fixture@example.com',
      'config': {
        'backupVersion': '3',
        'app': {'locale': 'en'},
        'favorite': 'broken',
        'history': ['broken'],
      },
    });

    expect(model.config, isNotNull);
    expect(model.config!.backupVersion, 3);
    expect(model.config!.app, {'locale': 'en'});
    expect(model.config!.favorite, isEmpty);
    expect(model.config!.history, isEmpty);
  });

  test('config upload preserves an existing canonical creation time', () {
    final payload = buildFirebaseConfigUploadData(
      config: '{}',
      email: 'fixture@example.com',
      version: '3.2.0',
      updateAt: '2026-09-12 05:00:00',
      hasCanonicalCreatedAt: true,
      legacyCreatedAt: DateTime.utc(2024),
      newCreatedAt: Object(),
    );

    expect(payload, isNot(contains('created_at')));
  });

  test('config upload migrates a legacy creation time', () {
    final legacyCreatedAt = DateTime.utc(2024, 2, 3);
    final payload = buildFirebaseConfigUploadData(
      config: '{}',
      email: 'fixture@example.com',
      version: '3.2.0',
      updateAt: '2026-09-12 05:00:00',
      hasCanonicalCreatedAt: false,
      legacyCreatedAt: legacyCreatedAt,
      newCreatedAt: Object(),
    );

    expect(payload['created_at'], same(legacyCreatedAt));
  });

  test('config upload initializes the creation time for a new profile', () {
    final serverTimestamp = Object();
    final payload = buildFirebaseConfigUploadData(
      config: '{}',
      email: 'fixture@example.com',
      version: '3.2.0',
      updateAt: '2026-09-12 05:00:00',
      hasCanonicalCreatedAt: false,
      newCreatedAt: serverTimestamp,
    );

    expect(payload['created_at'], same(serverTimestamp));
  });

  testWidgets('map config counts and all sections remain reachable at large text', (tester) async {
    final loader = _FixtureDocumentLoader((_) async => _profileData(config: _configMap()));
    await _pumpPage(
      tester,
      english,
      UserDetailConfigMainPage(documentId: 'fixture-user', loader: loader),
      textScale: 3,
    );

    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    await _scrollUntilHitTestable(tester, find.text('Cloud Config Raw Preview'));
    expect(find.text('Cloud Config Raw Preview').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid raw config keeps profile metadata and shows an empty preview', (tester) async {
    final loader = _FixtureDocumentLoader((_) async => _profileData(config: '{bad json'));
    await _pumpPage(tester, english, UserDetailConfigMainPage(documentId: 'fixture-user', loader: loader));

    expect(find.text('fixture@example.com'), findsOneWidget);
    expect(find.text('Cloud Config Raw Preview'), findsOneWidget);
    expect(find.text('Cloud profile could not be loaded'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('load failure is friendly and retry replaces it with profile data', (tester) async {
    var calls = 0;
    final loader = _FixtureDocumentLoader((_) async {
      calls++;
      if (calls == 1) throw StateError('private backend detail');
      return _profileData();
    });
    await _pumpPage(tester, english, UserDetailConfigMainPage(documentId: 'fixture-user', loader: loader));

    expect(find.text('Cloud profile could not be loaded'), findsOneWidget);
    expect(find.textContaining('private backend detail'), findsNothing);
    await tester.tap(find.text('Retry'));
    await _pumpFrames(tester);

    expect(calls, 2);
    expect(find.text('fixture@example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('document replacement keeps the newest request result', (tester) async {
    final first = Completer<Map<String, dynamic>?>();
    final second = Completer<Map<String, dynamic>?>();
    final loader = _FixtureDocumentLoader((documentId) => documentId == 'first' ? first.future : second.future);
    var documentId = 'first';
    late StateSetter updateHost;

    await tester.pumpWidget(
      _localizedHost(
        english,
        StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return UserDetailConfigMainPage(key: const ValueKey('profile'), documentId: documentId, loader: loader);
          },
        ),
      ),
    );
    await _pumpFrames(tester);
    expect(loader.documentIds, ['first']);

    updateHost(() => documentId = 'second');
    await _pumpFrames(tester);
    expect(loader.documentIds, ['first', 'second']);

    second.complete(_profileData(email: 'newest@example.com'));
    await _pumpFrames(tester);
    expect(find.text('newest@example.com'), findsOneWidget);

    first.complete(_profileData(email: 'stale@example.com'));
    await _pumpFrames(tester);
    expect(find.text('newest@example.com'), findsOneWidget);
    expect(find.text('stale@example.com'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late result after route disposal has no visible side effect', (tester) async {
    final result = Completer<Map<String, dynamic>?>();
    final loader = _FixtureDocumentLoader((_) => result.future);
    var showPage = true;
    late StateSetter updateHost;
    await tester.pumpWidget(
      _localizedHost(
        english,
        StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return showPage
                ? UserDetailConfigMainPage(documentId: 'fixture-user', loader: loader)
                : const SizedBox.shrink();
          },
        ),
      ),
    );
    await _pumpFrames(tester);

    updateHost(() => showPage = false);
    await _pumpFrames(tester);
    result.complete(_profileData());
    await _pumpFrames(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('empty document identity is rejected before a backend read', (tester) async {
    final loader = _FixtureDocumentLoader((_) async => _profileData());
    await _pumpPage(tester, english, UserDetailConfigMainPage(documentId: '  ', loader: loader));

    expect(loader.documentIds, isEmpty);
    expect(find.text('User document not found'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Map<String, dynamic> _profileData({String email = 'fixture@example.com', Object? config}) {
  return {
    'email': email,
    'created_at': Timestamp.fromDate(DateTime.utc(2024, 2, 3, 4, 5, 6)),
    'update_at': '2026-09-12 05:00:00',
    'version': '3.2.0',
    'config': config ?? _configMap(),
  };
}

Map<String, dynamic> _configMap() {
  return {
    'backupVersion': 3,
    'app': {'locale': 'en'},
    'favorite': {
      'favoriteRooms': [
        {'roomId': 'one'},
        {'roomId': 'two'},
      ],
    },
    'history': {
      'historyList': [
        {'roomId': 'one'},
        {'roomId': 'two'},
        {'roomId': 'three'},
      ],
    },
  };
}

class _FixtureDocumentLoader extends FirebaseUserConfigDocumentLoader {
  _FixtureDocumentLoader(this.callback);

  final Future<Map<String, dynamic>?> Function(String documentId) callback;
  final List<String> documentIds = [];

  @override
  Future<Map<String, dynamic>?> load(String documentId) {
    documentIds.add(documentId);
    return callback(documentId);
  }
}

Future<void> _pumpPage(WidgetTester tester, Map<String, dynamic> english, Widget page, {double textScale = 1}) async {
  tester.view.physicalSize = const Size(320, 480);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await tester.pumpWidget(_localizedHost(english, page, textScale: textScale));
  await _pumpFrames(tester);
}

Widget _localizedHost(Map<String, dynamic> english, Widget page, {double textScale = 1}) {
  return EasyLocalization(
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
  );
}

Future<void> _scrollUntilHitTestable(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 160, scrollable: find.byType(Scrollable).first);
  await _pumpFrames(tester);
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 6]) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Translations extends AssetLoader {
  const _Translations(this.english);

  final Map<String, dynamic> english;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => english;
}

class _FixtureSettingsService extends SettingsService {
  @override
  final font = FontSettingsController();

  @override
  final theme = ThemeSettingsController();

  @override
  // This fixture resolves only typography and loading-style settings.
  // ignore: must_call_super
  void onInit() {}
}
