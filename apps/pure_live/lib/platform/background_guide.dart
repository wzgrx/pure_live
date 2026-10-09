import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// "后台播放检查" (docs/O-Android系统集成/O01-通知和前台服务/O01.3-后台播放增强): what this phone's
// system does to an app playing in the background, read where Android lets
// an app read it, and the system pages to change it, per vendor build.
// The vendor knowledge lives here (tested); the native side
// (`BackgroundGuidePlugin.kt`, `pure_live/background_guide`) only reads the
// state and opens the pages it is given.

/// The family of the phone's system build.
enum RomFamily {
  /// Xiaomi, Redmi, POCO: MIUI or HyperOS.
  xiaomi,

  /// OPPO, OnePlus, realme: ColorOS (OxygenOS and realme UI are built on it).
  oppo,

  /// vivo, iQOO: OriginOS or Funtouch OS.
  vivo,

  /// Huawei: EMUI or HarmonyOS.
  huawei,

  /// Honor: MagicOS (EMUI before).
  honor,

  /// Samsung: One UI.
  samsung,

  /// Meizu: Flyme.
  meizu,

  /// Anything else (Pixel, Motorola, Sony, emulators): Android's own pages.
  other,
}

/// The phone and its system build.
@immutable
final class RomInfo {
  /// Creates the description.
  const new({
    required this.family,
    this.manufacturer = '',
    this.model = '',
    this.sdk = 0,
    this.romName = '',
    this.romVersion = '',
  });

  /// The family.
  final RomFamily family;

  /// `Build.MANUFACTURER` as the phone says it.
  final String manufacturer;

  /// `Build.MODEL`.
  final String model;

  /// `Build.VERSION.SDK_INT`.
  final int sdk;

  /// The vendor build's name ("HyperOS", "ColorOS"), empty when unknown.
  final String romName;

  /// Its version ("2.0"), empty when unknown.
  final String romVersion;

  /// "HyperOS 2.0", or the family's usual name, or the manufacturer.
  String get romLabel {
    if (romName.isEmpty) return manufacturer;
    return romVersion.isEmpty ? romName : '$romName $romVersion';
  }

  /// The Android version for the API level (for the device row).
  String get androidVersion => switch (sdk) {
    <= 0 => '',
    26 => '8.0',
    27 => '8.1',
    28 => '9',
    29 => '10',
    30 => '11',
    31 => '12',
    32 => '12L',
    33 => '13',
    34 => '14',
    35 => '15',
    36 => '16',
    37 => '17',
    _ => 'API $sdk',
  };
}

/// The family of [manufacturer] or [brand] (lower or upper case).
RomFamily romFamilyOf(String manufacturer, [String brand = '']) {
  for (final name in [manufacturer.trim().toLowerCase(), brand.trim().toLowerCase()]) {
    switch (name) {
      case 'xiaomi' || 'redmi' || 'poco' || 'blackshark':
        return RomFamily.xiaomi;
      case 'oppo' || 'oneplus' || 'realme':
        return RomFamily.oppo;
      case 'vivo' || 'iqoo':
        return RomFamily.vivo;
      case 'huawei':
        return RomFamily.huawei;
      case 'honor':
        return RomFamily.honor;
      case 'samsung':
        return RomFamily.samsung;
      case 'meizu':
        return RomFamily.meizu;
    }
  }
  return RomFamily.other;
}

String _strip(String value, String prefix) =>
    value.toLowerCase().startsWith(prefix.toLowerCase()) ? value.substring(prefix.length) : value;

/// "V140" → "14", "V125" → "12.5", "V12" → "12" (MIUI's version name).
String _miuiVersion(String name) {
  final digits = _strip(name.trim(), 'V');
  if (!RegExp(r'^\d+$').hasMatch(digits)) return digits;
  if (digits.length == 3) {
    final major = digits.substring(0, 2);
    final minor = digits.substring(2);
    return minor == '0' ? major : '$major.$minor';
  }
  return digits;
}

