import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/features/live_play/danmaku/danmaku_templates.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/logic/danmaku_fps.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/display_mode.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// 3.x's names of the font weights (`AppConsts.fontWeightLabels`).
const Map<int, String> danmakuFontWeightNames = {
  100: 'font_weight_thin',
  200: 'font_weight_extra_light',
  300: 'font_weight_light',
  400: 'font_weight_normal',
  500: 'font_weight_medium',
  600: 'font_weight_semi_bold',
  700: 'font_weight_bold',
  800: 'font_weight_extra_bold',
  900: 'font_weight_black',
};

/// The text key of what a template does (the line under the templates, U.2f
/// D2: it follows the chosen one); [preset] null is a look of the user's
/// own.
String danmakuTemplateDescription(String? preset) => switch (preset) {
  'danmaku_template_best' => 'danmaku_template_best_desc',
  'danmaku_template_comfort' => 'danmaku_template_comfort_desc',
  'danmaku_template_dense' => 'danmaku_template_dense_desc',
  'reset' => 'danmaku_template_reset_desc',
  _ => 'danmaku_template_custom_desc',
};

/// Opens the danmaku settings: the room's panel (U.2f), or the same panel in
/// a sheet where there is no room page around [context].
void showRoomDanmakuSettings(BuildContext context, LiveRoomController controller) {
  final panels = RoomPanelScope.maybeOf(context);
  if (panels != null) {
    panels.open(RoomPanelKind.danmaku);
    return;
  }
  unawaited(
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.6,
        child: RoomDanmakuSettingsPanel(controller: controller, onClose: () => Navigator.of(sheetContext).pop()),
      ),
    ),
  );
}

/// The danmaku settings panel (docs/ui/compare/U.2f, 弹幕设置): under the
/// picture in portrait, on the right otherwise; "改动立即生效" and ✕ in the
/// header.
class RoomDanmakuSettingsPanel extends StatelessWidget {
  /// Creates the panel.
  const new({required this.controller, required this.onClose, this.dragToClose = false, super.key});

  /// The room.
  final LiveRoomController controller;

  /// Closes the panel.
  final VoidCallback onClose;

  /// A downward drag on the header closes it (portrait).
  final bool dragToClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RoomSidePanel(
      key: const ValueKey('live-play-danmaku-panel'),
      title: i18n('danmaku_settings'),
      onClose: onClose,
      dragToClose: dragToClose,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(
            i18n('danmaku_settings_live_hint'),
            style: theme.textTheme.bodyMedium?.regular.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
      child: RoomDanmakuSettings(controller: controller),
    );
  }
}

/// Every danmaku setting of 3.x's `DanmakuSettingsContent`
/// (`pages/danmaku_settings_page.dart:195-420`), with its ranges and keys,
/// grouped as U.2f confirmed: 观看模板, 显示范围, 样式, 重复弹幕, 画面弹幕交互,
/// 流畅度; then the chat list's own switches (gifts, the list's look: v4's,
/// U.2a). Settings that depend on a switch grey out instead of vanishing
/// (D4, D5). Everything applies at once. The panel and the room's "弹幕设置"
/// tab show this same content.
class RoomDanmakuSettings extends ConsumerWidget {
  /// Creates the settings.
  const new({required this.controller, super.key});

