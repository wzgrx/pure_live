import 'package:flutter/material.dart';
import 'package:live_ui/src/icons/custom_icons.dart';
import 'package:remixicon/remixicon.dart';

/// The app's icons by what they are for (docs/specs/UI.md §6.4).
///
/// Each use maps to the icon 3.x showed in that place (`Remix.*`,
/// Material's `Icons.*` or 3.x's own `CustomIcons`), so pages name the use,
/// not the glyph, and a later switch of icon set changes only this file.
/// Danmaku on, off and settings are pictures, see `DanmakuIcon`; the record
/// button's ring and dot are drawn by `RecordGlyph`.
abstract final class AppIcons {
  // ---- the home shell (docs/A-界面设计/A06-首页和全局/A06.1-手机首页, U.3b) ----

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

  /// More actions ("更多"; also a card's ⋮ menu).
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

  // ---- the global dialogs (docs/A-界面设计/A06-首页和全局/A06.3-全局弹窗) ----

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

  // ---- the live room's popups (docs/A-界面设计/A07-直播间界面/A07.6-直播间弹窗) ----

  /// Close a panel or a sheet (✕).
  static const IconData close = Icons.close_rounded;

  /// The sleep timer (3.x's room menu).
  static const IconData sleepTimer = Remix.time_line;

  /// The room's own volume (3.x's room menu).
  static const IconData roomVolume = Remix.volume_up_line;

  /// The room volume panel's mute button, silent (3.x `volumeIcon`).
  static const IconData volumeMuted = Icons.volume_off_rounded;

  /// The room volume panel's mute button, below half.
  static const IconData volumeLow = Icons.volume_down_rounded;

  /// The room volume panel's mute button, half and above.
  static const IconData volumeHigh = Icons.volume_up_rounded;

  /// A DLNA receiver in the cast panel (3.x `LiveDlnaPage`).
  static const IconData castDevice = Icons.tv_rounded;

  /// Unfollow, in the follow button's menu (docs/A-界面设计/A07-直播间界面/A07.12-直播间子弹窗统一 c8).
  static const IconData unfollow = Remix.dislike_line;

  /// Copy a stream address ("获取直链", 3.x's room menu).
  static const IconData streamLink = Remix.link_m;

  /// The room in a new window (Windows, the room menu): the same stacked
  /// pages as the home menu's [newPlayerWindow] (A16.1 c12), so it no
  /// longer looks like [openExternal] next to it.
  static const IconData newWindow = Icons.add_to_photos_outlined;

  /// The local interaction sheet (the room menu and the settings page's
  /// header): its own glyph since 2026-10-09, so the star only means the
  /// local danmaku style ([localStyle], A08.13 c2, one meaning one icon).
  static const IconData localInteraction = Icons.interests_rounded;

  /// Save the danmaku look as the user's template (3.x's danmaku settings).
  static const IconData templateSave = Icons.save_outlined;

  /// Apply the user's danmaku template (3.x's danmaku settings).
  static const IconData templateRestore = Icons.restore_rounded;

  /// A recording is saved.
  static const IconData recordSaved = Icons.check_circle_rounded;

  // ---- the recording centre (3.x recorder_page.dart; docs/A-界面设计/A10-录制界面/A10.1-录制中心) ----

  /// Open the recording folder (3.x's app bar).
  static const IconData recordFolder = Remix.folder_video_line;

  /// The recording settings (3.x's app bar).
  static const IconData recordSettings = Remix.settings_5_line;

  /// No record task (3.x's empty centre).
  static const IconData recordEmpty = Icons.video_collection_outlined;

  /// This build cannot record.
  static const IconData recordUnavailable = Icons.videocam_off_outlined;

  /// Enter the live room (a card's menu).
  static const IconData enterRoom = Icons.open_in_new_rounded;

  /// Delete (a record task, a history entry).
  static const IconData delete = Remix.delete_bin_line;

  /// Stop a recording (■).
  static const IconData stopRecording = Icons.stop_rounded;

  /// Something will not work as the user expects (a switched-off setting).
  static const IconData warning = Icons.warning_amber_rounded;

  // ---- portrait streams, fullscreen and the wide room (docs/TASKS.md) ----

  /// The portrait room's handle: swipe down into the portrait fullscreen.
  static const IconData portraitFullscreenEnter = Icons.keyboard_arrow_down_rounded;

  /// The portrait fullscreen's hint: swipe up back to the panel.
  static const IconData portraitFullscreenRestore = Icons.keyboard_arrow_up_rounded;

  /// A one-off landscape fullscreen of a portrait room ("横屏全屏").
  static const IconData landscapeFullscreen = Icons.screen_rotation_rounded;

  /// The picture fills the window, without the app bar and the chat
  /// (3.x `ExpandWindowButton`, drawn a quarter turn round).
  static const IconData windowFullscreen = Icons.unfold_more_rounded;

  /// Leave the in-window fullscreen.
  static const IconData windowFullscreenExit = Icons.unfold_less_rounded;

  /// Fold the wide room's chat column away or bring it back.
  static const IconData chatColumn = Icons.vertical_split_rounded;

  /// The chat column's edge handle while the column shows (fold it to the right).
  static const IconData chatColumnFold = Remix.arrow_right_s_line;

  /// The edge handle while the column is folded (bring it back).
  static const IconData chatColumnUnfold = Remix.arrow_left_s_line;

  // ---- the room's states (docs/A-界面设计/A07-直播间界面/A07.7-直播间的状态) ----

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

  // ---- the room's tabs (docs/A-界面设计/A08-弹幕界面/A08.1-弹幕列表和弹幕设置页) ----

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

