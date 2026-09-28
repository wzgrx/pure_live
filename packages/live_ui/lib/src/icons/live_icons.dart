import 'package:flutter/widgets.dart';
import 'package:live_ui/src/icons/drawn_glyphs.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Every icon of Pure Live by meaning (principles §2.6), shown with
/// `LiveIcon`. Each is a glyph of the Material Symbols Rounded variable font
/// or, where Symbols has none, a glyph live_ui draws on the same 24 dp grid
/// ([LiveIcons.danmaku]). The table in live_ui's README lists them all.
///
/// A toggle keeps its glyph and shows its state by fill alone: pass
/// `filled: true` to `LiveIcon` when it is on, selected, followed or muted.
/// The app never names a font glyph itself (`Icons.*`, `Symbols.*`); a
/// test in the app enforces that.
enum LiveIcons {
  // Navigation.

  /// 关注 tab; filled when current. Symbols `favorite`.
  follows.symbol(Symbols.favorite_rounded),

  /// 发现 tab. Symbols `explore`.
  discover.symbol(Symbols.explore_rounded),

  /// 搜索 tab and search fields; its fill is a plain magnifier. Symbols `search`.
  search.symbol(Symbols.search_rounded),

  /// 我的 tab. Symbols `person`.
  me.symbol(Symbols.person_rounded),

  /// Expands the navigation rail. Symbols `menu`.
  railExpand.symbol(Symbols.menu_rounded),

  /// Collapses the navigation rail. Symbols `menu_open`.
  railCollapse.symbol(Symbols.menu_open_rounded),

  /// Back. Symbols `arrow_back`.
  back.symbol(Symbols.arrow_back_rounded),

  /// Close, cancel, remove an entry. Symbols `close`.
  close.symbol(Symbols.close_rounded),

  /// More actions. Symbols `more_vert`.
  more.symbol(Symbols.more_vert_rounded),

  /// A row that opens a page. Symbols `chevron_right`.
  subpage.symbol(Symbols.chevron_right_rounded),

  /// Shows more rows. Symbols `expand_more`.
  expand.symbol(Symbols.expand_more_rounded),

  /// Shows fewer rows. Symbols `expand_less`.
  collapse.symbol(Symbols.expand_less_rounded),

  // Common actions.

  /// Add. Symbols `add`.
  add.symbol(Symbols.add_rounded),

  /// An empty place to add something (a multi-view cell, a guide source).
  /// Symbols `add_circle`.
  addEntry.symbol(Symbols.add_circle_rounded),

  /// Edit. Symbols `edit`.
  edit.symbol(Symbols.edit_rounded),

  /// Delete. Symbols `delete`.
  delete.symbol(Symbols.delete_rounded),

  /// Clear a whole list. Symbols `delete_sweep`.
  clearAll.symbol(Symbols.delete_sweep_rounded),

  /// The chosen entry of a list. Symbols `check`.
  check.symbol(Symbols.check_rounded),

  /// Refresh. Symbols `refresh`.
  refresh.symbol(Symbols.refresh_rounded),

  /// Try again, watch back a programme. Symbols `replay`.
  replay.symbol(Symbols.replay_rounded),

  /// Restore a backup, reset to the default. Symbols `restore`.
  restore.symbol(Symbols.restore_rounded),

  /// Sort. Symbols `sort`.
  sort.symbol(Symbols.sort_rounded),

  /// Select everything shown. Symbols `select_all`.
  selectAll.symbol(Symbols.select_all_rounded),

  /// Start multi-select. Symbols `checklist`.
  multiSelect.symbol(Symbols.checklist_rounded),

  /// Drag to reorder. Symbols `drag_handle`.
  reorder.symbol(Symbols.drag_handle_rounded),

  /// Copy. Symbols `content_copy`.
  copy.symbol(Symbols.content_copy_rounded),

  /// Paste. Symbols `content_paste`.
  paste.symbol(Symbols.content_paste_rounded),

  /// Share. Symbols `share`.
  share.symbol(Symbols.share_rounded),

  /// A link. Symbols `link`.
  link.symbol(Symbols.link_rounded),

  /// A link that cannot be used. Symbols `link_off`.
  linkOff.symbol(Symbols.link_off_rounded),

  /// Open the platform's site. Symbols `open_in_new`.
  openSite.symbol(Symbols.open_in_new_rounded),

  /// Open in the platform's app. Symbols `open_in_phone`.
  openInApp.symbol(Symbols.open_in_phone_rounded),

  /// Open in a new window. Symbols `open_in_browser`.
  newWindow.symbol(Symbols.open_in_browser_rounded),

  /// Download, export. Symbols `download`.
  download.symbol(Symbols.download_rounded),

  /// Import a file. Symbols `upload_file`.
  importFile.symbol(Symbols.upload_file_rounded),

