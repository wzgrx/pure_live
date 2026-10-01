import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/record_settings/record_settings_dialogs.dart';
import 'package:pure_live/pages/recorder/recorder_page.dart';
import 'package:pure_live/pages/recorder/recorder_texts.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';

/// Recording settings (3.x `lib/recorder/pages/record_settings`): quality,
/// folder naming, the recording folder and its size limit, FFmpeg options,
/// reconnection and live checks.
///
/// Routes: `RoutePath.kRecordSettings`.
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
    await _refreshStorage();
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
  Future<String?> _saveDirectory(String path) async {
    final recording = _recording;
    if (recording == null) return i18n('path_or_permission_error');
    try {
      try {
        await recording.storage.prepare(path);
      } on FileSystemException {
        if (!Platform.isAndroid || !await recording.ensureStorageAccess()) rethrow;
        await recording.storage.prepare(path);
      }
      await _set(Settings.recordSavePath, path);
    } on Object {
      return i18n('path_or_permission_error');
    }
    unawaited(_refreshStorage());
    return null;
  }

  Future<void> _chooseDirectory() async {
    final recording = _recording;
    if (recording == null || _choosingDirectory) return;
    setState(() => _choosingDirectory = true);
    try {
      final picker = ref.read(recordDirectoryPickerProvider);
      final defaultPath = await recording.storage.defaultDirectory();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => RecordDirectoryDialog(
          initialPath: _settings.savePath,
          defaultPath: defaultPath,
          onSubmitted: _saveDirectory,
          browse: picker,
        ),
      );
    } finally {
      if (mounted) setState(() => _choosingDirectory = false);
    }
  }

  Future<void> _clearAll() async {
    final recording = _recording;
    if (recording == null || _clearing) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(i18n('confirm_clear_cache'), style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(i18n('confirm_clear_cache_desc')),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(i18n('cancel'))),
          FilledButton(
            key: const ValueKey('record-clear-confirm'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(i18n('clear')),
          ),
        ],
      ),
    );
    if (!(ok ?? false) || !mounted) return;
    setState(() => _clearing = true);
    try {
      await recording.storage.clearAll();
      AppNavigator.toast(i18n('cache_cleared'));
    } on Object {
      AppNavigator.toast(i18n('cache_operation_failed'));
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
    await _refreshStorage();
  }

  String _qualityLabel(String value) => i18nOr(switch (value) {
    '原画' => 'prefer_resolution_option_original',
    '蓝光8M' => 'prefer_resolution_option_blu_ray_8m',
    '蓝光4M' => 'prefer_resolution_option_blu_ray_4m',
    '超清' => 'prefer_resolution_option_super_hd',
    '流畅' => 'prefer_resolution_option_smooth',
    _ => value,
  }, value);

  Widget _spinner(String label) =>
      SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: label));

  @override
  Widget build(BuildContext context) {
    final recording = _recording;
    return Scaffold(
      appBar: AppBar(title: Text(i18n('record_settings'))),
      body: recording == null
          ? AppStatusView(
              type: AppStatusType.empty,
              icon: Icons.videocam_off_outlined,
              title: i18n('recorder_unavailable_title'),
              subtitle: i18n('recorder_unavailable_subtitle'),
            )
          : !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _content(context, recording),
    );
  }

  Widget _content(BuildContext context, AppRecording recording) {
    final settings = _settings;
    return ListView(
      key: const ValueKey('record-settings-list'),
      physics: const PureLiveScrollPhysics(),
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      children: [
        if (!recording.available) ...[
          const SizedBox(height: 8),
          context.buildModernCard([
            context.buildTile(
              icon: Icons.info_outline_rounded,
              title: i18n('recorder_unavailable_title'),
              subtitle: i18n('recorder_unavailable_subtitle'),
              isLong: true,
            ),
          ]),
        ],
        context.buildGroupTitle(i18n('basic_config')),
        context.buildModernCard([
          context.buildTile(
            icon: Remix.hd_line,
            title: i18n('default_record_quality'),
            subtitle: _qualityLabel(settings.defaultQuality),
            onTap: () => unawaited(
              showRecordRadioDialog<String>(
                context: context,
                title: i18n('default_record_quality'),
                selected: settings.defaultQuality,
                options: [
                  for (final value in recordQualityPreferences) RecordOption(value: value, label: _qualityLabel(value)),
                ],
                onSelected: (value) => _set(Settings.recordDefaultQuality, value),
              ),
            ),
          ),
          context.buildSwitchTile(
            icon: Remix.translate_2,
            title: i18n('use_pinyin_folder'),
            subtitle: i18n('use_pinyin_folder_desc'),
            value: settings.usePinyinForFolder,
            onChanged: (value) => _setNow(Settings.recordPinyinFolders, value),
          ),
          context.buildSwitchTile(
            icon: Remix.chat_3_line,
            title: i18n('record_danmaku'),
            subtitle: i18n('record_settings_danmaku_pending'),
            value: settings.recordDanmaku,
            enabled: false,
            onChanged: null,
          ),
        ]),
        const SizedBox(height: 20),
        _cacheHeader(context, recording),
        context.buildModernCard([
          context.buildTile(
            icon: Remix.folder_video_line,
            title: i18n('storage_directory'),
            subtitle: _directory ?? settings.savePath,
            isLong: true,
            onTap: _choosingDirectory ? null : () => unawaited(_chooseDirectory()),
          ),
          context.buildSwitchTile(
            icon: Remix.exchange_box_line,
            title: i18n('enable_cache_limit'),
            subtitle: i18n('enable_cache_limit_desc'),
            value: settings.enableCacheLimit,
            onChanged: (value) => unawaited(
              _set(Settings.recordEnableCacheLimit, value).then((_) => _applyCacheLimit(), onError: (Object _) {}),
            ),
          ),
          if (settings.enableCacheLimit)
            context.buildTile(
              icon: Remix.database_2_line,
              title: i18n('cache_limit'),
              subtitle: '${settings.maxCacheMB} MB',
              onTap: () => unawaited(
                showDialog<void>(
                  context: context,
                  builder: (_) => RecordIntegerDialog(
                    title: i18n('set_max_cache'),
                    fieldKey: 'record-cache-limit',
                    initialValue: settings.maxCacheMB,
                    minimum: 1,
                    suffix: 'MB',
                    hintText: i18n('please_input_number'),
                    errorText: i18n('record_cache_limit_invalid'),
                    quickValues: const [512, 1024, 2048, 5120, 10240, 20480],
                    onSubmitted: (value) async {
                      await _set(Settings.recordMaxCacheMB, value);
                      unawaited(_applyCacheLimit());
                    },
                  ),
                ),
              ),
            ),
          context.buildTile(
            icon: Remix.custom_size,
            title: i18n('current_cache_size'),
            subtitle: _sizeMB == null
                ? (_measuring ? i18n('record_settings_measuring') : '--')
                : recordSizeText(_sizeMB! * 1024 * 1024),
            trailing: _measuring
                ? _spinner(i18n('record_settings_measuring'))
                : IconButton(
                    key: const ValueKey('record-size-refresh'),
                    tooltip: i18n('refresh'),
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () => unawaited(_refreshStorage()),
                  ),
          ),
          context.buildTile(
            icon: Remix.delete_bin_4_line,
            title: i18n('clear_all_cache'),
            subtitle: i18n('clear_all_cache_desc'),
            iconColor: Colors.red,
            trailing: _clearing ? _spinner(i18n('clear_all_cache')) : null,
            onTap: _clearing ? null : () => unawaited(_clearAll()),
          ),
        ]),
        const SizedBox(height: 20),
        context.buildGroupTitle(i18n('record_performance_quality')),
        context.buildModernCard([
          context.buildSwitchTile(
            icon: Remix.video_download_line,
            title: i18n('prefer_best_stream'),
            subtitle: i18n('prefer_best_stream_desc'),
            value: settings.preferBestStream,
            onChanged: (value) => _setNow(Settings.recordPreferBestStream, value),
          ),
          context.buildTile(
            icon: Remix.timer_flash_line,
            title: i18n('rw_timeout'),
            subtitle: '${settings.rwTimeout}s',
            onTap: () => unawaited(
              showRecordRadioDialog<int>(
                context: context,
                title: i18n('rw_timeout'),
                selected: settings.rwTimeout,
                options: [
                  for (final value in RecordSettings.supportedRwTimeouts)
                    RecordOption(
                      value: value,
                      label: '${value}s',
                      description: i18n(switch (value) {
                        15 => 'timeout_fast',
                        30 => 'timeout_balanced',
                        _ => 'timeout_safe',
                      }),
                    ),
                ],
                onSelected: (value) => _set(Settings.recordRwTimeout, value),
              ),
            ),
          ),
          context.buildTile(
            icon: Remix.speed_mini_line,
            title: i18n('queue_size'),
            subtitle: '${settings.threadQueueSize}',
            onTap: () => unawaited(
              showRecordRadioDialog<int>(
                context: context,
                title: i18n('queue_size'),
                selected: settings.threadQueueSize,
                options: [
                  for (final value in RecordSettings.supportedThreadQueueSizes)
                    RecordOption(
                      value: value,
                      label: '$value',
                      description: i18n(switch (value) {
                        <= 512 => 'power_saving_mode',
                        1024 => 'hd_recommend',
                        2048 => 'fhd_recommend',
                        _ => 'extreme_performance',
                      }),
                    ),
                ],
                onSelected: (value) => _set(Settings.recordThreadQueueSize, value),
              ),
            ),
          ),
          context.buildSliderTile(
            icon: Remix.film_line,
            title: i18n('segment_duration'),
            value: settings.segmentTime.toDouble(),
            min: 60,
            max: 3600,
            displayValue: recordSecondsText(settings.segmentTime),
            onChanged: (value) => _setNow(Settings.recordSegmentTime, (value / 30).round() * 30),
          ),
          context.buildTile(
            icon: Remix.task_line,
            title: i18n('max_record_tasks'),
            subtitle: '${settings.maxTaskCount}',
            onTap: () => unawaited(
              showDialog<void>(
                context: context,
                builder: (_) => RecordIntegerDialog(
                  title: i18n('max_record_tasks'),
                  fieldKey: 'record-max-tasks',
                  initialValue: settings.maxTaskCount,
                  minimum: 1,
                  maximum: 10,
                  hintText: i18n('input_range'),
                  errorText: i18n('record_max_tasks_invalid'),
                  quickValues: [for (var value = 1; value <= 10; value++) value],
                  onSubmitted: (value) => _set(Settings.recordMaxTaskCount, value),
                ),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        context.buildGroupTitle(i18n('auto_reconnect')),
        context.buildModernCard([
          context.buildSwitchTile(
            icon: Remix.refresh_line,
            title: i18n('auto_reconnect_switch'),
            subtitle: i18n('auto_reconnect_desc'),
            value: settings.autoReconnect,
            onChanged: (value) => _setNow(Settings.recordAutoReconnect, value),
          ),
          if (settings.autoReconnect)
            context.buildSliderTile(
              icon: Remix.loop_left_line,
              title: i18n('max_retry_count'),
              value: settings.maxRetryCount.toDouble(),
              min: 1,
              max: 20,
              displayValue: '${settings.maxRetryCount}',
              onChanged: (value) => _setNow(Settings.recordMaxRetryCount, value.round()),
            ),
          context.buildSliderTile(
            icon: Remix.time_line,
            title: i18n('retry_delay'),
            value: settings.retryDelay.toDouble(),
            min: 5,
            max: 120,
            displayValue: '${settings.retryDelay}s',
            onChanged: (value) => _setNow(Settings.recordRetryDelay, value.round()),
          ),
        ]),
        const SizedBox(height: 20),
        context.buildGroupTitle(i18n('polling_detection')),
        context.buildModernCard([
          context.buildSwitchTile(
            icon: Remix.radar_line,
            title: i18n('enable_polling'),
            subtitle: i18n('enable_polling_desc'),
            value: settings.enablePolling,
            onChanged: (value) => _setNow(Settings.recordEnablePolling, value),
          ),
          if (settings.enablePolling) ...[
            context.buildSliderTile(
              icon: Remix.time_line,
              title: i18n('check_interval'),
              value: settings.liveCheckInterval.toDouble(),
              min: 10,
              max: 300,
              displayValue: '${settings.liveCheckInterval}s',
              onChanged: (value) => _setNow(Settings.recordLiveCheckInterval, value.round()),
            ),
            context.buildSwitchTile(
              icon: Remix.line_chart_line,
              title: i18n('enable_backoff'),
              subtitle: i18n('enable_backoff_desc'),
              value: settings.enableBackoff,
              onChanged: (value) => _setNow(Settings.recordEnableBackoff, value),
            ),
            if (settings.enableBackoff)
              context.buildSliderTile(
                icon: Remix.hourglass_2_line,
                title: i18n('max_check_interval'),
                value: settings.maxCheckInterval.toDouble(),
                min: 300,
                max: 3600,
                displayValue: recordSecondsText(settings.maxCheckInterval),
                onChanged: (value) => _setNow(Settings.recordMaxCheckInterval, (value / 60).round() * 60),
              ),
          ],
          context.buildSwitchTile(
            icon: Remix.restart_line,
            title: i18n('auto_start_boot'),
            subtitle: i18n('auto_start_boot_desc'),
            value: settings.autoStartOnBoot,
            isLong: true,
            onChanged: (value) => _setNow(Settings.recordAutoStartOnBoot, value),
          ),
        ]),
        const SizedBox(height: 60),
      ],
    );
  }

  Widget _cacheHeader(BuildContext context, AppRecording recording) {
    final theme = Theme.of(context);
    final title = context.buildGroupTitle(i18n('cache_management'));
    final action = TextButton.icon(
      key: const ValueKey('record-open-folder'),
      onPressed: () => unawaited(openRecordFolder(recording)),
      style: TextButton.styleFrom(
        minimumSize: const Size(kMinInteractiveDimension, kMinInteractiveDimension),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: theme.colorScheme.primary,
      ),
      icon: const Icon(Remix.folder_open_line, size: 18),
      label: Text(i18n('recorder_open_folder'), style: context.textStyles.t14.copyWith(fontWeight: FontWeight.w600)),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: title),
        Padding(padding: const EdgeInsets.only(right: 8, bottom: 2), child: action),
      ],
    );
  }
}
