import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/recording.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/recording/recording_page.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// What the record menu offers for a room's task (F-ROOM-14).
enum RoomRecordAction {
  /// 立即录制: a live room without a running task.
  recordNow,

  /// 开播时自动录制: an offline room is watched until it goes live.
  watch,

  /// 停止录制.
  stop,

  /// 立即检查: a watched room is checked now.
  checkNow,

  /// 移除监控 / 移除任务: the task goes, its files stay.
  remove,

  /// 录制中心.
  openCenter,
}

/// The entries for [task] of a room that is [live]; in menu order.
List<RoomRecordAction> roomRecordActions(RecordTask? task, {required bool live}) {
  final state = task?.state;
  return [
    if (state == null || state.terminal) ...[
      if (live) RoomRecordAction.recordNow else RoomRecordAction.watch,
      if (task != null) RoomRecordAction.remove,
    ] else if (state == RecordState.waitingLive) ...[
      RoomRecordAction.checkNow,
      RoomRecordAction.remove,
    ] else if (state != RecordState.finalizing)
      RoomRecordAction.stop,
    RoomRecordAction.openCenter,
  ];
}

/// The room's record button (F-ROOM-14): shows the task's state and opens a
/// menu with 立即录制 or 开播时自动录制, 停止录制, 立即检查, 移除 and 录制中心.
class RoomRecordButton extends ConsumerWidget {
  /// Creates the button for [detail].
  const new({required this.detail, super.key});

  /// The room.
  final RoomDetail detail;

  Future<void> _run(BuildContext context, WidgetRef ref, RoomRecordAction action, RecordTask? task) async {
    // Stopping a writing session and removing a task ask first (F-REC-02,
    // spec/modules/record.md §2), as in the recording center.
    if (task != null) {
      final confirmed = await switch (action) {
        RoomRecordAction.stop => confirmRecordStop(context, task),
        RoomRecordAction.remove => confirmRecordRemove(context, task),
        _ => Future.value(true),
      };
      if (!confirmed || !context.mounted) return;
    }
    final manager = ref.read(recordManagerProvider);
    final key = detail.ref.key;
    final messenger = ScaffoldMessenger.maybeOf(context);
    void say(String text) => messenger?.showSnackBar(SnackBar(content: Text(text)));
    try {
      switch (action) {
        case RoomRecordAction.recordNow:
          if (task == null) {
            await manager.add(detail);
          } else {
            await manager.start(key);
          }
          say(t.recording.start);
        case RoomRecordAction.watch:
          if (!ref.read(storeProvider).settings.get(Settings.recordPolling)) {
            messenger?.showSnackBar(
              SnackBar(
                content: Text(t.room.enableMonitoringFirst),
                action: SnackBarAction(
                  label: t.room.goToSettings,
                  onPressed: () => context.go('/me/settings/recording'),
                ),
              ),
            );
            return;
          }
          if (task == null) {
            await manager.add(detail, start: false);
          } else {
            // A strict check first: offline goes back to waiting (polling is on).
            await manager.start(key);
          }
          say(t.room.recordWhenLive);
        case RoomRecordAction.stop:
          say(t.room.stoppingRecording);
          await manager.stop(key);
        case RoomRecordAction.checkNow:
          await manager.checkNow(key);
        case RoomRecordAction.remove:
          await manager.remove(key);
          say(t.room.taskRemoved);
        case RoomRecordAction.openCenter:
          if (context.mounted) context.go('/me/recordings');
      }
    } on Object catch (error) {
      say(describeError(error).title);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = ref.watch(recordTaskProvider(detail.ref.key)).value;
    final state = task?.state;
    final running = state != null && (state.active || state == RecordState.waitingLive);
    final live = detail.state == LiveState.live;
    final label = running ? recordStateText(task!) : t.room.record;
    final colors = Theme.of(context).colorScheme;
    return MenuAnchor(
      menuChildren: [
        for (final action in roomRecordActions(task, live: live))
          MenuItemButton(
            leadingIcon: Icon(switch (action) {
              RoomRecordAction.recordNow => Icons.fiber_manual_record,
              RoomRecordAction.watch => Icons.schedule,
              RoomRecordAction.stop => Icons.stop,
              RoomRecordAction.checkNow => Icons.refresh,
              RoomRecordAction.remove => Icons.delete_outline,
              RoomRecordAction.openCenter => Icons.video_library_outlined,
            }),
            onPressed: () => unawaited(_run(context, ref, action, task)),
            child: Text(switch (action) {
              RoomRecordAction.recordNow => t.room.recordNow,
              RoomRecordAction.watch => t.room.recordOnLive,
              RoomRecordAction.stop => t.recording.stopTitle,
              RoomRecordAction.checkNow => t.recording.checkNow,
              RoomRecordAction.remove => state == RecordState.waitingLive ? t.recording.removeWatch : t.room.removeTask,
              RoomRecordAction.openCenter => t.app.recordings,
            }),
          ),
      ],
      builder: (context, controller, _) {
        void toggle() => controller.isOpen ? controller.close() : controller.open();
        final icon = Icon(
          running && state != RecordState.waitingLive ? Icons.fiber_manual_record : Icons.fiber_manual_record_outlined,
          size: 18,
          color: running && state != RecordState.waitingLive ? colors.error : null,
        );
        return running
            ? FilledButton.tonalIcon(
                key: const ValueKey('room-record'),
                icon: icon,
                label: Text(label),
                onPressed: toggle,
              )
            : OutlinedButton.icon(
                key: const ValueKey('room-record'),
                icon: icon,
                label: Text(label),
                onPressed: toggle,
              );
      },
    );
  }
}
