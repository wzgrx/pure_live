import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/launch_args.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/dialogs/iptv_guide.dart';
import 'package:pure_live/features/live_play/dialogs/player_dialogs.dart';
import 'package:pure_live/features/live_play/dialogs/room_dialogs.dart';
import 'package:pure_live/features/live_play/dialogs/room_switcher.dart';
import 'package:pure_live/features/live_play/dialogs/stream_dialogs.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/room_menu.dart';

/// Where "open in the app" goes: the official page, and on Android the
/// platform's own app when it has a link for it (3.x `RoomExternalOpener`).
typedef ExternalRoomTarget = ({Uri web, Uri? native});

/// The external target of [room], or null when it has no official page
/// (IPTV, a room without a web link).
ExternalRoomTarget? externalRoomTarget(LiveRoom room) {
  final web = Uri.tryParse(room.link?.trim() ?? '');
  if (room.platform == SiteIds.iptv ||
      web == null ||
      web.host.isEmpty ||
      web.userInfo.isNotEmpty ||
      (web.scheme != 'http' && web.scheme != 'https')) {
    return null;
  }
  final id = Uri.encodeComponent(room.roomId.trim());
  final native = switch (room.platform) {
    SiteIds.bilibili => 'bilibili://live/$id',
    SiteIds.douyu => 'douyulink://?type=90001&schemeUrl=douyuapp%3A%2F%2Froom%3FliveType%3D0%26rid%3D$id',
    SiteIds.douyin => switch (room.danmakuData) {
      final DouyinDanmakuArgs args when args.roomId.trim().isNotEmpty =>
        'snssdk1128://webcast_room?room_id=${Uri.encodeComponent(args.roomId.trim())}',
      _ => null,
    },
    SiteIds.huya => switch (room.danmakuData) {
      final HuyaDanmakuArgs args when args.subSid > 0 =>
        'yykiwi://homepage/index.html?banneraction=https%3A%2F%2Fdiy-front.cdn.huya.com%2Fzt%2Ffrontpage%2Fcc%2Fupdate.html%3Fhyaction%3Dlive%26channelid%3D${args.subSid}%26subid%3D${args.subSid}%26liveuid%3D${args.subSid}%26screentype%3D1%26sourcetype%3D0%26fromapp%3Dhuya_wap%252Fclick%252Fopen_app_guide%26&fromapp=huya_wap/click/open_app_guide',
      _ => null,
    },
    SiteIds.cc when (room.userId?.trim() ?? '').isNotEmpty =>
      'cc://join-room/$id/${Uri.encodeComponent(room.userId!.trim())}/',
    _ => null,
  };
  return (web: web, native: native == null ? null : Uri.parse(native));
}

/// Opens [room] in its app or browser (3.x `openNaviteAPP`): on Android
/// the platform's app first, then the web page.
Future<void> openRoomExternally(LiveRoom room, {bool? android}) async {
  final target = externalRoomTarget(room);
  if (target == null) {
    AppNavigator.toast(i18n('open_room_external_unavailable'));
    return;
  }
  Future<bool> attempt(Uri uri) async {
    try {
      return await AppNavigator.openExternal(uri);
    } on Object {
      // Never log the target: it may carry share parameters.
      return false;
    }
  }

  final native = (android ?? (!kIsWeb && Platform.isAndroid)) ? target.native : null;
  if (native != null) {
    if (await attempt(native)) return;
    AppNavigator.toast(i18n('open_app_failed_fallback_browser'));
  }
  if (!await attempt(target.web)) AppNavigator.toast(i18n('open_room_external_failed'));
}

/// The entries of the room menu.
enum RoomMenuEntry {
  /// Load the room again.
  refresh,

  /// The room's details.
  info,

  /// The IPTV guide.
  guide,

  /// Open in the platform's app or browser.
  external,

  /// Another followed or watched room.
  switchRoom,

  /// DLNA.
  cast,

  /// The picture's fit ("画面比例", U.2a change 5: off the portrait bar).
  videoFit,

  /// The sleep timer.
  timer,

  /// The player's volume for this room (desktop).
  volume,

  /// Copy a stream address.
  streamLink,

  /// Share the room.
  share,

  /// A new window (Windows).
  newWindow,
}

/// The room menu of the bar (3.x `LivePlayMenuButton`, its four-square
/// icon kept, U.2a choice B).
class RoomMenuButton extends ConsumerWidget {
  /// Creates the menu.
  const new({required this.controller, required this.onDetails, this.desktop = false, this.windows = false, super.key});

  /// The room.
  final LiveRoomController controller;

