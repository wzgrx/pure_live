import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';
import 'package:pure_live/modules/web_dav/web_dav_help.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> english;
  late Map<String, dynamic> chinese;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    english = jsonDecode(await File('assets/translations/en.json').readAsString()) as Map<String, dynamic>;
    chinese = jsonDecode(await File('assets/translations/zh.json').readAsString()) as Map<String, dynamic>;
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    String locale = 'en',
    Size size = const Size(800, 900),
    double textScale = 1,
    WebDavExternalLauncher? openExternalUrl,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    final language = locale == 'zh' ? chinese : english;
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: [Locale(locale)],
        startLocale: Locale(locale),
        fallbackLocale: Locale(locale),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: _Translations(language),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: WebDavHelpPage(openExternalUrl: openExternalUrl),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('English help localizes the complete page and reflects the current free-plan quota', (tester) async {
    await pumpPage(tester);

    expect(find.text('WebDAV help'), findsOneWidget);
    expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, kToolbarHeight);
    expect(find.text('Before you start'), findsOneWidget);
    expect(find.textContaining('Free plan: 1 GB uploads/month and 3 GB downloads/month.'), findsOneWidget);
    expect(find.textContaining('坚果云'), findsNothing);
    expect(find.textContaining('绑定教程'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('official help action remains reachable in a narrow very-large-text window', (tester) async {
    final opened = <Uri>[];
    await pumpPage(
      tester,
      size: const Size(320, 480),
      textScale: 3,
      openExternalUrl: (uri) async {
        opened.add(uri);
        return true;
      },
    );

    final action = find.byKey(const ValueKey('webdav-help-official-link'));
    final scrollable = find
        .descendant(of: find.byKey(const ValueKey('webdav-help-scroll')), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(action, 400, scrollable: scrollable, maxScrolls: 100);
    await tester.pumpAndSettle();
    expect(action.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://help.jianguoyun.com/?p=2064')]);
  });

  testWidgets('setup screenshots open and close through an accessible preview action', (tester) async {
    await pumpPage(tester);
    final image = find.byKey(const ValueKey('webdav-help-image-1'));
    final scrollable = find
        .descendant(of: find.byKey(const ValueKey('webdav-help-scroll')), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(image, 240, scrollable: scrollable, maxScrolls: 30);
    await tester.tap(image);
    await tester.pumpAndSettle();

    expect(find.byType(PhotoView), findsOneWidget);
    final close = find.byTooltip('Close image preview');
    expect(close.hitTestable(), findsOneWidget);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byType(PhotoView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server address copy has a localized accessible action and confirmation', (tester) async {
    String? clipboardText;
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

    await pumpPage(tester);
    await tester.tap(find.byTooltip('Copy server address'));
    await tester.pumpAndSettle();

    expect(clipboardText, 'https://dav.jianguoyun.com/dav/');
    expect(find.text('Copied to clipboard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('English and Chinese expose the same complete WebDAV help key set', () {
    final englishKeys = english.keys.where((key) => key.startsWith('webdav_help_')).toSet();
    final chineseKeys = chinese.keys.where((key) => key.startsWith('webdav_help_')).toSet();
    final hanCharacters = RegExp(r'[\u4e00-\u9fff]');
    expect(englishKeys, chineseKeys);
    expect(englishKeys.length, greaterThanOrEqualTo(35));
    for (final key in englishKeys) {
      expect(english[key], isA<String>().having((value) => value.trim(), key, isNotEmpty));
      expect(chinese[key], isA<String>().having((value) => value.trim(), key, isNotEmpty));
      expect(english[key], isNot(matches(hanCharacters)));
    }
  });
}

class _Translations extends AssetLoader {
  const _Translations(this.values);

  final Map<String, dynamic> values;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}
