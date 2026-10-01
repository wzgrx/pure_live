import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_store/src/block_lists.dart';
import 'package:live_store/src/legacy/hive_reader.dart';
import 'package:live_store/src/legacy/legacy_rules.dart';
import 'package:live_store/src/legacy/legacy_snapshot.dart';
import 'package:live_store/src/live_store.dart';
import 'package:live_store/src/rooms.dart';
import 'package:live_store/src/settings/setting.dart';
import 'package:live_store/src/settings/settings.dart';
import 'package:live_store/src/webdav.dart';
import 'package:path/path.dart' as p;

/// Where 3.x left its settings box (app_path_manager.dart at v3.2.11).
///
/// The app (M12) passes the platform folders; this only builds and checks
/// paths, and reads the Windows relocation ledger. Registry lookups
/// (installed copies under other folders) are the app's: it passes their
/// install folders as [windows]' `installDirectories`.
abstract final class LegacyLocations {
  /// The box name 3.x used.
  static const boxFile = 'app_settings.hive';

  /// Android: `<documents>/PURE_LIVE/HIVE_DB/app_settings.hive`
  /// (`getApplicationDocumentsDirectory`, which is `app_flutter`).
  static List<String> android({required String documentsDirectory}) => [
    p.join(documentsDirectory, 'PURE_LIVE', 'HIVE_DB', boxFile),
  ];

  /// Windows: the portable root `<exe folder>\AppData`, its fallback
  /// `<support>\PURE_LIVE`, the older roots 3.x itself migrated from
  /// (documents and support folders), sibling `pure_live` installs and
  /// [installDirectories], each followed through its
  /// `previous_install_locations.txt` (up to 32 roots). Every root is checked
  /// for `app_settings.hive` and `HIVE_DB\app_settings.hive`; only existing
  /// files are returned, without duplicates (case-insensitive).
  static Future<List<String>> windows({
    required String executableDirectory,
    required String supportDirectory,
    required String documentsDirectory,
    String? cacheDirectory,
    Iterable<String> installDirectories = const [],
  }) async {
    final roots = <String>[
      p.join(executableDirectory, 'AppData'),
      p.join(supportDirectory, 'PURE_LIVE'),
      p.join(supportDirectory, 'pure_live'),
      supportDirectory,
      p.join(documentsDirectory, 'PURE_LIVE'),
      p.join(documentsDirectory, 'pure_live'),
      ?cacheDirectory,
      for (final install in installDirectories) p.join(install, 'AppData'),
    ];
    final parent = Directory(executableDirectory).parent;
    try {
      await for (final entity in parent.list(followLinks: false)) {
        if (entity is! Directory) continue;
        if (p.basename(entity.path).toLowerCase().replaceAll(RegExp('[_ -]'), '') == 'purelive') {
          roots.add(p.join(entity.path, 'AppData'));
        }
      }
    } on FileSystemException {
      // The parent folder may not be listable.
    }
    final seenRoots = <String>{};
    final files = <String, String>{};
    for (var index = 0; index < roots.length && seenRoots.length < 32; index++) {
      final root = roots[index];
      if (!seenRoots.add(p.normalize(root).toLowerCase())) continue;
      for (final candidate in [p.join(root, boxFile), p.join(root, 'HIVE_DB', boxFile)]) {
        if (File(candidate).existsSync()) files.putIfAbsent(p.normalize(candidate).toLowerCase(), () => candidate);
      }
      final ledger = File(p.join(root, 'previous_install_locations.txt'));
      try {
        if (!ledger.existsSync()) continue;
        for (final line in await ledger.readAsLines()) {
          final install = line.trim().replaceAll(RegExp(r'[\\/]+$'), '');
          if (install.isNotEmpty && p.isAbsolute(install)) roots.add(p.join(install, 'AppData'));
        }
      } on FileSystemException {
        // An unreadable ledger only hides older installs.
      }
    }
    return files.values.toList();
  }
}

/// What an import read and wrote.
final class LegacyImportReport {
  /// Sources read in this run.
  int importedSources = 0;

  /// Sources skipped because they were imported before.
  int alreadyImported = 0;

  /// Sources that could not be read (retried next time).
  final List<String> failedSources = [];

  /// Follows after the import.
  int follows = 0;

  /// History entries after the import.
  int history = 0;

  /// Values that could not be read.
  final List<String> skipped = [];

