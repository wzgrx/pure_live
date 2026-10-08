import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

import 'support.dart';

// K01.2 (V01.2): the remembered Bilibili sign-ins. Every cookie, name and
// uid here is an obvious placeholder.

/// [FakeCipher] that refuses to seal while [failing] (a broken Keystore).
final class _FlakyCipher implements SecretCipher {
  bool failing = false;

  @override
  Future<Uint8List> seal(String ref, String plain) async {
    if (failing) throw StateError('keystore unavailable');
    return await const FakeCipher().seal(ref, plain);
  }

  @override
  Future<String> open(String ref, Uint8List sealed) => const FakeCipher().open(ref, sealed);
}

void main() {
  // The tests open a second database to read what another device sees.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late DateTime now;
  late LiveStore store;
  late _FlakyCipher cipher;

  setUp(() async {
    now = DateTime(2026, 10, 8, 12);
    cipher = _FlakyCipher();
    store = await LiveStore.memory(cipher: cipher, now: () => now);
  });

  tearDown(() => store.close());

  AccountRoster roster() => store.accounts;

  List<int> uids() => [for (final account in roster().of('bilibili')) account.uid];

  test('a sign-in is remembered sealed, newest first; the same uid is updated, unchanged writes nothing', () async {
    await roster().remember('bilibili', uid: 1, name: 'Fake One', cookie: 'SESSDATA=fake-1');
    now = now.add(const Duration(minutes: 1));
    await roster().remember('bilibili', uid: 2, name: 'Fake Two', cookie: ' SESSDATA=fake-2\n');
    expect(uids(), [2, 1]);
    expect(roster().find('bilibili', 2)!.cookie, 'SESSDATA=fake-2');
    final rows = await store.database.rows('SELECT ref, sealed FROM secrets');
    expect({for (final row in rows) row.read<String>('ref')}, {'account/bilibili/1', 'account/bilibili/2'});
    for (final row in rows) {
      final raw = String.fromCharCodes(row.read<List<int>>('sealed'));
      expect(raw, isNot(contains('SESSDATA')));
      expect(raw, isNot(contains('Fake')));
    }

    // The current cookie is not touched by remembering.
    expect(store.secrets.cookieFor('bilibili'), isNull);

    final changes = <String>[];
    final subscription = roster().changes.listen(changes.add);
    now = now.add(const Duration(minutes: 1));
    await roster().remember('bilibili', uid: 1, name: '', cookie: 'SESSDATA=fake-1');
    await Future<void>.delayed(Duration.zero);
    expect(changes, isEmpty, reason: 'nothing changed');
    await roster().remember('bilibili', uid: 1, name: '', cookie: 'SESSDATA=fake-1b');
    await Future<void>.delayed(Duration.zero);
    expect(changes, ['bilibili']);
    final one = roster().find('bilibili', 1)!;
    expect(one.name, 'Fake One', reason: 'an empty name keeps the known one');
    expect(one.cookie, 'SESSDATA=fake-1b');
    expect(uids(), [1, 2], reason: 'a new cookie counts as used now');
    await subscription.cancel();

    // Without a uid or a cookie nothing is remembered.
    await roster().remember('bilibili', uid: 0, name: 'x', cookie: 'SESSDATA=fake-0');
    await roster().remember('bilibili', uid: 3, name: 'x', cookie: ' ');
    expect(uids(), [1, 2]);
  });

  test('beyond five, the least recently used other sign-in is forgotten', () async {
    for (var uid = 1; uid <= 5; uid++) {
      now = now.add(const Duration(minutes: 1));
      await roster().remember('bilibili', uid: uid, name: 'Fake $uid', cookie: 'SESSDATA=fake-$uid');
    }
    // 1 becomes the most recent by switching to it.
    now = now.add(const Duration(minutes: 1));
    await roster().switchTo('bilibili', 1);
    now = now.add(const Duration(minutes: 1));
    await roster().remember('bilibili', uid: 6, name: 'Fake 6', cookie: 'SESSDATA=fake-6');
    expect(uids(), [6, 1, 5, 4, 3]);
    expect(AccountRoster.limit, 5);
  });

  test('switching makes the entry the current cookie in one write and keeps the one being left', () async {
    await roster().remember('bilibili', uid: 1, name: 'Fake One', cookie: 'SESSDATA=fake-1');
    await store.secrets.setCookie('bilibili', 'SESSDATA=fake-2');
    final cookies = <String>[];
    final subscription = store.secrets.cookieChanges.listen(cookies.add);
    now = now.add(const Duration(minutes: 1));
    final previous = SavedAccount(uid: 2, name: 'Fake Two', cookie: 'SESSDATA=fake-2', usedAt: now);
    final switched = await roster().switchTo('bilibili', 1, previous: previous);
    await Future<void>.delayed(Duration.zero);
    expect(switched!.uid, 1);
    expect(store.secrets.cookieFor('bilibili'), 'SESSDATA=fake-1');
    expect(cookies, ['bilibili']);
    expect(uids(), [1, 2]);
    expect(roster().find('bilibili', 1)!.usedAt, now);
    expect(await roster().switchTo('bilibili', 9), isNull);
    expect(store.secrets.cookieFor('bilibili'), 'SESSDATA=fake-1');
    await subscription.cancel();
  });

  test('forgetting removes the sealed entries; the current cookie stays', () async {
    await roster().remember('bilibili', uid: 1, name: 'Fake One', cookie: 'SESSDATA=fake-1');
    await roster().remember('bilibili', uid: 2, name: 'Fake Two', cookie: 'SESSDATA=fake-2');
    await store.secrets.setCookie('bilibili', 'SESSDATA=fake-2');
    await roster().forget('bilibili', [1]);
    expect(uids(), [2]);
    expect(store.secrets.cookieFor('bilibili'), 'SESSDATA=fake-2');
    expect(roster().forgetting('bilibili', (account) => account.cookie == 'SESSDATA=fake-2'), {
      'account/bilibili/2': null,
    });
    expect(roster().sites, {'bilibili'});
  });

  test('a failing secure storage changes nothing: the roster and the current cookie stay', () async {
    await roster().remember('bilibili', uid: 1, name: 'Fake One', cookie: 'SESSDATA=fake-1');
    await roster().remember('bilibili', uid: 2, name: 'Fake Two', cookie: 'SESSDATA=fake-2');
    await store.secrets.setCookie('bilibili', 'SESSDATA=fake-2');
    cipher.failing = true;
    await expectLater(
      roster().remember('bilibili', uid: 3, name: 'Fake 3', cookie: 'SESSDATA=fake-3'),
      throwsStateError,
    );
    await expectLater(roster().switchTo('bilibili', 1), throwsStateError);
    expect(uids(), [1, 2]);
    expect(store.secrets.cookieFor('bilibili'), 'SESSDATA=fake-2');
    final reopened = await SecretStore.load(store.database, const FakeCipher());
    expect(reopened.cookieFor('bilibili'), 'SESSDATA=fake-2');
    expect(reopened.refs, {'cookie/bilibili', 'account/bilibili/1', 'account/bilibili/2'});
  });

  test('entries this device cannot open are left out and dropped with the next write', () async {
    final foreign = await LiveStore.memory(cipher: const FakeCipher.foreign());
    addTearDown(foreign.close);
    await roster().remember('bilibili', uid: 1, name: 'Fake One', cookie: 'SESSDATA=fake-1');
    final rows = await store.database.rows('SELECT ref, sealed FROM secrets');
    for (final row in rows) {
      await foreign.database.run('INSERT INTO secrets (ref, sealed) VALUES (?, ?)', [
        row.read<String>('ref'),
        row.read<Uint8List>('sealed'),
      ]);
    }
    final secrets = await SecretStore.load(foreign.database, const FakeCipher.foreign());
    final other = AccountRoster(secrets);
    expect(other.of('bilibili'), isEmpty);
    expect(secrets.unreadable, {'account/bilibili/1'});
    await other.remember('bilibili', uid: 2, name: 'Fake Two', cookie: 'SESSDATA=fake-2');
    expect(secrets.unreadable, isEmpty);
    final left = await foreign.database.rows('SELECT ref FROM secrets');
    expect([for (final row in left) row.read<String>('ref')], ['account/bilibili/2']);
  });

  group('backups', () {
    Future<void> remembered() async {
      await roster().remember('bilibili', uid: 1, name: 'Fake One', cookie: 'SESSDATA=fake-1');
      now = now.add(const Duration(minutes: 1));
      await roster().remember('bilibili', uid: 2, name: 'Fake Two', cookie: 'SESSDATA=fake-2');
      await store.secrets.setCookie('bilibili', 'SESSDATA=fake-2');
      await store.settings.set(Settings.bilibiliUid, 2);
    }

    test('only a backup with accounts carries them, next to the cookies', () async {
      await remembered();
      final plain = await BackupService(store).exportAll();
      expect(plain.containsKey('cookie'), isFalse);
      expect('$plain', isNot(contains('fake-1')));
      final sensitive = await BackupService(store).exportAll(includeSensitiveData: true);
      final cookie = sensitive['cookie']! as Map<String, Object?>;
      expect(cookie['bilibiliCookie'], 'SESSDATA=fake-2');
      expect(cookie['bilibiliAccounts'], [
        {'uid': 2, 'name': 'Fake Two', 'cookie': 'SESSDATA=fake-2', 'usedAt': now.millisecondsSinceEpoch ~/ 1000},
        {
          'uid': 1,
          'name': 'Fake One',
          'cookie': 'SESSDATA=fake-1',
          'usedAt': now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/ 1000,
        },
      ]);
    });

    test('a restore adds the sign-ins it carries and keeps the others; a file without them leaves them', () async {
      await remembered();
      final file = await BackupService(store).exportAll(includeSensitiveData: true);
      final other = await LiveStore.memory(cipher: const FakeCipher(), now: () => now);
      addTearDown(other.close);
      await other.accounts.remember('bilibili', uid: 3, name: 'Fake 3', cookie: 'SESSDATA=fake-3');
      await other.secrets.setCookie('bilibili', 'SESSDATA=fake-3');

      // A 3.x file (or one from an older 4.x): the cookie only.
      await BackupService(other).restoreAll({
        'backupVersion': 3,
        'cookie': {'bilibiliCookie': 'SESSDATA=fake-9', 'bilibiliUid': 0},
      });
      expect(other.secrets.cookieFor('bilibili'), 'SESSDATA=fake-9');
      expect([for (final account in other.accounts.of('bilibili')) account.uid], [3]);

      await BackupService(other).restoreAll(file);
      expect(other.secrets.cookieFor('bilibili'), 'SESSDATA=fake-2');
      expect(other.settings.get(Settings.bilibiliUid), 2);
      expect({for (final account in other.accounts.of('bilibili')) account.uid}, {1, 2, 3});
      expect(other.accounts.find('bilibili', 1)!.name, 'Fake One');
    });

    test('a broken entry in a file is skipped; the list is read as a restore reads it', () {
      final snapshot = LegacySnapshot.fromBackup({
        'backupVersion': 4,
        'cookie': {
          'bilibiliAccounts': [
            {'uid': 5, 'name': 'Fake 5', 'cookie': 'SESSDATA=fake-5', 'usedAt': 10},
            {'uid': 0, 'cookie': 'SESSDATA=fake-0'},
            {'uid': 6, 'cookie': ''},
            'not an entry',
          ],
        },
      });
      expect(snapshot.secrets, isNull);
      expect([for (final account in snapshot.savedAccounts!['bilibili']!) account.uid], [5]);
    });
  });
}
