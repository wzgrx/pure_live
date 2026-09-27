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
import 'package:pure_live_app/core/recording.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:url_launcher/url_launcher.dart';

/// State in words (spec/product.md F-REC-01).
String recordStateText(RecordTask task) => switch (task.state) {
  RecordState.queued => '排队中',
  RecordState.resolving => '准备中',
  RecordState.recording => '录制中',
  RecordState.reconnecting => '重连中',
  RecordState.finalizing => task.remuxProgress == null ? '处理中' : '转封装 ${(task.remuxProgress! * 100).round()}%',
  RecordState.waitingLive => '等待开播',
  RecordState.completed => '已完成',
  RecordState.failed => '失败',
  RecordState.stopped => switch (task.stopCause) {
    StopCause.pollingOff => '已停止（开播监控已关闭）',
    StopCause.appRestart => '已停止（应用退出）',
    _ => '已停止',
  },
};

/// Why a recording failed, in words; the kind decides, never log text.
String recordFailureText(RecordFailure failure) => switch (failure.kind) {
  RecordErrorKind.roomOffline => '主播已下播',
  RecordErrorKind.roomBanned => '直播间被封禁',
  RecordErrorKind.roomNotFound => '直播间不存在',
  RecordErrorKind.platformUnsupported => '这个平台暂不支持录制',
  RecordErrorKind.loginRequired => '需要登录平台账号',
  RecordErrorKind.regionBlocked => '当前地区无法观看',
  RecordErrorKind.noQuality || RecordErrorKind.allLinesFailed => '拿不到可录制的直播流',
  RecordErrorKind.unsupportedProtocol => '这个直播间只有暂不支持录制的 HLS 流',
  RecordErrorKind.diskFull => '存储空间不足',
  RecordErrorKind.permissionDenied || RecordErrorKind.readOnly => '没有录制目录的写入权限',
  RecordErrorKind.pathInvalid => '录制目录不可用',
  RecordErrorKind.diskStalled => '磁盘写入卡住了',
  RecordErrorKind.backgroundInterrupted => '后台运行时间被系统用尽',
  RecordErrorKind.remuxFailed => '转成 MP4 失败，原始文件已保留',
  RecordErrorKind.inputDamaged => '录制文件损坏',
  RecordErrorKind.retriesExhausted => '多次重试都没有成功',
  _ => '网络或直播流出错',
};

/// Where a recording failed (spec/modules/record.md §21 stages), in words.
String recordStageText(RecordStage stage) => switch (stage) {
  RecordStage.room => '房间检查',
  RecordStage.quality => '选画质',
  RecordStage.stream => '取流',
  RecordStage.network => '连接',
  RecordStage.writer => '写文件',
  RecordStage.remux => '转封装',
  RecordStage.scheduler => '排队调度',
  RecordStage.background => '后台运行',
  RecordStage.status => '开播检查',
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
        ],
      ),
    ) ??
    false;

/// Confirms stopping [task] while it resolves, records or reconnects; other
/// states need no confirmation (F-REC-02).
Future<bool> confirmRecordStop(BuildContext context, RecordTask task) async =>
    !recordStopNeedsConfirm(task.state) ||
    await confirmRecordAction(context, title: '停止录制', message: '停止录制“${recordTaskName(task)}”？已录的部分会保存。', action: '停止');

/// Confirms removing [task]: "移除监控" for a watched room, "删除录制任务"
/// otherwise (F-REC-02). The files always stay.
Future<bool> confirmRecordRemove(BuildContext context, RecordTask task) {
  final name = recordTaskName(task);
  if (task.state == RecordState.waitingLive) {
    return confirmRecordAction(context, title: '移除监控', message: '不再等待“$name”开播？已录的文件会保留。', action: '移除');
  }
  return confirmRecordAction(
    context,
    title: '删除录制任务',
    message: task.state.active ? '删除“$name”的录制任务？正在进行的录制会先停止，已录的文件会保留。' : '删除“$name”的录制任务？已录的文件会保留。',
    action: '删除',
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
            ? const MessageView(title: '还没有关注的主播', message: '也可以在直播间里点录制按钮。')
            : ListView(
                children: [
                  const ListTile(title: Text('从关注里选择')),
                  for (final follow in follows)
                    ListTile(
                      leading: PlatformLogo(platformId: follow.ref.platform, size: Sizes.iconMd),
                      title: Text(follow.room.anchorName),
                      subtitle: Text(follow.room.title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('录制中心'),
        actions: [
          IconButton(
            tooltip: '录制设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go('/me/settings/recording'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('添加录制'),
      ),
      body: StreamBuilder<List<RecordTask>>(
        stream: manager.listChanges,
        initialData: manager.tasks,
        builder: (context, snapshot) {
          final tasks = snapshot.data ?? const <RecordTask>[];
          if (tasks.isEmpty) {
            return const MessageView(
              icon: Icons.fiber_manual_record_outlined,
              title: '还没有录制任务',
              message: '在直播间点录制，或者从关注里添加。开启开播监控后，主播开播会自动开始录制。',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: tasks.length,
            itemBuilder: (context, index) => _WatchedTask(initial: tasks[index]),
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
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('文件夹路径已复制：$directory')));
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
      if (session != null && session.gaps > 0) '缺口 ${session.gaps}',
    ];
    final problem = task.failure ?? task.retrying;
    final next = task.nextCheckAt;
    final button = recordTaskButton(task);
    return ListTile(
      leading: PlatformLogo(platformId: task.room.platform, size: Sizes.iconLg),
      title: Text(recordTaskName(task)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(details.join(' · '), style: LiveTheme.of(context).numeric),
          if (problem != null)
            Text(
              '${recordFailureText(problem)} · 出错环节：${recordStageText(problem.stage)}',
              style: theme.textTheme.bodySmall!.copyWith(
                color: task.failure != null ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (task.state == RecordState.waitingLive && next != null)
            Text('下次检查 ${TimeOfDay.fromDateTime(next.toLocal()).format(context)}', style: theme.textTheme.bodySmall),
        ],
      ),
      isThreeLine: problem != null || task.state == RecordState.waitingLive,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (button == RecordTaskAction.stop)
            IconButton(
              tooltip: switch (task.state) {
                RecordState.waitingLive => '停止监控',
                RecordState.queued => '取消排队',
                _ => '停止录制',
              },
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: () => unawaited(_dispatch(context, RecordTaskAction.stop)),
            )
          else if (button == RecordTaskAction.start)
            IconButton(
              tooltip: session == null ? '开始录制' : '重新录制',
              icon: session == null
                  ? const Icon(Icons.fiber_manual_record, color: Color(0xFFD92D20))
                  : const Icon(Icons.replay),
              onPressed: () => unawaited(_dispatch(context, RecordTaskAction.start)),
            ),
          PopupMenuButton<RecordTaskAction>(
            tooltip: '更多',
            onSelected: (action) => unawaited(_dispatch(context, action)),
            itemBuilder: (context) => [
              for (final action in recordTaskMenu(task))
                PopupMenuItem(
                  value: action,
                  child: Text(switch (action) {
                    RecordTaskAction.checkNow => '立即检查开播',
                    RecordTaskAction.forceStart => '强制开始',
                    RecordTaskAction.retryRemux => '重试转封装',
                    RecordTaskAction.openFolder => '打开文件夹',
                    RecordTaskAction.remove => task.state == RecordState.waitingLive ? '移除监控' : '删除任务（保留文件）',
                    RecordTaskAction.stop => '停止',
                    RecordTaskAction.start => '重新录制',
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
