import 'dart:io';
import 'dart:async';

import 'package:pure_live/common/index.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pure_live/plugins/file_utils.dart';
import 'package:pure_live/recorder/consts/recorder_keys.dart';
import 'package:pure_live/common/global/app_path_manager.dart';
import 'package:pure_live/recorder/consts/recorder_config.dart';
import 'package:pure_live/recorder/services/cache_service.dart';

class RecordSettingsController extends GetxController {
  /// =====================================
  /// 基础配置
  /// =====================================
  final defaultQuality = RecorderConfig.defaultQuality.obs;
  final recordSavePath = RecorderConfig.recordSavePath.obs;
  final maxCacheMB = RecorderConfig.maxCacheMB.obs;
  final cacheSizeMB = 0.0.obs;
  final managedRecordPath = ''.obs;

  /// =====================================
  /// 录制性能与画质
  /// =====================================
  final segmentTime = RecorderConfig.segmentTime.obs;
  final maxTaskCount = RecorderConfig.maxTaskCount.obs;
  final preferBestStream = hiveBool(RecorderKeys.preferBestStream, RecorderConfig.defaultPreferBestStream);
  final rwTimeout = RecorderConfig.rwTimeout.obs;
  final threadQueueSize = RecorderConfig.threadQueueSize.obs;

  /// =====================================
  /// 自动重连逻辑
  /// =====================================
  final autoReconnect = hiveBool(RecorderKeys.autoReconnect, RecorderConfig.defaultAutoReconnect);
  final maxRetryCount = RecorderConfig.maxRetryCount.obs;
  final retryDelay = RecorderConfig.retryDelay.obs;

  /// =====================================
  /// 挂机检测轮询
  /// =====================================
  final enablePolling = hiveBool(RecorderKeys.enablePolling, RecorderConfig.defaultEnablePolling);
  final liveCheckInterval = RecorderConfig.liveCheckInterval.obs;
  final enableBackoff = hiveBool(RecorderKeys.enableBackoff, RecorderConfig.defaultEnableBackoff);
  final maxCheckInterval = RecorderConfig.maxCheckInterval.obs;

  final autoStartOnBoot = hiveBool(RecorderKeys.autoStartOnBoot, RecorderConfig.defaultAutoStartOnBoot);
  final usePinyinForFolder = hiveBool(RecorderKeys.folderNamingStrategy, RecorderConfig.defaultUsePinyinForFolder);

  /// 缓存限制开关
  final enableCacheLimit = hiveBool(RecorderKeys.enableCacheLimit, RecorderConfig.defaultEnableCacheLimit);

  @override
  void onInit() {
    super.onInit();
    unawaited(RecorderConfig.normalizeStoredValues());
    unawaited(_initializeStorage());
  }

  Future<void> _initializeStorage() async {
    await initRecordPath();
    await refreshStorageInfo();
  }

  /// =====================================
  /// 刷新缓存大小
  /// =====================================
  Future<void> refreshCacheSize() async {
    cacheSizeMB.value = await CacheService.to.getCacheSize();
  }

  Future<void> refreshStorageInfo() async {
    managedRecordPath.value = await CacheService.to.getDisplayPath();
    await refreshCacheSize();
  }

  /// =====================================
  /// 更新缓存限制开关
  /// =====================================
  ///
  /// enableCacheLimit 使用 hiveBool() 后，
  /// 修改 value 会自动保存到 Hive。
  ///
  /// 保留这个方法是为了兼容现有 UI 调用。
  Future<void> updateEnableCacheLimit(bool v) async {
    enableCacheLimit.value = v;
  }

  /// =====================================
  /// 清除缓存
  /// =====================================
  Future<void> clearCache() async {
    await CacheService.to.clearAll();
    await refreshStorageInfo();
  }

  /// =====================================
  /// 更新切片时长
  /// =====================================
  Future<void> updateSegmentTime(int v) async {
    final normalized = RecorderConfig.normalizeSegmentTime(v);
    segmentTime.value = normalized;
    await RecorderConfig.setSegmentTime(normalized);
  }

  /// =====================================
  /// 更新最大任务数
  /// =====================================
  Future<void> updateMaxTask(int v) async {
    final normalized = RecorderConfig.normalizeMaxTaskCount(v);
    maxTaskCount.value = normalized;
    await RecorderConfig.setMaxTaskCount(normalized);
  }

  /// =====================================
  /// 更新自动重连
  /// =====================================
  ///
  /// autoReconnect 使用 hiveBool() 后，
  /// 修改 value 会自动保存到 Hive。
  ///
  /// 保留这个方法是为了兼容现有 UI 调用。
  Future<void> updateAutoReconnect(bool v) async {
    autoReconnect.value = v;
  }

