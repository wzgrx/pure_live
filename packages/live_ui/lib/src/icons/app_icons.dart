import 'package:flutter/material.dart';
import 'package:live_ui/src/icons/custom_icons.dart';
import 'package:remixicon/remixicon.dart';

/// The app's icons by what they are for (docs/ui/UI_PLAN.md §6.4).
///
/// Each use maps to the icon 3.x showed in that place (`Remix.*`,
/// Material's `Icons.*` or 3.x's own `CustomIcons`), so pages name the use,
/// not the glyph, and a later switch of icon set changes only this file.
/// Danmaku on, off and settings are pictures, see `DanmakuIcon`; the record
/// button's ring and dot are drawn by `RecordGlyph`.
abstract final class AppIcons {
  // ---- the home shell (docs/ui/compare/U.3a, U.3b) ----

  /// The home destination "关注".
  static const IconData homeFavorites = Remix.heart_3_line;

  /// The home destination "关注", selected.
  static const IconData homeFavoritesSelected = Remix.heart_3_fill;

  /// The home destination "热门".
  static const IconData homePopular = Remix.fire_line;

  /// The home destination "热门", selected.
  static const IconData homePopularSelected = Remix.fire_fill;

  /// The home destination "分区": three shapes (U.3a c7; 3.x's four squares
  /// stay the room menu's).
  static const IconData homeAreas = Remix.shapes_line;

  /// The home destination "分区", selected.
  static const IconData homeAreasSelected = Remix.shapes_fill;

  /// The home destination "录制中心".
  static const IconData homeRecord = Remix.download_2_line;

  /// The home destination "录制中心", selected.
  static const IconData homeRecordSelected = Remix.download_2_fill;

  /// The app menu (3.x `MenuButton`).
  static const IconData appMenu = Icons.menu_rounded;

  /// Search for rooms (3.x's wide rail, `CustomIcons.search`).
  static const IconData search = CustomIcons.search;

  /// More actions ("更多").
  static const IconData more = Remix.more_2_fill;

  /// The watch history ("观看记录").
  static const IconData watchHistory = Remix.history_line;

  /// Open a shared link ("链接解析").
  static const IconData openLink = Remix.link;

  /// Multi-view.
  static const IconData multiview = Remix.layout_grid_line;

  /// The settings.
  static const IconData settings = Remix.settings_5_line;

  /// About the app.
  static const IconData about = Remix.information_line;

  /// Backup and restore.
  static const IconData backup = Remix.cloud_line;

  /// An independent player window (Windows, 3.x's menu).
  static const IconData newPlayerWindow = Icons.add_to_photos_outlined;

  // ---- the global dialogs (docs/ui/compare/U.3d) ----

  /// A finished download.
  static const IconData downloadDone = Icons.check_circle_rounded;

  /// A download or an opening that failed.
  static const IconData downloadFailed = Icons.error_outline_rounded;

  /// Install a downloaded package (3.x's download dialog).
  static const IconData install = Icons.install_mobile_rounded;

  /// Try again.
  static const IconData retry = Icons.refresh_rounded;

  // ---- the live room's app bar (3.x live_play_header.dart, widgets/button) ----

  /// Back (3.x fullscreen `BackButton`).
  static const IconData back = Icons.arrow_back_rounded;

  /// Follow: the "＋ 关注" button.
  static const IconData follow = Remix.add_line;

  /// Followed: the "✓ 已关注" button.
  static const IconData followed = Remix.check_line;

  /// Follow as a heart (3.x `FavoriteFloatingButton`, the room details).
  static const IconData followHeart = Remix.heart_3_line;

  /// Followed as a heart.
  static const IconData followedHeart = Remix.heart_3_fill;

  /// A room that records by itself when it goes live ("自动录").
  static const IconData autoRecord = Remix.timer_line;

  /// The room menu (3.x `LivePlayMenuButton`).
  static const IconData roomMenu = Remix.apps_2_line;

  // ---- the bar at the top of the video (3.x `TopActionBar`) ----

