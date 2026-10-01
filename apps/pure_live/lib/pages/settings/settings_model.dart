import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/i18n/i18n.dart';

/// The groups of the settings, in the order a user looks for them (3.x had
/// eleven groups of one or two links each, in the order they were added).
enum SettingsSection {
  /// Theme, language, text, cards.
  appearance('settings_section_appearance', 'settings_section_appearance_desc', Remix.palette_line),

  /// Quality, sound, decoding, picture-in-picture.
  playback('settings_section_playback', 'settings_section_playback_desc', Remix.play_circle_line),

  /// Danmaku look and filters.
  danmaku('settings_section_danmaku', 'settings_section_danmaku_desc', Remix.chat_smile_2_line),

  /// Platform list, accounts, tags, discovery.
  platforms('settings_section_platforms', 'settings_section_platforms_desc', Remix.apps_2_line),

  /// Follow refresh and history.
  follows('settings_section_follows', 'settings_section_follows_desc', Remix.heart_3_line),

  /// Proxies.
  network('settings_section_network', 'settings_section_network_desc', Remix.global_line),

  /// Recording.
  recording('settings_section_recording', 'settings_section_recording_desc', Remix.record_circle_line),

  /// Start-up, home menu, window, timer.
  general('settings_section_general', 'settings_section_general_desc', Remix.settings_4_line),

  /// Backup, cache, reset.
  data('settings_section_data', 'settings_section_data_desc', Remix.database_2_line),

  /// About and updates.
  about('settings_section_about', 'settings_section_about_desc', Remix.information_line);

  new(this.titleKey, this.descriptionKey, this.icon);

  /// The title's translation key.
  final String titleKey;

  /// The one-line summary's translation key.
  final String descriptionKey;

  /// The icon.
  final IconData icon;
}

/// What the page knows about where it runs: entries only for one platform
/// (Android's background play, Windows' window size) or one width (paging
/// controls exist on wide screens only, as in 3.x) are left out elsewhere.
@immutable
final class SettingsEnv {
  /// Creates the environment.
  const new({required this.platform, required this.wide});

  /// The operating system.
  final TargetPlatform platform;

  /// Wider than 680 logical pixels (3.x `Get.width > 680`).
  final bool wide;

  /// Android.
  bool get isAndroid => platform == TargetPlatform.android;

  /// Windows.
  bool get isWindows => platform == TargetPlatform.windows;

  /// A phone or tablet OS.
  bool get isMobile => platform == TargetPlatform.android || platform == TargetPlatform.iOS;

  /// Android or Windows (the display-mode channel exists there).
  bool get hasRefreshRate => isAndroid || isWindows;
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
    this.description,
    this.keywords = const [],
    this.settings = const [],
    this.when = _always,
  });

  /// Unique id; the row's key is `settings-entry-<id>`.
  final String id;

  /// The section it is in.
  final SettingsSection section;

  /// The translation key of its group title inside the section.
  final String group;

  /// The title's translation key.
  final String title;

  /// The one-line explanation's translation key.
  final String? description;

  /// More words that find it (both languages, as written).
  final List<String> keywords;

  /// The stored settings it changes ("restore this section's defaults").
  final List<Setting<Object>> settings;

  /// Whether it applies to [SettingsEnv].
  final bool Function(SettingsEnv env) when;

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

  /// Whether [query] (lower case, trimmed, not empty) finds this entry.
  bool matches(String query) {
    final words = [titleText, ?descriptionText, ...keywords, i18n(group), i18n(section.titleKey)];
    return words.any((word) => word.toLowerCase().contains(query));
  }
}

/// The entries found by [query] in [entries], in catalogue order; nothing
/// for a blank query. Every word of the query must match (so "弹幕 速度"
/// finds the danmaku speed).
List<SettingsEntry> searchSettings(Iterable<SettingsEntry> entries, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  return [
    for (final entry in entries)
      if (words.every(entry.matches)) entry,
  ];
}

/// The entries of [section] that apply to [env], grouped by their group
/// title in catalogue order.
List<(String group, List<SettingsEntry> entries)> groupsOf(
  Iterable<SettingsEntry> entries,
  SettingsSection section,
  SettingsEnv env,
) {
  final groups = <String, List<SettingsEntry>>{};
  for (final entry in entries) {
    if (entry.section != section || !entry.when(env)) continue;
    groups.putIfAbsent(entry.group, () => []).add(entry);
  }
  return [for (final MapEntry(:key, :value) in groups.entries) (key, value)];
}

/// Settings changed from their defaults among [entries] (the badge of a
/// section and its "restore defaults" action).
List<Setting<Object>> changedSettings(SettingsStore store, Iterable<SettingsEntry> entries) {
  final seen = <String>{};
  return [
    for (final entry in entries)
      for (final setting in entry.settings)
        if (seen.add(setting.key) && store.isSet(setting) && !_sameValue(store.get(setting), setting.defaultValue))
          setting,
  ];
}

bool _sameValue(Object a, Object b) => switch ((a, b)) {
  (final List<Object?> x, final List<Object?> y) => listEquals(x, y),
  (final Map<Object?, Object?> x, final Map<Object?, Object?> y) => mapEquals(x, y),
  _ => a == b,
};
