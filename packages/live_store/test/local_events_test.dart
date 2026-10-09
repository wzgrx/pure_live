// The local interaction's history (docs/D-弹幕/D08-本地互动/D08.1-结构化的本地历史):
// the table, the move from schema 1, the old lines taken in once, the 2000
// limit and the backup.
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

DateTime _at(int minutes) => DateTime(2026, 10, 9, 20).add(Duration(minutes: minutes));

LocalEvent _chat(String text, {int minutes = 0, String roomId = '6', String platform = 'bilibili'}) => LocalEvent(
  at: _at(minutes),
  kind: LocalEventKind.chat,
  platform: platform,
  roomId: roomId,
  roomName: '主播',
  text: text,
  style: '{"localInteraction.danmakuColor":4294967295}',
);

void main() {
  test('a new database has the table (schema 2); entries newest first, ids never reused', () async {
    final store = await memoryStore();
    addTearDown(store.close);
    expect(store.database.schemaVersion, 2);
    final events = store.localEvents;
    expect(await events.all(), isEmpty);
    final first = await events.add(_chat('一', minutes: 1));
    final gift = await events.add(
      LocalEvent(
        at: _at(2),
        kind: LocalEventKind.gift,
        platform: 'bilibili',
        roomId: '6',
        giftId: 'bili_snack',
        count: 1,
        coins: 10,
      ),
    );
    await events.add(LocalEvent(at: _at(3), kind: LocalEventKind.recharge, coins: 500));
    final all = await events.all();
    expect([for (final e in all) e.kind], [LocalEventKind.recharge, LocalEventKind.gift, LocalEventKind.chat]);
    expect(all.last, _chat('一', minutes: 1).withId(first));
    expect(all[1].id, gift);
    expect(all.first.inRoom, isFalse);

    // A clear and its undo: the rows come back under their own ids; a row
    // added in between gets a new one.
    await events.clear();
    expect(await events.all(), isEmpty);
    final between = await events.add(_chat('二', minutes: 4));
    expect(between, greaterThan(gift + 1), reason: 'AUTOINCREMENT: no id comes back');
    await events.addAll(all);
    expect(
      [for (final e in await events.all()) e.id],
      [
        between,
        ...[for (final e in all) e.id],
      ],
    );
  });

  test("D08.4: a combo's entry grows in place; a cleared one stays gone", () async {
    final store = await memoryStore();
    addTearDown(store.close);
    final events = store.localEvents;
    final gift = LocalEvent(
      at: _at(1),
      kind: LocalEventKind.gift,
      platform: 'bilibili',
      roomId: '6',
      giftId: 'bili_snack',
      count: 1,
      coins: 10,
    );
    final id = await events.add(gift);
    await events.add(_chat('之后', minutes: 2));
    await events.updateCount(id, count: 5, coins: 50);
    final all = await events.all();
    expect(all, hasLength(2), reason: 'one entry, not five');
    expect(all.last, gift.withCount(5, 50).withId(id), reason: 'its time and place stay');
    await events.clear();
    await events.updateCount(id, count: 6, coins: 60);
    expect(await events.all(), isEmpty);
  });

  test('at most 2000: the oldest go first', () async {
    final store = await memoryStore();
    addTearDown(store.close);
    await store.localEvents.addAll([for (var i = 0; i < LocalEventStore.limit + 5; i++) _chat('$i', minutes: i)]);
    final all = await store.localEvents.all();
    expect(all, hasLength(2000));
    expect(all.first.text, '2004');
    expect(all.last.text, '5');
    await store.localEvents.add(_chat('new', minutes: 5000));
    final after = await store.localEvents.all();
    expect((after.length, after.first.text, after.last.text), (2000, 'new', '6'));
  });

  test("what a room shows again: this room's danmaku in the window, the newest 20, oldest first", () async {
    final store = await memoryStore();
    addTearDown(store.close);
    await store.localEvents.addAll([
      for (var i = 0; i < 25; i++) _chat('c$i', minutes: i),
      _chat('other room', minutes: 3, roomId: '7'),
      _chat('other site', minutes: 3, platform: 'douyu'),
      LocalEvent(at: _at(4), kind: LocalEventKind.gift, platform: 'bilibili', roomId: '6', giftId: 'bili_snack'),
      _chat('too late', minutes: 40),
    ]);
    final shown = await store.localEvents.recentChats(
      platform: 'bilibili',
      roomId: '6',
      since: _at(2),
      before: _at(30),
      count: 20,
    );
    expect([for (final e in shown) e.text], [for (var i = 5; i < 25; i++) 'c$i']);
    final few = await store.localEvents.recentChats(
      platform: 'bilibili',
      roomId: '6',
      since: _at(2),
      before: _at(30),
      count: 3,
    );
    expect([for (final e in few) e.text], ['c22', 'c23', 'c24']);
  });

  test('a 4.0.0 database (schema 1, a real file) moves to 2; nothing in it is lost', () async {
    final temp = await Directory.systemTemp.createTemp('live_store_v1_');
    addTearDown(() => temp.delete(recursive: true));
    await File(p.join('test', 'fixtures', 'store_v1.db')).copy(p.join(temp.path, LiveStore.fileName));
    final store = await LiveStore.open(temp, cipher: const FakeCipher());
    final lines = store.settings.get(Settings.localInteractionHistory);
    expect(lines, ['增加本地体验币 +500', '🌶️ 📺 舰队等级 · 听众 · Pure Live 送出 辣条 ×1', '增加本地体验币 +2000']);
    expect(store.settings.get(Settings.localInteractionCoins), 2490);
    expect([for (final room in await store.follows.all()) room.identityKey], ['bilibili:6']);
    expect(await store.localEvents.all(), isEmpty, reason: 'the new table is there');

    // c3: the old lines become legacy entries once, in their order; the key
    // stays as it was (D-018).
    final now = DateTime(2026, 10, 9, 21);
    expect(await store.localEvents.adoptLegacyHistory(lines, now: now), isTrue);
    final legacy = await store.localEvents.all();
    expect([for (final e in legacy) e.text], lines);
    expect(legacy.every((e) => e.kind == LocalEventKind.legacy && e.at.isBefore(now)), isTrue);
    expect(await store.localEvents.adoptLegacyHistory(['again'], now: now), isFalse);
    expect(await store.localEvents.all(), legacy);
    expect(await store.meta.get(LocalEventStore.legacyAdoptedKey), '3');
    await store.close();

    // Opened again: still schema 2, the entries and the key still there.
    final again = await LiveStore.open(temp, cipher: const FakeCipher());
    addTearDown(again.close);
    expect(await again.localEvents.all(), legacy);
    expect(again.settings.get(Settings.localInteractionHistory), lines);
    final version = await again.database.rows('PRAGMA user_version');
    expect(version.single.read<int>('user_version'), 2);
  });

  test('backup: the entries travel in "localEvents" and come back; no section without entries', () async {
    final store = await memoryStore();
    addTearDown(store.close);
    final empty = await BackupService(store).exportAll();
    expect(empty.containsKey(LocalEventStore.backupSection), isFalse);

    await store.localEvents.addAll([
      _chat('晚上好', minutes: 1),
      LocalEvent(
        at: _at(2),
        kind: LocalEventKind.gift,
        platform: 'bilibili',
        roomId: '6',
        roomName: '主播',
        giftId: 'bili_snack',
        count: 1,
        coins: 10,
      ),
      LocalEvent(at: _at(0), kind: LocalEventKind.legacy, text: '增加本地体验币 +500'),
    ]);
    final file = await BackupService(store).exportAll();
    final section = file[LocalEventStore.backupSection]! as Map;
    expect((section['events']! as List).first, containsPair('kind', 'gift'));
    final stored = await store.localEvents.all();
    expect(LocalEventStore.inBackup(file), stored);

    final other = await memoryStore();
    addTearDown(other.close);
    await other.localEvents.add(_chat('replaced', minutes: 9));
    await BackupService(other).restoreAll(file);
    expect(
      [for (final e in await other.localEvents.all()) e.toJson()..remove('id')],
      [for (final e in stored) e.toJson()..remove('id')],
    );
    // The file held the old lines already: they are not taken in again.
    expect(await other.localEvents.adoptLegacyHistory(['增加本地体验币 +500']), isFalse);

    // A file without the section (3.x, an empty history) leaves them.
    await BackupService(other).restoreAll(empty);
    expect(await other.localEvents.all(), hasLength(3));
  });

  test("a backup's entries are read with care", () {
    expect(LocalEventStore.inBackup({'localEvents': 'x'}), isNull);
    expect(LocalEventStore.inBackup({}), isNull);
    final events = LocalEventStore.inBackup({
      'localEvents': {
        'events': [
          {'at': 1, 'kind': 'chat', 'text': 'a', 'count': 2.0},
          {'at': 'x', 'kind': 'chat'},
          {'at': 1, 'kind': 'bogus'},
          'nope',
        ],
      },
    })!;
    expect(events, [
      LocalEvent(at: DateTime.fromMillisecondsSinceEpoch(1), kind: LocalEventKind.chat, text: 'a', count: 2),
    ]);
  });

  test('the platform name is kept as given (rooms are matched by platform and id)', () {
    final event = LocalEvent(at: _at(0), kind: LocalEventKind.chat, platform: SiteIds.bilibili, roomId: '6');
    expect(LocalEvent.fromJson(event.toJson()), event);
  });
}
