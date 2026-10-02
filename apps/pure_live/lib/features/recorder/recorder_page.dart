import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_ui/live_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/home/home_menu.dart';
import 'package:pure_live/features/home/menu_button.dart';
import 'package:pure_live/features/recorder/logic/recorder_view.dart';
import 'package:pure_live/features/recorder/recorder_task_card.dart';
import 'package:pure_live/features/recorder/recorder_texts.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/record/record_actions.dart';
import 'package:pure_live/shared/record/record_state.dart';
import 'package:pure_live/shared/record/record_status_card.dart';

/// How the recording folder opens on Android (M8.1); `main` installs the
/// system file manager (android_intent_plus).
abstract final class RecordFolderOpener {
  /// Opens a folder in the system file manager; false when it cannot.
  static Future<bool> Function(String path) android = (_) async => false;
}

/// The system file manager's address of [path] (`content://` of
/// `com.android.externalstorage.documents`, `primary:<relative>`), or null
/// outside the shared storage and inside `Android/data` and `Android/obb`,
/// which Android 11+'s file manager refuses to show.
Uri? androidDocumentFolderUri(String path) {
  final normalized = path.trim().replaceAll(r'\', '/');
  const roots = ['/storage/emulated/0/', '/sdcard/', '/storage/self/primary/'];
  final root = roots.where((root) => '$normalized/'.startsWith(root)).firstOrNull;
  if (root == null) return null;
  final relative = '$normalized/'.substring(root.length).replaceAll(RegExp(r'^/+|/+$'), '');
  if (relative.isEmpty || RegExp(r'^android/(data|obb)(/|$)', caseSensitive: false).hasMatch(relative)) return null;
  return Uri.parse(
    'content://com.android.externalstorage.documents/document/${Uri.encodeComponent('primary:$relative')}',
  );
}

/// Opens the managed recording folder (3.x `openFileDir`), or [path] inside
/// it (a saved recording's folder, U.7a c5): the file manager on the
/// desktop and, for a folder in the shared storage, on Android; for the
/// app's own folder (Android 11+'s file manager cannot enter it) or without
/// a file manager the path is copied and the toast says why.
Future<void> openRecordFolder(AppRecording recording, {String? path}) async {
  try {
    final folder = path ?? (await recording.storage.recordDirectory()).path;
    if (Platform.isAndroid) {
      if (await RecordFolderOpener.android(folder)) return;
      await Clipboard.setData(ClipboardData(text: folder));
      final private = androidDocumentFolderUri(folder) == null;
      AppNavigator.toast(
        i18n(private ? 'recorder_folder_private_copied' : 'recorder_folder_copied', args: {'path': folder}),
      );
      return;
    }
    if (!await AppNavigator.openExternal(Uri.directory(folder))) {
      AppNavigator.toast(i18n('recorder_folder_open_failed'));
    }
  } on Object {
    AppNavigator.toast(i18n('path_or_permission_error'));
  }
}

/// The folder of [task]'s recordings: where its last MP4 went, else its
/// last attempt's folder; null when it has none (the recording folder).
String? recordTaskFolder(RecordTask task) {
  final output = task.lastOutputPath?.trim() ?? '';
  if (output.isNotEmpty) return p.dirname(output);
  final attempt = task.outputDir?.trim() ?? '';
  return attempt.isEmpty ? null : attempt;
}

/// Recording centre (3.x `lib/recorder/pages/recorder`; docs/T08/T08b/T08b.2,
/// confirmed): five filters with counts, then each task's card, whose
/// status block is the live room's record panel status card (U.2f) in its
/// compact size. One column on a phone in portrait; as many columns of at
/// least 400 as the page's width holds otherwise.
///
/// Routes: `RoutePath.kRecordPage`; also the home's "record" tab (the menu
/// at the top left instead of back). The arguments may be a task id
/// (`RecordTask.taskId`): the list scrolls to that task and highlights it
/// for a moment ("录制已停止" reminder, F02 c2; [recorderTaskOf]).
class RecorderPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, this.now, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  /// The clock; a fixed one (tests) does not tick.
  final DateTime Function()? now;

  @override
  ConsumerState<RecorderPage> createState() => _RecorderPageState();
}

