import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// A full backup as 3.x v3.2.11 wrote it (`exportAllSettings`, sections).
Map<String, Object?> v3Backup({bool sensitive = false}) => {
  'backupVersion': 3,
  'sensitiveDataIncluded': sensitive,
  'app': {
    'enableDenseFavorites': false,
    'refreshRateMode': 'performance',
    'savedMenuIds': ['popular', 'bogus'],
  },
  'theme': {'themeMode': 'Dark', 'languageName': 'English'},
  'player': {'preferResolution': '超清', 'rememberPipPosition': false},
  'danmaku': {'danmakuSpeed': 130.0, 'pipDanmakuNoEmojiMode': true},
  'page': {
    'showGotoButton': false,
    'pageSizeOptions': [10, 20],
  },
  'windowSize': {
    'windowsPip': {'displayId': 'd1', 'windowsPipWidth': 320.0},
  },
  'favorite': {
    'shieldList': ['剧透'],
    'blockedDanmakuUsers': <String>[],
    'hotAreasList': ['douyu', 'bilibili'],
    'preferPlatform': 'douyu',
    'favoriteRooms': [v3Room('douyu', '5526219', nick: 'D'), v3Room('douyu', 'null')],
    'favoriteAreas': <Object?>[],
  },
  'history': {
    'historyRooms': [v3Room('huya', '1', lastWatchedAt: 10)],
    'historyLimit': 50,
  },
  'tags': {
    'tags': [
      {'id': 't1', 'name': 'A', 'description': '', 'order': 0},
    ],
    'roomTagsMap': {
      'douyu:5526219': ['t1'],
    },
  },
  if (sensitive) 'cookie': {'douyuCookie': 'dy_auth=1', 'bilibiliCookie': '', 'bilibiliUid': 7},
  if (sensitive)
    'webdav': {
      'currentWebDavConfig': '',
      'webDavConfigs': [
        {'name': 'nas', 'address': 'https://nas/dav', 'username': 'u', 'password': 'pw'},
      ],
    },
};

