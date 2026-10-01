import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/home/home_menu.dart';
import 'package:pure_live/home/menu_button.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/recorder/recorder_task_card.dart';
import 'package:pure_live/pages/recorder/recorder_texts.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

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

/// Opens the managed recording folder (3.x `openFileDir`): the file manager
/// on the desktop and, for a folder in the shared storage, on Android; for
/// the app's own folder (Android 11+'s file manager cannot enter it) or
/// without a file manager the path is copied and the toast says why.
Future<void> openRecordFolder(AppRecording recording) async {
  try {
    final directory = await recording.storage.recordDirectory();
    if (Platform.isAndroid) {
      if (await RecordFolderOpener.android(directory.path)) return;
      await Clipboard.setData(ClipboardData(text: directory.path));
      final private = androidDocumentFolderUri(directory.path) == null;
      AppNavigator.toast(
        i18n(private ? 'recorder_folder_private_copied' : 'recorder_folder_copied', args: {'path': directory.path}),
      );
      return;
    }
    if (!await AppNavigator.openExternal(Uri.directory(directory.path))) {
      AppNavigator.toast(i18n('recorder_folder_open_failed'));
    }
  } on Object {
    AppNavigator.toast(i18n('path_or_permission_error'));
  }
}

/// Recording centre (3.x `lib/recorder/pages/recorder`): the tasks by
/// status with their progress and actions, the folder and the settings.
///
/// Routes: `RoutePath.kRecordPage`; also the home's "record" tab.
class RecorderPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  ConsumerState<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends ConsumerState<RecorderPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: recorderFilters.length, vsync: this);
  final _restrictions = <String, LiveRestriction>{};
  StreamSubscription<List<RecordTask>>? _changes;
  StreamSubscription<RecordNotice>? _notices;
  List<RecordTask> _tasks = const [];

  @override
  void initState() {
    super.initState();
    final recorder = ref.read(recorderProvider);
    if (recorder == null) return;
    _tasks = recorder.tasks;
    _changes = recorder.changes.listen((tasks) {
      if (mounted) setState(() => _tasks = tasks);
    });
    _notices = recorder.notices.listen(_onNotice);
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    unawaited(_notices?.cancel());
    _tabs.dispose();
    super.dispose();
  }

  void _onNotice(RecordNotice notice) {
    final restriction = notice.streamError?.restriction;
    if (restriction != null) _restrictions[notice.task.taskId] = restriction;
    // The live room shows its own notices; the centre speaks while open.
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final text = recordNoticeText(notice);
    if (text != null && text.isNotEmpty) AppNavigator.toast(text);
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
    start: (task) async {
      final started = await recording.startTask(task);
      if (!started && task.status == RecordStatus.failed && mounted) {
        final failure = recordFailureText(task, restriction: _restrictions[task.taskId]);
        AppNavigator.toast(failure.summary);
      }
    },
    check: recorder.refreshTaskStatus,
    stop: recorder.stopTask,
    remove: (task) async {
      await recorder.removeTask(task);
      _restrictions.remove(task.taskId);
    },
  );

  @override
  Widget build(BuildContext context) {
    final recording = ref.watch(recordingProvider);
    final recorder = recording?.recorder;
    final phoneTab = widget.route.inHome && MediaQuery.sizeOf(context).width <= homeTabletBreakpoint;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        automaticallyImplyLeading: !widget.route.inHome,
        leading: phoneTab ? const MenuButton() : null,
        title: Text(i18n('recorder_title')),
        actions: [
          if (recording != null)
            IconButton(
              key: const ValueKey('recorder-open-folder'),
              tooltip: i18n('recorder_open_folder'),
              icon: const Icon(Remix.folder_video_line, size: 22),
              onPressed: () => unawaited(openRecordFolder(recording)),
            ),
          IconButton(
            key: const ValueKey('recorder-settings'),
            tooltip: i18n('record_settings'),
            icon: const Icon(Remix.settings_5_line, size: 22),
            onPressed: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kRecordSettings)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: recording == null || recorder == null
          ? AppStatusView(
              type: AppStatusType.empty,
              icon: Icons.videocam_off_outlined,
              title: i18n('recorder_unavailable_title'),
              subtitle: i18n('recorder_unavailable_subtitle'),
            )
          : Column(
              children: [
                _StatusSelector(controller: _tabs, tasks: _tasks),
                const Divider(height: 1),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      for (final filter in recorderFilters)
                        _TaskList(
                          tasks: _tasks,
                          status: filter.status,
                          restrictions: _restrictions,
                          actions: _actions(recording, recorder),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// The status chips (3.x `RecorderStatusSelector`: a fixed grid, not two
/// nested horizontal scrollers), with the number of tasks in each.
class _StatusSelector extends StatelessWidget {
  const new({required this.controller, required this.tasks});

  final TabController controller;
  final List<RecordTask> tasks;

  int _count(RecordStatus? status) =>
      status == null ? tasks.length : tasks.where((task) => task.status == status).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? recorderFilters.length
            : constraints.maxWidth >= 600
            ? 5
            : 3;
        final rows = <Widget>[];
        for (var start = 0; start < recorderFilters.length; start += columns) {
          rows.add(
            Row(
              children: [
                for (var index = start; index < start + columns; index++)
                  Expanded(
                    child: index >= recorderFilters.length
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.all(3),
                            child: AnimatedBuilder(
                              animation: controller,
                              builder: (context, _) => _chip(theme, index, controller.index == index),
                            ),
                          ),
                  ),
              ],
            ),
          );
        }
        return ColoredBox(
          color: theme.colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: rows),
          ),
        );
      },
    );
  }

  Widget _chip(ThemeData theme, int index, bool selected) {
    final filter = recorderFilters[index];
    final count = _count(filter.status);
    final foreground = selected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant;
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.46),
      borderRadius: BorderRadius.circular(11),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        key: ValueKey('recorder-status-$index'),
        onTap: () => controller.animateTo(index),
        child: SizedBox(
          height: kMinInteractiveDimension,
          child: Center(
            child: Text(
              count > 0 ? '${i18n(filter.label)} $count' : i18n(filter.label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: count > 0 || selected ? foreground : foreground.withValues(alpha: 0.6),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  const new({required this.tasks, required this.status, required this.restrictions, required this.actions});

  final List<RecordTask> tasks;
  final RecordStatus? status;
  final Map<String, LiveRestriction> restrictions;
  final RecorderCardActions actions;

  @override
  Widget build(BuildContext context) {
    final status = this.status;
    final visible = RecordTask.forDisplay(
      status == null ? tasks : tasks.where((task) => task.status == status),
      groupByStatus: status == null,
    );
    if (visible.isEmpty) {
      return AppStatusView(
        type: AppStatusType.empty,
        icon: Icons.video_collection_outlined,
        title: status == null
            ? i18n('recorder_empty_title')
            : i18n('recorder_empty_status', args: {'status': recordStatusText(status)}),
        subtitle: status == null ? i18n('recorder_empty_hint') : null,
      );
    }
    return ListView.builder(
      physics: const PureLiveBoundedScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: visible.length,
      itemBuilder: (context, index) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: RecorderTaskCard(
            key: ValueKey(visible[index].taskId),
            task: visible[index],
            restriction: restrictions[visible[index].taskId],
            actions: actions,
          ),
        ),
      ),
    );
  }
}
