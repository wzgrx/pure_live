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
import 'package:pure_live_app/i18n/strings.g.dart';

/// Settings groups of principles §4.4. Groups whose features are not in the
/// preview yet say so instead of showing dead switches.
enum SettingsGroup {
  general(Icons.tune),
  appearance(Icons.palette_outlined),
  playback(Icons.play_circle_outline),
  danmaku(Icons.subtitles_outlined),
  recording(Icons.fiber_manual_record_outlined),
  accounts(Icons.account_circle_outlined),
  network(Icons.lan_outlined),
  data(Icons.cloud_sync_outlined);

  new(this.icon);

  final IconData icon;

  /// The group's name in the interface language.
  String get label => switch (this) {
    general => t.settings.group.general,
    appearance => t.app.appearance,
    playback => t.settings.group.playback,
    danmaku => t.settings.group.danmaku,
    recording => t.settings.group.recording,
    accounts => t.settings.group.accounts,
    network => t.settings.group.network,
    data => t.settings.group.data,
  };
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
        appBar: AppBar(title: Text(t.app.settings)),
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

Map<QualityPreference, String> get _quality => {
  QualityPreference.original: t.quality.original,
  QualityPreference.bluRay8M: t.quality.bluRay8M,
  QualityPreference.bluRay4M: t.quality.bluRay4M,
  QualityPreference.superHigh: t.quality.superHigh,
  QualityPreference.smooth: t.quality.smooth,
};

/// The tiles of one group.
class SettingsGroupBody extends StatelessWidget {
  const new({required this.group, super.key});

  final SettingsGroup group;

