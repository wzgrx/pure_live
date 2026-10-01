import 'dart:io';

import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

import 'support.dart';

/// U.6b C-3: the default theme colour is the brand blue; 3.x's default blue
/// moves to it once, a colour the user picked stays.
void main() {
  test('the default is the brand blue; pure black is off', () {
    expect(Settings.themeColorSwitch.defaultValue, 'FF2E6FE0');
    expect(Settings.pureBlackTheme.defaultValue, isFalse);
    expect(Settings.pureBlackTheme.section, 'theme');
    expect(Settings.themeColorMigration.scope, SettingScope.internal);
  });

  test("3.x's default blue in its forms becomes the brand blue; other colours stay", () {
    for (final legacy in ['FF2196F3', 'ff2196f3', '#2196F3', '0xFF2196F3', ' 2196F3 ']) {
      expect(LegacyRules.themeColor(legacy), 'FF2E6FE0', reason: legacy);
    }
    expect(LegacyRules.themeColor('FF009688'), 'FF009688');
    expect(LegacyRules.themeColor('802196F3'), '802196F3');
  });

  test('3.x data and 3.x backups move; v4 backups keep the pick', () {
    expect(LegacySnapshot.fromHive({'themeColorSwitch': 'FF2196F3'}).settings[Settings.themeColorSwitch], 'FF2E6FE0');
    expect(LegacySnapshot.fromHive({'themeColorSwitch': 'FFDC143C'}).settings[Settings.themeColorSwitch], 'FFDC143C');
    expect(
      LegacySnapshot.fromBackup({
        'backupVersion': 3,
        'theme': {'themeColorSwitch': 'FF2196F3'},
      }).settings[Settings.themeColorSwitch],
      'FF2E6FE0',
    );
    expect(LegacySnapshot.fromBackup({'themeColorSwitch': 'FF2196F3'}).settings[Settings.themeColorSwitch], 'FF2E6FE0');
    expect(
      LegacySnapshot.fromBackup({
        'backupVersion': 4,
        'theme': {'themeColorSwitch': 'FF2196F3', 'pureBlackTheme': true},
      }).settings,
      {Settings.themeColorSwitch: 'FF2196F3', Settings.pureBlackTheme: true},
    );
  });

  test('an install that imported 3.x before moves once; a later pick of the old blue stays', () async {
    final dir = await Directory.systemTemp.createTemp('theme_color');
    addTearDown(() => dir.delete(recursive: true));
    var store = await LiveStore.open(dir, cipher: const FakeCipher());
    // As imported by an earlier version: the blue stored, no bookkeeping.
    await store.settings.set(Settings.themeColorSwitch, 'FF2196F3');
    await store.settings.reset(Settings.themeColorMigration);
    await store.close();

    store = await LiveStore.open(dir, cipher: const FakeCipher());
    expect(store.settings.get(Settings.themeColorSwitch), 'FF2E6FE0');
    expect(store.settings.get(Settings.themeColorMigration), 1);
    await store.settings.set(Settings.themeColorSwitch, 'FF2196F3');
    await store.close();

    store = await LiveStore.open(dir, cipher: const FakeCipher());
    expect(store.settings.get(Settings.themeColorSwitch), 'FF2196F3');
    await store.close();

    // A fresh install stores nothing but the bookkeeping.
    final fresh = await memoryStore();
    addTearDown(fresh.close);
    expect(fresh.settings.isSet(Settings.themeColorSwitch), isFalse);
    expect(fresh.settings.get(Settings.themeColorSwitch), 'FF2E6FE0');
  });
}
