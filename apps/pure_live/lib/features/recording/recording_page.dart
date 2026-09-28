import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/images.dart';
import 'package:pure_live_app/core/recording.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/recording/record_schedule.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';
import 'package:pure_live_app/i18n/strings.g.dart';
import 'package:url_launcher/url_launcher.dart';

/// State in words (spec/product.md F-REC-01).
String recordStateText(RecordTask task) => switch (task.state) {
  RecordState.queued => t.recording.state.queued,
  RecordState.resolving => t.recording.state.resolving,
  RecordState.recording => t.recording.state.recording,
  RecordState.reconnecting => t.recording.state.reconnecting,
  RecordState.finalizing =>
    task.remuxProgress == null
        ? t.recording.state.finalizing
        : t.recording.state.remuxing(percent: (task.remuxProgress! * 100).round()),
  RecordState.waitingLive => t.recording.state.waitingLive,
  RecordState.completed => t.recording.state.completed,
  RecordState.failed => t.recording.state.failed,
  RecordState.stopped => switch (task.stopCause) {
    StopCause.pollingOff => t.recording.state.stoppedPollingOff,
    StopCause.appRestart => t.recording.state.stoppedAppExit,
    _ => t.recording.state.stopped,
  },
};

/// Why a recording failed, in words; the kind decides, never log text.
String recordFailureText(RecordFailure failure) => switch (failure.kind) {
  RecordErrorKind.roomOffline => t.recording.failure.offline,
  RecordErrorKind.roomBanned => t.recording.failure.banned,
  RecordErrorKind.roomNotFound => t.recording.failure.missing,
  RecordErrorKind.platformUnsupported => t.recording.failure.unsupported,
  RecordErrorKind.loginRequired => t.recording.failure.needsLogin,
  RecordErrorKind.regionBlocked => t.recording.failure.region,
  RecordErrorKind.noQuality || RecordErrorKind.allLinesFailed => t.recording.failure.noStream,
  RecordErrorKind.unsupportedProtocol => t.recording.failure.unsupportedFormat,
  RecordErrorKind.diskFull => t.recording.failure.diskFull,
  RecordErrorKind.permissionDenied || RecordErrorKind.readOnly => t.recording.failure.noPermission,
  RecordErrorKind.pathInvalid => t.recording.failure.directory,
  RecordErrorKind.diskStalled => t.recording.failure.writeStalled,
  RecordErrorKind.backgroundInterrupted => t.recording.failure.background,
  RecordErrorKind.remuxFailed => t.recording.failure.remux,
  RecordErrorKind.inputDamaged => t.recording.failure.corrupt,
  RecordErrorKind.retriesExhausted => t.recording.failure.retries,
  _ => t.recording.failure.stream,
};

/// Where a recording failed (spec/modules/record.md §21 stages), in words.
String recordStageText(RecordStage stage) => switch (stage) {
  RecordStage.room => t.recording.stage.check,
  RecordStage.quality => t.recording.stage.quality,
  RecordStage.stream => t.recording.stage.resolve,
  RecordStage.network => t.recording.stage.connect,
  RecordStage.writer => t.recording.stage.write,
  RecordStage.remux => t.recording.stage.remux,
  RecordStage.scheduler => t.recording.stage.queue,
  RecordStage.background => t.recording.stage.background,
  RecordStage.status => t.recording.stage.poll,
};

/// The display name of [task]: the streamer, or the room number.
String recordTaskName(RecordTask task) =>
    task.snapshot.anchorName.isEmpty ? task.room.roomId : task.snapshot.anchorName;

/// Whether stopping a task in [state] ends a session that is writing or
/// about to write files; such a stop asks first (spec/modules/record.md §2).
bool recordStopNeedsConfirm(RecordState state) => state.holdsSlot;

/// Asks before an action that ends a recording or forgets a task.
Future<bool> confirmRecordAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.common.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
        ],
      ),
    ) ??
    false;

/// Confirms stopping [task] while it resolves, records or reconnects; other
/// states need no confirmation (F-REC-02).
Future<bool> confirmRecordStop(BuildContext context, RecordTask task) async =>
    !recordStopNeedsConfirm(task.state) ||
    await confirmRecordAction(
      context,
      title: t.recording.stopTitle,
      message: t.recording.stopConfirm(name: recordTaskName(task)),
      action: t.common.stop,
    );

