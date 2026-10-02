import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_dialogs.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_tiles.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/display_mode.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

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
    'no', 'auto', 'auto-safe', 'yes', 'auto-copy', 'vulkan', 'vulkan-copy', 'mediacodec', 'mediacodec-copy', //
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

/// The readable name of an mpv option without its key (U.6c 驱动选项页);
/// "auto" of the decoder reads "启用任意可用解码器" (3.x).
String mpvOptionName(String key, {MpvOptionKind? kind}) {
  if (kind == MpvOptionKind.decoder && key == 'auto') {
    return currentStrings?.language == AppLanguage.en ? 'Any available decoder' : '启用任意可用解码器';
  }
  final names = _mpvLabels[key];
  if (names == null) return key;
  return currentStrings?.language == AppLanguage.en ? names.$2 : names.$1;
}

/// Forget the remembered mini window (computers).
class PipPositionResetTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingActionTile(
    entry: entry,
    icon: AppIcons.settingsPipReset,
    onTap: () async {
      final confirmed = await showConfirmDialog(
        context: context,
        title: entry.titleText,
        message: '${i18n('windows_pip_reset_position_confirm')}${i18n('settings_pip_reset_next')}',
        confirmLabel: i18n('reset'),
        destructive: true,
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

/// The platform opened first (3.x `PlatformSettingsPage`): its logo and
/// name on the row; the choice dialog with logos and a filter over the
/// platforms shown (U.6d d8, d9).
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
    String name(String id) => platformName(id, fallback: sites.maybeOf(id)?.name);
    return SettingsLinkRow(
      key: entry.rowKey,
      icon: AppIcons.settingsPreferPlatform,
      title: entry.titleText,
      subtitle: entry.descriptionText,
      valueWidget: PlatformLogo(current, size: 24),
      value: name(current),
      onTap: () async {
        final picked = await showAppDialog<String>(
          context: context,
          builder: (context) => _PlatformPicker(
            title: entry.titleText,
            ids: choices,
            names: {for (final id in choices) id: name(id)},
            selected: current,
          ),
        );
        if (picked != null && context.mounted) writeSetting(ref, Settings.preferPlatform, picked);
      },
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
      actions: const [DialogCancelButton()],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              key: const ValueKey('settings-platform-filter'),
              onChanged: (value) => setState(() => _filter = value),
              decoration: dialogFieldDecoration(
                context,
                hint: i18n('prefer_platform_filter_hint'),
              ).copyWith(prefixIcon: const Icon(AppIcons.search), isDense: true),
            ),
          ),
          const SizedBox(height: 8),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(i18n('prefer_platform_filter_empty'), textAlign: TextAlign.center),
            )
          else
            for (final id in visible)
              SettingsChoiceRow(
                key: ValueKey('settings-platform-$id'),
                leading: PlatformLogo(id, size: 24),
                label: widget.names[id]!,
                selected: id == widget.selected,
                onTap: () => Navigator.of(context).pop(id),
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
    return SettingsLinkRow(
      key: entry.rowKey,
      icon: AppIcons.settingsTwitchLanguages,
      title: entry.titleText,
      subtitle: entry.descriptionText,
      value: selected.isEmpty ? i18n('settings_twitch_languages_all') : selected.map(languageName).join('、'),
      onTap: () async {
        final result = await showAppDialog<List<String>>(
          context: context,
          builder: (context) => _TwitchLanguagesDialog(initial: selected),
        );
        if (result != null && context.mounted) writeSetting(ref, Settings.twitchLanguages, result);
      },
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
      const DialogCancelButton(),
      DialogActionButton(
        key: const ValueKey('settings-twitch-save'),
        label: i18n('confirm'),
        onPressed: () => Navigator.of(context).pop(_selected),
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
                avatar: const Icon(AppIcons.allLanguages, size: 18),
                label: Text(i18n('settings_twitch_languages_all')),
                onPressed: () => setState(_selected.clear),
              ),
              ActionChip(
                key: const ValueKey('settings-twitch-legacy'),
                avatar: const Icon(AppIcons.legacyPreset, size: 18),
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
  app(Settings.enableAppProxy, Settings.appProxyHost, Settings.appProxyPort, AppIcons.settingsAppProxy),

  /// The player's stream requests.
  player(Settings.enableProxy, Settings.proxyHost, Settings.proxyPort, AppIcons.settingsStreamProxy);

  new(this.enabled, this.host, this.port, this.icon);

  /// On or off.
  final BoolSetting enabled;

  /// Host name or address.
  final StringSetting host;

  /// Port.
  final IntSetting port;

  /// The switch's icon (3.x `apps_line`, `video_line`).
  final IconData icon;
}

/// A proxy on the network page (3.x `NetworkProxySettingsPage`, U.6d d13):
/// the switch, then the address and port, which stay (greyed out) while it
/// is off; side by side 3:2 from 420 wide. Typed values are stored half a
/// second after the last key (3.x stored every key); a port outside
/// 1–65535 is shown in red and not stored.
class ProxyEditorTile extends ConsumerStatefulWidget {
  /// Creates the rows.
  const new({required this.entry, required this.proxy, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  /// Which proxy.
  final ProxySettings proxy;

  @override
  ConsumerState<ProxyEditorTile> createState() => _ProxyEditorTileState();
}

class _ProxyEditorTileState extends ConsumerState<ProxyEditorTile> {
  late final SettingsStore _settings = ref.read(storeProvider).settings;
  late final TextEditingController _host = TextEditingController(text: _settings.get(widget.proxy.host));
  late final TextEditingController _port = TextEditingController(text: '${_settings.get(widget.proxy.port)}');
  Timer? _save;
  String? _portError;

  @override
  void dispose() {
    _flush();
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  void _changed() {
    final port = int.tryParse(_port.text.trim());
    final error = port == null || port < 1 || port > 65535 ? i18n('proxy_port_invalid') : null;
    if (error != _portError) setState(() => _portError = error);
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 500), _flush);
  }

  void _flush() {
    final pending = _save;
    if (pending == null) return;
    pending.cancel();
    _save = null;
    final host = _host.text.trim();
    final port = int.tryParse(_port.text.trim());
    unawaited(
      _settings.setAll({
        widget.proxy.host: host,
        if (port != null && port >= 1 && port <= 65535) widget.proxy.port: port,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = watchSetting(ref, widget.proxy.enabled);
    final name = widget.proxy.name;
    Widget field(TextEditingController controller, String label, {required bool port}) => TextField(
      key: ValueKey('settings-proxy-$name-${port ? 'port' : 'host'}'),
      controller: controller,
      enabled: enabled,
      keyboardType: port ? TextInputType.number : TextInputType.url,
      inputFormatters: port ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)] : null,
      onChanged: (_) => _changed(),
      onSubmitted: (_) => _flush(),
      decoration: InputDecoration(
        labelText: label,
        hintText: port ? '7897' : '127.0.0.1',
        errorText: port ? _portError : null,
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
    );
    return Column(
      key: widget.entry.rowKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSwitchRow(
          key: ValueKey('settings-proxy-$name-switch'),
          icon: widget.proxy.icon,
          title: widget.entry.titleText,
          subtitle: widget.entry.descriptionText,
          value: enabled,
          onChanged: (on) => writeSetting(ref, widget.proxy.enabled, on),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Opacity(
            opacity: enabled ? 1 : 0.6,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final host = field(_host, i18n('proxy_address_label'), port: false);
                final port = field(_port, i18n('proxy_port_label'), port: true);
                if (constraints.maxWidth >= 420) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: host),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: port),
                    ],
                  );
                }
                return Column(mainAxisSize: MainAxisSize.min, children: [host, const SizedBox(height: 12), port]);
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// The window size at start (Windows; 3.x applied it to the window at
/// once): the size on the row; the dialog's presets (the current one
/// highlighted) and a checked size; "应用" sizes the window now (U.6d d7).
class WindowSizeTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = watchSetting(ref, Settings.windowWidth).round();
    final height = watchSetting(ref, Settings.windowHeight).round();
    return SettingsLinkRow(
      key: entry.rowKey,
      icon: AppIcons.settingsWindowSize,
      title: entry.titleText,
      subtitle: entry.descriptionText,
      value: '$width × $height',
      onTap: () async {
        final size = await showAppDialog<Size>(
          context: context,
          builder: (context) => _WindowSizeDialog(width: width, height: height),
        );
        if (size == null || !context.mounted) return;
        await ref.read(storeProvider).settings.setAll({
          Settings.windowWidth: size.width,
          Settings.windowHeight: size.height,
        });
        // The window takes the size at once (3.x), not only next start.
        final shell = DesktopShell.current;
        if (shell != null && !await shell.resize(size)) {
          AppNavigator.toast(i18n('window_size_apply_failed'));
          return;
        }
        AppNavigator.toast(i18n('save_success'));
      },
    );
  }
}

/// The smallest window size the dialog accepts: the stored setting's and
/// the window's own minimum, whichever is larger (U.13).
Size windowSizeMinimum() => Size(
  math.max(Settings.windowWidth.min!, DesktopShell.minimumSize.width),
  math.max(Settings.windowHeight.min!, DesktopShell.minimumSize.height),
);

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

  /// 3.x's presets; the default (1280 × 720) is marked.
  static const List<(int, int, String?)> _presets = [
    (1080, 720, null),
    (1280, 720, '720P'),
    (1600, 900, null),
    (1920, 1080, '1080P'),
    (2560, 1440, '2K'),
  ];

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  void _apply() {
    final width = int.tryParse(_width.text.trim());
    final height = int.tryParse(_height.text.trim());
    final minimum = windowSizeMinimum();
    final maxSide = Settings.windowWidth.max!;
    if (width == null ||
        height == null ||
        width < minimum.width ||
        height < minimum.height ||
        width > maxSide ||
        height > maxSide) {
      setState(() => _error = i18n('window_size_out_of_range'));
      return;
    }
    Navigator.of(context).pop(Size(width.toDouble(), height.toDouble()));
  }

  Widget _field(TextEditingController controller, String label, Key key) => TextField(
    key: key,
    controller: controller,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
    onChanged: (_) => setState(() => _error = null),
    onSubmitted: (_) => _apply(),
    decoration: dialogFieldDecoration(context, label: label).copyWith(isDense: true),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final minimum = windowSizeMinimum();
    final caption = (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontSize: 13,
      color: colors.onSurfaceVariant,
    );
    final defaultWidth = Settings.windowWidth.defaultValue.round();
    final defaultHeight = Settings.windowHeight.defaultValue.round();
    return SettingsDialogFrame(
      title: i18n('window_size'),
      actions: [
        const DialogCancelButton(),
        DialogActionButton(key: const ValueKey('settings-window-size-apply'), label: i18n('apply'), onPressed: _apply),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(i18n('preset_options'), style: caption),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (width, height, tag) in _presets)
                  ChoiceChip(
                    key: ValueKey('settings-window-size-$width'),
                    label: Text(
                      '$width × $height${_tag(tag, isDefault: width == defaultWidth && height == defaultHeight)}',
                    ),
                    selected: _width.text == '$width' && _height.text == '$height',
                    showCheckmark: false,
                    selectedColor: colors.primaryContainer,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
                    onSelected: (_) => setState(() {
                      _width.text = '$width';
                      _height.text = '$height';
                      _error = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(i18n('custom_input'), style: caption),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _field(_width, i18n('width'), const ValueKey('settings-window-width'))),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('×')),
                Expanded(child: _field(_height, i18n('height'), const ValueKey('settings-window-height'))),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _error ??
                  i18n(
                    'settings_window_size_hint',
                    args: {
                      'minWidth': '${minimum.width.round()}',
                      'minHeight': '${minimum.height.round()}',
                      'max': '${Settings.windowWidth.max!.round()}',
                    },
                  ),
              style: caption.copyWith(fontSize: 12, color: _error == null ? colors.onSurfaceVariant : colors.error),
            ),
          ],
        ),
      ),
    );
  }

  static String _tag(String? tag, {required bool isDefault}) {
    final parts = [?tag, if (isDefault) i18n('default_option')];
    return parts.isEmpty ? '' : ' (${parts.join(' · ')})';
  }
}

