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

  /// Add something (a new tag).
  static const IconData add = Remix.add_line;

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

  /// Go to the login page (U.4e c6).
  static const IconData login = Icons.login_rounded;

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

  /// Search.
  static const IconData search = Icons.search_rounded;

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
}