  /// Open the local danmaku composer: the chat list's button and the narrow
  /// fullscreen bar's (A08.13; they showed the style's star, one icon for
  /// two things). A speech bubble with a pen: write, not send yet.
  static const IconData localCompose = Icons.rate_review_rounded;

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

  /// "进房放回之前发的本地弹幕" (D08.1 c6; 3.x had no such switch).
  static const IconData localReplay = Icons.history_toggle_off_rounded;

  /// Send a danmaku's words once more as a local danmaku: "+1（本地）" on a
  /// platform's, "再发一次" on one's own (A08.14; 3.x had neither).
  static const IconData localSendAgain = Icons.plus_one_rounded;

  /// A chip over the local danmaku composer that is one of the local
  /// danmaku sent last ("最近", D08.2; 3.x had no chips).
  static const IconData localRecent = Icons.history_rounded;

  /// "存为常用语" in a local danmaku's panel (D08.2).
  static const IconData localPhraseSave = Icons.playlist_add_rounded;

  /// "已在常用语里": the danmaku is one of the phrases already (D08.2).
  static const IconData localPhraseSaved = Icons.playlist_add_check_rounded;

  /// The phrases group on the local interaction settings page (D08.2).
  static const IconData localPhrases = Icons.format_list_bulleted_rounded;

  // ---- the mini windows (U.2j: in-app floating window, picture-in-picture,
  // desktop mini window; 3.x player_manager.dart) ----

  /// Back to the room from a mini window (new in U.2j).
  static const IconData backToRoom = Icons.open_in_full_rounded;

  /// The desktop mini window stays on top (new in U.2j; Remix, as 3.x's
  /// "pinned" marks).
  static const IconData pinned = Remix.pushpin_fill;

  /// The desktop mini window does not stay on top.
  static const IconData unpinned = Remix.pushpin_line;

  /// The in-app floating window's resize grip on its bottom-left corner
  /// (docs/A-界面设计/A07-直播间界面/A07.22-小窗改大小和尺寸设置): an arrow out of the
  /// corner, the way it grows.
  static const IconData miniResizeBottomLeft = Icons.south_west_rounded;

  /// The grip on the bottom-right corner.
  static const IconData miniResizeBottomRight = Icons.south_east_rounded;

  // ---- room cards, browsing pages and their dialogs (docs/A-界面设计/A09-浏览界面/A09.1-房间卡片–U.4f) ----

  /// A cover that is loading or failed to load (3.x's cover placeholder).
  static const IconData coverPlaceholder = Icons.live_tv_rounded;

  /// The replay badge on a cover (3.x `CountChip`).
  static const IconData replay = Icons.videocam_rounded;

  /// A live status being checked ("正在核验", "状态待确认").
  static const IconData statusPending = Icons.sync_rounded;

  /// A restricted room on a cover (paid, login, region …).
  static const IconData restrictedBadge = Icons.lock_rounded;

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

  /// Scroll to the top (3.x's mini button).
  static const IconData toTop = Icons.arrow_upward_rounded;

  /// Scroll to the end (3.x's mini button).
  static const IconData toBottom = Icons.arrow_downward_rounded;

  /// The pull-to-refresh header while pulled; turns over once releasing
  /// refreshes (3.x `plugins/global.dart` pull icon; U.1c c19).
  static const IconData refreshPull = Icons.arrow_downward_rounded;

  /// The pull-to-refresh header after a refresh (easy_refresh's
  /// `ClassicHeader` default).
  static const IconData refreshSucceeded = Icons.done_rounded;

  /// The pull-to-refresh header after a failed refresh (U.1c c19).
  static const IconData refreshFailed = Icons.error_outline_rounded;

  /// The previous page of the desktop pager (3.x `desktop_components.dart`
  /// `Icons.arrow_back_ios_new_rounded`).
  static const IconData previousPage = Icons.arrow_back_ios_new_rounded;

  /// The next page of the desktop pager (3.x
  /// `Icons.arrow_forward_ios_rounded`).
  static const IconData nextPage = Icons.arrow_forward_ios_rounded;

  /// The desktop pager's rooms-per-page menu (3.x
  /// `Icons.arrow_drop_down_rounded`).
  static const IconData pageSize = Icons.arrow_drop_down_rounded;

  // ---- multi-view (docs/A-界面设计/A13-网络电视和多画面界面/A13.2-多画面; 3.x lib/modules/multiview) ----

  /// Keep only the cells on screen (沉浸模式).
  static const IconData immersive = Remix.expand_diagonal_line;

  /// Leave the immersive mode.
  static const IconData exitImmersive = Remix.collapse_diagonal_line;

  /// The multi-view in fullscreen.
  static const IconData gridFullscreen = Remix.fullscreen_line;

  /// Leave the multi-view's fullscreen.
  static const IconData gridExitFullscreen = Remix.fullscreen_exit_line;

  /// One view (1×1).
  static const IconData layoutSingle = Remix.aspect_ratio_line;

  /// Two views (1×2).
  static const IconData layoutDual = Remix.layout_column_line;

  /// Four views (2×2).
  static const IconData layoutQuad = Remix.layout_grid_line;

  /// One large view and small ones (1+3).
  static const IconData layoutFocus = Remix.focus_3_line;

  /// Silence every view ("全部静音"; the sound plays).
  static const IconData muteAll = Remix.volume_up_line;

  /// Every view is silent ("恢复声音").
  static const IconData mutedAll = Remix.volume_mute_line;

  /// Small views play the lowest quality ("小格省流").
  static const IconData smallCellSaver = Remix.speed_mini_line;

  /// Play one view.
  static const IconData cellPlay = Remix.play_line;

  /// Pause one view.
  static const IconData cellPause = Remix.pause_line;

  /// Load one view again.
  static const IconData cellRefresh = Remix.refresh_line;

