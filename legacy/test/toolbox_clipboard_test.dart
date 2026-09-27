import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings/theme_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/toolbox/toolbox_controller.dart';
import 'package:pure_live/modules/toolbox/toolbox_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Map<String, dynamic> translations;
  late Map<String, dynamic> english;
  late ToolBoxController controller;
  late List<Completer<Object?>> reads;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('toolbox-clipboard-');
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    Hive.init(directory.path);
    await HivePrefUtil.init();
    translations = jsonDecode(await File('assets/translations/zh.json').readAsString()) as Map<String, dynamic>;
    english = jsonDecode(await File('assets/translations/en.json').readAsString()) as Map<String, dynamic>;
  });
  setUp(() {
    Get.testMode = true;
    Get.put<SettingsService>(_Settings());
    Get.put(ThemeSettingsController());
    controller = Get.put(ToolBoxController());
    reads = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          final value = Completer<Object?>();
          reads.add(value);
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
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(900, 900),
    double scale = 1,
    String locale = 'zh',
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      for (final request in reads) {
        if (!request.isCompleted) request.complete(null);
      }
      await tester.pump();
      if (find.byType(ToolBoxPage).evaluate().isNotEmpty && Get.isSnackbarOpen) Get.closeAllSnackbars();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: [Locale(locale)],
        startLocale: Locale(locale),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: _Loader(locale == 'zh' ? translations : english),
        child: Builder(
          builder: (context) => GetMaterialApp(
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: const ToolBoxPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reply(WidgetTester tester, String? text) async {
    for (final request in reads.toList()) {
      if (!request.isCompleted) request.complete(text == null ? null : {'text': text});
    }
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  const url = 'https://live.bilibili.com/123';
  testWidgets('pending clipboard never replaces a newly typed field', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField).first, 'user draft');
    await reply(tester, url);
    expect(controller.roomJumpToController.text, 'user draft');
    expect(controller.getUrlController.text, url);
  });
  testWidgets('typing then clearing remains an intentional empty field', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField).first, 'user draft');
    controller.roomJumpToController.clear();
    await reply(tester, url);
    expect(controller.roomJumpToController.text, isEmpty);
    expect(controller.getUrlController.text, url);
  });
  testWidgets('existing drafts are preserved', (tester) async {
    controller.roomJumpToController.text = 'first draft';
    controller.getUrlController.text = 'second draft';
    await open(tester);
    await reply(tester, url);
    expect(controller.roomJumpToController.text, 'first draft');
    expect(controller.getUrlController.text, 'second draft');
  });
  testWidgets('page rebuild does not read the clipboard again', (tester) async {
    await open(tester);
    await reply(tester, null);
    tester.element(find.byType(ToolBoxPage)).markNeedsBuild();
    await tester.pump();
    expect(reads, hasLength(1));
  });
  testWidgets('late clipboard response after route disposal is ignored', (tester) async {
    await open(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    if (!controller.isClosed) controller.onDelete();
    expect(controller.isClosed, isTrue);
    await reply(tester, url);
    expect(tester.takeException(), isNull);
  });
  testWidgets('clipboard completion on a covered toolbox route stays local', (tester) async {
    await open(tester);
    final context = tester.element(find.byType(ToolBoxPage));
    unawaited(
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Other page')))),
    );
    await tester.pumpAndSettle();

    await reply(tester, url);

    expect(find.text('Other page'), findsOneWidget);
    expect(controller.roomJumpToController.text, isEmpty);
    expect(controller.getUrlController.text, isEmpty);
    expect(Get.isSnackbarOpen, isFalse);
  });
  testWidgets('clipboard platform failure is contained', (tester) async {
    await open(tester);
    reads.single.completeError(PlatformException(code: 'clipboard_unavailable'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(controller.roomJumpToController.text, isEmpty);
  });
  testWidgets('platform words without a URL are not auto-filled', (tester) async {
    await open(tester);
    await reply(tester, 'bilibili subscription notes 163');
    expect(controller.roomJumpToController.text, isEmpty);
    expect(controller.getUrlController.text, isEmpty);
  });
  testWidgets('a supported overseas URL is detected without network access', (tester) async {
    await open(tester);
    await reply(tester, 'Watch https://www.twitch.tv/fixture_channel');
    expect(controller.roomJumpToController.text, 'Watch https://www.twitch.tv/fixture_channel');
    expect(controller.getUrlController.text, controller.roomJumpToController.text);
  });
  testWidgets('one existing draft leaves the untouched field eligible', (tester) async {
    controller.roomJumpToController.text = 'saved draft';
    final original = controller.roomJumpToController.value;
    await open(tester);
    await reply(tester, url);
    expect(controller.roomJumpToController.value, original);
    expect(controller.getUrlController.text, url);
  });
  testWidgets('duplicate callbacks and post-fill rebuild keep one read', (tester) async {
    await open(tester);
    controller.autoCheckClipboard();
    controller.autoCheckClipboard();
    expect(reads, hasLength(1));
    await reply(tester, url);
    controller.roomJumpToController.clear();
    tester.element(find.byType(ToolBoxPage)).markNeedsBuild();
    await tester.pump();
    expect(reads, hasLength(1));
    expect(controller.roomJumpToController.text, isEmpty);
    expect(controller.getUrlController.text, url);
  });
  testWidgets('an absent clipboard plugin leaves manual input available', (tester) async {
    await open(tester);
    reads.single.completeError(MissingPluginException('fixture clipboard plugin'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField).first, 'manual input');
    expect(controller.roomJumpToController.text, 'manual input');
  });
  testWidgets('cleared fields remain independent through fold and unfold', (tester) async {
    await open(tester);
    await reply(tester, url);
    await tester.tap(find.descendant(of: find.byType(TextField).first, matching: find.byType(IconButton)));
    await tester.pumpAndSettle();
    expect(controller.roomJumpToController.text, isEmpty);
    expect(controller.getUrlController.text, url);
    final title = find.text(translations['toolbox_room_jump'] as String);
    await tester.tap(title);
    await tester.pumpAndSettle();
    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(controller.roomJumpToController.text, isEmpty);
    expect(controller.getUrlController.text, url);
    expect(reads, hasLength(1));
  });
  for (final locale in ['zh', 'en']) {
    testWidgets('$locale tools remain usable on a narrow large-text page', (tester) async {
      await open(tester, size: const Size(320, 480), scale: 3, locale: locale);
      await reply(tester, null);
      final parse = find.widgetWithText(
        FilledButton,
        (locale == 'zh' ? translations : english)['toolbox_get_parse'] as String,
      );
      await tester.scrollUntilVisible(parse, 180, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(parse.hitTestable(), findsOneWidget);
      final support = find.text((locale == 'zh' ? translations : english)['toolbox_support_list'] as String);
      await tester.scrollUntilVisible(support, 120, scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
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
