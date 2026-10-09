import 'package:meta/meta.dart';

/// The five quality preferences of the recording settings, best first (3.x
/// `PlayerConsts.resolutions`).
const recordQualityPreferences = ['原画', '蓝光8M', '蓝光4M', '超清', '流畅'];

/// Recording settings with 3.x's defaults and bounds (3.x `RecorderConfig`
/// and `RecordSettingsController`). Values out of range are normalized on
/// construction, like 3.x's `normalizeStoredValues`. Storage is M9's; the
/// recorder reads the current value through a getter on every decision.
@immutable
final class RecordSettings {
  /// Creates settings; out-of-range values are clamped or replaced.
  new({
    int segmentTime = 300,
    int maxTaskCount = 3,
    this.autoReconnect = true,
    int maxCacheMB = 1024,
    this.enableCacheLimit = false,
    this.savePath = '',
    String defaultQuality = '原画',
    int maxRetryCount = 5,
    int retryDelay = 30,
    this.enablePolling = false,
    int liveCheckInterval = 30,
    this.enableBackoff = false,
    int maxCheckInterval = 300,
    this.autoStartOnBoot = false,
    this.preferBestStream = true,
    int rwTimeout = 15,
    int threadQueueSize = 2048,
    this.usePinyinForFolder = false,
    this.recordDanmaku = false,
    this.recordDanmakuGifts = false,
    this.preferH264 = true,
  }) : segmentTime = segmentTime.clamp(60, 3600),
       maxTaskCount = maxTaskCount.clamp(1, 10),
       maxCacheMB = maxCacheMB < 1 ? 1 : maxCacheMB,
       defaultQuality = recordQualityPreferences.contains(defaultQuality)
           ? defaultQuality
           : recordQualityPreferences.first,
       maxRetryCount = maxRetryCount.clamp(1, 20),
       retryDelay = retryDelay.clamp(5, 120),
       liveCheckInterval = liveCheckInterval.clamp(10, 300),
       maxCheckInterval = maxCheckInterval.clamp(300, 3600),
       rwTimeout = supportedRwTimeouts.contains(rwTimeout) ? rwTimeout : 15,
       threadQueueSize = supportedThreadQueueSizes.contains(threadQueueSize) ? threadQueueSize : 2048;

  /// Choices of [rwTimeout].
  static const supportedRwTimeouts = [15, 30, 60];

  /// Choices of [threadQueueSize].
  static const supportedThreadQueueSizes = [512, 1024, 2048, 4096, 8192];

  /// Segment length, seconds (60–3600).
  final int segmentTime;

  /// Concurrent recordings (1–10).
  final int maxTaskCount;

  /// Retry after an interrupted attempt.
  final bool autoReconnect;

  /// Cache limit, MiB.
  final int maxCacheMB;

  /// Delete the oldest recordings above [maxCacheMB].
  final bool enableCacheLimit;

  /// Parent directory chosen by the user ('' for the default).
  final String savePath;

  /// One of [recordQualityPreferences].
  final String defaultQuality;

  /// Retries before falling back to waiting for the room (1–20).
  final int maxRetryCount;

  /// Retry delay, seconds (5–120).
  final int retryDelay;

  /// Poll rooms that are waiting to go live.
  final bool enablePolling;

  /// Live check interval, seconds (10–300).
  final int liveCheckInterval;

  /// Double the delays after each failure.
  final bool enableBackoff;

  /// Upper bound of backed-off delays, seconds (300–3600).
  final int maxCheckInterval;

  /// Resume waiting and interrupted tasks when the app starts.
  final bool autoStartOnBoot;

  /// Record only the first video and audio stream (`-map 0:v:0?`).
  final bool preferBestStream;

  /// FFmpeg read/write timeout, seconds.
  final int rwTimeout;

  /// FFmpeg input thread queue size.
  final int threadQueueSize;

  /// Name the platform and streamer folders in pinyin.
  final bool usePinyinForFolder;

  /// Save the chat beside each attempt (left to the app, see the M8 record).
  final bool recordDanmaku;

  /// The saved chat also has the room's gifts and super chats ("录制弹幕时包含
  /// 礼物", live_store `Settings.recordDanmakuGifts`, off by default; H01.8):
  /// the app's chat connector delivers them, `RecordChatWriter` writes
  /// them.
  final bool recordDanmakuGifts;

  /// The player's "优先 H.264" (live_store `Settings.preferH264`, on by
  /// default): a task that does not name its quality is not started on an
  /// HEVC quality while the room offers another (H01.7).
  final bool preferH264;
}
