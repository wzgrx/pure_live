import 'package:live_core/live_core.dart';
import 'package:live_record/src/diagnostics.dart';
import 'package:meta/meta.dart';

/// Where a record task is (3.x's `RecordStatus`; the order of the values is
/// the stored index of 3.x JSON and must not change).
enum RecordStatus {
  /// Waiting for a free recording slot.
  queued,

  /// Resolving the room, quality and line, or opening FFmpeg.
  preparing,

  /// Writing media.
  running,

  /// Waiting to retry after an interrupted attempt.
  reconnecting,

  /// Joining the recorded segments into MP4.
  processing,

  /// Finished normally.
  completed,

  /// Failed and not retrying.
  failed,

  /// Waiting for the room to go live.
  waitingLive,

  /// Stopped by the user.
  stopped;

  /// Display rank of the recording centre's "all" tab (3.x `order`):
  /// actionable states first.
  int get order => switch (this) {
    running => 0,
    reconnecting => 1,
    processing => 2,
    preparing => 3,
    queued => 4,
    waitingLive => 5,
    failed => 6,
    completed => 7,
    stopped => 8,
  };

  /// Whether the task holds a recording slot or files.
  bool get isActive => switch (this) {
    running || reconnecting || processing || preparing => true,
    _ => false,
  };

  /// Whether the task ended.
  bool get isFinished => switch (this) {
    completed || failed || stopped => true,
    _ => false,
  };
}

/// One finished capture attempt whose MPEG-TS segments still have to be
/// joined into MP4 (3.x's `PendingRecordingAttempt`). A signed CDN can end a
/// connection while the room stays live; the recorder reconnects first and
/// joins the attempts only when the user-visible session ends.
@immutable
final class PendingRecordingAttempt {
  /// Creates the attempt.
  const new({required this.directoryPath, required this.filePrefix, this.inputIntegrityError = false});

  /// Directory of the segments.
  final String directoryPath;

  /// Attempt prefix of the segment names.
  final String filePrefix;

  /// FFmpeg reported damaged packets while capturing; joining refuses it
  /// so the source survives (capture evidence, kept across restarts).
  final bool inputIntegrityError;

  /// JSON of 3.x.
  Map<String, Object?> toJson() => {
    'directoryPath': directoryPath,
    'filePrefix': filePrefix,
    'inputIntegrityError': inputIntegrityError,
  };

  /// Reads 3.x JSON; null without a directory or prefix.
  static PendingRecordingAttempt? fromJson(Map<String, Object?> json) {
    final directoryPath = json['directoryPath']?.toString().trim() ?? '';
    final filePrefix = json['filePrefix']?.toString().trim() ?? '';
    if (directoryPath.isEmpty || filePrefix.isEmpty) return null;
    return PendingRecordingAttempt(
      directoryPath: directoryPath,
      filePrefix: filePrefix,
      inputIntegrityError: _bool(json['inputIntegrityError']),
    );
  }
}

/// Stage ids of a failure, persisted with the task (3.x's set).
const recordFailureStages = {
  'room',
  'quality',
  'stream',
  'network',
  'ffmpeg',
  'merge',
  'scheduler',
  'background',
  'status',
  'recorder',
};

/// One recording task: the room, the current attempt and the session's
/// progress (3.x's `LiveRecordTask`, schema 9).
///
/// Mutable like 3.x: the `Recorder` owns it and updates it in place, and
/// listeners read it after each change notification. The JSON is 3.x's, so
/// tasks stored by 3.x load unchanged (M9 moves them into the new store).
final class RecordTask {
  /// Creates a task.
  new({
    required this.taskId,
    required this.roomId,
    required this.platform,
    required this.title,
    required this.nick,
    required this.avatar,
    required this.cover,
    required this.createTime,
    this.recordingStartedAt,
    this.liveStatus = LiveStatus.unknown,
    this.watching = '0',
    this.audienceMetricType = AudienceMetricType.unknown,
    this.followers = '0',
    this.isRecord = false,
    this.selectedLine,
    this.selectedQuality,
    this.selectedQualityId,
    this.selectedLineIndex,
    this.outputDir,
    List<PendingRecordingAttempt> pendingAttempts = const [],
    this.recordedSeconds = 0,
    this.fileSize = 0,
    this.recordSpeed = 0,
    this.bitrate = 0,
    this.fps = 0,
    this.lastFrame = 0,
    this.lastUpdate,
    this.status = RecordStatus.waitingLive,
    this.autoReconnect = true,
    this.retryCount = 0,
    this.wasStoppedByUser = false,
    this.lastFailTime,
    this.lastError,
    this.lastErrorStage,
    this.inputTailDiscarded = false,
    this.inputCoverageIncomplete = false,
    this.qualityOverride,
    this.recordDanmakuOverride,
    this.autoRecord,
    this.lastOutputPath,
  }) : pendingAttempts = List.of(pendingAttempts);

