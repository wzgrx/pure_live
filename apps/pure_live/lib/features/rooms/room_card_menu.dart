import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/error_text.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/alerts/alert_tiles.dart';
import 'package:pure_live_app/features/follows/follow_actions.dart';
import 'package:pure_live_app/features/follows/groups.dart';
import 'package:pure_live_app/features/room/room_menus.dart';
import 'package:pure_live_app/features/rooms/stream_link.dart';
import 'package:pure_live_app/features/system/launch_args.dart';
import 'package:pure_live_app/i18n/strings.g.dart';
import 'package:url_launcher/url_launcher.dart';

/// What the card menu offers (principles §4.2).
enum RoomCardAction {
  /// 多选: starts the follows page's multi-select with this room
  /// (spec/product.md F-FAV-09; not on TV).
  select,

  /// 关注.
  follow,

  /// 取消关注 (with undo).
  unfollow,

  /// 设置分组 (followed rooms).
  groups,

  /// 加入多画面.
  multiview,

  /// 分享: the 3.x-compatible share code.
  share,

  /// 复制链接: the room's page on the platform.
  copyLink,

  /// 获取直链: pick a quality and a line, copy its URL (F-SRC-04).
  streamLink,

  /// 在新窗口打开 (Windows, F-WIN-02).
  newWindow,

  /// 打开原站.
  openSite,
}

/// The entries for a room that is [followed], in menu order. A room of a
/// platform this build does not [supported] keeps only what needs no adapter:
/// following and groups (F-FAV-08). [select] adds 多选 first (the follows
/// page).
List<RoomCardAction> roomCardActions({
  required bool followed,
  required bool newWindow,
  bool supported = true,
  bool select = false,
}) => [
  if (select) RoomCardAction.select,
  if (followed) RoomCardAction.unfollow else RoomCardAction.follow,
  if (followed) RoomCardAction.groups,
  if (supported) ...[
    RoomCardAction.multiview,
    RoomCardAction.share,
    RoomCardAction.copyLink,
    RoomCardAction.streamLink,
    if (newWindow) RoomCardAction.newWindow,
    RoomCardAction.openSite,
  ],
];

/// The card menu of follows, discover, search and history (principles §4.2):
/// long press on touch, right click on desktops, long OK or the menu key on
/// a remote. [snapshot] is what following stores when the room is not
/// followed yet; share, link and site need the room's detail, loaded when
/// chosen. With [onSelect] the menu starts with 多选 (F-FAV-09).
Future<void> showRoomCardMenu(
  BuildContext context,
  WidgetRef ref, {
  required RoomRef room,
  required String anchorName,
  RoomSnapshot? snapshot,
  VoidCallback? onSelect,
}) async {
  final store = ref.read(storeProvider);
  final followed = await store.follows.contains(room);
  if (!context.mounted) return;
  final supported = ref.read(sitesProvider).containsKey(room.platform);
  final actions = roomCardActions(
    followed: followed,
    newWindow: newWindowSupported,
    supported: supported,
    select: onSelect != null,
  );
  final action = await showModalBottomSheet<RoomCardAction>(
    context: context,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(anchorName),
              subtitle: Text(
                supported
                    ? platformName(room.platform)
                    : t.follows.unsupportedPlatform(name: platformName(room.platform)),
              ),
            ),
            // F-NEW-01: per-room live alerts for followed rooms (not IPTV channels).
            if (followed && room.platform != 'iptv') RoomAlertSwitch(room: room),
            for (final action in actions)
              ListTile(
                leading: Icon(switch (action) {
                  RoomCardAction.select => Icons.checklist,
                  RoomCardAction.follow => Icons.favorite_border,
                  RoomCardAction.unfollow => Icons.heart_broken_outlined,
                  RoomCardAction.groups => Icons.folder_outlined,
                  RoomCardAction.multiview => Icons.grid_view,
                  RoomCardAction.share => Icons.share_outlined,
                  RoomCardAction.copyLink => Icons.link,
                  RoomCardAction.streamLink => Icons.content_copy,
                  RoomCardAction.newWindow => Icons.open_in_browser,
                  RoomCardAction.openSite => Icons.open_in_new,
                }),
                title: Text(switch (action) {
                  RoomCardAction.select => t.follows.select,
                  RoomCardAction.follow => t.common.follow,
                  RoomCardAction.unfollow => t.common.unfollow,
                  RoomCardAction.groups => t.rooms.setGroups,
                  RoomCardAction.multiview => t.room.addToMultiview,
                  RoomCardAction.share => t.room.share,
                  RoomCardAction.copyLink => t.common.copyLink,
                  RoomCardAction.streamLink => t.rooms.streamLink,
                  RoomCardAction.newWindow => t.rooms.openInNewWindow,
                  RoomCardAction.openSite => t.common.openSite,
                }),
                onTap: () => Navigator.pop(context, action),
              ),
          ],
        ),
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  void say(String text) => messenger.showSnackBar(SnackBar(content: Text(text)));

  Future<RoomDetail?> detail() async {
    try {
      return await ref.read(sitesProvider).of(room.platform).rooms.detail(room);
    } on Object catch (error) {
      say(describeError(error).title);
      return null;
    }
  }

  switch (action) {
    case RoomCardAction.select:
      onSelect?.call();
    case RoomCardAction.follow:
      final stored = snapshot ?? (await detail()).let(RoomSnapshot.fromDetail);
      if (stored == null || !context.mounted) return;
      // F-FAV-02: the write is awaited; a failure changes nothing and is said.
      if (await followWithNotice(context, ref, stored)) say(t.rooms.followedName(name: anchorName));
    case RoomCardAction.unfollow:
      await unfollowWithUndo(context, ref, room, anchorName);
    case RoomCardAction.groups:
      await editRoomGroups(context, ref, room, anchorName);
    case RoomCardAction.multiview:
      unawaited(context.push('/multiview', extra: [room]));
    case RoomCardAction.share:
      final loaded = await detail();
      if (loaded != null && context.mounted) await shareRoom(context, loaded);
    case RoomCardAction.copyLink:
      final loaded = await detail();
      if (loaded != null && context.mounted) await copyWithToast(context, loaded.link.toString(), t.common.linkCopied);
    case RoomCardAction.streamLink:
      await showStreamLinkPicker(context, ref, room, title: anchorName);
    case RoomCardAction.newWindow:
      if (!await ref.read(newWindowProvider)(room)) say(t.common.couldNotOpenWindow);
    case RoomCardAction.openSite:
      final loaded = await detail();
      if (loaded != null) await launchUrl(loaded.link, mode: LaunchMode.externalApplication);
  }
}

extension on RoomDetail? {
  T? let<T>(T Function(RoomDetail detail) convert) {
    final value = this;
    return value == null ? null : convert(value);
  }
}
