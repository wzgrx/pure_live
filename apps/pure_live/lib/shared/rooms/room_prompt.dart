import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/app_prompts.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// The user's answer to [showRoomPrompt].
enum RoomPromptChoice {
  /// Open the room.
  enter,

  /// Not now (also a tap outside, Back and Esc).
  dismiss,
}

/// Asks whether to open [room], found as a share code on the clipboard (3.x
/// `ShareCommandImportDialog`, docs/ui/compare/U.3d c11). The dialog waits
/// its turn among the app's prompts ([AppPrompts], before the update
/// prompt) and may open over any page, a full-screen room too.
///
/// The caller opens the room on [RoomPromptChoice.enter] (3.x), right away:
/// the next prompt looks a frame later, with the room on top.
Future<RoomPromptChoice> showRoomPrompt(BuildContext context, {required LiveRoom room, AppPrompts? prompts}) async =>
    await (prompts ?? AppPrompts.instance).show<RoomPromptChoice>(AppPromptKind.share, () async {
      if (!context.mounted) return RoomPromptChoice.dismiss;
      return await showDialog<RoomPromptChoice>(
        context: context,
        builder: (_) => RoomPromptDialog(room: room),
      );
    }) ??
    RoomPromptChoice.dismiss;

/// The dialog of [showRoomPrompt]: "打开分享的直播间", "从剪贴板识别到分享口令",
/// the avatar, the room's title and "主播 · 平台 · 房间号 …", then "取消" and
/// "进入房间". 3.x titled it "分享", showed the platform's id and boxed the
/// ids in a frame of their own (S1–S3).
class RoomPromptDialog extends StatelessWidget {
  /// Creates the dialog for [room].
  const new({required this.room, super.key});

  /// The room found.
  final LiveRoom room;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final styles = context.textStyles;
    final platform = platformName(room.platform);
    final title = room.title.trim();
    final nick = room.nick.trim();
    // A narrow window or a large system font puts the avatar on top (3.x).
    final stacked = MediaQuery.sizeOf(context).width < 350 || MediaQuery.textScalerOf(context).scale(10) >= 16;
    final avatar = CommonAvatar(avatarUrl: room.avatar, fallbackName: nick.isEmpty ? platform : nick, radius: 24);
    final meta = [if (nick.isNotEmpty) nick, platform, '${i18n('room_id')} ${room.roomId.trim()}'].join(' · ');
    final names = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.isEmpty ? i18n('untitled_room') : title,
          key: const ValueKey('room-prompt-title'),
          maxLines: stacked ? null : 2,
          overflow: stacked ? null : TextOverflow.ellipsis,
          style: styles.t15.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
        ),
        const SizedBox(height: 4),
        Text(
          meta,
          key: const ValueKey('room-prompt-meta'),
          style: styles.t14.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
    return DialogButtonsTheme(
      child: AlertDialog(
        key: const ValueKey('room-prompt'),
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(i18n('room_prompt_title')),
            const SizedBox(height: 6),
            Text(i18n('room_prompt_from_clipboard'), style: styles.t14.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 352),
          child: stacked
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [avatar, const SizedBox(height: 12), names],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    avatar,
                    const SizedBox(width: 12),
                    Expanded(child: names),
                  ],
                ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('room-prompt-cancel'),
            onPressed: () => Navigator.of(context).pop(RoomPromptChoice.dismiss),
            child: Text(i18n('cancel')),
          ),
          FilledButton(
            key: const ValueKey('room-prompt-enter'),
            onPressed: () => Navigator.of(context).pop(RoomPromptChoice.enter),
            child: Text(i18n('enter_room')),
          ),
        ],
      ),
    );
  }
}
