import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:live_store/src/backup/import_plan.dart';
import 'package:live_store/src/backup/import_report.dart';
import 'package:live_store/src/backup/legacy_format.dart';
import 'package:live_store/src/backup/record_tasks.dart';
import 'package:live_store/src/backup/v4_format.dart';
import 'package:live_store/src/database/database.dart';
import 'package:live_store/src/follow_areas.dart';
import 'package:live_store/src/follows.dart';
import 'package:live_store/src/iptv.dart';
import 'package:live_store/src/live_store.dart';
import 'package:live_store/src/rooms.dart';
import 'package:live_store/src/secrets/secret_store.dart';
import 'package:live_store/src/settings/registry.dart';
import 'package:live_store/src/settings/setting.dart';
import 'package:path/path.dart' as p;

/// Which restore entry the user chose (store.md §7.2).
enum RestoreMode {
  /// Replace every section the file contains; other data stays.
  full,

  /// Replace only follows and followed areas.
  follows,
}

/// Backup export and restore (store.md §7).
///
/// Restores parse and validate the whole file into an [ImportPlan] first,
/// then write it in one database transaction: a bad file writes nothing
/// (REG-STORE-009). Only one restore runs at a time.
final class BackupService {
  /// Backs up [_store]; [secrets] is needed to export or restore accounts,
  /// [recordTasks] to export or restore recording tasks (they live in the
  /// recorder's own file). [platform] is the platform family for
  /// device-scope settings (default: the running operating system).
  new(
    this._store, {
    this.secrets,
    this.recordTasks,
    this.appVersion = '4.0.0',
    String? platform,
    this.kdfIterations = 600000,
  }) : platform = platform ?? Platform.operatingSystem;

  final LiveStore _store;

  /// Secret store for accounts; without it secrets are neither exported nor
  /// restored.
  final SecretStore? secrets;

  /// App version written into backups.
  final String appVersion;

  /// Platform family written into backups and compared on restore.
  final String platform;

  /// PBKDF2 iterations for new encrypted secrets sections.
  final int kdfIterations;

  /// The recorder's tasks; without it the `recordTasks` section is neither
  /// exported nor restored.
  final RecordTaskBackup? recordTasks;

  bool _restoring = false;

  /// Builds a v4 backup document. Secrets are included only when
  /// [passphrase] is given (store.md §7.3).
  Future<Map<String, Object?>> export({BackupScope scope = BackupScope.full, String? passphrase, DateTime? now}) =>
      V4Format.export(
        _store,
        scope: scope,
        appVersion: appVersion,
        platform: platform,
        createdAt: now ?? DateTime.now(),
        secrets: secrets,
        passphrase: passphrase,
        iterations: kdfIterations,
        recordTasks: recordTasks,
      );

  /// Writes a v4 backup into [directory] and returns the file.
  Future<File> exportToDirectory(
    Directory directory, {
    BackupScope scope = BackupScope.full,
    String? passphrase,
    DateTime? now,
  }) async {
    final time = now ?? DateTime.now();
    final document = await export(scope: scope, passphrase: passphrase, now: time);
    final file = File(p.join(directory.path, fileName(scope, time)));
    await writeAtomically(file, const JsonEncoder.withIndent('  ').convert(document));
    return file;
  }

  /// `purelive_v4_<yyyy-MM-ddTHH_mm_ss>_<uuid>.json`, with `follows_` after
  /// `v4_` for follows-only backups (store.md §7.1).
  static String fileName(BackupScope scope, DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    final t = time.toLocal();
    final stamp = '${t.year}-${two(t.month)}-${two(t.day)}T${two(t.hour)}_${two(t.minute)}_${two(t.second)}';
    return 'purelive_v4_${scope == BackupScope.follows ? 'follows_' : ''}${stamp}_${_uuid()}.json';
  }

