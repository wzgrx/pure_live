import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/display_mode.dart';
import 'package:pure_live/shared/danmaku/danmaku_color_dialog.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings_content.dart';
import 'package:pure_live/shared/danmaku/danmaku_templates.dart';
import 'package:pure_live/shared/danmaku/setting_rows.dart';

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

/// The danmaku settings of the room: the shared [DanmakuSettingsContent]
/// (U.2f), then the chat list's look and gifts and 3.x's
/// picture-in-picture danmaku (U.2e c9, E1). The panel and the room's
/// "弹幕设置" tab show this same content.
class RoomDanmakuSettings extends ConsumerWidget {
  /// Creates the settings.
  const new({required this.controller, this.inTab = false, super.key});

  /// The room.
  final LiveRoomController controller;

  /// In the room's "弹幕设置" tab: no header, so "改动立即生效" sits right of
  /// the first group's title (U.2e c8).
  final bool inTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(storeProvider).settings;
    void set<T extends Object>(Setting<T> setting, T value) => unawaited(settings.set(setting, value));
    final listStyle = ChatListStyle.of(watchSetting(ref, Settings.danmakuListStyle));
    return DanmakuSettingsContent(
      hint: inTab ? i18n('danmaku_settings_live_hint') : null,
      extra: [
        // U.2e c9 (E1): the chat list's look and gifts (U.2a, v4), then 3.x's
        // picture-in-picture danmaku; in the tab and the panel alike.
        PanelGroupTitle(i18n('danmaku_list')),
        PanelCard(
          children: [
            SettingRow(
              settingKey: 'listStyle',
              title: i18n('danmaku_list_style'),
              subtitle: i18n('danmaku_list_style_desc'),
              trailing: const SizedBox.shrink(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SegmentedButton<ChatListStyle>(
                key: const ValueKey('danmaku-list-style'),
                segments: [
                  ButtonSegment(value: ChatListStyle.compact, label: Text(i18n('danmaku_list_style_compact'))),
                  ButtonSegment(value: ChatListStyle.card, label: Text(i18n('danmaku_list_style_card'))),
                ],
                selected: {listStyle},
                onSelectionChanged: (selection) => set(Settings.danmakuListStyle, selection.first.name),
              ),
            ),
            ListenableSelector<bool>(
              listenable: controller,
              selector: () => controller.showGifts,
              builder: (context, showGifts, _) => SettingSwitchRow(
                settingKey: 'gifts',
                title: i18n('live_play_show_gifts'),
                subtitle: i18n('live_play_show_gifts_desc'),
                value: showGifts,
                onChanged: (value) => unawaited(controller.setShowGifts(show: value)),
              ),
            ),
          ],
        ),
        PanelGroupTitle(i18n('pip_danmaku')),
        const PipDanmakuSettings(),
      ],
    );
  }
}

