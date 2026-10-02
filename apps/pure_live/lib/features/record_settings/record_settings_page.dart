import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/record_settings/record_settings_dialogs.dart';
import 'package:pure_live/features/record_settings/record_settings_texts.dart';
import 'package:pure_live/features/recorder/recorder_page.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/shared/record/record_actions.dart';

/// How long the "最大同时录制任务数" row stays highlighted when the page
/// opens at it ("改上限", U.7b c9).
const Duration recordLimitHighlight = Duration(seconds: 2);

/// Recording settings (3.x `lib/recorder/pages/record_settings`): quality,
/// folder naming, the recording folder and its size limit, FFmpeg options,
/// reconnection and live checks; docs/ui/compare/U.7b.
///
/// Routes: `RoutePath.kRecordSettings`; the argument
/// [recordSettingsMaxTasks] scrolls to "最大同时录制任务数" and highlights it.
class RecordSettingsPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  ConsumerState<RecordSettingsPage> createState() => _RecordSettingsPageState();
}

class _RecordSettingsPageState extends ConsumerState<RecordSettingsPage> {
  AppRecording? _recording;
  StreamSubscription<RecordSettings>? _changes;
  final GlobalKey _maxTasksKey = GlobalKey();
  Timer? _highlightTimer;
  var _highlight = false;
  var _loaded = false;
  String? _directory;
  double? _sizeMB;
  var _measuring = false;
  var _clearing = false;
  var _choosingDirectory = false;

  RecordSettings get _settings => _recording?.settings.current ?? RecordSettings();

  @override
  void initState() {
    super.initState();
    final recording = _recording = ref.read(recordingProvider);
    if (recording == null) return;
    _changes = recording.settings.changes.listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(_load(recording));
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _load(AppRecording recording) async {
    try {
      await recording.loadSettings();
    } on Object {
      // Defaults stay.
    }
    if (!mounted) return;
    setState(() => _loaded = true);
    if (widget.route.arguments == recordSettingsMaxTasks) _showLimit();
    await _refreshStorage();
  }

  /// Scrolls to "最大同时录制任务数" and highlights it for
  /// [recordLimitHighlight] (opened from "改上限").
  void _showLimit() {
    setState(() => _highlight = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _maxTasksKey.currentContext;
      if (row != null && row.mounted) {
        Scrollable.ensureVisible(row, alignment: 0.5, duration: const Duration(milliseconds: 300));
      }
    });
    _highlightTimer = Timer(recordLimitHighlight, () {
      if (mounted) setState(() => _highlight = false);
    });
  }

  /// The managed folder and its size (3.x `refreshStorageInfo`).
  Future<void> _refreshStorage() async {
    final recording = _recording;
    if (recording == null || _measuring) return;
    setState(() => _measuring = true);
    String? directory;
    double? size;
    try {
      directory = (await recording.storage.recordDirectory()).path;
      size = await recording.storage.sizeMB();
    } on Object {
      directory = null;
      size = null;
    }
    if (!mounted) return;
    setState(() {
      _directory = directory;
      _sizeMB = size;
      _measuring = false;
    });
  }

  Future<void> _set<T extends Object>(Setting<T> setting, T value) async {
    final recording = _recording;
    if (recording == null) return;
    try {
      await recording.settings.set(setting, value);
    } on Object {
      AppNavigator.toast(i18n('record_settings_apply_failed'));
      rethrow;
    }
  }

  void _setNow<T extends Object>(Setting<T> setting, T value) =>
      unawaited(_set(setting, value).catchError((Object _) {}));

  Future<void> _applyCacheLimit() async {
    final recording = _recording;
    final settings = _settings;
    if (recording == null || !settings.enableCacheLimit) return;
    try {
      await recording.storage.enforceLimit(maxMB: settings.maxCacheMB.toDouble());
    } on Object {
      AppNavigator.toast(i18n('cache_operation_failed'));
    }
    await _refreshStorage();
  }