  /// The room.
  final LiveRoomController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(storeProvider).settings;
    void set<T extends Object>(Setting<T> setting, T value) => unawaited(settings.set(setting, value));
    final area = watchSetting(ref, Settings.danmakuArea);
    final top = watchSetting(ref, Settings.danmakuTopArea);
    final bottom = watchSetting(ref, Settings.danmakuBottomArea);
    final opacity = watchSetting(ref, Settings.danmakuOpacity);
    final speed = watchSetting(ref, Settings.danmakuSpeed);
    final fontSize = watchSetting(ref, Settings.danmakuFontSize);
    final weight = watchSetting(ref, Settings.danmakuFontWeight);
    final stroke = watchSetting(ref, Settings.enableDanmakuStroke);
    final border = watchSetting(ref, Settings.danmakuFontBorder);
    final noEmoji = watchSetting(ref, Settings.noEmojiMode);
    final collapse = watchSetting(ref, Settings.collapseRepeatedDanmaku);
    final window = watchSetting(ref, Settings.repeatedDanmakuWindowSeconds);
    final autoFps = watchSetting(ref, Settings.danmakuAutoFps);
    final fps = watchSetting(ref, Settings.danmakuFps);
    final refreshMode = watchSetting(ref, Settings.refreshRateMode);
    watchSetting(ref, Settings.savedDanmakuTemplate);
    final listStyle = ChatListStyle.of(watchSetting(ref, Settings.danmakuListStyle));
    return ListView(
      key: const ValueKey('live-play-danmaku-settings'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        PanelGroupTitle(i18n('danmaku_group_templates')),
        _Templates(settings: settings),
        PanelGroupTitle(i18n('danmaku_group_range')),
        PanelCard(
          children: [
            _SliderRow(
              settingKey: 'area',
              title: i18n('danmaku_area'),
              value: area.clamp(0, 1).toDouble(),
              min: 0,
              max: 1,
              display: '${(area * 100).toInt()}%',
              onChanged: (value) => set(Settings.danmakuArea, value),
            ),
            _CounterRow(
              settingKey: 'top',
              title: i18n('margin_top'),
              value: top.toInt().clamp(0, 300),
              min: 0,
              max: 300,
              onChanged: (value) => set(Settings.danmakuTopArea, value.toDouble()),
            ),
            _CounterRow(
              settingKey: 'bottom',
              title: i18n('margin_bottom'),
              value: bottom.toInt().clamp(0, 300),
              min: 0,
              max: 300,
              onChanged: (value) => set(Settings.danmakuBottomArea, value.toDouble()),
            ),
          ],
        ),
        PanelGroupTitle(i18n('style')),
        PanelCard(
          children: [
            _SliderRow(
              settingKey: 'opacity',
              title: i18n('opacity'),
              value: opacity.clamp(0, 1).toDouble(),
              min: 0,
              max: 1,
              display: '${(opacity * 100).toInt()}%',
              onChanged: (value) => set(Settings.danmakuOpacity, value),
            ),
            _SliderRow(
              settingKey: 'speed',
              title: i18n('speed'),
              value: speed.clamp(20, 400).toDouble(),
              min: 20,
              max: 400,
              display: '${speed.toInt()} px/s',
              onChanged: (value) => set(Settings.danmakuSpeed, value),
            ),
            _SliderRow(
              settingKey: 'fontSize',
              title: i18n('font_size'),
              value: fontSize.clamp(10, 30).toDouble(),
              min: 10,
              max: 30,
              display: '${fontSize.toStringAsFixed(1)} px',
              onChanged: (value) => set(Settings.danmakuFontSize, value),
            ),
            _SliderRow(
              settingKey: 'fontWeight',
              title: i18n('font_weight'),
              value: weight.clamp(100, 900).toDouble(),
              min: 100,
              max: 900,
              divisions: 8,
              display: i18n(danmakuFontWeightNames[weight] ?? 'font_weight_medium'),
              onChanged: (value) => set(Settings.danmakuFontWeight, (value / 100).round() * 100),
            ),
            _SwitchRow(
              settingKey: 'stroke',
              title: i18n('danmaku_stroke'),
              value: stroke,
              onChanged: (value) => set(Settings.enableDanmakuStroke, value),
            ),
            // D4: greyed out while the stroke is off, not hidden.
            _SliderRow(
              settingKey: 'strokeWidth',
              title: i18n('stroke'),
              value: border.clamp(0, 4).toDouble(),
              min: 0,
              max: 4,
              display: '${border.toStringAsFixed(1)} px',
              onChanged: stroke ? (value) => set(Settings.danmakuFontBorder, value) : null,
            ),
            _SwitchRow(
              settingKey: 'noEmoji',
              title: i18n('danmaku_no_emoji'),
              value: noEmoji,
              onChanged: (value) => set(Settings.noEmojiMode, value),
            ),
          ],
        ),
        PanelGroupTitle(i18n('danmaku_group_repeat')),
        PanelCard(
          children: [
            _SwitchRow(
              settingKey: 'collapse',
              title: i18n('collapse_repeated_danmaku'),
              subtitle: i18n('collapse_repeated_danmaku_desc'),
              value: collapse,
              onChanged: (value) => set(Settings.collapseRepeatedDanmaku, value),
            ),
            _CounterRow(
              settingKey: 'repeatWindow',
              title: i18n('repeated_danmaku_window'),
              value: window.clamp(1, 30),
              min: 1,
              max: 30,
              onChanged: collapse ? (value) => set(Settings.repeatedDanmakuWindowSeconds, value) : null,
            ),
          ],
        ),
        PanelGroupTitle(i18n('danmaku_group_interaction')),
        PanelCard(
          children: [
            _SwitchRow(
              settingKey: 'tap',
              title: i18n('danmaku_tap_action'),
              value: watchSetting(ref, Settings.enableDanmakuTapInteraction),
              onChanged: (value) => set(Settings.enableDanmakuTapInteraction, value),
            ),
            _SwitchRow(
              settingKey: 'longPress',
              title: i18n('danmaku_long_press_action'),
              value: watchSetting(ref, Settings.enableDanmakuLongPressInteraction),
              onChanged: (value) => set(Settings.enableDanmakuLongPressInteraction, value),
            ),
          ],
        ),
        PanelGroupTitle(i18n('danmaku_group_smoothness')),
        PanelCard(
          children: [
            _SwitchRow(
              settingKey: 'autoFps',
              title: i18n('settings_danmaku_auto_fps'),
              subtitle: i18n('danmaku_auto_fps_desc'),
              value: autoFps,
              onChanged: (value) => set(Settings.danmakuAutoFps, value),
            ),
            // D5: greyed out while it follows the display, with the rate in use.
            ValueListenableBuilder(
              valueListenable: DisplayMode.info,
              builder: (context, display, _) {
                final shown = resolvedDanmakuFps(
                  automatic: autoFps,
                  configured: fps,
                  mode: refreshMode,
                  maxRefreshRate: display?.maxRefreshRate,
                  currentRefreshRate: display?.currentRefreshRate,
                );
                return _SliderRow(
                  settingKey: 'fps',
                  title: i18n('danmaku_fps'),
                  value: (autoFps ? shown : fps).clamp(30, 240).toDouble(),
                  min: 30,
                  max: 240,
                  divisions: 210,
                  display: '$shown FPS',
                  onChanged: autoFps ? null : (value) => set(Settings.danmakuFps, value.round()),
                );
              },
            ),
          ],
        ),
        // v4's switches of the chat list (U.2a), kept with the danmaku.
        PanelGroupTitle(i18n('danmaku_list')),
        PanelCard(
          children: [
            ListenableSelector<bool>(
              listenable: controller,
              selector: () => controller.showGifts,
              builder: (context, showGifts, _) => _SwitchRow(
                settingKey: 'gifts',
                title: i18n('live_play_show_gifts'),
                subtitle: i18n('live_play_show_gifts_desc'),
                value: showGifts,
                onChanged: (value) => unawaited(controller.setShowGifts(show: value)),
              ),
            ),
            _Row(
              settingKey: 'listStyle',
              title: i18n('danmaku_list_style'),
              subtitle: i18n('danmaku_list_style_desc'),
              trailing: SegmentedButton<ChatListStyle>(
                key: const ValueKey('danmaku-list-style'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: ChatListStyle.compact, label: Text(i18n('danmaku_list_style_compact'))),
                  ButtonSegment(value: ChatListStyle.card, label: Text(i18n('danmaku_list_style_card'))),
                ],
                selected: {listStyle},
                onSelectionChanged: (selection) => set(Settings.danmakuListStyle, selection.first.name),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The four templates (3.x's names), the line about the chosen one and
/// "save as mine" / "use mine" (3.x's save and restore, D2).
class _Templates extends StatelessWidget {
  const new({required this.settings});

  final SettingsStore settings;

  Future<void> _apply(DanmakuTemplate template, {required bool preset}) async {
    await (preset ? template.applyPreset(settings) : template.apply(settings));
    AppNavigator.toast(i18n('danmaku_template_applied'));
  }

  Future<void> _save() async {
    await settings.set(Settings.savedDanmakuTemplate, DanmakuTemplate.of(settings).encode());
    AppNavigator.toast(i18n('danmaku_template_saved'));
  }

  Future<void> _restore() async {
    final saved = settings.get(Settings.savedDanmakuTemplate);
    if (saved.trim().isEmpty) {
      AppNavigator.toast(i18n('danmaku_template_empty'));
      return;
    }
    final template = DanmakuTemplate.tryDecode(saved, DanmakuTemplate.of(settings));
    if (template == null) {
      AppNavigator.toast(i18n('danmaku_template_invalid'));
      return;
    }
    await _apply(template, preset: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chosen = DanmakuTemplate.presetOf(DanmakuTemplate.of(settings));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (key, template) in DanmakuTemplate.presets)
                ChoiceChip(
                  key: ValueKey('danmaku-template-$key'),
                  label: Text(i18n(key)),
                  selected: chosen == key,
                  onSelected: (_) => unawaited(_apply(template, preset: true)),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              i18n(danmakuTemplateDescription(chosen)),
              key: const ValueKey('danmaku-template-description'),
              style: theme.textTheme.bodyMedium?.regular.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Wrap(
            children: [
              TextButton.icon(
                key: const ValueKey('danmaku-template-save'),
                onPressed: () => unawaited(_save()),
                icon: const Icon(AppIcons.templateSave, size: 18),
                label: Text(i18n('danmaku_template_save_mine')),
              ),
              TextButton.icon(
                key: const ValueKey('danmaku-template-load'),
                onPressed: () => unawaited(_restore()),
                icon: const Icon(AppIcons.templateRestore, size: 18),
                label: Text(i18n('danmaku_template_use_mine')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

TextStyle? _titleStyle(ThemeData theme, {required bool enabled}) => theme.textTheme.bodyLarge?.regular.copyWith(
  fontSize: 15,
  color: enabled ? theme.colorScheme.onSurface : theme.colorScheme.onSurface.withValues(alpha: 0.38),
);

/// A row with a title (and a line under it) and a control on the right.
class _Row extends StatelessWidget {
  const new({
    required this.settingKey,
    required this.title,
    required this.trailing,
    this.subtitle,
    this.enabled = true,
  });

  final String settingKey;
  final String title;
  final String? subtitle;
  final Widget trailing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      key: ValueKey('danmaku-setting-$settingKey'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _titleStyle(theme, enabled: enabled)),
                if (subtitle case final text?)
                  Text(
                    text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: enabled ? scheme.onSurfaceVariant : scheme.onSurface.withValues(alpha: 0.38),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const new({
    required this.settingKey,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String settingKey;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: InkWell(
      // The whole row switches, as 3.x's `SwitchListTile`.
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: _Row(
        settingKey: settingKey,
        title: title,
        subtitle: subtitle,
        enabled: onChanged != null,
        trailing: Switch(key: ValueKey('danmaku-switch-$settingKey'), value: value, onChanged: onChanged),
      ),
    ),
  );
}

/// A title with its value on the right and a slider under it (3.x
/// `_slider`); a null [onChanged] greys it out.
class _SliderRow extends StatelessWidget {
  const new({
    required this.settingKey,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    this.divisions,
  });

  final String settingKey;
  final String title;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String display;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onChanged != null;
    return Padding(
      key: ValueKey('danmaku-setting-$settingKey'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: _titleStyle(theme, enabled: enabled)),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: enabled ? 0.1 : 0.05),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Text(
                    display,
                    key: ValueKey('danmaku-value-$settingKey'),
                    style: theme.textTheme.labelMedium?.emphasis.tabular.copyWith(
                      color: enabled ? scheme.primary : scheme.onSurface.withValues(alpha: 0.38),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Slider(
            key: ValueKey('danmaku-slider-$settingKey'),
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            semanticFormatterCallback: (_) => '$title, $display',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// A title with a − value + stepper (3.x `_counter`, `CountButton`); a null
/// [onChanged] greys it out.
class _CounterRow extends StatelessWidget {
  const new({
    required this.settingKey,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String settingKey;
  final String title;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onChanged != null;
    final ink = enabled ? scheme.onSurfaceVariant : scheme.onSurface.withValues(alpha: 0.38);
    return _Row(
      settingKey: settingKey,
      title: title,
      enabled: enabled,
      trailing: IgnorePointer(
        ignoring: !enabled,
        child: CountButton(
          key: ValueKey('danmaku-counter-$settingKey'),
          minValue: min,
          maxValue: max,
          selectedValue: value,
          buttonSize: const Size(40, 40),
          backgroundColor: scheme.surface,
          foregroundColor: ink,
          semanticLabel: title,
          decrementSemanticLabel: i18n('decrease_value', args: {'label': title}),
          incrementSemanticLabel: i18n('increase_value', args: {'label': title}),
          textStyle: theme.textTheme.titleSmall?.emphasis.tabular.copyWith(
            color: enabled ? scheme.primary : scheme.onSurface.withValues(alpha: 0.38),
          ),
          onChanged: (next) => onChanged?.call(next),
        ),
      ),
    );
  }
}
