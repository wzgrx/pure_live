import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/dialogs/player_dialogs.dart';
import 'package:pure_live/features/live_play/dialogs/room_dialogs.dart';
import 'package:pure_live/features/live_play/dialogs/stream_dialogs.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/features/live_play/switch_room/room_switch_panel.dart';
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
    SiteIds.kuaishou => switch (kuaishouStreamId(room)) {
      final stream? => kuaishouAppLink(stream),
      _ => null,
    },
    _ => null,
  };
  return (web: web, native: native == null ? null : Uri.parse(native));
}

/// The id of [room]'s current Kuaishou broadcast (3.x kept it in `link`),
/// from the detail or the danmaku arguments; null when off air.
String? kuaishouStreamId(LiveRoom room) {
  final id = switch ((room.data, room.danmakuData)) {
    (final KuaishouRoomData data, _) when (data.liveStreamId?.trim() ?? '').isNotEmpty => data.liveStreamId,
    (_, final KuaishouDanmakuArgs args) => args.liveStreamId,
    _ => null,
  };
  final trimmed = id?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// The Kuaishou app's room of broadcast [stream] (3.x
/// `room_external_opener.dart:193-200`, F.1c).
String kuaishouAppLink(String stream) {
  final id = Uri.encodeQueryComponent(stream);
  return 'kwai://liveaggregatesquare?liveStreamId=$id&recoStreamId=$id&recoLiveStreamId=$id&liveSquareSource=28'
      '&path=/rest/n/live/feed/sharePage/slide/more&mt_product=H5_OUTSIDE_CLIENT_SHARE';
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

/// The entries of the room menu, in its order (docs/A-界面设计/A07-直播间界面/A07.6-直播间弹窗, 右上角
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

  /// The local interaction panel (3.x's last entry, U.2k; only while the
  /// local interaction is on).
  localInteraction,
}

/// Whether [platform] offers DLNA casting: Android only, both the top bar's
/// button and the menu entry (docs/A-界面设计/A07-直播间界面/A07.4-横屏全屏 and U.2d "投屏只有
/// Android"; U.17a for iOS). 3.x listed it in every platform's menu.
bool castSupported(TargetPlatform platform) => platform == TargetPlatform.android;

/// The groups of the room menu (U.2f M1): watching, passing the room on,
/// then the local interaction (3.x's last entry, U.2k), only while [local]
/// (the `localInteraction.enabled` setting) is on; an empty group is left
/// out.
///
/// Cast only where [cast] ([castSupported]); the new window only with
/// [newWindow] (`DesktopWindow.offersNewWindow`: a desktop shell that opens
/// windows and the setting "新建独立播放窗口" on, A16.1 c12). The menu on the picture leaves out what its bars already show
/// ([onBars], docs/A-界面设计/A07-直播间界面/A07.13-切换直播间面板 c12).
List<List<RoomMenuEntry>> roomMenuGroups({
  required bool iptv,
  required bool newWindow,
  required bool cast,
  bool local = false,
  Set<RoomMenuEntry> onBars = const {},
}) => [
  for (final group in [
    const [RoomMenuEntry.switchRoom, RoomMenuEntry.timer, RoomMenuEntry.volume, RoomMenuEntry.videoFit],
    [
      if (cast) RoomMenuEntry.cast,
      RoomMenuEntry.streamLink,
      // An IPTV channel has no page to share or open (as before).
      if (!iptv) RoomMenuEntry.share,
      if (!iptv) RoomMenuEntry.external,
      if (newWindow) RoomMenuEntry.newWindow,
    ],
    [if (local) RoomMenuEntry.localInteraction],
  ])
    [
      for (final entry in group)
        if (!onBars.contains(entry)) entry,
    ],
];

/// The room menu's entries the fullscreen bars already show (U.2m c12,
/// audit A-08): the landscape top bar's ⇄ and cast and its bottom bar's
/// fit; the portrait fullscreen's ⇄ and cast (its bottom bar has the
/// portrait picture mode, not the fit). Cast only where [cast]. None for
/// the bars of the room page (the menu in the app bar keeps every entry).
Set<RoomMenuEntry> menuEntriesOnBars({required bool landscape, required bool cast}) => {
  RoomMenuEntry.switchRoom,
  if (cast) RoomMenuEntry.cast,
  if (landscape) RoomMenuEntry.videoFit,
};

/// One row of the room menu as the small menu and the panel show it.
typedef RoomMenuItem = ({RoomMenuEntry entry, IconData icon, String label, String? description, bool enabled});

/// Whether [entry] opens a panel of its own in the room: the panel's row
/// ends in › (docs/A-界面设计/A07-直播间界面/A07.23-横屏右上角菜单升级).
bool roomMenuOpensPanel(RoomMenuEntry entry) => switch (entry) {
  RoomMenuEntry.switchRoom ||
  RoomMenuEntry.timer ||
  RoomMenuEntry.volume ||
  RoomMenuEntry.cast ||
  RoomMenuEntry.streamLink ||
  RoomMenuEntry.localInteraction => true,
  RoomMenuEntry.videoFit || RoomMenuEntry.share || RoomMenuEntry.external || RoomMenuEntry.newWindow => false,
};

/// The room menu's rows for [controller] now, in their groups
/// ([roomMenuGroups]; an empty group is left out): 3.x's icons, the sleep
/// timer's time left and the picture's fit on a second line; cast and the
/// stream address only while playing. The small menu and the panel
/// (`RoomMenuPanel`) both show these.
List<List<RoomMenuItem>> roomMenuItems(
  LiveRoomController controller,
  SettingsStore settings, {
  Set<RoomMenuEntry> onBars = const {},
}) {
  final playing = controller.stage == RoomStage.playing;
  final deadline = controller.sleepDeadline;
  RoomMenuItem item(RoomMenuEntry entry) {
    final (icon, label, description) = switch (entry) {
      RoomMenuEntry.switchRoom => (AppIcons.switchRoom, i18n('switch_live_room'), null),
      RoomMenuEntry.timer => (
        AppIcons.sleepTimer,
        i18n('sleep_timer'),
        deadline == null
            ? null
            : i18n('live_play_timer_left', args: {'minutes': '${deadline.difference(controller.now()).inMinutes + 1}'}),
      ),
      RoomMenuEntry.volume => (AppIcons.roomVolume, i18n('room_volume'), null),
      RoomMenuEntry.videoFit => (
        AppIcons.aspectRatio,
        i18n('settings_video_fit'),
        videoFitName(videoFitIndexOf(settings)),
      ),
      RoomMenuEntry.cast => (AppIcons.cast, i18n('cast_screen'), null),
      RoomMenuEntry.streamLink => (AppIcons.streamLink, i18n('toolbox_get_direct_link'), null),
      RoomMenuEntry.share => (AppIcons.share, i18n('share'), null),
      RoomMenuEntry.external => (
        AppIcons.openExternal,
        i18n('live_play_open_in', args: {'platform': platformName(controller.room.platform)}),
        null,
      ),
      RoomMenuEntry.newWindow => (AppIcons.newWindow, i18n('open_in_new_window'), null),
      RoomMenuEntry.localInteraction => (AppIcons.localInteraction, i18n('local_interaction_title'), null),
    };
    return (
      entry: entry,
      icon: icon,
      label: label,
      description: description,
      // Cast and the stream address need a stream (as before).
      enabled: playing || (entry != RoomMenuEntry.cast && entry != RoomMenuEntry.streamLink),
    );
  }

  return [
    for (final group in roomMenuGroups(
      iptv: controller.site.id == SiteIds.iptv,
      newWindow: DesktopWindow.offersNewWindow(settings),
      local: settings.get(Settings.localInteractionEnabled),
      cast: castSupported(defaultTargetPlatform),
      onBars: onBars,
    ))
      if (group.isNotEmpty) [for (final entry in group) item(entry)],
  ];
}

/// The room menu (3.x `LivePlayMenuButton`, its four-square icon kept,
/// U.2a choice B), grouped (U.2f), with 3.x's icons ([roomMenuItems]). On
/// the room page's bar it is the app's small menu next to the button
/// ([AppMenuButton], docs/A-界面设计/A07-直播间界面/A07.12-直播间子弹窗统一 c7, B-7). On the
/// picture (the fullscreen bars, [onVideo]) it is the room's panel
/// ([RoomPanelKind.menu], `RoomMenuPanel`;
/// docs/A-界面设计/A07-直播间界面/A07.23-横屏右上角菜单升级): on the right in landscape,
/// along the bottom in portrait fullscreen, where the panels its rows open
/// come too; a second tap on the button closes it.
class RoomMenuButton extends ConsumerWidget {
  /// Creates the menu.
  const new({required this.controller, this.onVideo = false, this.onBars = const {}, this.onMenu, super.key});

  /// The room.
  final LiveRoomController controller;

  /// On the picture (the fullscreen bars, U.2c change 2): a white icon, and
  /// the menu is the room's panel.
  final bool onVideo;

  /// What the bars around the button already show, left out of the small
  /// menu ([menuEntriesOnBars], U.2m c12); the page gives the panel the
  /// same set.
  final Set<RoomMenuEntry> onBars;

  /// Told when the small menu opens (true) and closes: the controls stay up
  /// (an open panel holds them by itself).
  final ValueChanged<bool>? onMenu;

  /// Runs [entry] for [controller]; [context] is the menu's button or the
  /// panel's row, which the picture's fit menu opens next to (U.2n c5).
  static Future<void> run(
    BuildContext context,
    WidgetRef ref,
    LiveRoomController controller,
    RoomMenuEntry entry,
  ) async {
    final room = controller.room;
    switch (entry) {
      case RoomMenuEntry.videoFit:
        await showVideoFitMenu(context, ref.read(storeProvider).settings);
      case RoomMenuEntry.external:
        await openRoomExternally(room);
      case RoomMenuEntry.switchRoom:
        showRoomSwitchPanel(context, controller);
      case RoomMenuEntry.cast:
        showStreamPanel(context, controller, StreamUse.cast);
      case RoomMenuEntry.timer:
        showSleepTimer(context, controller);
      case RoomMenuEntry.volume:
        showRoomVolume(context, controller);
      case RoomMenuEntry.streamLink:
        showStreamPanel(context, controller, StreamUse.copy);
      case RoomMenuEntry.share:
        await shareRoom(room);
      case RoomMenuEntry.localInteraction:
        RoomPanelScope.maybeOf(context)?.open(RoomPanelKind.localInteraction);
      case RoomMenuEntry.newWindow:
        // It says "新窗口启动失败，请重试" itself when the window does not start.
        await DesktopWindow.openNewWindow(room: room);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icon = Icon(AppIcons.roomMenu, color: onVideo ? OnVideoColors.foreground : null);
    final panels = onVideo ? RoomPanelScope.maybeOf(context) : null;
    if (panels != null) {
      return IconButton(
        key: const ValueKey('live-play-menu'),
        tooltip: i18n('menu'),
        onPressed: () => panels.value == RoomPanelKind.menu ? panels.close() : panels.open(RoomPanelKind.menu),
        icon: icon,
      );
    }
    return Builder(
      builder: (anchor) => AppMenuButton<RoomMenuEntry>(
        key: const ValueKey('live-play-menu'),
        tooltip: i18n('menu'),
        icon: icon,
        onMenu: onMenu,
        onSelected: (entry) => unawaited(run(anchor, ref, controller, entry)),
        // Read when the menu opens: the bar does not rebuild for the room's
        // changes.
        entries: () => [
          for (final (index, group) in roomMenuItems(
            controller,
            ref.read(storeProvider).settings,
            onBars: onBars,
          ).indexed)
            for (final (row, item) in group.indexed)
              AppMenuEntry(
                key: ValueKey('room-menu-${item.entry.name}'),
                value: item.entry,
                icon: item.icon,
                label: item.label,
                description: item.description,
                divider: index > 0 && row == 0,
                enabled: item.enabled,
              ),
        ],
      ),
    );
  }
}
