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

  // ---- IPTV settings (docs/ui/compare/U.9; 3.x iptv_page.dart, iptv_manage.dart) ----

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
  static const IconData guide = Remix.tv_2_line;

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

  /// More actions of a card (⋮).
  static const IconData more = Icons.more_vert_rounded;

  /// Sync one source.
  static const IconData syncOne = Remix.download_cloud_2_line;

  /// Delete a source.
  static const IconData delete = Remix.delete_bin_6_line;

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

  /// A hint or a notice (ⓘ).
  static const IconData info = Remix.information_line;

  /// Try again.
  static const IconData retry = Remix.refresh_line;

  /// A row that opens another page (›).
  static const IconData navigate = Icons.chevron_right_rounded;

  // ---- platform accounts and cookies (docs/ui/compare/U.10a, U.10b; 3.x modules/account) ----

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

  // ---- the retired cloud account (docs/ui/compare/U.10c) ----

  /// The cloud account is gone.
  static const IconData cloudOff = Remix.cloud_off_line;

  /// WebDAV backups (3.x backup page).
  static const IconData webDav = Remix.cloud_line;

  /// Device sync over the local network (3.x backup page).
  static const IconData deviceSync = Remix.qr_scan_2_line;

  /// Backup files.
  static const IconData backupFiles = Remix.save_3_line;

  /// The platform accounts (3.x settings "三方认证").
  static const IconData platformAccounts = Remix.accessibility_line;
}
