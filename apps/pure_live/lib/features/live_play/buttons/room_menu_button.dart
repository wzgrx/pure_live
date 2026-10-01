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
import 'package:pure_live/features/live_play/dialogs/player_dialogs.dart';
import 'package:pure_live/features/live_play/dialogs/room_dialogs.dart';
import 'package:pure_live/features/live_play/dialogs/room_switcher.dart';
import 'package:pure_live/features/live_play/dialogs/stream_dialogs.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/rooms/room_menu.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

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

/// The entries of the room menu, in its order (docs/ui/compare/U.2f, 右上角
/// 菜单): three groups split by lines.
enum RoomMenuEntry {
  /// Another followed or watched room.
  switchRoom,

  /// The sleep timer.
  timer,

  /// The player's volume for this room.
  volume,

  /// The picture's fit ("画面比例", U.2a change 5: off the portrait bar).
  videoFit,

  /// DLNA.
  cast,

  /// Copy a stream address.
  streamLink,

  /// Share the room.
  share,

  /// Open in the platform's app or site ("在<平台>打开", 3.x's
  /// "打开直播间", M2).
  external,

  /// A new window (Windows).
  newWindow,
}

/// The groups of the room menu (U.2f M1): watching, passing the room on,
/// then the local interaction (3.x's last entry; v4 has no local
/// interaction yet, so that group is empty and left out).
List<List<RoomMenuEntry>> roomMenuGroups({required bool iptv, required bool windows}) => [
  const [RoomMenuEntry.switchRoom, RoomMenuEntry.timer, RoomMenuEntry.volume, RoomMenuEntry.videoFit],
  [
    RoomMenuEntry.cast,
    RoomMenuEntry.streamLink,
    // An IPTV channel has no page to share or open (as before).
    if (!iptv) RoomMenuEntry.share,
    if (!iptv) RoomMenuEntry.external,
    if (windows) RoomMenuEntry.newWindow,
  ],
];

/// The room menu of the bar (3.x `LivePlayMenuButton`, its four-square
/// icon kept, U.2a choice B): a menu next to the button, grouped (U.2f),
/// with 3.x's icons.
class RoomMenuButton extends ConsumerWidget {
  /// Creates the menu.
  const new({required this.controller, this.windows = false, super.key});

  /// The room.
  final LiveRoomController controller;

  /// Windows entries (new window).
  final bool windows;

  /// Runs [entry] for [controller].
  static Future<void> run(
    BuildContext context,
    WidgetRef ref,
    LiveRoomController controller,
    RoomMenuEntry entry,
  ) async {
    final room = controller.room;
    switch (entry) {
      case RoomMenuEntry.videoFit:
        await showVideoFitPicker(context, ref.read(storeProvider).settings);
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
    PopupMenuItem<RoomMenuEntry> item(RoomMenuEntry entry, {required bool playing, DateTime? deadline}) {
      final (icon, text, subtitle) = switch (entry) {
        RoomMenuEntry.switchRoom => (AppIcons.switchRoom, i18n('switch_live_room'), null),
        RoomMenuEntry.timer => (
          AppIcons.sleepTimer,
          i18n('sleep_timer'),
          deadline == null
              ? null
              : i18n(
                  'live_play_timer_left',
                  args: {'minutes': '${deadline.difference(controller.now()).inMinutes + 1}'},
                ),
        ),
        RoomMenuEntry.volume => (AppIcons.roomVolume, i18n('room_volume'), null),
        RoomMenuEntry.videoFit => (
          AppIcons.aspectRatio,
          i18n('settings_video_fit'),
          videoFitName(videoFitIndexOf(ref.read(storeProvider).settings)),
        ),
        RoomMenuEntry.cast => (AppIcons.cast, i18n('cast_screen'), null),
        RoomMenuEntry.streamLink => (AppIcons.streamLink, i18n('toolbox_get_direct_link'), null),
        RoomMenuEntry.share => (AppIcons.share, i18n('share'), null),
        RoomMenuEntry.external => (
          AppIcons.openExternal,
          i18n('live_play_open_in', args: {'platform': platformName(controller.room.platform)}),
          null,
        ),
        RoomMenuEntry.newWindow => (AppIcons.newWindow, i18n('open_room_in_new_window'), null),
      };
      // Cast and the stream address need a stream (as before).
      final enabled = playing || (entry != RoomMenuEntry.cast && entry != RoomMenuEntry.streamLink);
      return PopupMenuItem(
        key: ValueKey('room-menu-${entry.name}'),
        value: entry,
        enabled: enabled,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, size: 20),
          title: Text(text),
          subtitle: subtitle == null ? null : Text(subtitle),
        ),
      );
    }

    return PopupMenuButton<RoomMenuEntry>(
      key: const ValueKey('live-play-menu'),
      tooltip: i18n('menu'),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      icon: const Icon(AppIcons.roomMenu),
      onSelected: (entry) => unawaited(run(context, ref, controller, entry)),
      // Read when the menu opens: the bar does not rebuild for the room's
      // changes.
      itemBuilder: (context) {
        final playing = controller.stage == RoomStage.playing;
        final deadline = controller.sleepDeadline;
        final groups = roomMenuGroups(iptv: iptv, windows: windows).where((group) => group.isNotEmpty).toList();
        return [
          for (final (index, group) in groups.indexed) ...[
            if (index > 0) PopupMenuDivider(key: ValueKey('room-menu-divider-$index')),
            for (final entry in group) item(entry, playing: playing, deadline: deadline),
          ],
        ];
      },
    );
  }
}