/// The phone's build from what the native side read: `Build` fields and
/// the vendors' system properties (missing ones are empty).
RomInfo detectRom({
  required String manufacturer,
  String brand = '',
  String model = '',
  int sdk = 0,
  String display = '',
  Map<String, String> props = const {},
}) {
  final family = romFamilyOf(manufacturer, brand);
  String prop(String key) => (props[key] ?? '').trim();
  var name = '';
  var version = '';
  switch (family) {
    case RomFamily.xiaomi:
      final hyper = prop('ro.mi.os.version.name');
      final miui = prop('ro.miui.ui.version.name');
      if (hyper.isNotEmpty) {
        name = 'HyperOS';
        version = _strip(hyper, 'OS');
      } else if (miui.isNotEmpty) {
        name = 'MIUI';
        version = _miuiVersion(miui);
      } else {
        name = 'MIUI';
      }
    case RomFamily.oppo:
      final realme = prop('ro.build.version.realmeui');
      final color = prop('ro.build.version.oplusrom').isNotEmpty
          ? prop('ro.build.version.oplusrom')
          : prop('ro.build.version.opporom');
      if (realme.isNotEmpty) {
        name = 'realme UI';
        version = _strip(realme, 'V');
      } else if (manufacturer.toLowerCase() == 'oneplus' && prop('ro.oxygen.version').isNotEmpty) {
        name = 'OxygenOS';
        version = prop('ro.oxygen.version');
      } else {
        name = 'ColorOS';
        version = _strip(color, 'V');
      }
    case RomFamily.vivo:
      final os = prop('ro.vivo.os.name');
      final displayId = prop('ro.vivo.os.build.display.id');
      name = os.toLowerCase().contains('origin') || displayId.toLowerCase().contains('origin')
          ? 'OriginOS'
          : 'Funtouch OS';
      version = prop('ro.vivo.os.version');
    case RomFamily.huawei:
      final harmony = prop('hw_sc.build.platform.version');
      final emui = prop('ro.build.version.emui');
      if (harmony.isNotEmpty) {
        name = 'HarmonyOS';
        version = harmony;
      } else {
        name = 'EMUI';
        version = _strip(emui, 'EmotionUI_');
      }
    case RomFamily.honor:
      final magic = prop('ro.build.version.magic');
      final emui = prop('ro.build.version.emui');
      if (magic.isNotEmpty) {
        name = 'MagicOS';
        version = _strip(magic, 'MagicOS_');
      } else if (emui.isNotEmpty) {
        name = 'MagicUI';
        version = _strip(emui, 'EmotionUI_');
      } else {
        name = 'MagicOS';
      }
    case RomFamily.samsung:
      name = 'One UI';
      // "60100" is 6.1.
      final code = int.tryParse(prop('ro.build.version.oneui'));
      if (code != null && code >= 10000) {
        final minor = (code ~/ 100) % 100;
        version = '${code ~/ 10000}${minor == 0 ? '' : '.$minor'}';
      }
    case RomFamily.meizu:
      name = 'Flyme';
      final match = RegExp(r'Flyme\s*(?:OS\s*)?([\d.]+)', caseSensitive: false).firstMatch(display);
      version = match?.group(1) ?? '';
    case RomFamily.other:
      break;
  }
  return RomInfo(
    family: family,
    manufacturer: manufacturer.trim(),
    model: model.trim(),
    sdk: sdk,
    romName: name,
    romVersion: version.trim(),
  );
}

/// One system page to open; [BackgroundGuideChannel.open] tries a list in
/// order and stops at the first that opens.
@immutable
final class SystemPage {
  /// Creates the page: an intent [action], or an explicit [package] and
  /// [className], or both.
  const new({this.action, this.package, this.className, this.packageUri = false, this.extras = const {}});

  /// This app's details page ("应用信息"), which every vendor has: the
  /// last resort of every list.
  static const SystemPage appDetails = SystemPage(
    action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
    packageUri: true,
  );

  /// The intent's action.
  final String? action;

  /// The activity's package.
  final String? package;

  /// The activity's class (with its package).
  final String? className;

  /// Whether the intent's data is `package:<this app>`.
  final bool packageUri;

  /// String extras; `{package}` and `{label}` become this app's package
  /// and name.
  final Map<String, String> extras;

  /// Whether this is [appDetails].
  bool get isAppDetails => action == appDetails.action && package == null;

  /// What the channel receives.
  Map<String, Object?> toMap() => {
    'action': action,
    'package': package,
    'class': className,
    'packageUri': packageUri,
    'extras': extras,
  };

  @override
  bool operator ==(Object other) =>
      other is SystemPage &&
      other.action == action &&
      other.package == package &&
      other.className == className &&
      other.packageUri == packageUri &&
      mapEquals(other.extras, extras);

  @override
  int get hashCode => Object.hash(action, package, className, packageUri, Object.hashAll(extras.entries));

  @override
  String toString() => 'SystemPage(${className ?? action})';
}

SystemPage _component(String package, String className, {Map<String, String> extras = const {}}) =>
    SystemPage(package: package, className: className, extras: extras);

