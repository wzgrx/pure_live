import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/home/home_menu.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/settings/appearance_pages.dart';
import 'package:pure_live/pages/settings/settings_catalog.dart';
import 'package:pure_live/pages/settings/settings_dialogs.dart';
import 'package:pure_live/pages/settings/settings_model.dart';
import 'package:pure_live/pages/settings/settings_tiles.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// The three expert mpv options.
enum MpvOptionKind {
  /// `vo`.
  video,

  /// `ao`.
  audio,

  /// `hwdec`.
  decoder,
}

// 3.x's readable names (mpv_option_labels.dart): key → (Chinese, English).
const Map<String, (String, String)> _mpvLabels = {
  'gpu': ('GPU', 'GPU'),
  'gpu-next': ('GPU Next', 'GPU Next'),
  'libmpv': ('libmpv（Flutter 纹理）', 'libmpv (Flutter texture)'),
  'direct3d': ('Direct3D', 'Direct3D'),
  'sdl': ('SDL', 'SDL'),
  'mediacodec_embed': ('MediaCodec Embed', 'MediaCodec Embed'),
  'vaapi': ('VA-API', 'VA-API'),
  'vdpau': ('VDPAU', 'VDPAU'),
  'dmabuf-wayland': ('DMABUF Wayland', 'DMABUF Wayland'),
  'x11': ('X11', 'X11'),
  'xv': ('XVideo', 'XVideo'),
  'null': ('不输出', 'No output'),
  'auto': ('自动选择', 'Auto'),
  'wasapi': ('WASAPI', 'WASAPI'),
  'directsound': ('DirectSound', 'DirectSound'),
  'winmm': ('WinMM（旧版接口）', 'WinMM (legacy API)'),
  'audiotrack': ('AudioTrack', 'AudioTrack'),
  'aaudio': ('AAudio（Android 8.0+）', 'AAudio (Android 8.0+)'),
  'opensles': ('OpenSL ES', 'OpenSL ES'),
  'audiounit': ('AudioUnit', 'AudioUnit'),
  'coreaudio': ('CoreAudio', 'CoreAudio'),
  'pulse': ('PulseAudio', 'PulseAudio'),
  'pipewire': ('PipeWire', 'PipeWire'),
  'alsa': ('ALSA', 'ALSA'),
  'oss': ('OSS', 'OSS'),
  'jack': ('JACK（低延迟）', 'JACK (low latency)'),
  'pcm': ('PCM', 'PCM'),
  'openal': ('OpenAL', 'OpenAL'),
  'libao': ('libao', 'libao'),
  'auto-safe': ('启用最佳解码器', 'Best decoder'),
  'auto-copy': ('启用带拷贝功能的最佳解码器', 'Best decoder with copy-back'),
  'yes': ('强制硬件解码', 'Force hardware decoding'),
  'no': ('关闭（软件解码）', 'Off (software decoding)'),
  'd3d11va': ('DirectX 11', 'DirectX 11'),
  'd3d11va-copy': ('DirectX 11（非直通）', 'DirectX 11 (copy-back)'),
  'dxva2': ('DXVA2', 'DXVA2'),
  'dxva2-copy': ('DXVA2（非直通）', 'DXVA2 (copy-back)'),
  'nvdec': ('NVDEC（NVIDIA）', 'NVDEC (NVIDIA)'),
  'nvdec-copy': ('NVDEC（NVIDIA，非直通）', 'NVDEC (NVIDIA, copy-back)'),
  'cuda': ('CUDA（NVIDIA，已过时）', 'CUDA (NVIDIA, deprecated)'),
  'cuda-copy': ('CUDA（NVIDIA，已过时，非直通）', 'CUDA (NVIDIA, deprecated, copy-back)'),
  'mediacodec': ('MediaCodec', 'MediaCodec'),
  'mediacodec-copy': ('MediaCodec（非直通）', 'MediaCodec (copy-back)'),
  'videotoolbox': ('VideoToolbox', 'VideoToolbox'),
  'videotoolbox-copy': ('VideoToolbox（非直通）', 'VideoToolbox (copy-back)'),
  'vaapi-copy': ('VA-API（非直通）', 'VA-API (copy-back)'),
  'vdpau-copy': ('VDPAU（非直通）', 'VDPAU (copy-back)'),
  'drm': ('DRM', 'DRM'),
  'drm-copy': ('DRM（非直通）', 'DRM (copy-back)'),
  'vulkan': ('Vulkan（实验性）', 'Vulkan (experimental)'),
  'vulkan-copy': ('Vulkan（实验性，非直通）', 'Vulkan (experimental, copy-back)'),
  'rkmpp': ('Rockchip MPP', 'Rockchip MPP'),
};

