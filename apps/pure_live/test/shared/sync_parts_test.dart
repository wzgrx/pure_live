// J05.1 (V01.6): device sync picks parts of the backup it carries; what is
// left out stays as it is on the receiving device.
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/shared/backup/sync_parts.dart';

import '../support.dart';

LiveRoom _room(String id) => LiveRoom(platform: 'douyu', roomId: id, title: 't$id', nick: 'n$id');

/// A store with one of everything device sync carries.
Future<LiveStore> _filled({String room = '1', String word = 'spoiler', bool splash = false}) async {
  final store = await LiveStore.memory(cipher: FakeCipher());
  addTearDown(store.close);
  await store.settings.set(Settings.showSplashPage, splash);
  await store.follows.replaceAll([_room(room)]);
  await store.history.replaceAll([_room('h$room')]);
  await store.blockLists.replaceAll(BlockKind.keyword, [word]);
  await store.blockLists.replaceAll(BlockKind.user, ['user$room']);
  return store;
}

void main() {
  test('a v4 export holds every part; accounts and WebDAV only with sensitive data', () async {
    final store = await _filled();
    final plain = await BackupService(store).exportAll();
    expect(syncPartsSplittable(plain), isTrue);
    expect(syncPartsIn(plain), [
      SyncPart.settings,
      SyncPart.follows,
      SyncPart.areas,
      SyncPart.history,
      SyncPart.tags,
      SyncPart.keywords,
      SyncPart.users,
    ]);
    final sensitive = await BackupService(store).exportAll(includeSensitiveData: true);
    expect(syncPartsIn(sensitive), containsAll([SyncPart.webdav, SyncPart.accounts]));

    final counts = syncPartCounts(plain);
    expect(counts[SyncPart.follows], 1);
    expect(counts[SyncPart.history], 1);
    expect(counts[SyncPart.keywords], 1);
    expect(counts[SyncPart.settings], greaterThan(100));
    expect(counts.containsKey(SyncPart.accounts), isFalse);
  });

  test('picking follows keeps only the followed rooms; restoring it leaves the rest alone', () async {
    final source = await _filled(room: '2', word: 'noise');
    final target = await _filled();
    final picked = pickSyncParts(await BackupService(source).exportAll(), {SyncPart.follows});
    expect(picked.keys.toSet(), {'backupVersion', 'sensitiveDataIncluded', 'favorite'});
    expect((picked['favorite']! as Map).keys, ['favoriteRooms']);
    expect(syncSectionsOf(picked), ['favorite']);
    expect(syncPartsIn(picked), [SyncPart.follows]);

    await BackupService(target).restoreAll(picked);
    expect([for (final room in await target.follows.all()) room.roomId], ['2']);
    expect(await target.blockLists.list(BlockKind.keyword), ['spoiler'], reason: 'keywords not picked');
    expect([for (final room in await target.history.all()) room.roomId], ['h1'], reason: 'history not picked');
    expect(target.settings.get(Settings.showSplashPage), isFalse, reason: 'settings not picked');
  });

  test('picking settings and keywords splits the favorite section by key', () async {
    final source = await _filled(room: '2', word: 'noise', splash: true);
    final target = await _filled();
    final picked = pickSyncParts(await BackupService(source).exportAll(), {SyncPart.settings, SyncPart.keywords});
    final favorite = (picked['favorite']! as Map).keys.toSet();
    expect(favorite, containsAll(['shieldList', 'hotAreasList']));
    expect(favorite.intersection({'favoriteRooms', 'favoriteAreas', 'blockedDanmakuUsers'}), isEmpty);
    expect(picked.containsKey('tags'), isFalse);
    expect((picked['history']! as Map).containsKey('historyRooms'), isFalse);

    await BackupService(target).restoreAll(picked);
    expect(target.settings.get(Settings.showSplashPage), isTrue);
    expect(await target.blockLists.list(BlockKind.keyword), ['noise']);
    expect([for (final room in await target.follows.all()) room.roomId], ['1']);
    expect(await target.blockLists.list(BlockKind.user), ['user1']);
  });

  test('everything picked, or a flat 3.x file: the data goes as it is', () async {
    final store = await _filled();
    final full = await BackupService(store).exportAll();
    final all = SyncPart.values.toSet();
    expect(syncPartsLeaveOut(full, all), isFalse);
    expect(syncPartsLeaveOut(full, null), isFalse);
    expect(identical(onlySyncParts(full, all), full), isTrue);
    expect(syncPartsLeaveOut(full, {SyncPart.follows}), isTrue);

    final flat = <String, Object?>{'showSplashPage': false, 'favoriteRooms': <Object?>[]};
    expect(syncPartsSplittable(flat), isFalse);
    expect(identical(onlySyncParts(flat, {SyncPart.follows}), flat), isTrue);
  });

  test('a packet lists its sections: only those are read; none listed is the whole backup', () {
    final data = <String, Object?>{
      'backupVersion': 4,
      'app': {'showSplashPage': true},
      'favorite': {'favoriteRooms': <Object?>[]},
    };
    expect(withinSyncSections(data, null), same(data));
    expect(withinSyncSections(data, const []), same(data));
    expect(withinSyncSections(data, const ['favorite']).keys, ['backupVersion', 'favorite']);
  });

  test('K01.2: the remembered sign-ins travel with the account part only and are counted once', () async {
    final source = await _filled();
    await source.accounts.remember(SiteIds.bilibili, uid: 7, name: 'Fake Seven', cookie: 'SESSDATA=fake-7');
    await source.accounts.remember(SiteIds.bilibili, uid: 8, name: 'Fake Eight', cookie: 'SESSDATA=fake-8');
    await source.secrets.setCookie(SiteIds.bilibili, 'SESSDATA=fake-7');

    final plain = await BackupService(source).exportAll();
    expect('$plain', isNot(contains('fake-8')));
    final sensitive = await BackupService(source).exportAll(includeSensitiveData: true);
    // The current cookie and the one other remembered sign-in.
    expect(syncPartCounts(sensitive)[SyncPart.accounts], 2);
    final withoutAccounts = pickSyncParts(sensitive, SyncPart.values.toSet()..remove(SyncPart.accounts));
    expect('$withoutAccounts', isNot(contains('fake-')));

    final target = await _filled();
    await target.accounts.remember(SiteIds.bilibili, uid: 3, name: 'Fake Three', cookie: 'SESSDATA=fake-3');
    await target.secrets.setCookie(SiteIds.bilibili, 'SESSDATA=fake-3');
    await BackupService(target).restoreAll(withoutAccounts);
    expect([for (final account in target.accounts.of(SiteIds.bilibili)) account.uid], [3]);
    expect(target.secrets.cookieFor(SiteIds.bilibili), 'SESSDATA=fake-3');

    await BackupService(target).restoreAll(pickSyncParts(sensitive, {SyncPart.accounts}));
    expect(target.secrets.cookieFor(SiteIds.bilibili), 'SESSDATA=fake-7');
    expect({for (final account in target.accounts.of(SiteIds.bilibili)) account.uid}, {3, 7, 8});
  });
}