  static String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// Writes [text] to `<file>.part`, keeps the old file as `<file>.previous`
  /// until the new one is in place, then removes it (store.md §7.1).
  static Future<void> writeAtomically(File file, String text) async {
    final staged = File('${file.path}.part');
    final previous = File('${file.path}.previous');
    await file.parent.create(recursive: true);
    if (previous.existsSync()) {
      if (file.existsSync()) {
        await previous.delete();
      } else {
        await previous.rename(file.path);
      }
    }
    try {
      await staged.writeAsString(text, flush: true);
      final hadFile = file.existsSync();
      if (hadFile) await file.rename(previous.path);
      try {
        await staged.rename(file.path);
      } on Object {
        if (hadFile && previous.existsSync() && !file.existsSync()) await previous.rename(file.path);
        rethrow;
      }
    } on Object {
      if (staged.existsSync()) await staged.delete();
      rethrow;
    }
    if (previous.existsSync()) {
      try {
        await previous.delete();
      } on FileSystemException {
        // The new backup is complete; the next write retries the cleanup.
      }
    }
  }

  /// Parses and validates [document] (decoded JSON of any supported format)
  /// without writing. Throws [FormatException] for an unreadable or wrong
  /// file and [BackupTooNewException] for a newer format.
  Future<ImportPlan> plan(Object? document, {RestoreMode mode = RestoreMode.full, String? passphrase}) async {
    if (document is! Map<String, Object?>) throw const FormatException('Backup is not a JSON object');
    final followsOnly = mode == RestoreMode.follows;
    final localLimit = _store.settings.get(Settings.historyLimit);
    ImportPlan plan;
    if (document['type'] == 'pure_live_sync') {
      // LAN sync packages (store.md §7.4, §9): v1 wraps a v3 export, v2 a v4
      // document.
      final version = document['version'];
      final inner = version == 2 ? document['backup'] : (version == 1 ? document['settings'] : null);
      if (inner is! Map<String, Object?>) throw const FormatException('Unsupported sync package');
      return await this.plan(inner, mode: mode, passphrase: passphrase);
    } else if (V4Format.recognizes(document)) {
      plan = await V4Format.parse(
        document,
        followsOnly: followsOnly,
        localPlatform: platform,
        localHistoryLimit: localLimit,
        passphrase: passphrase,
      );
    } else if (LegacyFormat.recognizes(document)) {
      plan = LegacyFormat.parse(
        document,
        followsOnly: followsOnly,
        now: DateTime.now().toUtc(),
        localHistoryLimit: localLimit,
      );
    } else {
      throw const FormatException('Not a Pure Live backup');
    }
    if (!followsOnly && plan.followsOnlySource) {
      throw const FormatException('Follows-only backup: use "restore follows"');
    }
    if (followsOnly) plan.restrictToFollows();
    if (recordTasks == null && plan.recordTasks != null) {
      plan
        ..recordTasks = null
        ..report.note('recordTasks', 'unsupported');
    }
    if (secrets == null && plan.secrets != null) {
      plan
        ..secrets = null
        ..report.secretsSkipped = true;
    }
    return plan;
  }

  /// Restores [document]; see [plan] for the errors. Nothing is written
  /// when parsing fails. Throws [StateError] while another restore runs.
  Future<ImportReport> restore(Object? document, {RestoreMode mode = RestoreMode.full, String? passphrase}) =>
      _exclusive(() async {
        final plan = await this.plan(document, mode: mode, passphrase: passphrase);
        await _apply(plan);
        return plan.report;
      });