/// The options that make sense on [platform] (3.x offered every platform's
/// drivers everywhere, marked "Windows only" and so on).
List<String> mpvOptionsFor(MpvOptionKind kind, TargetPlatform platform) => switch ((kind, platform)) {
  (MpvOptionKind.video, TargetPlatform.windows) => ['gpu', 'gpu-next', 'direct3d', 'sdl', 'libmpv', 'null'],
  (MpvOptionKind.video, TargetPlatform.android) => ['gpu', 'gpu-next', 'mediacodec_embed', 'libmpv', 'null'],
  (MpvOptionKind.video, TargetPlatform.iOS) => ['libmpv'],
  (MpvOptionKind.video, TargetPlatform.macOS) => ['gpu', 'gpu-next', 'libmpv', 'null'],
  (MpvOptionKind.video, _) => [
    'gpu', 'gpu-next', 'xv', 'x11', 'vdpau', 'dmabuf-wayland', 'vaapi', 'sdl', 'libmpv', 'null', //
  ],
  (MpvOptionKind.audio, TargetPlatform.windows) => [
    'auto', 'wasapi', 'directsound', 'winmm', 'sdl', 'openal', 'pcm', 'null', //
  ],
  (MpvOptionKind.audio, TargetPlatform.android) => ['auto', 'audiotrack', 'aaudio', 'opensles', 'null'],
  (MpvOptionKind.audio, TargetPlatform.iOS) => ['auto', 'audiounit', 'null'],
  (MpvOptionKind.audio, TargetPlatform.macOS) => ['auto', 'coreaudio', 'jack', 'openal', 'null'],
  (MpvOptionKind.audio, _) => [
    'auto', 'pulse', 'pipewire', 'alsa', 'oss', 'jack', 'sdl', 'openal', 'libao', 'pcm', 'null', //
  ],
  (MpvOptionKind.decoder, TargetPlatform.windows) => [
    'auto', 'auto-safe', 'auto-copy', 'yes', 'no', 'd3d11va', 'd3d11va-copy', 'dxva2', 'dxva2-copy', //
    'nvdec', 'nvdec-copy', 'cuda', 'cuda-copy', 'vulkan', 'vulkan-copy',
  ],
  (MpvOptionKind.decoder, TargetPlatform.android) => [
    'auto', 'auto-safe', 'auto-copy', 'yes', 'no', 'mediacodec', 'mediacodec-copy', 'vulkan', 'vulkan-copy', //
    'rkmpp',
  ],
  (MpvOptionKind.decoder, TargetPlatform.iOS || TargetPlatform.macOS) => [
    'auto', 'auto-safe', 'auto-copy', 'no', 'videotoolbox', 'videotoolbox-copy', //
  ],
  (MpvOptionKind.decoder, _) => [
    'auto', 'auto-safe', 'auto-copy', 'yes', 'no', 'vaapi', 'vaapi-copy', 'vdpau', 'vdpau-copy', 'nvdec', //
    'nvdec-copy', 'cuda', 'cuda-copy', 'drm', 'drm-copy', 'vulkan', 'vulkan-copy', 'rkmpp',
  ],
};

/// The readable name of an mpv option.
String mpvOptionLabel(String key) {
  final names = _mpvLabels[key];
  if (names == null) return key;
  final label = currentStrings?.language == AppLanguage.en ? names.$2 : names.$1;
  return label == key ? key : '$label · $key';
}

