import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

Map<String, Object?> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, Object?>;

void main() {
  late LiveStore store;
  late SecretStore secrets;
  late BackupService backup;

  setUp(() async {
    store = await LiveStore.inMemory();
    secrets = await SecretStore.memory({'cookie/huya': 'old-huya', 'cookie/kuaishou': 'kept'});
    backup = BackupService(store, secrets: secrets, platform: 'android');
  });

  tearDown(() => store.close());

  group('3.x v3 full backup', () {
    late ImportReport report;

    setUp(() async => report = await backup.restore(fixture('v3_full_backup.json')));

    test('settings map through the registry (store.md §6.4)', () {
      final settings = store.settings;
      expect(report.format, 'v3');
      expect(settings.get(Settings.themeMode), AppThemeMode.dark);
      expect(settings.get(Settings.locale), 'en');
      expect(settings.get(Settings.denseFollows), isFalse);
      expect(settings.get(Settings.backgroundPlay), isTrue);
      expect(settings.get(Settings.autoCheckUpdate), isFalse);
      expect(settings.get(Settings.refreshRateMode), RefreshRateMode.balanced);
      expect(settings.get(Settings.qualityWifi), QualityPreference.bluRay4M);
      expect(settings.get(Settings.qualityMobile), QualityPreference.smooth);
      expect(settings.get(Settings.hardwareDecoding), isFalse);
      expect(settings.get(Settings.videoFit), VideoFit.cover);
      expect(settings.get(Settings.danmakuSpeed), 400, reason: 'clamped');
      expect(settings.get(Settings.danmakuFontSize), 20);
      expect(settings.get(Settings.danmakuOpacity), 0.8);
      expect(settings.get(Settings.danmakuNoEmoji), isTrue);
      expect(settings.get(Settings.danmakuLongPressInteraction), isFalse);
      expect(settings.get(Settings.danmakuRepeatedWindowSeconds), 8);
      expect(settings.get(Settings.danmakuPipNoEmoji), isTrue);
      expect(settings.get(Settings.catalogPlatforms), ['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou', 'twitch']);
      expect(settings.get(Settings.catalogPreferred), 'huya');
      expect(settings.get(Settings.historyLimit), 3);
      expect(settings.get(Settings.cardPresetMobile), CardPreset.compact);
      expect(settings.get(Settings.cardPresetDesktop), CardPreset.rich);
      expect(settings.get(Settings.textScale), 1.1);
      expect(settings.get(Settings.windowWidth), 1600);
      expect(settings.get(Settings.launchAtStartup), isTrue, reason: 'migrated users keep their value');
      expect(settings.get(Settings.bilibiliUid), 123456);
      expect(settings.get(Settings.douyuCookieSavedAt), 1790000000);
      expect(settings.get(Settings.autoRefreshFollows), isTrue);
      expect(settings.get(Settings.autoRefreshInterval), 15);
      final unknown = {
        for (final issue in report.issues)
          if (issue.reason == 'unknownKey') issue.detail,
      };
      expect(unknown, containsAll(['crossAxisSpacing', 'proxyPort', 'cornerRadius']));
      expect(unknown, isNot(contains('videoPlayerKey')), reason: 'dropped on purpose, not unknown');
      expect(unknown, isNot(contains('enableHighRefreshRate')));
    });

    test('follows are validated, de-duplicated and keep their order (§6.4.7)', () async {
      final follows = await store.follows.all();
      expect(follows.map((follow) => follow.ref.key), [
        'douyu:5526219',
        'huya:11342412',
        'bilibili:22603245',
        'kick:AbCdEf',
        'kick:abcdef',
      ]);
      expect(follows.first.room.anchorName, 'AnchorA');
      expect(follows.first.room.area, 'Chat');
      expect(follows.first.room.audience.popularity, 1200);
      expect(follows.first.source, FollowSource.import);
      expect(follows.first.room.lastState, LiveState.live, reason: 'kept as a cache');
      expect(follows.first.room.lastLiveAt, isNull, reason: 'an import is not a sighting');
      final huya = follows[1].room;
      expect(huya.audience.popularity, 88000, reason: 'Huya onlineViewers is popularity (§6.4.11)');
      expect(huya.audience.online, isNull);
      expect(huya.lastState, LiveState.offline);
      expect(follows[2].room.lastState, isNull, reason: 'liveStatus 3 is unknown');
      final follow = report.counts['follows']!;
      expect((follow.read, follow.written, follow.dropped), (8, 5, 3));
      expect(
        report.issues.where((issue) => issue.section == 'follows').map((issue) => issue.detail),
        containsAll(['douyu:0', 'bilibili:null', 'douyu:5526219']),
      );
    });

    test('areas use the §2 identity', () async {
      final areas = await store.followAreas.all();
      expect(areas.map((area) => area.key), ['douyu||1', 'missevan|tag|7', 'missevan|catalog|7']);
    });

    test('history keeps order, drops invalid rooms and honours the file limit', () async {
      final history = await store.history.all();
      expect(history.map((entry) => entry.ref.key), ['bilibili:22603245', 'douyu:5526219', 'huya:998']);
      expect(history.first.lastWatchedAt, DateTime.fromMillisecondsSinceEpoch(1790000000000, isUtc: true));
      expect(history.last.lastWatchedAt, isNull);
    });

    test('tags follow the mapping, merge names and resolve plain room ids (§6.4.6)', () async {
      final tags = await store.tags.all();
      expect(tags.map((tag) => tag.name), ['Music', 'Games', 'No id', 'Duplicate id']);
      expect(tags.map((tag) => tag.id).toSet(), hasLength(4));
      final games = tags.firstWhere((tag) => tag.name == 'Games').id;
      final music = tags.firstWhere((tag) => tag.name == 'Music').id;
      expect(games, 't1');
      expect(music, 't2');
      expect(await store.tags.tagsOf(RoomRef('douyu', '5526219')), {games});
      expect(await store.tags.tagsOf(RoomRef('bilibili', '22603245')), {music, games});
      expect(await store.tags.tagsOf(RoomRef('huya', '11342412')), {games});
      final reasons = report.issues.where((issue) => issue.section == 'roomTags').map((issue) => issue.reason);
      expect(reasons, containsAll(['unknownTag', 'unmatchedRoom']));
    });

    test('block rules, room preferences and cookies', () async {
      expect((await store.blockRules.all(BlockKind.keyword)).map((rule) => rule.value), ['广告', 'Spam']);
      expect((await store.blockRules.all(BlockKind.user)).map((rule) => rule.value), ['bot_user']);
      expect(await store.roomPrefs.volumeOf(RoomRef('douyu', '5526219')), 0.35);
      expect(await store.roomPrefs.volumeOf(RoomRef('huya', 'bad')), 1);
      expect(await store.roomPrefs.get(RoomRef('douyin', '646454278948'), RoomPrefStore.portraitLayout), 'portrait');
      expect(await store.roomPrefs.get(RoomRef('bilibili', 'bad-layout'), RoomPrefStore.portraitLayout), isNull);
      expect(secrets.cookieFor('bilibili'), 'SESSDATA=fake-bili; bili_jct=fake');
      expect(secrets.cookieFor('douyu'), 'acf_uid=1; acf_auth=fake-douyu');
      expect(secrets.read(SecretRefs.douyuLtp0), 'fake-ltp0');
      expect(secrets.cookieFor('huya'), isNull, reason: 'signed out in the backup');
      expect(secrets.cookieFor('kuaishou'), isNull);
      expect(report.issues.map((issue) => issue.section), contains('webdavProfiles'));
      expect(report.issues.map((issue) => '$issue').join('\n'), isNot(contains('hunter2')));
    });

    test('importing the same file twice gives the same result', () async {
      final first = jsonEncode(await backup.export(now: DateTime.utc(2026)));
      await backup.restore(fixture('v3_full_backup.json'));
      final second = jsonEncode(await backup.export(now: DateTime.utc(2026)));
      // Import times differ; everything else must not.
      String normalise(String text) => text.replaceAll(RegExp(r'"(followedAt|createdAt)":\d+'), '');
      expect(normalise(second), normalise(first));
    });
  });

  test('flat 3.x backups with pre-2.0 string lists', () async {
    final report = await backup.restore(fixture('legacy_flat_backup.json'));
    expect(report.format, 'legacy');
    expect(store.settings.get(Settings.themeMode), AppThemeMode.light);
    expect(store.settings.get(Settings.locale), 'zh-Hans');
    expect(store.settings.get(Settings.dynamicColor), isTrue);
    expect(store.settings.get(Settings.danmakuPipNoEmoji), isTrue);
    expect(store.settings.get(Settings.qualityWifi), QualityPreference.superHigh);
    expect(store.settings.get(Settings.refreshRateMode), RefreshRateMode.balanced);
    expect(store.settings.get(Settings.historyLimit), 0);
    expect(store.settings.get(Settings.catalogPreferred), 'bilibili', reason: 'not visible, so the first platform');
    expect((await store.follows.all()).map((follow) => follow.ref.key), ['bilibili:7734200', 'douyu:288016']);
    expect((await store.follows.all()).first.room.lastState, LiveState.live);
    expect(report.counts['follows']!.dropped, 1);
    expect((await store.history.all()).map((entry) => entry.ref.key), ['douyu:288016', 'bilibili:7734200']);
    expect(await store.tags.tagsOf(RoomRef('douyu', '288016')), {'legacy-1'});
    expect(secrets.cookieFor('bilibili'), 'SESSDATA=legacy');
    expect(secrets.cookieFor('huya'), 'old-huya', reason: 'absent keys leave secrets alone');
    expect(report.issues.where((issue) => issue.reason == 'unknownKey').map((issue) => issue.detail), [
      'someRemovedSetting',
    ]);
  });

  test('3.x follows-only files need the follows entry', () async {
    await store.settings.set(Settings.themeMode, AppThemeMode.dark);
    final document = {
      'backupVersion': 3,
      'backupScope': 'favorites',
      'favorite': {
        'favoriteRooms': [
          {'roomId': '1', 'platform': 'douyu', 'nick': 'A'},
        ],
        'favoriteAreas': <Object?>[],
      },
    };
    await expectLater(backup.restore(document), throwsFormatException);
    final report = await backup.restore(document, mode: RestoreMode.follows);
    expect(report.format, 'v3-follows');
    expect(await store.follows.count(), 1);
    expect(store.settings.get(Settings.themeMode), AppThemeMode.dark);
  });

  test('restoring follows from a full 3.x backup touches nothing else', () async {
    await backup.restore(fixture('v3_full_backup.json'), mode: RestoreMode.follows);
    expect(await store.follows.count(), 5);
    expect(await store.history.all(), isEmpty);
    expect(await store.tags.all(), isEmpty);
    expect(store.settings.isSet(Settings.themeMode), isFalse);
    expect(secrets.cookieFor('bilibili'), isNull);
  });

  test('v2 backups and LAN v1 packages import like v3', () async {
    final v2 = {
      'backupVersion': 2,
      'theme': {'themeMode': 'Light', 'languageName': 'English'},
      'favorite': {
        'favoriteRooms': [
          {'roomId': '9', 'platform': 'huya'},
        ],
      },
    };
    expect((await backup.restore(v2)).format, 'v2');
    expect(store.settings.get(Settings.locale), 'en');
    await backup.restore({
      'type': 'pure_live_sync',
      'version': 1,
      'settings': {
        'backupVersion': 3,
        'favorite': {
          'favoriteRooms': [
            {'roomId': '10', 'platform': 'huya'},
          ],
        },
      },
    });
    expect((await store.follows.all()).single.ref.roomId, '10');
  });

  test('invalid 3.x files write nothing', () async {
    await store.follows.follow(RoomSnapshot(ref: RoomRef('douyu', 'keep')));
    final bad = <Map<String, Object?>>[
      {'backupVersion': '3', 'app': <String, Object?>{}},
      {'backupVersion': -1, 'app': <String, Object?>{}},
      {'backupVersion': 3},
      {'backupVersion': 3, 'app': <String, Object?>{}},
      {'backupVersion': 3, 'app': 'not a map'},
      {
        'backupVersion': 3,
        'favorite': {'favoriteRooms': 'not a list'},
      },
      {'custom_tags_data': <String, Object?>{}},
      {'unrelated': true},
      {'type': 'pure_live_sync', 'version': 9, 'settings': <String, Object?>{}},
    ];
    for (final document in bad) {
      await expectLater(backup.restore(document), throwsFormatException, reason: '$document');
    }
    expect((await store.follows.all()).single.ref.roomId, 'keep');
  });

  test('without a secret store cookies are skipped, not written elsewhere', () async {
    final plain = BackupService(store);
    final report = await plain.restore(fixture('v3_full_backup.json'));
    expect(report.secretsSkipped, isTrue);
    final rows = await store.database.customSelect('SELECT value FROM settings').get();
    expect(rows.map((row) => row.read<String>('value')).join(), isNot(contains('fake-bili')));
  });
}