  /// Upload to a server. Symbols `cloud_upload`.
  upload.symbol(Symbols.cloud_upload_rounded),

  /// Send. Symbols `send`.
  send.symbol(Symbols.send_rounded),

  /// Receive from another device. Symbols `download_for_offline`.
  receive.symbol(Symbols.download_for_offline_rounded),

  /// The folder above. Symbols `arrow_upward`.
  parentFolder.symbol(Symbols.arrow_upward_rounded),

  /// A folder, a follows group. Symbols `folder`.
  folder.symbol(Symbols.folder_rounded),

  /// Pick a folder. Symbols `folder_open`.
  folderOpen.symbol(Symbols.folder_open_rounded),

  /// A file. Symbols `description`.
  file.symbol(Symbols.description_rounded),

  /// Nothing here. Symbols `inbox`.
  inbox.symbol(Symbols.inbox_rounded),

  /// History. Symbols `history`.
  history.symbol(Symbols.history_rounded),

  /// Nothing found. Symbols `search_off`.
  noResults.symbol(Symbols.search_off_rounded),

  /// Search the web. Symbols `travel_explore`.
  webSearch.symbol(Symbols.travel_explore_rounded),

  /// A web page, a web login. Symbols `public`.
  web.symbol(Symbols.public_rounded),

  /// Web pages cannot be shown here. Symbols `public_off`.
  webUnavailable.symbol(Symbols.public_off_rounded),

  /// Voice input. Symbols `mic`.
  voice.symbol(Symbols.mic_rounded),

  /// Show the password; filled while it shows. Symbols `visibility`.
  showPassword.symbol(Symbols.visibility_rounded),

  /// A key or password. Symbols `vpn_key`.
  key.symbol(Symbols.vpn_key_rounded),

  /// A QR code. Symbols `qr_code_2`.
  qrCode.symbol(Symbols.qr_code_2_rounded),

  /// Help. Symbols `help`.
  help.symbol(Symbols.help_rounded),

  /// Information, 关于. Symbols `info`.
  info.symbol(Symbols.info_rounded),

  /// A tip. Symbols `lightbulb`.
  tip.symbol(Symbols.lightbulb_rounded),

  /// An error; filled on a status list. Symbols `error`.
  error.symbol(Symbols.error_rounded),

  /// A warning. Symbols `warning`.
  warning.symbol(Symbols.warning_rounded),

  /// Done, working; filled on a status list and for the chosen device.
  /// Symbols `check_circle`.
  success.symbol(Symbols.check_circle_rounded),

  /// Block a keyword. Symbols `block`.
  block.symbol(Symbols.block_rounded),

  /// Block a user. Symbols `person_off`.
  blockUser.symbol(Symbols.person_off_rounded),

  /// Save the danmaku settings as a preset. Symbols `bookmark_add`.
  savePreset.symbol(Symbols.bookmark_add_rounded),

  /// Danmaku presets. Symbols `bookmark`.
  presets.symbol(Symbols.bookmark_rounded),

  // Rooms and follows.

  /// Follow; filled when followed. Symbols `favorite`.
  follow.symbol(Symbols.favorite_rounded),

  /// Unfollow. Symbols `heart_broken`.
  unfollow.symbol(Symbols.heart_broken_rounded),

  /// Star an area, the default platform; filled when starred. Symbols `star`.
  star.symbol(Symbols.star_rounded),

  /// The audience of a room. Symbols `person`.
  audience.symbol(Symbols.person_rounded),

  /// 多画面, its layouts. Symbols `grid_view`.
  multiview.symbol(Symbols.grid_view_rounded),

  /// A list of rooms. Symbols `format_list_bulleted`.
  roomList.symbol(Symbols.format_list_bulleted_rounded),

  /// A gift in the chat. Symbols `card_giftcard`.
  gift.symbol(Symbols.card_giftcard_rounded),

  /// Jump to the newest chat. Symbols `arrow_downward`.
  scrollToLatest.symbol(Symbols.arrow_downward_rounded),

  // Playback and the controls on the picture.

  /// Play. Symbols `play_arrow`.
  play.symbol(Symbols.play_arrow_rounded),

  /// Pause. Symbols `pause`.
  pause.symbol(Symbols.pause_rounded),

  /// A paused picture. Symbols `pause_circle`.
  paused.symbol(Symbols.pause_circle_rounded),

  /// Stop. Symbols `stop`.
  stop.symbol(Symbols.stop_rounded),

  /// 弹幕 on or off: filled when on. Drawn by live_ui ([danmakuGlyph]):
  /// Symbols has no danmaku glyph, and `subtitles` means captions.
  danmaku.drawn(danmakuGlyph),

  /// Danmaku settings, the 通用 settings. Symbols `tune`.
  tune.symbol(Symbols.tune_rounded),