  /// Opens the room details (the "直播间信息" entry).
  final VoidCallback onDetails;

  /// Desktop entries (room volume).
  final bool desktop;

  /// Windows entries (new window).
  final bool windows;

  /// Runs [entry] for [controller].
  static Future<void> run(
    BuildContext context,
    WidgetRef ref,
    LiveRoomController controller,
    RoomMenuEntry entry, {
    required VoidCallback onDetails,
  }) async {
    final room = controller.room;
    switch (entry) {
      case RoomMenuEntry.refresh:
        await controller.load();
      case RoomMenuEntry.info:
        onDetails();
      case RoomMenuEntry.videoFit:
        await showVideoFitPicker(context, ref.read(storeProvider).settings);
      case RoomMenuEntry.guide:
        await showIptvGuide(context, controller);
      case RoomMenuEntry.external:
        await openRoomExternally(room);
      case RoomMenuEntry.switchRoom:
        await showRoomSwitcher(context, room);
      case RoomMenuEntry.cast:
        await showStreamPicker(context, controller, StreamUse.cast);
      case RoomMenuEntry.timer:
        await showSleepTimerDialog(context, controller);
      case RoomMenuEntry.volume:
        await showRoomVolumeDialog(context, controller);
      case RoomMenuEntry.streamLink:
        await showStreamPicker(context, controller, StreamUse.copy);
      case RoomMenuEntry.share:
        await shareRoom(room);
      case RoomMenuEntry.newWindow:
        final services = ref.read(appServicesProvider);
        try {
          await launchNewWindow(services.store, services.cipher, room: room);
        } on Object catch (error, stackTrace) {
          developer.log('New window failed', name: 'LivePlay', error: error, stackTrace: stackTrace);
          AppNavigator.toast(i18n('open_new_window_failed'));
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iptv = controller.site.id == SiteIds.iptv;
    PopupMenuItem<RoomMenuEntry> item(
      RoomMenuEntry entry,
      IconData icon,
      String text, {
      String? subtitle,
      bool enabled = true,
    }) => PopupMenuItem(
      key: ValueKey('room-menu-${entry.name}'),
      value: entry,
      enabled: enabled,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, size: 20),
        title: Text(text),
        subtitle: subtitle == null ? null : Text(subtitle),
      ),
    );
    return PopupMenuButton<RoomMenuEntry>(
      key: const ValueKey('live-play-menu'),
      tooltip: i18n('menu'),
      position: PopupMenuPosition.under,
      icon: const Icon(AppIcons.roomMenu),
      onSelected: (entry) => unawaited(run(context, ref, controller, entry, onDetails: onDetails)),
      // Read when the menu opens: the bar does not rebuild for the room's
      // changes.
      itemBuilder: (context) {
        final playing = controller.stage == RoomStage.playing;
        final deadline = controller.sleepDeadline;
        return [
          item(RoomMenuEntry.refresh, Icons.refresh_rounded, i18n('live_play_refresh_room')),
          item(RoomMenuEntry.info, Icons.info_outline_rounded, i18n('live_play_room_info')),
          if (iptv) item(RoomMenuEntry.guide, Icons.assignment_outlined, i18n('view_schedule'), enabled: playing),
          if (!iptv) item(RoomMenuEntry.external, Icons.open_in_new_rounded, i18n('open_live_room')),
          item(RoomMenuEntry.switchRoom, Icons.swap_horiz_rounded, i18n('switch_live_room')),
          item(RoomMenuEntry.cast, Icons.cast_rounded, i18n('cast_screen'), enabled: playing),
          item(
            RoomMenuEntry.videoFit,
            AppIcons.aspectRatio,
            i18n('settings_video_fit'),
            subtitle: videoFitName(videoFitIndexOf(ref.read(storeProvider).settings)),
          ),
          item(
            RoomMenuEntry.timer,
            Icons.timer_outlined,
            i18n('sleep_timer'),
            subtitle: deadline == null
                ? null
                : i18n(
                    'live_play_timer_left',
                    args: {'minutes': '${deadline.difference(controller.now()).inMinutes + 1}'},
                  ),
          ),
          if (desktop) item(RoomMenuEntry.volume, Icons.volume_up_rounded, i18n('room_volume')),
          item(RoomMenuEntry.streamLink, Icons.link_rounded, i18n('toolbox_get_direct_link'), enabled: playing),
          if (!iptv) item(RoomMenuEntry.share, Icons.share_rounded, i18n('share')),
          if (windows) item(RoomMenuEntry.newWindow, Icons.open_in_browser_rounded, i18n('open_room_in_new_window')),
        ];
      },
    );
  }
}
