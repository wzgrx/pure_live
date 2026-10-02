import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_ui/live_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/recorder/recorder_texts.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/record/record_actions.dart';
import 'package:pure_live/shared/record/record_state.dart';
import 'package:pure_live/shared/record/record_status_card.dart';
import 'package:pure_live/shared/record/saved_file.dart';

/// Opens the record panel of [room]: the room's panel (U.2f), or the same
/// panel in a sheet where there is no room page around [context] (a lone
/// record button).
void showRecordPanel(BuildContext context, {required LiveRoom Function() room}) {
  final panels = RoomPanelScope.maybeOf(context);
  if (panels != null) {
    panels.open(RoomPanelKind.record);
    return;
  }
  unawaited(
    showRoomPanelSheet(
      context,
      heightFactor: 0.75,
      builder: (_, close) => RoomRecordPanel(room: room, onClose: close),
    ),
  );
}

/// The record panel (docs/A-界面设计/A07-直播间界面/A07.6-直播间弹窗, 录制, confirmed): "录制" with
/// "录制中心 ›" and ✕; the status card, "这次录制", "自动录", then
/// "录制设置 ›" and where files go. Under the picture in portrait, on the
/// right otherwise; the picture keeps playing. It replaces 3.x's dialog of
/// five actions, all of which are here: 立即启动录制 → "开始录制"/"现在就录",
/// 停止录制 → "停止录制", 添加/取消监控 → "开播自动录", 进入录制中心 →
/// "录制中心 ›".
class RoomRecordPanel extends StatelessWidget {
  /// Creates the panel.
  const new({required this.room, required this.onClose, this.qualities, this.dragToClose = false, this.now, super.key});

  /// The room as known now.
  final LiveRoom Function() room;

  /// The room's qualities ("这次录制" offers them); the settings' five
  /// preferences when null or empty.
  final List<LivePlayQuality> Function()? qualities;

  /// Closes the panel.
  final VoidCallback onClose;

  /// A downward drag on the header closes it (portrait).
  final bool dragToClose;

  /// The clock; a fixed one (tests) does not tick.
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) => RoomSidePanel(
    key: const ValueKey('live-play-record-panel'),
    title: i18n('record'),
    onClose: onClose,
    dragToClose: dragToClose,
    actions: [
      PanelLink(
        key: const ValueKey('record-panel-centre'),
        text: i18n('record_center'),
        onPressed: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kRecordPage)),
      ),
    ],
    child: RecordPanelBody(room: room, qualities: qualities, now: now),
  );
}

/// The whole failure of the last recording, in the panel (B09 c8).
class _FailureReason extends StatelessWidget {
  const new({required this.text, required this.onClose});

