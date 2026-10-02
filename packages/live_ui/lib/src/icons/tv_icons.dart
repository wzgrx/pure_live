import 'package:flutter/material.dart';
import 'package:remixicon/remixicon.dart';

/// The icons of the TV interface by what they are for (docs/T18/T18a/T18a.2),
/// in the same spirit as `AppIcons`: TV pages name the use, never the glyph.
/// Uses the phone has too (refresh, close, lock, the audience kinds) come
/// from `AppIcons`; these are the TV shell's own and the shared components
/// the TV draws first (the card dialog, the status page, the tag dialog).
abstract final class TvIcons {
  // ---- the side menu (pure_live_TV `TvMenuType`; the glyphs of M14.1, U.15b
  // redraws the menu) ----

  /// Follows.
  static const IconData menuFavorites = Icons.favorite_rounded;

  /// Recommended rooms.
  static const IconData menuPopular = Icons.local_fire_department_rounded;

  /// Areas.
  static const IconData menuAreas = Icons.grid_view_rounded;

  /// Watch history.
  static const IconData menuHistory = Icons.history_rounded;

  /// Search.
  static const IconData menuSearch = Icons.search_rounded;

  /// Network TV.
  static const IconData menuIptv = Icons.live_tv_rounded;

  /// Videos.
  static const IconData menuVideo = Icons.movie_rounded;

  /// Music.
  static const IconData menuMusic = Icons.library_music_rounded;

  /// Wallpapers.
  static const IconData menuWallpaper = Icons.wallpaper_rounded;

  /// Settings.
  static const IconData menuSettings = Icons.settings_rounded;

  /// A part of the TV interface that is not built yet.
  static const IconData underConstruction = Icons.construction_rounded;

  // ---- cards and covers (U.15a c6–c9, the phone's U.4a) ----

  /// The cover of a room or area whose picture is loading or failed (one
  /// placeholder for both, U.15a c8; never the "offline" Wi-Fi glyph).
  static const IconData coverPlaceholder = Icons.live_tv_rounded;

  /// A followed room or area on its cover.
  static const IconData followedMark = Icons.favorite_rounded;

  /// The "录播" chip of a replay (3.x `Icons.videocam_rounded`).
  static const IconData replay = Icons.videocam_rounded;

  /// "All platforms" in a platform tab row (pure_live_TV `Icons.apps_rounded`).
  static const IconData allPlatforms = Icons.apps_rounded;

  /// Set a room's tags (3.x `Remix.price_tag_3_line`).
  static const IconData tags = Remix.price_tag_3_line;

  /// Delete one entry (3.x `RemixIcons.delete_bin_line`).
  static const IconData delete = Remix.delete_bin_line;

  /// Clear a whole list (history, recent searches).
  static const IconData clearAll = Icons.delete_sweep_rounded;

  /// A tag that is ticked in a multiple choice.
  static const IconData ticked = Icons.check_rounded;

  /// A follow-the-area heart, not followed.
  static const IconData followArea = Icons.favorite_border_rounded;

  /// A follow-the-area heart, followed.
  static const IconData followedArea = Icons.favorite_rounded;

  // ---- states of a page (U.15a c14) ----

  /// The list could not be loaded (network, platform).
  static const IconData loadFailed = Icons.wifi_off_rounded;

  /// The platform hides its rooms until the user signs in.
  static const IconData needsLogin = Icons.account_circle_outlined;

  /// No rooms on a platform (the popular page's flame).
  static const IconData noRooms = Icons.local_fire_department_rounded;

  /// No follows yet.
  static const IconData noFollows = Icons.favorite_border_rounded;

  /// No areas.
  static const IconData noAreas = Icons.grid_view_rounded;

  /// No watch history.
  static const IconData noHistory = Icons.history_rounded;

  /// Nothing found.
  static const IconData noResults = Icons.search_off_rounded;

  /// Search before the first word.
  static const IconData searchIntro = Icons.manage_search_rounded;

  /// No playlists yet (network TV).
  static const IconData noPlaylists = Icons.playlist_add_rounded;

  /// No platforms switched on.
  static const IconData noPlatforms = Icons.apps_rounded;

  // ---- settings rows and fields ----

  /// A row that opens a page (›).
  static const IconData chevron = Icons.chevron_right_rounded;

  /// A row whose value opens a choice (▾).
  static const IconData choice = Icons.arrow_drop_down_rounded;

  /// The search field.
  static const IconData search = Icons.search_rounded;

  /// A recent search word.
  static const IconData recentWord = Icons.history_rounded;

  /// Manage the network TV playlists.
  static const IconData manage = Icons.tune_rounded;

  /// The interface mode (phone or TV).
  static const IconData uiMode = Icons.tv_rounded;

  /// The theme colour.
  static const IconData themeColor = Icons.palette_rounded;

  /// The text size.
  static const IconData textSize = Icons.format_size_rounded;

  /// The preferred quality.
  static const IconData quality = Icons.high_quality_rounded;

  /// Danmaku on the picture, on.
  static const IconData danmakuOn = Icons.subtitles_rounded;

  /// Danmaku on the picture, off.
  static const IconData danmakuOff = Icons.subtitles_off_rounded;

  /// The danmaku size.
  static const IconData danmakuSize = Icons.text_fields_rounded;

  /// The danmaku opacity.
  static const IconData danmakuOpacity = Icons.opacity_rounded;

  /// Network and proxy.
  static const IconData network = Icons.public_rounded;

  /// More settings (the full settings page).
  static const IconData moreSettings = Icons.settings_suggest_rounded;

  /// Grow the focused item (the low-end-box switch, U.15a c2).
  static const IconData focusZoom = Icons.zoom_in_rounded;

  // ---- the TV room (U.15d redraws it) ----

  /// A room off air.
  static const IconData offAir = Icons.nightlight_round;

  /// The room list beside the picture.
  static const IconData roomList = Icons.format_list_bulleted_rounded;
}
