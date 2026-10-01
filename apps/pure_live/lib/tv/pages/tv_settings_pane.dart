import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/settings_catalog.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_page_header.dart';
import 'package:pure_live/tv/widgets/tv_settings_rows.dart';

/// The accent presets of the TV settings (pure_live_TV's palettes: tech
/// blue, anime pink, cyberpunk green, plus 3.x's blue and two warm ones),
/// stored as the app's theme colour.
const List<(String, String)> tvThemeColors = [
  ('FF2196F3', 'tv_color_blue'),
  ('FF00D4FF', 'tv_color_cyan'),
  ('FFFF66CC', 'tv_color_pink'),
  ('FF2AD39A', 'tv_color_green'),
  ('FFFF9F43', 'tv_color_orange'),
  ('FF9C6BFF', 'tv_color_purple'),
];

/// Text sizes offered on the TV (pure_live_TV's font scale steps).
const List<double> tvTextScales = [0.9, 1.0, 1.15, 1.3, 1.45, 1.6];

/// Danmaku sizes offered on the TV.
const List<double> tvDanmakuSizes = [14, 16, 18, 20, 24, 28, 32, 36];

/// Danmaku opacities offered on the TV.
const List<double> tvDanmakuOpacities = [0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0];

/// The TV settings (pure_live_TV `TvSettingsPage`, first page) with the
/// settings rows of docs/ui/compare/U.15a: the common ones for the remote —
/// interface mode, theme colour, text size, growing the focused item,
/// default quality, danmaku on/off, size and opacity — then the proxy and
/// "more settings", which open the full settings page. OK on a value opens
/// its choices with the focus on the current one; OK or ←→ flip a switch.
/// The TV is dark only, so the theme mode is not offered here (U.6b →
/// U.15i); the page itself is U.15i's.
class TvSettingsPane extends ConsumerWidget {
  /// Creates the pane.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(storeProvider).settings;
    final scale = TvScale.of(context);
    String percent(double value) => '${(value * 100).round()}%';
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: scale.px(24), vertical: scale.px(28)),
      children: [
        TvPageHeader(title: i18n('tv_menu_settings')),
        SizedBox(height: scale.px(16)),
        TvSettingsGroup(
          children: [
            TvChoiceRow<String>(
              id: 'ui_mode',
              icon: TvIcons.uiMode,
              title: i18n('ui_mode'),
              subtitle: i18n('tv_ui_mode_desc'),
              value: watchSetting(ref, Settings.uiMode),
              options: [
                TvChoice(value: 'auto', label: i18n('ui_mode_auto'), description: i18n('ui_mode_auto_desc')),
                TvChoice(value: 'phone', label: i18n('ui_mode_phone')),
                TvChoice(value: 'tv', label: i18n('ui_mode_tv')),
              ],
              onChanged: (value) => settings.set(Settings.uiMode, value),
            ),
            TvChoiceRow<String>(
              id: 'theme_color',
              icon: TvIcons.themeColor,
              title: i18n('change_theme_color'),
              value: watchSetting(ref, Settings.themeColorSwitch).toUpperCase(),
              options: [for (final (hex, key) in tvThemeColors) TvChoice(value: hex, label: i18n(key))],
              onChanged: (value) async {
                // A picked colour wins over the system's dynamic colours.
                await settings.set(Settings.enableDynamicTheme, false);
                await settings.set(Settings.themeColorSwitch, value);
              },
            ),
            TvChoiceRow<double>(
              id: 'text_scale',
              icon: TvIcons.textSize,
              title: i18n('tv_text_size'),
              subtitle: i18n('tv_text_size_desc'),
              value: watchSetting(ref, Settings.textScaleFactor),
              options: [for (final value in tvTextScales) TvChoice(value: value, label: percent(value))],
              onChanged: (value) => settings.set(Settings.textScaleFactor, value),
            ),
            TvSwitchRow(
              id: 'focus_zoom',
              icon: TvIcons.focusZoom,
              title: i18n('tv_focus_zoom'),
              subtitle: i18n('tv_focus_zoom_desc'),
              value: watchSetting(ref, Settings.tvFocusZoom),
              onChanged: (value) => unawaited(settings.set(Settings.tvFocusZoom, value)),
            ),
          ],
        ),
        TvSettingsGroup(
          children: [
            TvChoiceRow<String>(
              id: 'quality',
              icon: TvIcons.quality,
              title: i18n('prefer_resolution'),
              value: watchSetting(ref, Settings.preferResolution),
              options: [
                for (final MapEntry(:key, :value) in resolutionKeys.entries) TvChoice(value: key, label: i18n(value)),
              ],
              onChanged: (value) => settings.set(Settings.preferResolution, value),
            ),
            TvSwitchRow(
              id: 'danmaku',
              icon: TvIcons.danmakuOn,
              title: i18n('show_danmaku'),
              value: watchSetting(ref, Settings.enableDanmakuDisplay),
              onChanged: (value) => unawaited(settings.set(Settings.enableDanmakuDisplay, value)),
            ),
            TvChoiceRow<double>(
              id: 'danmaku_size',
              icon: TvIcons.danmakuSize,
              title: i18n('tv_danmaku_size'),
              value: watchSetting(ref, Settings.danmakuFontSize),
              options: [for (final value in tvDanmakuSizes) TvChoice(value: value, label: '${value.round()}')],
              onChanged: (value) => settings.set(Settings.danmakuFontSize, value),
            ),
            TvChoiceRow<double>(
              id: 'danmaku_opacity',
              icon: TvIcons.danmakuOpacity,
              title: i18n('tv_danmaku_opacity'),
              value: watchSetting(ref, Settings.danmakuOpacity),
              options: [for (final value in tvDanmakuOpacities) TvChoice(value: value, label: percent(value))],
              onChanged: (value) => settings.set(Settings.danmakuOpacity, value),
            ),
          ],
        ),
        TvSettingsGroup(
          children: [
            TvLinkRow(
              id: 'proxy',
              icon: TvIcons.network,
              title: i18n('settings_section_network'),
              subtitle: i18n('tv_proxy_desc'),
              onTap: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kSettings, arguments: 'network')),
            ),
            TvLinkRow(
              id: 'more',
              icon: TvIcons.moreSettings,
              title: i18n('tv_more_settings'),
              subtitle: i18n('tv_more_settings_desc'),
              onTap: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kSettings)),
            ),
          ],
        ),
      ],
    );
  }
}