  final ({String summary, String? detail}) text;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      key: const ValueKey('record-panel-reason-text'),
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(i18n('record_panel_reason_title'), style: theme.textTheme.titleSmall?.emphasis)),
                TextButton(
                  key: const ValueKey('record-panel-reason-close'),
                  onPressed: onClose,
                  child: Text(i18n('live_play_details_fold')),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SelectableText(
                [text.summary, ?text.detail].join('\n\n'),
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Announces the recorder's and the settings' changes to the panel's parts.
final class _Changes extends ChangeNotifier {
  void changed() => notifyListeners();
}

/// What the panel's layout depends on: the status card's facts (everything
/// but the counters that move every second while recording, which redraw
/// on their own) and this recording's choices.
typedef _View = ({
  RecordCardFacts card,
  bool auto,
  bool busy,
  String? quality,
  bool? danmaku,
  String defaultQuality,
  String? output,
});

/// The panel's content (see [RoomRecordPanel]).
class RecordPanelBody extends ConsumerStatefulWidget {
  /// Creates the content.
  const new({required this.room, this.qualities, this.now, super.key});

  /// The room as known now.
  final LiveRoom Function() room;

  /// The room's qualities.
  final List<LivePlayQuality> Function()? qualities;

  /// The clock; a fixed one does not tick.
  final DateTime Function()? now;

  @override
  ConsumerState<RecordPanelBody> createState() => _RecordPanelBodyState();
}

class _RecordPanelBodyState extends ConsumerState<RecordPanelBody> {
  final _Changes _changes = _Changes();
  StreamSubscription<List<RecordTask>>? _tasks;
  StreamSubscription<RecordSettings>? _settings;
  Future<String>? _directory;

  /// "这次录制" before there is a task (written onto the task it creates).
  String? _quality;
  bool? _danmaku;
  bool _acting = false;

  AppRecording? get _recording => ref.read(recordingProvider);

  RecordTask? get _task => _recording?.taskFor(widget.room());

  @override
  void initState() {
    super.initState();
    final recording = _recording;
    _tasks = recording?.recorder?.changes.listen((_) => _changes.changed());
    _settings = recording?.settings.changes.listen((_) => _changes.changed());
    _directory = recording?.storage.recordDirectory().then((directory) => directory.path);
  }

  @override
  void dispose() {
    unawaited(_tasks?.cancel());
    unawaited(_settings?.cancel());
    _changes.dispose();
    _output.dispose();
    super.dispose();
  }

  List<LivePlayQuality> get _roomQualities => widget.qualities?.call() ?? const [];

  /// Whether the last recording's file is there (B08, audit B-20: each
  /// build asked the disk synchronously on the UI thread). A build uses the
  /// answer it has and looks again in the background; a different answer
  /// builds the panel again.
  late final SavedFileCheck _output = SavedFileCheck(() {
    if (mounted) setState(() {});
  });

  /// [path] when the file was there when last looked for, else null.
  String? _saved(String? path) => _output.saved(path);

  _View _view() {
    final recording = _recording;
    final settings = recording?.settings.current ?? RecordSettings();
    final task = _task;
    return (
      card: recordCardFacts(
        task,
        settings,
        running: recordSlotsInUse(recording?.recorder?.tasks ?? const []),
        chosen: _quality,
        failure: (task) => recordFailureText(task).summary,
      ),
      auto: autoRecordOn(task),
      busy: recordBusy(task),
      quality: task?.qualityOverride ?? _quality,
      danmaku: task?.recordDanmakuOverride ?? _danmaku,
      defaultQuality: settings.defaultQuality,
      output: task?.lastOutputPath,
    );
  }

  Future<void> _act(Future<void> Function(AppRecording recording, Recorder recorder) action) async {
    final recording = _recording;
    final recorder = recording?.recorder;
    if (recording == null || recorder == null || _acting) return;
    setState(() => _acting = true);
    try {
      await action(recording, recorder);
    } on Object {
      AppNavigator.toast(i18n('live_play_record_failed'));
    } finally {
      if (mounted) setState(() => _acting = false);
      _changes.changed();
    }
  }

  /// "开始录制", "再录一次": a new session now (F3: the panel stays and the
  /// card turns into the clock).
  Future<void> _start() => _act((recording, recorder) async {
    if (!await recording.ensureStorageAccess()) return;
    final room = widget.room();
    final task = recording.taskFor(room);
    recording.keepAlive?.allowUserRetry();
    if (task == null) {
      await recorder.addTask(room, quality: _quality, recordDanmaku: _danmaku, autoRecord: false);
    } else {
      await recordTaskAgain(recording, recorder, task);
    }
  });

  /// "现在就录", "重试".
  Future<void> _startTask() => _act((recording, recorder) async {
    final task = recording.taskFor(widget.room());
    if (task == null || recordBusy(task) || !await recording.ensureStorageAccess()) return;
    await recording.startTask(task);
  });

  /// "停止录制", "取消".
  Future<void> _stop() => _act((recording, recorder) async {
    final task = recording.taskFor(widget.room());
    if (task != null) await recorder.stopTask(task);
  });

  /// "开播自动录" (3.x's 添加/取消监控); turning it off leaves a running
  /// recording alone.
  Future<void> _setAuto(bool on) => _act(
    (recording, recorder) => setAutoRecord(
      recording,
      recorder,
      on: on,
      task: recording.taskFor(widget.room()),
      room: widget.room(),
      quality: _quality,
      danmaku: _danmaku,
    ),
  );

  void _pickQuality(String quality) {
    final task = _task;
    if (task == null) {
      setState(() => _quality = quality);
    } else if (!recordBusy(task)) {
      _recording?.recorder?.setTaskOptions(task, quality: quality);
    }
  }

  void _pickDanmaku(bool on) {
    final task = _task;
    if (task == null) {
      setState(() => _danmaku = on);
    } else if (!recordBusy(task)) {
      _recording?.recorder?.setTaskOptions(task, recordDanmaku: on);
    }
  }

  /// "查看原因" opens the whole failure under the card, selectable (B09 c8:
  /// the centred dialog lay over the picture, which is often in
  /// fullscreen); "收起" or the button again closes it.
  bool _reasonOpen = false;

  void _toggleReason() => setState(() => _reasonOpen = !_reasonOpen);

  @override
  Widget build(BuildContext context) {
    final recording = ref.watch(recordingProvider);
    if (recording == null || !recording.available) {
      return AppStatusView(
        type: AppStatusType.empty,
        isMini: true,
        title: i18n('recorder_unavailable_title'),
        subtitle: i18n('recorder_unavailable_subtitle'),
      );
    }
    return ListenableSelector<_View>(
      listenable: _changes,
      selector: _view,
      builder: (context, view, _) => ListView(
        key: const ValueKey('record-panel-list'),
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: RecordStatusCard(
              facts: view.card,
              changes: _changes,
              task: () => _task,
              chatCount: (task) => recording.chat?.countOf(task) ?? 0,
              now: widget.now,
              acting: _acting,
              onStart: () => unawaited(_start()),
              onStartTask: () => unawaited(_startTask()),
              onStop: () => unawaited(_stop()),
              onLimit: () => unawaited(openRecordLimit()),
              // "播放" with the system's player; hidden while there is no file.
              onPlay: switch (_saved(view.output)) {
                final path? => () => unawaited(playRecording(path)),
                _ => null,
              },
              onCentre: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kRecordPage)),
              onReason: _toggleReason,
            ),
          ),
          if (_task case final task? when _reasonOpen && task.status == RecordStatus.failed)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _FailureReason(text: recordFailureText(task), onClose: _toggleReason),
            ),
          PanelGroupTitle(i18n('record_panel_this_time')),
          _ThisRecording(
            view: view,
            choices: recordQualityChoices(_roomQualities),
            fallback: recordDefaultQuality(_roomQualities, view.defaultQuality),
            onQuality: _pickQuality,
            onDanmaku: _pickDanmaku,
          ),
          PanelGroupTitle(i18n('record_panel_auto')),
          _AutoRecord(
            view: view,
            acting: _acting,
            onChanged: (on) => unawaited(_setAuto(on)),
            onEnablePolling: () => unawaited(_act((recording, _) => enableRecordPolling(recording))),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 16, 0),
            child: Row(
              children: [
                PanelLink(
                  key: const ValueKey('record-panel-settings'),
                  text: i18n('record_settings'),
                  onPressed: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kRecordSettings)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FutureBuilder<String>(
                    future: _directory,
                    builder: (context, snapshot) {
                      final path = snapshot.data;
                      if (path == null) return const SizedBox.shrink();
                      final parts = p.split(path).where((part) => part.isNotEmpty && part != p.separator).toList();
                      final short = parts.length <= 2 ? path : parts.sublist(parts.length - 2).join('/');
                      return Tooltip(
                        message: path,
                        child: Text(
                          i18n('record_panel_save_to', args: {'path': short}),
                          key: const ValueKey('record-panel-folder'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: Theme.of(context).textTheme.bodyMedium?.regular
                              .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "这次录制": the quality and the chat of this recording (R6), read-only
/// while it runs.
class _ThisRecording extends StatelessWidget {
  const new({
    required this.view,
    required this.choices,
    required this.fallback,
    required this.onQuality,
    required this.onDanmaku,
  });

  final _View view;
  final List<String> choices;
  final String fallback;
  final ValueChanged<String> onQuality;
  final ValueChanged<bool> onDanmaku;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = theme.textTheme.bodyLarge?.regular.copyWith(fontSize: 15, color: scheme.onSurface);
    final hint = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final chosen = view.quality ?? fallback;
    final danmaku = view.danmaku ?? view.card.recordDanmaku;
    return PanelCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(child: Text(i18n('record_panel_quality'), style: title)),
              Flexible(
                child: Text(
                  view.busy
                      ? i18n('record_panel_locked', args: {'value': view.card.applied ?? chosen})
                      : i18n('record_panel_quality_hint'),
                  key: const ValueKey('record-panel-quality-hint'),
                  textAlign: TextAlign.end,
                  style: hint,
                ),
              ),
            ],
          ),
        ),
        if (!view.busy)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Wrap(
              key: const ValueKey('record-panel-qualities'),
              spacing: 8,
              runSpacing: 4,
              children: [
                // B09 c9: the app's one chip (U.1c c13: corners of 8, the
                // tick of the chosen one, the keyboard frame).
                for (final quality in choices)
                  AppChip(
                    key: ValueKey('record-quality-$quality'),
                    label: quality,
                    selected: quality == chosen,
                    onSelected: () => onQuality(quality),
                  ),
              ],
            ),
          ),
        MergeSemantics(
          child: InkWell(
            onTap: view.busy ? null : () => onDanmaku(!danmaku),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i18n('record_panel_danmaku'), style: title),
                        Text(
                          view.busy
                              ? '${i18n('record_panel_danmaku_desc')}${i18n('record_panel_locked_suffix')}'
                              : i18n('record_panel_danmaku_desc'),
                          style: hint,
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    key: const ValueKey('record-panel-danmaku'),
                    value: danmaku,
                    onChanged: view.busy ? null : onDanmaku,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "自动录": "开播自动录" (3.x's 添加/取消监控) and the live check it needs
/// (R4).
class _AutoRecord extends StatelessWidget {
  const new({required this.view, required this.acting, required this.onChanged, required this.onEnablePolling});

  final _View view;
  final bool acting;
  final ValueChanged<bool> onChanged;
  final VoidCallback onEnablePolling;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = theme.textTheme.bodyLarge?.regular.copyWith(fontSize: 15, color: scheme.onSurface);
    final hint = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final warning = LiveSemanticColors.warning(scheme.brightness);
    return PanelCard(
      children: [
        MergeSemantics(
          child: InkWell(
            onTap: acting ? null : () => onChanged(!view.auto),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i18n('record_panel_auto_switch'), style: title),
                        Text(i18n('record_panel_auto_desc'), style: hint),
                      ],
                    ),
                  ),
                  Switch(
                    key: const ValueKey('record-panel-auto'),
                    value: view.auto,
                    onChanged: acting ? null : onChanged,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (view.auto && view.card.polling)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              [
                i18n('record_panel_polling_info', args: {'seconds': '${view.card.interval}'}),
                if (view.card.lastCheck case final time?) i18n('record_panel_last_check', args: {'time': time}),
              ].join(' · '),
              key: const ValueKey('record-panel-polling'),
              style: hint?.tabular,
            ),
          ),
        if (view.auto && !view.card.polling)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: DecoratedBox(
              key: const ValueKey('record-panel-polling-off'),
              decoration: BoxDecoration(
                color: Color.alphaBlend(warning.withValues(alpha: 0.1), scheme.surface),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    Icon(AppIcons.warning, size: 18, color: warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        i18n('record_panel_polling_off'),
                        style: theme.textTheme.bodyMedium?.copyWith(color: warning),
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('record-panel-polling-on'),
                      onPressed: acting ? null : onEnablePolling,
                      child: Text(i18n('record_panel_polling_enable')),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
