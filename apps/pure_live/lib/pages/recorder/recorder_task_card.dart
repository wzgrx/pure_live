import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/recorder/recorder_texts.dart';

/// What a card's buttons do (the page owns the recorder).
final class RecorderCardActions {
  /// Creates the actions.
  const new({required this.open, required this.start, required this.check, required this.stop, required this.remove});

  /// Opens the room.
  final void Function(RecordTask task) open;

  /// Starts a new session (3.x `forceStartTask`).
  final Future<void> Function(RecordTask task) start;

  /// Checks whether the room is live now (waiting tasks).
  final Future<void> Function(RecordTask task) check;

  /// Stops the task.
  final Future<void> Function(RecordTask task) stop;

  /// Stops and removes the task.
  final Future<void> Function(RecordTask task) remove;
}

/// One task of the recording centre (3.x `_TaskCard`): cover with the
/// status, title, streamer, platform, quality, line and audience; the
/// recording's figures; warnings and the last failure; the actions.
class RecorderTaskCard extends StatefulWidget {
  /// Creates the card of [task].
  const new({required this.task, required this.actions, this.restriction, super.key});

  /// The task (mutable; the page rebuilds on every change).
  final RecordTask task;

  /// The buttons.
  final RecorderCardActions actions;

  /// The room's restriction learnt from this session's notice (22-1).
  final LiveRestriction? restriction;

  @override
  State<RecorderTaskCard> createState() => _RecorderTaskCardState();
}

class _RecorderTaskCardState extends State<RecorderTaskCard> {
  String? _busy;

  RecordTask get task => widget.task;