  /// Pick another room for a view ("换台").
  static const IconData changeRoom = Icons.swap_horiz_outlined;

  /// Empty a view ("关闭这一格").
  static const IconData closeCell = Remix.close_circle_line;

  /// A view's room volume.
  static const IconData cellVolume = Remix.volume_down_line;

  /// The view whose sound plays ("声音来源").
  static const IconData audioFocus = Remix.volume_up_line;

  /// An empty view, the "添加画面" slot.
  static const IconData addCell = Remix.add_circle_line;

  /// A view whose room is not on air.
  static const IconData roomOffline = Remix.live_line;

  /// A view that failed to play.
  static const IconData cellFailed = Remix.error_warning_line;

  /// Bring back the last visit's rooms.
  static const IconData restoreLast = Remix.history_line;

  /// Fold the right column away.
  static const IconData foldRight = Icons.chevron_right_rounded;

  // ---- IPTV settings (docs/A-界面设计/A13-网络电视和多画面界面/A13.1-网络电视管理; 3.x iptv_page.dart, iptv_manage.dart) ----

  /// Sync every network playlist and guide (the title bar), and the
  /// "sync at start" switch.
  static const IconData syncAll = Remix.refresh_line;

  /// "导入播放列表".
  static const IconData importPlaylist = Remix.download_2_line;

  /// "导入节目单".
  static const IconData importGuide = Remix.file_add_line;

  /// A playlist (its card, the import dialog's title, the empty state).
  static const IconData playlist = Remix.play_list_2_line;

  /// Adding a playlist: the import dialog's title and the empty state.
  static const IconData playlistAdd = Remix.play_list_add_line;

  /// A programme guide (its card, "当前使用的节目单", the default guide).
  static const IconData guide = Icons.assignment_outlined;

  /// A source read from a network address ("网络", "网络导入").
  static const IconData networkSource = Remix.global_line;

  /// A source read from a local file ("本地").
  static const IconData localSource = Remix.folder_2_line;

  /// Import a local playlist file.
  static const IconData localPlaylistFile = Remix.folder_open_line;

  /// Import a local guide file.
  static const IconData localGuideFile = Remix.draft_line;

  /// Import a guide from a network address.
  static const IconData networkGuide = Remix.cloud_windy_line;

  /// Paste text: the playlist import, a cookie.
  static const IconData pasteText = Remix.clipboard_line;

  /// Sync one source.
  static const IconData syncOne = Remix.download_cloud_2_line;

  /// A source's automatic sync.
  static const IconData autoSync = Remix.repeat_line;

  /// The automatic sync interval.
  static const IconData syncInterval = Remix.time_line;

  /// The IPTV request header (User-Agent).
  static const IconData userAgent = Remix.tv_line;

  /// The chosen option of a list of choices.
  static const IconData choiceOn = Remix.checkbox_circle_fill;

  /// An option of a list of choices that is not chosen.
  static const IconData choiceOff = Remix.checkbox_blank_circle_line;

  /// Empty a text field.
  static const IconData clearText = Remix.close_circle_line;

  /// Something failed (a load error, an expired QR code).
  static const IconData failed = Remix.error_warning_line;

  /// A row that opens another page (›).
  static const IconData navigate = Icons.chevron_right_rounded;

  // ---- platform accounts and cookies (docs/A-界面设计/A12-账号和数据界面/A12.1-账号总览, U.10b; 3.x modules/account) ----

  /// Sign out of a platform.
  static const IconData signOut = Remix.logout_box_r_line;

  /// Empty the cookie box.
  static const IconData eraseText = Remix.eraser_line;

  /// Save (the cookie page).
  static const IconData save = Icons.save_rounded;

  /// Ask the platform again who a cookie signs in as.
  static const IconData recheck = Remix.refresh_line;

  /// A QR code to scan.
  static const IconData qrCode = Remix.qr_code_line;

  /// The QR code was scanned.
  static const IconData qrScanned = Remix.checkbox_circle_line;

  /// Sign in on a web page.
  static const IconData webLogin = Remix.global_line;

  // ---- the retired cloud account (docs/A-界面设计/A12-账号和数据界面/A12.3-云账号停用说明) ----

  /// The cloud account is gone.
  static const IconData cloudOff = Remix.cloud_off_line;

  /// WebDAV backups (3.x backup page).
  static const IconData webDav = Remix.upload_cloud_2_line;

  /// Device sync over the local network (3.x backup page).
  static const IconData deviceSync = Remix.qr_scan_2_line;

  /// Backup files.
  static const IconData backupFiles = Remix.save_3_line;

  /// The platform accounts (3.x settings "三方认证"; 3.x's accessibility
  /// figure read as accessibility, A01.4 c4).
  static const IconData platformAccounts = Remix.account_box_line;

  // ---- settings: the overview (3.x settings_page.dart; U.6a) ----

  /// Appearance (3.x "主题定制").
  static const IconData settingsAppearance = Remix.palette_line;

  /// The bottom navigation bar's pages.
  static const IconData settingsNavigation = Remix.menu_line;

  /// Platforms shown and their accounts.
  static const IconData settingsPlatforms = Remix.apps_2_line;

  /// Automatic refresh of follows and covers.
  static const IconData settingsRefresh = Remix.refresh_line;

  /// IPTV sources.
  static const IconData settingsIptv = Remix.tv_line;

  /// Video playback.
  static const IconData settingsVideo = Remix.film_line;

  /// Danmaku in picture-in-picture and floating windows.
  static const IconData settingsPipDanmaku = Remix.picture_in_picture_2_line;

  /// The player engine and decoding.
  static const IconData settingsPlayerKernel = Remix.cpu_line;

  /// Recording settings.
  static const IconData settingsRecording = Remix.record_circle_line;

