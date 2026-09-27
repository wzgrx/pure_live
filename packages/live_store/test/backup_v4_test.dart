import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

RoomSnapshot room(String platform, String id, {String? nick}) =>
    RoomSnapshot(ref: RoomRef(platform, id), anchorName: nick, title: 'title $id');

Future<void> seed(LiveStore store) async {
  await store.settings.set(Settings.themeMode, AppThemeMode.dark);
  await store.settings.set(Settings.danmakuSpeed, 150);
  await store.settings.set(Settings.windowWidth, 1600);
  await store.follows.follow(room('douyu', '5526219', nick: 'A'), at: DateTime.utc(2026));
  await store.follows.follow(room('kick', 'AbC', nick: 'B'), at: DateTime.utc(2026, 2));
  await store.followAreas.follow(FollowedArea(platform: 'douyu', areaId: '1', areaName: 'LOL'));
  final tag = await store.tags.create('Games', description: 'fun');
  await store.tags.setTagsOf(RoomRef('douyu', '5526219'), {tag.id});
  await store.history.record(room('huya', '998'), at: DateTime.utc(2026, 3));
  await store.history.record(room('douyu', '5526219'), at: DateTime.utc(2026, 4));
  await store.blockRules.add(BlockKind.keyword, 'Spam', at: DateTime.utc(2026));
  await store.blockRules.add(BlockKind.user, 'bot', at: DateTime.utc(2026));
  await store.roomPrefs.setVolume(RoomRef('douyu', '5526219'), 0.3);
}

