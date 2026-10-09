// Z05.1: the translation keys the app builds at run time, and the keys kept
// although nothing asks for them (D-016, D-024).
import 'dart:collection';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:pure_live/app/app_log.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
import 'package:pure_live/features/live_play/logic/room_layout.dart';
import 'package:pure_live/features/search/search_capability.dart';
import 'package:pure_live/features/settings/settings_catalog.dart';
import 'package:pure_live/features/settings/settings_editors.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

/// One way the app builds keys: `template` is the string literal in `lib/`
/// with `*` for each interpolation, `keys` are all the keys it can build
/// (expanded from the same enums and tables the code uses) and `optional`
/// says the code has a fallback when a key is missing (`i18nOr`,
/// `i18nExists`), so only keys present in one file must be in the other.
typedef RuntimeKeyRule = ({String template, Iterable<String> keys, bool optional});

/// Platforms a stored room can name: today's and those retired in 3.2.8,
/// whose follows and history from 3.x backups stay readable.
List<String> get _platforms => [...SiteIds.supported, ...SiteIds.retired];

/// The five text sizes of `FontSizesPage` (a private table; read from its
/// source so the list follows the code).
List<String> get _fontSizes => [
  for (final match in RegExp(
    r"\(\s*'(font_[a-z_]+)',\s*Settings\.",
  ).allMatches(File('lib/features/settings/appearance_pages.dart').readAsStringSync()))
    match.group(1)!,
];

/// Every interpolated key literal in `lib/`, with what it can build.
List<RuntimeKeyRule> runtimeKeyRules() {
  final notes = {for (final id in SiteIds.supported) ?SearchCapabilities.of(id).noteKey};
  final ownPacks = {
    for (final pack in LocalCatalog.packs)
      if (pack.currencyKey != LocalCatalog.genericPack.currencyKey)
        pack.currencyKey.substring('local_currency_'.length),
  };
  return [
    // features/backup/log_page.dart
    (
      template: 'settings_log_level_*',
      keys: [for (final level in LogLevel.values) 'settings_log_level_${level.name}'],
      optional: false,
    ),
    // features/settings/audience_pages.dart
    (
      template: 'audience_*_detail',
      keys: [for (final id in SiteIds.supported) 'audience_${id}_detail'],
      optional: true,
    ),
    // features/popular/popular_grid.dart (else the adapter's directoryNoticeKey)
    (template: 'popular_scope_*', keys: [for (final id in SiteIds.supported) 'popular_scope_$id'], optional: true),
    // features/settings/settings_editors.dart
    (
      template: 'settings_twitch_language_*',
      keys: [for (final code in TwitchLanguagesTile.languages) 'settings_twitch_language_$code'],
      optional: false,
    ),
    (
      template: 'settings_refresh_rate_short_*',
      keys: [for (final option in RefreshRateTile.options()) 'settings_refresh_rate_short_${option.value}'],
      optional: false,
    ),
    // features/settings/appearance_pages.dart
    (template: '*_title', keys: [for (final size in _fontSizes) '${size}_title'], optional: false),
    (template: '*_desc', keys: [for (final size in _fontSizes) '${size}_desc'], optional: false),
    // features/live_play/logic/iptv_guide_rows.dart (DateTime.weekday)
    (
      template: 'live_play_weekday_*',
      keys: [for (var day = DateTime.monday; day <= DateTime.sunday; day++) 'live_play_weekday_$day'],
      optional: false,
    ),
    // features/live_play/local_interaction/
    (template: 'local_title_*', keys: [for (final id in LocalCatalog.titles) 'local_title_$id'], optional: false),
    (
      template: 'local_danmaku_preset_*',
      keys: [for (final preset in LocalCatalog.presets) 'local_danmaku_preset_${preset.id}'],
      optional: false,
    ),
    (
      template: 'local_danmaku_placement_*',
      keys: [for (final id in LocalCatalog.placementIds) 'local_danmaku_placement_$id'],
      optional: false,
    ),
    (
      template: 'local_danmaku_font_*',
      keys: [for (final id in LocalCatalog.fontFamilyIds) 'local_danmaku_font_$id'],
      optional: false,
    ),
    (template: 'local_currency_*', keys: [for (final own in ownPacks) 'local_currency_$own'], optional: false),
    (template: 'local_level_*', keys: [for (final own in ownPacks) 'local_level_$own'], optional: false),
    // features/live_play/player/bar_parts.dart
    (
      template: 'portrait_fullscreen_display_*',
      keys: [for (final mode in PortraitDisplayMode.values) 'portrait_fullscreen_display_${mode.name}'],
      optional: false,
    ),
    (
      template: 'portrait_fullscreen_display_*_desc',
      keys: [for (final mode in PortraitDisplayMode.values) 'portrait_fullscreen_display_${mode.name}_desc'],
      optional: false,
    ),
    // features/search/search_capability.dart
    (template: '*_short', keys: [for (final note in notes) '${note}_short'], optional: false),
    // shared/rooms/room_texts.dart (restrictionLabel and restrictionReason through their private table,
    // platformName, failureText)
    (
      template: 'room_mark_*',
      keys: _echo(() => [for (final r in _restrictions) restrictionLabel(r)!]),
      optional: false,
    ),
    (
      template: 'room_mark_*_hint',
      keys: _echo(() => [for (final r in _restrictions) restrictionReason(r)]),
      optional: false,
    ),
    (template: 'site_*', keys: [for (final id in _platforms) 'site_$id'], optional: true),
    (template: 'error_*', keys: [for (final type in PlayerErrorType.values) 'error_${type.name}'], optional: true),
  ];
}

