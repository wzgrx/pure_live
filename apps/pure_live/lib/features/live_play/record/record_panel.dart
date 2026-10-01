import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/logic/record_state.dart';
import 'package:pure_live/features/recorder/recorder_texts.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.75,
        child: RoomRecordPanel(room: room, onClose: () => Navigator.of(sheetContext).pop()),
      ),
    ),
  );
}

/// The record panel (docs/ui/compare/U.2f, 录制, confirmed): "录制" with
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

/// Announces the recorder's and the settings' changes to the panel's parts.
final class _Changes extends ChangeNotifier {
  void changed() => notifyListeners();
}

/// What the panel's layout depends on: everything but the counters that
/// move every second while recording (those redraw on their own).
typedef _View = ({
  RecordCardState state,
  bool auto,
  bool busy,
  String? quality,
  bool? danmaku,
  bool polling,
  int interval,
  int maxTasks,
  int running,
  int segmentTime,
  String defaultQuality,
  bool recordDanmaku,
  String? lastCheck,
  int retry,
  int maxRetry,
  String? stage,
  String? error,
  String? output,
  String? applied,
  int seconds,
  int bytes,
  DateTime? started,
  DateTime? retryAt,
  DateTime? finished,
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
    super.dispose();
  }

  List<LivePlayQuality> get _roomQualities => widget.qualities?.call() ?? const [];

  _View _view() {
    final recording = _recording;
    final settings = recording?.settings.current ?? RecordSettings();
    final recorder = recording?.recorder;
    final task = _task;
    final running = recordSlotsInUse(recorder?.tasks ?? const []);
    final state = recordCardState(task, running: running, capacity: settings.maxTaskCount);
    final moving = state == RecordCardState.recording;
    final check = task?.lastLiveCheckAt;
    return (
      state: state,
      auto: autoRecordOn(task),
      busy: recordBusy(task),
      quality: task?.qualityOverride ?? _quality,
      danmaku: task?.recordDanmakuOverride ?? _danmaku,
      polling: settings.enablePolling,
      interval: settings.liveCheckInterval,
      maxTasks: settings.maxTaskCount,
      running: running,
      segmentTime: settings.segmentTime,
      defaultQuality: settings.defaultQuality,
      recordDanmaku: settings.recordDanmaku,
      lastCheck: check == null ? null : _hourMinute(check),
      retry: task?.retryCount ?? 0,
      maxRetry: settings.maxRetryCount,
      stage: task?.lastErrorStage,
      error: task?.lastError,
      output: task?.lastOutputPath,
      applied: task?.selectedQuality,
      // The counters of a running task redraw in their own small parts.
      seconds: moving ? 0 : task?.recordedSeconds ?? 0,
      bytes: moving ? 0 : task?.fileSize ?? 0,
      started: task?.displayStartTime,
      retryAt: task?.nextRetryAt,
      finished: task?.lastUpdate,
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
    } else if (!recordBusy(task)) {
      if (!autoRecordOn(task)) recorder.setTaskOptions(task, autoRecord: false);
      await recording.startTask(task);
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

  /// Turns the live check on when it is off (F2: "开播自动录" needs it).
  Future<void> _enablePolling(AppRecording recording) async {
    final current = recording.settings.current;
    if (current.enablePolling) return;
    await recording.settings.set(Settings.recordEnablePolling, true);
    AppNavigator.toast(i18n('record_panel_polling_enabled', args: {'seconds': '${current.liveCheckInterval}'}));
  }

  /// "开播自动录" (3.x's 添加/取消监控); turning it off leaves a running
  /// recording alone.
  Future<void> _setAuto(bool on) => _act((recording, recorder) async {
    final room = widget.room();
    final task = recording.taskFor(room);
    if (on) {
      await _enablePolling(recording);
      if (task == null) {
        recording.keepAlive?.allowUserRetry();
        await recorder.addTask(
          room,
          startImmediately: false,
          quality: _quality,
          recordDanmaku: _danmaku,
          autoRecord: true,
        );
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
  });

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

  Future<void> _play(String path) async {
    if (!await AppNavigator.openFile(path)) AppNavigator.toast(i18n('record_panel_play_failed'));
  }

  Future<void> _showReason() async {
    final task = _task;
    if (task == null) return;
    final text = recordFailureText(task);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(i18n('record_panel_reason_title')),
        content: SelectableText([text.summary, ?text.detail].join('\n\n')),
        actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(i18n('close')))],
      ),
    );
  }

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
            child: _StatusCard(
              view: view,
              changes: _changes,
              task: () => _task,
              chatCount: (task) => recording.chat?.countOf(task) ?? 0,
              now: widget.now,
              acting: _acting,
              onStart: () => unawaited(_start()),
              onStartTask: () => unawaited(_startTask()),
              onStop: () => unawaited(_stop()),
              onLimit: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kRecordSettings)),
              // "播放" with the system's player; hidden while there is no file.
              onPlay: switch (view.output) {
                final path? when File(path).existsSync() => () => unawaited(_play(path)),
                _ => null,
              },
              onCentre: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kRecordPage)),
              onReason: () => unawaited(_showReason()),
            ),
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
            onEnablePolling: () => unawaited(_act((recording, _) => _enablePolling(recording))),
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

