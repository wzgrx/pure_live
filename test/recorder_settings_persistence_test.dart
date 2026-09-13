import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/recorder/consts/recorder_config.dart';
import 'package:pure_live/recorder/consts/recorder_keys.dart';
import 'package:pure_live/recorder/pages/record_settings/record_settings_controller.dart';
import 'package:pure_live/recorder/services/cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDirectory;

  setUp(() async {
    Get.testMode = true;
    hiveDirectory = await Directory.systemTemp.createTemp('pure_live_recorder_settings_');
    Hive.init(hiveDirectory.path);
    await HivePrefUtil.init();
  });

  tearDown(() async {
    Get.reset();
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  CacheService installCacheService() => Get.put(
    CacheService(defaultDirectoryResolver: () async => Directory(p.join(hiveDirectory.path, 'default-records'))),
  );

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

  test('directory selection commits only after the candidate is writable', () async {
    installCacheService();
    final previous = Directory(p.join(hiveDirectory.path, 'previous'));
    await RecorderConfig.setRecordSavePath(previous.path);
    final blocked = await File(p.join(hiveDirectory.path, 'blocked-parent')).writeAsString('fixture');
    final controller = RecordSettingsController(directoryPicker: () async => blocked.path);
    await controller.refreshStorageInfo();
    final previousManagedPath = controller.managedRecordPath.value;

    await controller.pickRecordDir();

    expect(controller.recordSavePath.value, previous.path);
    expect(RecorderConfig.recordSavePath, previous.path);
    expect(controller.managedRecordPath.value, previousManagedPath);
    expect(controller.selectingRecordDirectory.value, isFalse);
  });

  test('directory selection publishes the verified managed child and coalesces repeated taps', () async {
    installCacheService();
    final selected = Directory(p.join(hiveDirectory.path, 'selected'));
    final picker = Completer<String?>();
    var pickerCalls = 0;
    final controller = RecordSettingsController(
      directoryPicker: () {
        pickerCalls++;
        return picker.future;
      },
    );

    final first = controller.pickRecordDir();
    final second = controller.pickRecordDir();
    expect(controller.selectingRecordDirectory.value, isTrue);
    expect(pickerCalls, 1);
    picker.complete(selected.path);
    await Future.wait([first, second]);

    expect(controller.selectingRecordDirectory.value, isFalse);
    expect(controller.recordSavePath.value, selected.path);
    expect(RecorderConfig.recordSavePath, selected.path);
    expect(p.equals(controller.managedRecordPath.value, p.join(selected.path, CacheService.managedFolderName)), isTrue);
  });

  test('a user directory chosen during startup wins after default initialization settles', () async {
    final defaultGate = Completer<Directory>();
    Get.put(CacheService(defaultDirectoryResolver: () => defaultGate.future));
    final selected = Directory(p.join(hiveDirectory.path, 'selected-during-startup'));
    final controller = Get.put(RecordSettingsController(directoryPicker: () async => selected.path));

    final choosing = controller.pickRecordDir();
    expect(controller.selectingRecordDirectory.value, isTrue);
    defaultGate.complete(Directory(p.join(hiveDirectory.path, 'startup-default')));
    await choosing;

    expect(controller.recordSavePath.value, selected.path);
    expect(RecorderConfig.recordSavePath, selected.path);
    expect(p.equals(controller.managedRecordPath.value, p.join(selected.path, CacheService.managedFolderName)), isTrue);
  });
}
