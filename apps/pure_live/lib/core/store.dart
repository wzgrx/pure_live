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