  /// Quality and line. Symbols `high_quality`.
  quality.symbol(Symbols.high_quality_rounded),

  /// Line (CDN). Symbols `alt_route`.
  line.symbol(Symbols.alt_route_rounded),

  /// Volume. Symbols `volume_up`.
  volume.symbol(Symbols.volume_up_rounded),

  /// The low end of a volume slider. Symbols `volume_down`.
  volumeDown.symbol(Symbols.volume_down_rounded),

  /// Mute; filled while muted. Symbols `volume_off`.
  mute.symbol(Symbols.volume_off_rounded),

  /// Enter fullscreen. Symbols `fullscreen`.
  fullscreen.symbol(Symbols.fullscreen_rounded),

  /// Leave fullscreen. Symbols `fullscreen_exit`.
  fullscreenExit.symbol(Symbols.fullscreen_exit_rounded),

  /// Show larger (immersive multi-view, the room from the mini player).
  /// Symbols `open_in_full`.
  expandView.symbol(Symbols.open_in_full_rounded),

  /// Show smaller (leave immersive multi-view or picture-in-picture).
  /// Symbols `close_fullscreen`.
  collapseView.symbol(Symbols.close_fullscreen_rounded),

  /// Picture-in-picture. Symbols `picture_in_picture_alt`.
  pip.symbol(Symbols.picture_in_picture_alt_rounded),

  /// Cast. Symbols `cast`.
  cast.symbol(Symbols.cast_rounded),

  /// Casting to a device. Symbols `cast_connected`.
  casting.symbol(Symbols.cast_connected_rounded),

  /// Audio only; filled when on. Symbols `headphones`.
  audioOnly.symbol(Symbols.headphones_rounded),

  /// The chat over the fullscreen picture; filled when shown. Symbols
  /// `chat_bubble`.
  chat.symbol(Symbols.chat_bubble_rounded),

  /// The chat panel beside the picture; filled when shown. Symbols
  /// `view_sidebar`.
  chatPanel.symbol(Symbols.view_sidebar_rounded),

  /// Theatre mode; filled when on. Symbols `crop_7_5`.
  theater.symbol(Symbols.crop_7_5_rounded),

  /// Lock the controls; filled while locked. Symbols `lock`.
  lock.symbol(Symbols.lock_rounded),

  /// Switch to another room. Symbols `swap_horiz`.
  switchRoom.symbol(Symbols.swap_horiz_rounded),

  /// Switched to the room above or below. Symbols `swap_vert`.
  roomStep.symbol(Symbols.swap_vert_rounded),

  /// Swipe up or down to switch rooms. Symbols `swipe_vertical`.
  swipeRooms.symbol(Symbols.swipe_vertical_rounded),

  /// The first room of the list. Symbols `vertical_align_top`.
  firstRoom.symbol(Symbols.vertical_align_top_rounded),

  /// The last room of the list. Symbols `vertical_align_bottom`.
  lastRoom.symbol(Symbols.vertical_align_bottom_rounded),

  /// Aspect ratio. Symbols `aspect_ratio`.
  aspect.symbol(Symbols.aspect_ratio_rounded),

  /// Orientation. Symbols `screen_rotation_alt`.
  orientation.symbol(Symbols.screen_rotation_alt_rounded),

  /// Turn to landscape. Symbols `screen_rotation`.
  rotate.symbol(Symbols.screen_rotation_rounded),

  /// Show the whole picture. Symbols `fit_screen`.
  fitPicture.symbol(Symbols.fit_screen_rounded),

  /// Fill the screen with the picture. Symbols `crop_portrait`.
  fillScreen.symbol(Symbols.crop_portrait_rounded),

  /// Brightness. Symbols `brightness_medium`.
  brightness.symbol(Symbols.brightness_medium_rounded),

  /// Sleep timer. Symbols `bedtime`.
  sleepTimer.symbol(Symbols.bedtime_rounded),

  /// Quit the app. Symbols `exit_to_app`.
  quit.symbol(Symbols.exit_to_app_rounded),

  /// Screenshot. Symbols `photo_camera`.
  screenshot.symbol(Symbols.photo_camera_rounded),

  /// Keyboard shortcuts. Symbols `keyboard`.
  shortcuts.symbol(Symbols.keyboard_rounded),

  /// A full battery. Symbols `battery_full`.
  batteryFull.symbol(Symbols.battery_full_rounded),

  /// A battery above 60%. Symbols `battery_5_bar`.
  batteryHigh.symbol(Symbols.battery_5_bar_rounded),

  /// A battery above 35%. Symbols `battery_3_bar`.
  batteryHalf.symbol(Symbols.battery_3_bar_rounded),

  /// A battery above 15%. Symbols `battery_2_bar`.
  batteryLow.symbol(Symbols.battery_2_bar_rounded),

