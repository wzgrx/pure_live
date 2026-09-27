import 'package:drift/drift.dart';

/// Every room the app remembers: followed, watched or tagged
/// (spec/modules/store.md §3). One row per `RoomRef`; `room_id` keeps its
/// case, and SQLite's default BINARY collation compares it case-sensitively.
@DataClassName('RoomRow')
class Rooms extends Table {
  /// Internal row id; never leaves the device.
  IntColumn get id => integer().autoIncrement()();

  /// Lower-case platform id.
  TextColumn get platform => text()();

  /// Room id as the platform spells it.
  TextColumn get roomId => text()();

  /// Streamer's display name.
  TextColumn get nick => text().withDefault(const Constant(''))();

  /// Last known broadcast title.
  TextColumn get title => text().withDefault(const Constant(''))();

  /// Streamer's avatar URL.
  TextColumn get avatar => text().nullable()();

  /// Last known cover URL.
  TextColumn get cover => text().nullable()();

  /// Last known area name.
  TextColumn get area => text().nullable()();

  /// The streamer's user id on the platform, when known.
  TextColumn get userId => text().nullable()();

  /// Concurrent viewers at the last refresh.
  IntColumn get onlineViewers => integer().nullable()();

  /// Popularity score at the last refresh.
  IntColumn get popularity => integer().nullable()();

  /// Cumulative viewers at the last refresh.
  IntColumn get totalViewers => integer().nullable()();

  /// Follower count, when known.
  IntColumn get followers => integer().nullable()();

  /// Last known state: `live`, `offline`, `replay` or `banned`; null means
  /// unknown. A cache only: the UI shows every follow as unknown at startup
  /// (store.md §6.4.10).
  TextColumn get lastStatus => text().nullable()();

  /// When the room was last seen live (UTC milliseconds).
  IntColumn get lastLiveAt => integer().nullable()();

  /// JSON object with rarely used fields (notice, introduction, IPTV data).
  TextColumn get extra => text().nullable()();

  /// When this row last changed (UTC milliseconds).
  IntColumn get updatedAt => integer()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {platform, roomId},
  ];
}

/// Followed rooms; at most one row per room.
@DataClassName('FollowRow')
class Follows extends Table {
  /// The followed room.
  IntColumn get room => integer().references(Rooms, #id, onDelete: KeyAction.cascade)();

  /// Custom order, ascending.
  IntColumn get sortOrder => integer()();

  /// When the room was followed (UTC milliseconds).
  IntColumn get followedAt => integer()();

  /// `user`, `import` or `backup`.
  TextColumn get source => text().withDefault(const Constant('user'))();

  @override
  Set<Column> get primaryKey => {room};
}

/// Followed areas (store.md §3).
@DataClassName('FollowAreaRow')
class FollowAreas extends Table {
  /// Internal row id.
  IntColumn get id => integer().autoIncrement()();

  /// Lower-case platform id.
  TextColumn get platform => text()();

  /// Area id namespace; only missevan uses one (store.md §2).
  TextColumn get namespace => text().withDefault(const Constant(''))();

  /// Area id, trimmed.
  TextColumn get areaId => text()();

  /// Area display name.
  TextColumn get areaName => text().withDefault(const Constant(''))();

  /// Parent category name.
  TextColumn get typeName => text().withDefault(const Constant(''))();

  /// Area icon URL.
  TextColumn get areaPic => text().nullable()();

  /// Short name.
  TextColumn get shortName => text().nullable()();

  /// Custom order, ascending.
  IntColumn get sortOrder => integer()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {platform, namespace, areaId},
  ];
}

/// User tags, shown as follow groups (spec/product.md F-FAV-05).
@DataClassName('TagRow')
class Tags extends Table {
  /// Tag id; ids from 3.x are kept.
  TextColumn get id => text()();

  /// Display name.
  TextColumn get name => text()();

  /// Trimmed, lower-cased name; names are unique regardless of case.
  TextColumn get nameFolded => text().unique()();

  /// Optional description.
  TextColumn get description => text().withDefault(const Constant(''))();

  /// Custom order, ascending.
  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Tag membership; the only source of truth for a room's tags.
@DataClassName('RoomTagRow')
class RoomTags extends Table {
  /// The tagged room.
  IntColumn get room => integer().references(Rooms, #id, onDelete: KeyAction.cascade)();

  /// The tag.
  TextColumn get tag => text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {room, tag};
}

/// Watch history; one row per room.
@DataClassName('HistoryRow')
class HistoryEntries extends Table {
  @override
  String get tableName => 'history';

  /// Insertion order; breaks ties and orders entries without a time.
  IntColumn get id => integer().autoIncrement()();

  /// The watched room.
  IntColumn get room => integer().unique().references(Rooms, #id, onDelete: KeyAction.cascade)();

  /// When the room was last watched (UTC milliseconds); null for 3.x entries
  /// recorded before the field existed.
  IntColumn get lastWatchedAt => integer().nullable()();
}

/// Danmaku block rules (store.md §3).
@DataClassName('BlockRuleRow')
class BlockRules extends Table {
  /// Internal row id.
  IntColumn get id => integer().autoIncrement()();

  /// `keyword` or `user`.
  TextColumn get kind => text()();

  /// The value as the user typed it (trimmed).
  TextColumn get value => text()();

  /// Trimmed, lower-cased value used for matching and uniqueness.
  TextColumn get valueFolded => text()();

  /// When the rule was added (UTC milliseconds).
  IntColumn get createdAt => integer()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {kind, valueFolded},
  ];
}

/// Per-room preferences such as volume (store.md §3).
@DataClassName('RoomPrefRow')
class RoomPrefs extends Table {
  /// The room.
  IntColumn get room => integer().references(Rooms, #id, onDelete: KeyAction.cascade)();

  /// Preference key, for example `volume`.
  TextColumn get key => text()();

  /// JSON value.
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {room, key};
}

/// Settings values; keys come from the settings registry (store.md §5).
@DataClassName('SettingRow')
class SettingEntries extends Table {
  @override
  String get tableName => 'settings';

  /// Registry id, for example `danmaku.speed`.
  TextColumn get key => text()();

  /// JSON value.
  TextColumn get value => text()();

  /// When the value last changed (UTC milliseconds).
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Internal bookkeeping: import ledger, device id, first-run flags.
@DataClassName('MetaRow')
class MetaEntries extends Table {
  @override
  String get tableName => 'meta';

  /// Entry key.
  TextColumn get key => text()();

  /// Entry value.
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
