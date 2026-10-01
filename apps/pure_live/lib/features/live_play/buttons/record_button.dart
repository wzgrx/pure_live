import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/recorder/recorder_texts.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

/// The record button of the room bar (3.x `RecordActionButton`): shows the
/// room's task state; a tap offers record now, wait for live, stop, remove
/// and the recording centre. Hidden where this build cannot record.
class RecordButton extends ConsumerStatefulWidget {
  /// Creates the button for [room].
  const new({required this.room, this.compact = false, super.key});

  /// The room.
  final LiveRoom room;

  /// An icon without a label (narrow bars).
  final bool compact;

  @override
  ConsumerState<RecordButton> createState() => _RecordButtonState();
}

/// What the record sheet offers.
enum _RecordAction { start, monitor, stop, remove, centre }

class _RecordButtonState extends ConsumerState<RecordButton> {
  StreamSubscription<List<RecordTask>>? _changes;
  StreamSubscription<RecordNotice>? _notices;
  bool _busy = false;

  AppRecording? get _recording => ref.read(recordingProvider);

  @override
  void initState() {
    super.initState();
    final recorder = _recording?.recorder;
    _changes = recorder?.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _notices = recorder?.notices.listen((notice) {
      if (!mounted || notice.task.platform != widget.room.platform || notice.task.roomId != widget.room.roomId) return;
      if (recordNoticeText(notice) case final text?) AppNavigator.toast(text);
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    unawaited(_notices?.cancel());
    super.dispose();
  }

  Future<void> _pressed() async {
    final recording = _recording;
    if (recording == null || _busy) return;
    final task = recording.taskFor(widget.room);
    final running = task?.status.isActive ?? false;
    final action = await showModalBottomSheet<_RecordAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        Widget item(_RecordAction action, IconData icon, String key, {required bool enabled}) => ListTile(
          key: ValueKey('record-${action.name}'),
          enabled: enabled,
          leading: Icon(icon),
          title: Text(i18n(key)),
          onTap: () => Navigator.of(sheetContext).pop(action),
        );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (task != null)
                ListTile(
                  leading: Icon(Icons.fiber_manual_record_rounded, color: recordStatusColor(task.status)),
                  title: Text(recordStatusText(task.status)),
                ),
              item(_RecordAction.start, Icons.fiber_manual_record_outlined, 'start_record_now', enabled: !running),
              item(_RecordAction.monitor, Icons.schedule_rounded, 'add_monitor', enabled: task == null),
              item(_RecordAction.stop, Icons.stop_circle_outlined, 'stop_record', enabled: running),
              item(_RecordAction.remove, Icons.delete_outline_rounded, 'remove_monitor', enabled: task != null),
              item(_RecordAction.centre, Icons.video_library_outlined, 'go_record_center', enabled: true),
            ],
          ),
        );
      },
    );
    if (action == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final current = recording.taskFor(widget.room);
      switch (action) {
        case _RecordAction.start:
          if (!await recording.ensureStorageAccess()) return;
          if (current == null) {
            await recording.addTask(widget.room);
          } else if (!current.status.isActive) {
            await recording.startTask(current);
          }
        case _RecordAction.monitor:
          if (current == null && await recording.addTask(widget.room, startImmediately: false) != null) {
            AppNavigator.toast(i18n('record_task_added'));
          }
        case _RecordAction.stop:
          if (current != null) await recording.recorder?.stopTask(current);
        case _RecordAction.remove:
          if (current != null) await recording.recorder?.removeTask(current);
        case _RecordAction.centre:
          unawaited(AppNavigator.toNamed<void>(RoutePath.kRecordPage));
      }
    } on Object {
      AppNavigator.toast(i18n('live_play_record_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recording = ref.watch(recordingProvider);
    if (recording == null || !recording.available) return const SizedBox.shrink();
    final task = recording.taskFor(widget.room);
    final status = task?.status;
    final active = status?.isActive ?? false;
    final label = i18n(
      active
          ? 'recording'
          : task != null
          ? 'monitored'
          : 'record',
    );
    final color = active ? Colors.red : null;
    // M13.16: a hollow circle alone did not read as "record". Idle is the
    // record glyph (a dot in a ring); a monitored room adds an orange dot;
    // a recording one is a red dot with "录制中", on narrow bars too.
    final icon = _busy
        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : active
        ? const Icon(Icons.fiber_manual_record_rounded, color: Colors.red, size: 14)
        : Badge(
            isLabelVisible: task != null,
            smallSize: 7,
            backgroundColor: Colors.orange,
            child: const Icon(Icons.radio_button_checked_rounded),
          );
    final onPressed = _busy ? null : () => unawaited(_pressed());
    if (widget.compact && !active) {
      return IconButton(key: const ValueKey('live-play-record'), tooltip: label, onPressed: onPressed, icon: icon);
    }
    return TextButton.icon(
      key: const ValueKey('live-play-record'),
      style: widget.compact
          ? TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
              backgroundColor: Colors.red.withValues(alpha: 0.1),
            )
          : null,
      onPressed: onPressed,
      icon: icon,
      label: Text(
        label,
        style: TextStyle(color: color, fontSize: widget.compact ? 12 : null),
      ),
    );
  }
}
