import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_dialogs.dart';
import 'package:pure_live/features/settings/settings_editors.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_section_view.dart';
import 'package:pure_live/features/settings/settings_tiles.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/display_mode.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings_content.dart';
import 'package:pure_live/shared/danmaku/danmaku_templates.dart';
import 'package:pure_live/shared/permission_prompts.dart';

// The rows of the playback pages that draw more than a plain switch, slider
// or choice (docs/ui/compare/U.6c): the video page, the player page, the
// mpv option pages, the floating-window danmaku page.

/// Global mute: the icon follows the switch (3.x `volume_mute_line` /
/// `volume_up_line`).
class GlobalMuteTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = watchSetting(ref, Settings.globalVolumeMute);
    return SettingToggleTile(
      entry: entry,
      setting: Settings.globalVolumeMute,
      icon: muted ? AppIcons.settingsMuted : AppIcons.settingsUnmuted,
    );
  }
}

/// What a [SwitchGate] answered.
enum SwitchGateResult {
  /// The switch may turn on.
  granted,

  /// The system permission was refused (U.14 c13: the notification
  /// permission of background play and the sleep timer).
  denied,

  /// Something failed.
  failed,

  /// The user cancelled the explanation: the switch stays off, nothing
  /// turns red (3.x).
  cancelled,
}

/// Asks before a switch turns on (a system permission); null lets it turn
/// on at once.
typedef SwitchGate = Future<SwitchGateResult> Function(BoolSetting setting);

/// The check before background play or the automatic sleep turns on (the
/// notification permission and the battery exemption, U.14 c12, c13; F.0a):
/// the shared [BackgroundPermissions] where the platform asks (Android),
/// else null.
final Provider<SwitchGate?> switchGateProvider = Provider((ref) {
  final permissions = ref.watch(backgroundPermissionsProvider);
  if (permissions == null) return null;
  return (setting) async => switch (await permissions.confirm()) {
    PermissionAnswer.granted => SwitchGateResult.granted,
    PermissionAnswer.denied => SwitchGateResult.denied,
    PermissionAnswer.cancelled => SwitchGateResult.cancelled,
  };
});

/// A switch that may need a permission before it turns on (3.x background
/// play and automatic sleep): while asking the switch cannot be used; when
/// refused or failed the explanation turns red and the switch stays off.
class GatedToggleTile extends ConsumerStatefulWidget {
  /// Creates the row.
  const new({required this.entry, required this.setting, required this.icon, required this.failedKey, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  /// The stored switch.
  final BoolSetting setting;

  /// The icon.
  final IconData icon;

  /// The translation key of "could not change it, try again".
  final String failedKey;

  @override
  ConsumerState<GatedToggleTile> createState() => _GatedToggleTileState();
}

class _GatedToggleTileState extends ConsumerState<GatedToggleTile> {
  bool _asking = false;
  SwitchGateResult? _problem;

  Future<void> _change(bool on) async {
    final gate = ref.read(switchGateProvider);
    if (!on || gate == null) {
      setState(() => _problem = null);
      writeSetting(ref, widget.setting, on);
      return;
    }
    setState(() {
      _asking = true;
      _problem = null;
    });
    SwitchGateResult result;
    try {
      result = await gate(widget.setting);
    } on Object {
      result = SwitchGateResult.failed;
    }
    if (!mounted) return;
    setState(() {
      _asking = false;
      _problem = result == SwitchGateResult.granted || result == SwitchGateResult.cancelled ? null : result;
    });
    if (result == SwitchGateResult.granted) writeSetting(ref, widget.setting, true);
  }

  @override
  Widget build(BuildContext context) {
    final value = watchSetting(ref, widget.setting);
    final problem = _problem;
    return SettingsSwitchRow(
      key: widget.entry.rowKey,
      icon: widget.icon,
      title: widget.entry.titleText,
      subtitle: switch (problem) {
        SwitchGateResult.denied => i18n('settings_notification_denied'),
        SwitchGateResult.failed => i18n(widget.failedKey),
        _ => widget.entry.descriptionText,
      },
      subtitleColor: problem == null ? null : Theme.of(context).colorScheme.error,
      value: value,
      busy: _asking,
      onChanged: (on) => unawaited(_change(on)),
    );
  }
}

/// The desktop mini window stays on top (3.x "Windows 小窗始终置顶"): an
/// open mini window follows at once; when that fails the explanation turns
/// red and the switch goes back.
class PipOnTopTile extends ConsumerStatefulWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  ConsumerState<PipOnTopTile> createState() => _PipOnTopTileState();
}

class _PipOnTopTileState extends ConsumerState<PipOnTopTile> {
  bool _applying = false;
  bool _failed = false;