  /// General settings.
  static const IconData settingsGeneral = Remix.settings_4_line;

  /// "播放时匹配视频帧率" (U.2i): the refresh rate follows the video.
  static const IconData matchFrameRate = Remix.movie_2_line;

  /// Network proxies (a globe in 3.x; the language has its own icon now,
  /// A01.4 c4).
  static const IconData settingsNetwork = Remix.global_line;

  /// The app's language (3.x used the network globe, A01.4 c4).
  static const IconData settingsLanguage = Remix.translate_2;

  /// Local interaction: the same glyph as [localInteraction].
  static const IconData settingsLocalInteraction = Icons.interests_rounded;

  /// Cache and data.
  static const IconData settingsCache = Remix.database_2_line;

  /// Backup and restore.
  static const IconData settingsBackup = Remix.cloud_line;

  /// The local configuration preview.
  static const IconData settingsConfigPreview = Remix.file_text_line;

  // ---- settings: appearance (3.x theme_settings_page.dart; U.6b) ----

  /// Theme mode.
  static const IconData themeMode = Remix.moon_clear_line;

  /// Pure black background.
  static const IconData pureBlack = Remix.contrast_2_line;

  /// Theme colour (and the loading colour).
  static const IconData themeColor = Remix.palette_line;

  /// Dynamic colour.
  static const IconData dynamicColor = Remix.magic_line;

  /// Room card settings (3.x shared the multi-view grid; A01.4 c4 gives
  /// the cards their own).
  static const IconData roomCardSettings = Remix.gallery_view_2;

  /// Column spacing.
  static const IconData columnSpacing = Remix.arrow_left_right_line;

  /// Row spacing.
  static const IconData rowSpacing = Remix.arrow_up_down_line;

  /// The scroll-to-top button.
  static const IconData scrollToTop = Remix.arrow_up_circle_line;

  /// Paging settings.
  static const IconData pageSettings = Remix.pages_line;

  /// Interface mode (phone or TV).
  static const IconData uiMode = Remix.device_line;

  /// The app font.
  static const IconData appFont = Remix.font_family;

  /// Text size.
  static const IconData textSize = Remix.text_spacing;

  /// The five text sizes; the small text size.
  static const IconData fontSizes = Remix.font_size;

  /// Body text size.
  static const IconData fontBody = Remix.text;

  /// Large body text size.
  static const IconData fontBodyLarge = Remix.text_wrap;

  /// Card title size.
  static const IconData fontTitle = Remix.heading;

  /// App bar title size.
  static const IconData fontTitleLarge = Remix.bold;

  /// Reset the text sizes (3.x).
  static const IconData resetFontSizes = Remix.rest_time_line;

  /// Restore the loading style (3.x).
  static const IconData restoreDefault = Remix.arrow_go_back_line;

  /// Reset the room card layout (the same as [restoreDefault], A01.4 c4).
  static const IconData resetLayout = Remix.arrow_go_back_line;

  /// Show the anchor's avatar.
  static const IconData cardAvatar = Remix.user_3_line;

  /// Show the anchor's name.
  static const IconData cardAnchor = Remix.account_circle_line;

  /// Show the audience.
  static const IconData cardAudience = Remix.group_line;

  /// Show the replay badge.
  static const IconData cardReplay = Remix.video_line;

  /// The card layout.
  static const IconData cardLayout = Icons.view_agenda_outlined;

  /// The corner radius.
  static const IconData cornerRadius = Remix.rounded_corner;

  /// The page-size selector of the pager.
  static const IconData pageSizeSelector = Remix.list_settings_line;

  /// "Go to page" of the pager.
  static const IconData pageGoto = Remix.skip_forward_mini_line;

  /// The page sizes offered.
  static const IconData pageSizeOptions = Remix.list_check_2;

  /// The default page size.
  static const IconData pageDefaultSize = Remix.layout_line;

  /// Back to the recommended page sizes.
  static const IconData pageSizeRecommended = Icons.restart_alt_rounded;

  /// The system font.
  static const IconData systemFont = Icons.settings_suggest_outlined;

  /// Open a folder.
  static const IconData openFolder = Remix.folder_open_line;

  /// Download.
  static const IconData download = Remix.download_cloud_2_line;

  /// More actions (⋮).
  static const IconData moreVertical = Icons.more_vert_rounded;

  /// The chosen item of a gallery (a loading style).
  static const IconData chosen = Icons.check_circle_rounded;

  // ---- the desktop window's title bar (docs/A-界面设计/A16-桌面界面/A16.1-桌面窗口; 3.x
  // `CustomTitleBar`, desktop_manager.dart:572-580) ----

  /// Minimize the window (3.x `Icons.remove`).
  static const IconData windowMinimize = Icons.remove;

  /// Maximize the window (3.x `Icons.crop_square`).
  static const IconData windowMaximize = Icons.crop_square;

  /// Restore a maximized window: two squares, as Windows draws it (U.13 c3).
  static const IconData windowRestore = Icons.filter_none;

  /// Close the window (3.x `Icons.close`).
  static const IconData windowClose = Icons.close;

  // ---- search, web search and the watch history (docs/A-界面设计/A09-浏览界面/A09.7-搜索–U.5c) ----

  /// Search the words in the search field (3.x's field, `Icons.search`).
  static const IconData submitSearch = Icons.search;

  /// Paste the clipboard into an empty search field.
  static const IconData paste = Icons.content_paste_rounded;

  /// The "all platforms" chip of the search's platform row.
  static const IconData allPlatforms = Icons.apps_rounded;

  /// The order of search results (3.x `Icons.sort_rounded`).
  static const IconData sort = Icons.sort_rounded;

