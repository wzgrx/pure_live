import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive_ce.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

/// Writes `app_settings.hive` in [dir] the way 3.x did: hive_ce `Box.put`
/// of strings, numbers, booleans, `List<String>` and maps.
Future<String> writeV3Box(Directory dir, Map<String, Object?> values, {List<String> deleted = const []}) async {
  Hive.init(dir.path);
  final box = await Hive.openBox<dynamic>('app_settings');
  for (final entry in values.entries) {
    await box.put(entry.key, entry.value);
  }
  for (final key in deleted) {
    await box.delete(key);
  }
  await box.close();
  await Hive.close();
  return p.join(dir.path, 'app_settings.hive');
}

void main() {
  late Directory temp;
  setUp(() async => temp = await Directory.systemTemp.createTemp('live_store_migration_'));
  tearDown(() => temp.delete(recursive: true));

  test('HiveBoxReader reads every 3.x value type, last write wins, deletions apply', () async {
    final path = await writeV3Box(
      temp,
      {
        'danmakuSpeed': 150.5,
        'danmakuFontWeight': 600,
        'hideDanmaku': true,
        'shieldList': ['广告', 'spam'],
        'room_to_tags_mapping_v1': {
          'bilibili:1': ['t1'],
        },
        'user_custom_tags_v5': [
          {'id': 't1', 'name': 'Games', 'description': '', 'order': 0},
        ],
        'gone': 'x',
        'themeMode': 'Light',
      },
      deleted: ['gone'],
    );
    final raw = HiveBoxReader.read(File(path).readAsBytesSync());
    expect(raw['danmakuSpeed'], 150.5);
    expect(raw['danmakuFontWeight'], 600);
    expect(raw['hideDanmaku'], isTrue);
    expect(raw['shieldList'], ['广告', 'spam']);
    expect((raw['room_to_tags_mapping_v1']! as Map)['bilibili:1'], ['t1']);
    expect(((raw['user_custom_tags_v5']! as List).single as Map)['name'], 'Games');
    expect(raw.containsKey('gone'), isFalse);
    expect(raw['themeMode'], 'Light');
  });

  test('a damaged tail keeps the frames before it (as Hive recovers)', () async {
    final path = await writeV3Box(temp, {'a': 'one', 'b': 'two'});
    final bytes = File(path).readAsBytesSync();
    final cut = bytes.sublist(0, bytes.length - 3);
    expect(HiveBoxReader.read(cut), {'a': 'one'});
  });

  group('3.x box import', () {
    late String box;
    setUp(() async {
      box = await writeV3Box(Directory(p.join(temp.path, 'HIVE_DB'))..createSync(), {
        // 2.1+ layout: a JSON string with `list`.
        'favoriteRooms': jsonEncode({
          'list': [
            v3Room('bilibili', '1', nick: 'A'),
            v3Room('twitch', 'Shroud', nick: 'shroud'),
            v3Room('twitch', 'shroud', title: 'later spelling'),
            v3Room('fc2live', '9', nick: 'F', notice: 'FC2 远端聊天尚待接入；媒体控制 WebSocket 由播放或录制独占，并保持到原生输入完整释放。'),
            v3Room('douyu', '0'),
            v3Room('huajiao', 'retired-but-kept'),
          ],
        }),
        // 2.0 layout: a list of JSON strings.
        'historyRooms': [jsonEncode(v3Room('huya', '7', lastWatchedAt: 5)), jsonEncode(v3Room('huya', '8'))],
        'favoriteAreas': jsonEncode({
          'list': [
            {'platform': 'cc', 'areaType': '1', 'typeName': '直播分类', 'areaId': '1001', 'areaName': 'X'},
          ],
        }),
        'user_custom_tags_v5': [
          {'id': 't1', 'name': 'Games', 'description': '', 'order': 1},
          {'id': 't0', 'name': 'Top', 'description': '', 'order': 0},
        ],
        'room_to_tags_mapping_v1': {
          'twitch:Shroud': ['t1'],
          '7': ['t0'],
        },
        'shieldList': [' 广告 ', '广告', 'AD', 'ad'],
        'blockedDanmakuUsers': ['bot'],
        'bilibiliCookie': 'SESSDATA=abc\n',
        'douyuLtp0': 'ltp',
        'taobaoCookie': 'drop me',
        'webDavConfigs': jsonEncode({
          'list': [
            {'name': 'nas', 'address': 'https://nas/dav', 'username': 'u', 'password': 'pw'},
          ],
        }),
        'currentWebDavConfig': jsonEncode({
          'name': 'nas',
          'address': 'https://nas/dav',
          'username': 'u',
          'password': 'pw',
        }),
        'pipDanmaNoEmojiMode': true,
        'danmakuSpeed': 150.0,
        'autoRefreshInterval': 9999,
        'enableHighRefreshRate': true,
        'hotAreasList': ['Bilibili', 'douyu', 'huajiao', 'douyu'],
        'siteCatalogMigration': 36,
        'preferPlatform': 'HUYA',
        'audienceMetricMigration': 3,
        'realOnlinePlatforms': ['douyin'],
        'historyLimit': 0,
        'recorder_tasks': jsonEncode([
          {'platform': 'missevan', 'roomId': '1', 'selectedQualityId': 'flv'},
          {'platform': 'bilibili', 'roomId': '2', 'selectedQualityId': '10000'},
        ]),
        'localInteraction.coins': 900,
        'settingsUpgradeSchema': 4,
      });
    });

    test('reads follows, history, groups, blocks, accounts and settings, repaired', () async {
      final before = File(box).readAsBytesSync();
      final store = await memoryStore();
      final report = await LegacyMigration.importHiveFiles(store, [box]);
      expect(report.importedSources, 1);

      final follows = await store.follows.all();
      expect(
        [for (final r in follows) r.identityKey],
        ['bilibili:1', 'twitch:shroud', 'fc2live:9', 'huajiao:retired-but-kept'],
      );
      expect(follows[1].roomId, 'Shroud');
      expect(follows[1].title, 'later spelling');
      expect(follows[2].notice, '');
      expect([for (final r in await store.history.all()) r.roomId], ['7', '8']);
      expect((await store.followAreas.all()).single.areaId, '1001');

      expect([for (final t in await store.tags.all()) t.name], ['Top', 'Games']);
      expect(await store.tags.tagsOf(LiveRoom(platform: 'twitch', roomId: 'SHROUD')), ['t1']);
      expect(await store.tags.tagsOf(LiveRoom(platform: 'huya', roomId: '7')), ['t0']);

      expect(await store.blockLists.list(BlockKind.keyword), ['广告', 'AD']);
      expect(await store.blockLists.list(BlockKind.user), ['bot']);
      expect(store.secrets.cookieFor('bilibili'), 'SESSDATA=abc');
      expect(store.secrets.read(SecretRefs.douyuLtp0), 'ltp');
      expect(store.secrets.cookieFor('taobao'), isNull);
      expect((await store.webdav.current())?.password, 'pw');

      final s = store.settings;
      expect(s.get(Settings.pipDanmakuNoEmojiMode), isTrue);
      expect(s.get(Settings.danmakuSpeed), 150);
      expect(s.get(Settings.autoRefreshInterval), 360);
      expect(s.get(Settings.refreshRateMode), 'balanced');
      expect(s.get(Settings.hotAreasList), ['bilibili', 'douyu', 'sixroom', 'looklive']);
      expect(s.get(Settings.preferPlatform), 'bilibili');
      expect(s.get(Settings.realOnlinePlatforms), ['douyin', 'picarto', 'twitcasting']);
      expect(s.get(Settings.enableDanmakuTapInteraction), isTrue);
      expect(s.get(Settings.historyLimit), 0);

      final tasks = jsonDecode((await store.meta.legacyValue('recorder_tasks'))! as String) as List;
      expect(
        [for (final t in tasks) (t as Map)['selectedQualityId']],
        [MissevanApi.qualityIdFromLegacy('flv'), '10000'],
      );
      expect(MissevanApi.qualityIdFromLegacy('flv'), isNot('flv'));
      expect(await store.meta.legacyValue('localInteraction.coins'), 900);
      expect(await store.meta.legacyKeys(), isNot(contains('settingsUpgradeSchema')));

      expect(File(box).readAsBytesSync(), before, reason: 'the 3.x file is only read');
      expect(File('${p.withoutExtension(box)}.lock').existsSync(), isFalse);
      await store.close();
    });

    test('a second run imports nothing twice; data already in the store wins', () async {
      final store = await memoryStore();
      await store.settings.set(Settings.danmakuSpeed, 99);
      await store.follows.add(LiveRoom(platform: 'bilibili', roomId: '1', nick: 'mine'));
      await LegacyMigration.importHiveFiles(store, [box]);
      final second = await LegacyMigration.importHiveFiles(store, [box]);
      expect(second.importedSources, 0);
      expect(second.alreadyImported, 1);
      expect(await store.follows.count(), 4);
      expect((await store.follows.all()).first.nick, 'mine');
      expect(store.settings.get(Settings.danmakuSpeed), 99);
      await store.close();
    });

    test('Windows locations follow the relocation ledger', () async {
      final exe = Directory(p.join(temp.path, 'Program', 'PureLive'))..createSync(recursive: true);
      final old = Directory(p.join(temp.path, 'Old', 'PureLive'));
      Directory(p.join(old.path, 'AppData', 'HIVE_DB')).createSync(recursive: true);
      File(box).copySync(p.join(old.path, 'AppData', 'HIVE_DB', 'app_settings.hive'));
      Directory(p.join(exe.path, 'AppData')).createSync();
      File(p.join(exe.path, 'AppData', 'previous_install_locations.txt')).writeAsStringSync('${old.path}\n');
      final files = await LegacyLocations.windows(
        executableDirectory: exe.path,
        supportDirectory: p.join(temp.path, 'support'),
        documentsDirectory: p.join(temp.path, 'docs'),
      );
      expect(files, [p.join(old.path, 'AppData', 'HIVE_DB', 'app_settings.hive')]);
      expect(LegacyLocations.android(documentsDirectory: '/data/app_flutter'), [
        '/data/app_flutter/PURE_LIVE/HIVE_DB/app_settings.hive',
      ]);
    });
  });

  test('identity migration moves per-broadcast follows to the streamer', () async {
    final store = await memoryStore();
    await store.follows.replaceAll([
      LiveRoom(platform: 'niconico', roomId: 'lv345', nick: 'Nico', notice: 'old'),
      LiveRoom(platform: 'douyin', roomId: '7400000000000000001', nick: 'D'),
      LiveRoom(platform: 'douyin', roomId: '123456', nick: 'already web_rid'),
      LiveRoom(platform: 'youtube', roomId: 'dQw4w9WgXcQ', nick: 'Y'),
    ]);
    final tag = await store.tags.add('x');
    await store.tags.setTagsOf(LiveRoom(platform: 'niconico', roomId: 'lv345'), [tag!.id]);
    final asked = <String>[];
    final moved = await IdentityMigration.run(store, (room) async {
      asked.add(room.identityKey);
      return switch (room.platform) {
        'niconico' => LiveRoom(
          platform: 'niconico',
          roomId: 'user/42',
          link: 'https://live.nicovideo.jp/watch/user/42',
        ),
        'douyin' => LiveRoom(platform: 'douyin', roomId: '123456'),
        _ => null,
      };
    });
    expect(moved, 2);
    expect(asked, ['niconico:lv345', 'douyin:7400000000000000001', 'youtube:dQw4w9WgXcQ']);
    final follows = await store.follows.all();
    expect([for (final r in follows) r.identityKey], ['niconico:user/42', 'douyin:123456', 'youtube:dQw4w9WgXcQ']);
    expect(follows.first.nick, 'Nico');
    expect(follows.first.notice, '');
    expect(follows[1].nick, 'D', reason: 'the first of two joined follows keeps its place and data');
    expect(await store.tags.tagsOf(follows.first), [tag.id]);
    await store.close();
  });

  test('quality ids map once per platform (CC, Missevan, others unchanged)', () {
    expect(LegacyRules.qualityId('missevan', 'hls'), MissevanApi.qualityIdFromLegacy('hls'));
    expect(LegacyRules.qualityId('cc', 'high'), CcApi.qualityIdFromLegacy('high'));
    expect(LegacyRules.qualityId('bilibili', '10000'), '10000');
  });
}
