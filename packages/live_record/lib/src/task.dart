import 'package:live_core/live_core.dart';
import 'package:live_record/src/errors.dart';
import 'package:live_record/src/naming.dart';
import 'package:live_record/src/quality.dart';
import 'package:live_record/src/settings.dart';
import 'package:meta/meta.dart';

/// Task states (spec §3).
enum RecordState {
  /// Waiting for a concurrency slot.
  queued,

  /// Strict room check and resolve.
  resolving,

  /// Writing media.
  recording,

  /// Connection lost, reconnecting inside the same session.
  reconnecting,

  /// Closing files; remux when enabled.
  finalizing,

  /// Polling until the room goes live (only while `record.polling` is on).
  waitingLive,

  /// Ended normally (terminal).
  completed,

  /// Ended with a typed failure (terminal).
  failed,

  /// Stopped (terminal): by the user, or see [StopCause].
  stopped;

  /// A session exists (queued through finalizing).
  bool get active => index <= finalizing.index;

  /// Holds a concurrency slot (spec §11.2).
  bool get holdsSlot => this == resolving || this == recording || this == reconnecting;

  /// Completed, failed or stopped.
  bool get terminal => this == completed || this == failed || this == stopped;
}

/// Why a task is [RecordState.stopped].
enum StopCause {
  /// The user stopped it (the "user stopped" latch of spec §2).
  user,

  /// It was waiting for the room while polling was switched off; switching
  /// polling on again puts it back to waiting.
  pollingOff,

  /// It was active when the app last ended and was not resumed (§14.1).
  appRestart,
}

/// Display fields of the room (spec §2; only for showing the task).
@immutable
final class RecordRoomSnapshot {
  /// Creates a snapshot.
  const new({this.anchorName = '', this.title = '', this.avatar, this.cover});

  /// From a room detail.
  factory of(RoomDetail detail) => RecordRoomSnapshot(
    anchorName: detail.card.anchorName,
    title: detail.card.title,
    avatar: detail.avatar ?? detail.card.avatar,
    cover: detail.card.cover,
  );

  /// Restores a persisted snapshot.
  factory fromJson(Map<String, Object?> json) => RecordRoomSnapshot(
    anchorName: json['anchorName'] as String? ?? '',
    title: json['title'] as String? ?? '',
    avatar: json['avatar'] == null ? null : Uri.tryParse(json['avatar']! as String),
    cover: json['cover'] == null ? null : Uri.tryParse(json['cover']! as String),
  );

  /// Streamer name.
  final String anchorName;

  /// Broadcast title.
  final String title;

  /// Avatar.
  final Uri? avatar;

  /// Cover.
  final Uri? cover;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'anchorName': anchorName,
    'title': title,
    'avatar': avatar?.toString(),
    'cover': cover?.toString(),
  };
}

/// What the current or last session produced (spec §2, §19).
@immutable
final class RecordSessionInfo {
  /// Creates the info.
  const new({
    required this.layout,
    this.segments = const [],
    this.outputs = const [],
    this.bytes = 0,
    this.media = Duration.zero,
    this.gaps = 0,
    this.connections = 0,
    this.splices = 0,
  });

  /// Restores persisted info; a duration over a year is taken as damaged and reset (§13, REG-RECORD-011).
  factory fromJson(Map<String, Object?> json) {
    final mediaMs = (json['mediaMs'] as num?)?.toInt() ?? 0;
    return RecordSessionInfo(
      layout: SessionLayout.fromJson((json['layout']! as Map).cast<String, Object?>()),
      segments: [for (final path in json['segments'] as List? ?? const []) path as String],
      outputs: [for (final path in json['outputs'] as List? ?? const []) path as String],
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      media: Duration(milliseconds: mediaMs < 0 || mediaMs > const Duration(days: 366).inMilliseconds ? 0 : mediaMs),
      gaps: (json['gaps'] as num?)?.toInt() ?? 0,
      connections: (json['connections'] as num?)?.toInt() ?? 0,
      splices: (json['splices'] as num?)?.toInt() ?? 0,
    );
  }

  /// Directory, prefix and start time.
  final SessionLayout layout;

  /// Segment files (final paths).
  final List<String> segments;

  /// Remuxed MP4 files.
  final List<String> outputs;

  /// Bytes written.
  final int bytes;

  /// Media duration written.
  final Duration media;

  /// Gaps recorded.
  final int gaps;

  /// Connections opened.
  final int connections;

  /// Renewals spliced.
  final int splices;

  /// A copy with the given values replaced.
  RecordSessionInfo copyWith({
    List<String>? segments,
    List<String>? outputs,
    int? bytes,
    Duration? media,
    int? gaps,
    int? connections,
    int? splices,
  }) => RecordSessionInfo(
    layout: layout,
    segments: segments ?? this.segments,
    outputs: outputs ?? this.outputs,
    bytes: bytes ?? this.bytes,
    media: media ?? this.media,
    gaps: gaps ?? this.gaps,
    connections: connections ?? this.connections,
    splices: splices ?? this.splices,
  );

  /// JSON form.
  Map<String, Object?> toJson() => {
    'layout': layout.toJson(),
    'segments': segments,
    'outputs': outputs,
    'bytes': bytes,
    'mediaMs': media.inMilliseconds,
    'gaps': gaps,
    'connections': connections,
    'splices': splices,
  };
}

const _unset = _Unset();

final class _Unset {
  const new();
}