  /// Audio only, off.
  static const IconData audioOnly = Remix.headphone_line;

  /// Audio only, on.
  static const IconData audioOnlyActive = Remix.headphone_fill;

  /// Cast to a TV (3.x `CastButton`, the room menu).
  static const IconData cast = Remix.tv_2_line;

  /// Picture-in-picture (3.x `PIPButton`).
  static const IconData floatWindow = CustomIcons.float_window;

  /// The IPTV guide.
  static const IconData iptvGuide = Icons.assignment_outlined;

  /// Another followed or watched room (3.x's fullscreen room history).
  static const IconData switchRoom = Icons.swap_horiz_outlined;

  // ---- the bar at the bottom of the video (3.x `BottomActionBar`) ----

  /// Play.
  static const IconData play = Icons.play_arrow_rounded;

  /// Pause.
  static const IconData pause = Icons.pause_rounded;

  /// Load the room again.
  static const IconData refresh = Icons.refresh_rounded;

  /// The picture's orientation follows the stream (3.x
  /// `PortraitOrientationButton`).
  static const IconData orientationAuto = Icons.screen_rotation_alt_rounded;

  /// The room is forced to portrait.
  static const IconData orientationPortrait = Icons.stay_current_portrait_rounded;

  /// The room is forced to landscape.
  static const IconData orientationLandscape = Icons.stay_current_landscape_rounded;

  /// Enter fullscreen.
  static const IconData fullscreen = Icons.fullscreen_rounded;

  /// Leave fullscreen.
  static const IconData exitFullscreen = Icons.fullscreen_exit_rounded;

  /// The picture's fit (画面比例).
  static const IconData aspectRatio = Remix.aspect_ratio_line;

  /// The controls are locked (3.x `LockButton`).
  static const IconData locked = Icons.lock_rounded;

  /// Lock the controls.
  static const IconData unlocked = Icons.lock_open_rounded;

  // ---- the room strip and the room details ----

  /// A drop-down button (quality, line).
  static const IconData dropDown = Remix.arrow_down_s_line;

  /// Fold a section away ("收起").
  static const IconData foldUp = Remix.arrow_up_s_line;

  /// A link to another page (the room's area).
  static const IconData forward = Remix.arrow_right_s_line;

  /// The chosen entry of a list of choices.
  static const IconData selected = Icons.check_rounded;

  /// Copy (3.x's danmaku actions).
  static const IconData copy = Icons.copy_all_rounded;

  /// Share (3.x's room menu).
  static const IconData share = Remix.share_forward_line;

  /// Open in the platform's app or site (3.x's "打开直播间").
  static const IconData openExternal = Icons.open_in_new_rounded;

  /// Viewers now (3.x `AudienceInfo`).
  static const IconData audienceOnline = Icons.people_alt_rounded;

  /// The platform's heat score.
  static const IconData audienceHeat = Icons.whatshot_rounded;

  /// Viewers so far.
  static const IconData audienceTotal = Icons.visibility_rounded;

  /// Followers.
  static const IconData audienceFollowers = Icons.favorite_rounded;

  /// Time on air.
  static const IconData liveDuration = Icons.schedule_rounded;

  // ---- the chat list (3.x danmaku_list_view.dart, danmaku_message_actions.dart) ----

  /// Back to the newest messages.
  static const IconData newMessages = Icons.arrow_downward_rounded;

  /// Block a viewer.
  static const IconData blockUser = Icons.person_off_rounded;

  /// Block a keyword.
  static const IconData blockKeyword = Icons.filter_alt_rounded;

  /// A gift line.
  static const IconData chatGift = Icons.card_giftcard_rounded;

  /// A platform notice line.
  static const IconData chatNotice = Icons.campaign_outlined;

  /// The chat list's look (compact lines or cards).
  static const IconData chatListStyle = Icons.view_agenda_outlined;

  // ---- gestures over the video (3.x `BrightnessVolumnDargArea`) ----

  /// Low brightness.
  static const IconData brightnessLow = Icons.brightness_low;

  /// Medium brightness.
  static const IconData brightnessMedium = Icons.brightness_medium;

