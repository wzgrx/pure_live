import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_record/live_record.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/record/record_look.dart';
import 'package:pure_live/shared/record/record_state.dart';

/// What a task's status card shows, apart from the counters that move every
/// second while it records (those redraw on their own): the card rebuilds
/// only when this changes.
typedef RecordCardFacts = ({
  RecordCardState state,
  String quality,
  String? applied,
  bool polling,
  int interval,
  String? lastCheck,
  int maxTasks,
  int running,
  int segmentTime,
  bool recordDanmaku,
  int retry,
  int maxRetry,
  String? failure,
  bool coverageIncomplete,
  bool tailDiscarded,
  bool damagedKept,
  int seconds,
  int bytes,
  DateTime? started,
  DateTime? retryAt,
  DateTime? finished,
});

/// The facts of [task] (null: the room has none) under [settings], with
/// [running] slots in use. [chosen] is the quality picked before there is a
/// task (the panel's "这次录制"); [failure] words the last failure.
RecordCardFacts recordCardFacts(
  RecordTask? task,
  RecordSettings settings, {
  required int running,
  String? chosen,
  String Function(RecordTask task)? failure,
}) {
  final state = recordCardState(task, running: running, capacity: settings.maxTaskCount);
  final moving = state == RecordCardState.recording;
  final check = task?.lastLiveCheckAt;
  return (
    state: state,
    quality: task?.selectedQuality ?? task?.qualityOverride ?? chosen ?? settings.defaultQuality,
    applied: task?.selectedQuality,
    polling: settings.enablePolling,
    interval: settings.liveCheckInterval,
    lastCheck: check == null ? null : recordHourMinute(check),
    maxTasks: settings.maxTaskCount,
    running: running,
    segmentTime: settings.segmentTime,
    recordDanmaku: settings.recordDanmaku,
    retry: task?.retryCount ?? 0,
    maxRetry: settings.maxRetryCount,
    failure: state == RecordCardState.failed && task != null ? failure?.call(task) : null,
    coverageIncomplete: task?.inputCoverageIncomplete ?? false,
    tailDiscarded: task?.inputTailDiscarded ?? false,
    damagedKept: task?.inputDamagedKept ?? false,
    // The counters of a running task redraw in their own small parts.
    seconds: moving ? 0 : task?.recordedSeconds ?? 0,
    bytes: moving ? 0 : task?.fileSize ?? 0,
    started: task?.displayStartTime,
    retryAt: task?.nextRetryAt,
    finished: task?.lastUpdate,
  );
}

String _two(int value) => value.toString().padLeft(2, '0');

/// "今天 21:30", "昨天 21:30", else "10-01 21:30".
String recordDayTime(DateTime time, DateTime now) {
  final local = time.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final clock = recordHourMinute(local);
  if (day == today) return i18n('record_panel_today', args: {'time': clock});
  if (day == today.subtract(const Duration(days: 1))) return i18n('record_panel_yesterday', args: {'time': clock});
  return '${_two(local.month)}-${_two(local.day)} $clock';
}

/// The tones of the status card (U.2f R3: a colour only says the state).
enum _Tone {
  /// Not recording, waiting, preparing, joining.
  neutral,

  /// Recording.
  red,

  /// Queued, reconnecting.
  yellow,

  /// Saved.
  green,

  /// Failed.
  error,
}

_Tone _toneOf(RecordCardState state) => switch (state) {
  RecordCardState.recording => _Tone.red,
  RecordCardState.queued || RecordCardState.reconnecting => _Tone.yellow,
  RecordCardState.saved => _Tone.green,
  RecordCardState.failed => _Tone.error,
  _ => _Tone.neutral,
};

Color _accent(_Tone tone, ColorScheme scheme) => switch (tone) {
  _Tone.red => LiveSemanticColors.recording,
  _Tone.yellow => LiveSemanticColors.warning(scheme.brightness),
  _Tone.green => LiveSemanticColors.success(scheme.brightness),
  _Tone.error => scheme.error,
  _Tone.neutral => scheme.onSurfaceVariant,
};

/// Redraws [builder] every second with the time (a fixed clock does not
/// tick): only the clock and the countdown move, nothing around them.
class _Ticking extends StatefulWidget {
  const new({required this.builder, this.now});

  final Widget Function(BuildContext context, DateTime now) builder;
  final DateTime Function()? now;

  @override
  State<_Ticking> createState() => _TickingState();
}