/// One expert mpv option; usable only with "custom output" on.
class MpvOptionTile extends StatelessWidget {
  /// Creates the row.
  const new({required this.entry, required this.kind, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  /// Which option.
  final MpvOptionKind kind;

  @override
  Widget build(BuildContext context) {
    final (setting, icon) = switch (kind) {
      MpvOptionKind.video => (Settings.videoOutputDriver, Remix.tv_line),
      MpvOptionKind.audio => (Settings.audioOutputDriver, Remix.volume_up_line),
      MpvOptionKind.decoder => (Settings.videoHardwareDecoder, Remix.cpu_line),
    };
    return SettingChoiceTile<String>(
      entry: entry,
      setting: setting,
      icon: icon,
      enabledBy: Settings.customPlayerOutput,
      hint: i18n('settings_mpv_hint'),
      options: () => [
        for (final key in mpvOptionsFor(kind, defaultTargetPlatform))
          (value: key, label: mpvOptionLabel(key), description: null),
      ],
    );
  }
}

/// Forget the remembered picture-in-picture window (Windows).
class PipPositionResetTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingActionTile(
    entry: entry,
    icon: Remix.drag_drop_line,
    onTap: () async {
      final confirmed = await showConfirmDialog(
        context: context,
        title: entry.titleText,
        message: i18n('windows_pip_reset_position_confirm'),
        confirmLabel: i18n('reset'),
      );
      if (!confirmed) return;
      final settings = ref.read(storeProvider).settings;
      for (final setting in <Setting<Object>>[
        Settings.windowsPipDisplayId,
        Settings.windowsPipWidth,
        Settings.windowsPipHeight,
        Settings.windowsPipX,
        Settings.windowsPipY,
      ]) {
        await settings.reset(setting);
      }
      AppNavigator.toast(i18n('windows_pip_reset_position_success'));
    },
  );
}

/// The picture-in-picture danmaku style (3.x `PipDanmakuSettingsPage`).
class PipDanmakuPage extends ConsumerWidget {
  /// Creates the page.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final originalColor = watchSetting(ref, Settings.pipDanmakuUseOriginalColor);
    final color = Color(watchSetting(ref, Settings.pipDanmakuColor));
    Widget slider(
      String id,
      String title,
      Setting<Object> setting,
      IconData icon,
      double min,
      double max,
      String Function(double) format, {
      double? step,
      BoolSetting? enabledBy,
    }) => CardTile(
      child: SettingSliderTile(
        entry: subEntry(id, title),
        setting: setting,
        icon: icon,
        min: min,
        max: max,
        step: step,
        format: format,
        enabledBy: enabledBy,
      ),
    );
    Widget toggle(String id, String title, BoolSetting setting, IconData icon, {String? description}) => CardTile(
      child: SettingToggleTile(
        entry: subEntry(id, title, description: description),
        setting: setting,
        icon: icon,
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n('pip_danmaku')),
        actions: [
          IconButton(
            key: const ValueKey('settings-pip-danmaku-reset'),
            tooltip: i18n('pip_danmaku_reset'),
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () async {
              final confirmed = await showConfirmDialog(
                context: context,
                title: i18n('pip_danmaku_reset'),
                message: i18n('pip_danmaku_reset_confirm'),
                confirmLabel: i18n('reset'),
              );
              if (!confirmed) return;
              final settings = ref.read(storeProvider).settings;
              for (final setting in pipDanmakuSettings) {
                await settings.reset(setting);
              }
              AppNavigator.toast(i18n('settings_reset_done'));
            },
          ),
        ],
      ),
      body: SettingsListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Text(i18n('pip_danmaku_desc'), style: Theme.of(context).textTheme.bodySmall),
          ),
          context.buildModernCard([
            toggle('pip_no_emoji', 'danmaku_no_emoji', Settings.pipDanmakuNoEmojiMode, Remix.emotion_unhappy_line),
            toggle('pip_auto_scale', 'pip_danmaku_auto_scale', Settings.pipDanmakuAutoScale, Remix.aspect_ratio_line),
            toggle(
              'pip_original_color',
              'pip_danmaku_original_color',
              Settings.pipDanmakuUseOriginalColor,
              Remix.palette_line,
            ),
            SettingsDependent(
              enabled: !originalColor,
              child: context.buildTile(
                icon: Remix.paint_brush_line,
                title: i18n('pip_danmaku_color'),
                subtitle: '#${colorHex(color).substring(2)}',
                trailing: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                ),
                onTap: () async {
                  final picked = await showColorDialog(
                    context: context,
                    title: i18n('pip_danmaku_color'),
                    current: color,
                  );
                  if (picked?.color case final chosen? when context.mounted) {
                    writeSetting(ref, Settings.pipDanmakuColor, chosen.toARGB32());
                  }
                },
              ),
            ),
          ]),
          const SizedBox(height: 16),
          context.buildModernCard([
            slider(
              'pip_size',
              'font_size',
              Settings.pipDanmakuFontSize,
              Remix.font_size_2,
              8,
              24,
              (v) => '${v.round()}',
              step: 1,
            ),
            slider(
              'pip_weight',
              'font_weight',
              Settings.pipDanmakuFontWeight,
              Remix.bold,
              100,
              900,
              (v) => '${v.round()}',
              step: 100,
            ),
            slider(
              'pip_speed',
              'speed',
              Settings.pipDanmakuSpeed,
              Remix.speed_line,
              20,
              400,
              (v) => '${v.round()}',
              step: 1,
            ),
            slider(
              'pip_opacity',
              'opacity',
              Settings.pipDanmakuOpacity,
              Remix.contrast_drop_line,
              0.1,
              1,
              (v) => '${(v * 100).round()}%',
              step: 0.05,
            ),
            slider(
              'pip_area',
              'danmaku_area',
              Settings.pipDanmakuArea,
              Remix.layout_top_line,
              0.1,
              1,
              (v) => '${(v * 100).round()}%',
              step: 0.05,
            ),
            slider(
              'pip_max_visible',
              'pip_danmaku_max_visible',
              Settings.pipDanmakuMaxVisibleCount,
              Remix.stack_line,
              1,
              20,
              (v) => '${v.round()}',
            ),
            slider(
              'pip_interval',
              'pip_danmaku_interval',
              Settings.pipDanmakuEmitInterval,
              Remix.timer_line,
              0.05,
              2,
              (v) => '${v.toStringAsFixed(2)} s',
              step: 0.05,
            ),
          ]),
          const SizedBox(height: 16),
          context.buildModernCard([
            toggle(
              'pip_auto_fps',
              'settings_danmaku_auto_fps',
              Settings.pipDanmakuAutoFps,
              Remix.speed_up_line,
              description: 'pip_danmaku_fps_policy_desc',
            ),
            slider(
              'pip_fps',
              'danmaku_fps',
              Settings.pipDanmakuFps,
              Remix.dashboard_3_line,
              15,
              240,
              (v) => '${v.round()} FPS',
            ),
          ]),
        ],
      ),
    );
  }
}