  /// The platform's web search; a page opened in the system browser (3.x
  /// `Icons.open_in_browser_rounded`).
  static const IconData webSearch = Icons.open_in_browser_rounded;

  /// A line that opens more about itself (the search's scope line).
  static const IconData openDetails = Icons.chevron_right_rounded;

  /// The search before the first search (3.x `Icons.travel_explore_rounded`).
  static const IconData searchStart = Icons.travel_explore_rounded;

  /// Nothing found (3.x `Icons.search_off_rounded`).
  static const IconData noResults = Icons.search_off_rounded;

  /// Load more results (3.x `Icons.expand_more_rounded`).
  static const IconData loadMore = Icons.expand_more_rounded;

  /// Recent search words.
  static const IconData searchHistory = Icons.history_rounded;

  /// Remove every entry of a short list (recent search words).
  static const IconData clearAll = Icons.delete_sweep_outlined;

  /// A system component is missing (3.x's WebView2 dialog).
  static const IconData componentMissing = Icons.report_problem_rounded;

  /// Filter a list by words (the watch history).
  static const IconData filter = Icons.search_rounded;

  /// Close the filter.
  static const IconData filterOff = Icons.search_off_rounded;

  /// How many history entries are kept (3.x `Icons.settings_rounded`).
  static const IconData historyLimit = Icons.settings_rounded;

  /// Clear the watch history (3.x `Icons.delete_forever`).
  static const IconData clearHistory = Icons.delete_forever;

  /// No watch history (3.x `Icons.history_rounded`).
  static const IconData historyEmpty = Icons.history_rounded;

  /// Open the room of a pasted link (3.x toolbox "链接跳转").
  static const IconData linkJump = Remix.play_circle_line;

  /// "在线更新" on the about page (3.x).
  static const IconData onlineUpdate = Remix.download_cloud_2_line;

  /// "版本历史" on the about page (3.x "历史记录").
  static const IconData versionHistory = Remix.history_line;

  /// "开源许可证" on the about page (3.x).
  static const IconData licenses = Remix.shield_user_line;

  /// "项目主页" on the about page (3.x).
  static const IconData projectPage = Remix.code_s_slash_line;

  /// The update page's status card: a newer version is out.
  static const IconData updateAvailable = Icons.system_update_rounded;

  /// The update page's status card: this is the newest version.
  static const IconData upToDate = Icons.verified_rounded;

  /// Download an installation package (3.x version pages).
  static const IconData downloadPackage = Remix.download_2_line;

  /// One download mirror of a package (3.x "下载源 N").
  static const IconData downloadSource = Remix.link_m;

  /// Download in the browser.
  static const IconData openInBrowser = Icons.open_in_browser_rounded;

  /// A file of a release (3.x version history).
  static const IconData releaseFile = Remix.box_3_line;

  /// A release's publisher without an avatar (3.x version history).
  static const IconData releaseAuthor = Remix.user_line;

  /// Open a release's page (3.x version history).
  static const IconData releasePage = Remix.link;

  /// Edit (a tag; 3.x tag management).
  static const IconData edit = Remix.edit_line;

  /// The followed rooms that carry a tag.
  static const IconData tagRooms = Icons.live_tv_rounded;

  // ---- settings: playback (3.x video_settings_page.dart and the pages it
  // opens, player_kernel_settings_page.dart; U.6c) ----

  /// Global mute.
  static const IconData settingsMuted = Remix.volume_mute_line;

  /// The phones' default volume (3.x's handset read as the call volume,
  /// A01.4 c4).
  static const IconData settingsPhoneVolume = Remix.volume_up_line;

  /// The computers' default volume.
  static const IconData settingsDesktopVolume = Remix.volume_up_line;

  /// The preferred quality.
  static const IconData settingsQuality = Remix.hd_line;

  /// The quality on mobile data.
  static const IconData settingsCellularQuality = Remix.signal_tower_line;

  /// Prefer H.264.
  static const IconData settingsH264 = Remix.film_line;

  /// The picture's fit.
  static const IconData settingsVideoFit = Remix.aspect_ratio_line;

  /// Full screen on entering a room.
  static const IconData settingsFullscreenDefault = Remix.fullscreen_line;

  /// Keep the screen on.
  static const IconData settingsScreenKeepOn = Remix.lightbulb_line;

  /// Portrait streams.
  static const IconData settingsPortrait = Icons.stay_current_portrait_rounded;

  /// Audience counts and ranking.
  static const IconData settingsAudience = Icons.groups_2_rounded;

  /// Background play.
  static const IconData settingsBackgroundPlay = Remix.music_2_line;

  /// Automatic sleep in new rooms (the moon is the theme mode, A01.4 c4).
  static const IconData settingsAutoSleep = Remix.zzz_line;

  /// How long the automatic sleep plays.
  static const IconData settingsSleepMinutes = Remix.timer_2_line;

  /// The in-app mini window on leaving a room.
  static const IconData settingsLeaveRoomMini = Remix.picture_in_picture_2_line;

  /// Picture-in-picture on leaving the app.
  static const IconData settingsAutoPip = Icons.picture_in_picture_alt_rounded;

  /// How big the in-app floating window is (A07.22).
  static const IconData settingsMiniSize = Icons.photo_size_select_large_rounded;

  /// The desktop mini window stays on top.
  static const IconData settingsPipOnTop = Remix.pushpin_line;

  /// Remember the desktop mini window's place and size.
  static const IconData settingsPipRemember = Remix.terminal_window_fill;

  /// Forget the desktop mini window's place and size.
  static const IconData settingsPipReset = Remix.reserved_line;

  /// Show danmaku.
  static const IconData settingsShowDanmaku = Remix.chat_smile_2_line;

