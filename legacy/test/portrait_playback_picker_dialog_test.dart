import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/portrait_playback_picker_dialog.dart';
import 'package:pure_live/player/core/portrait_stream_support.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, Map<String, dynamic>> translations;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    translations = {
      for (final language in ['zh', 'en'])
        language: jsonDecode(await File('assets/translations/$language.json').readAsString()) as Map<String, dynamic>,
    };
  });

  for (final language in ['zh', 'en']) {
    testWidgets('$language orientation picker keeps choices and cancel reachable at 320x480 3x text', (tester) async {
      final context = await _pumpHost(tester, translations: translations, language: language, textScale: 3);
      unawaited(
        showDialog<PortraitOrientationPickerResult>(
          context: context,
          builder: (_) =>
              const PortraitOrientationPickerDialog(selected: PortraitOrientationOverride.automatic, remember: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('portrait-orientation-picker-cancel')).hitTestable(), findsOneWidget);
      await _scrollDialogUntilVisible(
        tester,
        dialogKey: 'portrait-orientation-picker-dialog',
        target: find.byKey(const ValueKey('portrait-room-remember-draft')),
      );
      expect(find.byKey(const ValueKey('portrait-room-remember-draft')).hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('portrait-orientation-picker-cancel')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$language display picker keeps all descriptions selectable at 320x480 3x text', (tester) async {
      final context = await _pumpHost(tester, translations: translations, language: language, textScale: 3);
      PortraitFullscreenDisplayMode? result;
      unawaited(
        showDialog<PortraitFullscreenDisplayMode>(
          context: context,
          builder: (_) =>
              const PortraitFullscreenDisplayModePickerDialog(selected: PortraitFullscreenDisplayMode.ambient),
        ).then((value) => result = value),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final cover = find.byKey(const ValueKey('portrait-fullscreen-display-cover'));
      await _scrollDialogUntilVisible(tester, dialogKey: 'portrait-fullscreen-display-picker-dialog', target: cover);
      expect(cover.hitTestable(), findsOneWidget);
      expect(find.byKey(const ValueKey('portrait-fullscreen-display-picker-cancel')).hitTestable(), findsOneWidget);
      await tester.tap(cover);
      await tester.pumpAndSettle();

      expect(result, PortraitFullscreenDisplayMode.cover);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('orientation remember switch is committed only with an orientation result', (tester) async {
    final context = await _pumpHost(tester, translations: translations, language: 'en');
    PortraitOrientationPickerResult? result;
    var completed = false;

    void open() {
      unawaited(
        showDialog<PortraitOrientationPickerResult>(
          context: context,
          builder: (_) =>
              const PortraitOrientationPickerDialog(selected: PortraitOrientationOverride.automatic, remember: true),
        ).then((value) {
          result = value;
          completed = true;
        }),
      );
    }

    open();
    await tester.pumpAndSettle();
    await _scrollDialogUntilVisible(
      tester,
      dialogKey: 'portrait-orientation-picker-dialog',
      target: find.byKey(const ValueKey('portrait-room-remember-draft')),
    );
    await tester.tap(find.byKey(const ValueKey('portrait-room-remember-draft')));
    await tester.pump();
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(result, isNull);

    completed = false;
    open();
    await tester.pumpAndSettle();
    await _scrollDialogUntilVisible(
      tester,
      dialogKey: 'portrait-orientation-picker-dialog',
      target: find.byKey(const ValueKey('portrait-room-remember-draft')),
    );
    await tester.tap(find.byKey(const ValueKey('portrait-room-remember-draft')));
    await tester.pump();
    await _scrollDialogUntilVisible(
      tester,
      dialogKey: 'portrait-orientation-picker-dialog',
      target: find.byKey(const ValueKey('portrait-room-override-landscape')),
      alignToEnd: false,
    );
    await tester.tap(find.byKey(const ValueKey('portrait-room-override-landscape')));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(result?.orientation, PortraitOrientationOverride.landscape);
    expect(result?.remember, isFalse);
  });
}

Future<BuildContext> _pumpHost(
  WidgetTester tester, {
  required Map<String, Map<String, dynamic>> translations,
  required String language,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(320, 480);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  late BuildContext hostContext;
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: [Locale(language)],
      startLocale: Locale(language),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: _LoadedTranslations(translations),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: context.locale,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              hostContext = context;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return hostContext;
}

Future<void> _scrollDialogUntilVisible(
  WidgetTester tester, {
  required String dialogKey,
  required Finder target,
  bool alignToEnd = true,
}) async {
  expect(find.byKey(ValueKey(dialogKey)), findsOneWidget);
  await Scrollable.ensureVisible(target.evaluate().single, alignment: alignToEnd ? 0.5 : 0, duration: Duration.zero);
  await tester.pumpAndSettle();
}

class _LoadedTranslations extends AssetLoader {
  const _LoadedTranslations(this.translations);

  final Map<String, Map<String, dynamic>> translations;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => translations[locale.languageCode]!;
}