  /// Proves [path] writable before saving it (3.x `pickRecordDir`); Android
  /// asks for storage access when the folder is outside the app's own.
  /// Returns the error text, or null when saved.
  Future<String?> _saveDirectory(String path) async {
    final recording = _recording;
    if (recording == null) return i18n('record_folder_unwritable');
    try {
      try {
        await recording.storage.prepare(path);
      } on FileSystemException {
        if (!Platform.isAndroid || !await recording.ensureStorageAccess()) rethrow;
        await recording.storage.prepare(path);
      }
      await _set(Settings.recordSavePath, path);
    } on Object {
      return i18n('record_folder_unwritable');
    }
    unawaited(_refreshStorage());
    return null;
  }

  /// The folder row: the system folder picker where there is one (3.x),
  /// else the folder dialog (a typed path, the default).
  Future<void> _chooseDirectory() async {
    final recording = _recording;
    if (recording == null || _choosingDirectory) return;
    setState(() => _choosingDirectory = true);
    try {
      final picker = ref.read(recordDirectoryPickerProvider);
      if (picker != null) {
        final picked = (await picker())?.trim() ?? '';
        if (picked.isEmpty || !mounted) return;
        final error = await _saveDirectory(picked);
        if (error != null) AppNavigator.toast(error);
        return;
      }
      final defaultPath = await recording.storage.defaultDirectory();
      if (!mounted) return;
      await showAppDialog<void>(
        context: context,
        builder: (_) => RecordDirectoryDialog(
          initialPath: _settings.savePath,
          defaultPath: defaultPath,
          onSubmitted: _saveDirectory,
        ),
      );
    } finally {
      if (mounted) setState(() => _choosingDirectory = false);
    }
  }