  /// The danmaku style (the room's danmaku settings; the palette is the
  /// theme colour, A01.4 c4).
  static const IconData settingsDanmakuStyle = Remix.chat_settings_line;

  /// The danmaku font (the same as [appFont]; the text size has
  /// [fontSizes]).
  static const IconData settingsDanmakuFont = Remix.font_family;

  /// The danmaku block list.
  static const IconData settingsDanmakuBlock = Remix.filter_2_line;

  /// The player engine.
  static const IconData settingsKernel = Remix.toggle_line;

  /// Close the player for good on leaving.
  static const IconData settingsHardStop = Remix.shut_down_line;

  /// Hardware decoding.
  static const IconData settingsHardwareDecoding = Remix.speed_up_line;

  /// The compatibility mode.
  static const IconData settingsCompatMode = Remix.shield_check_line;

  /// NVIDIA RTX video super resolution.
  static const IconData settingsRtxVsr = Remix.image_edit_line;

  /// The player's proxy.
  static const IconData settingsPlayerProxy = Remix.global_line;

  /// Custom mpv drivers.
  static const IconData settingsCustomOutput = Remix.code_box_line;

  /// mpv's video output.
  static const IconData settingsVideoOutput = Remix.movie_line;

  /// mpv's audio output.
  static const IconData settingsAudioOutput = Remix.volume_up_line;

  /// mpv's hardware decoder.
  static const IconData settingsDecoder = Remix.cpu_line;

  /// Back to the defaults of a page.
  static const IconData settingsRestoreDefaults = Icons.restart_alt_rounded;

  /// Smart portrait detection.
  static const IconData portraitDetect = Icons.aspect_ratio_rounded;

  /// Adaptive height of the room page (the rows are the card layout,
  /// A01.4 c4).
  static const IconData portraitHeight = Icons.height_rounded;

  /// The room page's layout for portrait streams.
  static const IconData portraitLayout = Icons.dashboard_customize_outlined;

  /// The full-screen orientation.
  static const IconData portraitFullscreen = Icons.fullscreen_rounded;

  /// The portrait full-screen picture.
  static const IconData portraitDisplay = Icons.fit_screen_rounded;

  /// The mini window follows the picture.
  static const IconData portraitPip = Icons.picture_in_picture_alt_rounded;

  /// Danmaku on portrait streams.
  static const IconData portraitDanmaku = Icons.subtitles_outlined;

  /// Remember a room's orientation.
  static const IconData portraitRemember = Icons.bookmark_added_outlined;

  /// Show the detection state.
  static const IconData portraitDiagnostics = Icons.monitor_heart_outlined;

  // ---- settings: general, platforms, refresh, network (U.6d) ----

  /// The refresh-rate policy (the speedometer is hardware decoding,
  /// A01.4 c4).
  static const IconData settingsRefreshRate = Remix.pulse_line;

  /// Start with the system.
  static const IconData settingsStartup = Remix.windows_line;

  /// The window size at start (the aspect ratio is the video fit, A01.4
  /// c4).
  static const IconData settingsWindowSize = Remix.window_line;

  /// The splash animation.
  static const IconData settingsSplash = Remix.rocket_2_line;

  /// Share codes on the clipboard (F.0a).
  static const IconData settingsClipboardRooms = Remix.clipboard_line;

  /// Check for updates (the same as [onlineUpdate]; the arrows are a
  /// refresh, A01.4 c4).
  static const IconData settingsAutoUpdate = Remix.download_cloud_2_line;

  /// GitHub as the update source.
  static const IconData settingsGitHub = Remix.github_line;

  /// What closing the window does.
  static const IconData settingsCloseWindow = Remix.logout_box_r_line;

  /// The exit timer.
  static const IconData settingsExitTimer = Remix.timer_line;

  /// How long before the app exits (the same as [settingsExitTimer]; the
  /// flash stopwatch is the recording timeout, A01.4 c4).
  static const IconData settingsExitMinutes = Remix.timer_line;

  /// The platforms shown.
  static const IconData settingsPlatformList = Remix.apps_2_line;

  /// The platform opened first.
  static const IconData settingsPreferPlatform = Remix.star_line;

  /// Show unplayable rooms.
  static const IconData settingsUnplayable = Remix.lock_line;

  /// Twitch's languages.
  static const IconData settingsTwitchLanguages = Remix.twitch_line;

  /// Renew Douyu's cookie (a key: the login, not a refresh, A01.4 c4).
  static const IconData settingsDouyuRenew = Remix.key_2_line;

  /// Refresh follows automatically.
  static const IconData settingsAutoRefresh = Remix.refresh_line;

  /// Refresh follows on returning to the app (a refresh, A01.4 c4).
  static const IconData settingsRefreshOnResume = Remix.refresh_line;

  /// "开播提醒": a notification when a followed streamer goes live (O01.1).
  static const IconData settingsLiveAlert = Remix.notification_3_line;

  /// A refresh interval.
  static const IconData settingsInterval = Remix.time_line;

  /// Parallel refresh tasks.
  static const IconData settingsConcurrency = Remix.server_line;

  /// Refresh covers automatically.
  static const IconData settingsAutoCovers = Remix.image_2_line;

  /// How many rooms the history keeps.
  static const IconData settingsHistoryLimit = Remix.history_line;

  /// The app's proxy (the network globe; 3.x's four circles read as the
  /// platforms, A01.4 c4).
  static const IconData settingsAppProxy = Remix.global_line;

  /// The player's proxy (on the network page).
  static const IconData settingsStreamProxy = Remix.video_line;

  // ---- settings: data (3.x cache_data_settings_page.dart,
  // local_config_preveiw.dart; U.6e) ----

  /// The cache's size.
  static const IconData settingsCacheSize = Remix.database_2_line;

