import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A08.15: "列表文字大小" and "行间距" are danmaku settings new in v4: 0 and
/// `standard` by default (D-040: the list as before), 12..22 with anything
/// else read as 0, carried by backups and device sync; a 3.x backup does
/// not have them and leaves the defaults.
void main() {
  const size = Settings.danmakuListFontSize;
  const spacing = Settings.danmakuListLineSpacing;

  test('the defaults keep the list as before; danmaku settings synced between devices', () async {
    final store = await memoryStore();
    addTearDown(store.close);
    expect(store.settings.get(size), 0);
    expect(store.settings.get(spacing), 'standard');
    for (final setting in <Setting<Object>>[size, spacing]) {
      expect(setting.section, 'danmaku', reason: setting.key);
      expect(setting.scope, SettingScope.synced, reason: setting.key);
      expect(Settings.byKey(setting.key), setting);
      expect(store.settings.isSet(setting), isFalse, reason: '${setting.key}: a fresh install stores nothing');
    }
  });

  test('12..22 are kept; 0 and anything out of range or unreadable read as 0', () {
    for (var value = 12; value <= 22; value++) {
      expect(size.read(value), value);
    }
    for (final raw in <Object?>[0, 11, 23, -5, 100, 'big', null, double.nan]) {
      expect(size.read(raw), 0, reason: '$raw');
    }
    expect(size.read('16'), 16, reason: 'a backup written as text');
    expect(size.read(15.6), 16, reason: 'rounded');
  });

  test('the three spacings are kept; anything else reads as standard', () {
    for (final value in ['compact', 'standard', 'loose']) {
      expect(spacing.read(value), value);
    }
    for (final raw in <Object?>['tight', '', 3, null]) {
      expect(spacing.read(raw), 'standard', reason: '$raw');
    }
  });

  test('a backup carries them both ways; a 3.x backup leaves the defaults', () async {
    final store = await memoryStore();
    addTearDown(store.close);
    await store.settings.set(size, 20);
    await store.settings.set(spacing, 'compact');
    final file = await BackupService(store).exportAll();
    final danmaku = file['danmaku']! as Map;
    expect(danmaku[size.key], 20);
    expect(danmaku[spacing.key], 'compact');

    final other = await memoryStore();
    addTearDown(other.close);
    await BackupService(other).restoreAll(file);
    expect(other.settings.get(size), 20);
    expect(other.settings.get(spacing), 'compact');

    final fresh = await memoryStore();
    addTearDown(fresh.close);
    await BackupService(fresh).restoreAll({
      'backupVersion': 3,
      'danmaku': {'danmakuSpeed': 130.0, 'danmakuListFontSize': 40},
    });
    expect(fresh.settings.get(size), 0, reason: 'out of range reads as 0');
    expect(fresh.settings.get(spacing), 'standard');
  });
}