/// The task the recording centre opens at: [arguments] when it is a task id,
/// else null.
String? recorderTaskOf(Object? arguments) => switch (arguments) {
  final String id when id.trim().isNotEmpty => id.trim(),
  _ => null,
};

/// Announces the recorder's and the settings' changes to the page's parts.
final class _Changes extends ChangeNotifier {
  void changed() => notifyListeners();
}

class _RecorderPageState extends ConsumerState<RecorderPage> {
  final _Changes _changes = _Changes();
  final _restrictions = <String, LiveRestriction>{};
  StreamSubscription<List<RecordTask>>? _tasks;
  StreamSubscription<RecordSettings>? _settings;
  StreamSubscription<RecordNotice>? _notices;
  RecorderFilter _filter = RecorderFilter.all;
  final ScrollController _scroll = ScrollController();

  /// The task the page was opened at (F02 c2), its card's key, whether it
  /// was found yet, and the highlight's run (0 before it shows).
  late final String? _target = recorderTaskOf(widget.route.arguments);
  final GlobalKey _targetKey = GlobalKey(debugLabel: 'recorder-target');
  bool _found = false;
  int _highlight = 0;

  AppRecording? get _recording => ref.read(recordingProvider);

  @override
  void initState() {
    super.initState();
    final recording = _recording;
    final recorder = recording?.recorder;
    if (recording == null || recorder == null) return;
    _tasks = recorder.changes.listen((_) {
      _changes.changed();
      // A task that was not in the list yet (the recorder still restoring).
      if (_target != null && !_found) WidgetsBinding.instance.addPostFrameCallback((_) => _seek());
    });
    _settings = recording.settings.changes.listen((_) => _changes.changed());
    _notices = recorder.notices.listen(_onNotice);
    if (_target != null) WidgetsBinding.instance.addPostFrameCallback((_) => _seek());
  }