  /// Measure the cache again.
  static const IconData settingsRecount = Icons.refresh_rounded;

  /// Refresh the covers now.
  static const IconData settingsRefreshCovers = Remix.image_2_line;

  /// Clear the cache.
  static const IconData settingsClearCache = Remix.delete_bin_6_line;

  /// The download folder.
  static const IconData settingsDownloadFolder = Remix.folder_2_line;

  /// Back to the default download folder (the same as [restoreDefault],
  /// A01.4 c4).
  static const IconData settingsDownloadReset = Remix.arrow_go_back_line;

  /// The log.
  static const IconData settingsLog = Remix.file_list_3_line;

  /// Every language (the Twitch filter's preset).
  static const IconData allLanguages = Icons.public_rounded;

  /// 3.x's choice (the Twitch filter's preset).
  static const IconData legacyPreset = Icons.history_rounded;

  /// Read again after an error.
  static const IconData settingsReload = Icons.refresh_rounded;

  /// A branch of the configuration tree, open.
  static const IconData treeExpanded = Icons.keyboard_arrow_down_rounded;

  /// A branch of the configuration tree, closed.
  static const IconData treeCollapsed = Icons.keyboard_arrow_right_rounded;

  /// Backup and restore, from the configuration preview.
  static const IconData settingsToBackup = Icons.settings_backup_restore_rounded;

  // ---- the recording settings (3.x record_settings_page.dart; docs/A-界面设计/A10-录制界面/A10.2-录制设置) ----

  /// The default recording quality.
  static const IconData recordQuality = Remix.hd_line;

  /// Pinyin folder names (the translation mark is the language, A01.4
  /// c4).
  static const IconData recordPinyin = Remix.input_method_line;

  /// Record the danmaku too.
  static const IconData recordDanmaku = Remix.chat_3_line;

  /// Limit the recordings' total size.
  static const IconData recordSizeLimit = Remix.exchange_box_line;

  /// The total size cap.
  static const IconData recordSizeCap = Remix.database_2_line;

  /// The space the recordings take.
  static const IconData recordUsedSpace = Remix.custom_size;

  /// Empty the recording folder.
  static const IconData recordClear = Remix.delete_bin_4_line;

  /// Prefer the original track.
  static const IconData recordBestStream = Remix.video_download_line;

  /// The read and write timeout.
  static const IconData recordTimeout = Remix.timer_flash_line;

  /// The input queue.
  static const IconData recordQueue = Remix.speed_mini_line;

  /// The segment length (the film is the video, A01.4 c4).
  static const IconData recordSegment = Remix.scissors_cut_line;

  /// The most recordings at once.
  static const IconData recordMaxTasks = Remix.task_line;

  /// Reconnect when a recording breaks (A01.4 c4).
  static const IconData recordReconnect = Remix.loop_right_line;

  /// The most retries.
  static const IconData recordRetries = Remix.loop_left_line;

  /// An interval (reconnect, live check).
  static const IconData recordInterval = Remix.time_line;

  /// The live check.
  static const IconData recordPolling = Remix.radar_line;

  /// The live check's back-off.
  static const IconData recordBackoff = Remix.line_chart_line;

  /// The longest check interval.
  static const IconData recordMaxInterval = Remix.hourglass_2_line;

  /// Resume the recordings at start.
  static const IconData recordResume = Remix.restart_line;

  /// One less (the counter rows).
  static const IconData decrease = Icons.remove_rounded;

  /// One more (the counter rows).
  static const IconData increase = Icons.add_rounded;

  // ---- backup and restore (3.x backup_page.dart, scan_page.dart; docs/A-界面设计/A12-账号和数据界面/A12.4-备份与恢复) ----

  /// Send the data to the TV.
  static const IconData syncTv = Remix.qr_code_line;

  /// Create a backup, export the follows.
  static const IconData backupCreate = Remix.file_download_line;

  /// Restore a backup, import the follows.
  static const IconData backupRestore = Remix.file_upload_line;

  /// A full backup file.
  static const IconData backupFile = Remix.file_text_line;

  /// A follows-only backup file; restore only the follows.
  static const IconData backupFollows = Remix.heart_line;

  /// The backup folder has no backup.
  static const IconData backupEmpty = Icons.inventory_2_outlined;

  /// The backup folder.
  static const IconData backupFolder = Remix.folder_open_line;

  /// Open the backup folder in the file manager (computers).
  static const IconData backupOpenFolder = Remix.external_link_line;

  /// The scanner's torch is off.
  static const IconData torchOff = Icons.flash_off_rounded;

  /// The scanner's torch is on.
  static const IconData torchOn = Icons.flash_on_rounded;

  /// The scanner has no torch.
  static const IconData torchUnavailable = Icons.no_flash_rounded;

  /// The front and back cameras.
  static const IconData switchCamera = Icons.cameraswitch_rounded;

  /// Type the address instead of scanning.
  static const IconData typeAddress = Icons.keyboard_rounded;

  /// Scan a QR code.
  static const IconData scanQr = Icons.qr_code_scanner_rounded;

  /// The camera cannot be used.
  static const IconData cameraUnavailable = Icons.no_photography_outlined;

  /// Done, sent.
  static const IconData syncDone = Icons.check_circle_rounded;

  /// A sync failed.
  static const IconData syncFailed = Icons.error_outline_rounded;

  // ---- WebDAV (3.x web_dav_page.dart, web_dav_help.dart; docs/A-界面设计/A12-账号和数据界面/A12.5-WebDAV) ----

  /// The servers.
  static const IconData webDavServers = Remix.server_line;

  /// The current server.
  static const IconData webDavServerCurrent = Icons.cloud_done_rounded;

