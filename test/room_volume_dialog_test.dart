import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/services/settings/volume_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/modules/live_play/dialogs/room_volume_dialog.dart';
import 'package:pure_live/modules/live_play/states/live_play_state.dart';
import 'package:pure_live/player/core/live_room_volume_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, Map<String, dynamic>> translations;
  late _VolumeSettings volume;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    translations = {
      for (final language in ['zh', 'en'])
        language: jsonDecode(await File('assets/translations/$language.json').readAsString()) as Map<String, dynamic>,
    };
  });

  setUp(() {
    Get.testMode = true;
    volume = _VolumeSettings();
    Get.put<SettingsService>(_Settings(volume));
  });

  tearDown(() {
    Get.reset();
    Get.testMode = false;
  });

  test('room volume lookup and storage reject non-finite runtime values', () async {
    volume.defaultDesktopVolume.value = double.nan;
    volume.roomVolumes['room_vol_bilibili_1'] = double.infinity;

    expect(LiveRoomVolumeManager.getRoomVolume('bilibili', '1'), 1.0);
    await LiveRoomVolumeManager.saveRoomVolume('bilibili', '1', double.nan);
    expect(volume.roomVolumes['room_vol_bilibili_1'], double.infinity);
  });

  testWidgets('reset remains a cancelable draft', (tester) async {
    volume.globalVolumeMute.value = true;
    volume.defaultMobileVolume.value = 0.2;
    volume.defaultDesktopVolume.value = 0.3;
    await _openHost(tester, translations: translations, language: 'en');
    await _showDialog(tester);

    await tester.tap(find.text('Reset Default'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(volume.globalVolumeMute.value, isTrue);
    expect(volume.defaultMobileVolume.value, 0.2);
    expect(volume.defaultDesktopVolume.value, 0.3);
  });

  testWidgets('reset confirmation commits both defaults', (tester) async {
    volume.globalVolumeMute.value = true;
    volume.defaultMobileVolume.value = 0.2;
    volume.defaultDesktopVolume.value = 0.3;
    await _openHost(tester, translations: translations, language: 'en');
    await _showDialog(tester);

    await tester.tap(find.text('Reset Default'));
    await tester.pump();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(volume.globalVolumeMute.value, isFalse);
    expect(volume.defaultMobileVolume.value, 0.5);
    expect(volume.defaultDesktopVolume.value, 1.0);
  });

  testWidgets('confirm awaits one mobile apply before committing the draft', (tester) async {
    final applyGate = Completer<void>();
    final applied = <double>[];
    volume.globalVolumeMute.value = true;
    volume.defaultMobileVolume.value = 0.2;
    volume.defaultDesktopVolume.value = 0.3;
    await _openHost(
      tester,
      translations: translations,
      language: 'en',
      platformOverride: TargetPlatform.android,
      applyVolume: (value) {
        applied.add(value);
        return applyGate.future;
      },
    );
    await _showDialog(tester);

    await tester.tap(find.byKey(const ValueKey('room-volume-reset')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('room-volume-confirm')));
    await tester.tap(find.byKey(const ValueKey('room-volume-confirm')));
    await tester.pump();

    expect(applied, [0.5]);
    expect(volume.globalVolumeMute.value, isTrue);
    expect(volume.defaultMobileVolume.value, 0.2);
    expect(volume.defaultDesktopVolume.value, 0.3);
    expect(find.text('Room Volume'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('room-volume-confirm'))).onPressed, isNull);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Room Volume'), findsOneWidget);

    applyGate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Room Volume'), findsNothing);
    expect(volume.globalVolumeMute.value, isFalse);
    expect(volume.defaultMobileVolume.value, 0.5);
    expect(volume.defaultDesktopVolume.value, 1.0);
  });

  testWidgets('Windows confirmation applies the desktop draft', (tester) async {
    final applied = <double>[];
    volume.defaultMobileVolume.value = 0.2;
    volume.defaultDesktopVolume.value = 0.3;
    await _openHost(
      tester,
      translations: translations,
      language: 'en',
      platformOverride: TargetPlatform.windows,
      applyVolume: (value) async => applied.add(value),
    );
    await _showDialog(tester);

    await tester.tap(find.byKey(const ValueKey('room-volume-confirm')));
    await tester.pumpAndSettle();

    expect(applied, [0.3]);
  });

  testWidgets('global mute applies zero without changing either draft default', (tester) async {
    final applied = <double>[];
    volume.globalVolumeMute.value = true;
    volume.defaultMobileVolume.value = 0.2;
    volume.defaultDesktopVolume.value = 0.3;
    await _openHost(
      tester,
      translations: translations,
      language: 'en',
      platformOverride: TargetPlatform.android,
      applyVolume: (value) async => applied.add(value),
    );
    await _showDialog(tester);

    await tester.tap(find.byKey(const ValueKey('room-volume-confirm')));
    await tester.pumpAndSettle();

    expect(applied, [0.0]);
    expect(volume.globalVolumeMute.value, isTrue);
    expect(volume.defaultMobileVolume.value, 0.2);
    expect(volume.defaultDesktopVolume.value, 0.3);
  });

  testWidgets('apply failure retains both the dialog and persisted settings', (tester) async {
    volume.globalVolumeMute.value = true;
    volume.defaultMobileVolume.value = 0.2;
    volume.defaultDesktopVolume.value = 0.3;
    await _openHost(
      tester,
      translations: translations,
      language: 'en',
      platformOverride: TargetPlatform.android,
      applyVolume: (_) async => throw StateError('fixture failure'),
    );
    await _showDialog(tester);

    await tester.tap(find.byKey(const ValueKey('room-volume-reset')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('room-volume-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Room Volume'), findsOneWidget);
    expect(find.text('Failed to apply volume. Try again.'), findsOneWidget);
    expect(volume.globalVolumeMute.value, isTrue);
    expect(volume.defaultMobileVolume.value, 0.2);
    expect(volume.defaultDesktopVolume.value, 0.3);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('room-volume-confirm'))).onPressed, isNotNull);
  });

  testWidgets('invalid persisted defaults render as bounded draft values', (tester) async {
    volume.defaultMobileVolume.value = double.nan;
    volume.defaultDesktopVolume.value = double.infinity;
    await _openHost(tester, translations: translations, language: 'en');
    await _showDialog(tester);

    expect(find.text('50%'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320x480 at 3x text keeps every volume action reachable', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _openHost(tester, translations: translations, language: 'en', textScale: 3);
    await _showDialog(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Cancel').hitTestable(), findsOneWidget);
    expect(find.text('Confirm').hitTestable(), findsOneWidget);
    final content = find.byType(SingleChildScrollView).first;
    final scrollable = find.descendant(of: content, matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Reset Default'), 100, scrollable: scrollable, maxScrolls: 20);
    expect(find.text('Reset Default').hitTestable(), findsOneWidget);
    expect(find.text('Cancel').hitTestable(), findsOneWidget);
    expect(find.text('Confirm').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openHost(
  WidgetTester tester, {
  required Map<String, Map<String, dynamic>> translations,
  required String language,
  double textScale = 1,
  TargetPlatform? platformOverride,
  RoomVolumeApplier? applyVolume,
}) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('zh'), Locale('en')],
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
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  key: const ValueKey('open-room-volume'),
                  onPressed: () => RoomVolumeDialog.show(
                    context: context,
                    controller: _Controller(),
                    platformOverride: platformOverride,
                    applyVolume: applyVolume,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _showDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open-room-volume')));
  await tester.pumpAndSettle();
}

class _LoadedTranslations extends AssetLoader {
  const _LoadedTranslations(this.translations);
  final Map<String, Map<String, dynamic>> translations;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => translations[locale.languageCode]!;
}

class _Settings extends SettingsService {
  _Settings(this._volume);
  final _VolumeSettings _volume;

  @override
  VolumeSettingsController get vol => _volume;

  @override
  // This isolated dialog fixture has no other application services.
  // ignore: must_call_super
  void onInit() {}
}

class _VolumeSettings implements VolumeSettingsController {
  @override
  final defaultMobileVolume = 0.5.obs;
  @override
  final defaultDesktopVolume = 1.0.obs;
  @override
  final globalVolumeMute = false.obs;
  @override
  final Map<String, double> roomVolumes = <String, double>{};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Controller extends GetxController implements LivePlayController {
  @override
  final Rx<LivePlayState> state = const LivePlayState().obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
