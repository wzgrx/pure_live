// The local danmaku phrases (docs/D-弹幕/D08-本地互动/D08.2-常用语和最近发送): a
// list setting of the localInteraction section, empty by default, at most 20,
// trimmed, no empty ones or repeats, carried by backups and device sync with
// the other settings.
import 'dart:convert';

import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  const phrases = Settings.localInteractionPhrases;

  test('new in v4: empty by default, in the localInteraction section, carried by backups', () {
    expect(phrases.key, 'localInteraction.phrases');
    expect(phrases.defaultValue, isEmpty);
    expect(phrases.section, 'localInteraction');
    expect(phrases.scope, SettingScope.synced);
    expect(Settings.byKey('localInteraction.phrases'), same(phrases));
    expect(Settings.localPhraseLimit, 20);
  });

  test('repaired as it is read: trimmed, no empty ones or repeats, the first 20', () {
    expect(phrases.read(['  晚上好 ', '', '   ', '晚上好', '666', '晚上好 ']), ['晚上好', '666']);
    final many = [for (var i = 0; i < 25; i++) '第$i句'];
    expect(phrases.read(many), many.take(20).toList());
    expect(phrases.read(['a', 'a', ...many]), ['a', ...many.take(19)], reason: 'a repeat does not take a place');
    expect(phrases.read('not a list'), isEmpty);
    expect(phrases.read([1, true, ' x ']), ['1', 'true', 'x'], reason: 'as text, as every list setting');
  });

  test('other list settings stay as they were (repeats and spaces kept)', () {
    expect(Settings.localInteractionHistory.read([' a ', ' a ', '']), [' a ', ' a ', '']);
  });

  test('stored and read back repaired; a backup carries them, a restore puts them back in order', () async {
    final store = await memoryStore();
    addTearDown(store.close);
    await store.settings.set(phrases, [' 主播晚上好 ', '666', '666', '前排']);
    expect(store.settings.get(phrases), ['主播晚上好', '666', '前排']);

    final file = jsonDecode(jsonEncode(await BackupService(store).exportAll())) as Map<String, Object?>;
    expect((file['localInteraction']! as Map)['localInteraction.phrases'], ['主播晚上好', '666', '前排']);

    final other = await memoryStore();
    addTearDown(other.close);
    await other.settings.set(phrases, ['别的']);
    await BackupService(other).restoreAll(file);
    expect(other.settings.get(phrases), ['主播晚上好', '666', '前排']);
  });

  test('a backup from before D08.2 (or from 3.x) leaves them empty; a bad one is repaired', () async {
    final store = await memoryStore();
    addTearDown(store.close);
    await BackupService(store).restoreAll({
      'backupVersion': 4,
      'localInteraction': {
        'localInteraction.userName': '阿明',
        'localInteraction.phrases': ['', ' 好 ', '好', for (var i = 0; i < 30; i++) '$i'],
      },
    });
    expect(store.settings.get(Settings.localInteractionUserName), '阿明');
    expect(store.settings.get(phrases), ['好', for (var i = 0; i < 19; i++) '$i']);

    final old = await memoryStore();
    addTearDown(old.close);
    await BackupService(old).restoreAll({
      'backupVersion': 3,
      'localInteraction': {'localInteraction.userName': '阿明'},
    });
    expect(old.settings.get(phrases), isEmpty);
  });
}
