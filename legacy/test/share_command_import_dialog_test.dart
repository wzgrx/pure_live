import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/widgets/share_command_import_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> english;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    english = jsonDecode(await File('assets/translations/en.json').readAsString()) as Map<String, dynamic>;
  });

  setUp(() {
    Get.testMode = true;
    Get.reset();
  });

  tearDown(() {
    Get.reset();
  });

  testWidgets('share import stays usable at 320x480 with 3x English text and returns explicit actions', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final room = LiveRoom(
      platform: 'very-long-platform-identity',
      roomId: 'very-long-room-identity-1234567890',
      title: 'A very long imported live room title that must wrap instead of overflowing',
      nick: 'A very long imported anchor identity',
    );
    bool? result;

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
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(3)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    onPressed: () async => result = await ShareCommandImportDialog.show(context: context, room: room),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LayoutBuilder), findsNothing);

    Future<void> openDialog() async {
      await tester.tap(find.text('Open').hitTestable());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(room.title!), findsOneWidget);
      expect(find.text(room.nick!), findsOneWidget);
      expect(find.text(room.platform!), findsOneWidget);
      expect(find.text(room.roomId!), findsOneWidget);
      await tester.ensureVisible(find.text(room.roomId!));
      await tester.pumpAndSettle();
      final roomIdRect = tester.getRect(find.text(room.roomId!));
      expect(roomIdRect.top, greaterThanOrEqualTo(0));
      expect(roomIdRect.bottom, lessThanOrEqualTo(480));
      for (final label in ['Cancel', 'Enter']) {
        final action = find.text(label).hitTestable();
        expect(action, findsOneWidget);
        final rect = tester.getRect(action);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.bottom, lessThanOrEqualTo(480));
      }
    }

    await openDialog();
    await tester.tap(find.text('Cancel').hitTestable());
    await tester.pumpAndSettle();
    expect(result, isFalse);

    result = null;
    await openDialog();
    await tester.tap(find.text('Enter').hitTestable());
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(tester.takeException(), isNull);
  });
}

class _Translations extends AssetLoader {
  const _Translations(this.values);

  final Map<String, dynamic> values;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}