/// 3.x's picture-in-picture danmaku (`PipDanmakuSettingsSection`, the end of
/// its danmaku tab), every setting with its range (U.2e c9, c10): the rest
/// folds away while "小窗显示弹幕" is off (3.x); the values carry their units
/// like the main danmaku's; "统一弹幕颜色" greys out while the platform's
/// colours are kept instead of vanishing.
class PipDanmakuSettings extends ConsumerWidget {
  /// Creates the group.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(storeProvider).settings;
    void set<T extends Object>(Setting<T> setting, T value) => unawaited(settings.set(setting, value));
    final enabled = watchSetting(ref, Settings.enablePipDanmaku);
    final rows = <Widget>[
      SettingSwitchRow(
        settingKey: 'pip',
        title: i18n('pip_danmaku_enable'),
        subtitle: i18n('pip_danmaku_desc'),
        value: enabled,
        onChanged: (value) => set(Settings.enablePipDanmaku, value),
      ),
    ];
    if (enabled) {
      final keepColors = watchSetting(ref, Settings.pipDanmakuUseOriginalColor);
      final color = Color(watchSetting(ref, Settings.pipDanmakuColor));
      final fontSize = watchSetting(ref, Settings.pipDanmakuFontSize);
      final weight = watchSetting(ref, Settings.pipDanmakuFontWeight);
      final speed = watchSetting(ref, Settings.pipDanmakuSpeed);
      final opacity = watchSetting(ref, Settings.pipDanmakuOpacity);
      final area = watchSetting(ref, Settings.pipDanmakuArea);
      final interval = watchSetting(ref, Settings.pipDanmakuEmitInterval);
      final autoFps = watchSetting(ref, Settings.pipDanmakuAutoFps);
      final fps = watchSetting(ref, Settings.pipDanmakuFps);
      final refreshMode = watchSetting(ref, Settings.refreshRateMode);
      rows.addAll([
        SettingSwitchRow(
          settingKey: 'pipNoEmoji',
          title: i18n('danmaku_no_emoji'),
          value: watchSetting(ref, Settings.pipDanmakuNoEmojiMode),
          onChanged: (value) => set(Settings.pipDanmakuNoEmojiMode, value),
        ),
        SettingSwitchRow(
          settingKey: 'pipAutoScale',
          title: i18n('pip_danmaku_auto_scale'),
          value: watchSetting(ref, Settings.pipDanmakuAutoScale),
          onChanged: (value) => set(Settings.pipDanmakuAutoScale, value),
        ),
        SettingSwitchRow(
          settingKey: 'pipOriginalColor',
          title: i18n('pip_danmaku_original_color'),
          value: keepColors,
          onChanged: (value) => set(Settings.pipDanmakuUseOriginalColor, value),
        ),
        // c10: greyed out while the platform's colours are kept.
        InkWell(
          onTap: keepColors
              ? null
              : () async {
                  final picked = await showDanmakuColorDialog(
                    context: context,
                    title: i18n('pip_danmaku_color'),
                    current: color,
                  );
                  if (picked != null) set(Settings.pipDanmakuColor, picked.toARGB32());
                },
          child: SettingRow(
            settingKey: 'pipColor',
            title: i18n('pip_danmaku_color'),
            enabled: !keepColors,
            trailing: DanmakuColorChip(color: color, enabled: !keepColors),
          ),
        ),
        SettingSliderRow(
          settingKey: 'pipFontSize',
          title: i18n('font_size'),
          value: fontSize.clamp(8, 24).toDouble(),
          min: 8,
          max: 24,
          display: '${fontSize.toStringAsFixed(1)} px',
          onChanged: (value) => set(Settings.pipDanmakuFontSize, value),
        ),
        SettingSliderRow(
          settingKey: 'pipFontWeight',
          title: i18n('font_weight'),
          value: weight.clamp(100, 900).toDouble(),
          min: 100,
          max: 900,
          divisions: 8,
          display: i18n(danmakuFontWeightNames[weight] ?? 'font_weight_normal'),
          onChanged: (value) => set(Settings.pipDanmakuFontWeight, (value / 100).round() * 100),
        ),
        SettingSliderRow(
          settingKey: 'pipSpeed',
          title: i18n('speed'),
          value: speed.clamp(20, 400).toDouble(),
          min: 20,
          max: 400,
          display: '${speed.toStringAsFixed(0)} px/s',
          onChanged: (value) => set(Settings.pipDanmakuSpeed, value),
        ),
        SettingSliderRow(
          settingKey: 'pipOpacity',
          title: i18n('opacity'),
          value: opacity.clamp(0.1, 1).toDouble(),
          min: 0.1,
          max: 1,
          display: '${(opacity * 100).toInt()}%',
          onChanged: (value) => set(Settings.pipDanmakuOpacity, value),
        ),
        SettingSliderRow(
          settingKey: 'pipArea',
          title: i18n('danmaku_area'),
          value: area.clamp(0.1, 1).toDouble(),
          min: 0.1,
          max: 1,
          display: '${(area * 100).toInt()}%',
          onChanged: (value) => set(Settings.pipDanmakuArea, value),
        ),
        SettingCounterRow(
          settingKey: 'pipMaxVisible',
          title: i18n('pip_danmaku_max_visible'),
          value: watchSetting(ref, Settings.pipDanmakuMaxVisibleCount).clamp(1, 20),
          min: 1,
          max: 20,
          onChanged: (value) => set(Settings.pipDanmakuMaxVisibleCount, value),
        ),
        SettingSliderRow(
          settingKey: 'pipInterval',
          title: i18n('pip_danmaku_interval'),
          value: interval.clamp(0.05, 2).toDouble(),
          min: 0.05,
          max: 2,
          display: i18n('pip_danmaku_interval_seconds', args: {'seconds': interval.toStringAsFixed(2)}),
          onChanged: (value) => set(Settings.pipDanmakuEmitInterval, value),
        ),
        SettingSwitchRow(
          settingKey: 'pipAutoFps',
          title: i18n('settings_danmaku_auto_fps'),
          subtitle: i18n('pip_danmaku_fps_follow_desc'),
          value: autoFps,
          onChanged: (value) => set(Settings.pipDanmakuAutoFps, value),
        ),
        ValueListenableBuilder(
          valueListenable: DisplayMode.info,
          builder: (context, display, _) {
            final shown = resolvedDanmakuFps(
              automatic: autoFps,
              configured: fps,
              mode: refreshMode,
              maxRefreshRate: display?.maxRefreshRate,
              currentRefreshRate: display?.currentRefreshRate,
              pip: true,
            );
            return SettingSliderRow(
              settingKey: 'pipFps',
              title: i18n('danmaku_fps'),
              value: (autoFps ? shown : fps).clamp(15, 240).toDouble(),
              min: 15,
              max: 240,
              divisions: 225,
              display: '$shown FPS',
              onChanged: autoFps ? null : (value) => set(Settings.pipDanmakuFps, value.round()),
            );
          },
        ),
      ]);
    }
    return PanelCard(children: rows);
  }
}
