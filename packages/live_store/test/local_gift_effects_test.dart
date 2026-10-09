// The local gift effects' level (docs/D-弹幕/D08-本地互动/D08.5-三档礼物特效 c2):
// a new choice beside 3.x's switch, `all` by default (what the switch on
// was, D-040), in the localInteraction section so backups and device sync
// carry it; 3.x's switch keeps its key and meaning (D-018).
import 'dart:convert';

import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  const level = Settings.localInteractionGiftEffectLevel;
  const legacy = Settings.localInteractionEnableGiftEffects;

  test('new in v4: all; three choices, anything else reads as all; synced', () {
    expect((level.key, level.defaultValue), ('localInteraction.giftEffectLevel', 'all'));
    expect(level.allowed, {'all', 'bigOnly', 'off'});
    expect(level.section, 'localInteraction');
    expect(level.scope, SettingScope.synced);
    expect(Settings.byKey(level.key), same(level));
    expect(
      [
        for (final raw in <Object?>['bigOnly', 'off', 'big', 3, null]) level.read(raw),
      ],
      ['bigOnly', 'off', 'all', 'all', 'all'],
    );
    expect((legacy.key, legacy.defaultValue), ('localInteraction.enableGiftEffects', true), reason: 'D-018');
  });

  test('a backup carries the level with the switch; a restore puts both back', () async {
    final store = await memoryStore();
    addTearDown(store.close);
    await store.settings.setAll({level: 'bigOnly', legacy: true});
    final file = jsonDecode(jsonEncode(await BackupService(store).exportAll())) as Map<String, Object?>;
    final section = file['localInteraction']! as Map;
    expect(
      (section['localInteraction.giftEffectLevel'], section['localInteraction.enableGiftEffects']),
      ('bigOnly', true),
    );

    final other = await memoryStore();
    addTearDown(other.close);
    await BackupService(other).restoreAll(file);
    expect((other.settings.get(level), other.settings.get(legacy)), ('bigOnly', true));
  });

  test('a backup from before D08.5 (or 3.x) keeps its switch and stores no level', () async {
    final store = await memoryStore();
    addTearDown(store.close);
    await BackupService(store).restoreAll({
      'backupVersion': 4,
      'localInteraction': {'localInteraction.enableGiftEffects': false},
    });
    expect(store.settings.get(legacy), isFalse);
    expect(store.settings.isSet(level), isFalse, reason: 'the app reads the switch: off');
    expect(store.settings.get(level), 'all');
  });
}
