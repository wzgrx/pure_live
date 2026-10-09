import 'dart:convert';

import 'package:drift/drift.dart' show QueryRow;
import 'package:live_store/src/database.dart';
import 'package:meta/meta.dart';

/// What a [LocalEvent] records (D08.1).
enum LocalEventKind {
  /// A local danmaku: [LocalEvent.text] is what it said.
  chat,

  /// A local gift: [LocalEvent.giftId], [LocalEvent.count] and what they
  /// cost in all in [LocalEvent.coins] (D08.4: one entry for a combo, its
  /// count and coins growing with each send).
  gift,

  /// Coins added: [LocalEvent.coins].
  recharge,

  /// A level reached: [LocalEvent.count] is the level (D08.3 writes it).
  level,

  /// A line of the history before D08.1 (`localInteraction.history`, a
  /// sentence in the language of its day): [LocalEvent.text] as it was.
  legacy;

  /// The kind named [name], or null.
  static LocalEventKind? byName(Object? name) {
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

/// One entry of the local interaction's history: data, not a sentence, so
/// it reads in the interface language of the day it is shown (D08.1 c1).
@immutable
final class LocalEvent {
  /// Creates an entry; [id] is given by the store.
  const new({
    required this.at,
    required this.kind,
    this.id,
    this.platform = '',
    this.roomId = '',
    this.roomName = '',
    this.text = '',
    this.giftId = '',
    this.count = 0,
    this.coins = 0,
    this.style,
  });

  /// The entry of a backup's [json], or null when it is not one.
  static LocalEvent? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = LocalEventKind.byName(json['kind']);
    final at = json['at'];
    if (kind == null || at is! num) return null;
    String text(String key) => json[key] is String ? json[key] as String : '';
    int number(String key) => json[key] is num ? (json[key] as num).toInt() : 0;
    return LocalEvent(
      id: json['id'] is num ? (json['id'] as num).toInt() : null,
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      kind: kind,
      platform: text('platform'),
      roomId: text('roomId'),
      roomName: text('roomName'),
      text: text('text'),
      giftId: text('giftId'),
      count: number('count'),
      coins: number('coins'),
      style: json['style'] is String ? json['style'] as String : null,
    );
  }

  /// The store's id; null until stored.
  final int? id;

  /// When it happened.
  final DateTime at;

  /// What it is.
  final LocalEventKind kind;

  /// The room's platform; empty outside a room (coins added on the settings
  /// page).
  final String platform;

  /// The room's id; empty outside a room.
  final String roomId;

  /// The room's name when it happened (the streamer's name, else the
  /// title); not updated afterwards.
  final String roomName;

  /// What a local danmaku said; a legacy line's sentence.
  final String text;

  /// The gift's id (`LocalGift.id`).
  final String giftId;

  /// How many gifts; the level of a [LocalEventKind.level].
  final int count;

  /// Coins added, or what the gifts cost in all.
  final int coins;

  /// The local danmaku's style when it was sent (JSON of the
  /// `localInteraction.danmaku*` settings), or null.
  final String? style;

  /// Whether it happened in a room.
  bool get inRoom => platform.isNotEmpty && roomId.isNotEmpty;

  /// A copy with [count] and [coins] (D08.4: a combo's entry grows).
  LocalEvent withCount(int count, int coins) => LocalEvent(
    id: id,
    at: at,
    kind: kind,
    platform: platform,
    roomId: roomId,
    roomName: roomName,
    text: text,
    giftId: giftId,
    count: count,
    coins: coins,
    style: style,
  );

  /// A copy stored under [id].
  LocalEvent withId(int id) => LocalEvent(
    id: id,
    at: at,
    kind: kind,
    platform: platform,
    roomId: roomId,
    roomName: roomName,
    text: text,
    giftId: giftId,
    count: count,
    coins: coins,
    style: style,
  );

  /// The backup's form.
  Map<String, Object?> toJson() => {
    'id': ?id,
    'at': at.millisecondsSinceEpoch,
    'kind': kind.name,
    if (platform.isNotEmpty) 'platform': platform,
    if (roomId.isNotEmpty) 'roomId': roomId,
    if (roomName.isNotEmpty) 'roomName': roomName,
    if (text.isNotEmpty) 'text': text,
    if (giftId.isNotEmpty) 'giftId': giftId,
    if (count != 0) 'count': count,
    if (coins != 0) 'coins': coins,
    'style': ?style,
  };

  @override
  bool operator ==(Object other) => other is LocalEvent && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;

  @override
  String toString() => 'LocalEvent(${jsonEncode(toJson())})';
}

/// The local interaction's history (D08.1, table `local_events`): newest
/// first, at most [limit] entries, the oldest going first.
final class LocalEventStore {
  /// Creates the store over `db`.
  new(this._db);

