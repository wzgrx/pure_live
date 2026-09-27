import 'package:drift/drift.dart';
import 'package:live_store/src/database/tables.dart';

part 'database.g.dart';

/// The v4 main database (spec/modules/store.md §3, ADR 0004).
///
/// Schema changes bump [schemaVersion], add a step to [migration] and dump the
/// schema with `dart run drift_dev make-migrations` (see the package README);
/// `test/drift/` verifies every dumped version.
@DriftDatabase(
  tables: [
    Rooms,
    Follows,
    FollowAreas,
    Tags,
    RoomTags,
    HistoryEntries,
    BlockRules,
    RoomPrefs,
    SettingEntries,
    MetaEntries,
  ],
)
final class StoreDatabase extends _$StoreDatabase {
  /// Opens the database on the query executor [e].
  new(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Version 1 is the first schema; later versions add their steps here.
      throw UnsupportedError('No migration from schema $from to $to');
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