/// What closing the window does (U.6d d5, U.13): ask each time, minimize
/// to the tray, or quit. Stored in 3.x's keys: "ask" is `dontAskExit` off;
/// the other two turn it on and remember the action in `exitChoose`.
class CloseWindowTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ask = !watchSetting(ref, Settings.dontAskExit);
    final action = watchSetting(ref, Settings.exitChoose);
    final current = ask ? 'ask' : action;
    final options = <SettingsChoice<String>>[
      (value: 'ask', label: i18n('settings_close_ask'), description: i18n('settings_close_ask_desc')),
      (value: 'minimize', label: i18n('settings_close_minimize'), description: i18n('settings_close_minimize_desc')),
      (value: 'exit', label: i18n('settings_close_exit'), description: null),
    ];
    return SettingsLinkRow(
      key: entry.rowKey,
      icon: AppIcons.settingsCloseWindow,
      title: entry.titleText,
      subtitle: entry.descriptionText,
      value: options.firstWhere((option) => option.value == current, orElse: () => options.first).label,
      onTap: () async {
        final picked = await showChoiceDialog<String>(
          context: context,
          title: entry.titleText,
          options: options,
          selected: current,
        );
        if (picked == null || !context.mounted) return;
        final settings = ref.read(storeProvider).settings;
        await settings.setAll(
          picked == 'ask' ? {Settings.dontAskExit: false} : {Settings.dontAskExit: true, Settings.exitChoose: picked},
        );
      },
    );
  }
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