class _TickingState extends State<_Ticking> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.now == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: widget.builder(context, (widget.now ?? DateTime.now)()));
}

/// The status card of a record task (docs/A-界面设计/A07-直播间界面/A07.6-直播间弹窗, 录制): what the
/// task is doing and the one or two things that can be done now (R2, R5).
///
/// The live room's record panel shows it in full size; the recording centre
/// (docs/A-界面设计/A10-录制界面/A10.1-录制中心, c2) shows the same card [compact]: the clock at 24
/// instead of 36, the buttons 40 high in one row, no explanation under "没在
/// 录制" and "等待开播" (the waiting card says when the room is checked
/// instead), and the recording's gaps under the figures (3.x's warning).
class RecordStatusCard extends StatelessWidget {
  /// Creates the card.
  const new({
    required this.facts,
    required this.changes,
    required this.task,
    required this.chatCount,
    required this.acting,
    required this.onStart,
    required this.onStartTask,
    required this.onStop,
    required this.onLimit,
    required this.onPlay,
    required this.onReason,
    this.onCentre,
    this.onFolder,
    this.compact = false,
    this.now,
    super.key,
  });

  /// What it shows.
  final RecordCardFacts facts;

  /// Announces the task's progress (size, rate, chat, segment).
  final Listenable changes;

  /// The task as it is now.
  final RecordTask? Function() task;

  /// The chat lines saved for a task.
  final int Function(RecordTask task) chatCount;

  /// The clock; a fixed one (tests) does not tick.
  final DateTime Function()? now;

  /// An action runs: the buttons wait.
  final bool acting;

  /// "开始录制", "再录一次".
  final VoidCallback onStart;

  /// "现在就录", "重试".
  final VoidCallback onStartTask;

  /// "停止录制", "取消".
  final VoidCallback onStop;

  /// "改上限".
  final VoidCallback onLimit;

  /// "播放"; hidden when null (no file).
  final VoidCallback? onPlay;

  /// "查看原因".
  final VoidCallback onReason;

  /// "在录制中心查看" of a saved recording (the panel).
  final VoidCallback? onCentre;

  /// "打开文件夹" of a saved recording (the recording centre).
  final VoidCallback? onFolder;

