import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

import 'support.dart';

/// D07.2: "上舰和开会员进醒目留言" (`superChatIncludesMembership`) is new in v4,
/// a danmaku setting, on by default (the exception D-040 names), carried by
/// backups and device sync; a 3.x backup does not have it and leaves it on.
void main() {
  const setting = Settings.superChatIncludesMembership;

  test('on by default; a danmaku setting synced between devices', () async {
    final store = await memoryStore();
    addTearDown(store.close);
    expect(setting.key, 'superChatIncludesMembership');
    expect(store.settings.get(setting), isTrue);
    expect(setting.section, 'danmaku');
    expect(setting.scope, SettingScope.synced);
    expect(Settings.byKey(setting.key), setting);
    expect(store.settings.isSet(setting), isFalse, reason: 'a fresh install stores nothing');
  });

  test('a backup carries it both ways; a 3.x backup leaves it on', () async {
    final store = await memoryStore();
    addTearDown(store.close);
    await store.settings.set(setting, false);
    final file = await BackupService(store).exportAll();
    expect((file['danmaku']! as Map)[setting.key], isFalse);

    final other = await memoryStore();
    addTearDown(other.close);
    await BackupService(other).restoreAll(file);
    expect(other.settings.get(setting), isFalse);

    final fresh = await memoryStore();
    addTearDown(fresh.close);
    await BackupService(fresh).restoreAll({
      'backupVersion': 3,
      'danmaku': {'danmakuSpeed': 130.0, 'showChatGifts': false},
    });
    expect(fresh.settings.get(setting), isTrue);
    expect(fresh.settings.isSet(setting), isFalse);
  });
}
