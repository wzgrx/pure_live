import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/features/alerts/alert_tiles.dart';
import 'package:pure_live_app/features/backup/data_settings.dart';
import 'package:pure_live_app/features/danmaku/danmaku_settings.dart';
import 'package:pure_live_app/features/health/cache_tile.dart';
import 'package:pure_live_app/features/settings/network_settings.dart';
import 'package:pure_live_app/features/settings/record_settings.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';
import 'package:pure_live_app/features/system/system_settings.dart';
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
      final tv = TvScope.of(context).enabled;
      // TV: always two panes (principles §5.3); the group under focus opens
      // on the right, the D-pad goes right into it.
      final twoPane = tv || (layout.width.atLeast(WidthClass.expanded) && !layout.isShortLandscape);
      final list = ListView(
        children: [
          for (final group in SettingsGroup.values)
            ListTile(
              leading: Icon(group.icon),
              title: Text(group.label),
              selected: twoPane && group == _selected,
              trailing: twoPane ? null : const Icon(Icons.chevron_right),
              onFocusChange: tv
                  ? (focused) {
                      if (focused && _selected != group) setState(() => _selected = group);
                    }
                  : null,
              onTap: () => twoPane ? setState(() => _selected = group) : context.go('/me/settings/${group.name}'),
            ),
        ],
      );
      return Scaffold(
        appBar: AppBar(title: const Text(S.settings)),
        body: twoPane
            ? Row(
                children: [
                  SizedBox(width: tv ? 240 : 280, child: list),
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
        SystemSettingTiles(SystemSettingsSection.general),
        SettingsHeader('电视'),
        ChoiceSettingTile<TvMode>(
          setting: Settings.tvMode,
          title: '电视模式',
          labels: {TvMode.auto: '自动（检测到电视时开启）', TvMode.on: '开启', TvMode.off: '关闭'},
        ),
        SwitchSettingTile(setting: Settings.tvPerformanceMode, title: '电视焦点只描边', subtitle: '性能优先：焦点不放大，适合低端电视盒子'),
        SettingsHeader('关注刷新'),
        SwitchSettingTile(setting: Settings.autoRefreshFollows, title: '定时刷新关注的开播状态'),
        SwitchSettingTile(setting: Settings.refreshFollowsOnResume, title: '回到应用时刷新关注'),
        SliderSettingTile(
          setting: Settings.autoRefreshInterval,
          title: '定时刷新间隔',
          // F-FAV-04: 3.x offered 5 minutes to 6 hours.
          min: 5,
          max: 360,
          divisions: 71,
          format: _minutes,
        ),
        SliderSettingTile(
          setting: Settings.maxConcurrentRefresh,
          title: '同时刷新的直播间数',
          min: 1,
          max: 16,
          divisions: 15,
          format: _integer,
        ),
        // F-FAV-04: covers of live cards downloaded again on a timer.
        SwitchSettingTile(setting: Settings.autoRefreshCovers, title: '定时刷新封面', subtitle: '开播卡片的封面按间隔重新下载，看到的画面更新'),
        SliderSettingTile(
          setting: Settings.coverRefreshInterval,
          title: '封面刷新间隔',
          min: 5,
          max: 360,
          divisions: 71,
          format: _minutes,
        ),
        SettingsHeader('通知'),
        LiveAlertsTile(),
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
        DynamicColorTile(),
        _TvThemeNote(),
        SwitchSettingTile(setting: Settings.denseFollows, title: '关注页紧凑卡片', subtitle: '主播名和标题放在一行'),
        CardPresetTile(),
        FontsTile(),
        SliderSettingTile(setting: Settings.textScale, title: '文字大小', min: 0.85, max: 1.3, divisions: 9),
      ],
      SettingsGroup.playback => const [
        ChoiceSettingTile<QualityPreference>(setting: Settings.qualityWifi, title: '默认画质（Wi-Fi）', labels: _quality),
        ChoiceSettingTile<QualityPreference>(setting: Settings.qualityMobile, title: '默认画质（移动网络）', labels: _quality),
        SwitchSettingTile(
          setting: Settings.autoLowerQuality,
          title: '网络不稳时自动降低画质',
          subtitle: '一分钟内卡顿 3 次就降一档；手动选过画质后不再自动调整',
        ),
        PlaybackOutputTiles(),
        ChoiceSettingTile<VideoFit>(
          setting: Settings.videoFit,
          title: '画面比例',
          labels: {VideoFit.contain: '适应', VideoFit.cover: '填充（裁切）', VideoFit.fill: '拉伸'},
        ),
        SwitchSettingTile(setting: Settings.fullScreenDefault, title: '进入直播间自动全屏'),
        SwitchSettingTile(
          setting: Settings.switchRoomGesture,
          title: '竖屏全屏上下滑切换直播间',
          subtitle: '上滑下一个、下滑上一个；开启后竖屏全屏里不再上下滑调亮度和音量',
        ),
        SettingsHeader('竖屏直播'),
        SwitchSettingTile(
          setting: Settings.portraitAdaptation,
          title: '竖屏直播适配',
          subtitle: '自动识别竖屏直播，手机上用竖屏全屏和可拖动的信息面板',
        ),
        ChoiceSettingTile<PortraitFullscreenPolicy>(
          setting: Settings.portraitFullscreenPolicy,
          title: '全屏方向',
          labels: {
            PortraitFullscreenPolicy.followSource: '跟随画面（竖屏直播竖着全屏）',
            PortraitFullscreenPolicy.followSystem: '跟随手机方向',
            PortraitFullscreenPolicy.landscape: '总是横屏',
          },
        ),
        ChoiceSettingTile<PortraitFit>(
          setting: Settings.portraitFit,
          title: '竖屏全屏画面',
          labels: {PortraitFit.contain: '完整显示', PortraitFit.cover: '铺满屏幕（裁掉边缘）'},
        ),
        ChoiceSettingTile<PortraitDanmakuArea>(
          setting: Settings.portraitDanmakuArea,
          title: '竖屏全屏弹幕区域',
          labels: {
            PortraitDanmakuArea.followGlobal: '跟随弹幕设置',
            PortraitDanmakuArea.upperQuarter: '只在上方四分之一',
            PortraitDanmakuArea.reduced: '减半',
            PortraitDanmakuArea.hidden: '不显示',
          },
        ),
        SwitchSettingTile(
          setting: Settings.rememberPortraitOverride,
          title: '记住每个直播间的画面方向',
          subtitle: '在直播间手动选的“按竖屏/横屏处理”下次进房仍然生效',
        ),
        SwitchSettingTile(setting: Settings.backgroundPlay, title: '后台播放', subtitle: '离开应用后继续播放声音'),
        SettingsHeader('助眠'),
        SwitchSettingTile(setting: Settings.asmrSleepMode, title: '助眠模式', subtitle: '进入直播间自动只播声音并开始定时关闭；恢复画面时取消这次定时'),
        SliderSettingTile(
          setting: Settings.asmrSleepMinutes,
          title: '助眠定时',
          min: 5,
          max: 180,
          divisions: 35,
          format: _minutes,
        ),
        SystemSettingTiles(SystemSettingsSection.playback),
        SliderSettingTile(
          setting: Settings.defaultMobileVolume,
          title: '手机默认音量',
          min: 0,
          max: 1,
          divisions: 20,
          format: _percent,
        ),
      ],
      SettingsGroup.danmaku => const [DanmakuSettingsTiles(), PipDanmakuTiles()],
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
      SettingsGroup.recording => const [RecordSettingsTiles()],
      SettingsGroup.accounts => [
        ListTile(
          title: const Text('首页平台'),
          subtitle: const Text('显示哪些平台、顺序和发现页默认打开的平台'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/me/platforms'),
        ),
        ListTile(
          title: const Text('观众数口径'),
          subtitle: const Text('卡片显示热度还是在线人数，以及各平台数字的含义'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/me/audience'),
        ),
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

/// principles §5.3: TV mode has only dark and pure black.
class _TvThemeNote extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => TvScope.of(context).enabled
      ? const ListTile(leading: Icon(Icons.tv), title: Text('电视模式下只用深色'), subtitle: Text('纯黑背景开关仍然有效'))
      : const SizedBox.shrink();
}

String _integer(double value) => value.round().toString();
String _minutes(double value) => '${value.round()} 分钟';
String _percent(double value) => '${(value * 100).round()}%';
String _historyLimit(double value) => value.round() == 0 ? '不限' : '${value.round()} 条';

/// F-SET-05, F-SET-06: volume defaults and the decoding and output options
/// of this device; each platform lists its own decoders and outputs.
class PlaybackOutputTiles extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final android = Platform.isAndroid;
    final windows = Platform.isWindows;
    final touch = android || Platform.isIOS;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHeader('音量'),
        const SwitchSettingTile(setting: Settings.globalMute, title: '进入直播间时静音', subtitle: '所有直播间都从静音开始'),
        SliderSettingTile(
          setting: touch ? Settings.defaultMobileVolume : Settings.defaultDesktopVolume,
          title: touch ? '默认音量' : '默认音量（没有记住音量的直播间）',
          min: 0,
          max: 1,
          divisions: 20,
          format: (value) => '${(value * 100).round()}%',
        ),
        const SettingsHeader('解码与输出'),
        const SwitchSettingTile(setting: Settings.hardwareDecoding, title: '硬件解码', subtitle: '画面异常时关闭试试'),
        ChoiceSettingTile<String>(
          setting: Settings.hardwareDecoder,
          title: '硬件解码方式',
          labels: {
            'auto-safe': '自动',
            if (android) ...{'mediacodec': 'MediaCodec', 'mediacodec-copy': 'MediaCodec（复制）'},
            if (windows) ...{'d3d11va': 'D3D11', 'd3d11va-copy': 'D3D11（复制）', 'dxva2': 'DXVA2', 'nvdec': 'NVDEC（英伟达）'},
            if (!android) 'vulkan': 'Vulkan',
          },
        ),
        if (android)
          const SwitchSettingTile(setting: Settings.androidCompatibility, title: '兼容模式', subtitle: '部分机型黑屏、花屏或卡住时打开'),
        const SwitchSettingTile(setting: Settings.lowLatency, title: '低延迟', subtitle: '缓冲更少、延迟更低，网络差时更容易卡'),
        ChoiceSettingTile<String>(
          setting: Settings.audioOutput,
          title: '音频输出',
          labels: {
            '': '自动',
            if (android) ...{'aaudio': 'AAudio', 'opensles': 'OpenSL ES', 'audiotrack': 'AudioTrack'},
            if (windows) ...{'wasapi': 'WASAPI', 'openal': 'OpenAL'},
            if (!android && !windows) ...{'pulse': 'PulseAudio', 'pipewire': 'PipeWire', 'alsa': 'ALSA'},
          },
        ),
      ],
    );
  }
}

