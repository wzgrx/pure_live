import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';

/// What the status card of a record task shows (docs/ui/compare/U.2f, 录制;
/// the same card in the recording centre, U.7a): one look per state of the
/// task, only the actions that work now.
enum RecordCardState {
  /// No task, or a task stopped before anything was recorded: "开始录制".
  idle,

  /// The task waits for the room to go live: "现在就录".
  waiting,

  /// Resolving the stream or starting FFmpeg: "取消".
  preparing,

  /// Every recording slot is taken: "取消" and "改上限".
  queued,

  /// Writing media: the clock and "停止录制".
  recording,

  /// Waiting to retry an interrupted attempt: "停止录制".
  reconnecting,

  /// Joining the attempts into MP4.
  processing,

  /// Finished or stopped with a file: "播放", "在录制中心查看", "再录一次".
  saved,

  /// Failed and not retrying: "查看原因", "重试".
  failed,
}

/// The card state of [task]; [running] and [capacity] tell a task that waits
/// for a slot ([RecordCardState.queued]) from one that starts in a moment
/// (the recorder's start gap, shown as [RecordCardState.preparing]).
RecordCardState recordCardState(RecordTask? task, {int running = 0, int capacity = 1}) {
  if (task == null) return RecordCardState.idle;
  return switch (task.status) {
    RecordStatus.waitingLive => RecordCardState.waiting,
    RecordStatus.preparing => RecordCardState.preparing,
    RecordStatus.queued => running >= capacity ? RecordCardState.queued : RecordCardState.preparing,
    RecordStatus.running => RecordCardState.recording,
    RecordStatus.reconnecting => RecordCardState.reconnecting,
    RecordStatus.processing => RecordCardState.processing,
    RecordStatus.completed => RecordCardState.saved,
    RecordStatus.stopped =>
      task.recordedSeconds > 0 || task.fileSize > 0 ? RecordCardState.saved : RecordCardState.idle,
    RecordStatus.failed => RecordCardState.failed,
  };
}

/// Recordings that hold a slot among [tasks] (resolving, writing or
/// joining; a reconnecting task waits without one).
int recordSlotsInUse(Iterable<RecordTask> tasks) => tasks
    .where(
      (task) => const {RecordStatus.preparing, RecordStatus.running, RecordStatus.processing}.contains(task.status),
    )
    .length;

/// Whether [task] holds or waits for a recording slot: its "这次录制"
/// choices are read-only then.
bool recordBusy(RecordTask? task) => task != null && (task.status.isActive || task.status == RecordStatus.queued);

/// Whether the room records by itself when it goes live ("开播自动录", 3.x's
/// "已监控"): a task that waits for the room, or one that is busy and will
/// wait again afterwards. A stopped, failed or finished task does not.
bool autoRecordOn(RecordTask? task) {
  if (task == null || task.status.isFinished || task.wasStoppedByUser) return false;
  if (task.status == RecordStatus.waitingLive) return true;
  return task.autoRecord ?? true;
}

/// The task of [room] among [tasks].
RecordTask? recordTaskOf(Iterable<RecordTask> tasks, LiveRoom room) =>
    tasks.where((task) => task.platform == room.platform && task.roomId == room.roomId).firstOrNull;

/// The qualities offered for "这次录制": the room's own (as the platform
/// names them, once each), else the settings' five preferences.
List<String> recordQualityChoices(List<LivePlayQuality> roomQualities) {
  final names = <String>[];
  for (final quality in RecordStreamResolver.orderQualities(roomQualities, recordQualityPreferences.first)) {
    final name = quality.quality.trim();
    if (name.isNotEmpty && !names.contains(name)) names.add(name);
  }
  return names.isEmpty ? recordQualityPreferences : names;
}

/// The quality the recorder picks for [preference] among the room's
/// [roomQualities] (its resolver's order); [preference] itself when the room
/// has none.
String recordDefaultQuality(List<LivePlayQuality> roomQualities, String preference) {
  final ordered = RecordStreamResolver.orderQualities(roomQualities, preference);
  return ordered.isEmpty ? preference : ordered.first.quality;
}

/// The whole percent of a join's [progress] (`RecordTask.mergeProgress`),
/// or null before FFmpeg reports.
int? recordMergePercent(double? progress) =>
    progress == null || progress.isNaN ? null : (progress.clamp(0.0, 1.0) * 100).floor();

/// The segment being written: segments are cut every [segmentSeconds].
int recordSegmentNumber(int recordedSeconds, int segmentSeconds) =>
    segmentSeconds <= 0 ? 1 : recordedSeconds ~/ segmentSeconds + 1;

/// The segments of a session of [recordedSeconds] (at least one).
int recordSegmentCount(int recordedSeconds, int segmentSeconds) {
  if (segmentSeconds <= 0 || recordedSeconds <= 0) return 1;
  return (recordedSeconds + segmentSeconds - 1) ~/ segmentSeconds;
}

/// `00:12:34`.
String recordClockText(Duration elapsed) {
  final seconds = elapsed.isNegative ? 0 : elapsed.inSeconds;
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(seconds ~/ 3600)}:${two(seconds ~/ 60 % 60)}:${two(seconds % 60)}';
}

/// `356 MB`, `1.2 GB`: the size as the panel shows it.
String recordShortSize(int bytes) {
  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).round()} MB';
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '${bytes < 0 ? 0 : bytes} B';
}

/// `1,284`.
String groupedNumber(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}

/// The order of the recording centre (U.7a c1, 3.x `RecordStatus.order` in
/// the card's words): recording, reconnecting, joining, preparing, queued,
/// waiting, failed, saved, not recording.
const List<RecordCardState> recordCardOrder = [
  RecordCardState.recording,
  RecordCardState.reconnecting,
  RecordCardState.processing,
  RecordCardState.preparing,
  RecordCardState.queued,
  RecordCardState.waiting,
  RecordCardState.failed,
  RecordCardState.saved,
  RecordCardState.idle,
];

/// Bitrate (3.x `_formatBitrate`): `3.2 Mbps`, `850 kbps`, `--`.
String recordBitrateText(double kilobitsPerSecond) {
  if (!kilobitsPerSecond.isFinite || kilobitsPerSecond <= 0) return '--';
  if (kilobitsPerSecond >= 1000) return '${(kilobitsPerSecond / 1000).toStringAsFixed(1)} Mbps';
  return '${kilobitsPerSecond.toStringAsFixed(0)} kbps';
}

/// `21:35` of [time] in local time.
String recordHourMinute(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}
