import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/danmaku/masked_blocks.dart';

/// The room's actions on [message] (UI_PLAN §7: a long-pressed danmaku is a
/// panel; docs/ui/compare/U.2n c1): the chat list's long press and a tap or
/// long press on a flying danmaku (F.2b) open the same panel, under the
/// picture in portrait and on the right in landscape; where there is no
/// room page around [context], in a sheet. Completes when the panel closes
/// (the flying danmaku stand until then, 3.x).
Future<void> showRoomMessageActions(BuildContext context, LiveRoomController controller, LiveMessage message) {
  final panels = RoomPanelScope.maybeOf(context);
  if (panels == null) {
    return showRoomPanelSheet(
      context,
      heightFactor: 0.5,
      builder: (sheetContext, close) => RoomMessagePanel(controller: controller, message: message, onClose: close),
    );
  }
  panels.openMessage(message);
  final closed = Completer<void>();
  void watch() {
    if (panels.value == RoomPanelKind.message && identical(panels.message, message)) return;
    panels.removeListener(watch);
    closed.complete();
  }

  panels.addListener(watch);
  return closed.future;
}

/// The panel of a long-pressed danmaku (3.x `DanmakuMessageActions`,
/// docs/ui/compare/U.2f 长按弹幕): "弹幕" and ✕, the message in a card (the
/// name in its colour), then copy, block the viewer and block a keyword,
/// each saying what it does. "屏蔽关键词…" closes the panel and opens the
/// app's input dialog filled with the message, to cut down to the word
/// (U.1d c8: one line, at most 40, "屏蔽"). A local danmaku and a masked name
/// (a Bilibili guest's `观***`, [isMaskedViewerName], B01 c1) have no
/// "屏蔽此用户".
class RoomMessagePanel extends StatelessWidget {
  /// Creates the panel.
  const new({
    required this.controller,
    required this.message,
    required this.onClose,
    this.dragToClose = false,
    super.key,
  });

  /// The room.
  final LiveRoomController controller;

  /// The danmaku.
  final LiveMessage message;

  /// Closes the panel.
  final VoidCallback onClose;

  /// A downward drag on the header closes it (portrait).
  final bool dragToClose;

  /// The longest keyword (3.x's field counted to 40).
  static const int keywordMaxLength = 40;

  Future<void> _blockKeyword(BuildContext context) async {
    final keyword = await showAppInputDialog(
      context: context,
      key: const ValueKey('live-play-keyword-dialog'),
      title: i18n('block_danmaku_keyword'),
      confirmLabel: i18n('live_play_block_action'),
      initial: message.message,
      hint: i18n('please_enter_keyword'),
      helper: i18n('live_play_block_word_desc'),
      maxLength: keywordMaxLength,
      fieldKey: const ValueKey('live-play-keyword-input'),
      confirmKey: const ValueKey('live-play-keyword-confirm'),
    );
    if (keyword == null || keyword.trim().isEmpty) return;
    await controller.blockKeyword(keyword);
    AppNavigator.toast(i18n('danmaku_keyword_blocked'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = message.userName.trim();
    final body = theme.textTheme.bodyLarge?.regular;
    final hint = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    return RoomSidePanel(
      key: const ValueKey('live-play-message-panel'),
      title: i18n('danmaku'),
      onClose: onClose,
      dragToClose: dragToClose,
      child: ListView(
        key: const ValueKey('live-play-message-sheet'),
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: DecoratedBox(
              key: const ValueKey('live-play-message-card'),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text.rich(
                  TextSpan(
                    children: [
                      if (name.isNotEmpty)
                        TextSpan(
                          text: '$name：',
                          style: body?.copyWith(
                            color: chatNameColor(message.color, theme.brightness) ?? scheme.onSurfaceVariant,
                          ),
                        ),
                      TextSpan(
                        text: message.message,
                        style: body?.copyWith(color: scheme.onSurface),
                      ),
                    ],
                  ),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          ListTile(
            key: const ValueKey('live-play-copy-message'),
            leading: const Icon(AppIcons.copy),
            title: Text(i18n('copy')),
            onTap: () async {
              onClose();
              // 3.x copied "用户名: 内容".
              await Clipboard.setData(ClipboardData(text: chatCopyText(message)));
              AppNavigator.toast(i18n('copied_to_clipboard'));
            },
          ),
          // 3.x: a local danmaku cannot block its sender. B-1: nor can a
          // masked name, which stands for many viewers.
          if (name.isNotEmpty && !message.isLocal && !isMaskedViewerName(name))
            ListTile(
              key: const ValueKey('live-play-block-user'),
              leading: const Icon(AppIcons.blockUser),
              title: Text(i18n('live_play_block_viewer')),
              subtitle: Text(i18n('live_play_block_viewer_desc', args: {'name': name}), style: hint),
              onTap: () async {
                onClose();
                await controller.blockUser(name);
                AppNavigator.toast(i18n('live_play_user_blocked', args: {'name': name}));
              },
            ),
          ListTile(
            key: const ValueKey('live-play-block-keyword'),
            leading: const Icon(AppIcons.blockKeyword),
            title: Text(i18n('live_play_block_word')),
            subtitle: Text(i18n('live_play_block_word_desc'), style: hint),
            onTap: () {
              // The panel goes first (a sheet's close pops the top route);
              // its context stays while it slides out.
              onClose();
              unawaited(_blockKeyword(context));
            },
          ),
        ],
      ),
    );
  }
}
