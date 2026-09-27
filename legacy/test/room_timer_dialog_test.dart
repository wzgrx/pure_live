import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/modules/live_play/dialogs/room_timer_dialog.dart';
import 'package:pure_live/modules/live_play/states/live_play_state.dart';
import 'package:pure_live/modules/live_play/states/ui_state.dart';
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

  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  testWidgets('cancel keeps an active room timer unchanged', (tester) async {
    final controller = _TimerController(enabled: true, minutes: 60);
    await _openHost(tester, controller: controller, translations: translations, language: 'en');
    await _showDialog(tester);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(controller.flagUpdates, isEmpty);
    expect(controller.minuteUpdates, isEmpty);
    expect(controller.commits, isEmpty);
    expect(controller.state.value.ui.closeTimeFlag, isTrue);
    expect(controller.state.value.ui.closeTimes, 60);
  });

  testWidgets('disabling commits one timer transaction and ignores an unfinished duration draft', (tester) async {
    final controller = _TimerController(enabled: true, minutes: 90);
    await _openHost(tester, controller: controller, translations: translations, language: 'en');
    await _showDialog(tester);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(controller.flagUpdates, isEmpty);
    expect(controller.minuteUpdates, isEmpty);
    expect(controller.commits, [(enabled: false, minutes: 90)]);
    expect(controller.state.value.ui.closeTimeFlag, isFalse);
    expect(controller.state.value.ui.closeTimes, 90);
  });

  testWidgets('enabled invalid duration stays open without changing the running timer', (tester) async {
    final controller = _TimerController(enabled: true, minutes: 45);
    await _openHost(tester, controller: controller, translations: translations, language: 'en');
    await _showDialog(tester);

    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.text('Confirm'));
    await tester.pump();

    expect(find.text('Current-room playback timer'), findsOneWidget);
    expect(find.text('Enter 1 minute to 365 days'), findsWidgets);
    expect(controller.commits, isEmpty);
    expect(controller.state.value.ui.closeTimeFlag, isTrue);
    expect(controller.state.value.ui.closeTimes, 45);
  });

  testWidgets('preset and custom duration commit exactly once', (tester) async {
    final controller = _TimerController(enabled: false, minutes: 30);
    await _openHost(tester, controller: controller, translations: translations, language: 'zh');
    await _showDialog(tester);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('120 分钟'));
    await tester.pump();
    expect((tester.widget<TextField>(find.byType(TextField))).controller!.text, '120');
    await tester.enterText(find.byType(TextField), '75');
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();

    expect(controller.commits, [(enabled: true, minutes: 75)]);
    expect(controller.state.value.ui.closeTimeFlag, isTrue);
    expect(controller.state.value.ui.closeTimes, 75);
  });

  testWidgets('320x480 at 3x text keeps timer content scrollable and actions reachable', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _TimerController(enabled: true, minutes: 60);
    await _openHost(tester, controller: controller, translations: translations, language: 'en', textScale: 3);
    await _showDialog(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Confirm').hitTestable(), findsOneWidget);
    final content = find.byKey(const ValueKey('room-timer-scroll'));
    expect(content, findsOneWidget);
    final scrollable = find.descendant(of: content, matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('480 min'), 100, scrollable: scrollable, maxScrolls: 20);
    expect(find.text('480 min').hitTestable(), findsOneWidget);
    expect(find.text('Cancel').hitTestable(), findsOneWidget);
    expect(find.text('Confirm').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openHost(
  WidgetTester tester, {
  required _TimerController controller,
  required Map<String, Map<String, dynamic>> translations,
  required String language,
  double textScale = 1,
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
                  key: const ValueKey('open-room-timer'),
                  onPressed: () => RoomTimerDialog.show(context: context, controller: controller),
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
  await tester.tap(find.byKey(const ValueKey('open-room-timer')));
  await tester.pumpAndSettle();
}

class _LoadedTranslations extends AssetLoader {
  const _LoadedTranslations(this.translations);
  final Map<String, Map<String, dynamic>> translations;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => translations[locale.languageCode]!;
}

class _TimerController extends GetxController implements LivePlayController {
  _TimerController({required bool enabled, required int minutes}) {
    state.value = LivePlayState(
      ui: UIState(closeTimeFlag: enabled, closeTimes: minutes),
    );
  }

  @override
  final Rx<LivePlayState> state = const LivePlayState().obs;
  final List<bool> flagUpdates = [];
  final List<int> minuteUpdates = [];
  final List<({bool enabled, int minutes})> commits = [];

  @override
  void updateTimerFlag(bool flag) {
    flagUpdates.add(flag);
    state.value = state.value.copyWith(ui: state.value.ui.copyWith(closeTimeFlag: flag));
  }

  @override
  void updateTimerTimes(int times) {
    minuteUpdates.add(times);
    state.value = state.value.copyWith(ui: state.value.ui.copyWith(closeTimes: times));
  }

  @override
  void applyRoomPlaybackTimer({required bool enabled, required int minutes}) {
    commits.add((enabled: enabled, minutes: minutes));
    state.value = state.value.copyWith(
      ui: state.value.ui.copyWith(closeTimeFlag: enabled, closeTimes: minutes),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