  Future<void> _clearAll() async {
    final recording = _recording;
    if (recording == null || _clearing) return;
    final size = _sizeMB;
    final ok = await confirmRecordClear(context, size: size == null ? '--' : recordSpaceLabel(size * 1024 * 1024));
    if (!ok || !mounted) return;
    setState(() => _clearing = true);
    try {
      await recording.storage.clearAll();
      AppNavigator.toast(i18n('record_files_cleared'));
    } on Object {
      AppNavigator.toast(i18n('cache_operation_failed'));
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
    await _refreshStorage();
  }

  void _editCacheLimit() => unawaited(
    showAppDialog<void>(
      context: context,
      builder: (_) => RecordIntegerDialog(
        title: i18n('record_size_cap_dialog'),
        fieldKey: 'record-cache-limit',
        initialValue: _settings.maxCacheMB,
        minimum: 1,
        suffix: 'MB',
        hintText: i18n('please_input_number'),
        errorText: i18n('record_cache_limit_invalid'),
        note: i18n('record_size_cap_note'),
        onSubmitted: (value) async {
          await _set(Settings.recordMaxCacheMB, value);
          unawaited(_applyCacheLimit());
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final recording = _recording;
    return Scaffold(
      appBar: settingsPageAppBar(context, title: i18n('record_settings')),
      body: recording == null
          ? AppStatusView(
              type: AppStatusType.empty,
              icon: AppIcons.recordUnavailable,
              title: i18n('recorder_unavailable_title'),
              subtitle: i18n('recorder_unavailable_subtitle'),
            )
          : !_loaded
          ? const AppStatusView(type: AppStatusType.loading, title: '', subtitle: '')
          : _content(context, recording),
    );
  }

  Widget _content(BuildContext context, AppRecording recording) {
    final settings = _settings;
    final size = _sizeMB;
    return SettingsPageList(
      key: const ValueKey('record-settings-list'),
      children: [
        if (!recording.available)
          SettingsGroup(
            first: true,
            children: [
              SettingsRow(
                icon: AppIcons.info,
                title: i18n('recorder_unavailable_title'),
                subtitle: i18n('recorder_unavailable_subtitle'),
                subtitleMaxLines: null,
              ),
            ],
          ),
        SettingsGroup(
          first: recording.available,
          title: i18n('basic_config'),
          children: [
            SettingsLinkRow(
              key: const ValueKey('record-quality'),
              icon: AppIcons.recordQuality,
              title: i18n('default_record_quality'),
              choice: true,
              value: recordQualityLabel(settings.defaultQuality),
              onTap: () => unawaited(
                showRecordRadioDialog<String>(
                  context: context,
                  title: i18n('default_record_quality'),
                  selected: settings.defaultQuality,
                  options: [
                    for (final value in recordQualityPreferences)
                      RecordOption(value: value, label: recordQualityLabel(value)),
                  ],
                  onSelected: (value) => _set(Settings.recordDefaultQuality, value),
                ),
              ),
            ),
            SettingsSwitchRow(
              icon: AppIcons.recordPinyin,
              title: i18n('use_pinyin_folder'),
              subtitle: i18n('use_pinyin_folder_desc'),
              subtitleMaxLines: null,
              value: settings.usePinyinForFolder,
              onChanged: (value) => _setNow(Settings.recordPinyinFolders, value),
            ),
            SettingsSwitchRow(
              icon: AppIcons.recordDanmaku,
              title: i18n('record_danmaku'),
              subtitle: i18n('record_danmaku_desc'),
              subtitleMaxLines: null,
              value: settings.recordDanmaku,
              onChanged: (value) => _setNow(Settings.recordDanmaku, value),
            ),
          ],
        ),
        SettingsGroup(
          title: i18n('record_files'),
          children: [
            SettingsRow(
              key: const ValueKey('record-directory'),
              icon: AppIcons.recordFolder,
              title: i18n('storage_directory'),
              subtitle: _directory ?? settings.savePath,
              subtitleMaxLines: null,
              stackTrailing: false,
              busy: _choosingDirectory,
              onTap: () => unawaited(_chooseDirectory()),
              trailing: IconButton(
                key: const ValueKey('record-open-folder'),
                tooltip: i18n('recorder_open_folder'),
                icon: const Icon(AppIcons.openFolder, size: 22),
                color: Theme.of(context).colorScheme.primary,
                onPressed: () => unawaited(openRecordFolder(recording)),
              ),
            ),
            SettingsSwitchRow(
              icon: AppIcons.recordSizeLimit,
              title: i18n('record_size_limit'),
              subtitle: i18n('record_size_limit_desc'),
              subtitleMaxLines: null,
              value: settings.enableCacheLimit,
              onChanged: (value) => unawaited(
                _set(Settings.recordEnableCacheLimit, value).then((_) => _applyCacheLimit(), onError: (Object _) {}),
              ),
            ),
            SettingsLinkRow(
              key: const ValueKey('record-size-cap'),
              icon: AppIcons.recordSizeCap,
              title: i18n('record_size_cap'),
              value: '${settings.maxCacheMB} MB',
              enabled: settings.enableCacheLimit,
              onTap: _editCacheLimit,
            ),
            SettingsRow(
              key: const ValueKey('record-used-space'),
              icon: AppIcons.recordUsedSpace,
              title: i18n('record_used_space'),
              tooltip: i18n('refresh'),
              busy: _measuring,
              onTap: () => unawaited(_refreshStorage()),
              trailing: Text(
                size == null ? '--' : recordSpaceLabel(size * 1024 * 1024),
                style: context.textStyles.t14.tabular.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            SettingsLinkRow(
              key: const ValueKey('record-clear'),
              icon: AppIcons.recordClear,
              title: i18n('clear_all_cache'),
              subtitle: i18n('clear_all_cache_desc'),
              subtitleMaxLines: null,
              busy: _clearing,
              onTap: () => unawaited(_clearAll()),
            ),
          ],
        ),
        SettingsGroup(
          title: i18n('record_performance_quality'),
          children: [
            SettingsSwitchRow(
              icon: AppIcons.recordBestStream,
              title: i18n('prefer_best_stream'),
              subtitle: i18n('prefer_best_stream_desc'),
              subtitleMaxLines: null,
              value: settings.preferBestStream,
              onChanged: (value) => _setNow(Settings.recordPreferBestStream, value),
            ),
            SettingsLinkRow(
              key: const ValueKey('record-timeout'),
              icon: AppIcons.recordTimeout,
              title: i18n('rw_timeout'),
              choice: true,
              subtitle: recordTimeoutMeaning(settings.rwTimeout),
              subtitleMaxLines: null,
              value: recordSecondsLabel(settings.rwTimeout),
              onTap: () => unawaited(
                showRecordRadioDialog<int>(
                  context: context,
                  title: i18n('rw_timeout'),
                  selected: settings.rwTimeout,
                  options: [
                    for (final value in RecordSettings.supportedRwTimeouts)
                      RecordOption(
                        value: value,
                        label: recordSecondsLabel(value),
                        description: recordTimeoutMeaning(value),
                      ),
                  ],
                  onSelected: (value) => _set(Settings.recordRwTimeout, value),
                ),
              ),
            ),
            SettingsLinkRow(
              key: const ValueKey('record-queue'),
              icon: AppIcons.recordQueue,
              title: i18n('queue_size'),
              choice: true,
              subtitle: recordQueueMeaning(settings.threadQueueSize),
              subtitleMaxLines: null,
              value: '${settings.threadQueueSize}',
              onTap: () => unawaited(
                showRecordRadioDialog<int>(
                  context: context,
                  title: i18n('queue_size'),
                  selected: settings.threadQueueSize,
                  options: [
                    for (final value in RecordSettings.supportedThreadQueueSizes)
                      RecordOption(value: value, label: '$value', description: recordQueueMeaning(value)),
                  ],
                  onSelected: (value) => _set(Settings.recordThreadQueueSize, value),
                ),
              ),
            ),
            _SliderSetting(
              key: const ValueKey('record-segment'),
              icon: AppIcons.recordSegment,
              title: i18n('segment_duration'),
              // Whole minutes, 1–60 (U.7b c11); a 3.x value between minutes
              // shows as it is until it is dragged.
              value: settings.segmentTime / 60,
              min: 1,
              max: 60,
              divisions: 59,
              label: (minutes) => recordDurationLabel((minutes * 60).round()),
              onChanged: (minutes) => _setNow(Settings.recordSegmentTime, minutes.round() * 60),
            ),
            _maxTasks(settings),
          ],
        ),
        SettingsGroup(
          title: i18n('auto_reconnect'),
          children: [
            SettingsSwitchRow(
              icon: AppIcons.recordReconnect,
              title: i18n('auto_reconnect_switch'),
              subtitle: i18n('auto_reconnect_desc'),
              value: settings.autoReconnect,
              onChanged: (value) => _setNow(Settings.recordAutoReconnect, value),
            ),
            _SliderSetting(
              key: const ValueKey('record-retries'),
              icon: AppIcons.recordRetries,
              title: i18n('max_retry_count'),
              value: settings.maxRetryCount.toDouble(),
              min: 1,
              max: 20,
              divisions: 19,
              enabled: settings.autoReconnect,
              label: (value) => recordTimesLabel(value.round()),
              onChanged: (value) => _setNow(Settings.recordMaxRetryCount, value.round()),
            ),
            _SliderSetting(
              key: const ValueKey('record-retry-delay'),
              icon: AppIcons.recordInterval,
              title: i18n('retry_delay'),
              value: settings.retryDelay.toDouble(),
              min: 5,
              max: 120,
              divisions: 115,
              enabled: settings.autoReconnect,
              label: (value) => recordSecondsLabel(value.round()),
              onChanged: (value) => _setNow(Settings.recordRetryDelay, value.round()),
            ),
          ],
        ),
        SettingsGroup(
          title: i18n('record_live_check'),
          children: [
            SettingsSwitchRow(
              icon: AppIcons.recordPolling,
              title: i18n('enable_polling'),
              subtitle: i18n('enable_polling_desc'),
              value: settings.enablePolling,
              onChanged: (value) => _setNow(Settings.recordEnablePolling, value),
            ),
            _SliderSetting(
              key: const ValueKey('record-check-interval'),
              icon: AppIcons.recordInterval,
              title: i18n('check_interval'),
              value: settings.liveCheckInterval.toDouble(),
              min: 10,
              max: 300,
              divisions: 290,
              enabled: settings.enablePolling,
              label: (value) => recordSecondsLabel(value.round()),
              onChanged: (value) => _setNow(Settings.recordLiveCheckInterval, value.round()),
            ),
            SettingsSwitchRow(
              icon: AppIcons.recordBackoff,
              title: i18n('enable_backoff'),
              subtitle: i18n('enable_backoff_desc'),
              value: settings.enableBackoff,
              enabled: settings.enablePolling,
              onChanged: (value) => _setNow(Settings.recordEnableBackoff, value),
            ),
            _SliderSetting(
              key: const ValueKey('record-max-check-interval'),
              icon: AppIcons.recordMaxInterval,
              title: i18n('max_check_interval'),
              value: settings.maxCheckInterval / 60,
              min: 5,
              max: 60,
              divisions: 55,
              enabled: settings.enablePolling && settings.enableBackoff,
              label: (minutes) => recordDurationLabel((minutes * 60).round()),
              onChanged: (minutes) => _setNow(Settings.recordMaxCheckInterval, minutes.round() * 60),
            ),
            SettingsSwitchRow(
              icon: AppIcons.recordResume,
              title: i18n('auto_start_boot'),
              subtitle: i18n('auto_start_boot_desc'),
              subtitleMaxLines: null,
              value: settings.autoStartOnBoot,
              onChanged: (value) => _setNow(Settings.recordAutoStartOnBoot, value),
            ),
          ],
        ),
      ],
    );
  }

  /// "最大同时录制任务数" with − and + on the row, 1–10, saved at once
  /// (U.7b c9); highlighted when the page opens at it.
  Widget _maxTasks(RecordSettings settings) {
    final colors = Theme.of(context).colorScheme;
    final count = settings.maxTaskCount;
    return AnimatedContainer(
      key: _maxTasksKey,
      duration: const Duration(milliseconds: 200),
      foregroundDecoration: BoxDecoration(
        border: _highlight ? Border.all(color: colors.primary, width: 2) : null,
        borderRadius: const BorderRadius.all(Radius.circular(16)),
      ),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: _highlight ? 0.08 : 0),
        borderRadius: const BorderRadius.all(Radius.circular(16)),
      ),
      child: SettingsCounterRow(
        key: const ValueKey('record-max-tasks'),
        icon: AppIcons.recordMaxTasks,
        title: i18n('max_record_tasks'),
        subtitle: i18n('record_max_tasks_desc'),
        subtitleMaxLines: null,
        value: '$count',
        decreaseTooltip: i18n('decrease_value', args: {'label': ''}).trim(),
        increaseTooltip: i18n('increase_value', args: {'label': ''}).trim(),
        decreaseKey: const ValueKey('record-max-tasks-decrease'),
        increaseKey: const ValueKey('record-max-tasks-increase'),
        onDecrease: count <= 1 ? null : () => _setNow(Settings.recordMaxTaskCount, count - 1),
        onIncrease: count >= 10 ? null : () => _setNow(Settings.recordMaxTaskCount, count + 1),
      ),
    );
  }
}

/// A slider row that follows the finger and saves when the drag ends (the
/// U.6a slider row; 3.x saved on every move).
class _SliderSetting extends StatefulWidget {
  const new({
    required this.icon,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final IconData icon;
  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double value) label;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  State<_SliderSetting> createState() => _SliderSettingState();
}

class _SliderSettingState extends State<_SliderSetting> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final value = _dragging ?? widget.value;
    return SettingsSliderRow(
      icon: widget.icon,
      title: widget.title,
      value: value.clamp(widget.min, widget.max),
      min: widget.min,
      max: widget.max,
      divisions: widget.divisions,
      enabled: widget.enabled,
      label: widget.label(value),
      onChanged: (next) => setState(() => _dragging = next),
      onChangeEnd: (end) {
        setState(() => _dragging = null);
        widget.onChanged(end);
      },
    );
  }
}
