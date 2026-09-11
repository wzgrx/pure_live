import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/app_settings_controller.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/common/utils/version_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/about/about_page.dart';
import 'package:pure_live/modules/about/widgets/version_dialog.dart';
import 'package:pure_live/modules/favorite/favorite_controller.dart';
import 'package:pure_live/modules/home/home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Loader extends AssetLoader {
  const _Loader(this.data);

  final Map<String, dynamic> data;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => data;
}

class _Settings extends SettingsService {
  @override
  final app = AppSettingsController();

  @override
  final font = FontSettingsController();

  @override
  // This layout fixture has no app, player or network services.
  // ignore: must_call_super
  void onInit() {}
}

class _Favorite extends GetxController implements FavoriteController {
  @override
  final tabBottomIndex = 0.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> english;
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('about-update-prompt-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Hive.init(directory.path);
    await HivePrefUtil.init();
    await HivePrefUtil.setStringList('savedMenuIds', const []);
    english = jsonDecode(await File('assets/translations/en.json').readAsString()) as Map<String, dynamic>;
  });

  tearDown(() {
    Get.reset();
    Get.testMode = false;
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> pump(
    WidgetTester tester, {
    required Widget home,
    Size size = const Size(320, 480),
    double textScale = 3,
    bool settle = true,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    Get.reset();
    Get.testMode = true;
    final settings = _Settings();
    Get.put<SettingsService>(settings);
    Get.put<FavoriteController>(_Favorite());
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        startLocale: const Locale('en'),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: _Loader(english),
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
    if (settle) await tester.pumpAndSettle();
  }

  testWidgets('about page keeps every section reachable at narrow 3x text', (tester) async {
    await pump(tester, home: const AboutPage());

    final scrollable = find.descendant(of: find.byType(AboutPage), matching: find.byType(Scrollable)).first;
    final projectAlert = find.text(english['project_alert'] as String);
    await tester.scrollUntilVisible(projectAlert, 160, scrollable: scrollable, maxScrolls: 30);
    await tester.pumpAndSettle();

    expect(projectAlert.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('automatic update prompt keeps both actions reachable at narrow 3x text', (tester) async {
    VersionUtil.latestUpdateLog =
        '# Highlights\n\nThis update contains a deliberately long release summary for the responsive prompt.';

    var updates = 0;
    await pump(
      tester,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => NewVersionDialog(onUpdate: () => updates++),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text(english['cancel'] as String).hitTestable(), findsOneWidget);
    expect(find.text(english['update'] as String).hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('new-version-update')));
    await tester.pumpAndSettle();
    expect(updates, 1);
    expect(find.byKey(const ValueKey('new-version-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup update prompt is a route dismissed by system back', (tester) async {
    var initialized = 0;
    var checked = 0;
    await pump(
      tester,
      textScale: 1,
      settle: false,
      home: HomePage(
        updateCheckDelay: Duration.zero,
        initializePackageInfo: () async {
          initialized++;
        },
        checkForUpdate: () async {
          checked++;
          return true;
        },
        hasNewVersion: () => true,
        updatePromptBuilder: (_) => const NewVersionDialog(),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(initialized, 1);
    expect(checked, 1);
    expect(find.byKey(const ValueKey('new-version-dialog')), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('new-version-dialog')), findsNothing);
    expect(find.byType(HomePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late startup update result cannot reopen a disposed home', (tester) async {
    final entered = Completer<void>();
    final result = Completer<bool>();
    addTearDown(() {
      if (!result.isCompleted) result.complete(false);
    });
    await pump(
      tester,
      textScale: 1,
      settle: false,
      home: HomePage(
        updateCheckDelay: Duration.zero,
        initializePackageInfo: () async {},
        checkForUpdate: () {
          entered.complete();
          return result.future;
        },
        hasNewVersion: () => true,
      ),
    );
    for (var attempt = 0; attempt < 5 && !entered.isCompleted; attempt++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(entered.isCompleted, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());

    result.complete(true);
    await tester.pump();

    expect(find.byKey(const ValueKey('new-version-dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
