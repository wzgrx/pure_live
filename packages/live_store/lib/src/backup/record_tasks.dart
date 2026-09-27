import 'package:live_core/live_core.dart';
import 'package:live_store/src/settings/values.dart';
import 'package:meta/meta.dart';

/// One recording task in a backup (store.md §7.1 `recordTasks`): which room
/// to record and how, never where its files are or what a session did.
@immutable
final class BackupRecordTask {
  /// Creates a task.
  const new({
    required this.ref,
    required this.createdAt,
    this.anchorName = '',
    this.title = '',
    this.avatar,
    this.cover,
    this.quality,
    this.autoReconnect = true,
    this.monitor = false,
  });

  /// The room.
  final RoomRef ref;

  /// When the task was added (the task list's order).
  final DateTime createdAt;

  /// Streamer name, for showing the task.
  final String anchorName;

  /// Broadcast title, for showing the task.
  final String title;

  /// Avatar.
  final Uri? avatar;

  /// Cover.
  final Uri? cover;

  /// The task's own quality; null uses `record.defaultQuality`.
  final QualityPreference? quality;

  /// Reconnect after a dropped connection.
  final bool autoReconnect;

  /// The user wants the room recorded when it goes live: the task was
  /// recording, queued or waiting when backed up. Restored as waiting for
  /// the room while `record.polling` is on (spec/modules/record.md §12).
  final bool monitor;

  /// The backup item.
  Map<String, Object?> toJson({int? order}) => {
    'platform': ref.platform,
    'roomId': ref.roomId,
    'nick': anchorName,
    'title': title,
    if (avatar != null) 'avatar': avatar.toString(),
    if (cover != null) 'cover': cover.toString(),
    'quality': quality?.name,
    'autoReconnect': autoReconnect,
    'monitor': monitor,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'order': ?order,
  };

  @override
  bool operator ==(Object other) =>
      other is BackupRecordTask &&
      other.ref == ref &&
      other.createdAt == createdAt &&
      other.anchorName == anchorName &&
      other.title == title &&
      other.avatar == avatar &&
      other.cover == cover &&
      other.quality == quality &&
      other.autoReconnect == autoReconnect &&
      other.monitor == monitor;

  @override
  int get hashCode => Object.hash(ref, createdAt, anchorName, title, avatar, cover, quality, autoReconnect, monitor);

  @override
  String toString() => 'BackupRecordTask(${ref.key}${monitor ? ', monitor' : ''})';
}

/// Recording tasks live outside the database (the app's
/// `DB/record_tasks.json`, managed by the recorder), so a backup reaches
/// them through this (store.md §7.1, §7.2).
abstract interface class RecordTaskBackup {
  /// The current tasks, in list order.
  Future<List<BackupRecordTask>> exportTasks();

  /// Replaces the tasks with [tasks] (validated, in order): tasks recording
  /// right now stay as they are; returns how many were written.
  Future<int> restoreTasks(List<BackupRecordTask> tasks);
}