/// Where a step stands.
enum GuideCheck {
  /// Read and fine.
  ok,

  /// Read and in the way of background play.
  todo,

  /// Android does not let an app read it: the user checks in the system.
  manual,
}

/// What tapping a step does.
enum GuideAction {
  /// The notification permission's dialog or settings page.
  notifications,

  /// The battery exemption's system dialog, else [GuideStep.pages].
  battery,

  /// [GuideStep.pages] in order.
  pages,

  /// Nothing to open: the step says what to do ([GuideStep.howKey]).
  none,
}

/// One thing that keeps background play alive on this phone.
@immutable
final class GuideStep {
  /// Creates the step.
  const new({
    required this.id,
    required this.titleKey,
    required this.howKey,
    required this.check,
    this.action = GuideAction.pages,
    this.pages = const [],
    this.problemKey,
  });

  /// Stable id (the row's key is `background-guide-<id>`).
  final String id;

  /// The title's translation key.
  final String titleKey;

  /// The translation key of what to do.
  final String howKey;

  /// Where it stands.
  final GuideCheck check;

  /// What a tap does.
  final GuideAction action;

  /// The system pages to try, the app's details last.
  final List<SystemPage> pages;

  /// Replaces [howKey] while [check] is [GuideCheck.todo] (what is wrong).
  final String? problemKey;
}

/// The Data Saver's say over this app's background data.
enum DataSaver {
  /// Off.
  off,

  /// On, and this app is let through.
  allowed,

  /// On: no mobile data in the background.
  restricted,
}

/// What the native side read ([BackgroundGuideChannel.status]).
@immutable
final class BackgroundStatus {
  /// Creates the state.
  const new({
    required this.rom,
    this.notifications = true,
    this.mediaChannel,
    this.batteryUnrestricted = true,
    this.backgroundRestricted = false,
    this.dataSaver = DataSaver.off,
    this.powerSave = false,
  });

  /// Reads the channel's map; missing values read as fine.
  factory fromMap(Map<Object?, Object?> map) {
    String text(String key) => map[key] is String ? map[key]! as String : '';
    final props = <String, String>{
      if (map['props'] case final Map<Object?, Object?> raw)
        for (final MapEntry(:key, :value) in raw.entries)
          if (key is String && value is String) key: value,
    };
    return BackgroundStatus(
      rom: detectRom(
        manufacturer: text('manufacturer'),
        brand: text('brand'),
        model: text('model'),
        sdk: map['sdk'] is int ? map['sdk']! as int : 0,
        display: text('display'),
        props: props,
      ),
      notifications: map['notifications'] != false,
      mediaChannel: switch (map['mediaChannel']) {
        'on' => true,
        'off' => false,
        _ => null,
      },
      batteryUnrestricted: map['batteryUnrestricted'] != false,
      backgroundRestricted: map['backgroundRestricted'] == true,
      dataSaver: switch (map['dataSaver']) {
        'restricted' => DataSaver.restricted,
        'allowed' => DataSaver.allowed,
        _ => DataSaver.off,
      },
      powerSave: map['powerSave'] == true,
    );
  }

  /// The phone.
  final RomInfo rom;

  /// Notifications are allowed for the app.
  final bool notifications;

  /// The media notification's channel ("媒体播放") is on; null before it was
  /// ever created (nothing played in the background yet).
  final bool? mediaChannel;

  /// The app is exempt from battery optimisation.
  final bool batteryUnrestricted;

  /// The system restricts the app in the background (Android 9+: "受限").
  final bool backgroundRestricted;

  /// The Data Saver.
  final DataSaver dataSaver;

  /// The battery saver is on (it may stop background work).
  final bool powerSave;
}

const SystemPage _appDetails = SystemPage.appDetails;

