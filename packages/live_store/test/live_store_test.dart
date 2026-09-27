import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

void main() {
  test('opens <root>/DB/pure_live.db on a background isolate and keeps data', () async {
    final root = await Directory.systemTemp.createTemp('live_store_root');
    addTearDown(() => root.delete(recursive: true));
    var store = await LiveStore.open(root.path);
    await store.follows.follow(RoomSnapshot(ref: RoomRef('douyu', '5526219'), anchorName: 'A'));
    await store.settings.set(Settings.themeMode, AppThemeMode.dark);
    await store.close();
    expect(File('${root.path}/DB/pure_live.db').existsSync(), isTrue);

    store = await LiveStore.open(root.path);
    expect((await store.follows.all()).single.room.anchorName, 'A');
    expect(store.settings.get(Settings.themeMode), AppThemeMode.dark);
    final mode = await store.database.customSelect('PRAGMA journal_mode').getSingle();
    expect(mode.data.values.single, 'wal');
    await store.close();
  });

  test('a plan can be previewed, then applied', () async {
    final store = await LiveStore.inMemory();
    addTearDown(store.close);
    final backup = BackupService(store);
    final plan = await backup.plan({
      'backupVersion': 3,
      'favorite': {
        'favoriteRooms': [
          {'roomId': '1', 'platform': 'douyu'},
        ],
      },
    });
    expect(plan.report.counts['follows']!.written, 1);
    expect(await store.follows.count(), 0, reason: 'planning writes nothing');
    await backup.apply(plan);
    expect(await store.follows.count(), 1);
  });
}