  Future<void> _run(String action, Future<void> Function(RecordTask task) work) async {
    if (_busy != null) return;
    setState(() => _busy = action);
    try {
      await work(task);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _confirmRemove() async {
    if (_busy != null) return;
    final name = [
      task.title,
      task.nick,
      task.roomId,
    ].map((value) => value.trim()).firstWhere((value) => value.isNotEmpty, orElse: () => '--');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        title: Text(i18n('recorder_cancel_monitor')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(i18n('recorder_cancel_monitor_confirm_named', args: {'name': name})),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(i18n('cancel'))),
          FilledButton(
            key: const ValueKey('recorder-remove-confirm'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(i18n('confirm')),
          ),
        ],
      ),
    );
    if (ok ?? false) await _run('remove', widget.actions.remove);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = context.textStyles;
    final color = recordStatusColor(task.status);
    final showStats =
        const {
          RecordStatus.running,
          RecordStatus.reconnecting,
          RecordStatus.processing,
          RecordStatus.preparing,
        }.contains(task.status) ||
        task.recordedSeconds > 0 ||
        task.fileSize > 0;
    final transitioning = const {
      RecordStatus.reconnecting,
      RecordStatus.preparing,
      RecordStatus.processing,
    }.contains(task.status);
    final failure = (task.lastError?.isNotEmpty ?? false) && task.status != RecordStatus.running
        ? recordFailureText(task, restriction: widget.restriction)
        : null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: task.status == RecordStatus.running
              ? Colors.green.withValues(alpha: 0.35)
              : theme.colorScheme.outline.withValues(alpha: 0.08),
        ),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('recorder-card-${task.taskId}'),
          borderRadius: BorderRadius.circular(18),
          onTap: () => widget.actions.open(task),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final details = _details(theme, styles);
                    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
                    if (constraints.maxWidth < 480 * textScale) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [_cover(color, styles), const SizedBox(height: 12), details],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _cover(color, styles),
                        const SizedBox(width: 14),
                        Expanded(child: details),
                      ],
                    );
                  },
                ),
                if (showStats) ...[const SizedBox(height: 14), _stats(theme)],
                if (transitioning) ...[
                  const SizedBox(height: 12),
                  _banner(
                    color: color.withValues(alpha: 0.08),
                    border: color.withValues(alpha: 0.14),
                    leading: SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: color),
                    ),
                    text: Text(
                      task.status == RecordStatus.reconnecting && task.retryCount > 0
                          ? i18n('recorder_retry_count', args: {'count': '${task.retryCount}'})
                          : recordStatusText(task.status),
                      style: styles.t12.copyWith(color: color, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
                if (task.inputTailDiscarded || task.inputCoverageIncomplete) ...[
                  const SizedBox(height: 12),
                  _banner(
                    key: const ValueKey('recorder-input-warning'),
                    color: theme.colorScheme.tertiaryContainer,
                    leading: Icon(Icons.warning_amber_rounded, size: 17, color: theme.colorScheme.onTertiaryContainer),
                    text: Text(
                      [
                        if (task.inputCoverageIncomplete) i18n('recorder_input_coverage_incomplete'),
                        if (task.inputTailDiscarded) i18n('recorder_input_tail_discarded'),
                      ].join('\n'),
                      style: styles.t12.copyWith(color: theme.colorScheme.onTertiaryContainer, height: 1.3),
                    ),
                  ),
                ],
                if (failure != null) ...[
                  const SizedBox(height: 12),
                  _banner(
                    key: const ValueKey('recorder-last-error'),
                    color: theme.colorScheme.errorContainer.withValues(alpha: 0.52),
                    leading: Icon(Icons.error_outline_rounded, size: 17, color: theme.colorScheme.error),
                    text: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          failure.summary,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: styles.t12.copyWith(color: theme.colorScheme.onErrorContainer, height: 1.3),
                        ),
                        if (failure.detail case final detail?)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              detail,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: styles.t11.copyWith(
                                color: theme.colorScheme.onErrorContainer.withValues(alpha: 0.7),
                                height: 1.3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _miniInfo(theme, styles, Icons.schedule_rounded, recordTimeText(task.displayStartTime)),
                      _actions(theme, styles),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover(Color color, AppTextStyles styles) {
    final url = normalizeImageUrl(task.cover);
    Widget blank(BuildContext _) => const ColoredBox(color: Colors.black12);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 150,
        height: 90,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url.isEmpty)
              const ColoredBox(color: Colors.black12)
            else
              LiveNetworkImage(url: url, placeholder: blank, error: blank, memCacheWidth: 360),
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 0.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (task.status == RecordStatus.running) ...[const _Pulse(), const SizedBox(width: 5)],
                    Text(
                      recordStatusText(task.status),
                      style: styles.t12.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _details(ThemeData theme, AppTextStyles styles) {
    final audienceKey = switch (task.audienceMetricType) {
      AudienceMetricType.popularity => 'audience_popularity',
      AudienceMetricType.onlineViewers => 'audience_online',
      AudienceMetricType.totalViewers => 'audience_total',
      AudienceMetricType.followers => 'audience_followers',
      AudienceMetricType.unknown => 'audience_count',
    };
    final audienceIcon = switch (task.audienceMetricType) {
      AudienceMetricType.popularity => Icons.whatshot_rounded,
      AudienceMetricType.totalViewers => Icons.visibility_rounded,
      AudienceMetricType.followers => Icons.favorite_rounded,
      AudienceMetricType.onlineViewers || AudienceMetricType.unknown => Icons.people_alt_rounded,
    };
    final title = task.title.trim().isNotEmpty ? task.title : task.roomId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: styles.t16.copyWith(fontWeight: FontWeight.w700, height: 1.2, letterSpacing: 0.1),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            CommonAvatar(avatarUrl: normalizeImageUrl(task.avatar), radius: 12, fallbackName: task.nick),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                task.nick,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: styles.t14.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PlatformLogo(task.platform, size: 14),
                const SizedBox(width: 4),
                Text(recordPlatformName(task.platform), style: styles.t11.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            _miniInfo(theme, styles, Icons.high_quality_rounded, task.selectedQuality ?? i18n('recorder_auto')),
            if (task.selectedLine?.isNotEmpty ?? false)
              _miniInfo(theme, styles, Icons.alt_route_rounded, task.selectedLine!),
            _miniInfo(theme, styles, audienceIcon, '${i18n(audienceKey)} ${task.watching}'),
          ],
        ),
      ],
    );
  }

  Widget _stats(ThemeData theme) {
    final running = task.status == RecordStatus.running;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              _statItem(theme, Icons.timer_outlined, recordDurationText(task.recordedSeconds)),
              _statItem(theme, Icons.storage_rounded, recordSizeText(task.fileSize)),
              _statItem(theme, Icons.speed_rounded, '${task.recordSpeed.toStringAsFixed(1)}x'),
              _statItem(theme, Icons.graphic_eq_rounded, recordBitrateText(task.bitrate)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 4,
              child: running || task.status == RecordStatus.processing
                  ? LinearProgressIndicator(color: theme.colorScheme.primary)
                  : ColoredBox(color: theme.colorScheme.primary.withValues(alpha: 0.4)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(ThemeData theme, IconData icon, String label) {
    final color = theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: context.textStyles.t12.copyWith(fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniInfo(ThemeData theme, AppTextStyles styles, IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          label,
          style: styles.t11.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
        ),
      ),
    ],
  );

  Widget _banner({required Color color, required Widget leading, required Widget text, Color? border, Key? key}) =>
      Container(
        key: key,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: border == null ? null : Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leading,
            const SizedBox(width: 8),
            Expanded(child: text),
          ],
        ),
      );

  Widget _actions(ThemeData theme, AppTextStyles styles) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    final textStyle = styles.t12.copyWith(fontWeight: FontWeight.w700);
    const padding = EdgeInsets.symmetric(horizontal: 14);
    const size = Size(0, kMinInteractiveDimension);
    Widget label(String action, String text) => _busy == action
        ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
        : Text(text);
    final busy = _busy != null;
    final remove = TextButton(
      key: const ValueKey('recorder-remove'),
      onPressed: busy ? null : _confirmRemove,
      child: _busy == 'remove'
          ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(i18n('remove'), style: styles.t15.copyWith(color: busy ? null : Colors.red)),
    );
    Widget primary(String action, String text, Future<void> Function(RecordTask task) work) => FilledButton(
      key: ValueKey('recorder-$action'),
      style: FilledButton.styleFrom(padding: padding, minimumSize: size, shape: shape, textStyle: textStyle),
      onPressed: busy ? null : () => unawaited(_run(action, work)),
      child: label(action, text),
    );
    final stop = FilledButton(
      key: const ValueKey('recorder-stop'),
      style: FilledButton.styleFrom(
        backgroundColor: Colors.redAccent,
        padding: padding,
        minimumSize: size,
        shape: shape,
        textStyle: textStyle,
      ),
      onPressed: busy ? null : () => unawaited(_run('stop', widget.actions.stop)),
      child: label('stop', i18n('recorder_stop')),
    );
    final children = switch (task.status) {
      RecordStatus.running || RecordStatus.reconnecting || RecordStatus.preparing => [remove, stop],
      RecordStatus.queued => [
        remove,
        primary('start', i18n('recorder_start'), widget.actions.start),
        OutlinedButton(
          key: const ValueKey('recorder-cancel'),
          style: OutlinedButton.styleFrom(
            padding: padding,
            minimumSize: size,
            shape: shape,
            side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
            textStyle: textStyle,
          ),
          onPressed: busy ? null : () => unawaited(_run('cancel', widget.actions.stop)),
          child: label('cancel', i18n('cancel')),
        ),
      ],
      RecordStatus.waitingLive => [
        remove,
        primary('check', i18n('recorder_check_now'), widget.actions.check),
        primary('start', i18n('recorder_start'), widget.actions.start),
      ],
      RecordStatus.failed => [remove, primary('start', i18n('retry'), widget.actions.start)],
      RecordStatus.completed => [remove, primary('start', i18n('recorder_restart_record'), widget.actions.start)],
      RecordStatus.stopped ||
      RecordStatus.processing => [remove, primary('start', i18n('recorder_start'), widget.actions.start)],
    };
    return Wrap(alignment: WrapAlignment.end, spacing: 6, runSpacing: 4, children: children);
  }
}

/// The blinking dot of a running recording.
class _Pulse extends StatefulWidget {
  const new();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
    child: const DecoratedBox(
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: SizedBox.square(dimension: 7),
    ),
  );
}
