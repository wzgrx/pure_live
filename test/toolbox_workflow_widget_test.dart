import 'dart:async';

import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/niconico/niconico_input_recipe.dart';

import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings/theme_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/toolbox/toolbox_controller.dart';
import 'package:pure_live/modules/toolbox/toolbox_direct_link_flow.dart';
import 'package:pure_live/modules/toolbox/toolbox_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/toolbox_test_site.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Map<String, dynamic> zh;
  late Map<String, dynamic> en;
  late ToolBoxTestSite site;
  late ToolBoxController controller;
  late List<String> notices;
  late List<String> copied;
  late List<Completer<Object?>> writes;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('toolbox-workflow-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Hive.init(directory.path);
    await HivePrefUtil.init();
    zh = jsonDecode(await File('assets/translations/zh.json').readAsString()) as Map<String, dynamic>;
    en = jsonDecode(await File('assets/translations/en.json').readAsString()) as Map<String, dynamic>;
  });
  setUp(() {
    Get.testMode = true;
    Get.put<SettingsService>(_Settings());
    Get.put(ThemeSettingsController());
    site = ToolBoxTestSite();
    notices = [];
    copied = [];
    writes = [];
    controller = Get.put(
      ToolBoxController(
        parseLink: (_) async => ['123', 'bilibili'],
        directLinkFlow: ToolBoxDirectLinkFlow(siteFor: (_) => site),
        notify: notices.add,
      ),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
          final value = Completer<Object?>();
          writes.add(value);
          return value.future;
        }
        return null;
      },
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    Get.deleteAll(force: true);
    Get.reset();
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  Future<void> frame(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> open(WidgetTester tester, {String locale = 'zh', bool narrow = false}) async {
    tester.view.physicalSize = narrow ? const Size(320, 480) : const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      controller.cancelAction();
      for (final pending in writes) {
        if (!pending.isCompleted) pending.complete(null);
      }
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: [Locale(locale)],
        startLocale: Locale(locale),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: _Loader(locale == 'zh' ? zh : en),
        child: Builder(
          builder: (context) => GetMaterialApp(
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)),
              child: child!,
            ),
            home: const ToolBoxPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester, {String locale = 'zh'}) async {
    controller.getUrlController.text = 'https://live.bilibili.com/123';
    final button = find.widgetWithText(FilledButton, (locale == 'zh' ? zh : en)['toolbox_get_parse'] as String);
    await tester.scrollUntilVisible(button, 180, scrollable: find.byType(Scrollable).first);
    await tester.pump();
    await tester.tap(button);
    await frame(tester);
  }

  Finder choices() => find.descendant(of: find.byType(SimpleDialog), matching: find.byType(ListTile));

  for (final locale in ['zh', 'en']) {
    testWidgets('$locale toolbox restores controls for session-only input', (tester) async {
      site = ToolBoxResolvedTestSite()
        ..resolution = LivePlayUrlResolution.owned(input: NiconicoInputRecipe(programId: 'lv123', resolution: null));
      await open(tester, locale: locale, narrow: true);
      await start(tester, locale: locale);
      await tester.tap(choices().first);
      await frame(tester);
      expect(controller.isBusy, isFalse);
      expect(find.byType(SimpleDialog), findsNothing);
      expect(find.byType(ToolBoxPage), findsOneWidget);
      expect(controller.getUrlController.text, 'https://live.bilibili.com/123');
      expect(site.calls, ['detail', 'qualities', 'resolve']);
      expect(copied, isEmpty);
      expect(notices, ['toolbox_session_source']);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('quality and line choices preserve input and wait for clipboard acknowledgement', (tester) async {
    await open(tester);
    await start(tester);
    expect(controller.isBusy, isTrue);
    expect(
      tester.widgetList<FilledButton>(find.byType(FilledButton)).every((button) => button.onPressed == null),
      isTrue,
    );
    final tile = tester.widget<ListTile>(choices().first);
    tile.onTap!();
    tile.onTap!(); // A second callback from the retiring dialog must not pop the page.
    await frame(tester);
    expect(site.requestedQuality, same(site.qualities.first));
    await tester.tap(choices().last);
    await frame(tester);
    expect(find.byType(ToolBoxPage), findsOneWidget);
    expect(copied, [site.urls.last]);
    expect(notices, isEmpty);
    expect(controller.isBusy, isTrue);
    writes.single.complete(null);
    await frame(tester);
    expect(notices, ['toolbox_copy_success']);
    expect(controller.isBusy, isFalse);
    expect(controller.getUrlController.text, 'https://live.bilibili.com/123');
  });
  testWidgets('copy failure reports failure and keeps retry controls enabled', (tester) async {
    await open(tester);
    await start(tester);
    await tester.tap(choices().first);
    await frame(tester);
    await tester.tap(choices().first);
    await frame(tester);
    writes.single.completeError(PlatformException(code: 'fixture_denied'));
    await frame(tester);
    expect(notices, ['toolbox_copy_failed']);
    expect(controller.isBusy, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('cancelling the quality dialog skips lines and clipboard', (tester) async {
    await open(tester);
    await start(tester);
    await tester.tap(
      find.descendant(of: find.byType(SimpleDialog), matching: find.widgetWithText(TextButton, zh['cancel'] as String)),
    );
    await frame(tester);
    expect(site.calls, ['detail', 'qualities']);
    expect(copied, isEmpty);
    expect(controller.isBusy, isFalse);
    expect(notices, isEmpty);
  });
  testWidgets('cancelling a pending request releases busy state and ignores late detail', (tester) async {
    final pending = Completer<LiveRoom>();
    site.detailReply = pending.future;
    await open(tester);
    await start(tester);
    await tester.tap(find.widgetWithText(TextButton, zh['cancel'] as String));
    await frame(tester);
    expect(controller.isBusy, isFalse);
    pending.complete(site.room);
    await frame(tester);
    expect(site.calls, ['detail']);
    expect(find.byType(SimpleDialog), findsNothing);
  });
  testWidgets('leaving the toolbox suppresses a late dialog without touching the new route', (tester) async {
    final pending = Completer<LiveRoom>();
    site.detailReply = pending.future;
    await open(tester);
    await start(tester);
    final context = tester.element(find.byType(ToolBoxPage));
    unawaited(
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Other page')))),
    );
    await frame(tester);
    pending.complete(site.room);
    await frame(tester);
    expect(find.text('Other page'), findsOneWidget);
    expect(find.byType(SimpleDialog), findsNothing);
    expect(notices, isEmpty);
  });
  testWidgets('cancellation removes only its own dialog underneath another route', (tester) async {
    await open(tester);
    await start(tester);
    final context = tester.element(find.byType(ToolBoxPage));
    unawaited(
      Navigator.of(context).push(
        DialogRoute<void>(
          context: context,
          builder: (_) => const AlertDialog(title: Text('Unrelated dialog')),
        ),
      ),
    );
    await frame(tester);
    controller.cancelAction();
    await frame(tester);
    expect(find.text('Unrelated dialog'), findsOneWidget);
    expect(find.byType(SimpleDialog, skipOffstage: false), findsNothing);
    expect(notices, isEmpty);
  });
  testWidgets('network deadline restores controls and contains a late result', (tester) async {
    final pending = Completer<LiveRoom>();
    site.detailReply = pending.future;
    await open(tester);
    await start(tester);
    await tester.pump(const Duration(seconds: 13));
    await frame(tester);
    expect(notices, ['toolbox_get_url_failed']);
    expect(controller.isBusy, isFalse);
    pending.complete(site.room);
    await frame(tester);
    expect(site.calls, ['detail']);
  });
  for (final locale in ['zh', 'en']) {
    testWidgets('$locale narrow large-text quality selector remains cancellable', (tester) async {
      await open(tester, locale: locale, narrow: true);
      await start(tester, locale: locale);
      final cancel = find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.widgetWithText(TextButton, (locale == 'zh' ? zh : en)['cancel'] as String),
      );
      await tester.ensureVisible(cancel);
      await frame(tester);
      await tester.tap(cancel);
      await frame(tester);
      expect(find.byType(SimpleDialog), findsNothing);
      expect(controller.isBusy, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}

class _Settings extends SettingsService {
  final _font = FontSettingsController();
  @override
  FontSettingsController get font => _font;
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _Loader extends AssetLoader {
  _Loader(this.data);
  final Map<String, dynamic> data;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => data;
}
