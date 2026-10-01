import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pure_live/app/app_log.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// Shares a file (share_plus in the app; replaced in tests). False when
/// nothing was shown.
typedef LogFileSharer = Future<bool> Function(File file);

/// The log page's share action; `main` sets the system share sheet.
final Provider<LogFileSharer?> logSharerProvider = Provider((ref) => null);

/// The app log (3.x's log switch on the backup page, its browser log page
/// and log folder): write to a file, the lowest level kept, the entries of
/// this session (filter by level, copy one, copy all), export or share,
/// open the folder and clear. Cookies and tokens never reach the log
/// ([redactSecrets]).
class LogPage extends ConsumerStatefulWidget {
  /// Creates the page over [log] (the app's by default).
  const new({this.log, super.key});

  /// The log shown.
  final AppLog? log;

  @override
  ConsumerState<LogPage> createState() => _LogPageState();
}

class _LogPageState extends ConsumerState<LogPage> {
  late final AppLog _log = widget.log ?? AppLog.instance;
  LogLevel _filter = LogLevel.debug;
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    _log.addListener(_changed);
  }

  @override
  void dispose() {
    _log.removeListener(_changed);
    super.dispose();
  }

  /// A log line can arrive during a build (a framework error); the page
  /// redraws after the frame then.
  void _changed() {
    if (!mounted || _pending) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      setState(() {});
      return;
    }
    _pending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      if (mounted) setState(() {});
    });
  }

  String get _allText => [for (final entry in _visible) entry.format()].join('\n');

  List<LogEntry> get _visible => [
    for (final entry in _log.entries.reversed)
      if (entry.level.index >= _filter.index) entry,
  ];

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _allText));
    AppNavigator.toast(i18n('copied_to_clipboard'));
  }

  Future<void> _share() async {
    try {
      final file = await _log.export(await getTemporaryDirectory());
      final share = ref.read(logSharerProvider);
      if (share != null && await share(file)) return;
      await Clipboard.setData(ClipboardData(text: await file.readAsString()));
      AppNavigator.toast(i18n('settings_log_copied_instead'));
    } on Object {
      AppNavigator.toast(i18n('settings_log_export_failed'));
    }
  }

  Future<void> _openFolder() async {
    final folder = _log.directory;
    var opened = false;
    if (folder != null) {
      try {
        await folder.create(recursive: true);
        opened = await AppNavigator.openFile(folder.path);
      } on Object {
        opened = false;
      }
    }
    if (!opened) AppNavigator.toast(i18n('settings_log_folder_failed', args: {'path': folder?.path ?? ''}));
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(i18n('settings_log_clear')),
        content: Text(i18n('settings_log_clear_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(i18n('cancel'))),
          FilledButton(
            key: const ValueKey('log-clear-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(i18n('clear')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _log.clear();
    AppNavigator.toast(i18n('settings_log_cleared'));
  }

  static String _levelLabel(LogLevel level) => i18n('settings_log_level_${level.name}');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.read(storeProvider).settings;
    final writing = watchSetting(ref, Settings.enableLocalLog);
    final level = LogLevel.parse(watchSetting(ref, Settings.logLevel));
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n('log_manage')),
        actions: [
          IconButton(
            key: const ValueKey('log-copy-all'),
            tooltip: i18n('settings_log_copy_all'),
            onPressed: visible.isEmpty ? null : () => unawaited(_copyAll()),
            icon: const Icon(Icons.copy_all_rounded),
          ),
          IconButton(
            key: const ValueKey('log-share'),
            tooltip: i18n('settings_log_share'),
            onPressed: _log.entries.isEmpty ? null : () => unawaited(_share()),
            icon: const Icon(Icons.ios_share_rounded),
          ),
          IconButton(
            key: const ValueKey('log-clear'),
            tooltip: i18n('settings_log_clear'),
            onPressed: () => unawaited(_clear()),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: context.buildModernCard([
              SwitchListTile(
                key: const ValueKey('log-write-file'),
                secondary: Icon(Remix.file_text_line, color: theme.colorScheme.primary),
                title: Text(i18n('enable_local_log')),
                subtitle: Text(
                  writing && _log.file != null ? _log.file!.path : i18n('settings_log_file_desc'),
                  style: context.textStyles.t12.copyWith(color: theme.hintColor),
                ),
                value: writing,
                onChanged: (value) => unawaited(settings.set(Settings.enableLocalLog, value)),
              ),
              ListTile(
                leading: Icon(Remix.filter_3_line, color: theme.colorScheme.primary),
                title: Text(i18n('settings_log_level')),
                subtitle: Text(i18n('settings_log_level_desc'), style: context.textStyles.t12),
                trailing: DropdownButton<LogLevel>(
                  key: const ValueKey('log-level'),
                  value: level,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final value in LogLevel.values)
                      DropdownMenuItem(value: value, child: Text(_levelLabel(value))),
                  ],
                  onChanged: (value) {
                    if (value != null) unawaited(settings.set(Settings.logLevel, value.name));
                  },
                ),
              ),
              ListTile(
                key: const ValueKey('log-open-folder'),
                leading: Icon(Remix.folder_open_line, color: theme.colorScheme.primary),
                title: Text(i18n('open_log_dir')),
                subtitle: Text(i18n('open_log_dir_desc'), style: context.textStyles.t12),
                onTap: () => unawaited(_openFolder()),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    i18n('settings_log_entries', args: {'count': '${visible.length}'}),
                    style: context.textStyles.t13SemiBold,
                  ),
                ),
                SegmentedButton<LogLevel>(
                  key: const ValueKey('log-filter'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [
                    for (final value in LogLevel.values) ButtonSegment(value: value, label: Text(_levelLabel(value))),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (value) => setState(() => _filter = value.first),
                ),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      i18n('settings_log_empty'),
                      key: const ValueKey('log-empty'),
                      style: context.textStyles.t13.copyWith(color: theme.hintColor),
                    ),
                  )
                : ListView.separated(
                    physics: const PureLiveScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => _EntryRow(entry: visible[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const new({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (entry.level) {
      LogLevel.error => scheme.error,
      LogLevel.warning => Colors.orange.shade700,
      LogLevel.info => scheme.primary,
      LogLevel.debug => scheme.outline,
    };
    final time = entry.time.toIso8601String().split('T').last;
    return InkWell(
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: entry.format()));
        AppNavigator.toast(i18n('copied_to_clipboard'));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${time.length > 12 ? time.substring(0, 12) : time}  ${entry.level.name.toUpperCase()}  ${entry.tag}',
              style: context.textStyles.t11.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              entry.message,
              maxLines: 12,
              overflow: TextOverflow.ellipsis,
              style: context.textStyles.t12.copyWith(fontFamily: 'monospace', height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}
