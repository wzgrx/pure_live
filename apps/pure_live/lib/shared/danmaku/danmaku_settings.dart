import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/danmaku/danmaku_overlay.dart';

// The danmaku look and its settings panel, shared by the live room and the
// multi-view page (M12.2).

/// The danmaku look from the settings.
DanmakuLook danmakuLookOf(WidgetRef ref) => DanmakuLook(
  fontSize: watchSetting(ref, Settings.danmakuFontSize),
  fontWeight: watchSetting(ref, Settings.danmakuFontWeight),
  speed: watchSetting(ref, Settings.danmakuSpeed),
  opacity: watchSetting(ref, Settings.danmakuOpacity),
  area: watchSetting(ref, Settings.danmakuArea),
  // Pixels kept free above and below (3.x `danmakuTopArea`/`BottomArea`).
  topMargin: watchSetting(ref, Settings.danmakuTopArea),
  bottomMargin: watchSetting(ref, Settings.danmakuBottomArea),
  stroke: watchSetting(ref, Settings.enableDanmakuStroke),
  strokeWidth: watchSetting(ref, Settings.danmakuFontBorder),
);

/// The main danmaku settings (3.x `DanmakuSettingsPage`, first part): they
/// apply to the video at once.
class DanmakuSettingsPanel extends ConsumerWidget {
  /// Creates the panel; [leading] goes above the settings (the live room's
  /// viewing templates).
  const new({this.leading = const [], super.key});