  /// A task for [room], created at [now].
  factory fromRoom(LiveRoom room, {DateTime? now}) => RecordTask(
    taskId: '${room.platform}_${room.roomId}',
    roomId: room.roomId,
    platform: room.platform,
    title: room.title,
    nick: room.nick,
    avatar: room.avatar,
    cover: room.cover,
    watching: room.watching.isEmpty ? '0' : room.watching,
    audienceMetricType: room.effectiveAudienceMetricType,
    followers: room.followers.isEmpty ? '0' : room.followers,
    liveStatus: room.effectiveLiveStatus,
    isRecord: room.isRecord,
    createTime: now ?? DateTime.now(),
  );

  /// Reads 3.x JSON (schema 1–9): numeric drift tolerated, enum names
  /// preferred over indexes, signed URLs and unknown stages dropped,
  /// diagnostics sanitized again.
  factory fromJson(Map<String, Object?> json) {
    final roomId = _string(json['roomId']);
    final platform = _string(json['platform']).toLowerCase();
    return RecordTask(
      taskId: _string(json['taskId'], fallback: '${platform}_$roomId'),
      roomId: roomId,
      platform: platform,
      title: _string(json['title']),
      nick: _string(json['nick']),
      avatar: _string(json['avatar']),
      cover: _string(json['cover']),
      watching: _string(json['watching'], fallback: '0'),
      audienceMetricType: _enum(
        AudienceMetricType.values,
        name: json['audienceMetricTypeName'],
        index: json['audienceMetricType'],
        fallback: _defaultAudience(platform),
      ),
      followers: _string(json['followers'], fallback: '0'),
      isRecord: _bool(json['isRecord']),
      liveStatus: _enum(
        LiveStatus.values,
        name: json['liveStatusName'],
        index: json['liveStatus'],
        fallback: LiveStatus.unknown,
      ),
      selectedLine: _nullableString(json['selectedLine']),
      selectedQuality: _nullableString(json['selectedQuality']),
      selectedQualityId: _nullableString(json['selectedQualityId']),
      selectedLineIndex: _nullableInt(json['selectedLineIndex']),
      outputDir: _nullableString(json['outputDir']),
      pendingAttempts: _pendingAttempts(json['pendingAttempts']),
      recordedSeconds: _recordedSeconds(json['recordedSeconds']),
      fileSize: _int(json['fileSize']),
      recordSpeed: _double(json['recordSpeed']),
      bitrate: _double(json['bitrate']),
      fps: _double(json['fps']),
      lastFrame: _int(json['lastFrame']),
      lastUpdate: _date(json['lastUpdate']),
      status: _enum(
        RecordStatus.values,
        name: json['statusName'],
        index: json['status'],
        fallback: RecordStatus.stopped,
      ),
      autoReconnect: _bool(json['autoReconnect'], fallback: true),
      retryCount: _int(json['retryCount']),
      createTime: _date(json['createTime']) ?? DateTime.now(),
      recordingStartedAt: _date(json['recordingStartedAt']),
      lastFailTime: _date(json['lastFailTime']),
      lastError: _diagnostic(json['lastError']),
      lastErrorStage: _stage(json['lastErrorStage']),
      inputTailDiscarded: _bool(json['inputTailDiscarded']),
      inputCoverageIncomplete: _bool(json['inputCoverageIncomplete']),
      wasStoppedByUser: _bool(json['wasStoppedByUser']),
      qualityOverride: _nullableString(json['qualityOverride']),
      recordDanmakuOverride: _nullableBool(json['recordDanmakuOverride']),
      autoRecord: _nullableBool(json['autoRecord']),
      lastOutputPath: _nullableString(json['lastOutputPath']),
    );
  }

  /// `<platform>_<roomId>`.
  final String taskId;

  /// Room id.
  final String roomId;

  /// Platform id.
  final String platform;

  /// Room title.
  String title;

  /// Streamer name.
  String nick;