  /// The recording centre's size.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = _toneOf(facts.state);
    final accent = _accent(tone, scheme);
    final neutral = tone == _Tone.neutral;
    final body = theme.textTheme.bodyMedium?.regular.copyWith(color: scheme.onSurfaceVariant);
    final warning = LiveSemanticColors.warning(scheme.brightness);
    final height = compact ? _compactButtonHeight : kMinInteractiveDimension;
    final gap = compact ? 8.0 : 12.0;
    VoidCallback? live(VoidCallback action) => acting ? null : action;
    Widget record(String key, String text, VoidCallback action, {bool dot = true}) =>
        _RecordButton(key: ValueKey(key), text: text, height: height, dot: dot, onPressed: live(action));
    Widget plain(String key, String text, VoidCallback? action) =>
        _PlainButton(key: ValueKey(key), text: text, height: height, onPressed: action);
    Widget stop() => _StopButton(
      key: const ValueKey('record-panel-stop'),
      text: i18n('stop_record'),
      height: height,
      onPressed: live(onStop),
    );
    Widget row(List<Widget> buttons) => Row(
      children: [
        for (final (index, button) in buttons.indexed) ...[
          if (index > 0) SizedBox(width: gap),
          Expanded(child: button),
        ],
      ],
    );
    final quality = facts.quality;
    // The head's glyph (docs/A-界面设计/A10-录制界面/A10.3-录制按钮和状态图标 c9): the room bar's picture of
    // the state, in the card's ink (amber when queued or reconnecting); a
    // join draws its progress.
    final ink = tone == _Tone.yellow ? accent : scheme.onSurfaceVariant;
    Widget glyph(RecordCardState state) => RecordGlyph(state: recordGlyphState(state), size: 20, color: ink);
    final (icon, title, meta, texts, buttons) = switch (facts.state) {
      RecordCardState.idle => (
        glyph(RecordCardState.idle),
        i18n('record_panel_idle_title'),
        null,
        <Widget>[if (!compact) Text(i18n('record_panel_idle_desc'), style: body)],
        <Widget>[record('record-panel-start', i18n('record_panel_start'), onStart)],
      ),
      RecordCardState.waiting => (
        glyph(RecordCardState.waiting),
        i18n('record_panel_waiting_title'),
        null,
        <Widget>[
          if (!compact)
            Text(i18n('record_panel_waiting_desc'), style: body)
          else if (facts.polling)
            Text(
              [
                i18n('record_panel_polling_info', args: {'seconds': '${facts.interval}'}),
                if (facts.lastCheck case final time?) i18n('record_panel_last_check', args: {'time': time}),
              ].join(' · '),
              key: const ValueKey('record-card-polling'),
              style: body?.tabular,
            )
          else
            Text(
              i18n('record_panel_polling_off'),
              key: const ValueKey('record-card-polling-off'),
              style: body?.copyWith(color: warning),
            ),
        ],
        <Widget>[record('record-panel-start-now', i18n('record_panel_start_now'), onStartTask)],
      ),
      RecordCardState.preparing => (
        glyph(RecordCardState.preparing),
        i18n('record_panel_preparing_title'),
        null,
        <Widget>[
          Text(i18n('record_panel_preparing_desc', args: {'quality': quality}), style: body),
        ],
        <Widget>[plain('record-panel-cancel', i18n('cancel'), live(onStop))],
      ),
      RecordCardState.queued => (
        glyph(RecordCardState.queued),
        i18n('record_panel_queued_title'),
        null,
        <Widget>[
          Text(
            i18n('record_panel_queued_desc', args: {'max': '${facts.maxTasks}', 'running': '${facts.running}'}),
            style: body,
          ),
        ],
        <Widget>[
          row([
            plain('record-panel-cancel', i18n('cancel'), live(onStop)),
            plain('record-panel-limit', i18n('record_panel_raise_limit'), onLimit),
          ]),
        ],
      ),
      RecordCardState.recording => (
        glyph(RecordCardState.recording),
        i18n('recording'),
        ListenableSelector<int>(
          listenable: changes,
          selector: () => recordSegmentNumber(task()?.recordedSeconds ?? 0, facts.segmentTime),
          builder: (context, segment, _) => Text(
            i18n('record_panel_segment', args: {'index': '$segment', 'minutes': '${(facts.segmentTime / 60).round()}'}),
            key: const ValueKey('record-panel-segment'),
            style: theme.textTheme.bodySmall?.tabular.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        <Widget>[
          if (facts.started case final started?)
            _Ticking(
              now: now,
              builder: (context, current) => Text(
                recordClockText(current.difference(started)),
                key: const ValueKey('record-panel-clock'),
                style: (compact ? theme.textTheme.headlineSmall : theme.textTheme.displaySmall)?.emphasis.tabular
                    .copyWith(color: scheme.onSurface),
              ),
            ),
          ListenableSelector<(int, int, String?, int, bool)>(
            listenable: changes,
            selector: () {
              final current = task();
              return (
                (current?.fileSize ?? 0) ~/ (1024 * 1024),
                (current?.bitrate ?? 0).round() ~/ 100,
                current?.selectedQuality,
                current == null ? 0 : chatCount(current),
                current?.recordsChat(fallback: facts.recordDanmaku) ?? false,
              );
            },
            builder: (context, _, _) {
              final current = task();
              return Wrap(
                key: const ValueKey('record-panel-figures'),
                spacing: compact ? 6 : 8,
                runSpacing: 6,
                children: [
                  _Chip(i18n('record_panel_recorded_size', args: {'size': recordShortSize(current?.fileSize ?? 0)})),
                  _Chip(recordBitrateText(current?.bitrate ?? 0)),
                  _Chip(current?.selectedQuality ?? quality),
                  if (current != null && current.recordsChat(fallback: facts.recordDanmaku))
                    _Chip(i18n('record_panel_danmaku_count', args: {'count': groupedNumber(chatCount(current))})),
                ],
              );
            },
          ),
        ],
        <Widget>[stop()],
      ),
      RecordCardState.reconnecting => (
        glyph(RecordCardState.reconnecting),
        i18n('record_panel_reconnecting_title'),
        Text(
          i18n('record_panel_reconnect_attempt', args: {'count': '${facts.retry}', 'max': '${facts.maxRetry}'}),
          style: theme.textTheme.bodySmall?.tabular.copyWith(color: scheme.onSurfaceVariant),
        ),
        <Widget>[
          _Ticking(
            now: now,
            builder: (context, current) {
              final left = facts.retryAt?.difference(current).inSeconds ?? 0;
              return Text(
                i18n(
                  'record_panel_reconnect_desc',
                  args: {
                    'seconds': '${left < 0 ? 0 : left}',
                    'duration': recordClockText(Duration(seconds: facts.seconds)),
                    'size': recordShortSize(facts.bytes),
                  },
                ),
                style: body?.tabular,
              );
            },
          ),
        ],
        <Widget>[stop()],
      ),
      // F.3a: how far the join is — the percent where the reconnect card
      // counts its attempts, and a bar under the text (moving until FFmpeg
      // reports); both redraw on their own, at most once per percent.
      RecordCardState.processing => (
        // Redrawn once per percent.
        ListenableSelector<int?>(
          listenable: changes,
          selector: () => recordMergePercent(task()?.mergeProgress),
          builder: (context, percent, _) => RecordGlyph(
            state: RecordGlyphState.processing,
            size: 20,
            color: ink,
            progress: percent == null ? null : percent / 100,
          ),
        ),
        i18n('record_panel_processing_title'),
        ListenableSelector<int?>(
          listenable: changes,
          selector: () => recordMergePercent(task()?.mergeProgress),
          builder: (context, percent, _) => Text(
            percent == null ? '' : '$percent%',
            key: const ValueKey('record-card-merge-percent'),
            style: theme.textTheme.bodySmall?.tabular.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        <Widget>[
          Text(
            i18n(
              // The centre has nothing to close: the panel's "可以关掉这里"
              // is left out.
              compact ? 'record_card_processing_desc' : 'record_panel_processing_desc',
              args: {'count': '${recordSegmentCount(facts.seconds, facts.segmentTime)}'},
            ),
            style: body,
          ),
          ListenableSelector<int?>(
            listenable: changes,
            selector: () => recordMergePercent(task()?.mergeProgress),
            builder: (context, percent, _) => LinearProgressIndicator(
              key: const ValueKey('record-card-merge-progress'),
              value: percent == null ? null : percent / 100,
              minHeight: 4,
              borderRadius: BorderRadius.circular(2),
              semanticsLabel: i18n('record_panel_processing_title'),
              semanticsValue: percent == null ? null : '$percent%',
            ),
          ),
        ],
        const <Widget>[],
      ),
      RecordCardState.saved => (
        Icon(AppIcons.recordSaved, size: 20, color: accent),
        i18n('record_panel_saved_title'),
        facts.finished == null
            ? null
            : Text(
                recordDayTime(facts.finished!, (now ?? DateTime.now)()),
                style: theme.textTheme.bodySmall?.tabular.copyWith(color: scheme.onSurfaceVariant),
              ),
        <Widget>[
          Text(
            [
              i18n('record_panel_saved_desc', args: {'duration': recordClockText(Duration(seconds: facts.seconds))}),
              recordShortSize(facts.bytes),
              ?facts.applied,
              if (task() case final saved? when saved.recordsChat(fallback: facts.recordDanmaku))
                i18n('record_panel_danmaku_count', args: {'count': groupedNumber(chatCount(saved))}),
            ].join(' · '),
            key: const ValueKey('record-panel-saved'),
            style: body?.tabular,
          ),
        ],
        compact
            ? <Widget>[
                row([
                  if (onPlay != null) plain('record-panel-play', i18n('record_panel_play'), onPlay),
                  if (onFolder != null) plain('record-card-folder', i18n('recorder_open_folder'), onFolder),
                  record('record-panel-again', i18n('record_panel_again'), onStart),
                ]),
              ]
            : <Widget>[
                if (onPlay != null || onCentre != null)
                  row([
                    if (onPlay != null) plain('record-panel-play', i18n('record_panel_play'), onPlay),
                    if (onCentre != null) plain('record-panel-view', i18n('record_panel_open_centre'), onCentre),
                    if (onFolder != null) plain('record-card-folder', i18n('recorder_open_folder'), onFolder),
                  ]),
                record('record-panel-again', i18n('record_panel_again'), onStart),
              ],
      ),
      RecordCardState.failed => (
        glyph(RecordCardState.failed),
        i18n('record_panel_failed_title'),
        null,
        <Widget>[
          Text(
            [
              ?facts.failure,
              if (facts.retry > 0) i18n('record_panel_failed_retries', args: {'count': '${facts.retry}'}),
            ].join(),
            style: body,
          ),
        ],
        <Widget>[
          row([
            plain('record-panel-reason', i18n('record_panel_reason'), onReason),
            record('record-panel-retry', i18n('retry'), onStartTask, dot: false),
          ]),
        ],
      ),
    };
    // The recording's gaps (3.x's warning on the card; the centre only).
    final gaps =
        compact && (facts.coverageIncomplete || facts.tailDiscarded || facts.damagedKept) && _showsGaps(facts.state);
    final textGap = compact ? 6.0 : 10.0;
    return DecoratedBox(
      key: ValueKey('record-card-${facts.state.name}'),
      decoration: BoxDecoration(
        color: neutral ? scheme.surfaceContainerHigh : Color.alphaBlend(accent.withValues(alpha: 0.08), scheme.surface),
        border: neutral ? null : Border.all(color: accent.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
      ),
      child: Padding(
        padding: compact ? const EdgeInsets.all(12) : const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox.square(dimension: 22, child: Center(child: icon)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    key: const ValueKey('record-card-title'),
                    style: theme.textTheme.titleMedium?.emphasis.copyWith(color: neutral ? scheme.onSurface : accent),
                  ),
                ),
                ?meta,
              ],
            ),
            for (final child in texts) ...[SizedBox(height: textGap), child],
            if (gaps) ...[
              const SizedBox(height: 8),
              Row(
                key: const ValueKey('record-card-gaps'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(AppIcons.warning, size: 16, color: warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      [
                        if (facts.coverageIncomplete) i18n('recorder_input_coverage_incomplete'),
                        if (facts.tailDiscarded) i18n('recorder_input_tail_discarded'),
                        if (facts.damagedKept) i18n('recorder_input_damaged_kept'),
                      ].join('\n'),
                      style: theme.textTheme.bodySmall?.copyWith(color: warning, height: 1.45),
                    ),
                  ),
                ],
              ),
            ],
            for (final child in buttons) ...[const SizedBox(height: 10), child],
          ],
        ),
      ),
    );
  }
}