/// The exit countdown's switch (3.x); switching it on starts the countdown.
class AutoExitTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingToggleTile(
    entry: entry,
    setting: Settings.enableAutoShutDownTime,
    icon: AppIcons.settingsExitTimer,
    onChanged: (_) => AutoExitTimer.instance.attach(ref.read(storeProvider).settings),
  );
}

/// How long before the app exits (3.x "退出前等待时间"): the time left while
/// the countdown runs (updated every second, only this row), the duration
/// dialog shared with the sleep timer (U.6d d6).
class AutoExitMinutesTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = watchSetting(ref, Settings.enableAutoShutDownTime);
    return ValueListenableBuilder<Duration?>(
      valueListenable: AutoExitTimer.instance.remaining,
      builder: (context, left, _) => SettingNumberTile(
        entry: entry,
        setting: Settings.autoShutDownTime,
        icon: AppIcons.settingsExitMinutes,
        presets: const [15, 30, 45, 60, 90, 120, 180],
        label: (value) => '$value ${i18n('minute')}',
        unit: i18n('minute'),
        hint: i18n('settings_exit_timer_hint'),
        inputLabel: i18n('custom_duration'),
        rangeText: i18n('app_exit_timer_custom_hint'),
        subtitle: running && left != null ? '${i18n('remaining_time')}: ${formatCountdown(left)}' : null,
      ),
    );
  }
}