  /// Streamer avatar.
  String avatar;

  /// Room cover.
  String cover;

  /// Room state from the last refresh.
  LiveStatus liveStatus;

  /// Audience text.
  String watching;

  /// What [watching] counts: a popularity score is not a head count.
  AudienceMetricType audienceMetricType;

  /// Followers text.
  String followers;

  /// A replay room.
  bool isRecord;

  /// The current attempt's media URL. Runtime only: signed URLs are never
  /// persisted.
  String? currentUrl;

  /// Label of the current line (`线路1`).
  String? selectedLine;

  /// Name of the applied quality.
  String? selectedQuality;

  /// Retry cursor: the requested quality id (no signed data, persisted).
  String? selectedQualityId;

  /// Retry cursor: the line index.
  int? selectedLineIndex;

  /// Directory of the current attempt.
  String? outputDir;

  /// Attempts waiting to be joined into MP4.
  final List<PendingRecordingAttempt> pendingAttempts;

  /// Seconds recorded in this session.
  int recordedSeconds;

  /// Bytes recorded in this session.
  int fileSize;

  /// FFmpeg speed.
  double recordSpeed;

  /// Output bitrate, kbit/s.
  double bitrate;

  /// Video frame rate.
  double fps;

  /// Last frame number.
  int lastFrame;

  /// Last progress.
  DateTime? lastUpdate;

  /// Current state.
  RecordStatus status;

  /// Retry after an interrupted attempt.
  bool autoReconnect;

  /// Consecutive retries.
  int retryCount;

  /// Start of the current attempt; also the attempt's file prefix.
  DateTime createTime;

  /// Start of the user-visible session (kept across attempts).
  DateTime? recordingStartedAt;

  /// Last failure time.
  DateTime? lastFailTime;

  /// Sanitized message of the last failure.
  String? lastError;

  /// Stage of the last failure ([recordFailureStages] or `ffmpeg.<kind>`).
  String? lastErrorStage;

  /// The input's tail was discarded when an attempt stopped.
  bool inputTailDiscarded;

  /// FFmpeg reported skipped HLS segments (a gap, not damage).
  bool inputCoverageIncomplete;

  /// The user stopped the task.
  bool wasStoppedByUser;

  /// The quality this task records at instead of the settings' default
  /// (the live room's "这次录制"; a platform's quality name or one of
  /// `recordQualityPreferences`). Null follows the settings. v4 only: 3.x
  /// JSON has no such field.
  String? qualityOverride;

  /// Whether this task saves the chat, instead of the settings' "record
  /// danmaku". Null follows the settings. v4 only.
  bool? recordDanmakuOverride;

  /// Whether the task waits for the room again after a session ends (the
  /// live room's "开播自动录"). Null keeps 3.x's rule: it waits when
  /// [autoReconnect] is on. v4 only.
  bool? autoRecord;

  /// The MP4 the last join wrote (the live room's "播放"). v4 only.
  String? lastOutputPath;

  /// When the room was last checked for going live. Runtime only.
  DateTime? lastLiveCheckAt;

  /// When a reconnecting task tries again. Runtime only.
  DateTime? nextRetryAt;

  /// The quality preference of the next attempt: [qualityOverride], else
  /// [fallback] (the settings' default).
  String preferredQuality(String fallback) => qualityOverride ?? fallback;

  /// Whether the chat is saved: [recordDanmakuOverride], else [fallback]
  /// (the settings' "record danmaku").
  bool recordsChat({required bool fallback}) => recordDanmakuOverride ?? fallback;

  /// When the session started, for display and ordering.
  DateTime get displayStartTime => recordingStartedAt ?? createTime;

  /// No progress for 30 seconds.
  bool isStalledAt(DateTime now) => lastUpdate != null && now.difference(lastUpdate!).inSeconds > 30;

  /// Takes title, names, audience and state from [room] (3.x
  /// `updateFromRoom`; v4 rooms have no null fields, so empty text keeps the
  /// stored value).
  void updateFromRoom(LiveRoom room) {
    if (room.title.isNotEmpty) title = room.title;
    if (room.nick.isNotEmpty) nick = room.nick;
    if (room.avatar.isNotEmpty) avatar = room.avatar;
    if (room.cover.isNotEmpty) cover = room.cover;
    if (room.watching.isNotEmpty) watching = room.watching;
    audienceMetricType = room.effectiveAudienceMetricType;
    if (room.followers.isNotEmpty) followers = room.followers;
    if (room.liveStatus != null) liveStatus = room.liveStatus!;
    isRecord = room.isRecord;
  }

