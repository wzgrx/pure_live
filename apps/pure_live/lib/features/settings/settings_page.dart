import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/features/backup/data_settings.dart';
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
      SettingsGroup.danmaku => const [
        SwitchSettingTile(setting: Settings.danmakuEnabled, title: '显示弹幕'),
        SliderSettingTile(
          setting: Settings.danmakuFontSize,
          title: '字号',
          min: 10,
          max: 30,
          divisions: 20,
          format: _integer,
        ),
        SliderSettingTile(
          setting: Settings.danmakuFontWeight,
          title: '字重',
          min: 100,
          max: 900,
          divisions: 8,
          format: _integer,
        ),
        SliderSettingTile(
          setting: Settings.danmakuOpacity,
          title: '不透明度',
          min: 0,
          max: 1,
          divisions: 20,
          format: _percent,
        ),
        SliderSettingTile(
          setting: Settings.danmakuSpeed,
          title: '速度',
          min: 20,
          max: 400,
          divisions: 38,
          format: _integer,
        ),
        SliderSettingTile(
          setting: Settings.danmakuArea,
          title: '显示区域',
          min: 0,
          max: 1,
          divisions: 20,
          format: _percent,
        ),
        SwitchSettingTile(setting: Settings.danmakuStroke, title: '描边'),
        SwitchSettingTile(setting: Settings.danmakuNoEmoji, title: '隐藏表情弹幕'),
        SettingsHeader('过滤'),
        SwitchSettingTile(setting: Settings.danmakuCollapseRepeated, title: '合并重复弹幕'),
        SwitchSettingTile(setting: Settings.danmakuSimilarityFilter, title: '过滤相似弹幕'),
        SwitchSettingTile(setting: Settings.danmakuFilterDouyuAutomated, title: '过滤斗鱼机器人弹幕'),
      ],
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
      ],
      SettingsGroup.recording ||
      SettingsGroup.accounts ||
      SettingsGroup.network => const [ListTile(enabled: false, title: Text(S.comingSoon))],
    },
  );
}

String _integer(double value) => value.round().toString();
String _percent(double value) => '${(value * 100).round()}%';
String _historyLimit(double value) => value.round() == 0 ? '不限' : '${value.round()} 条';
