import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/record/record_actions.dart';
import 'package:pure_live/shared/record/record_state.dart';
import 'package:pure_live/shared/record/record_status_card.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// What a card's buttons do (the page owns the recorder).
final class RecorderCardActions {
  /// Creates the actions.
  const new({
    required this.open,
    required this.again,
    required this.startNow,
    required this.stop,
    required this.remove,
    required this.setAuto,
    required this.limit,
    required this.folder,
    required this.reason,
    required this.failed,
  });

  /// Opens the room ("进入直播间", a tap on the card).
  final void Function(RecordTask task) open;

  /// "开始录制", "再录一次": a new session (3.x `forceStartTask`).
  final Future<void> Function(RecordTask task) again;

  /// "现在就录", "重试" (3.x's 立即检测 and 重试, also `forceStartTask`).
  final Future<void> Function(RecordTask task) startNow;

  /// "停止录制", "取消".
  final Future<void> Function(RecordTask task) stop;

  /// "删除任务": stops (and saves) the task, then removes it.
  final Future<void> Function(RecordTask task) remove;

  /// "开播自动录" on or off.
  final Future<void> Function(RecordTask task, {required bool on}) setAuto;

  /// "改上限": the recording settings.
  final VoidCallback limit;

  /// "打开文件夹" of a saved recording.
  final void Function(RecordTask task) folder;

  /// "查看原因".
  final void Function(BuildContext context, RecordTask task) reason;

  /// An action threw.
  final VoidCallback failed;
}

/// What the card's layout depends on: the status card's facts and the head.
typedef _CardView = ({
  RecordCardFacts facts,
  String nick,
  String title,
  String cover,
  String platform,
  String audience,
  bool auto,
  String? output,
});

/// The entries of a card's menu (U.7a c4).
enum _CardMenu {
  /// "进入直播间".
  open,

  /// "开播自动录" (a switch).
  auto,

  /// "删除任务".
  delete,
}

/// One task of the recording centre (docs/ui/compare/U.7a, c2–c5): the
/// head (cover, streamer with "自动录", title, platform and audience, "⋮"),
/// then the live room's status card (U.2f) in its compact size. A tap opens
/// the room (3.x); a long press, a right click or "⋮" opens the menu:
/// "进入直播间", "开播自动录", "删除任务".
class RecorderTaskCard extends StatefulWidget {
  /// Creates the card of the task [taskId].
  const new({
    required this.taskId,
    required this.task,
    required this.facts,
    required this.changes,
    required this.chatCount,
    required this.actions,
    this.wide = false,
    this.now,
    super.key,
  });

  /// The task's id.
  final String taskId;

  /// The task as it is now (null once removed).
  final RecordTask? Function() task;

  /// The status card's facts of a task.
  final RecordCardFacts Function(RecordTask task) facts;

  /// Announces the recorder's and the settings' changes.
  final Listenable changes;

  /// The chat lines saved for a task.
  final int Function(RecordTask task) chatCount;

  /// The buttons.
  final RecorderCardActions actions;

  /// A wide page: the larger cover (160×90 instead of 96×54).
  final bool wide;

  /// The clock; a fixed one (tests) does not tick.
  final DateTime Function()? now;

  @override
  State<RecorderTaskCard> createState() => _RecorderTaskCardState();
}

class _RecorderTaskCardState extends State<RecorderTaskCard> {
  final _menu = GlobalKey<AppMenuButtonState<_CardMenu>>();
  bool _acting = false;

  _CardView? _view() {
    final task = widget.task();
    if (task == null) return null;
    final audience = task.watching.trim();
    return (
      facts: widget.facts(task),
      nick: task.nick.trim().isNotEmpty ? task.nick.trim() : task.roomId,
      title: task.title.trim().isNotEmpty ? task.title.trim() : task.roomId,
      cover: normalizeImageUrl(task.cover),
      platform: task.platform,
      audience: audience.isEmpty || audience == '0'
          ? ''
          : '${audienceLabel(task.audienceMetricType)} ${readableAudience(audience)}',
      auto: autoRecordOn(task),
      output: task.lastOutputPath,
    );
  }

