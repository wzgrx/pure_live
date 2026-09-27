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
import 'package:pure_live_app/features/follows/groups.dart';
import 'package:pure_live_app/features/room/room_menus.dart';
import 'package:pure_live_app/features/system/launch_args.dart';
import 'package:url_launcher/url_launcher.dart';

/// What the card menu offers (principles §4.2).
enum RoomCardAction {
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

  /// 在新窗口打开 (Windows, F-WIN-02).
  newWindow,

  /// 打开原站.
  openSite,
}

/// The entries for a room that is [followed], in menu order.
List<RoomCardAction> roomCardActions({required bool followed, required bool newWindow}) => [
  if (followed) RoomCardAction.unfollow else RoomCardAction.follow,
  if (followed) RoomCardAction.groups,
  RoomCardAction.multiview,
  RoomCardAction.share,
  RoomCardAction.copyLink,
  if (newWindow) RoomCardAction.newWindow,
  RoomCardAction.openSite,
];

/// The card menu of follows, discover, search and history (principles §4.2):
/// long press on touch, right click on desktops, long OK or the menu key on
/// a remote. [snapshot] is what following stores when the room is not
/// followed yet; share, link and site need the room's detail, loaded when
/// chosen.
Future<void> showRoomCardMenu(
  BuildContext context,
  WidgetRef ref, {
  required RoomRef room,
  required String anchorName,
  RoomSnapshot? snapshot,
}) async {
  final store = ref.read(storeProvider);
  final followed = await store.follows.contains(room);
  if (!context.mounted) return;
  final actions = roomCardActions(followed: followed, newWindow: newWindowSupported);
  final action = await showModalBottomSheet<RoomCardAction>(
    context: context,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(anchorName), subtitle: Text(platformNames[room.platform] ?? room.platform)),
            // F-NEW-01: per-room live alerts for followed rooms (not IPTV channels).
            if (followed && room.platform != 'iptv') RoomAlertSwitch(room: room),
            for (final action in actions)
              ListTile(
                leading: Icon(switch (action) {
                  RoomCardAction.follow => Icons.favorite_border,
                  RoomCardAction.unfollow => Icons.heart_broken_outlined,
                  RoomCardAction.groups => Icons.folder_outlined,
                  RoomCardAction.multiview => Icons.grid_view,
                  RoomCardAction.share => Icons.share_outlined,
                  RoomCardAction.copyLink => Icons.link,
                  RoomCardAction.newWindow => Icons.open_in_browser,
                  RoomCardAction.openSite => Icons.open_in_new,
                }),
                title: Text(switch (action) {
                  RoomCardAction.follow => '关注',
                  RoomCardAction.unfollow => '取消关注',
                  RoomCardAction.groups => '设置分组',
                  RoomCardAction.multiview => '加入多画面',
                  RoomCardAction.share => '分享',
                  RoomCardAction.copyLink => '复制链接',
                  RoomCardAction.newWindow => '在新窗口打开',
                  RoomCardAction.openSite => '打开原站',
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
    final site = ref.read(sitesProvider)[room.platform];
    if (site == null) return null;
    try {
      return await site.rooms.detail(room);
    } on Object catch (error) {
      say(describeError(error).title);
      return null;
    }
  }

  switch (action) {
    case RoomCardAction.follow:
      final stored = snapshot ?? (await detail()).let(RoomSnapshot.fromDetail);
      if (stored == null) return;
      await store.follows.follow(stored);
      say('已关注 $anchorName');
    case RoomCardAction.unfollow:
      final removed = await store.follows.unfollow(room);
      if (removed == null) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('已取消关注 $anchorName'),
          action: SnackBarAction(label: '撤销', onPressed: () => store.follows.restore([removed])),
        ),
      );
    case RoomCardAction.groups:
      await editRoomGroups(context, ref, room, anchorName);
    case RoomCardAction.multiview:
      unawaited(context.push('/multiview', extra: [room]));
    case RoomCardAction.share:
      final loaded = await detail();
      if (loaded != null && context.mounted) await shareRoom(context, loaded);
    case RoomCardAction.copyLink:
      final loaded = await detail();
      if (loaded != null && context.mounted) await copyWithToast(context, loaded.link.toString(), '链接已复制');
    case RoomCardAction.newWindow:
      if (!await ref.read(newWindowProvider)(room)) say('没能打开新窗口');
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