  /// Widgets above the settings.
  final List<Widget> leading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(storeProvider).settings;
    void set<T extends Object>(Setting<T> setting, T value) => unawaited(settings.set(setting, value));
    final area = watchSetting(ref, Settings.danmakuArea);
    final opacity = watchSetting(ref, Settings.danmakuOpacity);
    final speed = watchSetting(ref, Settings.danmakuSpeed);
    final fontSize = watchSetting(ref, Settings.danmakuFontSize);
    final weight = watchSetting(ref, Settings.danmakuFontWeight);
    final border = watchSetting(ref, Settings.danmakuFontBorder);
    final repeatWindow = watchSetting(ref, Settings.repeatedDanmakuWindowSeconds);
    final threshold = watchSetting(ref, Settings.danmakuSimilarityThreshold);
    final top = watchSetting(ref, Settings.danmakuTopArea);
    final bottom = watchSetting(ref, Settings.danmakuBottomArea);
    return ListView(
      key: const ValueKey('live-play-danmaku-settings'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        Text(i18n('danmaku_realtime_hint'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        ...leading,
        context.buildModernCard([
          context.buildSwitchTile(
            title: i18n('show_danmaku'),
            icon: Icons.subtitles_rounded,
            value: watchSetting(ref, Settings.enableDanmakuDisplay),
            onChanged: (value) => set(Settings.enableDanmakuDisplay, value),
          ),
          context.buildSwitchTile(
            title: i18n('live_play_danmaku_on_video'),
            icon: Icons.layers_outlined,
            value: !watchSetting(ref, Settings.hideDanmaku),
            onChanged: (value) => set(Settings.hideDanmaku, !value),
          ),
          context.buildSwitchTile(
            title: i18n('danmaku_stroke'),
            icon: Icons.format_color_text_rounded,
            value: watchSetting(ref, Settings.enableDanmakuStroke),
            onChanged: (value) => set(Settings.enableDanmakuStroke, value),
          ),
        ]),
        context.buildModernCard([
          context.buildSliderTile(
            icon: Icons.height_rounded,
            title: i18n('live_play_danmaku_area'),
            value: area,
            min: 0.1,
            max: 1,
            displayValue: '${(area * 100).round()}%',
            onChanged: (value) => set(Settings.danmakuArea, (value * 20).round() / 20),
          ),
          context.buildSliderTile(
            icon: Icons.vertical_align_top_rounded,
            title: i18n('settings_danmaku_top_margin'),
            value: top.clamp(0, 300).toDouble(),
            min: 0,
            max: 300,
            displayValue: '${top.round()}',
            onChanged: (value) => set(Settings.danmakuTopArea, (value / 5).round() * 5.0),
          ),
          context.buildSliderTile(
            icon: Icons.vertical_align_bottom_rounded,
            title: i18n('live_play_danmaku_bottom_margin'),
            value: bottom.clamp(0, 300).toDouble(),
            min: 0,
            max: 300,
            displayValue: '${bottom.round()}',
            onChanged: (value) => set(Settings.danmakuBottomArea, (value / 5).round() * 5.0),
          ),
          context.buildSliderTile(
            icon: Icons.opacity_rounded,
            title: i18n('opacity'),
            value: opacity,
            min: 0.1,
            max: 1,
            displayValue: '${(opacity * 100).round()}%',
            onChanged: (value) => set(Settings.danmakuOpacity, (value * 20).round() / 20),
          ),
          context.buildSliderTile(
            icon: Icons.speed_rounded,
            title: i18n('speed'),
            value: speed.clamp(30, 400),
            min: 30,
            max: 400,
            displayValue: '${speed.round()}',
            onChanged: (value) => set(Settings.danmakuSpeed, value.roundToDouble()),
          ),
          context.buildSliderTile(
            icon: Icons.format_size_rounded,
            title: i18n('font_size'),
            value: fontSize.clamp(10, 40),
            min: 10,
            max: 40,
            displayValue: '${fontSize.round()}',
            onChanged: (value) => set(Settings.danmakuFontSize, value.roundToDouble()),
          ),
          context.buildSliderTile(
            icon: Icons.format_bold_rounded,
            title: i18n('font_weight'),
            value: weight.clamp(100, 900).toDouble(),
            min: 100,
            max: 900,
            displayValue: '$weight',
            onChanged: (value) => set(Settings.danmakuFontWeight, (value / 100).round() * 100),
          ),
          context.buildSliderTile(
            icon: Icons.border_style_rounded,
            title: i18n('stroke'),
            value: border,
            min: 0,
            max: 4,
            displayValue: border.toStringAsFixed(1),
            onChanged: (value) => set(Settings.danmakuFontBorder, (value * 2).round() / 2),
          ),
        ]),
        context.buildGroupTitle(i18n('platform_danmaku_filter')),
        context.buildModernCard([
          context.buildSwitchTile(
            title: i18n('collapse_repeated_danmaku'),
            subtitle: i18n('collapse_repeated_danmaku_desc'),
            icon: Icons.filter_list_rounded,
            value: watchSetting(ref, Settings.collapseRepeatedDanmaku),
            onChanged: (value) => set(Settings.collapseRepeatedDanmaku, value),
          ),
          context.buildSliderTile(
            icon: Icons.timer_outlined,
            title: i18n('repeated_danmaku_window'),
            value: repeatWindow.clamp(1, 30).toDouble(),
            min: 1,
            max: 30,
            displayValue: '$repeatWindow',
            onChanged: (value) => set(Settings.repeatedDanmakuWindowSeconds, value.round()),
          ),
          context.buildSwitchTile(
            title: i18n('danmaku_similarity_filter_enable'),
            icon: Icons.compare_arrows_rounded,
            value: watchSetting(ref, Settings.enableDanmakuSimilarityFilter),
            onChanged: (value) => set(Settings.enableDanmakuSimilarityFilter, value),
          ),
          context.buildSliderTile(
            icon: Icons.tune_rounded,
            title: i18n('danmaku_similarity_threshold'),
            value: threshold.clamp(50, 100).toDouble(),
            min: 50,
            max: 100,
            displayValue: '$threshold%',
            onChanged: (value) => set(Settings.danmakuSimilarityThreshold, value.round()),
          ),
        ]),
      ],
    );
  }
}