  Future<void> _run(Future<void> Function(RecordTask task) action) async {
    final task = widget.task();
    if (task == null || _acting) return;
    setState(() => _acting = true);
    try {
      await action(task);
    } on Object {
      widget.actions.failed();
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  void _showMenu() => unawaited(_menu.currentState?.show());

  void _onMenu(_CardMenu entry) {
    final task = widget.task();
    if (task == null) return;
    switch (entry) {
      case _CardMenu.open:
        widget.actions.open(task);
      case _CardMenu.auto:
        unawaited(_run((task) => widget.actions.setAuto(task, on: !autoRecordOn(task))));
      case _CardMenu.delete:
        unawaited(_confirmDelete(task));
    }
  }

  Future<void> _confirmDelete(RecordTask task) async {
    final name = [
      task.nick,
      task.title,
      task.roomId,
    ].map((value) => value.trim()).firstWhere((value) => value.isNotEmpty, orElse: () => '--');
    final ok = await showAppConfirmDialog(
      context: context,
      key: const ValueKey('recorder-delete-dialog'),
      title: i18n('recorder_delete_title', args: {'name': name}),
      message: i18n('recorder_delete_body'),
      confirmLabel: i18n('delete'),
      danger: true,
      confirmKey: const ValueKey('recorder-delete-confirm'),
    );
    if (ok) await _run(widget.actions.remove);
  }

  /// The small menu (U.1d, B03): open, "开播自动录" with its switch (the
  /// row toggles it and the menu closes), delete.
  List<AppMenuEntry<_CardMenu>> _menuItems() => [
    AppMenuEntry(
      key: const ValueKey('recorder-menu-open'),
      value: _CardMenu.open,
      icon: AppIcons.enterRoom,
      label: i18n('room_open'),
    ),
    AppMenuEntry(
      key: const ValueKey('recorder-menu-auto'),
      value: _CardMenu.auto,
      icon: AppIcons.autoRecord,
      label: i18n('record_panel_auto_switch'),
      switchValue: autoRecordOn(widget.task()),
      switchKey: const ValueKey('recorder-menu-auto-switch'),
    ),
    AppMenuEntry(
      key: const ValueKey('recorder-menu-delete'),
      value: _CardMenu.delete,
      icon: AppIcons.delete,
      label: i18n('recorder_delete_task'),
      danger: true,
      divider: true,
    ),
  ];

  @override
  Widget build(BuildContext context) => ListenableSelector<_CardView?>(
    listenable: widget.changes,
    selector: _view,
    builder: (context, view, _) {
      if (view == null) return const SizedBox.shrink();
      final scheme = Theme.of(context).colorScheme;
      final actions = widget.actions;
      void run(Future<void> Function(RecordTask task) action) => unawaited(_run(action));
      final output = view.output;
      return Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: ValueKey('recorder-card-${widget.taskId}'),
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (widget.task() case final task?) actions.open(task);
          },
          onLongPress: _showMenu,
          onSecondaryTap: _showMenu,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Head(view: view, wide: widget.wide, menu: _menuButton()),
                const SizedBox(height: 10),
                RecordStatusCard(
                  facts: view.facts,
                  changes: widget.changes,
                  task: widget.task,
                  chatCount: widget.chatCount,
                  acting: _acting,
                  compact: true,
                  now: widget.now,
                  onStart: () => run(actions.again),
                  onStartTask: () => run(actions.startNow),
                  onStop: () => run(actions.stop),
                  onLimit: actions.limit,
                  // "播放" while the file is there (the panel's rule).
                  onPlay: output != null && File(output).existsSync() ? () => unawaited(playRecording(output)) : null,
                  onFolder: () {
                    if (widget.task() case final task?) actions.folder(task);
                  },
                  onReason: () {
                    if (widget.task() case final task?) actions.reason(context, task);
                  },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _menuButton() => AppMenuButton<_CardMenu>(
    key: _menu,
    tooltip: i18n('more'),
    icon: const Icon(AppIcons.more, size: 22),
    entries: _menuItems,
    onSelected: _onMenu,
  );
}

/// The card's head (U.7a c3): cover, the streamer with "自动录", the title,
/// the platform and the audience; "⋮" at the top right. No state on the
/// cover any more (the status card says it, P2).
class _Head extends StatelessWidget {
  const new({required this.view, required this.wide, required this.menu});

  final _CardView view;
  final bool wide;
  final Widget menu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final secondary = scheme.onSurfaceVariant;
    final (width, height) = wide ? (160.0, 90.0) : (96.0, 54.0);
    Widget blank(BuildContext _) => ColoredBox(color: scheme.surfaceContainerHighest);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            key: const ValueKey('recorder-card-cover'),
            width: width,
            height: height,
            child: view.cover.isEmpty
                ? blank(context)
                : LiveNetworkImage(
                    url: view.cover,
                    placeholder: blank,
                    error: blank,
                    // Decoded at twice the size shown.
                    memCacheWidth: (width * 2).round(),
                  ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      view.nick,
                      key: const ValueKey('recorder-card-nick'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.emphasis.copyWith(color: scheme.onSurface),
                    ),
                  ),
                  if (view.auto) ...[const SizedBox(width: 6), const _AutoPill()],
                ],
              ),
              const SizedBox(height: 1),
              Text(
                view.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.regular.copyWith(color: secondary),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  ClipRRect(borderRadius: BorderRadius.circular(3), child: PlatformLogo(view.platform, size: 13)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      [platformName(view.platform), if (view.audience.isNotEmpty) view.audience].join(' · '),
                      key: const ValueKey('recorder-card-meta'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.regular.tabular.copyWith(color: secondary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // "⋮" sits in the card's corner (40 × 40, the padding taken back).
        Transform.translate(
          offset: const Offset(6, -6),
          child: SizedBox.square(dimension: 40, child: menu),
        ),
      ],
    );
  }
}

/// "⏱ 自动录" (the live room bar's mark, U.2a change 13).
class _AutoPill extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      key: const ValueKey('recorder-card-auto'),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(11)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.autoRecord, size: 13, color: scheme.onPrimaryContainer),
            const SizedBox(width: 3),
            Text(
              i18n('live_play_auto_record'),
              maxLines: 1,
              style: theme.textTheme.bodySmall?.emphasis.copyWith(color: scheme.onPrimaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}