  final StoreDatabase _db;

  static const Set<String> _tables = {StoreTables.localEvents};

  /// The most entries kept.
  static const int limit = 2000;

  /// The `meta` key set once `localInteraction.history` has been taken in
  /// ([adoptLegacyHistory]).
  static const String legacyAdoptedKey = 'localEvents.legacyAdopted';

  /// The backup section (`{"localEvents": {"events": [...]}}`, new in v4;
  /// 3.x ignores it).
  static const String backupSection = 'localEvents';

  static const String _columns = 'id, at, kind, platform, room_id, room_name, text, gift_id, count, coins, style';

  static LocalEvent? _read(QueryRow row) {
    final kind = LocalEventKind.byName(row.read<String>('kind'));
    if (kind == null) return null;
    return LocalEvent(
      id: row.read<int>('id'),
      at: DateTime.fromMillisecondsSinceEpoch(row.read<int>('at')),
      kind: kind,
      platform: row.read<String>('platform'),
      roomId: row.read<String>('room_id'),
      roomName: row.read<String>('room_name'),
      text: row.read<String>('text'),
      giftId: row.read<String>('gift_id'),
      count: row.read<int>('count'),
      coins: row.read<int>('coins'),
      style: row.readNullable<String>('style'),
    );
  }

  /// Every entry, newest first.
  Future<List<LocalEvent>> all() async => [
    for (final row in await _db.rows('SELECT $_columns FROM local_events ORDER BY at DESC, id DESC')) ?_read(row),
  ];

  /// [all], again after every change.
  Stream<List<LocalEvent>> watch() => _db.watch(_tables, all);

  /// The local danmaku sent in [platform]'s room [roomId] at [since] or
  /// later and before [before], the newest [count] of them, oldest first
  /// (D08.1 c6: what a room shows again when it is entered).
  Future<List<LocalEvent>> recentChats({
    required String platform,
    required String roomId,
    required DateTime since,
    required DateTime before,
    required int count,
  }) async {
    final rows = await _db.rows(
      'SELECT $_columns FROM local_events WHERE kind = ? AND platform = ? AND room_id = ? AND at >= ? AND at < ? '
      'ORDER BY at DESC, id DESC LIMIT ?',
      [LocalEventKind.chat.name, platform, roomId, since.millisecondsSinceEpoch, before.millisecondsSinceEpoch, count],
    );
    return [for (final row in rows.reversed) ?_read(row)];
  }

  Future<int> _insert(LocalEvent event) async {
    final id = event.id;
    if (id != null) {
      final taken = await _db.rows('SELECT 1 FROM local_events WHERE id = ?', [id]);
      if (taken.isEmpty) {
        await _db.run('INSERT INTO local_events ($_columns) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [
          id,
          ..._values(event),
        ]);
        return id;
      }
    }
    await _db.run(
      'INSERT INTO local_events (at, kind, platform, room_id, room_name, text, gift_id, count, coins, style) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      _values(event),
    );
    return (await _db.rows('SELECT last_insert_rowid() AS id')).single.read<int>('id');
  }