/// Confirms removing [task]: "移除监控" for a watched room, "删除录制任务"
/// otherwise (F-REC-02). The files always stay.
Future<bool> confirmRecordRemove(BuildContext context, RecordTask task) {
  final name = recordTaskName(task);
  if (task.state == RecordState.waitingLive) {
    return confirmRecordAction(
      context,
      title: t.recording.removeWatch,
      message: t.recording.removeWatchConfirm(name: name),
      action: t.common.remove,
    );
  }
  return confirmRecordAction(
    context,
    title: t.recording.deleteTask,
    message: task.state.active ? t.recording.deleteTaskRunning(name: name) : t.recording.deleteTaskConfirm(name: name),
    action: t.common.delete,
  );
}

/// What the task list offers (F-REC-01, F-REC-02).
enum RecordTaskAction {
  /// 停止 (asks while a session writes).
  stop,

  /// 开始录制 / 重新录制 for a task in a final state.
  start,

  /// 强制开始: a queued or waiting task starts now (record.md §2).
  forceStart,

  /// 立即检查开播.
  checkNow,

  /// 重试转封装.
  retryRemux,

  /// 打开文件夹.
  openFolder,

  /// 删除任务 / 移除监控 (asks first).
  remove,
}

/// The button next to [task]: stop while it runs or waits, (re)start in a
/// final state, none while its files are finishing.
RecordTaskAction? recordTaskButton(RecordTask task) => switch (task.state) {
  RecordState.finalizing => null,
  final state when state.terminal => RecordTaskAction.start,
  _ => RecordTaskAction.stop,
};

/// The menu entries of [task], in order.
List<RecordTaskAction> recordTaskMenu(RecordTask task) => [
  if (task.state == RecordState.waitingLive) RecordTaskAction.checkNow,
  if (task.state == RecordState.waitingLive || task.state == RecordState.queued) RecordTaskAction.forceStart,
  if (task.state == RecordState.failed && task.failure?.kind == RecordErrorKind.remuxFailed)
    RecordTaskAction.retryRemux,
  if (task.session != null) RecordTaskAction.openFolder,
  RecordTaskAction.remove,
];

