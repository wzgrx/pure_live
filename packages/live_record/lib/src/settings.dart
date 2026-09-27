import 'package:meta/meta.dart';

/// The five quality preferences of `record.defaultQuality` (spec §20), best first.
enum RecordQuality {
  /// 原画.
  original('原画'),

  /// 蓝光8M.
  bluRay8M('蓝光8M'),

  /// 蓝光4M.
  bluRay4M('蓝光4M'),

  /// 超清.
  superHd('超清'),

  /// 流畅.
  smooth('流畅');

  new(this.label);

  /// Label as the platforms and 3.x spell it.
  final String label;
}

/// Recording settings (spec §20). The app maps its `record.*` settings onto
/// this; [clamped] applies the documented ranges.
@immutable
final class RecordSettings {
  /// Creates settings with the spec defaults.
  const new({
    this.defaultQuality = RecordQuality.original,
    this.maxConcurrent = 3,
    this.autoReconnect = true,
    this.maxRetries = 5,
    this.retryDelay = const Duration(seconds: 30),
    this.polling = false,
    this.liveCheckInterval = const Duration(seconds: 30),
    this.backoff = false,
    this.maxCheckInterval = const Duration(seconds: 300),
    this.resumeOnLaunch = false,
    this.readTimeout = const Duration(seconds: 15),
    this.danmaku = false,
    this.splitMinutes = 0,
    this.splitMegabytes = 0,
    this.remuxToMp4 = true,
    this.keepSourceAfterRemux = false,
  });

  /// `record.defaultQuality`.
  final RecordQuality defaultQuality;

  /// `record.maxConcurrent` (1–10): sessions resolving, recording or reconnecting at once.
  final int maxConcurrent;

  /// `record.autoReconnect`: copied into a task when the user starts it.
  final bool autoReconnect;

  /// `record.maxRetries` (1–20): regular retries before the session gives up.
  final int maxRetries;

  /// `record.retryDelay` (5–120 s): regular retry delay.
  final Duration retryDelay;

  /// `record.polling`: check waiting rooms until they go live.
  final bool polling;

  /// `record.liveCheckInterval` (10–300 s).
  final Duration liveCheckInterval;

  /// `record.backoff`: double regular delays up to [maxCheckInterval].
  final bool backoff;

  /// `record.maxCheckInterval` (300–3600 s).
  final Duration maxCheckInterval;

  /// `record.resumeOnLaunch`: resume tasks that were active when the app last ran.
  final bool resumeOnLaunch;

  /// `record.readTimeout` (15 / 30 / 60 s): upstream read idle timeout.
  final Duration readTimeout;

  /// `record.danmaku`: write chat XML next to each segment.
  final bool danmaku;

  /// `record.splitMinutes` (0 = off, else ≥ 1).
  final int splitMinutes;

  /// `record.splitMegabytes` (0 = off, else ≥ 64).
  final int splitMegabytes;

  /// `record.remuxToMp4`.
  final bool remuxToMp4;

  /// `record.keepSourceAfterRemux`.
  final bool keepSourceAfterRemux;

  /// Split duration, or null when off.
  Duration? get splitDuration => splitMinutes <= 0 ? null : Duration(minutes: splitMinutes);

  /// Split size in bytes, or null when off.
  int? get splitBytes => splitMegabytes <= 0 ? null : splitMegabytes * 1024 * 1024;

  /// A copy with every value inside its documented range (spec §20).
  RecordSettings clamped() {
    Duration clampDuration(Duration value, int min, int max) => Duration(seconds: value.inSeconds.clamp(min, max));
    final timeout = readTimeout.inSeconds <= 15
        ? 15
        : readTimeout.inSeconds <= 30
        ? 30
        : 60;
    return RecordSettings(
      defaultQuality: defaultQuality,
      maxConcurrent: maxConcurrent.clamp(1, 10),
      autoReconnect: autoReconnect,
      maxRetries: maxRetries.clamp(1, 20),
      retryDelay: clampDuration(retryDelay, 5, 120),
      polling: polling,
      liveCheckInterval: clampDuration(liveCheckInterval, 10, 300),
      backoff: backoff,
      maxCheckInterval: clampDuration(maxCheckInterval, 300, 3600),
      resumeOnLaunch: resumeOnLaunch,
      readTimeout: Duration(seconds: timeout),
      danmaku: danmaku,
      splitMinutes: splitMinutes <= 0 ? 0 : splitMinutes,
      splitMegabytes: splitMegabytes <= 0 ? 0 : (splitMegabytes < 64 ? 64 : splitMegabytes),
      remuxToMp4: remuxToMp4,
      keepSourceAfterRemux: keepSourceAfterRemux,
    );
  }

  /// A copy with the given values replaced.
  RecordSettings copyWith({
    RecordQuality? defaultQuality,
    int? maxConcurrent,
    bool? autoReconnect,
    int? maxRetries,
    Duration? retryDelay,
    bool? polling,
    Duration? liveCheckInterval,
    bool? backoff,
    Duration? maxCheckInterval,
    bool? resumeOnLaunch,
    Duration? readTimeout,
    bool? danmaku,
    int? splitMinutes,
    int? splitMegabytes,
    bool? remuxToMp4,
    bool? keepSourceAfterRemux,
  }) => RecordSettings(
    defaultQuality: defaultQuality ?? this.defaultQuality,
    maxConcurrent: maxConcurrent ?? this.maxConcurrent,
    autoReconnect: autoReconnect ?? this.autoReconnect,
    maxRetries: maxRetries ?? this.maxRetries,
    retryDelay: retryDelay ?? this.retryDelay,
    polling: polling ?? this.polling,
    liveCheckInterval: liveCheckInterval ?? this.liveCheckInterval,
    backoff: backoff ?? this.backoff,
    maxCheckInterval: maxCheckInterval ?? this.maxCheckInterval,
    resumeOnLaunch: resumeOnLaunch ?? this.resumeOnLaunch,
    readTimeout: readTimeout ?? this.readTimeout,
    danmaku: danmaku ?? this.danmaku,
    splitMinutes: splitMinutes ?? this.splitMinutes,
    splitMegabytes: splitMegabytes ?? this.splitMegabytes,
    remuxToMp4: remuxToMp4 ?? this.remuxToMp4,
    keepSourceAfterRemux: keepSourceAfterRemux ?? this.keepSourceAfterRemux,
  );
}
