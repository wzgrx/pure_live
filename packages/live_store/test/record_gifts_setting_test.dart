import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

import 'support.dart';

/// H01.8: "录制弹幕时包含礼物" is a recorder setting new in v4, off by default
/// (D-040: the chat file stays as it was), carried by backups and device
/// sync; a 3.x backup does not have it and leaves it off.
void main() {
  const setting = Settings.recordDanmakuGifts;

  test('off by default; a recorder setting synced between devices', () async {
    final store = await memoryStore();
    addTearDown(store.close);
    expect(store.settings.get(setting), isFalse);
    expect(setting.section, 'recorder');
    expect(setting.scope, SettingScope.synced);
    expect(Settings.byKey(setting.key), setting);
    expect(Settings.recorder, contains(setting), reason: 'the recording page follows the recorder settings');
    expect(store.settings.isSet(setting), isFalse, reason: 'a fresh install stores nothing');
    // "同时录制弹幕" keeps its 3.x key and default.
    expect(Settings.recordDanmaku.key, 'recorder_record_danmaku');
    expect(Settings.recordDanmaku.defaultValue, isFalse);
  });

  test('a backup carries it both ways; a 3.x backup leaves it off', () async {
    final store = await memoryStore();
    addTearDown(store.close);
    await store.settings.set(setting, true);
    final file = await BackupService(store).exportAll();
    expect((file['recorder']! as Map)[setting.key], isTrue);

    final other = await memoryStore();
    addTearDown(other.close);
    await BackupService(other).restoreAll(file);
    expect(other.settings.get(setting), isTrue);

    final fresh = await memoryStore();
    addTearDown(fresh.close);
    await BackupService(fresh).restoreAll({
      'backupVersion': 3,
      'danmaku': {'danmakuSpeed': 130.0},
    });
    expect(fresh.settings.get(setting), isFalse);
    expect(fresh.settings.isSet(setting), isFalse);
  });
}
