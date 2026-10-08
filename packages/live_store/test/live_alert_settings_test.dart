import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

import 'support.dart';

/// O01.1 (V01.1, D-036): "开播提醒" is new in v4 and off by default, so a
/// 3.x user notices nothing; it and its tag choice travel in the `refresh`
/// section of backups (3.x reads only its own keys there and skips these).
void main() {
  late LiveStore store;
  setUp(() async => store = await memoryStore());
  tearDown(() => store.close());

  test('off and every follow by default; refresh section, synced', () {
    expect(store.settings.get(Settings.liveAlertEnabled), isFalse);
    expect(store.settings.get(Settings.liveAlertTagIds), isEmpty);
    for (final setting in <Setting<Object>>[Settings.liveAlertEnabled, Settings.liveAlertTagIds]) {
      expect(setting.section, 'refresh');
      expect(setting.scope, SettingScope.synced);
      expect(Settings.byKey(setting.key), setting);
    }
  });

  test('backups carry both; a 3.x file leaves them off and empty', () async {
    await store.settings.set(Settings.liveAlertEnabled, true);
    await store.settings.set(Settings.liveAlertTagIds, ['t1', 't2']);
    final file = await BackupService(store).exportAll();
    final refresh = file['refresh']! as Map;
    expect(refresh['liveAlertEnabled'], isTrue);
    expect(refresh['liveAlertTagIds'], ['t1', 't2']);

    final other = await memoryStore();
    addTearDown(other.close);
    await BackupService(other).restoreAll(file);
    expect(other.settings.get(Settings.liveAlertEnabled), isTrue);
    expect(other.settings.get(Settings.liveAlertTagIds), ['t1', 't2']);

    final fresh = await memoryStore();
    addTearDown(fresh.close);
    await BackupService(fresh).restoreAll({
      'backupVersion': 3,
      'refresh': {'autoRefreshFavorite': true, 'autoRefreshInterval': 10},
    });
    expect(fresh.settings.get(Settings.liveAlertEnabled), isFalse);
    expect(fresh.settings.get(Settings.liveAlertTagIds), isEmpty);
    expect(fresh.settings.get(Settings.autoRefreshInterval), 10);
  });
}