  /// Writes a [plan] from [plan()] (for example after the user confirmed a
  /// preview) in one transaction, then its secrets. Throws [StateError]
  /// while another restore runs.
  Future<ImportReport> apply(ImportPlan plan) => _exclusive(() async {
    await _apply(plan);
    return plan.report;
  });

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (_restoring) throw StateError('A restore is already running');
    _restoring = true;
    try {
      return await action();
    } finally {
      _restoring = false;
    }
  }

  /// Reads a backup file and restores it.
  Future<ImportReport> restoreFile(File file, {RestoreMode mode = RestoreMode.full, String? passphrase}) async {
    final Object? document;
    try {
      document = jsonDecode(await file.readAsString());
    } on FormatException {
      throw const FormatException('Backup is not valid JSON');
    }
    return await restore(document, mode: mode, passphrase: passphrase);
  }

  Future<void> _apply(ImportPlan plan) async {
    final db = _store.database;
    final source = plan.report.format == 'v4' ? FollowSource.backup : FollowSource.import;
    await db.transaction(() async {
      final now = DateTime.now().toUtc();
      if (plan.settings case final settings?) await _applySettings(db, plan, settings, now);
      if (plan.follows case final follows?) {
        await db.delete(db.follows).go();
        for (final (index, follow) in follows.indexed) {
          final id = await RoomRows.upsert(
            db,
            follow.room.snapshot,
            now: now,
            extra: follow.room.extra,
            seenNow: false,
          );
          await db
              .into(db.follows)
              .insert(
                FollowsCompanion.insert(
                  room: Value(id),
                  sortOrder: index,
                  followedAt: follow.followedAt.millisecondsSinceEpoch,
                  source: Value(source.name),
                ),
              );
        }
      }
      if (plan.followAreas case final areas?) {
        await db.delete(db.followAreas).go();
        for (final (index, area) in areas.indexed) {
          await db.into(db.followAreas).insert(FollowAreaStore.companion(area, order: index));
        }
      }
      if (plan.tags case final tags?) {
        final kept = plan.roomTags == null ? await db.select(db.roomTags).get() : const <RoomTagRow>[];
        await db.delete(db.tags).go();
        for (final tag in tags) {
          await db
              .into(db.tags)
              .insert(
                TagsCompanion.insert(
                  id: tag.id,
                  name: tag.name,
                  nameFolded: tag.name.trim().toLowerCase(),
                  description: Value(tag.description),
                  sortOrder: tag.order,
                ),
              );
        }
        final ids = {for (final tag in tags) tag.id};
        for (final row in kept) {
          if (ids.contains(row.tag)) await db.into(db.roomTags).insert(row);
        }
      }
      if (plan.roomTags case final membership?) {
        await db.delete(db.roomTags).go();
        final ids = {for (final row in await db.select(db.tags).get()) row.id};
        for (final MapEntry(key: ref, value: tagIds) in membership.entries) {
          final room = await RoomRows.ensure(db, ref);
          for (final tag in tagIds.where(ids.contains)) {
            await db.into(db.roomTags).insert(RoomTagsCompanion.insert(room: room, tag: tag));
          }
        }
      }
      if (plan.history case final history?) {
        await db.delete(db.historyEntries).go();
        for (final entry in history) {
          final id = await RoomRows.upsert(db, entry.room.snapshot, now: now, extra: entry.room.extra, seenNow: false);
          await db
              .into(db.historyEntries)
              .insert(
                HistoryEntriesCompanion.insert(
                  room: id,
                  lastWatchedAt: Value(entry.lastWatchedAt?.millisecondsSinceEpoch),
                ),
              );
        }
      }
      if (plan.blockRules case final rules?) {
        for (final MapEntry(key: kind, value: list) in rules.entries) {
          await (db.delete(db.blockRules)..where((row) => row.kind.equals(kind.name))).go();
          for (final rule in list) {
            await db
                .into(db.blockRules)
                .insert(
                  BlockRulesCompanion.insert(
                    kind: kind.name,
                    value: rule.value,
                    valueFolded: rule.folded,
                    createdAt: rule.createdAt.millisecondsSinceEpoch,
                  ),
                  mode: InsertMode.insertOrIgnore,
                );
          }
        }
      }
      if (plan.roomPrefs case final prefs?) {
        await db.delete(db.roomPrefs).go();
        for (final pref in prefs) {
          final room = await RoomRows.ensure(db, pref.ref);
          await db
              .into(db.roomPrefs)
              .insertOnConflictUpdate(
                RoomPrefsCompanion.insert(room: room, key: pref.key, value: jsonEncode(pref.value)),
              );
        }
      }
      if (plan.iptv case final iptv?) await _applyIptv(db, iptv, now);
    });
    await _store.settings.load();
    await _store.history.trim();
    final store = secrets;
    if (plan.secrets case final values? when store != null && values.isNotEmpty) {
      await store.writeAll(values);
      plan.report.written('secrets', values.length);
    }
    // Outside the transaction, like secrets: the recorder keeps its own file.
    final recorder = recordTasks;
    if (plan.recordTasks case final tasks? when recorder != null) {
      try {
        plan.report.written('recordTasks', await recorder.restoreTasks(tasks));
      } on Object catch (error) {
        plan.report.note('recordTasks', 'writeFailed', error.runtimeType.toString());
      }
    }
  }

  /// Replaces the URL playlists and guide sources; file-imported ones stay
  /// first. Restored ones have no entries until their first sync.
  static Future<void> _applyIptv(StoreDatabase db, PlannedIptv iptv, DateTime now) async {
    for (final playlist in await db.select(db.iptvPlaylists).get()) {
      if (isRemoteSource(playlist.source)) {
        await (db.delete(db.iptvPlaylists)..where((row) => row.id.equals(playlist.id))).go();
      }
    }
    var order = (await db.select(db.iptvPlaylists).get()).length;
    for (final playlist in iptv.playlists) {
      await db
          .into(db.iptvPlaylists)
          .insert(
            IptvPlaylistsCompanion.insert(
              name: playlist.name,
              source: playlist.url,
              userAgent: Value(playlist.userAgent),
              autoSync: Value(playlist.autoSync),
              sortOrder: order++,
              createdAt: now.millisecondsSinceEpoch,
            ),
          );
    }
    for (final guide in await db.select(db.iptvGuideSources).get()) {
      if (isRemoteSource(guide.source)) {
        await (db.delete(db.iptvGuideSources)..where((row) => row.id.equals(guide.id))).go();
      }
    }
    final kept = await db.select(db.iptvGuideSources).get();
    final select = iptv.guides.any((guide) => guide.selected);
    if (select) await db.update(db.iptvGuideSources).write(const IptvGuideSourcesCompanion(selected: Value(false)));
    order = kept.length;
    var selected = !select && kept.any((guide) => guide.selected);
    for (final guide in iptv.guides) {
      final pick = !selected && (guide.selected || !select);
      selected = selected || pick;
      await db
          .into(db.iptvGuideSources)
          .insert(
            IptvGuideSourcesCompanion.insert(
              name: guide.name,
              source: guide.url,
              autoSync: Value(guide.autoSync),
              selected: Value(pick),
              sortOrder: order++,
              createdAt: now.millisecondsSinceEpoch,
            ),
          );
    }
  }

  Future<void> _applySettings(StoreDatabase db, ImportPlan plan, Map<String, Object> settings, DateTime now) async {
    if (plan.replaceSettings) {
      final scopes = {SettingScope.synced, if (plan.includeDeviceSettings) SettingScope.device};
      final ids = [
        for (final setting in Settings.all)
          if (scopes.contains(setting.scope)) setting.id,
      ];
      await (db.delete(db.settingEntries)..where((row) => row.key.isIn(ids))).go();
    }
    for (final MapEntry(key: id, :value) in settings.entries) {
      final setting = Settings.byId(id)!;
      await db
          .into(db.settingEntries)
          .insertOnConflictUpdate(
            SettingEntriesCompanion.insert(
              key: id,
              value: jsonEncode(setting.encode(value)),
              updatedAt: now.millisecondsSinceEpoch,
            ),
          );
    }
  }
}