  @override
  void dispose() {
    unawaited(_tasks?.cancel());
    unawaited(_settings?.cancel());
    unawaited(_notices?.cancel());
    _changes.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Brings the target task into view once it is in the list, then
  /// highlights it.
  void _seek() {
    final id = _target;
    if (id == null || _found || !mounted) return;
    if (!recorderVisible(_taskList, _states(), _filter).any((task) => task.taskId == id)) return;
    _found = true;
    _reveal(0);
  }

  /// The cards are built as they scroll in: until the target's is built,
  /// go down a screen at a time.
  void _reveal(int step) {
    if (!mounted) return;
    final card = _targetKey.currentContext;
    if (card != null) {
      final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      unawaited(
        Scrollable.ensureVisible(
          card,
          alignment: 0.2,
          duration: still ? Duration.zero : const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        ).then((_) {
          if (mounted) setState(() => _highlight++);
        }),
      );
      return;
    }
    if (step >= 100 || !_scroll.hasClients) return;
    final position = _scroll.positions.last;
    if (position.pixels >= position.maxScrollExtent) return;
    _scroll.jumpTo(math.min(position.pixels + position.viewportDimension, position.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(step + 1));
  }

  void _onNotice(RecordNotice notice) {
    final restriction = notice.streamError?.restriction;
    if (restriction != null) _restrictions[notice.task.taskId] = restriction;
    _changes.changed();
    // The live room shows its own notices; the centre speaks while open.
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final text = recordNoticeText(notice);
    if (text != null && text.isNotEmpty) AppNavigator.toast(text);
  }

  List<RecordTask> get _taskList => _recording?.recorder?.tasks ?? const [];

  RecordSettings get _settingsNow => _recording?.settings.current ?? RecordSettings();

  Map<String, RecordCardState> _states() => recorderStates(_taskList, capacity: _settingsNow.maxTaskCount);

  RecordTask? _taskOf(String id) => _taskList.where((task) => task.taskId == id).firstOrNull;

  ({String summary, String? detail}) _failure(RecordTask task) =>
      recordFailureText(task, restriction: _restrictions[task.taskId]);

  RecordCardFacts _facts(RecordTask task) => recordCardFacts(
    task,
    _settingsNow,
    running: recordSlotsInUse(_taskList),
    failure: (task) => _failure(task).summary,
  );

  /// A start that failed says why (3.x's toast).
  void _sayFailure(RecordTask task, {required bool started}) {
    if (!started && task.status == RecordStatus.failed && mounted) AppNavigator.toast(_failure(task).summary);
  }

  RecorderCardActions _actions(AppRecording recording, Recorder recorder) => RecorderCardActions(
    open: (task) => unawaited(
      AppNavigator.toLiveRoomDetail(
        liveRoom: LiveRoom(
          roomId: task.roomId,
          platform: task.platform,
          title: task.title,
          nick: task.nick,
          avatar: task.avatar,
          cover: task.cover,
          watching: task.watching,
          followers: task.followers,
          audienceMetricType: task.audienceMetricType,
          liveStatus: task.liveStatus,
        ),
      ),
    ),
    again: (task) async {
      if (recordBusy(task) || !await recording.ensureStorageAccess()) return;
      recording.keepAlive?.allowUserRetry();
      await recordTaskAgain(recording, recorder, task);
      _sayFailure(task, started: task.status != RecordStatus.failed);
    },
    startNow: (task) async {
      if (recordBusy(task) || !await recording.ensureStorageAccess()) return;
      _sayFailure(task, started: await recording.startTask(task));
    },
    stop: recorder.stopTask,
    remove: (task) async {
      await recorder.removeTask(task);
      _restrictions.remove(task.taskId);
    },
    setAuto: (task, {required on}) => setAutoRecord(recording, recorder, on: on, task: task),
    limit: () => unawaited(openRecordLimit()),
    folder: (task) => unawaited(openRecordFolder(recording, path: recordTaskFolder(task))),
    reason: (context, task) => unawaited(showRecordFailureReason(context, _failure(task))),
    failed: () => AppNavigator.toast(i18n('live_play_record_failed')),
  );

  @override
  Widget build(BuildContext context) {
    final recording = ref.watch(recordingProvider);
    final recorder = recording?.recorder;
    final phoneTab = showsHomeBarButtons(context, inHome: widget.route.inHome);
    return Scaffold(
      appBar: AppBar(
        centerTitle: centredPageTitle,
        // The home's tab has the menu (3.x); opened from the rail or a room,
        // back. This follows the home's layout, not the screen's width (U.7a
        // P11, U.3a).
        automaticallyImplyLeading: !widget.route.inHome,
        leading: phoneTab ? const MenuButton() : null,
        title: Text(i18n('recorder_title')),
        actions: [
          if (recording != null)
            IconButton(
              key: const ValueKey('recorder-open-folder'),
              tooltip: i18n('recorder_open_folder'),
              icon: const Icon(AppIcons.recordFolder, size: 22),
              onPressed: () => unawaited(openRecordFolder(recording)),
            ),
          IconButton(
            key: const ValueKey('recorder-settings'),
            tooltip: i18n('record_settings'),
            icon: const Icon(AppIcons.recordSettings, size: 22),
            onPressed: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kRecordSettings)),
          ),
          // As a phone tab, search and "more" as on every home tab (U.3a c6).
          if (phoneTab) const CommonAppBarActions() else const SizedBox(width: 8),
        ],
      ),
      body: recording == null || recorder == null
          ? AppStatusView(
              type: AppStatusType.empty,
              icon: AppIcons.recordUnavailable,
              title: i18n('recorder_unavailable_title'),
              subtitle: i18n('recorder_unavailable_subtitle'),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                // Wide: a tablet, a desktop window (not a phone on its side,
                // whose height is compact). Only the page's own size counts.
                final wide = constraints.maxWidth >= 840 && constraints.maxHeight >= 480;
                final gutter = wide ? 24.0 : 16.0;
                return Column(
                  children: [
                    _FilterBar(
                      changes: _changes,
                      counts: () => recorderCounts(_states()),
                      selected: _filter,
                      wide: wide,
                      onSelected: (filter) => setState(() => _filter = filter),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _TaskGrid(
                        key: ValueKey(_filter),
                        changes: _changes,
                        filter: _filter,
                        visible: () => recorderVisible(_taskList, _states(), _filter),
                        hasTasks: () => _taskList.isNotEmpty,
                        pollingOff: () => !_settingsNow.enablePolling,
                        columns: recorderColumns(constraints.maxWidth - 2 * gutter),
                        gutter: gutter,
                        wide: wide,
                        controller: _scroll,
                        onEnablePolling: () => unawaited(enableRecordPolling(recording)),
                        card: (task) {
                          final card = RecorderTaskCard(
                            key: ValueKey(task.taskId),
                            taskId: task.taskId,
                            task: () => _taskOf(task.taskId),
                            facts: _facts,
                            changes: _changes,
                            chatCount: (task) => recording.chat?.countOf(task) ?? 0,
                            actions: _actions(recording, recorder),
                            wide: wide,
                            now: widget.now,
                          );
                          return task.taskId == _target
                              ? RecorderTaskHighlight(key: _targetKey, run: _highlight, child: card)
                              : card;
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

/// The five filters in one row (U.7a c6; 3.x `RecorderStatusSelector`'s
/// look: equal cells, the chosen one in the primary container), each with
/// its count. Only this row rebuilds when a count changes.
class _FilterBar extends StatelessWidget {
  const new({
    required this.changes,
    required this.counts,
    required this.selected,
    required this.wide,
    required this.onSelected,
  });

  final Listenable changes;
  final RecorderCounts Function() counts;
  final RecorderFilter selected;
  final bool wide;
  final ValueChanged<RecorderFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final row = ListenableSelector<RecorderCounts>(
      listenable: changes,
      selector: counts,
      builder: (context, counts, _) => Row(
        children: [
          for (final filter in RecorderFilter.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: _FilterChip(
                  filter: filter,
                  count: recorderCountOf(counts, filter),
                  selected: filter == selected,
                  onTap: () => onSelected(filter),
                ),
              ),
            ),
        ],
      ),
    );
    return ColoredBox(
      color: scheme.surface,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: wide ? 21 : 10, vertical: 6),
          // On a wide page the five stay as wide as on a large phone.
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wide ? 660 - 42 : double.infinity),
            child: row,
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const new({required this.filter, required this.count, required this.selected, required this.onTap});

  final RecorderFilter filter;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    final label = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: foreground,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
    );
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest.withValues(alpha: 0.46),
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          key: ValueKey('recorder-filter-${filter.name}'),
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: SizedBox(
            height: kMinInteractiveDimension,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: recorderFilterLabel(filter)),
                        TextSpan(
                          text: ' $count',
                          style: theme.textTheme.bodySmall?.tabular.copyWith(
                            color: foreground.withValues(alpha: 0.8),
                            fontWeight: label.fontWeight,
                          ),
                        ),
                      ],
                    ),
                    key: ValueKey('recorder-filter-${filter.name}-label'),
                    maxLines: 1,
                    style: label,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The cards of one filter: a column on a phone, rows of [columns] cards
/// otherwise, built as they scroll in; the live check's warning on top when
/// a waiting task will not start by itself (U.7a c8); the two empty states
/// (c7). The list rebuilds only when its tasks or their order change.
class _TaskGrid extends StatelessWidget {
  const new({
    required this.changes,
    required this.filter,
    required this.visible,
    required this.hasTasks,
    required this.pollingOff,
    required this.columns,
    required this.gutter,
    required this.wide,
    required this.controller,
    required this.onEnablePolling,
    required this.card,
    super.key,
  });

  final Listenable changes;
  final ScrollController controller;
  final RecorderFilter filter;
  final List<RecordTask> Function() visible;

  /// Whether there is any task at all (an empty filter says which).
  final bool Function() hasTasks;
  final bool Function() pollingOff;
  final int columns;
  final double gutter;
  final bool wide;
  final VoidCallback onEnablePolling;
  final Widget Function(RecordTask task) card;

  @override
  Widget build(BuildContext context) => ListenableSelector<(String, bool, bool)>(
    listenable: changes,
    selector: () {
      final tasks = visible();
      final waiting = tasks.any((task) => task.status == RecordStatus.waitingLive);
      return (tasks.map((task) => task.taskId).join('\n'), waiting && pollingOff(), hasTasks());
    },
    builder: (context, view, _) {
      final tasks = visible();
      if (tasks.isEmpty) {
        final none = !view.$3;
        return AppStatusView(
          key: ValueKey(none ? 'recorder-empty' : 'recorder-empty-filter'),
          type: AppStatusType.empty,
          icon: AppIcons.recordEmpty,
          iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
          title: none
              ? i18n('recorder_empty_title')
              : i18n('recorder_empty_status', args: {'status': recorderFilterLabel(filter)}),
          subtitle: none ? i18n('recorder_empty_hint') : '',
        );
      }
      final banner = view.$2;
      final rows = (tasks.length + columns - 1) ~/ columns;
      return ListView.builder(
        key: const ValueKey('recorder-list'),
        controller: controller,
        physics: const PureLiveBoundedScrollPhysics(),
        padding: EdgeInsets.fromLTRB(gutter, wide ? 16 : 12, gutter, 24),
        itemCount: rows + (banner ? 1 : 0),
        itemBuilder: (context, index) {
          if (banner && index == 0) return _PollingOffBanner(onEnable: onEnablePolling);
          final row = index - (banner ? 1 : 0);
          final start = row * columns;
          final cells = [
            for (var column = 0; column < columns; column++)
              if (start + column < tasks.length) card(tasks[start + column]) else null,
          ];
          return Padding(
            padding: EdgeInsets.only(bottom: row == rows - 1 ? 0 : recorderCardGap),
            child: columns == 1
                ? cells.single
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (column, cell) in cells.indexed) ...[
                        if (column > 0) const SizedBox(width: recorderCardGap),
                        Expanded(child: cell ?? const SizedBox.shrink()),
                      ],
                    ],
                  ),
          );
        },
      );
    },
  );
}

/// "“开播检测”关着，等待开播的任务到时不会自动开始。" with "打开" (U.7a c8,
/// the record panel's words and action): the reminder colour of the
/// page-top bar (U.1c c8).
class _PollingOffBanner extends StatelessWidget {
  const new({required this.onEnable});

  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: StatusBanner(
      key: const ValueKey('recorder-polling-off'),
      kind: StatusBannerKind.warning,
      text: i18n('recorder_polling_off'),
      margin: EdgeInsets.zero,
      actions: [
        (key: const ValueKey('recorder-polling-on'), label: i18n('record_panel_polling_enable'), onPressed: onEnable),
      ],
    ),
  );
}

/// The card the page was opened at (F02 c2): once it is in view ([run] 1
/// and on), a primary-coloured frame and tint that hold for a moment, then
/// fade.
class RecorderTaskHighlight extends StatelessWidget {
  /// Creates the highlight around [child].
  const new({required this.run, required this.child, super.key});

  /// How many times it has shown; 0 before the card is in view.
  final int run;

  /// The card.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (run == 0) return child;
    final primary = Theme.of(context).colorScheme.primary;
    return TweenAnimationBuilder<double>(
      key: ValueKey(run),
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 2400),
      curve: const Interval(0.5, 1, curve: Curves.easeIn),
      child: child,
      builder: (context, strength, child) => DecoratedBox(
        key: const ValueKey('recorder-task-highlight'),
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.12 * strength),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: primary.withValues(alpha: strength), width: 2),
        ),
        child: child,
      ),
    );
  }
}