/// Keys kept in tables and handed to `i18n` through a variable (most of the
/// `i18n(variable)` calls): each must be translated in both files.
Map<String, Iterable<String>> variableKeyTables() => {
  'settings catalogue': [
    for (final entry in settingsCatalog) ...[
      entry.title,
      ?entry.description,
      if (!settingsUntitledGroup(entry.group)) entry.group,
    ],
    for (final area in SettingsArea.values) area.titleKey,
    for (final section in SettingsSection.values) ...[section.titleKey, section.descriptionKey],
    for (final subpage in SettingsSubpage.values) subpage.titleKey,
    for (final (above, under) in settingsGroupNotes.values) ...[?above, ?under],
  ],
  'local interaction': [
    for (final pack in [LocalCatalog.genericPack, ...LocalCatalog.packs]) ...[
      pack.nameKey,
      pack.currencyKey,
      pack.levelKey,
      for (final gift in LocalCatalog.giftsFor(pack.id)) gift.nameKey,
    ],
  ],
  'search notes': [for (final id in SiteIds.supported) ?SearchCapabilities.of(id).noteKey],
};

/// Interpolated literals in `lib/` that look like keys but are not
/// translated (widget keys, file names).
const notTranslationKeyTemplates = {
  '*_**', // shared/backup/backup_files.dart: a numbered file name
  'favorite_areas_*', // features/areas/favorite_areas_view.dart: a PageStorageKey
  'instance_*', // app/launch_args.dart: a safe instance name
  'multiview_cell_*', // features/multiview/multiview_page.dart: a GlobalKey label
  'playlist_**', // app/iptv_legacy.dart: a copied playlist's file name
  'window_*_*', // app/launch_args.dart: an instance id
};

/// Keys in the files that nothing in `lib/` asks for, kept on purpose. A
/// key that loses its last use must be added here (or deleted with the
/// maintainer's consent, D-024); one that is used again must leave.
const keptUnusedKeys = {
  // A08.5 replaced the old danmaku rows; D-024 keeps them until the
  // maintainer agrees to delete (Z05.1 record.md has each one checked).
  'danmaku_filter',
  'danmaku_screen_interaction',
  'danmaku_similarity_cache_duration_desc',
  'danmaku_similarity_filter_desc',
  'danmaku_similarity_max_cache_size_desc',
  'danmaku_similarity_threshold_desc',
  'live_play_danmaku_area',
  'settings_app_font_desc',
  'settings_block_list',
  'settings_danmaku_auto_fps_desc',
  'settings_danmaku_bottom_margin',
  'settings_danmaku_long_press',
  'settings_danmaku_tap',
  'settings_danmaku_top_margin',
  'settings_douyu_bots',
  'settings_douyu_bots_desc',
  'settings_group_danmaku_display',
  'settings_repeat_window',
  // A16.2: the room menu says "在新窗口打开" (open_in_new_window) now.
  'open_room_in_new_window',
  // D08.3: the panel's coin row ("本地体验币 +500 …") moved into the
  // identity card's "更多"; D-024 keeps its label.
  'local_experience_coins',
  // 3.x keys with no page of their own in 4.x yet.
  'auto_close_time', // the 3.x auto-close dialog (i18n_test reads it)
  'bilibili_guest_name_masked', // 3.x's note for masked guest names
  'dlan_title',
  'double_click_to_exit', // one of 3.x's four one-language keys
  'exit_yes',
  'monitored',
  'room_playback_timer', // the timer's old title (B07 made it a panel titled otherwise)
  'user_not_found', // 3.x TikTok's missing user
  'videofit_scaleDown', // one of 3.x's four one-language keys
};

Iterable<LiveRestriction> get _restrictions => LiveRestriction.values.where((r) => r != LiveRestriction.none);

/// What [build] asks `i18n` for: the words answer every key with itself
/// (for helpers whose key table is private).
List<String> _echo(List<String> Function() build) {
  final saved = currentStrings;
  currentStrings = AppStrings(AppLanguage.zh, _EchoTable());
  try {
    return build();
  } finally {
    currentStrings = saved;
  }
}

final class _EchoTable extends MapBase<String, String> {
  @override
  String? operator [](Object? key) => key is String ? key : null;

  @override
  void operator []=(String key, String value) => throw UnsupportedError('read only');

  @override
  bool containsKey(Object? key) => key is String;

  @override
  Iterable<String> get keys => const [];

  @override
  void clear() {}

  @override
  String? remove(Object? key) => null;
}

/// The templates of the interpolated key-like literals in the Dart files
/// under [root]: `'room_mark_${x}_hint'` gives `room_mark_*_hint`.
Set<String> interpolatedKeyTemplates(String root) {
  const piece = r'(?:\$\{[^{}\x27"\n]*\}|\$[A-Za-z_]\w*)';
  final literal = RegExp('([\'"])([a-z0-9_]*$piece[a-z0-9_]*(?:$piece[a-z0-9_]*)*)\\1');
  final interpolation = RegExp(piece);
  return {
    for (final file in Directory(root).listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart'))
        for (final match in literal.allMatches(file.readAsStringSync()))
          if (match.group(2)!.replaceAll(interpolation, '*') case final template when template.contains('_')) template,
  };
}
