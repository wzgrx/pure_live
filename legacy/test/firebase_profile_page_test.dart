import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/auth/mine_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> english;
  late Directory hiveDirectory;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('firebase-profile-page-test-');
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
    Get.reset();
  });

  tearDownAll(() async {
    await Hive.close().timeout(const Duration(seconds: 10));
    await hiveDirectory.delete(recursive: true);
  });

  testWidgets('profile actions remain reachable without app-bar overflow at large text', (tester) async {
    final actions = _FixtureProfileActions(userId: 'fixture-user');
    await _pumpProfile(tester, english, MinePage(actions: actions), textScale: 3);

    expect(tester.takeException(), isNull);
    expect(find.text('Config Preview'), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Config Preview')), findsNothing);
    await _scrollUntilHitTestable(tester, find.text('Sign Out'));
    expect(find.text('Sign Out').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing account identity leaves preview on the profile page', (tester) async {
    final actions = _FixtureProfileActions();
    await _pumpProfile(tester, english, MinePage(actions: actions));

    await tester.tap(find.text('Config Preview'));
    await tester.pump();

    expect(actions.previewCalls, isEmpty);
    expect(find.byType(MinePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated upload taps share one page action', (tester) async {
    final gate = Completer<void>();
    final actions = _FixtureProfileActions(userId: 'fixture-user', uploadGate: gate);
    await _pumpProfile(tester, english, MinePage(actions: actions));

    await _scrollUntilHitTestable(tester, find.text('Upload Config'));
    await tester.tap(find.text('Upload Config'));
    await tester.tap(find.text('Upload Config'));
    await tester.pump();
    expect(actions.uploadCalls, 1);

    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cloud download requires an explicit overwrite confirmation', (tester) async {
    final actions = _FixtureProfileActions(userId: 'fixture-user');
    await _pumpProfile(tester, english, MinePage(actions: actions), textScale: 3);

    await _scrollUntilHitTestable(tester, find.text('Download user configs'));
    await tester.tap(find.text('Download user configs'));
    await tester.pumpAndSettle();
    expect(actions.downloadCalls, 0);
    expect(find.text('Replace local settings?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(actions.downloadCalls, 0);

    await _scrollUntilHitTestable(tester, find.text('Download user configs'));
    await tester.tap(find.text('Download user configs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(actions.downloadCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sign out requires confirmation and holds one action while pending', (tester) async {
    final gate = Completer<void>();
    final actions = _FixtureProfileActions(userId: 'fixture-user', signOutGate: gate);
    await _pumpProfile(tester, english, MinePage(actions: actions));

    await _scrollUntilHitTestable(tester, find.text('Sign Out'));
    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();
    expect(actions.signOutCalls, 0);
    expect(find.text('Sign out?'), findsOneWidget);

    await tester.tap(find.text('Confirm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(actions.signOutCalls, 1);
    expect(find.text('Sign out?'), findsNothing);
    final signOutTile = find.ancestor(of: find.text('Sign Out'), matching: find.byType(ListTile));
    expect(tester.widget<ListTile>(signOutTile).onTap, isNull);

    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed cloud action is contained and becomes retryable', (tester) async {
    final actions = _FixtureProfileActions(userId: 'fixture-user', uploadError: StateError('fixture failure'));
    await _pumpProfile(tester, english, MinePage(actions: actions));

    await _scrollUntilHitTestable(tester, find.text('Upload Config'));
    await tester.tap(find.text('Upload Config'));
    await tester.pumpAndSettle();
    expect(actions.uploadCalls, 1);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Upload Config'));
    await tester.pumpAndSettle();
    expect(actions.uploadCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late cloud completion does not update a disposed profile page', (tester) async {
    final gate = Completer<void>();
    final actions = _FixtureProfileActions(userId: 'fixture-user', uploadGate: gate);
    await _pumpProfile(tester, english, MinePage(actions: actions));

    await _scrollUntilHitTestable(tester, find.text('Upload Config'));
    await tester.tap(find.text('Upload Config'));
    await tester.pump();
    expect(actions.uploadCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    gate.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

class _FixtureProfileActions extends FirebaseProfileActions {
  _FixtureProfileActions({this.userId, this.uploadGate, this.signOutGate, this.uploadError});

  @override
  final String? userId;
  final Completer<void>? uploadGate;
  final Completer<void>? signOutGate;
  final Object? uploadError;

  int uploadCalls = 0;
  int downloadCalls = 0;
  int signOutCalls = 0;
  final List<String> previewCalls = [];

  @override
  bool get hasManagementPower => false;

  @override
  Future<void> uploadConfig() async {
    uploadCalls++;
    await uploadGate?.future;
    if (uploadError case final error?) throw error;
  }

  @override
  Future<void> downloadConfig() async {
    downloadCalls++;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    await signOutGate?.future;
  }

  @override
  Future<void> openConfigPreview(String documentId) async {
    previewCalls.add(documentId);
  }
}

Future<void> _pumpProfile(
  WidgetTester tester,
  Map<String, dynamic> english,
  Widget home, {
  double textScale = 1,
}) async {
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
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: home,
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

Future<void> _scrollUntilHitTestable(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 160, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

class _FixtureSettingsService extends SettingsService {
  @override
  final font = FontSettingsController();

  @override
  // This widget fixture resolves only typography settings.
  // ignore: must_call_super
  void onInit() {}
}
