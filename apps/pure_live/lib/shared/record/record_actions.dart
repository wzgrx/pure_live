import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/record/record_state.dart';

// What the live room's record panel (U.2f) and the recording centre (U.7a)
// do the same way: "开播自动录", the live check it needs, "再录一次",
// "播放" and "查看原因".

/// The argument of `RoutePath.kRecordSettings` that scrolls the page to
/// "最大同时录制任务数" and highlights it (the "改上限" buttons, U.7b c9).
const String recordSettingsMaxTasks = 'max-tasks';

/// "改上限" of a queued recording (the room's record panel, the recording
/// centre): the recording settings at the "最大同时录制任务数" row.
Future<void> openRecordLimit() =>
    AppNavigator.toNamed<void>(RoutePath.kRecordSettings, arguments: recordSettingsMaxTasks);

/// Turns the live check on when it is off ("开播自动录" needs it, U.2f F2;
/// the centre's "打开"), with the toast.
Future<void> enableRecordPolling(AppRecording recording) async {
  final current = recording.settings.current;
  if (current.enablePolling) return;
  await recording.settings.set(Settings.recordEnablePolling, true);
  AppNavigator.toast(i18n('record_panel_polling_enabled', args: {'seconds': '${current.liveCheckInterval}'}));
}

/// "开播自动录" (3.x's 添加/取消监控) of [task], or of [room] when it has no
/// task yet (a new task waits for the room with [quality] and [danmaku]).
/// Turning it off leaves a running recording alone and removes a task that
/// only waits (3.x's 取消监控).
Future<void> setAutoRecord(
  AppRecording recording,
  Recorder recorder, {
  required bool on,
  required RecordTask? task,
  LiveRoom? room,
  String? quality,
  bool? danmaku,
}) async {
  if (on) {
    await enableRecordPolling(recording);
    if (task == null) {
      if (room == null) return;
      recording.keepAlive?.allowUserRetry();
      await recorder.addTask(room, startImmediately: false, quality: quality, recordDanmaku: danmaku, autoRecord: true);
    } else if (recordBusy(task)) {
      recorder.setTaskOptions(task, autoRecord: true);
    } else {
      await recorder.monitorTask(task);
    }
  } else if (task != null) {
    if (recordBusy(task)) {
      recorder.setTaskOptions(task, autoRecord: false);
    } else if (task.status == RecordStatus.waitingLive) {
      await recorder.removeTask(task);
    }
  }
}

/// "开始录制", "再录一次" of an existing [task]: a new session now, which
/// ends with the broadcast unless "开播自动录" is on (U.2f F3).
Future<void> recordTaskAgain(AppRecording recording, Recorder recorder, RecordTask task) async {
  if (recordBusy(task)) return;
  if (!autoRecordOn(task)) recorder.setTaskOptions(task, autoRecord: false);
  await recording.startTask(task);
}

/// "播放": the recording in the system's player.
Future<void> playRecording(String path) async {
  if (!await AppNavigator.openFile(path)) AppNavigator.toast(i18n('record_panel_play_failed'));
}

/// "查看原因": the whole failure, selectable.
Future<void> showRecordFailureReason(BuildContext context, ({String summary, String? detail}) text) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: Text(i18n('record_panel_reason_title')),
    content: SelectableText([text.summary, ?text.detail].join('\n\n')),
    actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(i18n('close')))],
  ),
);
