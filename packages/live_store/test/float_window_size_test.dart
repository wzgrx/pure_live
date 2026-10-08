import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A07.22 (V01.5): "小窗大小" and the size the user pulled the in-app
/// floating window to are player settings new in v4; by default the window
/// is the size it always had.
void main() {
  late LiveStore store;
  setUp(() async => store = await memoryStore());
  tearDown(() => store.close());

  test('medium and not resized by default; three sizes; factors 0.25..4', () async {
    expect(store.settings.get(Settings.floatWindowSize), 'medium');
    expect(store.settings.get(Settings.floatWindowLandscapeScale), 1);
    expect(store.settings.get(Settings.floatWindowPortraitScale), 1);
    for (final setting in <Setting<Object>>[
      Settings.floatWindowSize,
      Settings.floatWindowLandscapeScale,
      Settings.floatWindowPortraitScale,
    ]) {
      expect(setting.section, 'player');
      expect(setting.scope, SettingScope.synced);
    }
    for (final size in ['small', 'large', 'medium']) {
      await store.settings.set(Settings.floatWindowSize, size);
      expect(store.settings.get(Settings.floatWindowSize), size);
    }
    await store.settings.set(Settings.floatWindowSize, 'huge');
    expect(store.settings.get(Settings.floatWindowSize), 'medium', reason: 'not one of the three');
    for (final (raw, read) in [(1.4, 1.4), (0.1, 0.25), (9.0, 4.0)]) {
      await store.settings.set(Settings.floatWindowPortraitScale, raw);
      expect(store.settings.get(Settings.floatWindowPortraitScale), read, reason: '$raw');
    }
  });

  test("backups carry them; a file without them (3.x's) leaves the window as it was", () async {
    final backup = BackupService(store);
    await store.settings.set(Settings.floatWindowSize, 'large');
    await store.settings.set(Settings.floatWindowLandscapeScale, 1.3);
    final file = await backup.exportAll();
    final player = file['player']! as Map;
    expect(player['floatWindowSize'], 'large');
    expect(player['floatWindowLandscapeScale'], 1.3);

    final other = await memoryStore();
    addTearDown(other.close);
    await BackupService(other).restoreAll(file);
    expect(other.settings.get(Settings.floatWindowSize), 'large');
    expect(other.settings.get(Settings.floatWindowLandscapeScale), 1.3);
    expect(other.settings.get(Settings.floatWindowPortraitScale), 1);

    final fresh = await memoryStore();
    addTearDown(fresh.close);
    await BackupService(fresh).restoreAll({
      'backupVersion': 3,
      'player': {'floatPlay': true},
    });
    expect(fresh.settings.get(Settings.floatWindowSize), 'medium');
    expect(fresh.settings.isSet(Settings.floatWindowSize), isFalse);
    expect(fresh.settings.get(Settings.floatWindowLandscapeScale), 1);
  });
}
