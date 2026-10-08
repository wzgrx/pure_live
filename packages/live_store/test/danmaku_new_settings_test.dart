import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Danmaku settings new in v4 from the V01 proposals (D-036), defaulting
/// to what 3.x did, carried by backups and device sync: D05.2 (V01.4)
/// "同屏最大弹幕条数", 3.x's fixed 48; D03.4 (V01.3) "按住飞行弹幕让它停住", off.
void main() {
  late LiveStore store;
  setUp(() async => store = await memoryStore());
  tearDown(() => store.close());

  test('48 by default (3.x); 10..120; out of range reads as 48', () async {
    expect(store.settings.get(Settings.danmakuMaxVisibleCount), 48);
    expect(Settings.danmakuMaxVisibleCount.section, 'danmaku');
    expect(Settings.danmakuMaxVisibleCount.scope, SettingScope.synced);
    expect(Settings.byKey('danmakuMaxVisibleCount'), Settings.danmakuMaxVisibleCount);
    for (final (raw, read) in [(10, 10), (120, 120), (64, 64), (0, 48), (9, 48), (121, 48), (-1, 48)]) {
      await store.settings.set(Settings.danmakuMaxVisibleCount, raw);
      expect(store.settings.get(Settings.danmakuMaxVisibleCount), read, reason: '$raw');
    }
  });

  test("backups carry it; a file without it (3.x's) leaves the default; pure_live_TV's 0 is 48", () async {
    final backup = BackupService(store);
    await store.settings.set(Settings.danmakuMaxVisibleCount, 20);
    final file = await backup.exportAll();
    expect((file['danmaku']! as Map)['danmakuMaxVisibleCount'], 20);

    final other = await memoryStore();
    addTearDown(other.close);
    await BackupService(other).restoreAll(file);
    expect(other.settings.get(Settings.danmakuMaxVisibleCount), 20);

    final fresh = await memoryStore();
    addTearDown(fresh.close);
    await BackupService(fresh).restoreAll({
      'backupVersion': 3,
      'danmaku': {'danmakuSpeed': 130.0},
    });
    expect(fresh.settings.get(Settings.danmakuMaxVisibleCount), 48);
    expect(fresh.settings.isSet(Settings.danmakuMaxVisibleCount), isFalse);

    await BackupService(fresh).restoreAll({
      'backupVersion': 4,
      'danmaku': {'danmakuMaxVisibleCount': 0},
    });
    expect(fresh.settings.get(Settings.danmakuMaxVisibleCount), 48);
  });

  test('D03.4: "按住飞行弹幕让它停住" is on by default (D-039); a danmaku setting carried by backups', () async {
    expect(store.settings.get(Settings.holdDanmakuOnPress), isTrue);
    expect(Settings.holdDanmakuOnPress.section, 'danmaku');
    expect(Settings.holdDanmakuOnPress.scope, SettingScope.synced);
    expect(Settings.byKey('holdDanmakuOnPress'), Settings.holdDanmakuOnPress);
    await store.settings.set(Settings.holdDanmakuOnPress, false);
    final file = await BackupService(store).exportAll();
    expect((file['danmaku']! as Map)['holdDanmakuOnPress'], isFalse);
    final other = await memoryStore();
    addTearDown(other.close);
    await BackupService(other).restoreAll(file);
    expect(other.settings.get(Settings.holdDanmakuOnPress), isFalse);
    // 3.x's files do not have it: the default, on.
    final fresh = await memoryStore();
    addTearDown(fresh.close);
    await BackupService(fresh).restoreAll({
      'backupVersion': 3,
      'danmaku': {'danmakuSpeed': 130.0},
    });
    expect(fresh.settings.get(Settings.holdDanmakuOnPress), isTrue);
  });

  test('A08.10: "显示用户名" is on by default (3.x always named senders); a danmaku setting carried by backups', () async {
    expect(store.settings.get(Settings.showChatNames), isTrue);
    expect(Settings.showChatNames.section, 'danmaku');
    expect(Settings.showChatNames.scope, SettingScope.synced);
    expect(Settings.byKey('showChatNames'), Settings.showChatNames);
    await store.settings.set(Settings.showChatNames, false);
    final file = await BackupService(store).exportAll();
    expect((file['danmaku']! as Map)['showChatNames'], isFalse);
    final other = await memoryStore();
    addTearDown(other.close);
    await BackupService(other).restoreAll(file);
    expect(other.settings.get(Settings.showChatNames), isFalse);
  });
}
