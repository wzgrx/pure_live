import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/settings/settings_catalog.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';

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

/// The TV settings (pure_live_TV `TvSettingsPage`, first page): the common
/// ones in one list for the remote — interface mode, theme, text size,
/// default quality, danmaku on/off, size and opacity — then the proxy and
/// "more settings", which open the full settings page. OK opens a value's
/// choices; Left and Right step through them in place.
class TvSettingsPane extends ConsumerWidget {
  /// Creates the pane.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(storeProvider).settings;
    final scale = TvScale.of(context);
    final palette = TvTheme.of(context);
    String percent(double value) => '${(value * 100).round()}%';
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: scale(48), vertical: scale(28)),
      children: [
        Text(
          i18n('tv_menu_settings'),
          style: scale.style(34, weight: FontWeight.w700, color: palette.text),
        ),
        SizedBox(height: scale(20)),
        _ChoiceRow<String>(
          id: 'ui_mode',
          icon: Icons.tv_rounded,
          title: i18n('ui_mode'),
          subtitle: i18n('tv_ui_mode_desc'),
          value: watchSetting(ref, Settings.uiMode),
          options: [
            (value: 'auto', label: i18n('ui_mode_auto'), description: i18n('ui_mode_auto_desc')),
            (value: 'phone', label: i18n('ui_mode_phone'), description: null),
            (value: 'tv', label: i18n('ui_mode_tv'), description: null),
          ],
          onChanged: (value) => settings.set(Settings.uiMode, value),
        ),
        _ChoiceRow<String>(
          id: 'theme_mode',
          icon: Icons.dark_mode_rounded,
          title: i18n('change_theme_mode'),
          value: watchSetting(ref, Settings.themeMode),
          options: [
            (value: 'System', label: i18n('theme_mode_system'), description: null),
            (value: 'Dark', label: i18n('theme_mode_dark'), description: null),
            (value: 'Light', label: i18n('theme_mode_light'), description: null),
          ],
          onChanged: (value) => settings.set(Settings.themeMode, value),
        ),
        _ChoiceRow<String>(
          id: 'theme_color',
          icon: Icons.palette_rounded,
          title: i18n('change_theme_color'),
          value: watchSetting(ref, Settings.themeColorSwitch).toUpperCase(),
          options: [for (final (hex, key) in tvThemeColors) (value: hex, label: i18n(key), description: null)],
          onChanged: (value) async {
            // A picked colour wins over the system's dynamic colours.
            await settings.set(Settings.enableDynamicTheme, false);
            await settings.set(Settings.themeColorSwitch, value);
          },
        ),
        _ChoiceRow<double>(
          id: 'text_scale',
          icon: Icons.format_size_rounded,
          title: i18n('tv_text_size'),
          subtitle: i18n('tv_text_size_desc'),
          value: watchSetting(ref, Settings.textScaleFactor),
          options: [for (final value in tvTextScales) (value: value, label: percent(value), description: null)],
          onChanged: (value) => settings.set(Settings.textScaleFactor, value),
        ),
        _ChoiceRow<String>(
          id: 'quality',
          icon: Icons.high_quality_rounded,
          title: i18n('prefer_resolution'),
          value: watchSetting(ref, Settings.preferResolution),
          options: [
            for (final MapEntry(:key, :value) in resolutionKeys.entries)
              (value: key, label: i18n(value), description: null),
          ],
          onChanged: (value) => settings.set(Settings.preferResolution, value),
        ),
        _ChoiceRow<bool>(
          id: 'danmaku',
          icon: Icons.subtitles_rounded,
          title: i18n('show_danmaku'),
          value: watchSetting(ref, Settings.enableDanmakuDisplay),
          options: [
            (value: true, label: i18n('tv_on'), description: null),
            (value: false, label: i18n('tv_off'), description: null),
          ],
          toggle: true,
          onChanged: (value) => settings.set(Settings.enableDanmakuDisplay, value),
        ),
        _ChoiceRow<double>(
          id: 'danmaku_size',
          icon: Icons.text_fields_rounded,
          title: i18n('tv_danmaku_size'),
          value: watchSetting(ref, Settings.danmakuFontSize),
          options: [for (final value in tvDanmakuSizes) (value: value, label: '${value.round()}', description: null)],
          onChanged: (value) => settings.set(Settings.danmakuFontSize, value),
        ),
        _ChoiceRow<double>(
          id: 'danmaku_opacity',
          icon: Icons.opacity_rounded,
          title: i18n('tv_danmaku_opacity'),
          value: watchSetting(ref, Settings.danmakuOpacity),
          options: [for (final value in tvDanmakuOpacities) (value: value, label: percent(value), description: null)],
          onChanged: (value) => settings.set(Settings.danmakuOpacity, value),
        ),
        _LinkRow(
          id: 'proxy',
          icon: Icons.public_rounded,
          title: i18n('settings_section_network'),
          subtitle: i18n('tv_proxy_desc'),
          onTap: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kSettings, arguments: 'network')),
        ),
        _LinkRow(
          id: 'more',
          icon: Icons.settings_suggest_rounded,
          title: i18n('tv_more_settings'),
          subtitle: i18n('tv_more_settings_desc'),
          onTap: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kSettings)),
        ),
      ],
    );
  }
}