/// The platform opened first, chosen from the shown platforms with a filter
/// (3.x `PlatformSettingsPage`).
class PreferPlatformTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sites = ref.read(sitesProvider);
    final shown = [
      for (final id in watchSetting(ref, Settings.hotAreasList))
        if (sites.maybeOf(id) != null) id,
    ];
    final current = watchSetting(ref, Settings.preferPlatform);
    final choices = shown.isEmpty ? sites.ids : shown;
    return KeyedSubtree(
      key: entry.rowKey,
      child: context.buildTile(
        icon: Remix.star_line,
        title: entry.titleText,
        subtitle: entry.descriptionText,
        isLong: true,
        stackTrailingOnNarrow: true,
        trailing: SettingValueText(platformName(current, sites.maybeOf(current))),
        onTap: () async {
          final picked = await showDialog<String>(
            context: context,
            builder: (context) => _PlatformPicker(
              title: entry.titleText,
              ids: choices,
              names: {for (final id in choices) id: platformName(id, sites.maybeOf(id))},
              selected: current,
            ),
          );
          if (picked != null && context.mounted) writeSetting(ref, Settings.preferPlatform, picked);
        },
      ),
    );
  }
}

class _PlatformPicker extends StatefulWidget {
  const new({required this.title, required this.ids, required this.names, required this.selected});

  final String title;
  final List<String> ids;
  final Map<String, String> names;
  final String selected;

  @override
  State<_PlatformPicker> createState() => _PlatformPickerState();
}

