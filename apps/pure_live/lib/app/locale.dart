import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Interface language setting (F-APP-06): `system`, `zh-Hans`, `zh-Hant` or
/// `en`, stored once in [Settings.locale].
final localeSetting = NotifierProvider<SettingNotifier<String>, String>(() => SettingNotifier(Settings.locale));

/// The system's preferred languages; follows changes while the app runs.
final systemLocalesProvider = NotifierProvider<SystemLocalesNotifier, List<Locale>>(SystemLocalesNotifier.new);

/// Watches the platform's language list.
class SystemLocalesNotifier extends Notifier<List<Locale>> with WidgetsBindingObserver {
  @override
  List<Locale> build() {
    final binding = WidgetsBinding.instance..addObserver(this);
    ref.onDispose(() => binding.removeObserver(this));
    return binding.platformDispatcher.locales;
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    state = locales ?? WidgetsBinding.instance.platformDispatcher.locales;
  }
}

/// The interface language in use: the setting, or the system's when it
/// says `system`.
final appLocaleProvider = Provider<AppLocale>(
  (ref) => localeForSetting(ref.watch(localeSetting), ref.watch(systemLocalesProvider)),
);

/// The language for the stored [setting]; `system` (or anything unknown)
/// follows [system].
AppLocale localeForSetting(String setting, List<Locale> system) => switch (setting) {
  'zh-Hans' => AppLocale.zhHans,
  'zh-Hant' => AppLocale.zhHant,
  'en' => AppLocale.en,
  _ => localeForSystem(system),
};

/// Follow-system matching (F-APP-06): the first Chinese or English language
/// in the system's preference list decides. Chinese in the Traditional
/// script, or of Taiwan, Hong Kong or Macau, is Traditional; other Chinese is
/// Simplified; English, and a list with neither, is English.
AppLocale localeForSystem(List<Locale> system) {
  for (final locale in system) {
    if (locale.languageCode == 'zh') {
      return PureTheme.isTraditionalChinese(locale) ? AppLocale.zhHant : AppLocale.zhHans;
    }
    if (locale.languageCode == 'en') return AppLocale.en;
  }
  return AppLocale.en;
}

/// The Flutter locale of [locale] for Material's own text and for glyph
/// selection: Traditional Chinese uses Taiwan's conventions, like the
/// translation.
Locale flutterLocaleOf(AppLocale locale) => switch (locale) {
  AppLocale.zhHans => const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  AppLocale.zhHant => const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
  AppLocale.en => const Locale('en'),
};

/// Locales the app declares to Flutter.
final List<Locale> supportedFlutterLocales = [for (final locale in AppLocale.values) flutterLocaleOf(locale)];

var _chinesePlurals = false;

/// Chinese has a single plural form ("other"); slang has no built-in rule
/// for it and would warn on every plural.
void _registerChinesePlurals() {
  if (_chinesePlurals) return;
  _chinesePlurals = true;
  String other(num n, {String? zero, String? one, String? two, String? few, String? many, String? other}) => other!;
  LocaleSettings.setPluralResolverSync(language: 'zh', cardinalResolver: other, ordinalResolver: other);
}

/// Makes [locale] the language of `t` and of live_ui's own words. Returns
/// whether it changed.
bool applyAppLocale(AppLocale locale) {
  _registerChinesePlurals();
  final changed = LocaleSettings.currentLocale != locale;
  if (changed) LocaleSettings.setLocaleSync(locale);
  LiveUiText.current = liveUiTextOf(t);
  return changed;
}

/// live_ui's words from the translations (live_ui cannot import them).
LiveUiText liveUiTextOf(Translations text) {
  final ui = text.ui;
  return LiveUiText(
    live: ui.live,
    liveFor: (duration) => ui.liveFor(duration: duration),
    liveNow: ui.liveNow,
    offline: ui.offline,
    recording: ui.recording,
    separator: ui.separator,
    retry: ui.retry,
    ok: ui.ok,
    cancel: ui.cancel,
    justNow: ui.justNow,
    minutesAgo: (minutes) => ui.minutesAgo(n: minutes),
    hoursAgo: (hours) => ui.hoursAgo(n: hours),
    daysAgo: (days) => ui.daysAgo(n: days),
    countBase: int.parse(ui.countBase),
    countUnits: ui.countUnits,
  );
}

/// Rebuilds every widget under [context] after a language change: pages
/// read the global `t`, so they have no dependency that would rebuild them.
/// State (routes, players, scroll positions) is kept.
void rebuildAllText(BuildContext context) {
  void mark(Element element) {
    element
      ..markNeedsBuild()
      ..visitChildren(mark);
  }

  (context as Element).visitChildren(mark);
}