String _two(int value) => value.toString().padLeft(2, '0');

String _hourMinute(DateTime time) {
  final local = time.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}';
}

/// "今天 21:30", "昨天 21:30", else "10-01 21:30".
String _dayTime(DateTime time, DateTime now) {
  final local = time.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final clock = _hourMinute(local);
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

/// The status card: what the task is doing and the one or two things that
/// can be done now (R2, R5).
class _StatusCard extends StatelessWidget {
  const new({
    required this.view,
    required this.changes,
    required this.task,
    required this.chatCount,
    required this.acting,
    required this.onStart,
    required this.onStartTask,
    required this.onStop,
    required this.onLimit,
    required this.onPlay,
    required this.onCentre,
    required this.onReason,
    this.now,
  });

  final _View view;
  final Listenable changes;
  final RecordTask? Function() task;
  final int Function(RecordTask task) chatCount;
  final DateTime Function()? now;
  final bool acting;
  final VoidCallback onStart;
  final VoidCallback onStartTask;
  final VoidCallback onStop;
  final VoidCallback onLimit;
  final VoidCallback? onPlay;
  final VoidCallback onCentre;
  final VoidCallback onReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = _toneOf(view.state);
    final accent = _accent(tone, scheme);
    final neutral = tone == _Tone.neutral;
    final body = theme.textTheme.bodyMedium?.regular.copyWith(color: scheme.onSurfaceVariant);
    VoidCallback? live(VoidCallback action) => acting ? null : action;
    final quality = view.applied ?? view.quality ?? view.defaultQuality;
    final (icon, title, meta, children) = switch (view.state) {
      RecordCardState.idle => (
        const RecordGlyph(state: RecordGlyphState.idle, size: 20),
        i18n('record_panel_idle_title'),
        null,
        <Widget>[
          Text(i18n('record_panel_idle_desc'), style: body),
          _RecordButton(
            key: const ValueKey('record-panel-start'),
            text: i18n('record_panel_start'),
            onPressed: live(onStart),
          ),
        ],
      ),
      RecordCardState.waiting => (
        Icon(AppIcons.autoRecord, size: 20, color: scheme.primary),
        i18n('record_panel_waiting_title'),
        null,
        <Widget>[
          Text(i18n('record_panel_waiting_desc'), style: body),
          _RecordButton(
            key: const ValueKey('record-panel-start-now'),
            text: i18n('record_panel_start_now'),
            onPressed: live(onStartTask),
          ),
        ],
      ),
      RecordCardState.preparing => (
        const _Spinner(),
        i18n('record_panel_preparing_title'),
        null,
        <Widget>[
          Text(i18n('record_panel_preparing_desc', args: {'quality': quality}), style: body),
          _PlainButton(key: const ValueKey('record-panel-cancel'), text: i18n('cancel'), onPressed: live(onStop)),
        ],
      ),
      RecordCardState.queued => (
        Icon(AppIcons.recordQueued, size: 20, color: accent),
        i18n('record_panel_queued_title'),
        null,
        <Widget>[
          Text(
            i18n('record_panel_queued_desc', args: {'max': '${view.maxTasks}', 'running': '${view.running}'}),
            style: body,
          ),
          Row(
            children: [
              Expanded(
                child: _PlainButton(
                  key: const ValueKey('record-panel-cancel'),
                  text: i18n('cancel'),
                  onPressed: live(onStop),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PlainButton(
                  key: const ValueKey('record-panel-limit'),
                  text: i18n('record_panel_raise_limit'),
                  onPressed: onLimit,
                ),
              ),
            ],
          ),
        ],
      ),
      RecordCardState.recording => (
        const _Dot(),
        i18n('recording'),
        ListenableSelector<int>(
          listenable: changes,
          selector: () => recordSegmentNumber(task()?.recordedSeconds ?? 0, view.segmentTime),
          builder: (context, segment, _) => Text(
            i18n('record_panel_segment', args: {'index': '$segment', 'minutes': '${(view.segmentTime / 60).round()}'}),
            key: const ValueKey('record-panel-segment'),
            style: theme.textTheme.bodySmall?.tabular.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        <Widget>[
          if (view.started case final started?)
            _Ticking(
              now: now,
              builder: (context, current) => Text(
                recordClockText(current.difference(started)),
                key: const ValueKey('record-panel-clock'),
                style: theme.textTheme.displaySmall?.emphasis.tabular.copyWith(color: scheme.onSurface),
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
                current?.recordsChat(fallback: view.recordDanmaku) ?? false,
              );
            },
            builder: (context, _, _) {
              final current = task();
              return Wrap(
                key: const ValueKey('record-panel-figures'),
                spacing: 8,
                runSpacing: 6,
                children: [
                  _Chip(i18n('record_panel_recorded_size', args: {'size': recordShortSize(current?.fileSize ?? 0)})),
                  _Chip(recordBitrateText(current?.bitrate ?? 0)),
                  _Chip(current?.selectedQuality ?? quality),
                  if (current != null && current.recordsChat(fallback: view.recordDanmaku))
                    _Chip(i18n('record_panel_danmaku_count', args: {'count': groupedNumber(chatCount(current))})),
                ],
              );
            },
          ),
          _StopButton(key: const ValueKey('record-panel-stop'), text: i18n('stop_record'), onPressed: live(onStop)),
        ],
      ),
      RecordCardState.reconnecting => (
        Icon(AppIcons.recordReconnecting, size: 20, color: accent),
        i18n('record_panel_reconnecting_title'),
        Text(
          i18n('record_panel_reconnect_attempt', args: {'count': '${view.retry}', 'max': '${view.maxRetry}'}),
          style: theme.textTheme.bodySmall?.tabular.copyWith(color: scheme.onSurfaceVariant),
        ),
        <Widget>[
          _Ticking(
            now: now,
            builder: (context, current) {
              final left = view.retryAt?.difference(current).inSeconds ?? 0;
              return Text(
                i18n(
                  'record_panel_reconnect_desc',
                  args: {
                    'seconds': '${left < 0 ? 0 : left}',
                    'duration': recordClockText(Duration(seconds: view.seconds)),
                    'size': recordShortSize(view.bytes),
                  },
                ),
                style: body?.tabular,
              );
            },
          ),
          _StopButton(key: const ValueKey('record-panel-stop'), text: i18n('stop_record'), onPressed: live(onStop)),
        ],
      ),
      RecordCardState.processing => (
        const _Spinner(),
        i18n('record_panel_processing_title'),
        null,
        <Widget>[
          Text(
            i18n(
              'record_panel_processing_desc',
              args: {'count': '${recordSegmentCount(view.seconds, view.segmentTime)}'},
            ),
            style: body,
          ),
        ],
      ),
      RecordCardState.saved => (
        Icon(AppIcons.recordSaved, size: 20, color: accent),
        i18n('record_panel_saved_title'),
        view.finished == null
            ? null
            : Text(
                _dayTime(view.finished!, (now ?? DateTime.now)()),
                style: theme.textTheme.bodySmall?.tabular.copyWith(color: scheme.onSurfaceVariant),
              ),
        <Widget>[
          Text(
            [
              i18n('record_panel_saved_desc', args: {'duration': recordClockText(Duration(seconds: view.seconds))}),
              recordShortSize(view.bytes),
              ?view.applied,
              if (task() case final saved? when saved.recordsChat(fallback: view.recordDanmaku))
                i18n('record_panel_danmaku_count', args: {'count': groupedNumber(chatCount(saved))}),
            ].join(' · '),
            key: const ValueKey('record-panel-saved'),
            style: body?.tabular,
          ),
          Row(
            children: [
              if (onPlay != null) ...[
                Expanded(
                  child: _PlainButton(
                    key: const ValueKey('record-panel-play'),
                    text: i18n('record_panel_play'),
                    onPressed: onPlay,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: _PlainButton(
                  key: const ValueKey('record-panel-view'),
                  text: i18n('record_panel_open_centre'),
                  onPressed: onCentre,
                ),
              ),
            ],
          ),
          _RecordButton(
            key: const ValueKey('record-panel-again'),
            text: i18n('record_panel_again'),
            onPressed: live(onStart),
          ),
        ],
      ),
      RecordCardState.failed => (
        Icon(AppIcons.recordFailed, size: 20, color: accent),
        i18n('record_panel_failed_title'),
        null,
        <Widget>[
          Text(
            [
              if (task() case final failed?) recordFailureText(failed).summary,
              if (view.retry > 0) i18n('record_panel_failed_retries', args: {'count': '${view.retry}'}),
            ].join(),
            style: body,
          ),
          Row(
            children: [
              Expanded(
                child: _PlainButton(
                  key: const ValueKey('record-panel-reason'),
                  text: i18n('record_panel_reason'),
                  onPressed: onReason,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RecordButton(
                  key: const ValueKey('record-panel-retry'),
                  text: i18n('retry'),
                  dot: false,
                  onPressed: live(onStartTask),
                ),
              ),
            ],
          ),
        ],
      ),
    };
    return DecoratedBox(
      key: ValueKey('record-card-${view.state.name}'),
      decoration: BoxDecoration(
        color: neutral ? scheme.surfaceContainerHigh : Color.alphaBlend(accent.withValues(alpha: 0.08), scheme.surface),
        border: neutral ? null : Border.all(color: accent.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
            for (final child in children) ...[const SizedBox(height: 10), child],
          ],
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 16,
    child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary),
  );
}

/// The red dot of a running recording ("● 录制中").
class _Dot extends StatelessWidget {
  const new({this.size = 10, this.color = LiveSemanticColors.recording});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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
const _buttonSize = Size.fromHeight(kMinInteractiveDimension);

/// A red action that starts a recording ("● 开始录制").
class _RecordButton extends StatelessWidget {
  const new({required this.text, required this.onPressed, this.dot = true, super.key});

  final String text;
  final VoidCallback? onPressed;
  final bool dot;

  @override
  Widget build(BuildContext context) => FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: LiveSemanticColors.recording,
      foregroundColor: LiveSemanticColors.onRecording,
      minimumSize: _buttonSize,
      shape: _buttonShape,
    ),
    onPressed: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) ...[const _Dot(size: 8, color: LiveSemanticColors.onRecording), const SizedBox(width: 8)],
        Text(text),
      ],
    ),
  );
}

/// "■ 停止录制": red outline.
class _StopButton extends StatelessWidget {
  const new({required this.text, required this.onPressed, super.key});

  final String text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      foregroundColor: LiveSemanticColors.recording,
      backgroundColor: Theme.of(context).colorScheme.surface,
      side: const BorderSide(color: LiveSemanticColors.recording),
      minimumSize: _buttonSize,
      shape: _buttonShape,
    ),
    onPressed: onPressed,
    icon: const Icon(AppIcons.stopRecording, size: 18),
    label: Text(text),
  );
}

class _PlainButton extends StatelessWidget {
  const new({required this.text, required this.onPressed, super.key});

  final String text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      backgroundColor: Theme.of(context).colorScheme.surface,
      minimumSize: _buttonSize,
      shape: _buttonShape,
    ),
    onPressed: onPressed,
    child: Text(text, textAlign: TextAlign.center),
  );
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
    final danmaku = view.danmaku ?? view.recordDanmaku;
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
                      ? i18n('record_panel_locked', args: {'value': view.applied ?? chosen})
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
                for (final quality in choices)
                  ChoiceChip(
                    key: ValueKey('record-quality-$quality'),
                    label: Text(quality),
                    selected: quality == chosen,
                    // Five qualities fit on one line of a phone.
                    visualDensity: VisualDensity.compact,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                    onSelected: (_) => onQuality(quality),
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
        if (view.auto && view.polling)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              [
                i18n('record_panel_polling_info', args: {'seconds': '${view.interval}'}),
                if (view.lastCheck case final time?) i18n('record_panel_last_check', args: {'time': time}),
              ].join(' · '),
              key: const ValueKey('record-panel-polling'),
              style: hint?.tabular,
            ),
          ),
        if (view.auto && !view.polling)
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