/// The refresh-rate policy (3.x "界面刷新率", U.6d d3, d4): the policy on
/// the right, the display's rates as the explanation (on Windows the
/// monitor's mode, updated when the window moves to another monitor; 3.x's
/// "Windows 动态刷新率" row); the dialog explains each policy and can read
/// the display again. P01 c3: a line under the row while the system holds
/// the app at 60 Hz against the policy ([DisplayMode.limited]).
class RefreshRateTile extends ConsumerStatefulWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  /// The policies, with their energy use and explanation (3.x).
  static List<SettingsChoice<String>> options() => [
    for (final (mode, label, energy, description) in const [
      ('powerSaving', 'refresh_rate_power_saving', 'refresh_rate_energy_low', 'refresh_rate_power_saving_desc'),
      ('balanced', 'refresh_rate_balanced', 'refresh_rate_energy_medium', 'refresh_rate_balanced_desc'),
      ('performance', 'refresh_rate_performance', 'refresh_rate_energy_high', 'refresh_rate_performance_desc'),
    ])
      (value: mode, label: '${i18n(label)} · ${i18n(energy)}', description: i18n(description)),
  ];

  @override
  ConsumerState<RefreshRateTile> createState() => _RefreshRateTileState();
}

class _RefreshRateTileState extends ConsumerState<RefreshRateTile> {
  @override
  void initState() {
    super.initState();
    unawaited(DisplayMode.refresh());
  }

