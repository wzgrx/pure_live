import 'package:live_store/src/database/database.dart';

/// Internal bookkeeping (store.md §3 `meta`): import ledger, device id,
/// first-run flags. Never backed up.
final class MetaStore {
  /// Wraps [_db].
  new(this._db);

  final StoreDatabase _db;

  /// Id of this device for LAN sync, kept from 3.x `remote_sync_device_id`.
  static const lanDeviceId = 'device.lanId';

  /// The value of [key], or null.
  Future<String?> get(String key) async =>
      (await (_db.select(_db.metaEntries)..where((row) => row.key.equals(key))).getSingleOrNull())?.value;

  /// Stores [value] under [key]; null removes it.
  Future<void> set(String key, String? value) async {
    if (value == null) {
      await (_db.delete(_db.metaEntries)..where((row) => row.key.equals(key))).go();
      return;
    }
    await _db.into(_db.metaEntries).insertOnConflictUpdate(MetaEntriesCompanion.insert(key: key, value: value));
  }
}
