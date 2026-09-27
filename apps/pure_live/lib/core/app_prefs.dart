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
  const new({this.clipboardRecognition = true, this.crashReports = false, this.firstRunDone = false});

  /// Look for share codes and room links in the clipboard when the app
  /// returns to the foreground (F-SHR-02; on by default as in 3.x, can be
  /// turned off).
  final bool clipboardRecognition;

  /// After an uncaught error, offer to export a diagnostics bundle on the
  /// next launch (F-NEW-11; off by default, never uploads anything).
  final bool crashReports;

  /// The first-run wizard (F-NEW-08) was offered.
  final bool firstRunDone;

  /// Meta key of [clipboardRecognition].
  static const clipboardKey = 'app.clipboardRecognition';

  /// Meta key of [crashReports].
  static const crashReportsKey = 'app.crashReports';

  /// Meta key of [firstRunDone].
  static const firstRunKey = 'app.firstRunDone';

  /// Reads the stored preferences.
  static Future<AppPrefs> load(MetaStore meta) async {
    bool? flag(String? value) => value == null ? null : value == '1';
    const defaults = AppPrefs();
    return AppPrefs(
      clipboardRecognition: flag(await meta.get(clipboardKey)) ?? defaults.clipboardRecognition,
      crashReports: flag(await meta.get(crashReportsKey)) ?? defaults.crashReports,
      firstRunDone: flag(await meta.get(firstRunKey)) ?? defaults.firstRunDone,
    );
  }

  /// A copy with the given fields replaced.
  AppPrefs copyWith({bool? clipboardRecognition, bool? crashReports, bool? firstRunDone}) => AppPrefs(
    clipboardRecognition: clipboardRecognition ?? this.clipboardRecognition,
    crashReports: crashReports ?? this.crashReports,
    firstRunDone: firstRunDone ?? this.firstRunDone,
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

  Future<void> _save(AppPrefs next, String key, {required bool value}) async {
    state = next;
    await ref.read(storeProvider).meta.set(key, value ? '1' : '0');
  }
}

/// This installation's preferences.
final appPrefsProvider = NotifierProvider<AppPrefsNotifier, AppPrefs>(AppPrefsNotifier.new);
