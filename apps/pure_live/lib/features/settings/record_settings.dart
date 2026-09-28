import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/features/settings/record_directory_tile.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';
import 'package:pure_live_app/features/settings/settings_search.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

Map<QualityPreference, String> get _quality => {
  QualityPreference.original: t.quality.original,
  QualityPreference.bluRay8M: t.quality.bluRay8M,
  QualityPreference.bluRay4M: t.quality.bluRay4M,
  QualityPreference.superHigh: t.quality.superHigh,
  QualityPreference.smooth: t.quality.smooth,
};

/// The recording group of the settings (F-REC-03; spec/modules/record.md
/// §20): every registered `record.*` setting has a tile here.
class RecordSettingsTiles extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SettingAnchor(
        id: recordCenterAnchor,
        child: ListTile(
          title: Text(t.app.recordings),
          subtitle: Text(t.settings.record.centerSubtitle),
          trailing: const LiveIcon(LiveIcons.subpage),
          onTap: () => context.go('/me/recordings'),
        ),
      ),
      const RecordDirectoryTile(),
      ChoiceSettingTile<QualityPreference>(
        setting: Settings.recordDefaultQuality,
        title: t.settings.record.quality,
        labels: _quality,
      ),
      SettingsHeader(t.settings.record.monitoring),
      SwitchSettingTile(
        setting: Settings.recordPolling,
        title: t.settings.record.monitoring,
        subtitle: t.settings.record.monitoringSubtitle,
      ),
      SliderSettingTile(
        setting: Settings.recordLiveCheckInterval,
        title: t.settings.record.pollInterval,
        min: 10,
        max: 300,
        divisions: 29,
        format: _integer,
      ),
      // §11.5: regular retries and the waiting-for-live checks share these.
      SettingsHeader(t.settings.record.reconnect),
      SwitchSettingTile(setting: Settings.recordAutoReconnect, title: t.settings.record.autoReconnect),
      SliderSettingTile(
        setting: Settings.recordMaxRetries,
        title: t.settings.record.retries,
        min: 1,
        max: 20,
        divisions: 19,
        format: _integer,
      ),
      SliderSettingTile(
        setting: Settings.recordRetryDelay,
        title: t.settings.record.retryInterval,
        min: 5,
        max: 120,
        divisions: 23,
        format: _integer,
      ),
      SwitchSettingTile(
        setting: Settings.recordBackoff,
        title: t.settings.record.backoff,
        subtitle: t.settings.record.backoffSubtitle,
      ),
      SliderSettingTile(
        setting: Settings.recordMaxCheckInterval,
        title: t.settings.record.maxBackoff,
        min: 300,
        max: 3600,
        divisions: 55,
        format: _minutes,
      ),
      _IntChoiceTile(
        setting: Settings.recordReadTimeout,
        title: t.settings.record.readTimeout,
        choices: const [15, 30, 60],
        format: _seconds,
      ),
      SettingsHeader(t.settings.record.files),
      SliderSettingTile(
        setting: Settings.recordMaxConcurrent,
        title: t.settings.record.maxConcurrent,
        min: 1,
        max: 10,
        divisions: 9,
        format: _integer,
      ),
      SliderSettingTile(
        setting: Settings.recordSplitMinutes,
        title: t.settings.record.splitDuration,
        min: 0,
        max: 240,
        divisions: 48,
        format: _integer,
      ),
      // §6.5: 0 = off, otherwise at least 64 MB.
      SliderSettingTile(
        setting: Settings.recordSplitMegabytes,
        title: t.settings.record.splitSize,
        min: 0,
        max: 8192,
        divisions: 32,
        format: _splitSize,
      ),
      SwitchSettingTile(
        setting: Settings.recordDanmaku,
        title: t.settings.record.saveDanmaku,
        subtitle: t.settings.record.saveDanmakuSubtitle,
      ),
      SwitchSettingTile(setting: Settings.recordRemuxToMp4, title: t.settings.record.remuxMp4),
      SwitchSettingTile(setting: Settings.recordKeepSourceAfterRemux, title: t.settings.record.keepSource),
      SwitchSettingTile(
        setting: Settings.recordPinyinFolders,
        title: t.settings.record.pinyinFolders,
        subtitle: t.settings.record.pinyinFoldersSubtitle,
      ),
      SwitchSettingTile(setting: Settings.recordResumeOnLaunch, title: t.settings.record.resumeOnStart),
      // §15: the "cache limit" keys cap the recording folder.
      SettingsHeader(t.settings.record.space),
      SwitchSettingTile(
        setting: Settings.recordCacheLimitEnabled,
        title: t.settings.record.limitSize,
        subtitle: t.settings.record.limitSizeSubtitle,
      ),
      _IntChoiceTile(
        setting: Settings.recordCacheLimitMb,
        title: t.settings.record.sizeLimit,
        choices: const [1024, 2048, 5120, 10240, 20480, 51200, 102400, 204800, 512000, 1048576],
        format: _megabytes,
      ),
    ],
  );
}

/// One of a few numbers; a stored value outside [choices] (from 3.x) is
/// shown and listed too.
class _IntChoiceTile extends StatelessWidget {
  const new({required this.setting, required this.title, required this.choices, required this.format});

  final IntSetting setting;
  final String title;
  final List<int> choices;
  final String Function(int value) format;

  @override
  Widget build(BuildContext context) => SettingBuilder<int>(
    setting: setting,
    builder: (context, value, _) {
      final values = {...choices, value}.toList()..sort();
      return ChoiceSettingTile<int>(
        setting: setting,
        title: title,
        labels: {for (final choice in values) choice: format(choice)},
      );
    },
  );
}

String _integer(double value) => value.round().toString();

String _seconds(int value) => t.common.seconds(n: value);

String _minutes(double value) => t.common.minutes(n: (value / 60).round());

String _megabytes(int value) => value >= 1024 && value % 1024 == 0
    ? '${value ~/ 1024} GB'
    : (value >= 1024 ? '${(value / 1024).toStringAsFixed(1)} GB' : '$value MB');

String _splitSize(double value) {
  final mb = value.round();
  return mb == 0 ? t.settings.record.noSplit : _megabytes(mb);
}