  Future<void> _change(bool on) async {
    final settings = ref.read(storeProvider).settings;
    setState(() {
      _failed = false;
      _applying = DesktopWindow.mini.value;
    });
    await settings.set(Settings.windowsPipAlwaysOnTop, on);
    if (!DesktopWindow.mini.value) {
      if (mounted) setState(() => _applying = false);
      return;
    }
    final applied = await DesktopWindow.setMiniOnTop(onTop: on);
    if (!applied) await settings.set(Settings.windowsPipAlwaysOnTop, !on);
    if (mounted) {
      setState(() {
        _applying = false;
        _failed = !applied;
      });
    }
  }

  @override
  Widget build(BuildContext context) => SettingsSwitchRow(
    key: widget.entry.rowKey,
    icon: AppIcons.settingsPipOnTop,
    title: widget.entry.titleText,
    subtitle: _failed ? i18n('settings_pip_on_top_failed') : widget.entry.descriptionText,
    subtitleColor: _failed ? Theme.of(context).colorScheme.error : null,
    value: watchSetting(ref, Settings.windowsPipAlwaysOnTop),
    busy: _applying,
    onChanged: (on) => unawaited(_change(on)),
  );
}

/// The player engine: v4 plays everything with mpv (PLAN §4, M7.1), so the
/// row shows it and cannot be changed (3.x on computers).
class KernelTile extends StatelessWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context) => SettingsLinkRow(
    key: entry.rowKey,
    icon: AppIcons.settingsKernel,
    title: entry.titleText,
    subtitle: entry.descriptionText,
    value: i18n('player_mpv'),
    chevron: false,
    onTap: null,
  );
}

/// The player's proxy, changed in one place (U.6c c9, U.6d d14): on or off
/// here; a tap opens the network page at "播放器内核代理".
class PlayerProxyLinkTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingsLinkRow(
    key: entry.rowKey,
    icon: AppIcons.settingsPlayerProxy,
    title: entry.titleText,
    subtitle: entry.descriptionText,
    value: i18n(watchSetting(ref, Settings.enableProxy) ? 'enabled' : 'disabled'),
    onTap: () => openOrReveal(
      context,
      entry,
      () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const SettingsSectionPage(section: SettingsSection.network, highlight: 'player_proxy'),
        ),
      ),
    ),
  );
}

/// One expert mpv option: the value in use, a tap opens its page; usable
/// only with "custom drivers" on (3.x, U.6c c5).
class MpvOptionTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, required this.kind, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  /// Which option.
  final MpvOptionKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setting = mpvOptionSetting(kind);
    final value = watchSetting(ref, setting);
    final unmet = watchUnmet(ref, [
      ..._customOutputTaken(),
      needsOn(Settings.customPlayerOutput, 'custom_output_hwdec'),
    ]);
    return SettingsLinkRow(
      key: entry.rowKey,
      icon: switch (kind) {
        MpvOptionKind.video => AppIcons.settingsVideoOutput,
        MpvOptionKind.audio => AppIcons.settingsAudioOutput,
        MpvOptionKind.decoder => AppIcons.settingsDecoder,
      },
      title: entry.titleText,
      subtitle: entry.descriptionText,
      value: mpvOptionName(effectiveMpvOption(kind, value, defaultTargetPlatform), kind: kind),
      enabled: unmet == null,
      disabledReason: unmetReason(unmet),
      onTap: () => openOrReveal(
        context,
        entry,
        () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MpvOptionPage(kind: kind, title: entry.titleText),
          ),
        ),
      ),
    );
  }
}

