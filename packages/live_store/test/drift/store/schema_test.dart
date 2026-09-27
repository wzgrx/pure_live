import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:live_store/src/database/database.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';

// Schema verification (docs/adr/0004): every dumped schema version under
// drift_schemas/store/ must match what the database class creates and
// migrates to. After a schema change run `dart run drift_dev make-migrations`
// in packages/live_store (README) and add a migration test per step.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('the current schema version has a dump', () async {
    final db = StoreDatabase(await verifier.startAt(GeneratedHelper.versions.last));
    expect(db.schemaVersion, GeneratedHelper.versions.last);
    await db.close();
  });

  test('a new database matches the dumped schema', () async {
    final db = StoreDatabase(await verifier.startAt(1));
    await verifier.migrateAndValidate(db, 1);
    await db.close();
  });
}