/// 动态取色 (F-SET-01): Android 12+ follows the wallpaper, Windows the system
/// accent colour; hidden elsewhere.
class DynamicColorTile extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    if (Platform.isWindows) {
      return const SwitchSettingTile(setting: Settings.dynamicColor, title: '跟随系统强调色', subtitle: '主题色改用 Windows 的强调色');
    }
    if (Platform.isAndroid) {
      return const SwitchSettingTile(
        setting: Settings.dynamicColor,
        title: '跟随壁纸取色',
        subtitle: 'Android 12 及以上，主题色取自壁纸',
      );
    }
    return const SizedBox.shrink();
  }
}

/// F-SET-03: the density of discover and search cards on this kind of
/// device (phones and desktops keep their own, as 3.x did).
class CardPresetTile extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final touch = Platform.isAndroid || Platform.isIOS;
    // 3.x's 详细 and 自定义 show as the standard two lines.
    return SettingBuilder<CardPreset>(
      setting: touch ? Settings.cardPresetMobile : Settings.cardPresetDesktop,
      builder: (context, value, set) => SwitchListTile(
        title: Text(touch ? '发现和搜索用紧凑卡片（手机）' : '发现和搜索用紧凑卡片（桌面）'),
        subtitle: const Text('主播名和标题放在一行'),
        value: value == CardPreset.compact,
        onChanged: (compact) => set(compact ? CardPreset.compact : CardPreset.normal),
      ),
    );
  }
}

/// 字体 (F-SET-01, F-DM-06).
class FontsTile extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => ListTile(
    title: const Text('字体'),
    subtitle: const Text('下载开源字体，用作界面或弹幕字体'),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => context.go('/me/fonts'),
  );
}
