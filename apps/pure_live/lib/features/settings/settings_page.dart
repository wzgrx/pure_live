import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/features/backup/data_settings.dart';
import 'package:pure_live_app/features/health/cache_tile.dart';
import 'package:pure_live_app/features/settings/network_settings.dart';
import 'package:pure_live_app/features/settings/record_directory_tile.dart';
import 'package:pure_live_app/features/danmaku/danmaku_settings.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';
import 'package:pure_live_app/l10n/strings.dart';

/// Settings groups of principles §4.4. Groups whose features are not in the
/// preview yet say so instead of showing dead switches.
enum SettingsGroup {
  general('通用', Icons.tune),
  appearance(S.appearance, Icons.palette_outlined),
  playback('播放', Icons.play_circle_outline),
  danmaku('弹幕', Icons.subtitles_outlined),
  recording('录制', Icons.fiber_manual_record_outlined),
  accounts('平台与账号', Icons.account_circle_outlined),
  network('网络', Icons.lan_outlined),
  data('数据与同步', Icons.cloud_sync_outlined);

  new(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The settings list; from expanded width the chosen group opens beside it.
class SettingsPage extends StatefulWidget {
  const new({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsGroup _selected = SettingsGroup.general;

  @override
  Widget build(BuildContext context) => WindowLayoutBuilder(
    builder: (context, layout) {
      final twoPane = layout.width.atLeast(WidthClass.expanded) && !layout.isShortLandscape;
      final list = ListView(
        children: [
          for (final group in SettingsGroup.values)
            ListTile(
              leading: Icon(group.icon),
              title: Text(group.label),
              selected: twoPane && group == _selected,
              trailing: twoPane ? null : const Icon(Icons.chevron_right),
              onTap: () => twoPane ? setState(() => _selected = group) : context.go('/me/settings/${group.name}'),
            ),
        ],
      );
      return Scaffold(
        appBar: AppBar(title: const Text(S.settings)),
        body: twoPane
            ? Row(
                children: [
                  SizedBox(width: 280, child: list),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
                        child: SettingsGroupBody(group: _selected),
                      ),
                    ),
                  ),
                ],
              )
            : list,
      );
    },
  );
}

/// One group as its own page (compact and medium width).
class SettingsGroupPage extends StatelessWidget {
  const new({required this.group, super.key});

  final SettingsGroup group;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(group.label)),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Sizes.readingWidth),
        child: SettingsGroupBody(group: group),
      ),
    ),
  );
}

const Map<QualityPreference, String> _quality = {
  QualityPreference.original: '原画',
  QualityPreference.bluRay8M: '蓝光 8M',
  QualityPreference.bluRay4M: '蓝光 4M',
  QualityPreference.superHigh: '超清',
  QualityPreference.smooth: '流畅',
};

/// The tiles of one group.
class SettingsGroupBody extends StatelessWidget {
  const new({required this.group, super.key});

  final SettingsGroup group;

