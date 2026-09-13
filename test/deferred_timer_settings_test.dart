import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/exit_settings_controller.dart';
import 'package:pure_live/common/services/settings/iptv_settings_controller.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pure-live-deferred-timers-');
    Hive.init(directory.path);
    await HivePrefUtil.init();
  });

  setUp(() async {
    Get.testMode = true;
    await HivePrefUtil.clear();
  });

  tearDown(() async {
    Get.reset();
    await HivePrefUtil.flush();
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('app exit timer keeps every input inside its supported year-long range', () {
    expect(ExitSettingsController.normalizeAutoShutdownMinutes(-20), ExitSettingsController.minAutoShutdownMinutes);
    expect(ExitSettingsController.normalizeAutoShutdownMinutes(7), 7);
    expect(
      ExitSettingsController.normalizeAutoShutdownMinutes(999999999),
      ExitSettingsController.maxAutoShutdownMinutes,
    );

    expect(
      ExitSettingsController.parseConfig({'autoShutDownTime': 0})['autoShutDownTime'],
      ExitSettingsController.minAutoShutdownMinutes,
    );
    expect(
      ExitSettingsController.extractConfig({
        'exit': {'autoShutDownTime': 999999999},
      })['autoShutDownTime'],
      ExitSettingsController.maxAutoShutdownMinutes,
    );
    expect(() => ExitSettingsController.parseConfig({'autoShutDownTime': 'bad'}), throwsA(isA<TypeError>()));
  });

  test('IPTV automatic sync interval is bounded at every import boundary', () {
    expect(IptvSettingsController.normalizeAutoSyncHours(-1), IptvSettingsController.minAutoSyncHours);
    expect(IptvSettingsController.normalizeAutoSyncHours(24), 24);
    expect(IptvSettingsController.normalizeAutoSyncHours(999999999), IptvSettingsController.maxAutoSyncHours);

    expect(
      IptvSettingsController.parseConfig({'autoSyncHoursInterval': 0})['autoSyncHoursInterval'],
      IptvSettingsController.minAutoSyncHours,
    );
    expect(
      IptvSettingsController.extractConfig({
        'iptv': {'autoSyncHoursInterval': 999999999},
      })['autoSyncHoursInterval'],
      IptvSettingsController.maxAutoSyncHours,
    );
    expect(() => IptvSettingsController.parseConfig({'autoSyncHoursInterval': 'bad'}), throwsA(isA<TypeError>()));
  });

  test('persisted timer values are repaired before either scheduler observes them', () async {
    await HivePrefUtil.setInt('autoShutDownTime', -5);
    await HivePrefUtil.setInt(IptvSettingsController.autoSyncHoursIntervalKey, 5000);

    final exit = Get.put(ExitSettingsController());
    final iptv = Get.put(IptvSettingsController());

    expect(exit.autoShutDownTime.value, ExitSettingsController.minAutoShutdownMinutes);
    expect(iptv.autoSyncHoursInterval.value, IptvSettingsController.maxAutoSyncHours);
    await Future<void>.delayed(Duration.zero);
    await HivePrefUtil.flush();
    expect(HivePrefUtil.getInt('autoShutDownTime'), ExitSettingsController.minAutoShutdownMinutes);
    expect(
      HivePrefUtil.getInt(IptvSettingsController.autoSyncHoursIntervalKey),
      IptvSettingsController.maxAutoSyncHours,
    );
  });

  test('runtime exit timer edits share the same normalization contract', () {
    final exit = Get.put(ExitSettingsController());
    exit.updateShutDownTime(0);
    expect(exit.autoShutDownTime.value, ExitSettingsController.minAutoShutdownMinutes);

    exit.changeShutDownConfig(999999999, false);
    expect(exit.autoShutDownTime.value, ExitSettingsController.maxAutoShutdownMinutes);
    expect(exit.toJson()['autoShutDownTime'], ExitSettingsController.maxAutoShutdownMinutes);
  });

  test('one exit timer action is not restarted again by its persistence observer', () async {
    final exit = Get.put(ExitSettingsController());

    exit.updateShutDownTime(1);
    exit.enableAutoShutdown();
    expect(exit.timerRestartCount, 1);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(exit.timerRestartCount, 1);

    exit.updateShutDownTime(1);
    expect(exit.timerRestartCount, 2, reason: 'saving the same duration is an explicit restart');
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(exit.timerRestartCount, 2);
  });
}