List<SettingRequirement> _customOutputTaken() => [
  if (defaultTargetPlatform == TargetPlatform.android)
    (setting: Settings.playerCompatMode, value: false, reason: i18n('settings_taken_over_by_compat')),
];

/// The stored setting of [kind].
StringSetting mpvOptionSetting(MpvOptionKind kind) => switch (kind) {
  MpvOptionKind.video => Settings.videoOutputDriver,
  MpvOptionKind.audio => Settings.audioOutputDriver,
  MpvOptionKind.decoder => Settings.videoHardwareDecoder,
};

/// The value in use: [stored] when this platform offers it, otherwise the
/// default (3.x fell back the same way, U.6c c11).
String effectiveMpvOption(MpvOptionKind kind, String stored, TargetPlatform platform) {
  final options = mpvOptionsFor(kind, platform);
  if (options.contains(stored)) return stored;
  final fallback = mpvOptionSetting(kind).defaultValue;
  return options.contains(fallback) ? fallback : options.first;
}

/// The options of one expert mpv setting (3.x `MpvOptionPage`): only what
/// this platform offers, the default marked "默认", the current one in the
/// primary colour with a tick; a tap picks it and goes back (U.6c c11).
class MpvOptionPage extends ConsumerWidget {
  /// Creates the page.
  const new({required this.kind, required this.title, super.key});

  /// Which option.
  final MpvOptionKind kind;

  /// The page title (the row's).
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setting = mpvOptionSetting(kind);
    final current = effectiveMpvOption(kind, watchSetting(ref, setting), defaultTargetPlatform);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      key: ValueKey('settings-mpv-${kind.name}'),
      appBar: settingsAppBar(context, title: title, embedded: SettingsPane.of(context)),
      body: SettingsPageBody(
        start: SettingsPane.of(context),
        children: [
          SettingsNote(i18n('settings_mpv_option_intro'), padding: const EdgeInsets.fromLTRB(8, 8, 8, 12)),
          SettingsGroup(
            children: [
              for (final option in mpvOptionsFor(kind, defaultTargetPlatform))
                SettingsRow(
                  key: ValueKey('settings-mpv-option-$option'),
                  title: mpvOptionName(option, kind: kind),
                  titleColor: option == current ? colors.primary : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 8,
                    children: [
                      if (option == setting.defaultValue) _DefaultTag(),
                      SizedBox(
                        width: 24,
                        child: option == current ? Icon(AppIcons.selected, size: 22, color: colors.primary) : null,
                      ),
                    ],
                  ),
                  onTap: () {
                    writeSetting(ref, setting, option);
                    Navigator.of(context).maybePop();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DefaultTag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Text(
          i18n('default_option'),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.onSecondaryContainer),
        ),
      ),
    );
  }
}

/// The MPV warning under its group, with the "MPV 官方文档" link (3.x put it
/// above the group in low contrast, U.6c c10).
class MpvDocsNote extends StatelessWidget {
  /// Creates the note.
  const new({super.key});

  /// mpv's manual.
  static final Uri docs = Uri.parse('https://mpv.io/manual/stable/');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      fontSize: 12,
      height: 1.5,
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      child: Text.rich(
        key: const ValueKey('settings-mpv-docs'),
        TextSpan(
          style: style,
          children: [
            TextSpan(text: i18n('mpv_warning_text')),
            TextSpan(
              text: i18n('mpv_official_docs'),
              style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
              recognizer: TapGestureRecognizer()..onTap = () => unawaited(AppNavigator.openExternal(docs)),
            ),
          ],
        ),
      ),
    );
  }
}

/// "恢复……默认设置" (U.6c c8): the last row of a page, in red; asks first,
/// saying what goes back, then restores [settings] and says so.
class RestoreDefaultsTile extends ConsumerWidget {
  /// Creates the row.
  const new({
    required this.entry,
    required this.settings,
    required this.confirmTitle,
    required this.confirmMessage,
    super.key,
  });

  /// The entry drawn.
  final SettingsEntry entry;

  /// What goes back to its default.
  final List<Setting<Object>> settings;