  @override
  Widget build(BuildContext context) => ListView(
    children: switch (group) {
      SettingsGroup.general => const [
        ChoiceSettingTile<StartPage>(
          setting: Settings.startPage,
          title: '启动页',
          labels: {StartPage.follows: S.follows, StartPage.discover: S.discover},
        ),
        SwitchSettingTile(setting: Settings.screenKeepOn, title: '播放时屏幕常亮'),
        ChoiceSettingTile<RefreshRateMode>(
          setting: Settings.refreshRateMode,
          title: '刷新率',
          labels: {
            RefreshRateMode.powerSaving: '省电',
            RefreshRateMode.balanced: '均衡',
            RefreshRateMode.performance: '最高',
          },
        ),
        SwitchSettingTile(setting: Settings.autoCheckUpdate, title: '自动检查更新'),
        ClipboardRecognitionTile(),
        SettingsHeader('关注刷新'),
        SwitchSettingTile(setting: Settings.autoRefreshFollows, title: '定时刷新关注的开播状态'),
        SwitchSettingTile(setting: Settings.refreshFollowsOnResume, title: '回到应用时刷新关注'),
        SliderSettingTile(
          setting: Settings.maxConcurrentRefresh,
          title: '同时刷新的直播间数',
          min: 1,
          max: 16,
          divisions: 15,
          format: _integer,
        ),
      ],
      SettingsGroup.appearance => const [
        ChoiceSettingTile<AppThemeMode>(
          setting: Settings.themeMode,
          title: '主题',
          labels: {
            AppThemeMode.system: S.themeSystem,
            AppThemeMode.light: S.themeLight,
            AppThemeMode.dark: S.themeDark,
          },
        ),
        SwitchSettingTile(setting: Settings.pureBlack, title: S.themeBlack, subtitle: '深色时用纯黑背景，适合 OLED 屏幕'),
        SwitchSettingTile(setting: Settings.denseFollows, title: '关注页紧凑卡片', subtitle: '主播名和标题放在一行'),
        SliderSettingTile(setting: Settings.textScale, title: '文字大小', min: 0.85, max: 1.3, divisions: 9),
      ],
      SettingsGroup.playback => const [
        ChoiceSettingTile<QualityPreference>(setting: Settings.qualityWifi, title: '默认画质（Wi-Fi）', labels: _quality),
        ChoiceSettingTile<QualityPreference>(setting: Settings.qualityMobile, title: '默认画质（移动网络）', labels: _quality),
        SwitchSettingTile(setting: Settings.hardwareDecoding, title: '硬件解码', subtitle: '画面异常时关闭试试'),
        ChoiceSettingTile<VideoFit>(
          setting: Settings.videoFit,
          title: '画面比例',
          labels: {VideoFit.contain: '适应', VideoFit.cover: '填充（裁切）', VideoFit.fill: '拉伸'},
        ),
        SwitchSettingTile(setting: Settings.fullScreenDefault, title: '进入直播间自动全屏'),
        SwitchSettingTile(setting: Settings.backgroundPlay, title: '后台播放', subtitle: '离开应用后继续播放声音'),
        SliderSettingTile(
          setting: Settings.defaultMobileVolume,
          title: '手机默认音量',
          min: 0,
          max: 1,
          divisions: 20,
          format: _percent,
        ),
      ],
      SettingsGroup.danmaku => const [DanmakuSettingsTiles()],
      SettingsGroup.data => const [
        SliderSettingTile(
          setting: Settings.historyLimit,
          title: '观看历史最多保留',
          min: 0,
          max: 500,
          divisions: 50,
          format: _historyLimit,
        ),
        DataSyncTiles(),
        CacheTile(),
      ],
      SettingsGroup.recording => [
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
        const SwitchSettingTile(setting: Settings.recordPolling, title: '开播监控', subtitle: '主播开播后自动开始录制'),
        const SliderSettingTile(
          setting: Settings.recordLiveCheckInterval,
          title: '开播检查间隔（秒）',
          min: 10,
          max: 300,
          divisions: 29,
          format: _integer,
        ),
        const SwitchSettingTile(setting: Settings.recordAutoReconnect, title: '断线自动重连'),
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
        const SwitchSettingTile(setting: Settings.recordDanmaku, title: '同时保存弹幕', subtitle: '与视频同名的 XML 文件'),
        const SwitchSettingTile(setting: Settings.recordRemuxToMp4, title: '录完转成 MP4'),
        const SwitchSettingTile(setting: Settings.recordKeepSourceAfterRemux, title: '转成 MP4 后保留原始 FLV'),
        const SwitchSettingTile(setting: Settings.recordResumeOnLaunch, title: '启动时继续未完成的录制'),
      ],
      SettingsGroup.accounts => [
        ListTile(
          title: const Text('平台账号'),
          subtitle: const Text('登录或退出各平台账号'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/me/accounts'),
        ),
      ],
      SettingsGroup.network => const [NetworkSettings()],
    },
  );
}

String _integer(double value) => value.round().toString();
String _percent(double value) => '${(value * 100).round()}%';
String _historyLimit(double value) => value.round() == 0 ? '不限' : '${value.round()} 条';