class _PlatformPickerState extends State<_PlatformPicker> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final query = _filter.trim().toLowerCase();
    final visible = [
      for (final id in widget.ids)
        if (query.isEmpty || id.contains(query) || widget.names[id]!.toLowerCase().contains(query)) id,
    ];
    return SettingsDialogFrame(
      title: widget.title,
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel')))],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              onChanged: (value) => setState(() => _filter = value),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: i18n('prefer_platform_filter_hint'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (visible.isEmpty)
            Padding(padding: const EdgeInsets.all(16), child: Text(i18n('prefer_platform_filter_empty')))
          else
            RadioGroup<String>(
              groupValue: widget.selected,
              onChanged: (value) {
                if (value != null) Navigator.of(context).pop(value);
              },
              child: Column(
                children: [
                  for (final id in visible)
                    RadioListTile<String>(
                      key: ValueKey('settings-platform-$id'),
                      value: id,
                      secondary: PlatformLogo(id, size: 24),
                      title: Text(widget.names[id]!),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Platforms whose real online count is preferred, one switch each, with
/// what each platform reports (3.x `AudienceMetricSettingsPage`).
class AudiencePlatformsPage extends ConsumerWidget {
  /// Creates the page.
  const new({super.key});

  /// 3.x's list (platforms that report both figures).
  static const platforms = [
    'bilibili', 'douyu', 'huya', 'douyin', 'kuaishou', 'cc', 'twitch', 'soop', 'yy', 'acfun', 'picarto', //
    'twitcasting', 'missevan', 'inke', 'kilakila', 'xiaohongshu', 'niconico', 'weibo', 'looklive',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = watchSetting(ref, Settings.realOnlinePlatforms);
    final sites = ref.read(sitesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(i18n('audience_online_platforms'))),
      body: SettingsListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Text(i18n('audience_ranking_rule_desc'), style: Theme.of(context).textTheme.bodySmall),
          ),
          context.buildModernCard([
            for (final id in platforms)
              CardTile(
                key: ValueKey('settings-audience-$id'),
                child: SwitchListTile(
                  secondary: PlatformLogo(id, size: 24),
                  title: Text(platformName(id, sites.maybeOf(id))),
                  subtitle: Text(i18nOr('audience_${id}_detail', ''), style: context.textStyles.t12),
                  value: selected.contains(id),
                  onChanged: (on) => writeSetting(ref, Settings.realOnlinePlatforms, [
                    for (final value in selected)
                      if (value != id) value,
                    if (on) id,
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(i18n('audience_metric_fallback_desc'), style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

/// Languages of the Twitch directory (UPGRADES 8-3): none means every
/// language; 3.x's fixed Chinese + Korean filter is offered as a preset.
class TwitchLanguagesTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  /// Languages offered (Twitch's broadcaster language codes).
  static const languages = ['zh', 'en', 'ko', 'ja', 'es', 'pt', 'de', 'fr', 'ru', 'it', 'th', 'vi', 'id', 'tr', 'pl'];

  /// The name of a language code.
  static String languageName(String code) => i18nOr('settings_twitch_language_$code', code);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = watchSetting(ref, Settings.twitchLanguages);
    return KeyedSubtree(
      key: entry.rowKey,
      child: context.buildTile(
        icon: Remix.twitch_line,
        title: entry.titleText,
        subtitle: entry.descriptionText,
        isLong: true,
        stackTrailingOnNarrow: true,
        trailing: SettingValueText(
          selected.isEmpty ? i18n('settings_twitch_languages_all') : selected.map(languageName).join('、'),
        ),
        onTap: () async {
          final result = await showDialog<List<String>>(
            context: context,
            builder: (context) => _TwitchLanguagesDialog(initial: selected),
          );
          if (result != null && context.mounted) writeSetting(ref, Settings.twitchLanguages, result);
        },
      ),
    );
  }
}

class _TwitchLanguagesDialog extends StatefulWidget {
  const new({required this.initial});

  final List<String> initial;

  @override
  State<_TwitchLanguagesDialog> createState() => _TwitchLanguagesDialogState();
}

class _TwitchLanguagesDialogState extends State<_TwitchLanguagesDialog> {
  late final List<String> _selected = List.of(widget.initial);

  @override
  Widget build(BuildContext context) => SettingsDialogFrame(
    title: i18n('settings_twitch_languages'),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel'))),
      FilledButton(
        key: const ValueKey('settings-twitch-save'),
        onPressed: () => Navigator.of(context).pop(_selected),
        child: Text(i18n('confirm')),
      ),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(i18n('settings_twitch_languages_hint'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                key: const ValueKey('settings-twitch-all'),
                avatar: const Icon(Icons.public_rounded, size: 18),
                label: Text(i18n('settings_twitch_languages_all')),
                onPressed: () => setState(_selected.clear),
              ),
              ActionChip(
                key: const ValueKey('settings-twitch-legacy'),
                avatar: const Icon(Icons.history_rounded, size: 18),
                label: Text(i18n('settings_twitch_languages_legacy')),
                onPressed: () => setState(
                  () => _selected
                    ..clear()
                    ..addAll(Settings.twitchLegacyLanguages),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final code in TwitchLanguagesTile.languages)
                FilterChip(
                  key: ValueKey('settings-twitch-$code'),
                  label: Text(TwitchLanguagesTile.languageName(code)),
                  selected: _selected.contains(code),
                  onSelected: (on) => setState(() => on ? _selected.add(code) : _selected.remove(code)),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// One proxy's three settings.
enum ProxySettings {
  /// The requests of the app (lists, rooms, danmaku).
  app(Settings.enableAppProxy, Settings.appProxyHost, Settings.appProxyPort),

  /// The player's stream requests.
  player(Settings.enableProxy, Settings.proxyHost, Settings.proxyPort);

  new(this.enabled, this.host, this.port);

  /// On or off.
  final BoolSetting enabled;

  /// Host name or address.
  final StringSetting host;

  /// Port.
  final IntSetting port;
}

/// A proxy: a switch on the row, the address in a dialog (3.x put the
/// fields on the page, saved as typed, and accepted an empty host).
class ProxyTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, required this.proxy, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  /// Which proxy.
  final ProxySettings proxy;

  Future<bool> _edit(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(storeProvider).settings;
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (context) =>
          _ProxyDialog(title: entry.titleText, host: settings.get(proxy.host), port: settings.get(proxy.port)),
    );
    if (result == null) return false;
    await settings.setAll({proxy.host: result.$1, proxy.port: result.$2});
    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = watchSetting(ref, proxy.enabled);
    final host = watchSetting(ref, proxy.host);
    final port = watchSetting(ref, proxy.port);
    final address = host.trim().isEmpty ? i18n('settings_proxy_not_set') : '$host:$port';
    return KeyedSubtree(
      key: entry.rowKey,
      child: context.buildTile(
        icon: Remix.global_line,
        title: entry.titleText,
        subtitle: '${entry.descriptionText}\n${i18n('settings_proxy_address')}: $address',
        isLong: true,
        trailing: Switch(
          key: ValueKey('settings-proxy-${proxy.name}-switch'),
          value: enabled,
          onChanged: (on) async {
            if (on && host.trim().isEmpty && !await _edit(context, ref)) return;
            if (context.mounted) writeSetting(ref, proxy.enabled, on);
          },
        ),
        onTap: () => unawaited(_edit(context, ref)),
      ),
    );
  }
}

class _ProxyDialog extends StatefulWidget {
  const new({required this.title, required this.host, required this.port});

  final String title;
  final String host;
  final int port;

  @override
  State<_ProxyDialog> createState() => _ProxyDialogState();
}

class _ProxyDialogState extends State<_ProxyDialog> {
  late final _host = TextEditingController(text: widget.host);
  late final _port = TextEditingController(text: '${widget.port}');
  String? _hostError;
  String? _portError;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _save() {
    final host = _host.text.trim().replaceFirst(RegExp('^https?://'), '').replaceFirst(RegExp(r'/+$'), '');
    final port = int.tryParse(_port.text.trim());
    setState(() {
      _hostError = host.isEmpty || host.contains(RegExp(r'[\s/]')) ? i18n('settings_proxy_host_invalid') : null;
      _portError = port == null || port < 1 || port > 65535 ? i18n('proxy_port_invalid') : null;
    });
    if (_hostError == null && _portError == null) Navigator.of(context).pop((host, port!));
  }

  @override
  Widget build(BuildContext context) => SettingsDialogFrame(
    title: widget.title,
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel'))),
      FilledButton(key: const ValueKey('settings-proxy-save'), onPressed: _save, child: Text(i18n('save'))),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('settings-proxy-host'),
            controller: _host,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: i18n('proxy_address_label'),
              hintText: '127.0.0.1',
              errorText: _hostError,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('settings-proxy-port'),
            controller: _port,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: i18n('proxy_port_label'),
              hintText: '7897',
              errorText: _portError,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(i18n('settings_proxy_hint'), style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}

/// The home menus: drag to order, switch to show (3.x
/// `NavigationSettingsPage`).
class HomeMenusPage extends ConsumerWidget {
  /// Creates the page.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = HomeMenu.fromIds(watchSetting(ref, Settings.savedMenuIds));
    final order = [...shown, ...HomeMenu.values.where((menu) => !shown.contains(menu))];
    void save(List<HomeMenu> menus) => writeSetting(ref, Settings.savedMenuIds, [for (final menu in menus) menu.id]);
    return Scaffold(
      appBar: AppBar(title: Text(i18n('settings_home_menus'))),
      body: ListView(
        physics: const PureLiveScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Text(i18n('drag_menu_to_sort_tip'), style: Theme.of(context).textTheme.bodySmall),
          ),
          context.buildModernCard([
            ReorderableListView(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              physics: const NeverScrollableScrollPhysics(),
              onReorderItem: (from, to) {
                final next = List.of(order);
                final moved = next.removeAt(from);
                next.insert(to, moved);
                save([
                  for (final menu in next)
                    if (shown.contains(menu)) menu,
                ]);
              },
              children: [
                for (final (index, menu) in order.indexed)
                  ListTile(
                    key: ValueKey('settings-menu-${menu.id}'),
                    leading: Icon(menu.icon, color: Theme.of(context).colorScheme.primary),
                    title: Text(i18n(menu.titleKey)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: shown.contains(menu),
                          onChanged: (on) {
                            if (!on && shown.length == 1) {
                              AppNavigator.toast(i18n('at_least_one_menu_required'));
                              return;
                            }
                            save([
                              for (final item in order)
                                if (item == menu ? on : shown.contains(item)) item,
                            ]);
                          },
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle_rounded)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ]),
        ],
      ),
    );
  }
}

/// The window size at start (Windows): presets or a checked size (3.x
/// applied it to the window at once; the desktop shell, M12, reads it).
class WindowSizeTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = watchSetting(ref, Settings.windowWidth).round();
    final height = watchSetting(ref, Settings.windowHeight).round();
    return KeyedSubtree(
      key: entry.rowKey,
      child: context.buildTile(
        icon: Remix.aspect_ratio_line,
        title: entry.titleText,
        subtitle: entry.descriptionText,
        isLong: true,
        trailing: SettingValueText('$width × $height'),
        onTap: () async {
          final size = await showDialog<Size>(
            context: context,
            builder: (context) => _WindowSizeDialog(width: width, height: height),
          );
          if (size == null || !context.mounted) return;
          await ref.read(storeProvider).settings.setAll({
            Settings.windowWidth: size.width,
            Settings.windowHeight: size.height,
          });
          AppNavigator.toast(i18n('save_success'));
        },
      ),
    );
  }
}

class _WindowSizeDialog extends StatefulWidget {
  const new({required this.width, required this.height});

  final int width;
  final int height;

  @override
  State<_WindowSizeDialog> createState() => _WindowSizeDialogState();
}

class _WindowSizeDialogState extends State<_WindowSizeDialog> {
  late final _width = TextEditingController(text: '${widget.width}');
  late final _height = TextEditingController(text: '${widget.height}');
  String? _error;

  static const _presets = [(1080, 720), (1280, 720), (1600, 900), (1920, 1080), (2560, 1440)];

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  void _apply() {
    final width = int.tryParse(_width.text.trim());
    final height = int.tryParse(_height.text.trim());
    final maxSide = Settings.windowWidth.max!;
    if (width == null ||
        height == null ||
        width < Settings.windowWidth.min! ||
        height < Settings.windowHeight.min! ||
        width > maxSide ||
        height > maxSide) {
      setState(() => _error = i18n('window_size_out_of_range'));
      return;
    }
    Navigator.of(context).pop(Size(width.toDouble(), height.toDouble()));
  }

  Widget _field(TextEditingController controller, String label) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
    onChanged: (_) {
      if (_error != null) setState(() => _error = null);
    },
    decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
  );

  @override
  Widget build(BuildContext context) => SettingsDialogFrame(
    title: i18n('window_size'),
    actions: [
      TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(i18n('cancel'))),
      FilledButton(onPressed: _apply, child: Text(i18n('confirm'))),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (width, height) in _presets)
                ActionChip(
                  label: Text('$width × $height'),
                  onPressed: () => setState(() {
                    _width.text = '$width';
                    _height.text = '$height';
                    _error = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _field(_width, i18n('width'))),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('×')),
              Expanded(child: _field(_height, i18n('height'))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? i18n('window_size_range_hint'),
            style: context.textStyles.t12.copyWith(
              color: _error == null ? Theme.of(context).hintColor : Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
    ),
  );
}

/// The app's exit countdown (3.x `ExitSettingsController`'s stopwatch): runs
/// while `enableAutoShutDownTime` is on and restarts when it is switched on
/// or its length changes; at zero the app quits.
///
/// The app should [attach] it at start (3.x started it with the settings
/// service); the settings page attaches it too, so switching it on there
/// always starts it.
final class AutoExitTimer {
  new _();

  /// The one timer of the app.
  static final AutoExitTimer instance = AutoExitTimer._();

  /// Time left, or null when off.
  final ValueNotifier<Duration?> remaining = ValueNotifier(null);

  /// Quits the app (tests replace it).
  @visibleForTesting
  static void Function() quit = () {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) exit(0);
    unawaited(SystemNavigator.pop());
  };

  SettingsStore? _settings;
  StreamSubscription<Setting<Object>>? _changes;
  Timer? _ticker;
  DateTime? _deadline;

  /// Follows [settings]; a second call with the same store does nothing.
  void attach(SettingsStore settings) {
    if (identical(settings, _settings)) return;
    detach();
    _settings = settings;
    _changes = settings.changes.listen((setting) {
      if (setting.key == Settings.enableAutoShutDownTime.key || setting.key == Settings.autoShutDownTime.key) {
        _apply();
      }
    });
    _apply();
  }

  /// Stops following the store and the countdown.
  void detach() {
    unawaited(_changes?.cancel());
    _changes = null;
    _settings = null;
    _stop();
  }

  void _apply() {
    final settings = _settings;
    if (settings == null || !settings.get(Settings.enableAutoShutDownTime)) {
      _stop();
      return;
    }
    _deadline = DateTime.now().add(Duration(minutes: settings.get(Settings.autoShutDownTime)));
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _tick();
  }

  void _tick() {
    final deadline = _deadline;
    if (deadline == null) return;
    final left = deadline.difference(DateTime.now());
    if (left <= Duration.zero) {
      _stop();
      quit();
      return;
    }
    remaining.value = Duration(seconds: left.inSeconds);
  }

  void _stop() {
    _ticker?.cancel();
    _ticker = null;
    _deadline = null;
    remaining.value = null;
  }
}

/// "HH:MM:SS".
String formatCountdown(Duration duration) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(duration.inHours)}:${two(duration.inMinutes % 60)}:${two(duration.inSeconds % 60)}';
}

/// The exit countdown's switch, showing the time left while it runs.
class AutoExitTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = watchSetting(ref, Settings.enableAutoShutDownTime);
    return KeyedSubtree(
      key: entry.rowKey,
      child: ValueListenableBuilder<Duration?>(
        valueListenable: AutoExitTimer.instance.remaining,
        builder: (context, left, _) => context.buildSwitchTile(
          title: entry.titleText,
          subtitle: enabled && left != null
              ? '${i18n('remaining_time')}: ${formatCountdown(left)}'
              : entry.descriptionText,
          isLong: true,
          icon: Remix.timer_flash_line,
          value: enabled,
          onChanged: (on) => writeSetting(ref, Settings.enableAutoShutDownTime, on),
        ),
      ),
    );
  }
}