void main() {
  late LiveStore store;
  late BackupService backup;
  setUp(() async {
    store = await memoryStore();
    backup = BackupService(store);
  });
  tearDown(() => store.close());

  test('restores a 3.x full backup', () async {
    await backup.restoreAll(v3Backup(sensitive: true));
    final s = store.settings;
    expect(s.get(Settings.enableDenseFavorites), isFalse);
    expect(s.get(Settings.refreshRateMode), 'performance');
    expect(s.get(Settings.savedMenuIds), ['popular']);
    expect(s.get(Settings.themeMode), 'Dark');
    expect(s.get(Settings.language), 'English');
    expect(s.get(Settings.preferResolution), '超清');
    expect(s.get(Settings.rememberPipPosition), isFalse);
    expect(s.get(Settings.pipDanmakuNoEmojiMode), isTrue);
    expect(s.get(Settings.pageShowGotoButton), isFalse);
    expect(s.get(Settings.pageSizeOptions), '10,20');
    expect(s.get(Settings.windowsPipDisplayId), 'd1');
    expect(s.get(Settings.hotAreasList), ['douyu', 'bilibili']);
    expect(s.get(Settings.preferPlatform), 'douyu');
    expect([for (final r in await store.follows.all()) r.roomId], ['5526219']);
    expect([for (final r in await store.history.all()) r.lastWatchedAt], [10]);
    expect(await store.tags.tagsOf(LiveRoom(platform: 'douyu', roomId: '5526219')), ['t1']);
    expect(await store.blockLists.list(BlockKind.keyword), ['剧透']);
    expect(store.secrets.cookieFor('douyu'), 'dy_auth=1');
    expect(store.secrets.cookieFor('bilibili'), isNull);
    expect((await store.webdav.all()).single.password, 'pw');
  });

  test('sections the file does not have stay as they are (3.x reset them)', () async {
    await store.settings.set(Settings.enableProxy, true);
    await store.follows.add(LiveRoom(platform: 'bilibili', roomId: '1'));
    await backup.restoreAll({
      'backupVersion': 3,
      'danmaku': {'hideDanmaku': true},
    });
    expect(store.settings.get(Settings.hideDanmaku), isTrue);
    expect(store.settings.get(Settings.enableProxy), isTrue);
    expect(await store.follows.count(), 1);
  });

  test('a malformed file writes nothing', () async {
    await store.follows.add(LiveRoom(platform: 'bilibili', roomId: '1'));
    final broken = v3Backup()..['history'] = 'not a section';
    await expectLater(backup.restoreAll(broken), throwsFormatException);
    await expectLater(backup.restoreAll({'backupVersion': 'x'}), throwsFormatException);
    await expectLater(backup.restoreAll({'something': 1}), throwsFormatException);
    expect(await store.follows.count(), 1);
    expect(store.settings.get(Settings.themeMode), 'System');
  });

  test('v4 export round-trips and keeps 3.x layout; accounts only when asked', () async {
    await backup.restoreAll(v3Backup(sensitive: true));
    await store.settings.set(Settings.preferH264, false);
    final plain = await backup.exportAll();
    expect(plain['backupVersion'], 4);
    expect(plain.containsKey('cookie'), isFalse);
    expect(plain.containsKey('webdav'), isFalse);
    expect(((plain['favorite']! as Map)['favoriteRooms']! as List).single, containsPair('roomId', '5526219'));
    expect((plain['danmaku']! as Map)['pipDanmakuNoEmojiMode'], isTrue);
    expect((plain['page']! as Map)['pageSizeOptions'], [10, 20]);

    final other = await memoryStore();
    final full = jsonDecode(jsonEncode(await backup.exportAll(includeSensitiveData: true))) as Map<String, Object?>;
    await BackupService(other).restoreAll(full);
    expect(other.settings.get(Settings.preferH264), isFalse);
    expect(other.settings.get(Settings.themeMode), 'Dark');
    expect(other.secrets.cookieFor('douyu'), 'dy_auth=1');
    expect(await other.tags.tagsOf(LiveRoom(platform: 'douyu', roomId: '5526219')), ['t1']);
    await other.close();
  });

  test('recorder settings: adopted once from parked 3.x values, carried by backups except the folder', () async {
    await store.meta.keepLegacyValues({
      'segmentTime': 600,
      'maxTaskCount': 99,
      'default_quality': '超清',
      'recordSavePath': '/old/records',
      'recorder_tasks': '[]',
    });
    await store.settings.set(Settings.recordEnablePolling, true);
    await store.meta.keepLegacyValues({'enable_polling': false});
    expect(await LegacyMigration.adoptLegacyValues(store), 4);
    expect(store.settings.get(Settings.recordSegmentTime), 600);
    expect(store.settings.get(Settings.recordMaxTaskCount), 10);
    expect(store.settings.get(Settings.recordDefaultQuality), '超清');
    expect(store.settings.get(Settings.recordEnablePolling), isTrue, reason: 'a stored value wins');
    expect(await store.meta.legacyKeys(), ['recorder_tasks'], reason: 'adopted keys leave legacy_values');
    expect(await LegacyMigration.adoptLegacyValues(store), 0);

    final file = await backup.exportAll();
    final recorder = file['recorder']! as Map;
    expect(recorder['segmentTime'], 600);
    expect(recorder.containsKey('recordSavePath'), isFalse, reason: 'a path of this device (like backupDirectory)');
    final other = await memoryStore();
    await BackupService(other).restoreAll(jsonDecode(jsonEncode(file)) as Map<String, Object?>);
    expect(other.settings.get(Settings.recordSegmentTime), 600);
    expect(other.settings.get(Settings.recordEnablePolling), isTrue);
    expect(other.settings.get(Settings.recordSavePath), '');
    await other.close();
  });

  test('follows-only files (3.x backup_roundtrip_test)', () async {
    await store.follows.add(LiveRoom(platform: 'douyu', roomId: '1'));
    await store.settings.set(Settings.hideDanmaku, true);
    final file = await backup.exportFollows();
    expect(file['backupScope'], 'favorites');
    expect(file.keys, unorderedEquals(['backupVersion', 'backupScope', 'favorite']));
    await expectLater(backup.restoreAll(file), throwsFormatException);

    await store.follows.replaceAll([]);
    await backup.restoreFollows(file);
    expect(await store.follows.count(), 1);
    expect(store.settings.get(Settings.hideDanmaku), isTrue);
    await backup.restoreFollows({
      'favoriteRooms': [jsonEncode(v3Room('huya', '9'))],
    });
    expect([for (final r in await store.follows.all()) r.roomId], ['9']);
  });

  test('flat backups without a version (oldest 3.x)', () async {
    await backup.restoreAll({
      'danmakuSpeed': 90.0,
      'favoriteRooms': [v3Room('bilibili', '3')],
      'custom_tags_data': {
        'tags': [
          {'id': 'x', 'name': 'X', 'order': 0},
        ],
        'roomTagsMap': {
          '3': ['x'],
        },
      },
    });
    expect(store.settings.get(Settings.danmakuSpeed), 90);
    expect(await store.tags.tagsOf(LiveRoom(platform: 'bilibili', roomId: '3')), ['x']);
  });

  test('one restore at a time', () async {
    final first = backup.restoreAll(v3Backup());
    await expectLater(backup.restoreAll(v3Backup()), throwsStateError);
    await first;
  });

  test('files are written through .part and replace the old one', () async {
    final dir = await Directory.systemTemp.createTemp('live_store_backup_');
    final file = File(p.join(dir.path, 'purelive_backup.txt'));
    await BackupService.writeFile(file, {'backupVersion': 4});
    await BackupService.writeFile(file, {'backupVersion': 4, 'app': <String, Object?>{}});
    expect(await BackupService.readFile(file), containsPair('app', <String, Object?>{}));
    expect(dir.listSync().map((e) => p.basename(e.path)), ['purelive_backup.txt']);
    await dir.delete(recursive: true);
  });
}
