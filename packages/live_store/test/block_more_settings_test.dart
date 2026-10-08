import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

import 'support.dart';

/// D02.2: the emoticon-only and length blocks are off by default (D-040),
/// danmaku settings carried by backups; a pattern block word (`/…/`) is a
/// word like any other in the block list, its backup and 3.x's import.
void main() {
  late LiveStore store;
  setUp(() async => store = await memoryStore());
  tearDown(() => store.close());

  test('off by default; the length is 30, kept to 10..100', () async {
    for (final setting in [Settings.blockEmoteOnlyDanmaku, Settings.blockLongDanmaku]) {
      expect(store.settings.get(setting), isFalse, reason: setting.key);
      expect(setting.section, 'danmaku');
      expect(setting.scope, SettingScope.synced);
      expect(Settings.byKey(setting.key), setting);
    }
    expect(store.settings.get(Settings.blockLongDanmakuLength), 30);
    for (final (raw, read) in [(10, 10), (100, 100), (45, 45), (5, 10), (500, 100)]) {
      await store.settings.set(Settings.blockLongDanmakuLength, raw);
      expect(store.settings.get(Settings.blockLongDanmakuLength), read, reason: '$raw');
    }
  });

  test('backups carry them; a file without them (3.x) leaves them off', () async {
    await store.settings.set(Settings.blockEmoteOnlyDanmaku, true);
    await store.settings.set(Settings.blockLongDanmaku, true);
    await store.settings.set(Settings.blockLongDanmakuLength, 50);
    final file = await BackupService(store).exportAll();
    final danmaku = file['danmaku']! as Map;
    expect(danmaku['blockEmoteOnlyDanmaku'], isTrue);
    expect(danmaku['blockLongDanmaku'], isTrue);
    expect(danmaku['blockLongDanmakuLength'], 50);

    final other = await memoryStore();
    addTearDown(other.close);
    await BackupService(other).restoreAll(file);
    expect(other.settings.get(Settings.blockEmoteOnlyDanmaku), isTrue);
    expect(other.settings.get(Settings.blockLongDanmaku), isTrue);
    expect(other.settings.get(Settings.blockLongDanmakuLength), 50);

    final fresh = await memoryStore();
    addTearDown(fresh.close);
    await BackupService(fresh).restoreAll({
      'backupVersion': 3,
      'danmaku': {'danmakuSpeed': 130.0},
    });
    expect(fresh.settings.get(Settings.blockEmoteOnlyDanmaku), isFalse);
    expect(fresh.settings.get(Settings.blockLongDanmaku), isFalse);
    expect(fresh.settings.get(Settings.blockLongDanmakuLength), 30);
  });

  test('a pattern block word is stored, backed up and restored as typed', () async {
    const pattern = r'/^[0-9]+$/';
    const long = '/(qq|vx|微信).{0,8}[0-9a-z]{5,}/';
    expect(await store.blockLists.add(BlockKind.keyword, pattern), isTrue);
    expect(await store.blockLists.add(BlockKind.keyword, long), isTrue);
    expect(await store.blockLists.add(BlockKind.keyword, '广告'), isTrue);
    final file = await BackupService(store).exportAll();
    expect((file['favorite']! as Map)['shieldList'], [pattern, long, '广告']);

    final other = await memoryStore();
    addTearDown(other.close);
    await BackupService(other).restoreAll(file);
    expect(await other.blockLists.list(BlockKind.keyword), [pattern, long, '广告']);

    // 3.x's own file (its `shieldList`) brings a pattern in unchanged too.
    final fresh = await memoryStore();
    addTearDown(fresh.close);
    await BackupService(fresh).restoreAll({
      'backupVersion': 3,
      'favorite': {
        'shieldList': [pattern],
      },
    });
    expect(await fresh.blockLists.list(BlockKind.keyword), [pattern]);
  });
}
