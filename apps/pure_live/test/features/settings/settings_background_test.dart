// O01.3 (docs/O-Android系统集成/O01-通知和前台服务/O01.3-后台播放增强): "后台播放设置" — the
// row on the video page, its page with this phone's checks and the
// vendor's steps, the system pages and their fallbacks, the three away
// switches, and the one-time hint after background play turns on.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/settings/background_guide_tiles.dart';
import 'package:pure_live/platform/background_guide.dart';
import 'package:pure_live/platform/system_permissions.dart';

import '../../support.dart';
import 'settings_harness.dart';

/// The native side, as a phone would answer.
final class _FakeGuide extends BackgroundGuideChannel {
  new(this.answer) : super(android: true);

  Map<String, Object?> answer;

  /// What [open] answers: the index of the page that opened (-1 none).
  int Function(List<SystemPage> pages) opens = (pages) => 0;

  final List<List<SystemPage>> opened = [];

  int reads = 0;

  @override
  Future<BackgroundStatus?> status() async {
    reads++;
    return BackgroundStatus.fromMap(answer);
  }

  @override
  Future<int> open(List<SystemPage> pages) async {
    opened.add(pages);
    return opens(pages);
  }
}

final class _FakePermissions extends SystemPermissions {
  new() : super(android: true);

  NotificationPermission notificationState = NotificationPermission.askable;
  bool battery = false;
  bool batteryAfterAsking = false;
  final List<String> calls = [];

  @override
  Future<NotificationPermission> notifications() async => notificationState;

  @override
  Future<bool> requestNotifications() async {
    calls.add('requestNotifications');
    return true;
  }

  @override
  Future<bool> openNotificationSettings() async {
    calls.add('openNotificationSettings');
    return true;
  }

  @override
  Future<bool> batteryUnrestricted() async => battery;

  @override
  Future<bool> requestBatteryUnrestricted() async {
    calls.add('requestBatteryUnrestricted');
    return battery = batteryAfterAsking;
  }
}

Map<String, Object?> _phone({
  String manufacturer = 'Xiaomi',
  Map<String, String> props = const {'ro.mi.os.version.name': 'OS2.0'},
  bool notifications = true,
  bool battery = true,
  String mediaChannel = 'on',
}) => {
  'sdk': 37,
  'manufacturer': manufacturer,
  'brand': manufacturer,
  'model': '25010PN30C',
  'props': props,
  'notifications': notifications,
  'mediaChannel': mediaChannel,
  'batteryUnrestricted': battery,
  'backgroundRestricted': false,
  'dataSaver': 'off',
  'powerSave': false,
};

Finder _step(String id) => find.byKey(ValueKey('background-guide-$id'));

Finder _inRow(String id, Finder matching) => find.descendant(of: settingsRow(id), matching: matching);