  /// High brightness.
  static const IconData brightnessHigh = Icons.brightness_high;

  /// No sound.
  static const IconData volumeMute = Icons.volume_mute;

  /// Low volume.
  static const IconData volumeDown = Icons.volume_down;

  /// High volume.
  static const IconData volumeUp = Icons.volume_up;

  // ---- states over the video ----

  /// Playback failed.
  static const IconData playbackError = Icons.error_outline_rounded;

  /// A restricted room (login, paid, region).
  static const IconData restricted = Icons.lock_outline_rounded;

  /// No stream to play.
  static const IconData noStream = Icons.videocam_off_outlined;

  /// Play a finished replay again.
  static const IconData playAgain = Icons.replay_rounded;

  /// The picture is paused.
  static const IconData pausedOverlay = Icons.pause_circle_outline_rounded;

  // ---- the live room's popups (docs/ui/compare/U.2f) ----

  /// Close a panel or a sheet (✕).
  static const IconData close = Icons.close_rounded;

  /// The sleep timer (3.x's room menu).
  static const IconData sleepTimer = Remix.time_line;

  /// The room's own volume (3.x's room menu).
  static const IconData roomVolume = Remix.volume_up_line;

  /// Copy a stream address ("获取直链", 3.x's room menu).
  static const IconData streamLink = Remix.link_m;

  /// The room in a new window (Windows, 3.x's room menu).
  static const IconData newWindow = Icons.open_in_new_rounded;

  /// The local interaction sheet (3.x's room menu).
  static const IconData localInteraction = Icons.auto_awesome_rounded;

  /// Save the danmaku look as the user's template (3.x's danmaku settings).
  static const IconData templateSave = Icons.save_outlined;

  /// Apply the user's danmaku template (3.x's danmaku settings).
  static const IconData templateRestore = Icons.restore_rounded;

  /// A recording waits for a free slot.
  static const IconData recordQueued = Remix.hourglass_line;

  /// A recording reconnects.
  static const IconData recordReconnecting = Remix.loop_right_line;

  /// A recording is saved.
  static const IconData recordSaved = Icons.check_circle_rounded;

  /// A recording failed.
  static const IconData recordFailed = Icons.error_outline_rounded;

  /// Stop a recording (■).
  static const IconData stopRecording = Icons.stop_rounded;

  /// Something will not work as the user expects (a switched-off setting).
  static const IconData warning = Icons.warning_amber_rounded;

  // ---- the room's states (docs/ui/compare/U.2g) ----

  /// Play the next line ("换线路"; U.2g note 6: Material's alt route).
  static const IconData switchLine = Icons.alt_route_rounded;

  /// A room the platform banned or closed.
  static const IconData banned = Icons.block_rounded;

  /// The platform did not say whether the room is on air.
  static const IconData statusUnknown = Icons.help_outline_rounded;

  /// Sign in to the platform ("去登录"; U.2g, U.4e c6).
  static const IconData login = Icons.login_rounded;

  /// The IPTV programme guide's title (3.x `IptvScheduleDialog`).
  static const IconData guideTitle = Remix.calendar_todo_line;

  /// An ended programme that can be replayed (3.x `IptvScheduleDialog`).
  static const IconData catchup = Remix.history_line;

  /// The programme on air, the way back to it (3.x `IptvScheduleDialog`).
  static const IconData liveNow = Remix.live_line;

  /// A guide with no programmes for the channel (3.x).
  static const IconData guideEmpty = Remix.inbox_line;

  /// The guide could not be read (3.x).
  static const IconData guideFailed = Remix.error_warning_line;

  /// Add (a guide, a keyword, a new tag).
  static const IconData add = Remix.add_line;

  /// Unfold a column folded to the right (the wide channel's guide).
  static const IconData unfoldLeft = Remix.arrow_left_s_line;

  // ---- the room's tabs (docs/ui/compare/U.2e) ----

  /// No chat, no super chats yet (3.x `SuperChatPage`'s empty state).
  static const IconData chatEmpty = Remix.chat_smile_3_line;

