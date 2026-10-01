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
import 'package:pure_live/shared/danmaku/danmaku_settings_content.dart';

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

/// The danmaku settings of the room ([DanmakuSettingsContent]) with v4's
/// switches of the chat list last (gifts, the list's look: U.2a).
class RoomDanmakuSettings extends ConsumerWidget {
  /// Creates the settings.
  const new({required this.controller, super.key});

  /// The room.
  final LiveRoomController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(storeProvider).settings;
    void set<T extends Object>(Setting<T> setting, T value) => unawaited(settings.set(setting, value));
    final listStyle = ChatListStyle.of(watchSetting(ref, Settings.danmakuListStyle));
    return DanmakuSettingsContent(
      extra: [
        PanelGroupTitle(i18n('danmaku_list')),
        PanelCard(
          children: [
            ListenableSelector<bool>(
              listenable: controller,
              selector: () => controller.showGifts,
              builder: (context, showGifts, _) => DanmakuSwitchRow(
                settingKey: 'gifts',
                title: i18n('live_play_show_gifts'),
                subtitle: i18n('live_play_show_gifts_desc'),
                value: showGifts,
                onChanged: (value) => unawaited(controller.setShowGifts(show: value)),
              ),
            ),
            DanmakuSettingRow(
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