  /// Starts a new user session: flags and totals reset, session start set.
  void beginNewRecording({DateTime? now}) {
    final startedAt = now ?? DateTime.now();
    inputTailDiscarded = false;
    inputCoverageIncomplete = false;
    recordedSeconds = 0;
    fileSize = 0;
    recordingStartedAt = startedAt;
    beginNewAttempt(now: startedAt);
  }

  /// Starts one capture attempt, keeping the session's totals.
  void beginNewAttempt({DateTime? now}) {
    createTime = now ?? DateTime.now();
    recordSpeed = 0;
    bitrate = 0;
    fps = 0;
    lastFrame = 0;
    lastUpdate = null;
    currentUrl = null;
    selectedLine = null;
    selectedQuality = null;
  }

  /// Adds an attempt to join; a damaged verdict is never erased.
  void queuePendingAttempt({
    required String directoryPath,
    required String filePrefix,
    bool inputIntegrityError = false,
  }) {
    final directory = directoryPath.trim();
    final prefix = filePrefix.trim();
    if (directory.isEmpty || prefix.isEmpty) return;
    final index = pendingAttempts.indexWhere(
      (attempt) => attempt.directoryPath == directory && attempt.filePrefix == prefix,
    );
    final attempt = PendingRecordingAttempt(
      directoryPath: directory,
      filePrefix: prefix,
      inputIntegrityError: inputIntegrityError,
    );
    if (index < 0) {
      pendingAttempts.add(attempt);
    } else if (inputIntegrityError && !pendingAttempts[index].inputIntegrityError) {
      pendingAttempts[index] = attempt;
    }
  }

  /// Removes a joined attempt.
  void removePendingAttempt(PendingRecordingAttempt attempt) => pendingAttempts.removeWhere(
    (candidate) => candidate.directoryPath == attempt.directoryPath && candidate.filePrefix == attempt.filePrefix,
  );

  /// Records a failure of [stage] with a sanitized [error].
  void markFailure({required String stage, required Object error, DateTime? now}) {
    lastFailTime = now ?? DateTime.now();
    lastErrorStage = stage.trim().toLowerCase();
    final text = sanitizeRecordDiagnostic(error);
    lastError = text.isEmpty ? null : text;
  }

  /// Clears the last failure.
  void clearFailure() {
    lastError = null;
    lastErrorStage = null;
  }

  /// Prefix of the current attempt's files: `yyyyMMdd_HHmmss_SSS` of
  /// [createTime].
  String get recordingFilePrefix => recordingPrefixOf(createTime);

  /// JSON of 3.x schema 9; [currentUrl] is never written.
  Map<String, Object?> toJson() => {
    'schemaVersion': 9,
    'taskId': taskId,
    'roomId': roomId,
    'platform': platform,
    'title': title,
    'nick': nick,
    'avatar': avatar,
    'cover': cover,
    'watching': watching,
    'audienceMetricType': audienceMetricType.index,
    'audienceMetricTypeName': audienceMetricType.name,
    'followers': followers,
    'isRecord': isRecord,
    'liveStatus': liveStatus.index,
    'liveStatusName': liveStatus.name,
    'selectedLine': selectedLine,
    'selectedQuality': selectedQuality,
    'selectedQualityId': selectedQualityId,
    'selectedLineIndex': selectedLineIndex,
    'outputDir': outputDir,
    'pendingAttempts': [for (final attempt in pendingAttempts) attempt.toJson()],
    'recordedSeconds': recordedSeconds,
    'fileSize': fileSize,
    'recordSpeed': recordSpeed,
    'bitrate': bitrate,
    'fps': fps,
    'lastFrame': lastFrame,
    'lastUpdate': lastUpdate?.toIso8601String(),
    'status': status.index,
    'statusName': status.name,
    'autoReconnect': autoReconnect,
    'retryCount': retryCount,
    'createTime': createTime.toIso8601String(),
    'recordingStartedAt': recordingStartedAt?.toIso8601String(),
    'lastFailTime': lastFailTime?.toIso8601String(),
    'lastError': lastError,
    'lastErrorStage': lastErrorStage,
    'inputTailDiscarded': inputTailDiscarded,
    'inputCoverageIncomplete': inputCoverageIncomplete,
    'wasStoppedByUser': wasStoppedByUser,
    // v4's own choices: written only when set, so a task without them stays
    // 3.x's JSON and 3.x reads every task (it ignores unknown fields).
    'qualityOverride': ?qualityOverride,
    'recordDanmakuOverride': ?recordDanmakuOverride,
    'autoRecord': ?autoRecord,
    'lastOutputPath': ?lastOutputPath,
  };