  @override
  Widget build(BuildContext context) => ListView(
    children: switch (group) {
      SettingsGroup.general => [
        const LanguageTile(),
        ChoiceSettingTile<StartPage>(
          setting: Settings.startPage,
          title: t.settings.general.startPage,
          labels: {StartPage.follows: t.app.tabs.follows, StartPage.discover: t.app.tabs.discover},
        ),
        SwitchSettingTile(setting: Settings.screenKeepOn, title: t.settings.general.keepScreenOn),
        ChoiceSettingTile<RefreshRateMode>(
          setting: Settings.refreshRateMode,
          title: t.settings.general.refreshRate,
          labels: {
            RefreshRateMode.powerSaving: t.settings.general.refreshPowerSaving,
            RefreshRateMode.balanced: t.settings.general.refreshBalanced,
            RefreshRateMode.performance: t.settings.general.refreshHighest,
          },
        ),
        SwitchSettingTile(setting: Settings.autoCheckUpdate, title: t.settings.general.autoCheckUpdate),
        const ClipboardRecognitionTile(),
        const SystemSettingTiles(SystemSettingsSection.general),
        SettingsHeader(t.settings.general.tv),
        ChoiceSettingTile<TvMode>(
          setting: Settings.tvMode,
          title: t.settings.general.tvMode,
          labels: {TvMode.auto: t.settings.general.tvModeAuto, TvMode.on: t.common.on, TvMode.off: t.common.off},
        ),
        SwitchSettingTile(
          setting: Settings.tvPerformanceMode,
          title: t.settings.general.tvFocusOutline,
          subtitle: t.settings.general.tvFocusOutlineSubtitle,
        ),
        SettingsHeader(t.settings.general.followRefresh),
        SwitchSettingTile(setting: Settings.autoRefreshFollows, title: t.settings.general.autoRefreshFollows),
        SwitchSettingTile(setting: Settings.refreshFollowsOnResume, title: t.settings.general.refreshOnResume),
        SliderSettingTile(
          setting: Settings.autoRefreshInterval,
          title: t.settings.general.refreshInterval,
          // F-FAV-04: 3.x offered 5 minutes to 6 hours.
          min: 5,
          max: 360,
          divisions: 71,
          format: _minutes,
        ),
        SliderSettingTile(
          setting: Settings.maxConcurrentRefresh,
          title: t.settings.general.maxConcurrentRefresh,
          min: 1,
          max: 16,
          divisions: 15,
          format: _integer,
        ),
        // F-FAV-04: covers of live cards downloaded again on a timer.
        SwitchSettingTile(
          setting: Settings.autoRefreshCovers,
          title: t.settings.general.refreshCovers,
          subtitle: t.settings.general.refreshCoversSubtitle,
        ),
        SliderSettingTile(
          setting: Settings.coverRefreshInterval,
          title: t.settings.general.coverInterval,
          min: 5,
          max: 360,
          divisions: 71,
          format: _minutes,
        ),
        SettingsHeader(t.settings.general.notifications),
        const LiveAlertsTile(),
      ],
      SettingsGroup.appearance => [
        ChoiceSettingTile<AppThemeMode>(
          setting: Settings.themeMode,
          title: t.settings.appearance.theme,
          labels: {
            AppThemeMode.system: t.app.themeSystem,
            AppThemeMode.light: t.app.themeLight,
            AppThemeMode.dark: t.app.themeDark,
          },
        ),
        SwitchSettingTile(setting: Settings.pureBlack, title: t.app.themeBlack, subtitle: t.me.pureBlackSubtitle),
        const DynamicColorTile(),
        const _TvThemeNote(),
        SwitchSettingTile(
          setting: Settings.denseFollows,
          title: t.me.denseFollows,
          subtitle: t.settings.appearance.denseSubtitle,
        ),
        const CardPresetTile(),
        const FontsTile(),
        SliderSettingTile(
          setting: Settings.textScale,
          title: t.settings.appearance.textSize,
          min: 0.85,
          max: 1.3,
          divisions: 9,
        ),
      ],
      SettingsGroup.playback => [
        ChoiceSettingTile<QualityPreference>(
          setting: Settings.qualityWifi,
          title: t.settings.playback.qualityWifi,
          labels: _quality,
        ),
        ChoiceSettingTile<QualityPreference>(
          setting: Settings.qualityMobile,
          title: t.settings.playback.qualityMobile,
          labels: _quality,
        ),
        SwitchSettingTile(
          setting: Settings.autoLowerQuality,
          title: t.settings.playback.autoLower,
          subtitle: t.settings.playback.autoLowerSubtitle,
        ),
        const PlaybackOutputTiles(),
        ChoiceSettingTile<VideoFit>(
          setting: Settings.videoFit,
          title: t.room.aspect,
          labels: {
            VideoFit.contain: t.room.fit.contain,
            VideoFit.cover: t.settings.playback.fitCover,
            VideoFit.fill: t.room.fit.fill,
          },
        ),
        SwitchSettingTile(setting: Settings.fullScreenDefault, title: t.settings.playback.autoFullscreen),
        SwitchSettingTile(
          setting: Settings.switchRoomGesture,
          title: t.settings.playback.swipeRooms,
          subtitle: t.settings.playback.swipeRoomsSubtitle,
        ),
        SettingsHeader(t.settings.playback.portrait),
        SwitchSettingTile(
          setting: Settings.portraitAdaptation,
          title: t.settings.playback.portraitAdaptation,
          subtitle: t.settings.playback.portraitAdaptationSubtitle,
        ),
        ChoiceSettingTile<PortraitFullscreenPolicy>(
          setting: Settings.portraitFullscreenPolicy,
          title: t.settings.playback.fullscreenOrientation,
          labels: {
            PortraitFullscreenPolicy.followSource: t.settings.playback.orientationSource,
            PortraitFullscreenPolicy.followSystem: t.settings.playback.orientationSystem,
            PortraitFullscreenPolicy.landscape: t.settings.playback.orientationLandscape,
          },
        ),
        ChoiceSettingTile<PortraitFit>(
          setting: Settings.portraitFit,
          title: t.settings.playback.portraitFit,
          labels: {
            PortraitFit.contain: t.settings.playback.portraitFitContain,
            PortraitFit.cover: t.settings.playback.portraitFitCover,
          },
        ),
        ChoiceSettingTile<PortraitDanmakuArea>(
          setting: Settings.portraitDanmakuArea,
          title: t.settings.playback.portraitDanmaku,
          labels: {
            PortraitDanmakuArea.followGlobal: t.settings.playback.danmakuFollow,
            PortraitDanmakuArea.upperQuarter: t.settings.playback.danmakuUpperQuarter,
            PortraitDanmakuArea.reduced: t.settings.playback.danmakuHalf,
            PortraitDanmakuArea.hidden: t.settings.playback.danmakuHidden,
          },
        ),
        SwitchSettingTile(
          setting: Settings.rememberPortraitOverride,
          title: t.settings.playback.rememberOrientation,
          subtitle: t.settings.playback.rememberOrientationSubtitle,
        ),
        SwitchSettingTile(
          setting: Settings.backgroundPlay,
          title: t.settings.playback.background,
          subtitle: t.settings.playback.backgroundSubtitle,
        ),
        SettingsHeader(t.settings.playback.sleep),
        SwitchSettingTile(
          setting: Settings.asmrSleepMode,
          title: t.settings.playback.sleepMode,
          subtitle: t.settings.playback.sleepModeSubtitle,
        ),
        SliderSettingTile(
          setting: Settings.asmrSleepMinutes,
          title: t.settings.playback.sleepMinutes,
          min: 5,
          max: 180,
          divisions: 35,
          format: _minutes,
        ),
        const SystemSettingTiles(SystemSettingsSection.playback),
        SliderSettingTile(
          setting: Settings.defaultMobileVolume,
          title: t.settings.playback.phoneVolume,
          min: 0,
          max: 1,
          divisions: 20,
          format: _percent,
        ),
      ],
      SettingsGroup.danmaku => const [DanmakuSettingsTiles(), PipDanmakuTiles()],
      SettingsGroup.data => [
        SliderSettingTile(
          setting: Settings.historyLimit,
          title: t.settings.data.historyLimit,
          min: 0,
          max: 500,
          divisions: 50,
          format: _historyLimit,
        ),
        const DataSyncTiles(),
        const CacheTile(),
      ],
      SettingsGroup.recording => const [RecordSettingsTiles()],
      SettingsGroup.accounts => [
        ListTile(
          title: Text(t.settings.accounts.platforms),
          subtitle: Text(t.settings.accounts.platformsSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/me/platforms'),
        ),
        ListTile(
          title: Text(t.settings.accounts.audience),
          subtitle: Text(t.settings.accounts.audienceSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/me/audience'),
        ),
        ListTile(
          title: Text(t.app.accounts),
          subtitle: Text(t.settings.accounts.accountsSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go('/me/accounts'),
        ),
      ],
      SettingsGroup.network => const [NetworkSettings()],
    },
  );
}

/// 语言 (F-APP-06): follow the system, or Simplified Chinese, Traditional
/// Chinese or English; stored once in [Settings.locale]. Each language shows
/// its own name.
class LanguageTile extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => ChoiceSettingTile<String>(
    setting: Settings.locale,
    title: t.settings.language,
    labels: {
      'system': t.settings.languageSystem,
      for (final tag in const ['zh-Hans', 'zh-Hant', 'en']) tag: t.settings.languageNames[tag] ?? tag,
    },
  );
}

/// principles §5.3: TV mode has only dark and pure black.
class _TvThemeNote extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => TvScope.of(context).enabled
      ? ListTile(
          leading: const Icon(Icons.tv),
          title: Text(t.settings.tvDarkOnly),
          subtitle: Text(t.settings.tvDarkOnlySubtitle),
        )
      : const SizedBox.shrink();
}

String _integer(double value) => value.round().toString();
String _minutes(double value) => t.common.minutes(n: value.round());
String _percent(double value) => '${(value * 100).round()}%';
String _historyLimit(double value) =>
    value.round() == 0 ? t.common.unlimited : t.settings.historyEntries(n: value.round());

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
        SettingsHeader(t.settings.output.volume),
        SwitchSettingTile(
          setting: Settings.globalMute,
          title: t.settings.output.startMuted,
          subtitle: t.settings.output.startMutedSubtitle,
        ),
        SliderSettingTile(
          setting: touch ? Settings.defaultMobileVolume : Settings.defaultDesktopVolume,
          title: touch ? t.settings.output.defaultVolume : t.settings.output.defaultVolumeDesktop,
          min: 0,
          max: 1,
          divisions: 20,
          format: (value) => '${(value * 100).round()}%',
        ),
        SettingsHeader(t.settings.output.decoding),
        SwitchSettingTile(
          setting: Settings.hardwareDecoding,
          title: t.settings.output.hardwareDecoding,
          subtitle: t.settings.output.hardwareDecodingSubtitle,
        ),
        ChoiceSettingTile<String>(
          setting: Settings.hardwareDecoder,
          title: t.settings.output.decoder,
          labels: {
            'auto-safe': t.common.auto,
            if (android) ...{'mediacodec': 'MediaCodec', 'mediacodec-copy': t.settings.output.mediacodecCopy},
            if (windows) ...{
              'd3d11va': 'D3D11',
              'd3d11va-copy': t.settings.output.d3d11Copy,
              'dxva2': 'DXVA2',
              'nvdec': t.settings.output.nvdec,
            },
            if (!android) 'vulkan': 'Vulkan',
          },
        ),
        if (android)
          SwitchSettingTile(
            setting: Settings.androidCompatibility,
            title: t.settings.output.compatibility,
            subtitle: t.settings.output.compatibilitySubtitle,
          ),
        SwitchSettingTile(
          setting: Settings.lowLatency,
          title: t.settings.output.lowLatency,
          subtitle: t.settings.output.lowLatencySubtitle,
        ),
        ChoiceSettingTile<String>(
          setting: Settings.audioOutput,
          title: t.settings.output.audio,
          labels: {
            '': t.common.auto,
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
      return SwitchSettingTile(
        setting: Settings.dynamicColor,
        title: t.settings.appearance.accentColor,
        subtitle: t.settings.appearance.accentColorSubtitle,
      );
    }
    if (Platform.isAndroid) {
      return SwitchSettingTile(
        setting: Settings.dynamicColor,
        title: t.settings.appearance.wallpaperColor,
        subtitle: t.settings.appearance.wallpaperColorSubtitle,
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
        title: Text(touch ? t.settings.appearance.compactCardsPhone : t.settings.appearance.compactCardsDesktop),
        subtitle: Text(t.settings.appearance.denseSubtitle),
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
    title: Text(t.fonts.title),
    subtitle: Text(t.settings.appearance.fontsSubtitle),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => context.go('/me/fonts'),
  );
}