  /// The question's title key.
  final String confirmTitle;

  /// The question's text key (what goes back).
  final String confirmMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingActionTile(
    entry: entry,
    icon: AppIcons.settingsRestoreDefaults,
    destructive: true,
    onTap: () async {
      final confirmed = await showConfirmDialog(
        context: context,
        title: i18n(confirmTitle),
        message: i18n(confirmMessage),
        confirmLabel: i18n('reset'),
        destructive: true,
      );
      if (!confirmed) return;
      final store = ref.read(storeProvider).settings;
      for (final setting in settings) {
        await store.reset(setting);
      }
      AppNavigator.toast(i18n('settings_reset_done'));
    },
  );
}

/// "弹幕样式" (U.6c c12): the room's danmaku settings (U.2f, the same
/// component), here without entering a room; changes apply to every room.
class DanmakuStylePage extends StatelessWidget {
  /// Creates the page.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final start = SettingsPane.of(context);
    return Scaffold(
      key: const ValueKey('settings-danmaku-style'),
      appBar: settingsAppBar(context, title: i18n('settings_danmaku_style'), embedded: start),
      body: Align(
        alignment: start ? Alignment.topLeft : Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: start ? 12 : 4),
            child: DanmakuSettingsContent(hint: i18n('danmaku_settings_live_hint')),
          ),
        ),
      ),
    );
  }
}

/// "统一弹幕颜色" of the mini windows: the colour dialog of U.6b; greyed out
/// while the platform's colours are kept (U.6c c5).
class PipColorTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = Color(watchSetting(ref, Settings.pipDanmakuColor));
    final unmet = watchUnmet(ref, [
      needsOn(Settings.enablePipDanmaku, 'pip_danmaku_enable'),
      (
        setting: Settings.pipDanmakuUseOriginalColor,
        value: false,
        reason: i18n('settings_needs_off', args: {'name': i18n('pip_danmaku_original_color')}),
      ),
    ]);
    return SettingsLinkRow(
      key: entry.rowKey,
      title: entry.titleText,
      value: '#${colorHex(color)}',
      valueWidget: SettingsSwatch(color, size: 24),
      enabled: unmet == null,
      disabledReason: unmetReason(unmet),
      onTap: () async {
        final picked = await showColorDialog(context: context, title: entry.titleText, current: color);
        if (picked != null && context.mounted) writeSetting(ref, Settings.pipDanmakuColor, picked.toARGB32());
      },
    );
  }
}

/// The mini windows' danmaku frame rate: while it follows the refresh-rate
/// policy the slider is greyed out at the rate in use and says which policy
/// (U.6c 小窗弹幕 14).
class PipFpsTile extends ConsumerWidget {
  /// Creates the row.
  const new({required this.entry, super.key});

  /// The entry drawn.
  final SettingsEntry entry;