/// The states after a session wrote something, where its gaps matter.
bool _showsGaps(RecordCardState state) => switch (state) {
  RecordCardState.recording ||
  RecordCardState.reconnecting ||
  RecordCardState.processing ||
  RecordCardState.saved ||
  RecordCardState.failed => true,
  _ => false,
};

/// The white dot of "● 开始录制".
class _Dot extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 8,
    child: DecoratedBox(
      decoration: BoxDecoration(color: LiveSemanticColors.onRecording, shape: BoxShape.circle),
    ),
  );
}

class _Chip extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.regular.tabular.copyWith(color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }
}

const _buttonShape = StadiumBorder();

/// The compact card's buttons (U.7a c2); the panel's are 48.
const double _compactButtonHeight = 40;

/// The compact card's padding inside a button: three fit a phone's row.
const EdgeInsets _compactButtonPadding = EdgeInsets.symmetric(horizontal: 8);

EdgeInsetsGeometry? _paddingFor(double height) => height == _compactButtonHeight ? _compactButtonPadding : null;

/// A red action that starts a recording ("● 开始录制").
class _RecordButton extends StatelessWidget {
  const new({required this.text, required this.onPressed, required this.height, this.dot = true, super.key});

  final String text;
  final VoidCallback? onPressed;
  final double height;
  final bool dot;

