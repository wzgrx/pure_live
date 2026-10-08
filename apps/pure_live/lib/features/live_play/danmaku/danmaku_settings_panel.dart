import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/danmaku/chat_list_settings.dart';
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
    showRoomPanelSheet(
      context,
      builder: (_, close) => RoomDanmakuSettingsPanel(controller: controller, onClose: close),
    ),
  );
}

/// The danmaku settings panel (docs/A-界面设计/A07-直播间界面/A07.6-直播间弹窗, 弹幕设置): under the
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
class RoomDanmakuSettings extends StatelessWidget {
  /// Creates the settings.
  const new({required this.controller, this.inTab = false, super.key});

  /// The room.
  final LiveRoomController controller;

  /// In the room's "弹幕设置" tab: no header, so "改动立即生效" sits right of
  /// the first group's title (U.2e c8).
  final bool inTab;

  @override
  Widget build(BuildContext context) {
    return DanmakuSettingsContent(
      hint: inTab ? i18n('danmaku_settings_live_hint') : null,
      // U.2e c9 (E1): the chat list's look and gifts (U.2a, v4), then 3.x's
      // picture-in-picture danmaku; in the tab and the panel alike, and on
      // 设置 → 弹幕 (A08.6).
      extra: danmakuListAndPipGroups(),
    );
  }
}