  /// =====================================
  /// 更新最大重试次数
  /// =====================================
  Future<void> updateMaxRetryCount(int v) async {
    final normalized = RecorderConfig.normalizeMaxRetryCount(v);
    maxRetryCount.value = normalized;
    await RecorderConfig.setMaxRetryCount(normalized);
  }

  /// =====================================
  /// 更新重试等待时间
  /// =====================================
  Future<void> updateRetryDelay(int v) async {
    final normalized = RecorderConfig.normalizeRetryDelay(v);
    retryDelay.value = normalized;
    await RecorderConfig.setRetryDelay(normalized);
  }

  /// =====================================
  /// 更新开播检测间隔
  /// =====================================
  Future<void> updateLiveCheckInterval(int v) async {
    final normalized = RecorderConfig.normalizeLiveCheckInterval(v);
    liveCheckInterval.value = normalized;
    await RecorderConfig.setLiveCheckInterval(normalized);
  }

  /// =====================================
  /// 更新最大检测间隔
  /// =====================================
  Future<void> updateMaxCheckInterval(int v) async {
    final normalized = RecorderConfig.normalizeMaxCheckInterval(v);
    maxCheckInterval.value = normalized;
    await RecorderConfig.setMaxCheckInterval(normalized);
  }

  /// =====================================
  /// 更新挂机检测
  /// =====================================
  ///
  /// enablePolling 使用 hiveBool() 后，
  /// 修改 value 会自动保存到 Hive。
  ///
  /// 保留这个方法是为了兼容现有 UI 调用。
  Future<void> updateEnablePolling(bool v) async {
    enablePolling.value = v;
  }

  /// =====================================
  /// 更新指数退避
  /// =====================================
  ///
  /// enableBackoff 使用 hiveBool() 后，
  /// 修改 value 会自动保存到 Hive。
  ///
  /// 保留这个方法是为了兼容现有 UI 调用。
  Future<void> updateEnableBackoff(bool v) async {
    enableBackoff.value = v;
  }

  /// =====================================
  /// 选择录制目录
  /// =====================================
  Future<void> pickRecordDir() async {
    final result = await FilePicker.getDirectoryPath();

    if (result != null && result.isNotEmpty) {
      recordSavePath.value = result;
      await RecorderConfig.setRecordSavePath(result);
      await refreshStorageInfo();
    }
  }

  Future<void> openRecordDir() async {
    final path = managedRecordPath.value.isNotEmpty ? managedRecordPath.value : await CacheService.to.getDisplayPath();

    if (path.isEmpty) {
      return;
    }

    await FileUtils.openFileOrUrl(path);
  }

  Future<void> updateDefaultQuality(String v) async {
    final normalized = RecorderConfig.normalizeDefaultQuality(v);
    defaultQuality.value = normalized;
    await RecorderConfig.setDefaultQuality(normalized);
  }

  Future<void> updateMaxCache(int v) async {
    final normalized = RecorderConfig.normalizeMaxCacheMB(v);
    maxCacheMB.value = normalized;
    await RecorderConfig.setMaxCacheMB(normalized);
  }

  /// =====================================
  /// 更新优先最高画质
  /// =====================================
  ///
  /// preferBestStream 使用 hiveBool() 后，
  /// 修改 value 会自动保存到 Hive。
  ///
  /// 保留这个方法是为了兼容现有 UI 调用。
  Future<void> updatePreferBestStream(bool v) async {
    preferBestStream.value = v;
  }

  /// =====================================
  /// 更新读写超时
  /// =====================================
  Future<void> updateRwTimeout(int v) async {
    final normalized = RecorderConfig.normalizeRwTimeout(v);
    rwTimeout.value = normalized;
    await RecorderConfig.setRwTimeout(normalized);
  }

  /// =====================================
  /// 更新缓冲队列大小
  /// =====================================
  Future<void> updateThreadQueueSize(int v) async {
    final normalized = RecorderConfig.normalizeThreadQueueSize(v);
    threadQueueSize.value = normalized;
    await RecorderConfig.setThreadQueueSize(normalized);
  }

  /// =====================================
  /// 更新后台自动启动
  /// =====================================

  Future<void> updateAutoStartOnBoot(bool v) async {
    autoStartOnBoot.value = v;
  }

  /// =====================================
  /// 更新文件夹命名策略
  /// =====================================

  Future<void> updateUsePinyinForFolder(bool v) async {
    usePinyinForFolder.value = v;
  }

  Future<void> initRecordPath() async {
    if (recordSavePath.value.isEmpty) {
      final Directory recordDir = await AppPathManager().getDir(AppPathManager.dirRecords);

      recordSavePath.value = recordDir.path;

      await RecorderConfig.setRecordSavePath(recordDir.path);
    }
  }
}