  @override
  Widget build(BuildContext context) => FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: LiveSemanticColors.recording,
      foregroundColor: LiveSemanticColors.onRecording,
      minimumSize: Size.fromHeight(height),
      padding: _paddingFor(height),
      shape: _buttonShape,
    ),
    onPressed: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) ...[const _Dot(), const SizedBox(width: 8)],
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}

/// "■ 停止录制": red outline.
class _StopButton extends StatelessWidget {
  const new({required this.text, required this.onPressed, required this.height, super.key});

  final String text;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      foregroundColor: LiveSemanticColors.recording,
      backgroundColor: Theme.of(context).colorScheme.surface,
      side: const BorderSide(color: LiveSemanticColors.recording),
      minimumSize: Size.fromHeight(height),
      padding: _paddingFor(height),
      shape: _buttonShape,
    ),
    onPressed: onPressed,
    icon: const Icon(AppIcons.stopRecording, size: 18),
    label: Text(text),
  );
}

class _PlainButton extends StatelessWidget {
  const new({required this.text, required this.onPressed, required this.height, super.key});

  final String text;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      backgroundColor: Theme.of(context).colorScheme.surface,
      minimumSize: Size.fromHeight(height),
      padding: _paddingFor(height),
      shape: _buttonShape,
    ),
    onPressed: onPressed,
    child: Text(text, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}