void main() {
  setUpAll(loadStrings);

  Future<(SettingsHarness, _FakeGuide, _FakePermissions)> pumpGuide(
    WidgetTester tester,
    Map<String, Object?> phone, {
    bool open = true,
  }) async {
    final guide = _FakeGuide(phone);
    final permissions = _FakePermissions();
    final h = await pumpSettings(
      tester,
      height: 3200,
      arguments: 'video',
      overrides: [
        backgroundGuideChannelProvider.overrideWithValue(guide),
        backgroundGuidePermissionsProvider.overrideWithValue(permissions),
      ],
    );
    if (open) await tapSettings(tester, settingsRow('background_guide'));
    return (h, guide, permissions);
  }

  testWidgets('the video page: the row follows "后台播放", with its icon; "N 项待处理" when something is in the way', (
    tester,
  ) async {
    await pumpGuide(tester, _phone(notifications: false, battery: false), open: false);
    expectInOrder(tester, [settingsRow('background_play'), settingsRow('background_guide'), settingsRow('asmr_sleep')]);
    expect(_inRow('background_guide', find.byIcon(AppIcons.settingsBackgroundGuide)), findsOneWidget);
    expect(_inRow('background_guide', find.text('后台播放设置')), findsOneWidget);
    expect(_inRow('background_guide', find.text('2 项待处理')), findsOneWidget);
  });

  testWidgets('everything readable fine: no count on the row', (tester) async {
    await pumpGuide(tester, _phone(), open: false);
    expect(_inRow('background_guide', find.textContaining('待处理')), findsNothing);
  });

  testWidgets("Xiaomi HyperOS: the phone, Android's checks, then the vendor's with the note; the away switches", (
    tester,
  ) async {
    await pumpGuide(tester, _phone(battery: false));
    expect(find.text('后台播放设置'), findsWidgets);
    expect(find.text('Xiaomi 25010PN30C'), findsOneWidget);
    expect(find.text(withoutOrphan('HyperOS 2.0 · Android 17')), findsOneWidget);
    expectInOrder(tester, [
      for (final id in ['device', 'notifications', 'battery', 'xiaomi_autostart', 'xiaomi_battery', 'lock_recents'])
        _step(id),
    ]);
    expect(find.descendant(of: _step('notifications'), matching: find.text('已设置')), findsOneWidget);
    expect(find.descendant(of: _step('battery'), matching: find.text('去设置')), findsOneWidget);
    expect(find.descendant(of: _step('xiaomi_autostart'), matching: find.text('去看看')), findsOneWidget);
    // Locking in the recent apps opens nothing.
    expect(find.descendant(of: _step('lock_recents'), matching: find.text('去看看')), findsNothing);
    expect(find.textContaining('下面几项是 HyperOS 2.0 自己的设置'), findsOneWidget);
    for (final (id, icon) in [
      ('notifications', AppIcons.backgroundGuideNotifications),
      ('battery', AppIcons.backgroundGuideBattery),
      ('xiaomi_autostart', AppIcons.backgroundGuideAutostart),
      ('xiaomi_battery', AppIcons.backgroundGuidePowerSaving),
      ('lock_recents', AppIcons.backgroundGuideLockRecents),
    ]) {
      expect(
        find.descendant(of: _step(id), matching: find.byIcon(icon)),
        findsOneWidget,
        reason: id,
      );
    }
    expect(find.text('离开应用时'), findsOneWidget);
    expectInOrder(tester, [
      settingsRow('background_audio_only'),
      settingsRow('background_pause_danmaku'),
      settingsRow('pause_on_pip_close'),
    ]);
    expect(_inRow('background_audio_only', find.byIcon(AppIcons.settingsBackgroundAudioOnly)), findsOneWidget);
    expect(_inRow('background_pause_danmaku', find.byIcon(AppIcons.settingsBackgroundDanmaku)), findsOneWidget);
    expect(_inRow('pause_on_pip_close', find.byIcon(AppIcons.settingsPipClosePause)), findsOneWidget);
  });

  testWidgets('the away switches start off (D-040) and are stored', (tester) async {
    final (h, _, _) = await pumpGuide(tester, _phone());
    for (final setting in [Settings.backgroundAudioOnly, Settings.backgroundPauseDanmaku, Settings.pauseOnPipClose]) {
      expect(h.settings.get(setting), isFalse, reason: setting.key);
    }
    await tapSettings(tester, settingsRow('background_audio_only'));
    await tapSettings(tester, settingsRow('background_pause_danmaku'));
    await tapSettings(tester, settingsRow('pause_on_pip_close'));
    expect(h.settings.get(Settings.backgroundAudioOnly), isTrue);
    expect(h.settings.get(Settings.backgroundPauseDanmaku), isTrue);
    expect(h.settings.get(Settings.pauseOnPipClose), isTrue);
  });

  testWidgets('a vendor step opens its page first; where it is missing the app details, said in a toast', (
    tester,
  ) async {
    final (h, guide, _) = await pumpGuide(tester, _phone());
    await tapSettings(tester, _step('xiaomi_autostart'));
    final pages = guide.opened.single;
    expect(pages.first.package, 'com.miui.securitycenter');
    expect(pages.last.isAppDetails, isTrue);
    expect(h.toasts, isEmpty, reason: 'the vendor page opened');

    guide.opens = (pages) => pages.length - 1;
    await tapSettings(tester, _step('xiaomi_battery'));
    expect(h.toasts.single, '已打开应用信息，请在里面找“省电策略”');

    guide.opens = (_) => -1;
    await tapSettings(tester, _step('xiaomi_autostart'));
    expect(h.toasts.last, '没能打开系统设置，请在系统设置 → 应用 → 纯粹直播里手动修改');
  });

  testWidgets('the battery step asks the system first; refused where the vendor removed it, the list opens', (
    tester,
  ) async {
    final (_, guide, permissions) = await pumpGuide(tester, _phone(battery: false));
    await tapSettings(tester, _step('battery'));
    expect(permissions.calls, ['requestBatteryUnrestricted']);
    expect(guide.opened.single.first.action, 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS');

    // Allowed in the system dialog: nothing else opens; read again.
    permissions.batteryAfterAsking = true;
    final reads = guide.reads;
    await tapSettings(tester, _step('battery'));
    expect(guide.opened, hasLength(1));
    expect(guide.reads, greaterThan(reads));
  });

  testWidgets('notifications off: the system dialog while it can ask, else the settings page', (tester) async {
    final (_, _, permissions) = await pumpGuide(tester, _phone(notifications: false));
    expect(find.descendant(of: _step('notifications'), matching: find.text('去设置')), findsOneWidget);
    await tapSettings(tester, _step('notifications'));
    expect(permissions.calls, ['requestNotifications']);
    permissions.notificationState = NotificationPermission.blocked;
    await tapSettings(tester, _step('notifications'));
    expect(permissions.calls.last, 'openNotificationSettings');
  });

  testWidgets('the media category switched off alone is in the way and opens its own page', (tester) async {
    final (_, guide, _) = await pumpGuide(tester, _phone(mediaChannel: 'off'));
    expect(find.textContaining('“媒体播放”这一类通知被关掉了'), findsOneWidget);
    await tapSettings(tester, _step('notifications'));
    expect(guide.opened.single.first.action, 'android.settings.CHANNEL_NOTIFICATION_SETTINGS');
    expect(guide.opened.single.first.extras['android.provider.extra.CHANNEL_ID'], 'com.mystyle.purelive.audio');
  });

  testWidgets("a phone without vendor steps (a Pixel) shows Android's checks only", (tester) async {
    await pumpGuide(tester, _phone(manufacturer: 'Google', props: const {}));
    expect(find.text('Google 25010PN30C'), findsOneWidget);
    expect(find.text(withoutOrphan('Android 17')), findsOneWidget);
    expect(_step('notifications'), findsOneWidget);
    expect(_step('lock_recents'), findsNothing);
    expect(find.textContaining('自己的设置'), findsNothing);
  });

  for (final (maker, props, ids) in [
    ('OPPO', {'ro.build.version.oplusrom': 'V15.0.0'}, ['oppo_autostart', 'oppo_battery', 'lock_recents']),
    ('vivo', {'ro.vivo.os.name': 'OriginOS', 'ro.vivo.os.version': '5.0'}, ['vivo_power', 'vivo_autostart']),
    ('HUAWEI', {'hw_sc.build.platform.version': '4.2.0'}, ['huawei_launch', 'lock_recents']),
    ('HONOR', {'ro.build.version.magic': 'MagicOS_8.0'}, ['honor_launch', 'lock_recents']),
    ('samsung', {'ro.build.version.oneui': '60100'}, ['samsung_battery', 'samsung_sleeping']),
  ]) {
    testWidgets('$maker: its own steps', (tester) async {
      await pumpGuide(tester, _phone(manufacturer: maker, props: props));
      for (final id in ids) {
        expect(_step(id), findsOneWidget, reason: id);
      }
      expect(_step('xiaomi_autostart'), findsNothing);
    });
  }

  group('the hint after background play turns on', () {
    testWidgets('on a vendor build: once, "去设置" opens the page', (tester) async {
      final (h, _, _) = await pumpGuide(tester, _phone(), open: false);
      await tapSettings(tester, settingsRow('background_play'));
      expect(h.settings.get(Settings.enableBackgroundPlay), isTrue);
      expect(find.text('还要在系统里设置一下'), findsOneWidget);
      expect(find.textContaining('HyperOS 2.0 会清理后台的应用'), findsOneWidget);
      await tapSettings(tester, find.byKey(const ValueKey('permission-confirm')));
      expect(_step('xiaomi_autostart'), findsOneWidget);

      // Off and on again: not asked twice.
      await tester.pageBack();
      await settleSettings(tester);
      await tapSettings(tester, settingsRow('background_play'));
      await tapSettings(tester, settingsRow('background_play'));
      expect(find.text('还要在系统里设置一下'), findsNothing);
    });

    testWidgets('on a phone without vendor steps: no hint', (tester) async {
      await pumpGuide(tester, _phone(manufacturer: 'Google', props: const {}), open: false);
      await tapSettings(tester, settingsRow('background_play'));
      expect(find.text('还要在系统里设置一下'), findsNothing);
    });
  });

  testWidgets("search finds the page by the vendor's name", (tester) async {
    await pumpSettings(tester);
    await searchSettingsFor(tester, 'HyperOS');
    expect(find.text('后台播放设置'), findsWidgets);
  });
}
