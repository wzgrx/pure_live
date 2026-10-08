import 'dart:async';
import 'dart:developer';

import 'package:flutter/widgets.dart';
import 'package:live_record/live_record.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

// What Android's recording notifications say (docs/A-界面设计/A14-系统界面/A14.1-系统界面 c3–c5;
// 3.x always showed "直播录制进行中 / 录制与封装由独立后台服务保护…").

/// The words of the recording notification, and the one active task's id
/// (H05.2: a tap opens the recording centre at it; null with none or several).
typedef RecordNotificationContent = ({String title, String text, String stop, DateTime? since, String? task});

String _nick(RecordTask task) => task.nick.trim().isEmpty ? platformName(task.platform) : task.nick.trim();

/// The notification for [tasks] (U.14 c3, c4): one room "正在录制 · 晚风"
/// over its title and quality (or what it does instead of writing:
/// preparing, reconnecting, joining; U.2a2 X4); several "正在录制 N 个直播间" over the
/// streamers. Its `since` is the first recording's
/// start, from which the system's clock counts (no refresh every second).
RecordNotificationContent recordNotificationContent(Iterable<RecordTask> tasks) {
  final active = [
    for (final task in tasks)
      if (task.status.isActive) task,
  ];
  if (active.isEmpty) {
    return (
      title: i18n('recorder_background_notification_title'),
      text: i18n('recorder_background_notification_text'),
      stop: i18n('record_notify_stop'),
      since: null,
      task: null,
    );
  }
  DateTime? since;
  for (final task in active) {
    final start = task.displayStartTime;
    if (since == null || start.isBefore(since)) since = start;
  }
  if (active.length == 1) {
    final task = active.single;
    return (
      title: i18n(_oneTitleKey(task.status), args: {'name': _nick(task)}),
      text: [task.title.trim(), task.selectedQuality?.trim() ?? ''].where((part) => part.isNotEmpty).join(' · '),
      stop: i18n('record_notify_stop'),
      since: since,
      task: task.taskId,
    );
  }
  return (
    title: i18n('record_notify_many', args: {'count': '${active.length}'}),
    text: active.map(_nick).join('、'),
    stop: i18n('record_notify_stop_all'),
    since: since,
    task: null,
  );
}

/// One room's headline: only a stream being written says "正在录制" (U.2a2
/// X4; 3.x and 4.0.0 said so while preparing and joining too).
String _oneTitleKey(RecordStatus status) => switch (status) {
  RecordStatus.preparing => 'record_notify_one_preparing',
  RecordStatus.reconnecting => 'record_notify_one_reconnecting',
  RecordStatus.processing => 'record_notify_one_processing',
  _ => 'record_notify_one',
};

/// "5:52:10", "12:34" (the recording centre's duration).
String formatRecordDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = seconds % 3600 ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:${minutes.toString().padLeft(2, '0')}:$rest' : '$minutes:$rest';
}

/// The "录制已停止" reminder of [task] (U.14 c5): why it stopped and what
/// was saved.
({String title, String text}) recordStoppedContent(RecordTask task) {
  final reason = switch ((task.lastErrorStage, task.lastError)) {
    ('background', 'timeout') => i18n('record_stopped_timeout'),
    ('background', _) => i18n('record_stopped_killed'),
    _ => i18n('record_stopped_failed'),
  };
  final saved = task.recordedSeconds > 0
      ? i18n('record_stopped_saved', args: {'duration': formatRecordDuration(task.recordedSeconds)})
      : i18n('record_stopped_restart');
  return (title: i18n('record_stopped_title', args: {'name': _nick(task)}), text: '$reason$saved');
}

/// Follows the recorder for Android's notifications (U.14 c3–c5): the
/// ongoing notification's words when the recordings change ([refresh],
/// which sends only real changes), and a reminder ([alert]) when a
/// recording fails because Android stopped the background service, or
/// fails while the app is not in front. "停止录制 / 全部停止" on the
/// notification arrives at [stopAll].
final class RecordingNotices {
  /// Creates the follower of a recorder's [tasks] and [changes].
  new({
    required this.tasks,
    required this.changes,
    required this.stopTask,
    required this.refresh,
    required this.alert,
    bool Function()? inFront,
  }) : _inFront = inFront ?? (() => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

  /// Follows [recorder].
  factory of(
    Recorder recorder, {
    required Future<void> Function() refresh,
    required Future<void> Function(String id, String title, String text) alert,
  }) => RecordingNotices(
    tasks: () => recorder.tasks,
    changes: recorder.changes,
    stopTask: recorder.stopTask,
    refresh: refresh,
    alert: alert,
  );

  /// The recorder's tasks now.
  final List<RecordTask> Function() tasks;

  /// The task list after every change.
  final Stream<List<RecordTask>> changes;

  /// Stops a task as the user would (what was recorded is saved).
  final Future<void> Function(RecordTask task) stopTask;

  /// Updates the ongoing notification.
  final Future<void> Function() refresh;

  /// Posts a reminder `(id, title, text)`.
  final Future<void> Function(String id, String title, String text) alert;

  final bool Function() _inFront;
  final Map<String, RecordStatus> _last = {};
  StreamSubscription<List<RecordTask>>? _changes;

  /// Starts following.
  void start() {
    for (final task in tasks()) {
      _last[task.taskId] = task.status;
    }
    _changes ??= changes.listen(changed);
  }

  /// One change of the task list.
  @visibleForTesting
  void changed(List<RecordTask> tasks) {
    unawaited(refresh().catchError((Object error) => log('Notification update failed: $error', name: 'Recording')));
    for (final task in tasks) {
      final before = _last[task.taskId];
      _last[task.taskId] = task.status;
      if (task.status != RecordStatus.failed || before == RecordStatus.failed || before == null) continue;
      if (task.lastErrorStage != 'background' && _inFront()) continue;
      final content = recordStoppedContent(task);
      unawaited(
        alert(task.taskId, content.title, content.text).catchError((Object error) {
          log('Recording reminder failed: $error', name: 'Recording');
        }),
      );
    }
  }

  /// Stops every recording in progress (the notification's button); what
  /// was recorded is saved.
  Future<void> stopAll() async {
    await Future.wait([
      for (final task in tasks())
        if (task.status.isActive || task.status == RecordStatus.queued) stopTask(task),
    ]);
  }

  /// Stops following.
  Future<void> dispose() async => await _changes?.cancel();
}
