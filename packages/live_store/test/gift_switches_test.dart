import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A08.12: the three gift switches new in v4 ("只显示值钱的礼物", "礼物价值换算成元",
/// "飞行弹幕显示礼物") are danmaku settings, off by default (D-040: nothing
/// changes for old users), carried by backups and device sync; a 3.x
/// backup does not have them and leaves them off.
void main() {
  const switches = [Settings.chatGiftsAboveTier, Settings.giftValueInYuan, Settings.danmakuShowGifts];

  test('off by default; danmaku settings synced between devices', () async {
    final store = await memoryStore();
    addTearDown(store.close);
    for (final setting in switches) {
      expect(store.settings.get(setting), isFalse, reason: setting.key);
      expect(setting.section, 'danmaku', reason: setting.key);
      expect(setting.scope, SettingScope.synced, reason: setting.key);
      expect(Settings.byKey(setting.key), setting);
      expect(store.settings.isSet(setting), isFalse, reason: '${setting.key}: a fresh install stores nothing');
    }
    // "在聊天列表显示礼物" keeps its key and default.
    expect(Settings.showChatGifts.key, 'showChatGifts');
    expect(Settings.showChatGifts.defaultValue, isTrue);
  });

  test('a backup carries them both ways; a 3.x backup leaves them off', () async {
    final store = await memoryStore();
    addTearDown(store.close);
    for (final setting in switches) {
      await store.settings.set(setting, true);
    }
    final file = await BackupService(store).exportAll();
    final danmaku = file['danmaku']! as Map;
    for (final setting in switches) {
      expect(danmaku[setting.key], isTrue, reason: setting.key);
    }

    final other = await memoryStore();
    addTearDown(other.close);
    await BackupService(other).restoreAll(file);
    for (final setting in switches) {
      expect(other.settings.get(setting), isTrue, reason: setting.key);
    }

    final fresh = await memoryStore();
    addTearDown(fresh.close);
    await BackupService(fresh).restoreAll({
      'backupVersion': 3,
      'danmaku': {'danmakuSpeed': 130.0, 'showChatGifts': false},
    });
    for (final setting in switches) {
      expect(fresh.settings.get(setting), isFalse, reason: setting.key);
      expect(fresh.settings.isSet(setting), isFalse, reason: setting.key);
    }
  });
}
