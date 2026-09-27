import 'package:drift/drift.dart';
import 'package:live_store/src/database/database.steps.dart';
import 'package:live_store/src/database/tables.dart';

part 'database.g.dart';

/// The v4 main database (spec/modules/store.md §3, ADR 0004).
///
/// Schema changes bump [schemaVersion], add a step to [migration] and dump the
/// schema with `dart run drift_dev make-migrations` (see the package README);
/// `test/drift/` verifies every dumped version and step.
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
    IptvPlaylists,
    IptvChannels,
    IptvGuideSources,
    IptvGuideChannels,
    IptvProgrammes,
  ],
)
final class StoreDatabase extends _$StoreDatabase {
  /// Opens the database on the query executor [e].
  new(super.e);

  /// Version history: 1 the preview tables; 2 adds IPTV playlists, channels,
  /// guide sources, guide channels and programmes (spec/modules/iptv.md §7).
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: stepByStep(
      from1To2: (m, schema) async {
        await m.createTable(schema.iptvPlaylists);
        await m.createTable(schema.iptvChannels);
        await m.createTable(schema.iptvGuideSources);
        await m.createTable(schema.iptvGuideChannels);
        await m.createTable(schema.iptvProgrammes);
        await m.createIndex(schema.iptvChannelsName);
        await m.createIndex(schema.iptvChannelsGroup);
        await m.createIndex(schema.iptvProgrammesChannel);
        await m.createIndex(schema.iptvProgrammesStop);
      },
    ),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
