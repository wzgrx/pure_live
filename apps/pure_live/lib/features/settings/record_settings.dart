import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/settings/record_directory_tile.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';

const Map<QualityPreference, String> _quality = {
  QualityPreference.original: '原画',
  QualityPreference.bluRay8M: '蓝光 8M',
  QualityPreference.bluRay4M: '蓝光 4M',
  QualityPreference.superHigh: '超清',
  QualityPreference.smooth: '流畅',
};

/// The recording group of the settings (F-REC-03; spec/modules/record.md
/// §20): every registered `record.*` setting has a tile here.
class RecordSettingsTiles extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ListTile(
        title: const Text('录制中心'),
        subtitle: const Text('查看和管理录制任务'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go('/me/recordings'),
      ),
      const RecordDirectoryTile(),
      const ChoiceSettingTile<QualityPreference>(
        setting: Settings.recordDefaultQuality,
        title: '默认录制画质',
        labels: _quality,
      ),
      const SettingsHeader('开播监控'),
      const SwitchSettingTile(setting: Settings.recordPolling, title: '开播监控', subtitle: '主播开播后自动开始录制'),
      const SliderSettingTile(
        setting: Settings.recordLiveCheckInterval,
        title: '开播检查间隔（秒）',
        min: 10,
        max: 300,
        divisions: 29,
        format: _integer,
      ),
      // §11.5: regular retries and the waiting-for-live checks share these.
      const SettingsHeader('断线重连'),
      const SwitchSettingTile(setting: Settings.recordAutoReconnect, title: '断线自动重连'),
      const SliderSettingTile(
        setting: Settings.recordMaxRetries,
        title: '重试次数',
        min: 1,
        max: 20,
        divisions: 19,
        format: _integer,
      ),
      const SliderSettingTile(
        setting: Settings.recordRetryDelay,
        title: '重试间隔（秒）',
        min: 5,
        max: 120,
        divisions: 23,
        format: _integer,
      ),
      const SwitchSettingTile(
        setting: Settings.recordBackoff,
        title: '失败后逐次加长等待',
        subtitle: '重试和开播检查每失败一次，等待时间翻倍，直到最长间隔',
      ),
      const SliderSettingTile(
        setting: Settings.recordMaxCheckInterval,
        title: '最长等待间隔',
        min: 300,
        max: 3600,
        divisions: 55,
        format: _minutes,
      ),
      const _IntChoiceTile(
        setting: Settings.recordReadTimeout,
        title: '读取超时（直播流多久没有数据算断线）',
        choices: [15, 30, 60],
        format: _seconds,
      ),
      const SettingsHeader('文件'),
      const SliderSettingTile(
        setting: Settings.recordMaxConcurrent,
        title: '同时录制的数量',
        min: 1,
        max: 10,
        divisions: 9,
        format: _integer,
      ),
      const SliderSettingTile(
        setting: Settings.recordSplitMinutes,
        title: '按时长分段（分钟，0 为不分段）',
        min: 0,
        max: 240,
        divisions: 48,
        format: _integer,
      ),
      // §6.5: 0 = off, otherwise at least 64 MB.
      const SliderSettingTile(
        setting: Settings.recordSplitMegabytes,
        title: '按大小分段',
        min: 0,
        max: 8192,
        divisions: 32,
        format: _splitSize,
      ),
      const SwitchSettingTile(setting: Settings.recordDanmaku, title: '同时保存弹幕', subtitle: '与视频同名的 XML 文件'),
      const SwitchSettingTile(setting: Settings.recordRemuxToMp4, title: '录完转成 MP4'),
      const SwitchSettingTile(setting: Settings.recordKeepSourceAfterRemux, title: '转成 MP4 后保留原始 FLV'),
      const SwitchSettingTile(
        setting: Settings.recordPinyinFolders,
        title: '文件夹名用拼音',
        subtitle: '主播名转成拼音作文件夹名，方便在不支持中文的设备上查看',
      ),
      const SwitchSettingTile(setting: Settings.recordResumeOnLaunch, title: '启动时继续未完成的录制'),
      // §15: the "cache limit" keys cap the recording folder.
      const SettingsHeader('空间'),
      const SwitchSettingTile(
        setting: Settings.recordCacheLimitEnabled,
        title: '限制录制目录大小',
        subtitle: '超过上限时从最早的录制文件开始删除，正在录制和处理的不删',
      ),
      const _IntChoiceTile(
        setting: Settings.recordCacheLimitMb,
        title: '录制目录上限',
        choices: [1024, 2048, 5120, 10240, 20480, 51200, 102400, 204800, 512000, 1048576],
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

String _seconds(int value) => '$value 秒';

String _minutes(double value) => '${(value / 60).round()} 分钟';

String _megabytes(int value) => value >= 1024 && value % 1024 == 0
    ? '${value ~/ 1024} GB'
    : (value >= 1024 ? '${(value / 1024).toStringAsFixed(1)} GB' : '$value MB');

String _splitSize(double value) {
  final mb = value.round();
  return mb == 0 ? '不分段' : _megabytes(mb);
}