  @override
  String toString() =>
      'LegacyImportReport(imported: $importedSources, before: $alreadyImported, failed: ${failedSources.length}, '
      'follows: $follows, history: $history, skipped: ${skipped.length})';
}

/// Imports 3.x data into a [LiveStore].
///
/// Sources are only read: the box file's bytes are parsed by
/// [HiveBoxReader], nothing is opened, locked, renamed or deleted. A source
/// is recorded by `path|size|modified` (3.x's own ledger format, whose
/// entries count as imported too) and skipped next time; one that fails to
/// read is not recorded and is retried on the next start.
abstract final class LegacyMigration {
  static const _ledgerKey = 'legacy.importedSources';

  /// Imports [files] (from [LegacyLocations]); the first file is the main
  /// source. Data already in the store wins; follows, history, areas,
  /// groups and block lists are joined by identity with empty fields filled
  /// from the sources (3.x `SettingsUpgradeMigration.mergeRawSettings`).
  static Future<LegacyImportReport> importHiveFiles(LiveStore store, List<String> files) async {
    final report = LegacyImportReport();
    final ledger = <String>{...?_decodeLedger(await store.meta.get(_ledgerKey))};
    final imported = <String>[];
    for (final path in files) {
      final file = File(path);
      final String fingerprint;
      final LegacySnapshot snapshot;
      try {
        final stat = file.statSync();
        if (stat.type != FileSystemEntityType.file) continue;
        fingerprint = '${file.absolute.path}|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
        if (ledger.contains(fingerprint)) {
          report.alreadyImported++;
          continue;
        }
        final raw = HiveBoxReader.read(await file.readAsBytes());
        ledger.addAll(_decodeLedger(raw['settingsUpgradeImportedSources']) ?? const []);
        snapshot = LegacySnapshot.fromHive(raw);
      } on FileSystemException {
        report.failedSources.add(path);
        continue;
      }
      await merge(store, snapshot);
      report
        ..importedSources += 1
        ..skipped.addAll(snapshot.skipped);
      imported.add(fingerprint);
      ledger.add(fingerprint);
    }
    if (imported.isNotEmpty) await store.meta.set(_ledgerKey, jsonEncode(ledger.toList()..sort()));
    report
      ..follows = await store.follows.count()
      ..history = (await store.history.all()).length;
    return report;
  }

  static List<String>? _decodeLedger(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final list = jsonDecode(raw);
      return list is List ? [for (final item in list) '$item'] : null;
    } on FormatException {
      return null;
    }
  }

  /// Moves the 3.x values kept in `legacy_values` whose key has since become
  /// a registered setting (the recorder's, M8.1) into the settings: an
  /// import before the setting existed parked them there, and the source is
  /// in the ledger, so it is not read again. A value the store already has
  /// wins (as in [merge]); an unreadable one is dropped. Adopted keys leave
  /// `legacy_values`, so this runs once per key. Returns how many settings
  /// were set.
  static Future<int> adoptLegacyValues(LiveStore store) async {
    final adopted = <Setting<Object>, Object>{};
    final done = <String>[];
    for (final key in await store.meta.legacyKeys()) {
      final setting = Settings.byKey(key);
      if (setting == null) continue;
      done.add(key);
      if (store.settings.isSet(setting)) continue;
      final value = setting.decode(await store.meta.legacyValue(key));
      if (value != null) adopted[setting] = setting.normalize(value);
    }
    if (adopted.isNotEmpty) await store.settings.setAll(adopted);
    if (done.isNotEmpty) await store.meta.forgetLegacyValues(done);
    return adopted.length;
  }

  /// Joins [snapshot] into [store]: settings, cookies and WebDAV servers only
  /// where the store has none; collections joined by identity, stored
  /// entries first.
  static Future<void> merge(LiveStore store, LegacySnapshot snapshot) async {
    await store.settings.setAll({
      for (final entry in snapshot.settings.entries)
        if (!store.settings.isSet(entry.key)) entry.key: entry.value,
    });
    if (snapshot.secrets case final secrets?) {
      await store.secrets.writeAll({
        for (final entry in secrets.entries)
          if (store.secrets.read(entry.key) == null && entry.value.isNotEmpty) entry.key: entry.value,
      });
    }
    if (snapshot.follows case final rooms?) {
      await store.follows.replaceAll(_join(await store.follows.all(), rooms));
    }
    if (snapshot.history case final rooms?) {
      await store.history.replaceAll(_join(await store.history.all(), rooms));
    }
    if (snapshot.followAreas case final areas?) {
      await store.followAreas.replaceAll([...await store.followAreas.all(), ...areas]);
    }
    if (snapshot.blockedKeywords case final values?) {
      await store.blockLists.replaceAll(BlockKind.keyword, [
        ...await store.blockLists.list(BlockKind.keyword),
        ...values,
      ]);
    }
    if (snapshot.blockedUsers case final values?) {
      await store.blockLists.replaceAll(BlockKind.user, [...await store.blockLists.list(BlockKind.user), ...values]);
    }
    if (snapshot.tags != null || snapshot.roomTags != null) {
      final tags = await store.tags.all();
      final known = {for (final tag in tags) tag.id};
      final assignments = await store.tags.assignments();
      for (final entry in (snapshot.roomTags ?? const <String, List<String>>{}).entries) {
        assignments[entry.key] = {...?assignments[entry.key], ...entry.value}.toList();
      }
      await store.tags.replaceAll([...tags, ...?snapshot.tags?.where((tag) => !known.contains(tag.id))], assignments);
    }
    if (snapshot.webdav case final configs?) {
      final stored = await store.webdav.all();
      final names = {for (final config in stored) config.name};
      final current = await store.webdav.current();
      await store.webdav.replaceAll(
        [...stored, ...configs.where((config) => !names.contains(config.name))],
        current:
            current ??
            (snapshot.currentWebDav == null ? null : WebDavConfig(name: snapshot.currentWebDav!, address: '')),
      );
    }
    await store.meta.keepLegacyValues(snapshot.otherValues);
  }

  static List<LiveRoom> _join(List<LiveRoom> stored, List<LiveRoom> incoming) {
    final byIdentity = {for (final room in stored) room.identityKey: room};
    final order = [for (final room in stored) room.identityKey];
    for (final room in incoming) {
      final existing = byIdentity[room.identityKey];
      if (existing == null) {
        byIdentity[room.identityKey] = room;
        order.add(room.identityKey);
      } else {
        byIdentity[room.identityKey] = fillEmptyFields(existing, room);
      }
    }
    return [for (final key in order) byIdentity[key]!];
  }
}

