// Local growth's settings (docs/D-弹幕/D08-本地互动/D08.3-本地成长): the switch,
// on by default (D-040), and today's counts, both in the localInteraction
// section, so full backups and device sync carry them with the coins and the
// experience.
import 'dart:convert';

import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  const enabled = Settings.localInteractionGrowthEnabled;
  const day = Settings.localInteractionGrowthDay;
  const today = '{"day":"2026-10-09","watchedMs":1500000,"watchExp":20,"checkedIn":true,"chatExp":3}';

  test('new in v4: on, nothing counted yet; in the localInteraction section, synced', () {
    expect((enabled.key, enabled.defaultValue), ('localInteraction.growthEnabled', true));
    expect((day.key, day.defaultValue), ('localInteraction.growthDay', ''));
    for (final setting in <Setting<Object>>[enabled, day]) {
      expect(setting.section, 'localInteraction');
      expect(setting.scope, SettingScope.synced);
      expect(Settings.byKey(setting.key), same(setting));
    }
  });

  test('a backup carries the switch, the counts, the coins and the experience; a restore puts them back', () async {
    final store = await memoryStore();
    addTearDown(store.close);
    await store.settings.setAll({
      enabled: false,
      day: today,
      Settings.localInteractionCoins: 1240,
      Settings.localInteractionExperience: 523,
    });
    final file = jsonDecode(jsonEncode(await BackupService(store).exportAll())) as Map<String, Object?>;
    final section = file['localInteraction']! as Map;
    expect(section['localInteraction.growthEnabled'], false);
    expect(section['localInteraction.growthDay'], today);

    final other = await memoryStore();
    addTearDown(other.close);
    await BackupService(other).restoreAll(file);
    expect(other.settings.get(enabled), isFalse);
    expect(other.settings.get(day), today);
    expect(other.settings.get(Settings.localInteractionCoins), 1240);
    expect(other.settings.get(Settings.localInteractionExperience), 523);
  });

  test('a backup from before D08.3 (or 3.x) leaves growth on and nothing counted', () async {
    final store = await memoryStore();
    addTearDown(store.close);
    await BackupService(store).restoreAll({
      'backupVersion': 4,
      'localInteraction': {'localInteraction.coins': 3000, 'localInteraction.experience': 1200},
    });
    expect(store.settings.get(enabled), isTrue);
    expect(store.settings.get(day), '');
    expect(store.settings.get(Settings.localInteractionExperience), 1200);
  });
}