/// The steps for [status]: Android's readable ones first (only those that
/// apply), then the vendor's (only the user can check them).
List<GuideStep> guideSteps(BackgroundStatus status) {
  final notificationsOk = status.notifications && status.mediaChannel != false;
  return [
    GuideStep(
      id: 'notifications',
      titleKey: 'background_guide_notifications',
      howKey: 'background_guide_notifications_how',
      problemKey: status.notifications ? 'background_guide_media_channel_off' : null,
      check: notificationsOk ? GuideCheck.ok : GuideCheck.todo,
      action: status.notifications ? GuideAction.pages : GuideAction.notifications,
      pages: [
        if (status.notifications && status.mediaChannel == false)
          const SystemPage(
            action: 'android.settings.CHANNEL_NOTIFICATION_SETTINGS',
            extras: {
              'android.provider.extra.APP_PACKAGE': '{package}',
              'android.provider.extra.CHANNEL_ID': mediaNotificationChannel,
            },
          ),
        const SystemPage(
          action: 'android.settings.APP_NOTIFICATION_SETTINGS',
          extras: {'android.provider.extra.APP_PACKAGE': '{package}'},
        ),
        _appDetails,
      ],
    ),
    GuideStep(
      id: 'battery',
      titleKey: 'background_guide_battery',
      howKey: 'background_guide_battery_how',
      check: status.batteryUnrestricted ? GuideCheck.ok : GuideCheck.todo,
      action: GuideAction.battery,
      pages: const [
        SystemPage(action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS'),
        _appDetails,
      ],
    ),
    if (status.backgroundRestricted)
      const GuideStep(
        id: 'restricted',
        titleKey: 'background_guide_restricted',
        howKey: 'background_guide_restricted_how',
        check: GuideCheck.todo,
        pages: [_appDetails],
      ),
    if (status.dataSaver == DataSaver.restricted)
      const GuideStep(
        id: 'data_saver',
        titleKey: 'background_guide_data_saver',
        howKey: 'background_guide_data_saver_how',
        check: GuideCheck.todo,
        pages: [
          SystemPage(action: 'android.settings.IGNORE_BACKGROUND_DATA_RESTRICTIONS_SETTINGS', packageUri: true),
          _appDetails,
        ],
      ),
    ...vendorSteps(status.rom.family),
  ];
}

/// The vendor's own steps for [family] (every list of pages ends with the
/// app's details page).
List<GuideStep> vendorSteps(RomFamily family) => switch (family) {
  RomFamily.xiaomi => [
    GuideStep(
      id: 'xiaomi_autostart',
      titleKey: 'background_guide_autostart',
      howKey: 'background_guide_xiaomi_autostart_how',
      check: GuideCheck.manual,
      pages: [
        _component('com.miui.securitycenter', 'com.miui.permcenter.autostart.AutoStartManagementActivity'),
        _appDetails,
      ],
    ),
    GuideStep(
      id: 'xiaomi_battery',
      titleKey: 'background_guide_xiaomi_battery',
      howKey: 'background_guide_xiaomi_battery_how',
      check: GuideCheck.manual,
      pages: [
        _component(
          'com.miui.powerkeeper',
          'com.miui.powerkeeper.ui.HiddenAppsConfigActivity',
          extras: {'package_name': '{package}', 'package_label': '{label}'},
        ),
        _appDetails,
      ],
    ),
    _lockRecents,
  ],
  RomFamily.oppo => [
    GuideStep(
      id: 'oppo_autostart',
      titleKey: 'background_guide_autostart',
      howKey: 'background_guide_oppo_autostart_how',
      check: GuideCheck.manual,
      pages: [
        _component('com.coloros.safecenter', 'com.coloros.safecenter.startupapp.StartupAppListActivity'),
        _component('com.coloros.safecenter', 'com.coloros.safecenter.permission.startup.StartupAppListActivity'),
        _component('com.oppo.safe', 'com.oppo.safe.permission.startup.StartupAppListActivity'),
        _appDetails,
      ],
    ),
    GuideStep(
      id: 'oppo_battery',
      titleKey: 'background_guide_oppo_battery',
      howKey: 'background_guide_oppo_battery_how',
      check: GuideCheck.manual,
      pages: [
        _component('com.coloros.oppoguardelf', 'com.coloros.powermanager.fuelgaue.PowerUsageModelActivity'),
        _appDetails,
      ],
    ),
    _lockRecents,
  ],
  RomFamily.vivo => [
    GuideStep(
      id: 'vivo_power',
      titleKey: 'background_guide_vivo_power',
      howKey: 'background_guide_vivo_power_how',
      check: GuideCheck.manual,
      pages: [
        _component('com.vivo.abe', 'com.vivo.applicationbehaviorengine.ui.ExcessivePowerManagerActivity'),
        _component('com.iqoo.powersaving', 'com.iqoo.powersaving.PowerSavingManagerActivity'),
        _appDetails,
      ],
    ),
    GuideStep(
      id: 'vivo_autostart',
      titleKey: 'background_guide_autostart',
      howKey: 'background_guide_vivo_autostart_how',
      check: GuideCheck.manual,
      pages: [
        _component('com.vivo.permissionmanager', 'com.vivo.permissionmanager.activity.BgStartUpManagerActivity'),
        _component('com.iqoo.secure', 'com.iqoo.secure.ui.phoneoptimize.BgStartUpManager'),
        _appDetails,
      ],
    ),
    _lockRecents,
  ],
  RomFamily.huawei => [
    GuideStep(
      id: 'huawei_launch',
      titleKey: 'background_guide_huawei_launch',
      howKey: 'background_guide_huawei_launch_how',
      check: GuideCheck.manual,
      pages: [
        _component('com.huawei.systemmanager', 'com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity'),
        _component(
          'com.huawei.systemmanager',
          'com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity',
        ),
        _component('com.huawei.systemmanager', 'com.huawei.systemmanager.optimize.process.ProtectActivity'),
        _appDetails,
      ],
    ),
    _lockRecents,
  ],
  RomFamily.honor => [
    GuideStep(
      id: 'honor_launch',
      titleKey: 'background_guide_huawei_launch',
      howKey: 'background_guide_huawei_launch_how',
      check: GuideCheck.manual,
      pages: [
        _component('com.hihonor.systemmanager', 'com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity'),
        _component('com.huawei.systemmanager', 'com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity'),
        _appDetails,
      ],
    ),
    _lockRecents,
  ],
  RomFamily.samsung => [
    const GuideStep(
      id: 'samsung_battery',
      titleKey: 'background_guide_samsung_battery',
      howKey: 'background_guide_samsung_battery_how',
      check: GuideCheck.manual,
      pages: [_appDetails],
    ),
    GuideStep(
      id: 'samsung_sleeping',
      titleKey: 'background_guide_samsung_sleeping',
      howKey: 'background_guide_samsung_sleeping_how',
      check: GuideCheck.manual,
      pages: [
        _component('com.samsung.android.lool', 'com.samsung.android.sm.battery.ui.BatteryActivity'),
        _component('com.samsung.android.lool', 'com.samsung.android.sm.ui.battery.BatteryActivity'),
        _appDetails,
      ],
    ),
  ],
  RomFamily.meizu => [
    GuideStep(
      id: 'meizu_background',
      titleKey: 'background_guide_meizu_background',
      howKey: 'background_guide_meizu_background_how',
      check: GuideCheck.manual,
      pages: [_component('com.meizu.safe', 'com.meizu.safe.permission.SmartBGActivity'), _appDetails],
    ),
  ],
  RomFamily.other => const [],
};

const GuideStep _lockRecents = GuideStep(
  id: 'lock_recents',
  titleKey: 'background_guide_lock_recents',
  howKey: 'background_guide_lock_recents_how',
  check: GuideCheck.manual,
  action: GuideAction.none,
);

/// The media notification's channel (audio_service's
/// `androidNotificationChannelId` in `RoomMediaNotification`).
const String mediaNotificationChannel = 'com.mystyle.purelive.audio';

/// How many readable steps of [steps] are in the way.
int pendingSteps(List<GuideStep> steps) => steps.where((step) => step.check == GuideCheck.todo).length;

/// Whether the vendor of [family] has steps only the user can check (the
/// one-time hint after background play turns on).
bool hasVendorSteps(RomFamily family) => vendorSteps(family).isNotEmpty;

/// `pure_live/background_guide` (`BackgroundGuidePlugin.kt`): the state and
/// the system pages. Elsewhere than Android, and when the native side
/// fails, there is nothing ([status] null, [open] -1).
class BackgroundGuideChannel {
  /// Creates the channel; `android` defaults to the platform.
  const new({this.channel = const MethodChannel('pure_live/background_guide'), this._android});

  /// The native channel.
  final MethodChannel channel;

  final bool? _android;

  /// Whether there is a guide (Android).
  bool get applies => _android ?? (!kIsWeb && Platform.isAndroid);

  /// What the native side reads now.
  Future<BackgroundStatus?> status() async {
    if (!applies) return null;
    try {
      final map = await channel.invokeMethod<Map<Object?, Object?>>('status');
      return map == null ? null : BackgroundStatus.fromMap(map);
    } on PlatformException catch (error) {
      log('status failed: ${error.message}', name: 'BackgroundGuide');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Opens the first of [pages] that opens; its index, or -1 when none did.
  Future<int> open(List<SystemPage> pages) async {
    if (!applies || pages.isEmpty) return -1;
    try {
      return await channel.invokeMethod<int>('open', {
            'pages': [for (final page in pages) page.toMap()],
          }) ??
          -1;
    } on PlatformException catch (error) {
      log('open failed: ${error.message}', name: 'BackgroundGuide');
      return -1;
    } on MissingPluginException {
      return -1;
    }
  }
}
