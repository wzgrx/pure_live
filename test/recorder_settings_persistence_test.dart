import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/recorder/consts/recorder_config.dart';
import 'package:pure_live/recorder/consts/recorder_keys.dart';
import 'package:pure_live/recorder/pages/record_settings/record_settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDirectory;

  setUp(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pure_live_recorder_settings_');
    Hive.init(hiveDirectory.path);
    await HivePrefUtil.init();
  });

  tearDown(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  test('recorder switches persist when their reactive values change', () async {
    final controller = RecordSettingsController();

    controller.autoReconnect.value = false;
    controller.enablePolling.value = true;
    controller.enableCacheLimit.value = true;
    controller.preferBestStream.value = false;
    controller.autoStartOnBoot.value = true;

    await Future<void>.delayed(Duration.zero);
    await HivePrefUtil.flush();

    expect(RecorderConfig.autoReconnect, isFalse);
    expect(RecorderConfig.enablePolling, isTrue);
    expect(RecorderConfig.enableCacheLimit, isTrue);
    expect(RecorderConfig.preferBestStream, isFalse);
    expect(RecorderConfig.autoStartOnBoot, isTrue);
    controller.enablePolling.value = false;
    await HivePrefUtil.flush();
    final reopened = RecordSettingsController();
    expect(reopened.enablePolling.value, isFalse);
    expect(reopened.autoStartOnBoot.value, isTrue);
  });

  test('cache-limit getter observes changes made after first read', () async {
    expect(RecorderConfig.enableCacheLimit, RecorderConfig.defaultEnableCacheLimit);

    await RecorderConfig.setEnableCacheLimit(true);

    expect(RecorderConfig.enableCacheLimit, isTrue);
  });

  test('persisted recorder numbers are normalized to every UI and runtime boundary', () async {
    await HivePrefUtil.setInt(RecorderKeys.segmentTime, 0);
    await HivePrefUtil.setInt(RecorderKeys.maxTaskCount, 99);
    await HivePrefUtil.setInt(RecorderKeys.maxCacheMB, 0);
    await HivePrefUtil.setInt(RecorderKeys.maxRetryCount, 0);
    await HivePrefUtil.setInt(RecorderKeys.retryDelay, 999);
    await HivePrefUtil.setInt(RecorderKeys.liveCheckInterval, 0);
    await HivePrefUtil.setInt(RecorderKeys.maxCheckInterval, 99999);
    await HivePrefUtil.setInt(RecorderKeys.rwTimeout, 99);
    await HivePrefUtil.setInt(RecorderKeys.threadQueueSize, 99);
    await HivePrefUtil.setString(RecorderKeys.defaultQuality, 'invalid-quality');

    final controller = RecordSettingsController();

    expect(controller.segmentTime.value, 60);
    expect(controller.maxTaskCount.value, 10);
    expect(controller.maxCacheMB.value, 1);
    expect(controller.maxRetryCount.value, 1);
    expect(controller.retryDelay.value, 120);
    expect(controller.liveCheckInterval.value, 10);
    expect(controller.maxCheckInterval.value, 3600);
    expect(controller.rwTimeout.value, 15);
    expect(controller.threadQueueSize.value, 2048);
    expect(controller.defaultQuality.value, '原画');

    await RecorderConfig.normalizeStoredValues();
    await HivePrefUtil.flush();
    expect(HivePrefUtil.getInt(RecorderKeys.segmentTime), 60);
    expect(HivePrefUtil.getInt(RecorderKeys.maxTaskCount), 10);
    expect(HivePrefUtil.getInt(RecorderKeys.maxCacheMB), 1);
    expect(HivePrefUtil.getInt(RecorderKeys.maxRetryCount), 1);
    expect(HivePrefUtil.getInt(RecorderKeys.retryDelay), 120);
    expect(HivePrefUtil.getInt(RecorderKeys.liveCheckInterval), 10);
    expect(HivePrefUtil.getInt(RecorderKeys.maxCheckInterval), 3600);
    expect(HivePrefUtil.getInt(RecorderKeys.rwTimeout), 15);
    expect(HivePrefUtil.getInt(RecorderKeys.threadQueueSize), 2048);
    expect(HivePrefUtil.getString(RecorderKeys.defaultQuality), '原画');
  });

  test('controller updates publish normalized values before persistence completes', () async {
    final controller = RecordSettingsController();

    final writes = <Future<void>>[
      controller.updateSegmentTime(1),
      controller.updateMaxTask(99),
      controller.updateMaxCache(0),
      controller.updateMaxRetryCount(99),
      controller.updateRetryDelay(0),
      controller.updateLiveCheckInterval(999),
      controller.updateMaxCheckInterval(0),
      controller.updateRwTimeout(99),
      controller.updateThreadQueueSize(99),
      controller.updateDefaultQuality('invalid-quality'),
    ];

    expect(controller.segmentTime.value, 60);
    expect(controller.maxTaskCount.value, 10);
    expect(controller.maxCacheMB.value, 1);
    expect(controller.maxRetryCount.value, 20);
    expect(controller.retryDelay.value, 5);
    expect(controller.liveCheckInterval.value, 300);
    expect(controller.maxCheckInterval.value, 300);
    expect(controller.rwTimeout.value, 15);
    expect(controller.threadQueueSize.value, 2048);
    expect(controller.defaultQuality.value, '原画');

    await Future.wait(writes);
    await HivePrefUtil.flush();
    expect(RecorderConfig.segmentTime, 60);
    expect(RecorderConfig.maxTaskCount, 10);
    expect(RecorderConfig.maxCacheMB, 1);
    expect(RecorderConfig.maxRetryCount, 20);
    expect(RecorderConfig.retryDelay, 5);
    expect(RecorderConfig.liveCheckInterval, 300);
    expect(RecorderConfig.maxCheckInterval, 300);
    expect(RecorderConfig.rwTimeout, 15);
    expect(RecorderConfig.threadQueueSize, 2048);
    expect(RecorderConfig.defaultQuality, '原画');
  });
}