  /// The danmaku server did not answer in time.
  static const IconData danmakuTimeout = Remix.wifi_off_line;

  /// The platform has no danmaku; the list is switched off.
  static const IconData danmakuUnavailable = Remix.chat_off_line;

  /// A super chat's price (3.x `SuperChatCard`).
  static const IconData superChatPrice = Remix.money_cny_circle_fill;

  /// The "SC" mark of a super chat (3.x `SuperChatCard`).
  static const IconData superChatMark = Remix.vip_diamond_fill;

  /// A super chat's remaining time (3.x `SuperChatCard`).
  static const IconData superChatTime = Remix.time_line;

  /// Remove a blocked word or viewer (×, 3.x `KeywordBlockPage`).
  static const IconData chipRemove = Remix.close_line;

  // ---- local interaction (3.x widgets/local_interaction, U.2k) ----

  /// The local danmaku style (the composer's star, 3.x `auto_awesome_rounded`).
  static const IconData localStyle = Icons.auto_awesome_rounded;

  /// Send a local danmaku (3.x `send_rounded`).
  static const IconData localSend = Icons.send_rounded;

  /// Local coins (3.x `toll_rounded`).
  static const IconData localCoins = Icons.toll_rounded;

  /// Local danmaku fly over the picture (3.x `subtitles_rounded`).
  static const IconData localOverlay = Icons.subtitles_rounded;

  /// The platform badge switch (3.x `workspace_premium_rounded`).
  static const IconData localBadge = Icons.workspace_premium_rounded;

  /// The local level switch (3.x `military_tech_rounded`).
  static const IconData localLevel = Icons.military_tech_rounded;

  /// The gift effect switch (3.x `celebration_rounded`).
  static const IconData localGiftEffects = Icons.celebration_rounded;

  /// Clear the local history (3.x `delete_sweep_outlined`).
  static const IconData localClearHistory = Icons.delete_sweep_outlined;

  /// The style preview's picture (3.x `live_tv_rounded`).
  static const IconData localPreviewStage = Icons.live_tv_rounded;

  /// The style preview's "实时预览" mark (3.x `play_circle_fill_rounded`).
  static const IconData localPreviewLive = Icons.play_circle_fill_rounded;

  /// The style's "saved and shared everywhere" line (3.x `sync_rounded`).
  static const IconData localStyleSync = Icons.sync_rounded;

  /// Scrolling local danmaku (3.x `trending_flat_rounded`).
  static const IconData localPlaceScroll = Icons.trending_flat_rounded;

  /// Local danmaku fixed at the top (3.x `vertical_align_top_rounded`).
  static const IconData localPlaceTop = Icons.vertical_align_top_rounded;

  /// Local danmaku fixed at the bottom (3.x `vertical_align_bottom_rounded`).
  static const IconData localPlaceBottom = Icons.vertical_align_bottom_rounded;

  /// Bold (3.x `format_bold_rounded`).
  static const IconData localBold = Icons.format_bold_rounded;

  /// Italic (3.x `format_italic_rounded`).
  static const IconData localItalic = Icons.format_italic_rounded;

  /// Outline (3.x `border_color_rounded`).
  static const IconData localStroke = Icons.border_color_rounded;

  /// Shadow or glow (3.x `blur_on_rounded`).
  static const IconData localShadow = Icons.blur_on_rounded;

  // ---- the mini windows (U.2j: in-app floating window, picture-in-picture,
  // desktop mini window; 3.x player_manager.dart) ----

  /// Back to the room from a mini window (new in U.2j).
  static const IconData backToRoom = Icons.open_in_full_rounded;

  /// Play in a mini window (3.x `Icons.play_circle_filled`).
  static const IconData miniPlay = Icons.play_circle_filled;

  /// Pause in a mini window (3.x `Icons.pause_circle_filled`).
  static const IconData miniPause = Icons.pause_circle_filled;

  /// The desktop mini window stays on top (new in U.2j; Remix, as 3.x's
  /// "pinned" marks).
  static const IconData pinned = Remix.pushpin_fill;

