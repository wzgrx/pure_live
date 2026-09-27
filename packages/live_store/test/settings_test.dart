import 'dart:io';

import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

void main() {
  group('setting definitions', () {
    test('every id is unique and every default is valid', () {
      final ids = <String>{};
      for (final setting in Settings.all) {
        expect(ids.add(setting.id), isTrue, reason: setting.id);
        expect(setting.decode(setting.encode(setting.defaultValue)), setting.defaultValue, reason: setting.id);
        expect(Settings.byId(setting.id), same(setting));
      }
    });

    test('numbers are clamped and non-finite values rejected', () {
      expect(Settings.danmakuSpeed.decode(900), 400);
      expect(Settings.danmakuSpeed.decode(5), 20);
      expect(Settings.danmakuSpeed.decode(double.nan), isNull);
      expect(Settings.danmakuSpeed.decode('150'), 150);
      expect(Settings.danmakuFps.decode(59.6), 60);
      expect(Settings.historyLimit.decode(-3), 0);
      expect(Settings.historyLimit.decode('x'), isNull);
    });

    test('enums, strings and lists validate their values', () {
      expect(Settings.themeMode.decode('dark'), AppThemeMode.dark);
      expect(Settings.themeMode.decode('Dark'), isNull);
      expect(Settings.locale.decode('fr'), isNull);
      expect(Settings.locale.decode('zh-Hant'), 'zh-Hant');
      expect(Settings.catalogPlatforms.decode([' Douyu', 'huya', 'douyu', '', 3]), ['douyu', 'huya']);
      expect(Settings.pureBlack.decode('true'), isTrue);
      expect(Settings.pureBlack.decode(1), isNull);
    });

    test('3.x values convert to v4 values (store.md §6.4)', () {
      Object? convert(Setting<Object> setting, String key, Object? value) =>
          setting.decode(setting.legacy.firstWhere((legacy) => legacy.name == key).apply(value));
      expect(convert(Settings.themeMode, 'themeMode', 'System'), AppThemeMode.system);
      expect(convert(Settings.themeMode, 'themeMode', 'Light'), AppThemeMode.light);
      expect(convert(Settings.themeMode, 'themeMode', 'Purple'), AppThemeMode.system);
      expect(convert(Settings.locale, 'language', '简体中文'), 'zh-Hans');
      expect(convert(Settings.locale, 'languageName', 'English'), 'en');
      expect(convert(Settings.qualityWifi, 'preferResolution', '原画'), QualityPreference.original);
      expect(convert(Settings.qualityWifi, 'preferResolution', '蓝光8M'), QualityPreference.bluRay8M);
      expect(convert(Settings.qualityMobile, 'preferResolutionCellular', '超清'), QualityPreference.superHigh);
      expect(convert(Settings.qualityMobile, 'preferResolutionCellular', '4K'), QualityPreference.original);
      expect(convert(Settings.videoFit, 'videoFitIndex', 5), VideoFit.scaleDown);
      expect(convert(Settings.videoFit, 'videoFitIndex', 9), VideoFit.contain);
      expect(convert(Settings.refreshRateMode, 'enableHighRefreshRate', true), RefreshRateMode.balanced);
      expect(convert(Settings.refreshRateMode, 'enableHighRefreshRate', false), RefreshRateMode.powerSaving);
      expect(convert(Settings.catalogPreferred, 'preferPlatform', ' HUYA '), 'huya');
      expect(convert(Settings.danmakuPipNoEmoji, 'pipDanmaNoEmojiMode', true), isTrue);
    });

    test('scopes follow store.md §5', () {
      expect(Settings.danmakuSpeed.scope, SettingScope.synced);
      expect(Settings.themeMode.scope, SettingScope.synced);
      expect(Settings.hardwareDecoding.scope, SettingScope.device);
      expect(Settings.windowWidth.scope, SettingScope.device);
      expect(Settings.launchAtStartup.scope, SettingScope.device);
      expect(Settings.launchAtStartup.defaultValue, isFalse);
    });
  });

  group('SettingsStore', () {
    late LiveStore store;

    setUp(() async => store = await LiveStore.inMemory());
    tearDown(() => store.close());

    test('reads defaults, stores values and resets them', () async {
      final settings = store.settings;
      expect(settings.get(Settings.themeMode), AppThemeMode.system);
      expect(settings.isSet(Settings.themeMode), isFalse);
      await settings.set(Settings.themeMode, AppThemeMode.dark);
      await settings.set(Settings.danmakuOpacity, 7);
      expect(settings.get(Settings.themeMode), AppThemeMode.dark);
      expect(settings.get(Settings.danmakuOpacity), 1, reason: 'clamped');
      await settings.reset(Settings.themeMode);
      expect(settings.get(Settings.themeMode), AppThemeMode.system);
    });

    test('watch emits the current value, then each change once', () async {
      final values = <double>[];
      final subscription = store.settings.watch(Settings.danmakuSpeed).listen(values.add);
      await pumpEventQueue();
      await store.settings.set(Settings.danmakuSpeed, 150);
      await store.settings.set(Settings.danmakuSpeed, 150);
      await store.settings.set(Settings.danmakuFontSize, 20);
      await store.settings.reset(Settings.danmakuSpeed);
      await pumpEventQueue();
      expect(values, [120, 150, 120]);
      await subscription.cancel();
    });

    test('resetAll keeps nothing of the chosen scopes', () async {
      await store.settings.set(Settings.danmakuSpeed, 150);
      await store.settings.set(Settings.windowWidth, 1600);
      await store.settings.resetAll(scopes: {SettingScope.synced});
      expect(store.settings.isSet(Settings.danmakuSpeed), isFalse);
      expect(store.settings.get(Settings.windowWidth), 1600);
    });

    test('export lists stored values of the given scopes as JSON', () async {
      await store.settings.set(Settings.themeMode, AppThemeMode.dark);
      await store.settings.set(Settings.catalogPlatforms, ['huya', 'douyu']);
      await store.settings.set(Settings.windowWidth, 1600);
      expect(store.settings.export({SettingScope.synced}), {
        'theme.mode': 'dark',
        'catalog.platforms': ['huya', 'douyu'],
      });
    });
  });

  test('values survive reopening; invalid stored values fall back to defaults', () async {
    final directory = await Directory.systemTemp.createTemp('live_store_settings');
    addTearDown(() => directory.delete(recursive: true));
    final warnings = <String>[];
    var fileStore = await LiveStore.open(directory.path, background: false);
    await fileStore.settings.set(Settings.startPage, StartPage.discover);
    await fileStore.database.customStatement(
      "INSERT INTO settings (key, value, updated_at) VALUES ('danmaku.fps', '\"fast\"', 0), ('gone.key', '1', 0)",
    );
    await fileStore.close();
    fileStore = await LiveStore.open(directory.path, background: false, log: StoreLog(warnings.add));
    expect(fileStore.settings.get(Settings.startPage), StartPage.discover);
    expect(fileStore.settings.get(Settings.danmakuFps), 60);
    expect(warnings, hasLength(2));
    expect(File(LiveStore.databasePath(directory.path)).existsSync(), isTrue);
    await fileStore.close();
  });
}
