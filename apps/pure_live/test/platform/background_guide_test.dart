// O01.3 (docs/O-Android系统集成/O01-通知和前台服务/O01.3-后台播放增强): which system build the
// phone runs, the steps for it, and the channel (`pure_live/background_guide`).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/platform/background_guide.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the system build', () {
    for (final (manufacturer, brand, props, display, family, label) in [
      (
        'Xiaomi',
        'Redmi',
        {'ro.mi.os.version.name': 'OS2.0', 'ro.miui.ui.version.name': 'V816'},
        '',
        RomFamily.xiaomi,
        'HyperOS 2.0',
      ),
      ('Xiaomi', 'POCO', {'ro.miui.ui.version.name': 'V140'}, '', RomFamily.xiaomi, 'MIUI 14'),
      ('Xiaomi', 'Xiaomi', {'ro.miui.ui.version.name': 'V125'}, '', RomFamily.xiaomi, 'MIUI 12.5'),
      ('OPPO', 'OPPO', {'ro.build.version.oplusrom': 'V15.0.0'}, '', RomFamily.oppo, 'ColorOS 15.0.0'),
      ('OPPO', 'OPPO', {'ro.build.version.opporom': 'V13.1'}, '', RomFamily.oppo, 'ColorOS 13.1'),
      ('OnePlus', 'OnePlus', {'ro.oxygen.version': '14.0'}, '', RomFamily.oppo, 'OxygenOS 14.0'),
      ('realme', 'realme', {'ro.build.version.realmeui': 'V5.0'}, '', RomFamily.oppo, 'realme UI 5.0'),
      (
        'vivo',
        'iQOO',
        {'ro.vivo.os.name': 'OriginOS', 'ro.vivo.os.version': '5.0'},
        '',
        RomFamily.vivo,
        'OriginOS 5.0',
      ),
      (
        'vivo',
        'vivo',
        {'ro.vivo.os.name': 'Funtouch', 'ro.vivo.os.version': '13.0'},
        '',
        RomFamily.vivo,
        'Funtouch OS 13.0',
      ),
      ('HUAWEI', 'HUAWEI', {'hw_sc.build.platform.version': '4.2.0'}, '', RomFamily.huawei, 'HarmonyOS 4.2.0'),
      ('HUAWEI', 'HUAWEI', {'ro.build.version.emui': 'EmotionUI_12.0.0'}, '', RomFamily.huawei, 'EMUI 12.0.0'),
      ('HONOR', 'HONOR', {'ro.build.version.magic': 'MagicOS_8.0'}, '', RomFamily.honor, 'MagicOS 8.0'),
      ('samsung', 'samsung', {'ro.build.version.oneui': '60100'}, '', RomFamily.samsung, 'One UI 6.1'),
      ('samsung', 'samsung', {'ro.build.version.oneui': '70000'}, '', RomFamily.samsung, 'One UI 7'),
      ('Meizu', 'meizu', <String, String>{}, 'Flyme 10.5.0.1A', RomFamily.meizu, 'Flyme 10.5.0.1'),
      ('Google', 'google', <String, String>{}, '', RomFamily.other, 'Google'),
    ]) {
      test('$manufacturer ($brand): $label', () {
        final rom = detectRom(manufacturer: manufacturer, brand: brand, sdk: 37, display: display, props: props);
        expect(rom.family, family);
        expect(rom.romLabel, label);
        expect(rom.androidVersion, '17');
      });
    }

    test('the brand decides when the maker is unknown; no properties still names the family', () {
      expect(romFamilyOf('unknown', 'Redmi'), RomFamily.xiaomi);
      expect(romFamilyOf('', 'iqoo'), RomFamily.vivo);
      expect(detectRom(manufacturer: 'Xiaomi').romLabel, 'MIUI');
      expect(detectRom(manufacturer: 'HONOR').romLabel, 'MagicOS');
      expect(const RomInfo(family: RomFamily.other, sdk: 26).androidVersion, '8.0');
      expect(const RomInfo(family: RomFamily.other, sdk: 40).androidVersion, 'API 40');
    });
  });

  group('the steps', () {
    BackgroundStatus status({
      String manufacturer = 'Xiaomi',
      bool notifications = true,
      bool? mediaChannel = true,
      bool battery = true,
      bool restricted = false,
      DataSaver dataSaver = DataSaver.off,
    }) => BackgroundStatus(
      rom: detectRom(manufacturer: manufacturer),
      notifications: notifications,
      mediaChannel: mediaChannel,
      batteryUnrestricted: battery,
      backgroundRestricted: restricted,
      dataSaver: dataSaver,
    );

    test("Android's readable checks first, then the vendor's, which only the user can check", () {
      final steps = guideSteps(status());
      expect(
        [for (final step in steps) step.id],
        ['notifications', 'battery', 'xiaomi_autostart', 'xiaomi_battery', 'lock_recents'],
      );
      expect(
        [for (final step in steps) step.check],
        [GuideCheck.ok, GuideCheck.ok, GuideCheck.manual, GuideCheck.manual, GuideCheck.manual],
      );
      expect(pendingSteps(steps), 0);
    });

    test('what is read in the way counts; restriction and Data Saver only show when they apply', () {
      final steps = guideSteps(
        status(notifications: false, battery: false, restricted: true, dataSaver: DataSaver.restricted),
      );
      expect([for (final step in steps.take(4)) step.id], ['notifications', 'battery', 'restricted', 'data_saver']);
      expect(pendingSteps(steps), 4);
      expect(steps.first.action, GuideAction.notifications);
      expect(guideSteps(status(dataSaver: DataSaver.allowed)).any((step) => step.id == 'data_saver'), isFalse);
    });

    test('the media category off: in the way, its own page first', () {
      final step = guideSteps(status(mediaChannel: false)).first;
      expect(step.check, GuideCheck.todo);
      expect(step.problemKey, 'background_guide_media_channel_off');
      expect(step.action, GuideAction.pages);
      expect(step.pages.first.extras['android.provider.extra.CHANNEL_ID'], mediaNotificationChannel);
      // Never created yet (nothing played in the background): not in the way.
      expect(guideSteps(status(mediaChannel: null)).first.check, GuideCheck.ok);
    });

    test('every vendor list of pages ends with the app details (the fallback)', () {
      for (final family in RomFamily.values) {
        for (final step in vendorSteps(family)) {
          if (step.action == GuideAction.none) {
            expect(step.pages, isEmpty, reason: step.id);
            continue;
          }
          expect(step.pages.last, SystemPage.appDetails, reason: step.id);
          expect(step.pages.last.isAppDetails, isTrue);
        }
      }
      expect(vendorSteps(RomFamily.other), isEmpty);
      expect(hasVendorSteps(RomFamily.other), isFalse);
      expect(hasVendorSteps(RomFamily.samsung), isTrue);
    });

    test("Xiaomi's power page gets this app's package and name", () {
      final page = vendorSteps(RomFamily.xiaomi).firstWhere((step) => step.id == 'xiaomi_battery').pages.first;
      expect(page.toMap(), {
        'action': null,
        'package': 'com.miui.powerkeeper',
        'class': 'com.miui.powerkeeper.ui.HiddenAppsConfigActivity',
        'packageUri': false,
        'extras': {'package_name': '{package}', 'package_label': '{label}'},
      });
    });
  });

  group('the channel', () {
    const name = MethodChannel('pure_live/background_guide');
    final calls = <MethodCall>[];

    tearDown(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(name, null);
    });

    void answer(Object? Function(MethodCall call) reply) =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(name, (call) async {
          calls.add(call);
          return reply(call);
        });

    test('status reads the map; missing values read as fine', () async {
      answer(
        (_) => {
          'sdk': 35,
          'manufacturer': 'vivo',
          'brand': 'vivo',
          'model': 'V2309A',
          'props': {'ro.vivo.os.name': 'OriginOS', 'ro.vivo.os.version': '4.0'},
          'notifications': true,
          'mediaChannel': 'missing',
          'batteryUnrestricted': false,
          'backgroundRestricted': true,
          'dataSaver': 'restricted',
          'powerSave': true,
        },
      );
      final status = (await const BackgroundGuideChannel(android: true).status())!;
      expect(status.rom.family, RomFamily.vivo);
      expect(status.rom.romLabel, 'OriginOS 4.0');
      expect(status.rom.androidVersion, '15');
      expect(status.mediaChannel, isNull);
      expect(status.batteryUnrestricted, isFalse);
      expect(status.backgroundRestricted, isTrue);
      expect(status.dataSaver, DataSaver.restricted);
      expect(status.powerSave, isTrue);

      final empty = BackgroundStatus.fromMap(const {});
      expect(empty.rom.family, RomFamily.other);
      expect(empty.notifications, isTrue);
      expect(empty.batteryUnrestricted, isTrue);
    });

    test('open sends the pages in order and answers the one that opened', () async {
      answer((_) => 1);
      final opened = await const BackgroundGuideChannel(android: true).open(vendorSteps(RomFamily.oppo).first.pages);
      expect(opened, 1);
      final pages = (calls.single.arguments as Map<Object?, Object?>)['pages']! as List<Object?>;
      expect(pages, hasLength(4));
      expect((pages.last! as Map)['action'], 'android.settings.APPLICATION_DETAILS_SETTINGS');
      expect((pages.last! as Map)['packageUri'], isTrue);
    });

    test('a failing native side reads as nothing, never throws', () async {
      answer((_) => throw PlatformException(code: 'boom'));
      expect(await const BackgroundGuideChannel(android: true).status(), isNull);
      expect(await const BackgroundGuideChannel(android: true).open(const [SystemPage.appDetails]), -1);
    });

    test('elsewhere than Android nothing is asked', () async {
      answer((_) => fail('not asked'));
      expect(await const BackgroundGuideChannel(android: false).status(), isNull);
      expect(await const BackgroundGuideChannel(android: false).open(const [SystemPage.appDetails]), -1);
      expect(calls, isEmpty);
    });
  });
}