void main() {
  // Two stores (source and target) are open on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late LiveStore source;
  late LiveStore target;
  late SecretStore sourceSecrets;
  late SecretStore targetSecrets;

  setUp(() async {
    source = await LiveStore.inMemory();
    target = await LiveStore.inMemory();
    sourceSecrets = await SecretStore.memory({'cookie/douyu': 'acf_auth=secret-cookie', 'cookie/douyu.did': 'did'});
    targetSecrets = await SecretStore.memory();
  });

  tearDown(() async {
    await source.close();
    await target.close();
  });

  BackupService service(LiveStore store, SecretStore secrets, {String platform = 'android'}) =>
      BackupService(store, secrets: secrets, platform: platform, kdfIterations: 1000);

  test('the document follows store.md §7.1 and holds no secrets by default', () async {
    await seed(source);
    final document = await service(source, sourceSecrets).export(now: DateTime.utc(2026, 9, 27, 2));
    expect(document['format'], 'pure_live.backup');
    expect(document['version'], 4);
    expect(document['createdAt'], '2026-09-27T02:00:00Z');
    expect(document['app'], {'version': '4.0.0', 'platform': 'android'});
    expect(document['scope'], 'full');
    expect(document['secrets'], isNull);
    final sections = document['sections']! as Map<String, Object?>;
    expect(sections.keys, containsAll(['settings', 'follows', 'followAreas', 'tags', 'roomTags', 'history']));
    expect(sections['settings'], {'theme.mode': 'dark', 'danmaku.speed': 150.0, 'window.width': 1600.0});
    final follows = sections['follows']! as List<Object?>;
    expect(follows.first, containsPair('platform', 'douyu'));
    expect(follows.first, containsPair('roomId', '5526219'));
    expect(follows.first, containsPair('followedAt', DateTime.utc(2026).millisecondsSinceEpoch));
    final text = jsonEncode(document);
    expect(text, isNot(contains('secret-cookie')));
    expect(text, isNot(contains('"id":1')), reason: 'no internal row ids');
  });

  test('export then restore reproduces the data', () async {
    await seed(source);
    final document = await service(source, sourceSecrets).export();
    final report = await service(target, targetSecrets).restore(jsonDecode(jsonEncode(document)));
    expect(report.format, 'v4');
    expect(report.issues, isEmpty);
    expect(target.settings.get(Settings.themeMode), AppThemeMode.dark);
    expect(target.settings.get(Settings.danmakuSpeed), 150);
    expect(target.settings.get(Settings.windowWidth), 1600, reason: 'same platform family');
    final follows = await target.follows.all();
    expect(follows.map((follow) => follow.ref.key), ['douyu:5526219', 'kick:AbC']);
    expect(follows.first.room.anchorName, 'A');
    expect(follows.first.followedAt, DateTime.utc(2026));
    expect(follows.first.source, FollowSource.backup);
    final tags = await target.tags.all();
    expect(tags.single.name, 'Games');
    expect(follows.first.tagIds, {tags.single.id});
    expect((await target.history.all()).map((entry) => entry.ref.key), ['douyu:5526219', 'huya:998']);
    expect((await target.blockRules.all()).map((rule) => rule.value), ['Spam', 'bot']);
    expect(await target.roomPrefs.volumeOf(RoomRef('douyu', '5526219')), 0.3);
    expect((await target.followAreas.all()).single.areaName, 'LOL');
    expect(targetSecrets.refs, isEmpty);

    // Idempotent: the same file again changes nothing.
    await service(target, targetSecrets).restore(document);
    expect(await target.follows.count(), 2);
    expect(await target.history.all(), hasLength(2));
  });

  test('device settings only restore on the same platform family', () async {
    await seed(source);
    await target.settings.set(Settings.windowWidth, 800);
    await target.settings.set(Settings.danmakuFontSize, 25);
    final document = await service(source, sourceSecrets).export();
    final report = await service(target, targetSecrets, platform: 'windows').restore(document);
    expect(target.settings.get(Settings.windowWidth), 800);
    expect(target.settings.get(Settings.danmakuFontSize), 16, reason: 'the synced scope is replaced as a whole');
    expect(report.issues.map((issue) => issue.reason), contains('otherPlatform'));
  });

  test('secrets travel only with a passphrase; a wrong one imports the rest', () async {
    await seed(source);
    final document = await service(source, sourceSecrets).export(passphrase: 'correct horse');
    final envelope = document['secrets']! as Map<String, Object?>;
    expect(envelope['kdf'], 'pbkdf2-sha256');
    expect(envelope['cipher'], 'aes-256-gcm');
    expect(base64Decode(envelope['salt']! as String), hasLength(16));
    expect(base64Decode(envelope['nonce']! as String), hasLength(12));
    expect(jsonEncode(document), isNot(contains('secret-cookie')));

    final wrong = await service(target, targetSecrets).restore(document, passphrase: 'wrong');
    expect(wrong.secretsSkipped, isTrue);
    expect(targetSecrets.refs, isEmpty);
    expect(await target.follows.count(), 2);

    final none = await service(target, targetSecrets).restore(document);
    expect(none.secretsSkipped, isTrue);

    final right = await service(target, targetSecrets).restore(document, passphrase: 'correct horse');
    expect(right.secretsSkipped, isFalse);
    expect(targetSecrets.cookieFor('douyu'), 'acf_auth=secret-cookie');
    expect(targetSecrets.read(SecretRefs.douyuDid), 'did');
  });

  test('a tampered createdAt breaks the secrets binding', () async {
    final document = await service(source, sourceSecrets).export(passphrase: 'pw');
    document['createdAt'] = '2020-01-01T00:00:00Z';
    final report = await service(target, targetSecrets).restore(document, passphrase: 'pw');
    expect(report.secretsSkipped, isTrue);
  });

  test('follows-only backups', () async {
    await seed(source);
    await target.settings.set(Settings.themeMode, AppThemeMode.light);
    await target.history.record(room('bilibili', '1'));
    final document = await service(source, sourceSecrets).export(scope: BackupScope.follows);
    expect(document['scope'], 'follows');
    expect((document['sections']! as Map).keys, ['follows', 'followAreas']);
    await expectLater(service(target, targetSecrets).restore(document), throwsFormatException);
    await service(target, targetSecrets).restore(document, mode: RestoreMode.follows);
    expect(await target.follows.count(), 2);
    expect(target.settings.get(Settings.themeMode), AppThemeMode.light);
    expect(await target.history.all(), hasLength(1));
  });

  test('restoring follows only from a full backup leaves everything else', () async {
    await seed(source);
    await target.blockRules.add(BlockKind.keyword, 'local');
    final document = await service(source, sourceSecrets).export();
    await service(target, targetSecrets).restore(document, mode: RestoreMode.follows);
    expect(await target.follows.count(), 2);
    expect((await target.blockRules.all()).single.value, 'local');
    expect(target.settings.isSet(Settings.themeMode), isFalse);
  });

  test('sections missing from the file keep local data (store.md §7.2)', () async {
    await target.history.record(room('bilibili', '1'));
    await target.blockRules.add(BlockKind.keyword, 'local');
    await target.settings.set(Settings.danmakuSpeed, 200);
    final document = {
      'format': 'pure_live.backup',
      'version': 4,
      'createdAt': '2026-09-27T02:00:00Z',
      'app': {'version': '4.0.0', 'platform': 'android'},
      'scope': 'full',
      'sections': {
        'follows': [
          {'platform': 'douyu', 'roomId': '1', 'order': 1},
          {'platform': 'douyu', 'roomId': '0'},
          {'platform': 'DOUYU', 'roomId': '2', 'order': 0},
          {'platform': 'douyu', 'roomId': '1', 'nick': 'filled'},
        ],
        'recordTasks': <Object?>[],
        'future': <Object?>[],
      },
      'secrets': null,
    };
    final report = await service(target, targetSecrets).restore(document);
    expect((await target.follows.all()).map((follow) => follow.ref.roomId), ['2', '1']);
    expect((await target.follows.get(RoomRef('douyu', '1')))!.room.anchorName, 'filled');
    expect(await target.history.all(), hasLength(1));
    expect((await target.blockRules.all()).single.value, 'local');
    expect(target.settings.get(Settings.danmakuSpeed), 200);
    expect(report.counts['follows']!.read, 4);
    expect(report.counts['follows']!.written, 2);
    expect(report.counts['follows']!.dropped, 2);
    expect(report.issues.map((issue) => issue.reason), containsAll(['invalidRoom', 'duplicate', 'unsupported']));
  });

  test('bad files write nothing', () async {
    await seed(target);
    final before = jsonEncode(await service(target, targetSecrets).export(now: DateTime.utc(2026)));
    final backup = service(target, targetSecrets);
    final bad = <Object?>[
      'text',
      <String, Object?>{'hello': 1},
      {'format': 'pure_live.backup', 'version': 5, 'scope': 'full', 'sections': <String, Object?>{}},
      {'format': 'pure_live.backup', 'version': '4', 'scope': 'full', 'sections': <String, Object?>{}},
      {'format': 'pure_live.backup', 'version': 4, 'scope': 'full'},
      {
        'format': 'pure_live.backup',
        'version': 4,
        'scope': 'full',
        'sections': {
          'follows': [
            {'platform': 'douyu', 'roomId': '9'},
          ],
          'history': 'not a list',
        },
      },
      {
        'format': 'pure_live.backup',
        'version': 4,
        'scope': 'full',
        'sections': {'settings': <Object?>[]},
      },
    ];
    for (final document in bad) {
      await expectLater(backup.restore(document), throwsA(anything), reason: '$document');
    }
    await expectLater(
      backup.restore({'format': 'pure_live.backup', 'version': 5, 'scope': 'full', 'sections': <String, Object?>{}}),
      throwsA(isA<BackupTooNewException>()),
    );
    expect(jsonEncode(await service(target, targetSecrets).export(now: DateTime.utc(2026))), before);
  });

  test('only one restore at a time', () async {
    await seed(source);
    final document = await service(source, sourceSecrets).export();
    final backup = service(target, targetSecrets);
    final first = backup.restore(document);
    await expectLater(backup.restore(document), throwsStateError);
    await first;
  });

  test('files: name, atomic write and restoreFile', () async {
    final directory = await Directory.systemTemp.createTemp('live_store_backup');
    addTearDown(() => directory.delete(recursive: true));
    await seed(source);
    final name = BackupService.fileName(BackupScope.full, DateTime(2026, 9, 27, 10, 5, 9));
    expect(name, matches(RegExp(r'^purelive_v4_2026-09-27T10_05_09_[0-9a-f-]{36}\.json$')));
    expect(BackupService.fileName(BackupScope.follows, DateTime(2026)), startsWith('purelive_v4_follows_2026-01-01T'));
    final file = await service(source, sourceSecrets).exportToDirectory(directory);
    expect(directory.listSync().map((entry) => entry.path), [file.path]);
    await BackupService.writeAtomically(file, file.readAsStringSync());
    expect(directory.listSync(), hasLength(1), reason: 'no .part or .previous left behind');
    await service(target, targetSecrets).restoreFile(file);
    expect(await target.follows.count(), 2);
    File('${directory.path}/bad.json').writeAsStringSync('{');
    await expectLater(
      service(target, targetSecrets).restoreFile(File('${directory.path}/bad.json')),
      throwsFormatException,
    );
  });

  test('a LAN v2 package wraps a v4 document', () async {
    await seed(source);
    final document = await service(source, sourceSecrets).export();
    await service(target, targetSecrets).restore({'type': 'pure_live_sync', 'version': 2, 'backup': document});
    expect(await target.follows.count(), 2);
  });
}
