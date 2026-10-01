import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:live_ui/live_ui.dart';

/// The languages of 3.x (`AppConsts.languages`): the name the `language`
/// setting stores and the translation file.
enum AppLanguage {
  /// Simplified Chinese, 3.x's fallback.
  zh('简体中文', Locale('zh')),

  /// English.
  en('English', Locale('en'));

  new(this.displayName, this.locale);

  /// The stored name (setting `language`).
  final String displayName;

  /// The locale.
  final Locale locale;

  /// The language stored as [name] (3.x's names; case and spaces ignored), or
  /// null.
  static AppLanguage? fromName(String name) {
    final key = name.trim().toLowerCase();
    for (final language in values) {
      if (language.displayName.toLowerCase() == key || language.name == key) return language;
    }
    return null;
  }

  /// The language to show.
  ///
  /// The user's choice when the `language` setting was written ([stored]);
  /// otherwise the first of the device's [preferred] locales that 3.x
  /// translated, else Chinese. 3.x started easy_localization from the device
  /// locale with Chinese as the fallback and only wrote its setting when the
  /// user picked a language, so an English phone that never touched the
  /// setting showed English while the setting said 简体中文.
  static AppLanguage resolve({required String? stored, required List<Locale> preferred}) {
    final chosen = stored == null ? null : fromName(stored);
    if (chosen != null) return chosen;
    for (final locale in preferred) {
      for (final language in values) {
        if (language.locale.languageCode == locale.languageCode) return language;
      }
    }
    return zh;
  }
}

/// The words of one language (3.x `assets/translations/<code>.json`, read
/// through easy_localization).
///
/// A key missing in the language falls back to Chinese, then English, then
/// the key itself: 3.x's files differ by a few keys (`count_wan` and
/// `videofit_scaleDown` only in Chinese, `count_k` and
/// `double_click_to_exit` only in English), which 3.x showed as raw keys in
/// Chinese.
final class AppStrings {
  /// Creates the words from parsed tables.
  new(this.language, Map<String, String> table, {this._zh = const {}, this._en = const {}}) : _table = table;

  /// The asset of [language]'s file.
  static String assetOf(AppLanguage language) => 'assets/translations/${language.locale.languageCode}.json';

  /// Loads [language] (with both fallbacks) from [bundle].
  static Future<AppStrings> load(AppLanguage language, AssetBundle bundle) async {
    Future<Map<String, String>> read(AppLanguage which) async {
      final decoded = jsonDecode(await bundle.loadString(assetOf(which), cache: false));
      return {
        if (decoded is Map)
          for (final MapEntry(:key, :value) in decoded.entries)
            if (value is String) '$key': value,
      };
    }

    final zh = await read(AppLanguage.zh);
    final en = await read(AppLanguage.en);
    return AppStrings(language, language == AppLanguage.zh ? zh : en, zh: zh, en: en);
  }

  /// The language.
  final AppLanguage language;

  final Map<String, String> _table;
  final Map<String, String> _zh;
  final Map<String, String> _en;

  /// Whether [key] has a text in this language or a fallback.
  bool contains(String key) => _table.containsKey(key) || _zh.containsKey(key) || _en.containsKey(key);

  /// The text of [key] with `{name}` placeholders filled from [args]
  /// (easy_localization's named arguments).
  String tr(String key, {Map<String, String>? args}) {
    var text = _table[key] ?? _zh[key] ?? _en[key] ?? key;
    if (args != null) {
      for (final MapEntry(:key, :value) in args.entries) {
        text = text.replaceAll('{$key}', value);
      }
    }
    return text;
  }

  /// The shared widgets' words (live_ui) in this language.
  LiveUiStrings get ui => LiveUiStrings(
    emptyTitle: tr('status_empty_title'),
    emptySubtitle: tr('status_empty_subtitle'),
    errorTitle: tr('status_error_title'),
    errorSubtitle: tr('status_error_subtitle'),
    retry: tr('status_retry_button'),
    audiencePopularity: tr('audience_popularity'),
    audienceOnline: tr('audience_online'),
    audienceTotal: tr('audience_total'),
    audienceFollowers: tr('audience_followers'),
    audienceCount: tr('audience_count'),
    audienceWaiting: tr('audience_waiting'),
    replay: tr('replay'),
    verifying: tr('favorite_status_verifying'),
    delete: tr('delete'),
    offline: tr('offline_room_title'),
  );
}

AppStrings? _current;

/// The words in use; the app sets them before the first frame and whenever
/// the language changes.
AppStrings? get currentStrings => _current;

set currentStrings(AppStrings? strings) => _current = strings;

/// The text of [key] in the current language (3.x `i18n` from
/// `plugins/locale_helper.dart`; same name and arguments so pages port
/// call by call). Before the words are loaded it answers [key].
String i18n(String key, {Map<String, String>? args}) => _current?.tr(key, args: args) ?? key;

/// [i18n], or [fallback] while the key has no text (3.x `i18nOr`).
String i18nOr(String key, String fallback, {Map<String, String>? args}) =>
    i18nExists(key) ? i18n(key, args: args) : fallback;

/// Whether [key] has a text (3.x `i18nExists`).
bool i18nExists(String key) => _current?.contains(key) ?? false;