  static List<Object?> _values(LocalEvent event) => [
    event.at.millisecondsSinceEpoch,
    event.kind.name,
    event.platform,
    event.roomId,
    event.roomName,
    event.text,
    event.giftId,
    event.count,
    event.coins,
    event.style,
  ];

  Future<void> _trim() => _db.run(
    'DELETE FROM local_events WHERE id NOT IN (SELECT id FROM local_events ORDER BY at DESC, id DESC LIMIT ?)',
    [limit],
  );

  /// Stores [event] (its own [LocalEvent.id] when that is free, a new one
  /// otherwise), dropping the oldest beyond [limit]; returns the id.
  Future<int> add(LocalEvent event) => _db.write(_tables, () async {
    final id = await _insert(event);
    await _trim();
    return id;
  });

  /// Stores [events] as [add] does (an undone clear: they keep their ids).
  Future<void> addAll(Iterable<LocalEvent> events) => _db.write(_tables, () async {
    for (final event in events) {
      await _insert(event);
    }
    await _trim();
  });

  /// Writes [count] and [coins] into the entry [id] (D08.4: a combo's entry
  /// grows with each send); nothing when it is gone (cleared meanwhile).
  Future<void> updateCount(int id, {required int count, required int coins}) => _db.write(
    _tables,
    () => _db.run('UPDATE local_events SET count = ?, coins = ? WHERE id = ?', [count, coins, id]),
  );

  /// Removes every entry.
  Future<void> clear() => _db.write(_tables, () => _db.run('DELETE FROM local_events'));

  /// Replaces every entry with [events] (a backup restore): the newest
  /// [limit] of them. Also counts as having taken in the old history
  /// ([legacyAdoptedKey]): the file's entries already hold it.
  Future<void> replaceAll(Iterable<LocalEvent> events) => _db.write({..._tables, StoreTables.meta}, () async {
    await _db.run('DELETE FROM local_events');
    for (final event in events) {
      await _insert(event);
    }
    await _trim();
    await _db.run('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)', [legacyAdoptedKey, '1']);
  });

  /// Takes in the history kept before D08.1 (`localInteraction.history`,
  /// newest first) once (D08.1 c3): each line becomes a
  /// [LocalEventKind.legacy] entry, older than [now] and than every entry
  /// there is, in the same order. The setting itself is left as it is
  /// (D-018). Later calls do nothing; true when this one took them in.
  Future<bool> adoptLegacyHistory(List<String> lines, {DateTime? now}) =>
      _db.write({..._tables, StoreTables.meta}, () async {
        final done = await _db.rows('SELECT 1 FROM meta WHERE key = ?', [legacyAdoptedKey]);
        if (done.isNotEmpty) return false;
        // Older than every entry there is (they came after the lines).
        final oldest = (await _db.rows('SELECT MIN(at) AS at FROM local_events')).single.readNullable<int>('at');
        final time = (now ?? DateTime.now()).millisecondsSinceEpoch;
        final newest = oldest != null && oldest < time ? oldest : time;
        final kept = [
          for (final line in lines)
            if (line.trim().isNotEmpty) line,
        ];
        for (var i = 0; i < kept.length; i++) {
          await _insert(
            LocalEvent(
              at: DateTime.fromMillisecondsSinceEpoch(newest - 1 - i),
              kind: LocalEventKind.legacy,
              text: kept[i],
            ),
          );
        }
        await _trim();
        await _db.run('INSERT INTO meta (key, value) VALUES (?, ?)', [legacyAdoptedKey, '${kept.length}']);
        return true;
      });

  /// The entries of a backup [json]'s [backupSection] (newest first, as
  /// written); null when the file has none.
  static List<LocalEvent>? inBackup(Map<String, Object?> json) {
    final section = json[backupSection];
    if (section is! Map || section['events'] is! List) return null;
    return [for (final entry in section['events'] as List) ?LocalEvent.fromJson(entry)];
  }
}