  String _rates(DisplayModeInfo? info, double fallback) {
    if (info == null) {
      if (DisplayMode.supported) return i18n('display_mode_detecting');
      final rate = '${fallback.round()}';
      return i18n('settings_refresh_rate_rates', args: {'current': rate, 'max': rate});
    }
    final current = '${info.currentRefreshRate.round()}';
    final max = '${info.maxRefreshRate.round()}';
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return i18n(
        'settings_refresh_rate_monitor',
        args: {'width': '${info.width ?? '?'}', 'height': '${info.height ?? '?'}', 'current': current, 'max': max},
      );
    }
    return i18n('settings_refresh_rate_rates', args: {'current': current, 'max': max});
  }

  @override
  Widget build(BuildContext context) {
    final fallback = View.maybeOf(context)?.display.refreshRate ?? 60;
    final asksHigh = watchSetting(ref, Settings.refreshRateMode) != 'powerSaving';
    return ValueListenableBuilder<DisplayModeInfo?>(
      valueListenable: DisplayMode.info,
      builder: (context, info, _) {
        final rates = _rates(info, fallback);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingChoiceTile<String>(
              entry: widget.entry,
              setting: Settings.refreshRateMode,
              icon: AppIcons.settingsRefreshRate,
              options: RefreshRateTile.options,
              subtitle: rates,
              hint: '${i18n('refresh_rate_mode_hint')}\n$rates',
              valueText: (current, value) => i18n('settings_refresh_rate_short_$value'),
              action: DisplayMode.supported
                  ? (
                      label: i18n('settings_display_recheck'),
                      key: const ValueKey('settings-display-recheck'),
                      onPressed: () => unawaited(DisplayMode.refresh()),
                    )
                  : null,
            ),
            ValueListenableBuilder<bool>(
              valueListenable: DisplayMode.limited,
              builder: (context, limited, _) => limited && asksHigh
                  ? _RefreshRateLimitedNote(rate: info?.currentRefreshRate ?? 60)
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }
}

/// P01 c3: the system holds the app at [rate] (60 Hz) although the policy
/// asks for more; under the refresh-rate row, where the row's text starts,
/// in the warning colour.
class _RefreshRateLimitedNote extends StatelessWidget {
  const new({required this.rate});

  final double rate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tv = SettingsRowStyle.tvOf(context);
    return Padding(
      key: const ValueKey('settings-refresh-rate-limited'),
      padding: EdgeInsetsDirectional.fromSTEB(tv ? 60 : 56, 0, 16, 12),
      child: Text(
        i18n('settings_refresh_rate_limited', args: {'rate': '${rate.round()}'}),
        style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
          fontSize: tv ? 14 : 12,
          height: 1.45,
          color: LiveSemanticColors.warning(theme.brightness),
        ),
      ),
    );
  }
}

/// Start with Windows (3.x): while the entry is written the switch cannot
/// be used ("正在更新 Windows 启动项…"); when writing failed the
/// explanation turns red.
class StartupTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = watchSetting(ref, Settings.enableStartUp);
    return ValueListenableBuilder<StartupEntryState>(
      valueListenable: DesktopShell.startupState,
      builder: (context, state, _) => SettingsSwitchRow(
        key: entry.rowKey,
        icon: AppIcons.settingsStartup,
        title: entry.titleText,
        subtitle: switch (state) {
          StartupEntryState.applying => i18n('startup_applying'),
          StartupEntryState.failed => i18n('settings_startup_failed'),
          StartupEntryState.idle => entry.descriptionText,
        },
        subtitleColor: state == StartupEntryState.failed ? Theme.of(context).colorScheme.error : null,
        value: enabled,
        busy: state == StartupEntryState.applying,
        onChanged: (value) => writeSetting(ref, Settings.enableStartUp, value),
      ),
    );
  }
}