  static const Map<String, String> _modeNames = {
    'powerSaving': 'settings_refresh_rate_short_powerSaving',
    'balanced': 'settings_refresh_rate_short_balanced',
    'performance': 'settings_refresh_rate_short_performance',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = watchSetting(ref, Settings.refreshRateMode);
    final fps = watchSetting(ref, Settings.pipDanmakuFps);
    return ValueListenableBuilder<DisplayModeInfo?>(
      valueListenable: DisplayMode.info,
      builder: (context, display, _) {
        final shown = resolvedDanmakuFps(
          automatic: true,
          configured: fps,
          mode: mode,
          maxRefreshRate: display?.maxRefreshRate,
          currentRefreshRate: display?.currentRefreshRate,
          pip: true,
        );
        return SettingSliderTile(
          entry: entry,
          setting: Settings.pipDanmakuFps,
          icon: null,
          min: 15,
          max: 240,
          step: 1,
          format: (value) => '${value.round()} FPS',
          shown: shown.toDouble(),
          requires: [
            needsOn(Settings.enablePipDanmaku, 'pip_danmaku_enable'),
            (
              setting: Settings.pipDanmakuAutoFps,
              value: false,
              reason: i18n(
                'settings_pip_fps_following',
                args: {'mode': i18n(_modeNames[mode] ?? 'settings_refresh_rate_short_powerSaving')},
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The floating-window danmaku page (3.x `PipDanmakuSettingsPage`, U.6c
/// c13, c14): the explanation and the live preview above the rows on
/// phones; from 840 wide, or below 480 high (a phone held sideways), the
/// preview stays on the left and the rows scroll on the right.
class PipDanmakuPage extends ConsumerWidget {
  /// Creates the page.
  const new({this.highlight, this.onBack, super.key});

  /// The row to highlight (search).
  final String? highlight;

  /// The back button of the one-column layout's first page.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final embedded = SettingsPane.of(context);
    return Scaffold(
      key: const ValueKey('settings-page-pipDanmaku'),
      appBar: settingsAppBar(
        context,
        title: i18n(SettingsSection.pipDanmaku.titleKey),
        embedded: embedded,
        leading: onBack == null ? null : BackButton(onPressed: onBack),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.maxWidth >= 840 || (constraints.maxHeight < 480 && constraints.maxWidth >= 560);
          final intro = SettingsNote(
            i18n('settings_pip_danmaku_intro'),
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          );
          final rows = SettingsSectionView(section: SettingsSection.pipDanmaku, highlight: highlight);
          if (side) {
            final previewWidth = (constraints.maxWidth * 0.43).clamp(240.0, 520.0);
            return Row(
              key: const ValueKey('settings-pip-two-columns'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: previewWidth,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [intro, const PipDanmakuPreviewBinding()],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: rows),
              ],
            );
          }
          return Column(
            key: const ValueKey('settings-pip-one-column'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: embedded ? Alignment.topLeft : Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(embedded ? 24 : 16, 4, embedded ? 24 : 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        intro,
                        // At most about a third of the height, so the rows
                        // keep room (3.x: 31%).
                        ConstrainedBox(
                          constraints: BoxConstraints(maxHeight: (constraints.maxHeight * 0.34).clamp(120.0, 420.0)),
                          child: const Center(child: PipDanmakuPreviewBinding()),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(child: rows),
            ],
          );
        },
      ),
    );
  }
}

/// [PipDanmakuPreview] drawn with the stored settings.
class PipDanmakuPreviewBinding extends ConsumerWidget {
  /// Creates the preview.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keepColors = watchSetting(ref, Settings.pipDanmakuUseOriginalColor);
    final autoFps = watchSetting(ref, Settings.pipDanmakuAutoFps);
    final fps = watchSetting(ref, Settings.pipDanmakuFps);
    final mode = watchSetting(ref, Settings.refreshRateMode);
    final display = DisplayMode.info.value;
    return PipDanmakuPreview(
      key: const ValueKey('settings-pip-preview'),
      enabled: watchSetting(ref, Settings.enablePipDanmaku),
      label: i18n('pip_danmaku_preview_text'),
      disabledLabel: i18n('pip_danmaku_disabled'),
      opacity: watchSetting(ref, Settings.pipDanmakuOpacity),
      fontSize: watchSetting(ref, Settings.pipDanmakuFontSize),
      fontWeight: watchSetting(ref, Settings.pipDanmakuFontWeight),
      speed: watchSetting(ref, Settings.pipDanmakuSpeed),
      area: watchSetting(ref, Settings.pipDanmakuArea),
      maxVisible: watchSetting(ref, Settings.pipDanmakuMaxVisibleCount),
      emitInterval: watchSetting(ref, Settings.pipDanmakuEmitInterval),
      autoScale: watchSetting(ref, Settings.pipDanmakuAutoScale),
      stroke: watchSetting(ref, Settings.enableDanmakuStroke),
      strokeWidth: watchSetting(ref, Settings.danmakuFontBorder),
      color: keepColors ? null : Color(watchSetting(ref, Settings.pipDanmakuColor)),
      fps: resolvedDanmakuFps(
        automatic: autoFps,
        configured: fps,
        mode: mode,
        maxRefreshRate: display?.maxRefreshRate,
        currentRefreshRate: display?.currentRefreshRate,
        pip: true,
      ),
    );
  }
}