  /// A server.
  static const IconData webDavServer = Icons.cloud_outlined;

  /// A folder on the server.
  static const IconData webDavFolder = Icons.folder_rounded;

  /// An empty folder.
  static const IconData webDavFolderEmpty = Icons.folder_open_outlined;

  /// A backup file on the server.
  static const IconData webDavBackupFile = Remix.file_shield_2_line;

  /// Another file on the server.
  static const IconData webDavOtherFile = Icons.insert_drive_file_rounded;

  /// Upload a backup.
  static const IconData webDavUpload = Icons.cloud_upload_rounded;

  /// The usage help.
  static const IconData help = Remix.question_line;

  /// A path separator.
  static const IconData pathSeparator = Icons.navigate_next_rounded;

  /// A server's name.
  static const IconData webDavName = Remix.bookmark_line;

  /// A server's address.
  static const IconData webDavAddress = Remix.global_line;

  /// A user name.
  static const IconData userName = Remix.user_3_line;

  /// A password.
  static const IconData password = Remix.lock_password_line;

  /// Show the password.
  static const IconData showPassword = Icons.visibility_outlined;

  /// Hide the password.
  static const IconData hidePassword = Icons.visibility_off_outlined;

  /// A check passed.
  static const IconData checkPassed = Icons.check_circle_outline_rounded;

  /// A link (the help's server address).
  static const IconData link = Remix.links_line;

  /// Copy (the help's values).
  static const IconData copyValue = Remix.file_copy_line;

  /// An e-mail address (the help's account).
  static const IconData mail = Remix.mail_line;

  // ---- device sync (3.x remote_sync_page.dart; docs/A-界面设计/A12-账号和数据界面/A12.6-设备同步) ----

  /// Start the sync service.
  static const IconData syncStart = Remix.play_circle_line;

  /// Stop the sync service.
  static const IconData syncStop = Remix.stop_circle_line;

  /// The sync service runs.
  static const IconData syncRunning = Icons.check_circle_rounded;

  /// The sync service does not run.
  static const IconData syncNotRunning = Icons.error_outline_rounded;

  /// A phone.
  static const IconData devicePhone = Icons.smartphone_rounded;

  /// A computer.
  static const IconData deviceComputer = Icons.laptop_rounded;

  /// A tablet or another device.
  static const IconData deviceOther = Icons.devices_rounded;

  /// A network address.
  static const IconData lanAddress = Icons.lan_outlined;

  /// Receive the settings.
  static const IconData receive = Icons.download_rounded;

  /// Send the settings.
  static const IconData send = Icons.upload_rounded;

  /// A list item's bullet (the restore preview).
  static const IconData bullet = Icons.circle;

  // ---- the log page (3.x backup_page.dart's log group; settings → 日志管理) ----

  /// Write the log to a file.
  static const IconData logFile = Remix.file_text_line;

  /// The lowest level kept.
  static const IconData logLevel = Remix.filter_3_line;

  /// Export or share the log file.
  static const IconData exportFile = Icons.ios_share_rounded;

  /// Clear the log.
  static const IconData clearLog = Icons.delete_sweep_outlined;

  /// The title of the dialog that adds a WebDAV server.
  static const IconData webDavAddConfig = Remix.add_box_line;

  /// The title of the dialog that edits a WebDAV server.
  static const IconData webDavEditConfig = Remix.edit_box_line;

  // ---- the live room's switch-room panel (docs/A-界面设计/A07-直播间界面/A07.13-切换直播间面板) ----

  /// Show the rooms as v3's small cards (the panel's style button while it
  /// shows the list).
  static const IconData switchRoomGrid = Icons.grid_view_rounded;

  /// Show the rooms as rows (the style button while it shows the grid).
  static const IconData switchRoomList = Icons.view_list_rounded;

  /// The "正在观看" line: the room playing now.
  static const IconData switchRoomWatching = Icons.graphic_eq_rounded;

  /// The refresh failed (the refresh button turns red).
  static const IconData switchRoomRefreshFailed = Icons.error_outline_rounded;

  /// No streamer's name matches the filter.
  static const IconData switchRoomNoMatch = Icons.search_off_rounded;

  /// A group with no rooms.
  static const IconData switchRoomEmpty = Icons.live_tv_rounded;

  // ---- live_ui's shared components (docs/A-界面设计/A02-组件; A01.3: the
  // components name their icons here too) ----

  /// A settings row that opens a list of choices (⌄; a row that opens a
  /// page has [navigate]).
  static const IconData choiceRow = Icons.expand_more_rounded;

  /// The magnifier at the start of the settings' search field.
  static const IconData searchField = Icons.search_rounded;

  /// Empty the settings' search field (✕ at its end).
  static const IconData clearQuery = Icons.close_rounded;

  /// `QrCodeCard`: get a new QR code after it expired or failed.
  static const IconData qrCardRefresh = Icons.refresh_rounded;

  /// `QrCodeCard`: the code was scanned, confirm on the phone (the account
  /// pages' status line has [qrScanned]).
  static const IconData qrCardScanned = Icons.check_circle_outline_rounded;

  /// `QrCodeCard`: the code expired or could not be loaded.
  static const IconData qrCardFailed = Icons.error_outline_rounded;

  /// An avatar without a picture.
  static const IconData avatarPlaceholder = Icons.person_rounded;

  /// An error banner (an information banner has [info], a warning
  /// [warning]).
  static const IconData bannerError = Icons.error_outline_rounded;

  /// The status page while loading and when there is nothing (3.x
  /// `AppStatusView`).
  static const IconData statusEmpty = Icons.live_tv_rounded;

  /// The status page after an error (offline has [networkError], a
  /// restricted room [restricted]).
  static const IconData statusError = Icons.error_outline_rounded;
}