String _size(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

String _duration(Duration d) =>
    '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// The recording center (F-REC-01, F-REC-02).
class RecordingPage extends ConsumerWidget {
  const new({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final follows = await ref.read(storeProvider).follows.all();
    if (!context.mounted) return;
    final room = await showModalBottomSheet<RoomRef>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: follows.isEmpty
            ? MessageView(title: t.follows.emptyTitle, message: t.recording.recordFromRoomHint)
            : ListView(
                children: [
                  ListTile(title: Text(t.recording.pickFromFollows)),
                  for (final follow in follows)
                    ListTile(
                      leading: InitialAvatar(
                        name: follow.room.anchorName,
                        seed: follow.ref.key,
                        image: networkImage(
                          follow.room.avatar,
                          logicalWidth: 40,
                          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                        ),
                      ),
                      title: Text(follow.room.anchorName),
                      subtitle: Row(
                        children: [
                          PlatformLogo(platformId: follow.ref.platform),
                          const SizedBox(width: Space.s1),
                          Expanded(child: Text(follow.room.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                      trailing: follow.room.lastState == LiveState.live ? const LiveBadge() : null,
                      onTap: () => Navigator.pop(context, follow.ref),
                    ),
                ],
              ),
      ),
    );
    if (room == null || !context.mounted) return;
    try {
      final detail = await ref.read(sitesProvider)[room.platform]!.rooms.detail(room);
      await ref.read(recordManagerProvider).add(detail);
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(error).title)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(recordManagerProvider);
    final schedule = ref.watch(recordScheduleProvider);
    return Scaffold(
      appBar: PageAppBar(
        // Rows as wide as a reading column, not the window (principles §4.3).
        maxContentWidth: Sizes.readingWidth,
        title: Text(t.app.recordings),
        actions: [
          IconButton(
            tooltip: t.recording.settings,
            icon: const LiveIcon(LiveIcons.settings),
            onPressed: () => context.go('/me/settings/recording'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const LiveIcon(LiveIcons.add),
        label: Text(t.recording.add),
      ),
      body: StreamBuilder<List<RecordTask>>(
        stream: manager.listChanges,
        initialData: manager.tasks,
        builder: (context, snapshot) {
          final tasks = snapshot.data ?? const <RecordTask>[];
          // Until the stored tasks are read, empty is not "none".
          if (tasks.isEmpty && !manager.loaded) return const SkeletonList();
          if (tasks.isEmpty && schedule.isEmpty) {
            return MessageView(
              illustration: Illustration.noRecordings,
              title: t.recording.noTasks,
              message: t.recording.noTasksHint,
            );
          }
          return PageBody(
            maxContentWidth: Sizes.readingWidth,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                // F-IPTV-10: booked windows first.
                if (schedule.isNotEmpty) ...[
                  SettingsHeader(t.recording.scheduled),
                  for (final item in schedule) _ScheduledTile(item: item),
                  if (tasks.isNotEmpty) SettingsHeader(t.recording.tasks),
                ],
                for (final task in tasks) _WatchedTask(initial: task),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WatchedTask extends ConsumerWidget {
  const new({required this.initial});

  final RecordTask initial;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(recordManagerProvider);
    return StreamBuilder<RecordTask>(
      stream: manager.watch(initial.key),
      initialData: initial,
      builder: (context, snapshot) {
        final task = snapshot.data ?? initial;
        return RecordTaskTile(task: task, onAction: (action) => _act(context, manager, task, action));
      },
    );
  }

  Future<void> _act(BuildContext context, RecordManager manager, RecordTask task, RecordTaskAction action) async {
    switch (action) {
      case RecordTaskAction.stop:
        await manager.stop(task.key);
      case RecordTaskAction.start:
        await manager.start(task.key);
      case RecordTaskAction.forceStart:
        await manager.forceStart(task.key);
      case RecordTaskAction.checkNow:
        await manager.checkNow(task.key);
      case RecordTaskAction.retryRemux:
        await manager.retryRemux(task.key);
      case RecordTaskAction.openFolder:
        final directory = task.session!.layout.directory;
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          await launchUrl(Uri.directory(directory));
        } else {
          await Clipboard.setData(ClipboardData(text: directory));
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(t.recording.folderCopied(path: directory))));
          }
        }
      case RecordTaskAction.remove:
        await manager.remove(task.key);
    }
  }
}

/// One task of the recording center (F-REC-01): state, size, duration, the
/// last error with the stage it happened in, a stop or (re)start button and
/// a menu. Stopping a writing session and removing a task ask first
/// (F-REC-02); [onAction] runs only after that.
class RecordTaskTile extends StatelessWidget {
  /// Creates the tile.
  const new({required this.task, required this.onAction, super.key});

  /// The task.
  final RecordTask task;

  /// Runs a confirmed action.
  final Future<void> Function(RecordTaskAction action) onAction;

  Future<void> _dispatch(BuildContext context, RecordTaskAction action) async {
    final confirmed = await switch (action) {
      RecordTaskAction.stop => confirmRecordStop(context, task),
      RecordTaskAction.remove => confirmRecordRemove(context, task),
      _ => Future.value(true),
    };
    if (confirmed) await onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = task.session;
    final details = [
      recordStateText(task),
      if (session != null && session.bytes > 0) _size(session.bytes),
      if (session != null && session.media > Duration.zero) _duration(session.media),
      if (task.state == RecordState.recording && task.bitsPerSecond > 0) '${task.bitsPerSecond ~/ 1000} kbps',
      if (session != null && session.gaps > 0) t.recording.gaps(n: session.gaps),
    ];
    final problem = task.failure ?? task.retrying;
    final next = task.nextCheckAt;
    final button = recordTaskButton(task);
    // principles §3.4: the streamer's avatar leads the row; the logo only
    // names the source, in the subtitle.
    return ListTile(
      leading: InitialAvatar(
        name: recordTaskName(task),
        seed: task.room.key,
        image: networkImage(
          task.snapshot.avatar,
          logicalWidth: 40,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        ),
      ),
      title: Text(recordTaskName(task)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The logo rides on the first line, also when the line wraps. The
          // subtitle's own size and weight, never heavier than the name.
          Text.rich(
            TextSpan(
              children: [
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: Space.s1),
                    child: PlatformLogo(platformId: task.room.platform),
                  ),
                ),
                TextSpan(text: details.join(' · ')),
              ],
            ),
            style: LiveTheme.tabularFigures,
          ),
          if (problem != null)
            Text(
              t.recording.problemWithStage(problem: recordFailureText(problem), stage: recordStageText(problem.stage)),
              style: theme.textTheme.bodySmall!.copyWith(
                color: task.failure != null ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (task.state == RecordState.waitingLive && next != null)
            Text(
              t.recording.nextCheck(time: TimeOfDay.fromDateTime(next.toLocal()).format(context)),
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
      isThreeLine: problem != null || task.state == RecordState.waitingLive,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (button == RecordTaskAction.stop)
            IconButton(
              tooltip: switch (task.state) {
                RecordState.waitingLive => t.recording.stopWatch,
                RecordState.queued => t.recording.cancelQueue,
                _ => t.recording.stopTitle,
              },
              icon: const LiveIcon(LiveIcons.stopTask),
              onPressed: () => unawaited(_dispatch(context, RecordTaskAction.stop)),
            )
          // Starting is an outlined circle with words: the solid red dot
          // means "recording now" (principles §2.2).
          else if (button == RecordTaskAction.start && session == null)
            TextButton.icon(
              icon: const LiveIcon(LiveIcons.record),
              label: Text(t.recording.start),
              onPressed: () => unawaited(_dispatch(context, RecordTaskAction.start)),
            )
          else if (button == RecordTaskAction.start)
            IconButton(
              tooltip: t.recording.restart,
              icon: const LiveIcon(LiveIcons.replay),
              onPressed: () => unawaited(_dispatch(context, RecordTaskAction.start)),
            ),
          PopupMenuButton<RecordTaskAction>(
            icon: const LiveIcon(LiveIcons.more),
            tooltip: t.common.more,
            onSelected: (action) => unawaited(_dispatch(context, action)),
            itemBuilder: (context) => [
              for (final action in recordTaskMenu(task))
                PopupMenuItem(
                  value: action,
                  child: Text(switch (action) {
                    RecordTaskAction.checkNow => t.recording.checkNow,
                    RecordTaskAction.forceStart => t.recording.forceStart,
                    RecordTaskAction.retryRemux => t.recording.retryRemux,
                    RecordTaskAction.openFolder => t.recording.openFolder,
                    RecordTaskAction.remove =>
                      task.state == RecordState.waitingLive ? t.recording.removeWatch : t.recording.deleteKeepFiles,
                    RecordTaskAction.stop => t.common.stop,
                    RecordTaskAction.start => t.recording.restart,
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScheduledTile extends ConsumerWidget {
  const new({required this.item});

  final ScheduledRecording item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final running = !now.isBefore(item.start.toLocal()) && now.isBefore(item.stop.toLocal());
    String at(DateTime time) {
      final local = time.toLocal();
      String two(int value) => value.toString().padLeft(2, '0');
      final day = local.day == now.day && local.month == now.month
          ? ''
          : '${t.common.monthDay(month: local.month, day: local.day)} ';
      return '$day${two(local.hour)}:${two(local.minute)}';
    }

    return ListTile(
      leading: LiveIcon(
        running ? LiveIcons.record : LiveIcons.schedule,
        filled: running,
        // "录制中" follows in the subtitle: dot plus words, the live red.
        color: running ? FixedColors.live : null,
      ),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${item.room.roomId} · ${at(item.start)}–${at(item.stop)}${running ? ' · ${t.recording.state.recording}' : ''}',
      ),
      trailing: IconButton(
        tooltip: t.recording.cancelScheduled,
        icon: const LiveIcon(LiveIcons.close),
        onPressed: () => unawaited(ref.read(recordScheduleProvider.notifier).remove(item)),
      ),
    );
  }
}
