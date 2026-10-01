import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/route_path.dart';

/// The five groups of the settings overview (U.6a c2; 3.x had eleven, most
/// with one row).
enum SettingsArea {
  /// Appearance and navigation.
  interface('settings_area_interface'),

  /// Platforms, refresh, IPTV.
  sources('settings_area_sources'),

  /// Video, danmaku, floating-window danmaku, player, recording.
  playback('settings_area_playback'),

  /// General, network, local interaction.
  general('settings_area_general'),

  /// Cache, backup, configuration preview.
  data('settings_area_data');

  new(this.titleKey);

  /// The group title's translation key.
  final String titleKey;
}

/// The settings pages: the rows of the overview, in its order (3.x
/// `settings_page.dart`, regrouped by U.6a). A page is either built from
/// the catalogue's rows, or another route of the app ([route]).
enum SettingsSection {
  /// Theme, colours, loading animation, cards, spacing, language, fonts
  /// (3.x "主题定制", U.6b).
  appearance(SettingsArea.interface, 'settings_appearance', 'settings_appearance_desc', AppIcons.settingsAppearance),

  /// The bottom navigation bar and the multi-view entry (U.6b).
  navigation(
    SettingsArea.interface,
    'navigation_display_settings',
    'settings_navigation_desc',
    AppIcons.settingsNavigation,
  ),

  /// Platforms, accounts, tags (U.6d).
  platforms(SettingsArea.sources, 'platform_settings', 'settings_platforms_desc', AppIcons.settingsPlatforms),

  /// Follow and cover refresh, history (U.6d).
  refresh(SettingsArea.sources, 'refresh_settings', 'refresh_settings_subtitle', AppIcons.settingsRefresh),

  /// IPTV sources (U.9).
  iptv(SettingsArea.sources, 'iptv_settings', 'manage_iptv_sources', AppIcons.settingsIptv, route: RoutePath.kIptv),

  /// Video playback (U.6c).
  video(SettingsArea.playback, 'video', 'settings_video_desc', AppIcons.settingsVideo),

  /// Danmaku (U.2e; new on the overview, U.6a c6).
  danmaku(SettingsArea.playback, 'settings_section_danmaku', 'settings_danmaku_desc', null),

  /// Danmaku of the floating windows (U.6c).
  pipDanmaku(SettingsArea.playback, 'pip_danmaku', 'settings_pip_danmaku_page_desc', AppIcons.settingsPipDanmaku),

  /// The player and decoding (U.6c).
  playerKernel(SettingsArea.playback, 'player_kernel', 'settings_player_kernel_desc', AppIcons.settingsPlayerKernel),

  /// Recording settings (U.7b; new on the overview, U.6a c6).
  recording(
    SettingsArea.playback,
    'settings_section_recording',
    'settings_recording_desc',
    AppIcons.settingsRecording,
    route: RoutePath.kRecordSettings,
  ),

  /// Refresh rate, start-up, updates, window, exit timer (U.6d).
  general(SettingsArea.general, 'general', 'settings_general_desc', AppIcons.settingsGeneral),

  /// Proxies (U.6d).
  network(SettingsArea.general, 'custom_network_proxy', 'custom_network_proxy_desc', AppIcons.settingsNetwork),

  /// Local interaction (U.2k, U.6d).
  localInteraction(
    SettingsArea.general,
    'local_interaction_title',
    'local_interaction_settings_desc',
    AppIcons.settingsLocalInteraction,
    route: RoutePath.kLocalInteraction,
  ),

  /// Cache and data (U.6e).
  cache(SettingsArea.data, 'cache_and_data', 'settings_cache_desc', AppIcons.settingsCache),

  /// Backup and restore (U.11a).
  backup(
    SettingsArea.data,
    'backup_recover',
    'settings_backup_page_desc',
    AppIcons.settingsBackup,
    route: RoutePath.kBackup,
  ),

  /// The local configuration, read only (3.x's app bar "配置预览", U.6a c5).
  configPreview(
    SettingsArea.data,
    'settings_config_preview',
    'settings_config_preview_local_desc',
    AppIcons.settingsConfigPreview,
  ),

  /// The log (U.11a Q1: moved to the settings, a row of the data group; its
  /// own page, opened like a route).
  log(SettingsArea.data, 'log_manage', 'settings_log_desc', AppIcons.settingsLog, route: RoutePath.kLogs);

  new(this.area, this.titleKey, this.descriptionKey, this.icon, {this.route});

  /// The overview group it is in.
  final SettingsArea area;

  /// The title's translation key.
  final String titleKey;

  /// The explanation's translation key.
  final String descriptionKey;

  /// The icon; null for danmaku, whose icon is 3.x's picture
  /// ([DanmakuIcon]).
  final IconData? icon;

  /// Another route of the app that is this page.
  final String? route;

  /// The section named [name] (route arguments), or null.
  static SettingsSection? byName(Object? name) => switch (name) {
    final SettingsSection section => section,
    final String text => values.asNameMap()[text],
    _ => null,
  };
}

/// A page inside a settings page (opened from one of its rows) whose rows
/// are in the catalogue too, so search finds them.
enum SettingsSubpage {
  /// The pager of computers (3.x `PageSettingsPage`).
  paging(SettingsSection.appearance, 'page_settings'),

