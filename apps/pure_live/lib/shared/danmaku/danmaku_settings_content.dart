import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/display_mode.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings.dart';
import 'package:pure_live/shared/danmaku/danmaku_templates.dart';
import 'package:pure_live/shared/danmaku/setting_rows.dart';

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

/// Every danmaku setting of 3.x's `DanmakuSettingsContent`
/// (`pages/danmaku_settings_page.dart:195-420`), with its ranges and keys,
/// grouped as U.2f confirmed: 观看模板, 显示范围, 样式, 重复弹幕, 画面弹幕交互,
/// 流畅度 (显示范围 also holds "暂停时的弹幕", B02 c3, new in v4); then the
/// groups of [extra] (the live room's chat list and
/// picture-in-picture danmaku). Settings that depend on a switch grey out
/// instead of vanishing (D4, D5). Everything applies at once. The live
/// room's panel and tab and the multi-view's panel (docs/ui/compare/U.8)
/// show this same content.
class DanmakuSettingsContent extends ConsumerWidget {
  /// Creates the settings.
  const new({this.extra = const [], this.hint, super.key});

  /// Groups after the danmaku's own (a [PanelGroupTitle] and a [PanelCard]).
  final List<Widget> extra;

  /// A note right of the first group's title where no panel header carries
  /// it ("改动立即生效" in the room's tab, U.2e c8).
  final String? hint;

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
    final paused = watchSetting(ref, Settings.danmakuPausedBehavior);
    watchSetting(ref, Settings.savedDanmakuTemplate);
    return ListView(
      key: const ValueKey('live-play-danmaku-settings'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        PanelGroupTitle(i18n('danmaku_group_templates'), trailing: hint),
        _Templates(settings: settings),
        PanelGroupTitle(i18n('danmaku_group_range')),
        PanelCard(
          children: [
            SettingSliderRow(
              settingKey: 'area',
              title: i18n('danmaku_area'),
              value: area.clamp(0, 1).toDouble(),
              min: 0,
              max: 1,
              display: '${(area * 100).toInt()}%',
              onChanged: (value) => set(Settings.danmakuArea, value),
            ),
            SettingCounterRow(
              settingKey: 'top',
              title: i18n('margin_top'),
              value: top.toInt().clamp(0, 300),
              min: 0,
              max: 300,
              onChanged: (value) => set(Settings.danmakuTopArea, value.toDouble()),
            ),
            SettingCounterRow(
              settingKey: 'bottom',
              title: i18n('margin_bottom'),
              value: bottom.toInt().clamp(0, 300),
              min: 0,
              max: 300,
              onChanged: (value) => set(Settings.danmakuBottomArea, value.toDouble()),
            ),
            // B02 c3: what the flying danmaku do while the video is paused.
            SettingRow(
              settingKey: 'pausedBehavior',
              title: i18n('danmaku_paused_behavior'),
              subtitle: i18n('danmaku_paused_behavior_desc'),
              trailing: const SizedBox.shrink(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SegmentedButton<String>(
                key: const ValueKey('danmaku-paused-behavior'),
                segments: [
                  ButtonSegment(value: DanmakuPausedBehavior.pause, label: Text(i18n('danmaku_paused_pause'))),
                  ButtonSegment(value: DanmakuPausedBehavior.fly, label: Text(i18n('danmaku_paused_fly'))),
                ],
                selected: {paused},
                onSelectionChanged: (selection) => set(Settings.danmakuPausedBehavior, selection.first),
              ),
            ),
          ],
        ),
        PanelGroupTitle(i18n('style')),
        PanelCard(
          children: [
            SettingSliderRow(
              settingKey: 'opacity',
              title: i18n('opacity'),
              value: opacity.clamp(0, 1).toDouble(),
              min: 0,
              max: 1,
              display: '${(opacity * 100).toInt()}%',
              onChanged: (value) => set(Settings.danmakuOpacity, value),
            ),
            SettingSliderRow(
              settingKey: 'speed',
              title: i18n('speed'),
              value: speed.clamp(20, 400).toDouble(),
              min: 20,
              max: 400,
              display: '${speed.toInt()} px/s',
              onChanged: (value) => set(Settings.danmakuSpeed, value),
            ),
            SettingSliderRow(
              settingKey: 'fontSize',
              title: i18n('font_size'),
              value: fontSize.clamp(10, 30).toDouble(),
              min: 10,
              max: 30,
              display: '${fontSize.toStringAsFixed(1)} px',
              onChanged: (value) => set(Settings.danmakuFontSize, value),
            ),
            SettingSliderRow(
              settingKey: 'fontWeight',
              title: i18n('font_weight'),
              value: weight.clamp(100, 900).toDouble(),
              min: 100,
              max: 900,
              divisions: 8,
              display: i18n(danmakuFontWeightNames[weight] ?? 'font_weight_medium'),
              onChanged: (value) => set(Settings.danmakuFontWeight, (value / 100).round() * 100),
            ),
            SettingSwitchRow(
              settingKey: 'stroke',
              title: i18n('danmaku_stroke'),
              value: stroke,
              onChanged: (value) => set(Settings.enableDanmakuStroke, value),
            ),
            // D4: greyed out while the stroke is off, not hidden.
            SettingSliderRow(
              settingKey: 'strokeWidth',
              title: i18n('stroke'),
              value: border.clamp(0, 4).toDouble(),
              min: 0,
              max: 4,
              display: '${border.toStringAsFixed(1)} px',
              onChanged: stroke ? (value) => set(Settings.danmakuFontBorder, value) : null,
            ),
            SettingSwitchRow(
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
            SettingSwitchRow(
              settingKey: 'collapse',
              title: i18n('collapse_repeated_danmaku'),
              subtitle: i18n('collapse_repeated_danmaku_desc'),
              value: collapse,
              onChanged: (value) => set(Settings.collapseRepeatedDanmaku, value),
            ),
            SettingCounterRow(
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
            SettingSwitchRow(
              settingKey: 'tap',
              title: i18n('danmaku_tap_action'),
              value: watchSetting(ref, Settings.enableDanmakuTapInteraction),
              onChanged: (value) => set(Settings.enableDanmakuTapInteraction, value),
            ),
            SettingSwitchRow(
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
            SettingSwitchRow(
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
                return SettingSliderRow(
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
        ...extra,
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
