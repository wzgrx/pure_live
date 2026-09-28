import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/store.dart';

/// Preferences of this installation that are not user settings to back up or
/// sync: kept in the `meta` table (store.md §3), read once before the first
/// frame like the settings.
@immutable
final class AppPrefs {
  /// Creates preferences; the defaults are a fresh installation's.
  const new({
    this.clipboardRecognition = true,
    this.crashReports = false,
    this.firstRunDone = false,
    this.switchGestureHinted = false,
    this.tips = const {},
    this.navRailExtended,
  });

  /// Look for share codes and room links in the clipboard when the app
  /// returns to the foreground (F-SHR-02; on by default as in 3.x, can be
  /// turned off).
  final bool clipboardRecognition;

  /// After an uncaught error, offer to export a diagnostics bundle on the
  /// next launch (F-NEW-11; off by default, never uploads anything).
  final bool crashReports;

  /// The first-run wizard (F-NEW-08) was offered.
  final bool firstRunDone;

  /// The one-time tip that portrait fullscreen can switch rooms by swiping
  /// was shown (principles §6.1, §6.5).
  final bool switchGestureHinted;

  /// One-time tips already shown (principles §6.5), by [Tip] name.
  final Set<String> tips;

  /// The navigation rail expanded (true) or collapsed (false) by the user
  /// (principles §5.2); null until they choose, so the window class decides.
  /// A property of this device's windows, not a setting to sync.
  final bool? navRailExtended;

  /// Whether [tip] was shown.
  bool shown(Tip tip) => tips.contains(tip.name);

  /// Meta key of [tips]: names joined by commas.
  static const tipsKey = 'app.tips';

  /// Meta key of [clipboardRecognition].
  static const clipboardKey = 'app.clipboardRecognition';

  /// Meta key of [crashReports].
  static const crashReportsKey = 'app.crashReports';

  /// Meta key of [firstRunDone].
  static const firstRunKey = 'app.firstRunDone';

  /// Meta key of [switchGestureHinted].
  static const switchGestureHintKey = 'app.switchGestureHinted';

  /// Meta key of [navRailExtended].
  static const navRailKey = 'app.navRailExtended';

  /// Reads the stored preferences.
  static Future<AppPrefs> load(MetaStore meta) async {
    bool? flag(String? value) => value == null ? null : value == '1';
    const defaults = AppPrefs();
    return AppPrefs(
      clipboardRecognition: flag(await meta.get(clipboardKey)) ?? defaults.clipboardRecognition,
      crashReports: flag(await meta.get(crashReportsKey)) ?? defaults.crashReports,
      firstRunDone: flag(await meta.get(firstRunKey)) ?? defaults.firstRunDone,
      switchGestureHinted: flag(await meta.get(switchGestureHintKey)) ?? defaults.switchGestureHinted,
      navRailExtended: flag(await meta.get(navRailKey)),
      tips: {
        for (final name in (await meta.get(tipsKey) ?? '').split(','))
          if (name.isNotEmpty) name,
      },
    );
  }

  /// A copy with the given fields replaced.
  AppPrefs copyWith({
    bool? clipboardRecognition,
    bool? crashReports,
    bool? firstRunDone,
    bool? switchGestureHinted,
    Set<String>? tips,
    bool? navRailExtended,
  }) => AppPrefs(
    clipboardRecognition: clipboardRecognition ?? this.clipboardRecognition,
    crashReports: crashReports ?? this.crashReports,
    firstRunDone: firstRunDone ?? this.firstRunDone,
    switchGestureHinted: switchGestureHinted ?? this.switchGestureHinted,
    tips: tips ?? this.tips,
    navRailExtended: navRailExtended ?? this.navRailExtended,
  );
}

/// [AppPrefs] as state; main() overrides it with the loaded values.
class AppPrefsNotifier extends Notifier<AppPrefs> {
  new([this._initial = const AppPrefs()]);

  final AppPrefs _initial;

  @override
  AppPrefs build() => _initial;

  /// Turns clipboard recognition on or off.
  Future<void> setClipboardRecognition({required bool enabled}) =>
      _save(state.copyWith(clipboardRecognition: enabled), AppPrefs.clipboardKey, value: enabled);

  /// Turns the crash prompt on or off.
  Future<void> setCrashReports({required bool enabled}) =>
      _save(state.copyWith(crashReports: enabled), AppPrefs.crashReportsKey, value: enabled);

  /// Records that the first-run wizard was offered.
  Future<void> markFirstRunDone() => _save(state.copyWith(firstRunDone: true), AppPrefs.firstRunKey, value: true);

  /// Records that the room-switch swipe tip was shown.
  Future<void> markSwitchGestureHinted() =>
      _save(state.copyWith(switchGestureHinted: true), AppPrefs.switchGestureHintKey, value: true);

  /// Remembers that the user expanded or collapsed the navigation rail.
  Future<void> setNavRailExtended({required bool extended}) =>
      _save(state.copyWith(navRailExtended: extended), AppPrefs.navRailKey, value: extended);

  /// Takes [tip] if it was not shown yet: true once per installation.
  bool takeTip(Tip tip) {
    if (state.shown(tip)) return false;
    final tips = {...state.tips, tip.name};
    state = state.copyWith(tips: tips);
    unawaited(ref.read(storeProvider).meta.set(AppPrefs.tipsKey, tips.join(',')).catchError((Object _) {}));
    return true;
  }

  Future<void> _save(AppPrefs next, String key, {required bool value}) async {
    state = next;
    await ref.read(storeProvider).meta.set(key, value ? '1' : '0');
  }
}

/// This installation's preferences.
final appPrefsProvider = NotifierProvider<AppPrefsNotifier, AppPrefs>(AppPrefsNotifier.new);

/// One-time tips for changed habits (principles §6.5).
enum Tip {
  /// First room on a desktop: 收起聊天栏 and 剧场 replace 3.x's 宽屏.
  desktopRoom,

  /// First fullscreen on a touch device: pinch for the fit, long press for
  /// the quick panel.
  fullscreen,

  /// First long press: the quick panel explains itself.
  quickPanel,

  /// First room on a TV: the remote's keys.
  tvRoom,
}