/// An immutable snapshot of one recording task (spec §2). One task per room;
/// its [key] is the room key. Connection data (URLs, headers, cookies) is
/// never part of it.
@immutable
final class RecordTask {
  /// Creates a snapshot.
  const new({
    required this.room,
    required this.createdAt,
    required this.state,
    this.snapshot = const RecordRoomSnapshot(),
    this.quality,
    this.cursor,
    this.autoReconnect = true,
    this.failure,
    this.stopCause,
    this.session,
    this.retrying,
    this.nextCheckAt,
    this.bitsPerSecond = 0,
    this.lastGapMs,
    this.remuxProgress,
  });

  /// Restores a persisted task.
  factory fromJson(Map<String, Object?> json) => RecordTask(
    room: RoomRef.parse(json['room']! as String),
    createdAt: DateTime.parse(json['createdAt']! as String),
    state: RecordState.values.asNameMap()[json['state']] ?? RecordState.stopped,
    snapshot: RecordRoomSnapshot.fromJson((json['snapshot'] as Map? ?? const {}).cast<String, Object?>()),
    quality: RecordQuality.values.asNameMap()[json['quality']],
    cursor: json['cursor'] == null ? null : RecordCursor.fromJson((json['cursor']! as Map).cast<String, Object?>()),
    autoReconnect: json['autoReconnect'] as bool? ?? true,
    failure: json['failure'] == null ? null : RecordFailure.fromJson((json['failure']! as Map).cast<String, Object?>()),
    stopCause: StopCause.values.asNameMap()[json['stopCause']],
    session: json['session'] == null
        ? null
        : RecordSessionInfo.fromJson((json['session']! as Map).cast<String, Object?>()),
  );

  /// Room identity.
  final RoomRef room;

  /// When the task was added; tasks are listed in this order (REG-RECORD-039).
  final DateTime createdAt;

  /// State.
  final RecordState state;

  /// Display fields.
  final RecordRoomSnapshot snapshot;

  /// Task quality override; null uses `record.defaultQuality`.
  final RecordQuality? quality;

  /// Last quality and line position.
  final RecordCursor? cursor;

  /// Reconnect automatically (copied from the settings when started).
  final bool autoReconnect;

  /// Why the task failed ([RecordState.failed]); sanitised.
  final RecordFailure? failure;

  /// Why the task is stopped ([RecordState.stopped]).
  final StopCause? stopCause;

  /// Current or last session.
  final RecordSessionInfo? session;

  /// The last retryable error while reconnecting or polling (not persisted).
  final RecordFailure? retrying;

  /// Next waiting-for-live check (not persisted).
  final DateTime? nextCheckAt;

  /// Current bit rate (not persisted).
  final int bitsPerSecond;

  /// Missing time of the last gap (not persisted).
  final int? lastGapMs;

  /// Remux progress 0–1 while finalizing (not persisted).
  final double? remuxProgress;

  /// Storage key: the room key.
  String get key => room.key;

  /// The "user stopped" latch (spec §2).
  bool get userStopped => state == RecordState.stopped && stopCause == StopCause.user;

  /// A copy with the given values replaced; pass null through the nullable
  /// parameters to clear them.
  RecordTask copyWith({
    RecordState? state,
    RecordRoomSnapshot? snapshot,
    Object? quality = _unset,
    Object? cursor = _unset,
    bool? autoReconnect,
    Object? failure = _unset,
    Object? stopCause = _unset,
    Object? session = _unset,
    Object? retrying = _unset,
    Object? nextCheckAt = _unset,
    int? bitsPerSecond,
    Object? lastGapMs = _unset,
    Object? remuxProgress = _unset,
  }) => RecordTask(
    room: room,
    createdAt: createdAt,
    state: state ?? this.state,
    snapshot: snapshot ?? this.snapshot,
    quality: identical(quality, _unset) ? this.quality : quality as RecordQuality?,
    cursor: identical(cursor, _unset) ? this.cursor : cursor as RecordCursor?,
    autoReconnect: autoReconnect ?? this.autoReconnect,
    failure: identical(failure, _unset) ? this.failure : failure as RecordFailure?,
    stopCause: identical(stopCause, _unset) ? this.stopCause : stopCause as StopCause?,
    session: identical(session, _unset) ? this.session : session as RecordSessionInfo?,
    retrying: identical(retrying, _unset) ? this.retrying : retrying as RecordFailure?,
    nextCheckAt: identical(nextCheckAt, _unset) ? this.nextCheckAt : nextCheckAt as DateTime?,
    bitsPerSecond: bitsPerSecond ?? this.bitsPerSecond,
    lastGapMs: identical(lastGapMs, _unset) ? this.lastGapMs : (lastGapMs as num?)?.toInt(),
    remuxProgress: identical(remuxProgress, _unset) ? this.remuxProgress : (remuxProgress as num?)?.toDouble(),
  );

  /// JSON form for persistence: never URLs, headers, cookies or keys (spec §13).
  Map<String, Object?> toJson() => {
    'room': room.key,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'state': state.name,
    'snapshot': snapshot.toJson(),
    'quality': quality?.name,
    'cursor': cursor?.toJson(),
    'autoReconnect': autoReconnect,
    'failure': failure?.toJson(),
    'stopCause': stopCause?.name,
    'session': session?.toJson(),
  };

  @override
  String toString() => 'RecordTask($key, ${state.name}${failure == null ? '' : ', ${failure!.kind.name}'})';
}
