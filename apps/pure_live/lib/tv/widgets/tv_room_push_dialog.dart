import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';

/// What the user chose in [showTvRoomPush].
enum TvRoomPushChoice {
  /// Open the room that was recognised.
  open,

  /// Search the pushed text (nothing was recognised).
  search,
}

/// Asks whether to open a room a phone pushed to the TV (docs/TASKS.md/
/// U.15a c15): the phone's "口令导入" dialog of U.3d in the TV style, so the
/// room is recognised before asking (pure_live_TV showed the raw link, P16).
///
/// With [room] it shows the streamer's picture, the title and "主播 · 平台 ·
/// 房间号", with "进入房间" focused; without, the pushed [text] (three lines
/// at most) and "搜索这段文字". Null when cancelled.
///
/// The TV has no receiver for phone pushes yet (pure_live_TV
/// `GlobalRoomPushOverlay`); this is the dialog it will show, the parsing is
/// U.3d's share-code import (docs/T18/T18a/T18a.2/record.md).
Future<TvRoomPushChoice?> showTvRoomPush(BuildContext context, {required String text, LiveRoom? room}) =>
    showTvDialog<TvRoomPushChoice>(
      context,
      builder: (_) => TvRoomPushDialog(text: text, room: room),
    );

/// The content of [showTvRoomPush].
class TvRoomPushDialog extends StatelessWidget {
  /// Creates the dialog.
  const new({required this.text, this.room, super.key});

  /// What the phone sent.
  final String text;

  /// The room recognised in [text], if any.
  final LiveRoom? room;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final room = this.room;
    final secondary = scale.font(TvTextSize.small, color: palette.textSecondary, height: 1.5);
    return TvDialog(
      key: const ValueKey('tv-room-push'),
      width: 520,
      title: i18n('tv_push_title'),
      subtitle: i18n('tv_push_from_phone'),
      actions: [
        TvButton(
          key: const ValueKey('tv-room-push-cancel'),
          label: i18n('cancel'),
          onTap: () => Navigator.pop(context),
        ),
        TvButton(
          key: const ValueKey('tv-room-push-go'),
          label: i18n(room == null ? 'tv_push_search' : 'enter_room'),
          kind: TvButtonKind.primary,
          autofocus: true,
          onTap: () => Navigator.pop(context, room == null ? TvRoomPushChoice.search : TvRoomPushChoice.open),
        ),
      ],
      child: Padding(
        padding: EdgeInsets.only(top: scale.px(18)),
        child: room == null
            ? Text(
                text,
                key: const ValueKey('tv-room-push-text'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: scale.font(TvTextSize.body, color: palette.textSecondary, height: 1.6),
              )
            : Row(
                children: [
                  CommonAvatar(avatarUrl: room.avatar, fallbackName: room.nick, radius: scale.pxText(28)),
                  SizedBox(width: scale.px(14)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          roomLabel(room),
                          key: const ValueKey('tv-room-push-title'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: scale.font(TvTextSize.body, weight: FontWeight.w600, color: palette.text, height: 1.4),
                        ),
                        SizedBox(height: scale.px(2)),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: scale.px(6),
                          children: [
                            if (room.nick.trim().isNotEmpty) Text('${room.nick.trim()} ·', style: secondary),
                            PlatformLogo(room.platform, size: scale.pxText(16)),
                            Text(
                              i18n(
                                'tv_room_platform_id',
                                args: {'platform': platformName(room.platform), 'id': room.roomId},
                              ),
                              key: const ValueKey('tv-room-push-id'),
                              style: secondary.tabular,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