/// A settings row: icon, title, description and the current value.
class _Row extends StatelessWidget {
  const new({
    required this.id,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.value,
    this.onKey,
  });

  final String id;
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback onTap;
  final TvKeyHandler? onKey;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: scale(12)),
      child: TvFocusable(
        key: ValueKey('tv-setting-$id'),
        scale: 1.02,
        onTap: onTap,
        onKey: onKey,
        builder: (context, focused) {
          final color = focused ? palette.onFocusedCard : palette.text;
          return Container(
            padding: EdgeInsets.symmetric(horizontal: scale.text(24), vertical: scale.text(16)),
            decoration: BoxDecoration(
              color: focused ? palette.focusedCard : palette.card,
              borderRadius: BorderRadius.circular(scale(16)),
            ),
            child: Row(
              children: [
                Icon(icon, color: focused ? color : palette.focus, size: scale.text(30)),
                SizedBox(width: scale(20)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: scale.style(23, weight: FontWeight.w600, color: color),
                      ),
                      if (subtitle case final subtitle? when subtitle.isNotEmpty)
                        Text(subtitle, style: scale.style(17, color: color.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
                if (value != null) ...[
                  if (focused) Icon(Icons.chevron_left_rounded, color: color, size: scale.text(28)),
                  Text(
                    value!,
                    style: scale.style(22, weight: FontWeight.w600, color: focused ? color : palette.focus),
                  ),
                  if (focused) Icon(Icons.chevron_right_rounded, color: color, size: scale.text(28)),
                ] else
                  Icon(Icons.chevron_right_rounded, color: color, size: scale.text(30)),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A row whose value is one of [options]: OK picks from a dialog (a
/// [toggle] flips), Left and Right step to the previous or next option.
class _ChoiceRow<T> extends StatelessWidget {
  const new({
    required this.id,
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
    this.subtitle,
    this.toggle = false,
  });

  final String id;
  final IconData icon;
  final String title;
  final String? subtitle;
  final T value;
  final List<TvChoice<T>> options;
  final Future<void> Function(T value) onChanged;
  final bool toggle;

  int get _index => options.indexWhere((option) => option.value == value);

  void _step(int delta) {
    final index = _index;
    final next = index < 0 ? 0 : (index + delta).clamp(0, options.length - 1);
    if (next != index) unawaited(onChanged(options[next].value));
  }

  @override
  Widget build(BuildContext context) {
    final index = _index;
    return _Row(
      id: id,
      icon: icon,
      title: title,
      subtitle: subtitle,
      value: index < 0 ? '$value' : options[index].label,
      onTap: () async {
        if (toggle) {
          final next = options[(index + 1) % options.length].value;
          await onChanged(next);
          return;
        }
        final picked = await showTvChoice<T>(context, title: title, options: options, current: value);
        if (picked != null && picked != value) await onChanged(picked);
      },
      onKey: (node, event) {
        if (event is KeyUpEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _step(-1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _step(1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
  }
}

/// A row that opens a page.
class _LinkRow extends StatelessWidget {
  const new({required this.id, required this.icon, required this.title, required this.onTap, this.subtitle});

  final String id;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Row(id: id, icon: icon, title: title, subtitle: subtitle, onTap: onTap);
}