/// The room a stored [room] is now, under its new identity, or null to keep
/// it as it is (not found, needs login, offline: try again next time).
///
/// The app (M12/M13) implements it with the platform adapters: Douyin
/// `getRoomDetailForRefresh` (web_rid), niconico `NiconicoSite.resolveRoomId`
/// with `NiconicoApi.watchUrl`, YouTube `YouTubeSite.resolveRoomId` with
/// `YouTubeApi.roomLink`.
typedef RoomIdentityResolver = Future<LiveRoom?> Function(LiveRoom room);

/// Moves 3.x's per-broadcast follows and history to the streamer
/// ([LegacyRules.needsIdentityMigration]). Run it before any follow refresh:
/// a refresh answers with the new identity, which [LiveRoom.mergeFrom]
/// ignores.
abstract final class IdentityMigration {
  /// Resolves every room that needs it; the stored data (name, groups,
  /// position) moves to the new identity, the stored link and notice are
  /// replaced, and a room that is then followed twice is joined. Returns how
  /// many rooms moved.
  static Future<int> run(LiveStore store, RoomIdentityResolver resolve) async {
    final targets = <String, LiveRoom>{};
    final candidates = [...await store.follows.all(), ...await store.history.all()];
    for (final room in candidates) {
      if (!LegacyRules.needsIdentityMigration(room) || targets.containsKey(room.identityKey)) continue;
      LiveRoom? resolved;
      try {
        resolved = await resolve(room);
      } on Object {
        resolved = null;
      }
      if (resolved == null || resolved.platform != room.platform || resolved.identityKey == room.identityKey) continue;
      targets[room.identityKey] = resolved;
    }
    if (targets.isEmpty) return 0;
    LiveRoom moved(LiveRoom room) {
      final target = targets[room.identityKey];
      if (target == null) return room;
      final rebased = LiveRoom.fromJson({...room.toJson(), 'roomId': target.roomId, 'link': '', 'notice': ''});
      return rebased.mergeFrom(target);
    }

    await store.follows.replaceAll((await store.follows.all()).map(moved));
    await store.history.replaceAll((await store.history.all()).map(moved));
    for (final entry in targets.entries) {
      await store.tags.moveRoom(entry.key, entry.value.identityKey);
    }
    return targets.length;
  }
}