  /// Portrait streams (3.x `PortraitLiveSettingsPage`, opened from the video
  /// page; U.6c).
  portrait(SettingsSection.video, 'portrait_live_settings'),

  /// Audience counts and ranking (3.x `AudienceMetricSettingsPage`, opened
  /// from the video page; U.6c c15).
  audience(SettingsSection.video, 'audience_metric_settings');

  new(this.section, this.titleKey);

  /// The page it opens from.
  final SettingsSection section;

  /// Its title's translation key.
  final String titleKey;
}

/// What the page knows about where it runs: rows only for one platform
/// (Android's background play, Windows' window size, the pager of
/// computers) are left out elsewhere.
@immutable
final class SettingsEnv {
  /// Creates the environment.
  const new({required this.platform, this.fastDisplay = false});

  /// The environment of this device: [defaultTargetPlatform] and whether a
  /// display refreshes faster than 60 Hz.
  factory current() => SettingsEnv(
    platform: defaultTargetPlatform,
    fastDisplay: WidgetsBinding.instance.platformDispatcher.displays.any((display) => display.refreshRate > 61),
  );

  /// The operating system.
  final TargetPlatform platform;

  /// A display above 60 Hz (an iPhone or iPad with ProMotion).
  final bool fastDisplay;

  /// Android.
  bool get isAndroid => platform == TargetPlatform.android;

  /// iOS.
  bool get isIOS => platform == TargetPlatform.iOS;

  /// Windows.
  bool get isWindows => platform == TargetPlatform.windows;

  /// A phone or tablet OS.
  bool get isMobile => platform == TargetPlatform.android || platform == TargetPlatform.iOS;

  /// Linux or macOS.
  bool get isOtherDesktop => platform == TargetPlatform.linux || platform == TargetPlatform.macOS;

  /// Android or Windows (the display-mode channel exists there), and iPhones
  /// and iPads with ProMotion (U.17a).
  bool get hasRefreshRate => isAndroid || isWindows || (isIOS && fastDisplay);
}

bool _always(SettingsEnv env) => true;

/// One row of the settings: where it lives, how it is found by search and
/// how it is drawn.
@immutable
final class SettingsEntry {
  /// Creates an entry.
  const new({
    required this.id,
    required this.section,
    required this.group,
    required this.title,
    required this.build,
    this.subpage,
    this.description,
    this.keywords = const [],
    this.settings = const [],
    this.when = _always,
    this.opens = false,
  });

  /// Unique id; the row's key is `settings-entry-<id>`.
  final String id;

  /// The page it is on.
  final SettingsSection section;

  /// The sub-page of [section] it is on, or null.
  final SettingsSubpage? subpage;

  /// The translation key of its group title.
  final String group;

  /// The title's translation key.
  final String title;

  /// The explanation's translation key.
  final String? description;

  /// More words that find it (both languages, as written).
  final List<String> keywords;

  /// The stored settings it changes.
  final List<Setting<Object>> settings;

  /// Whether it applies to [SettingsEnv].
  final bool Function(SettingsEnv env) when;

  /// Whether a tap opens another page (in search results such a row goes to
  /// its page instead, U.6a c8).
  final bool opens;

  /// Draws the row.
  final Widget Function(BuildContext context, SettingsEntry entry) build;

  /// The key of the drawn row.
  ValueKey<String> get rowKey => ValueKey('settings-entry-$id');

  /// The translated title.
  String get titleText => i18n(title);

  /// The translated explanation, or null.
  String? get descriptionText => switch (description) {
    final key? => i18n(key),
    null => null,
  };

  /// "页面 › 分组" of a search result.
  String get crumb => '${i18n(subpage?.titleKey ?? section.titleKey)} › ${i18n(group)}';

  /// Whether [query] (lower case, trimmed, not empty) finds this entry.
  bool matches(String query) {
    final words = [titleText, ?descriptionText, ...keywords, i18n(group), i18n(section.titleKey)];
    return words.any((word) => word.toLowerCase().contains(query));
  }
}

/// The lower-case words of [query].
List<String> searchWords(String query) =>
    query.toLowerCase().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();

/// The entries found by [query] in [entries], in catalogue order; nothing
/// for a blank query. Every word of the query must match (so "弹幕 速度"
/// finds the danmaku speed).
List<SettingsEntry> searchSettings(Iterable<SettingsEntry> entries, String query) {
  final words = searchWords(query);
  if (words.isEmpty) return const [];
  return [
    for (final entry in entries)
      if (words.every(entry.matches)) entry,
  ];
}

/// The entries of [section] (or of its [subpage]) that apply to [env],
/// grouped by their group title in catalogue order.
List<(String group, List<SettingsEntry> entries)> groupsOf(
  Iterable<SettingsEntry> entries,
  SettingsSection section,
  SettingsEnv env, {
  SettingsSubpage? subpage,
}) {
  final groups = <String, List<SettingsEntry>>{};
  for (final entry in entries) {
    if (entry.section != section || entry.subpage != subpage || !entry.when(env)) continue;
    groups.putIfAbsent(entry.group, () => []).add(entry);
  }
  return [for (final MapEntry(:key, :value) in groups.entries) (key, value)];
}