  /// Display order of the recording centre (3.x `RecorderTaskOrdering`):
  /// by [RecordStatus.order] when [groupByStatus], then the newest session
  /// first, then by id.
  static List<RecordTask> forDisplay(Iterable<RecordTask> tasks, {required bool groupByStatus}) {
    final result = tasks.toList(growable: false)
      ..sort((left, right) {
        if (groupByStatus) {
          final status = left.status.order.compareTo(right.status.order);
          if (status != 0) return status;
        }
        final time = right.displayStartTime.compareTo(left.displayStartTime);
        return time != 0 ? time : right.taskId.compareTo(left.taskId);
      });
    return result;
  }
}

/// `yyyyMMdd_HHmmss_SSS` of [time]: the attempt prefix of segment names.
String recordingPrefixOf(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}${two(time.month)}${two(time.day)}_'
      '${two(time.hour)}${two(time.minute)}${two(time.second)}_'
      '${time.millisecond.toString().padLeft(3, '0')}';
}

String _string(Object? value, {String fallback = ''}) {
  final text = value?.toString() ?? '';
  return text.isEmpty ? fallback : text;
}

String? _nullableString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String? _diagnostic(Object? value) {
  final text = sanitizeRecordDiagnostic(value);
  return text.isEmpty ? null : text;
}

String? _stage(Object? value) {
  final normalized = value?.toString().trim().toLowerCase() ?? '';
  if (normalized.startsWith('ffmpeg.')) return normalized;
  return recordFailureStages.contains(normalized) ? normalized : null;
}

int _int(Object? value) => value is num ? value.toInt() : int.tryParse(value?.toString() ?? '') ?? 0;

int? _nullableInt(Object? value) => value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

double _double(Object? value) => value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '') ?? 0;

/// FFmpeg's INT32_MAX timestamp sentinel was once stored as a duration; no
/// capture keeps a counter above a year.
int _recordedSeconds(Object? value) {
  final seconds = _int(value);
  return seconds >= 0 && seconds <= 365 * 24 * 60 * 60 ? seconds : 0;
}

bool _bool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return switch (value?.toString().toLowerCase()) {
    'true' || '1' => true,
    'false' || '0' => false,
    _ => fallback,
  };
}

bool? _nullableBool(Object? value) => value == null ? null : _bool(value);

DateTime? _date(Object? value) => DateTime.tryParse(value?.toString() ?? '');

AudienceMetricType _defaultAudience(String platform) => switch (platform) {
  'bilibili' || 'douyu' || 'huya' || 'cc' || 'yy' => AudienceMetricType.popularity,
  'kuaishou' || 'twitch' || 'soop' => AudienceMetricType.onlineViewers,
  'douyin' => AudienceMetricType.totalViewers,
  _ => AudienceMetricType.unknown,
};

List<PendingRecordingAttempt> _pendingAttempts(Object? value) {
  if (value is! List) return const [];
  final attempts = <PendingRecordingAttempt>[];
  final seen = <String, int>{};
  for (final item in value) {
    if (item is! Map) continue;
    final attempt = PendingRecordingAttempt.fromJson(Map<String, Object?>.from(item));
    if (attempt == null) continue;
    final key = '${attempt.directoryPath}\u0000${attempt.filePrefix}';
    final duplicate = seen[key];
    if (duplicate == null) {
      seen[key] = attempts.length;
      attempts.add(attempt);
    } else if (attempt.inputIntegrityError) {
      attempts[duplicate] = attempt;
    }
  }
  return attempts;
}

T _enum<T extends Enum>(List<T> values, {required Object? name, required Object? index, required T fallback}) {
  final normalized = name?.toString().trim() ?? '';
  if (normalized.isNotEmpty) {
    for (final value in values) {
      if (value.name == normalized) return value;
    }
  }
  final parsed = index is num ? index.toInt() : int.tryParse(index?.toString() ?? '');
  return parsed != null && parsed >= 0 && parsed < values.length ? values[parsed] : fallback;
}
