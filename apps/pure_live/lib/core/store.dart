import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';

/// The opened database; main() overrides it after `LiveStore.open`.
final storeProvider = Provider<LiveStore>((ref) => throw StateError('LiveStore is opened in main()'));

/// One setting as state: starts from the in-memory value (settings are loaded
/// before the first frame, REG-STORE-001) and follows later changes.
class SettingNotifier<T extends Object> extends Notifier<T> {
  new(this.setting);

  /// The setting.
  final Setting<T> setting;

  @override
  T build() {
    final settings = ref.watch(storeProvider).settings;
    final subscription = settings.watch(setting).listen((value) => state = value);
    ref.onDispose(subscription.cancel);
    return settings.get(setting);
  }

  /// Stores a new value.
  Future<void> set(T value) => ref.read(storeProvider).settings.set(setting, value);
}

/// Theme mode: system, light or dark.
final themeModeSetting = NotifierProvider<SettingNotifier<AppThemeMode>, AppThemeMode>(
  () => SettingNotifier(Settings.themeMode),
);

/// Pure black surfaces in dark mode.
final pureBlackSetting = NotifierProvider<SettingNotifier<bool>, bool>(() => SettingNotifier(Settings.pureBlack));

/// Compact cards on the follows page.
final denseFollowsSetting = NotifierProvider<SettingNotifier<bool>, bool>(() => SettingNotifier(Settings.denseFollows));

/// Interface text scale, multiplied with the system's.
final textScaleSetting = NotifierProvider<SettingNotifier<double>, double>(() => SettingNotifier(Settings.textScale));

/// Enabled platforms in the user's order (discover tabs, search).
final catalogPlatformsSetting = NotifierProvider<SettingNotifier<List<String>>, List<String>>(
  () => SettingNotifier(Settings.catalogPlatforms),
);

/// How the video fills its box.
final videoFitSetting = NotifierProvider<SettingNotifier<VideoFit>, VideoFit>(() => SettingNotifier(Settings.videoFit));

/// Keep the screen on while playing.
final screenKeepOnSetting = NotifierProvider<SettingNotifier<bool>, bool>(() => SettingNotifier(Settings.screenKeepOn));

/// TV mode: auto, on or off (principles §5.1).
final tvModeSetting = NotifierProvider<SettingNotifier<TvMode>, TvMode>(() => SettingNotifier(Settings.tvMode));

/// TV focus without growth (performance mode, principles §5.3).
final tvPerformanceSetting = NotifierProvider<SettingNotifier<bool>, bool>(
  () => SettingNotifier(Settings.tvPerformanceMode),
);

/// Vertical swipes in portrait fullscreen switch rooms (F-NEW-04; off by default).
final switchRoomGestureSetting = NotifierProvider<SettingNotifier<bool>, bool>(
  () => SettingNotifier(Settings.switchRoomGesture),
);

/// Portrait stream adaptation (F-ROOM-06, GEO-7).
final portraitAdaptationSetting = NotifierProvider<SettingNotifier<bool>, bool>(
  () => SettingNotifier(Settings.portraitAdaptation),
);

/// Fullscreen orientation on phones (F-ROOM-06).
final portraitFullscreenPolicySetting =
    NotifierProvider<SettingNotifier<PortraitFullscreenPolicy>, PortraitFullscreenPolicy>(
      () => SettingNotifier(Settings.portraitFullscreenPolicy),
    );

/// How portrait sources fill portrait fullscreen (F-ROOM-06).
final portraitFitSetting = NotifierProvider<SettingNotifier<PortraitFit>, PortraitFit>(
  () => SettingNotifier(Settings.portraitFit),
);

/// Danmaku area in portrait fullscreen (F-ROOM-06).
final portraitDanmakuAreaSetting = NotifierProvider<SettingNotifier<PortraitDanmakuArea>, PortraitDanmakuArea>(
  () => SettingNotifier(Settings.portraitDanmakuArea),
);

/// The platform discover opens on (F-DSC-03).
final catalogPreferredSetting = NotifierProvider<SettingNotifier<String>, String>(
  () => SettingNotifier(Settings.catalogPreferred),
);

/// Dynamic colour: wallpaper (Android 12+) or system accent (Windows),
/// off by default (principles §2.2).
final dynamicColorSetting = NotifierProvider<SettingNotifier<bool>, bool>(() => SettingNotifier(Settings.dynamicColor));

/// Card preset of phones and tablets (F-SET-03).
final cardPresetMobileSetting = NotifierProvider<SettingNotifier<CardPreset>, CardPreset>(
  () => SettingNotifier(Settings.cardPresetMobile),
);

/// Card preset of desktops (F-SET-03).
final cardPresetDesktopSetting = NotifierProvider<SettingNotifier<CardPreset>, CardPreset>(
  () => SettingNotifier(Settings.cardPresetDesktop),
);
