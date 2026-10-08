import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

import 'support.dart';

/// D05.2 (V01.4): "同屏最大弹幕条数" is a danmaku setting new in v4, 3.x's
/// fixed 48 by default, carried by backups and device sync.
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
}