  /// The desktop mini window does not stay on top.
  static const IconData unpinned = Remix.pushpin_line;

  // ---- room cards, browsing pages and their dialogs (docs/ui/compare/U.4a–U.4f) ----

  /// A cover that is loading or failed to load (3.x's cover placeholder).
  static const IconData coverPlaceholder = Icons.live_tv_rounded;

  /// The replay badge on a cover (3.x `CountChip`).
  static const IconData replay = Icons.videocam_rounded;

  /// A live status being checked ("正在核验", "状态待确认").
  static const IconData statusPending = Icons.sync_rounded;

  /// A restricted room on a cover (paid, login, region …).
  static const IconData restrictedBadge = Icons.lock_rounded;

  /// Delete one entry (3.x's history card).
  static const IconData delete = Remix.delete_bin_line;

  /// A room's tags (3.x's card dialog).
  static const IconData tag = Remix.price_tag_3_line;

  /// Clear a text field.
  static const IconData clearField = Icons.cancel_rounded;

  /// The platform display settings (hide and order platforms).
  static const IconData platformSettings = Icons.tune_rounded;

  /// Drag to reorder (a six-dot handle, U.4f c9).
  static const IconData dragHandle = Icons.drag_indicator_rounded;

  /// A short explanation in a tinted bar.
  static const IconData info = Icons.info_outline_rounded;

  /// The 3.x information icon (the platform display explanation).
  static const IconData infoLine = Remix.information_line;

  /// Mobile data in use (3.x's cellular notice).
  static const IconData mobileData = Icons.signal_cellular_alt_rounded;

  /// Loading failed for the network (3.x `AppStatusView` error).
  static const IconData networkError = Icons.wifi_off_rounded;

  /// The platform wants a login.
  static const IconData loginRequired = Icons.account_circle_outlined;

  /// No live rooms on the popular page (3.x `RemixIcons.fire_fill`).
  static const IconData emptyPopular = Remix.fire_fill;

  /// No follows (3.x `Remix.heart_3_fill`).
  static const IconData emptyFollows = Remix.heart_3_fill;

  /// Areas (3.x `Remix.apps_2_line`): no areas, "go to areas".
  static const IconData areas = Remix.apps_2_line;

  /// Follow an area (3.x's "关注分区" button).
  static const IconData followArea = Remix.heart_add_2_line;

  /// Unfollow an area.
  static const IconData unfollowArea = Remix.dislike_line;

  /// A followed area, on its picture (U.4d c6).
  static const IconData areaFollowedMark = Icons.favorite_rounded;

  /// An area's picture is missing or broken (3.x `AreaCard`).
  static const IconData brokenImage = Icons.broken_image_rounded;

  /// Show what was hidden (rooms that cannot play here).
  static const IconData showHidden = Icons.visibility_rounded;

  /// Something is hidden.
  static const IconData hiddenNote = Icons.visibility_off_outlined;

  /// Scroll to the top (3.x's mini button).
  static const IconData toTop = Icons.arrow_upward_rounded;

  /// Scroll to the end (3.x's mini button).
  static const IconData toBottom = Icons.arrow_downward_rounded;

  /// The previous page of the desktop pager.
  static const IconData previousPage = Icons.chevron_left_rounded;

  /// The next page of the desktop pager.
  static const IconData nextPage = Icons.chevron_right_rounded;

  // ---- the desktop window's title bar (docs/ui/compare/U.13; 3.x
  // `CustomTitleBar`, desktop_manager.dart:572-580) ----

  /// Minimize the window (3.x `Icons.remove`).
  static const IconData windowMinimize = Icons.remove;

  /// Maximize the window (3.x `Icons.crop_square`).
  static const IconData windowMaximize = Icons.crop_square;

  /// Restore a maximized window: two squares, as Windows draws it (U.13 c3).
  static const IconData windowRestore = Icons.filter_none;

  /// Close the window (3.x `Icons.close`).
  static const IconData windowClose = Icons.close;
}