  /// An almost empty battery. Symbols `battery_alert`.
  batteryAlert.symbol(Symbols.battery_alert_rounded),

  /// A charging battery. Symbols `battery_charging_full`.
  batteryCharging.symbol(Symbols.battery_charging_full_rounded),

  /// A screen that shows nothing (the room is offline, no device found).
  /// Symbols `tv_off`.
  noPicture.symbol(Symbols.tv_off_rounded),

  /// No network. Symbols `wifi_off`.
  offline.symbol(Symbols.wifi_off_rounded),

  // Recording.

  /// Record; filled while recording or booked. Symbols `fiber_manual_record`.
  record.symbol(Symbols.fiber_manual_record_rounded),

  /// Waits for the room to go live; a time. Symbols `schedule`.
  schedule.symbol(Symbols.schedule_rounded),

  /// Stop a task. Symbols `stop_circle`.
  stopTask.symbol(Symbols.stop_circle_rounded),

  /// The recording center. Symbols `video_library`.
  recordingCenter.symbol(Symbols.video_library_rounded),

  // IPTV.

  /// IPTV, a channel on air. Symbols `live_tv`.
  liveTv.symbol(Symbols.live_tv_rounded),

  /// The programme guide. Symbols `event_note`.
  guide.symbol(Symbols.event_note_rounded),

  /// No programmes. Symbols `event_busy`.
  noProgrammes.symbol(Symbols.event_busy_rounded),

  /// Add a playlist. Symbols `playlist_add`.
  addPlaylist.symbol(Symbols.playlist_add_rounded),

  /// Synchronise. Symbols `sync`.
  sync.symbol(Symbols.sync_rounded),

  // Settings, data and about.

  /// Settings. Symbols `settings`.
  settings.symbol(Symbols.settings_rounded),

  /// 外观. Symbols `palette`.
  appearance.symbol(Symbols.palette_rounded),

  /// 播放. Symbols `play_circle`.
  playback.symbol(Symbols.play_circle_rounded),

  /// 账号. Symbols `account_circle`.
  accounts.symbol(Symbols.account_circle_rounded),

  /// 网络. Symbols `lan`.
  network.symbol(Symbols.lan_rounded),

  /// 数据与同步. Symbols `cloud_sync`.
  data.symbol(Symbols.cloud_sync_rounded),

  /// TV mode. Symbols `tv`.
  tvMode.symbol(Symbols.tv_rounded),

  /// Live alerts; filled when on. Symbols `notifications`.
  alerts.symbol(Symbols.notifications_rounded),

  /// Back up. Symbols `save`.
  backup.symbol(Symbols.save_rounded),

  /// WebDAV. Symbols `cloud`.
  webdav.symbol(Symbols.cloud_rounded),

  /// No WebDAV account. Symbols `cloud_off`.
  noWebdav.symbol(Symbols.cloud_off_rounded),

  /// Test a connection. Symbols `wifi_tethering`.
  testConnection.symbol(Symbols.wifi_tethering_rounded),

  /// LAN sync, other devices. Symbols `devices_other`.
  lanSync.symbol(Symbols.devices_other_rounded),

  /// Diagnostics. Symbols `medical_information`.
  diagnostics.symbol(Symbols.medical_information_rounded),

  /// Debug logging. Symbols `bug_report`.
  debugLog.symbol(Symbols.bug_report_rounded),

  /// Platform status. Symbols `monitor_heart`.
  platformStatus.symbol(Symbols.monitor_heart_rounded),

  /// Clear the cache. Symbols `cleaning_services`.
  clearCache.symbol(Symbols.cleaning_services_rounded),

  /// Source code. Symbols `code`.
  sourceCode.symbol(Symbols.code_rounded),

  /// Feedback. Symbols `feedback`.
  feedback.symbol(Symbols.feedback_rounded),

  /// Changelog. Symbols `history_edu`.
  changelog.symbol(Symbols.history_edu_rounded),

  /// Licences. Symbols `gavel`.
  licenses.symbol(Symbols.gavel_rounded),

  /// Check for updates. Symbols `system_update`.
  update.symbol(Symbols.system_update_rounded),

  /// A new release. Symbols `new_releases`.
  newRelease.symbol(Symbols.new_releases_rounded),

  /// Verify a download. Symbols `verified`.
  verified.symbol(Symbols.verified_rounded);

  /// A glyph of Material Symbols Rounded.
  new symbol(IconData this.glyph) : outline = null;

  /// A glyph live_ui draws.
  new drawn(GlyphBuilder this.outline) : glyph = null;

  /// The Material Symbols Rounded glyph, or null for a drawn one.
  final IconData? glyph;

  /// The outline of a drawn glyph, or null for a font glyph.
  final GlyphBuilder? outline;
}
