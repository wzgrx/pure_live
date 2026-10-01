import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/search/search_history.dart';

/// The one backup service of the pages (local files and WebDAV share it, so
/// its "one restore at a time" lock covers both).
final Provider<BackupService> backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(storeProvider)),
);

/// What a backup holds or a restore applies.
enum BackupScope {
  /// Everything (3.x "create backup" / "recover backup").
  all,

  /// Followed rooms and areas only (3.x "favorites only").
  follows,
}

/// The backup section the pages add for the search words (new in v4, see
/// docs/modules/M13.10-backup.md): `{"search": {"history": [...]}}`. 3.x and
/// `BackupService` ignore sections they do not know.
const String searchSection = 'search';

/// The data of a new backup: [BackupService]'s file (3.x layout, no
/// accounts, as 3.x) and, for a full backup, the search words.
Future<Map<String, Object?>> exportBackup(BackupService service, LiveStore store, BackupScope scope) async {
  if (scope == BackupScope.follows) return await service.exportFollows();
  final data = {...await service.exportAll()};
  data[searchSection] = {'history': await _storedSearchWords(store)};
  return data;
}

/// Applies [json] for [scope]; a full restore also replaces the search
/// words when the file has them. Throws [FormatException] for a file that is
/// not a backup and [StateError] when another restore runs.
Future<void> restoreBackup(BackupService service, LiveStore store, Map<String, Object?> json, BackupScope scope) async {
  if (scope == BackupScope.follows) return await service.restoreFollows(json);
  await service.restoreAll(json);
  final words = searchWordsIn(json);
  if (words != null) await store.meta.set(SearchHistory.key, jsonEncode(words));
}

/// The search words of a backup, cleaned like the search page keeps them
/// (trimmed, cut, case-insensitively unique, at most [SearchHistory.limit]),
/// or null when the file has none.
List<String>? searchWordsIn(Map<String, Object?> json) {
  final section = json[searchSection];
  if (section is! Map || section['history'] is! List) return null;
  return _cleanWords((section['history']! as List).whereType<String>());
}

List<String> _cleanWords(Iterable<String> words) {
  final seen = <String>{};
  final result = <String>[];
  for (final word in words) {
    var text = word.trim();
    if (text.isEmpty) continue;
    if (text.length > SearchHistory.maxLength) text = text.substring(0, SearchHistory.maxLength);
    if (!seen.add(text.toLowerCase())) continue;
    result.add(text);
    if (result.length == SearchHistory.limit) break;
  }
  return result;
}

Future<List<String>> _storedSearchWords(LiveStore store) async {
  try {
    final decoded = jsonDecode(await store.meta.get(SearchHistory.key) ?? '[]');
    return decoded is List ? _cleanWords(decoded.whereType<String>()) : const [];
  } on FormatException {
    return const [];
  }
}

/// One part of the data a restore replaces.
enum RestorePartKind {
  /// Followed rooms.
  follows('backup_part_follows'),

  /// Followed areas.
  areas('backup_part_areas'),

  /// Watch history.
  history('backup_part_history'),

  /// Follow groups.
  tags('backup_part_tags'),

  /// Danmaku keyword blocks.
  keywords('backup_part_keywords'),

  /// Danmaku user blocks.
  users('backup_part_users'),

  /// WebDAV servers.
  webdav('backup_part_webdav'),

  /// Search words.
  search('backup_part_search');

  new(this.labelKey);

  /// Translation key of the name.
  final String labelKey;
}

/// How one part changes: counts now and after, entries added and removed.
final class RestorePart {
  /// Creates the change.
  const new({required this.kind, required this.current, required this.incoming, this.added = 0, this.removed = 0});

  /// Compares the [current] entries with the [incoming] ones by [key].
  static RestorePart compare<T>(RestorePartKind kind, List<T> current, List<T> incoming, String? Function(T) key) {
    final now = {for (final item in current) ?key(item)};
    final next = {for (final item in incoming) ?key(item)};
    return RestorePart(
      kind: kind,
      current: current.length,
      incoming: incoming.length,
      added: next.difference(now).length,
      removed: now.difference(next).length,
    );
  }

  /// The part.
  final RestorePartKind kind;

  /// Entries now.
  final int current;

  /// Entries after the restore.
  final int incoming;

  /// Entries the file adds.
  final int added;

  /// Entries the restore removes.
  final int removed;

  /// Whether the restore leaves the part as it is.
  bool get unchanged => added == 0 && removed == 0 && current == incoming;
}

/// What a restore would change, shown before it runs (new in v4: 3.x only
/// asked "overwrite?").
final class RestorePreview {
  /// Creates the preview.
  const new({
    required this.scope,
    required this.version,
    required this.followsOnlyFile,
    required this.parts,
    required this.kept,
    this.settingsInFile = 0,
    this.settingsChanged = 0,
    this.accounts = 0,
    this.skipped = 0,
  });

  /// What the restore applies (a follows-only file always restores follows).
  final BackupScope scope;

  /// `backupVersion` of the file; null for 3.x's flat format.
  final int? version;

  /// Whether the file is a follows-only backup.
  final bool followsOnlyFile;

  /// The parts the file has, in display order.
  final List<RestorePart> parts;

  /// The parts the file does not have (they stay as they are).
  final List<RestorePartKind> kept;

  /// Settings in the file.
  final int settingsInFile;

  /// Settings whose value differs from the current one.
  final int settingsChanged;

  /// Account entries (cookies, Douyu passport) the file writes.
  final int accounts;

  /// Entries that could not be read and are left out.
  final int skipped;

  /// Whether anything would change.
  bool get changesSomething => settingsChanged > 0 || accounts > 0 || parts.any((part) => !part.unchanged);
}

/// Works out what restoring [json] for [scope] would change in [store].
///
/// Reads the file the way [BackupService] does ([LegacySnapshot.fromBackup])
/// and throws the same [FormatException] for a file that is not a backup. A
/// follows-only file asked to restore everything becomes a follows restore
/// (3.x refused it with a bare "restore failed").
Future<RestorePreview> previewRestore(LiveStore store, Map<String, Object?> json, BackupScope scope) async {
  final snapshot = LegacySnapshot.fromBackup(json);
  final version = switch (json['backupVersion']) {
    final num value => value.toInt(),
    _ => null,
  };
  final followsOnly = snapshot.favoritesOnly;
  final effective = followsOnly ? BackupScope.follows : scope;
  final parts = <RestorePart>[];
  final kept = <RestorePartKind>[];

  if (snapshot.follows case final rooms?) {
    parts.add(RestorePart.compare(RestorePartKind.follows, await store.follows.all(), rooms, (r) => r.identityKey));
  } else {
    kept.add(RestorePartKind.follows);
  }
  if (snapshot.followAreas case final areas?) {
    parts.add(RestorePart.compare(RestorePartKind.areas, await store.followAreas.all(), areas, (a) => a.identityKey));
  } else {
    kept.add(RestorePartKind.areas);
  }
  if (effective == BackupScope.follows) {
    if (parts.isEmpty) throw const FormatException('No favorite lists in backup');
    return RestorePreview(
      scope: effective,
      version: version,
      followsOnlyFile: followsOnly,
      parts: parts,
      kept: const [],
      skipped: snapshot.skipped.length,
    );
  }

  String lower(String value) => value.toLowerCase();
  if (snapshot.history case final rooms?) {
    parts.add(RestorePart.compare(RestorePartKind.history, await store.history.all(), rooms, (r) => r.identityKey));
  } else {
    kept.add(RestorePartKind.history);
  }
  if (snapshot.tags case final tags?) {
    final current = await store.tags.all();
    parts.add(RestorePart.compare(RestorePartKind.tags, current, tags, (t) => lower(t.name)));
  } else {
    kept.add(RestorePartKind.tags);
  }
  if (snapshot.blockedKeywords case final values?) {
    final current = await store.blockLists.list(BlockKind.keyword);
    parts.add(RestorePart.compare(RestorePartKind.keywords, current, values, lower));
  } else {
    kept.add(RestorePartKind.keywords);
  }
  if (snapshot.blockedUsers case final values?) {
    final current = await store.blockLists.list(BlockKind.user);
    parts.add(RestorePart.compare(RestorePartKind.users, current, values, lower));
  } else {
    kept.add(RestorePartKind.users);
  }
  if (snapshot.webdav case final configs?) {
    final current = await store.webdav.all();
    parts.add(RestorePart.compare(RestorePartKind.webdav, current, configs, (c) => c.name));
  } else {
    kept.add(RestorePartKind.webdav);
  }
  if (searchWordsIn(json) case final words?) {
    parts.add(RestorePart.compare(RestorePartKind.search, await _storedSearchWords(store), words, lower));
  } else {
    kept.add(RestorePartKind.search);
  }

  var changed = 0;
  for (final MapEntry(key: setting, :value) in snapshot.settings.entries) {
    final now = store.settings.get(setting);
    if (jsonEncode(setting.encode(now)) != jsonEncode(setting.encode(value))) changed++;
  }
  final accounts = snapshot.secrets?.values.where((value) => value.isNotEmpty).length ?? 0;
  return RestorePreview(
    scope: effective,
    version: version,
    followsOnlyFile: false,
    parts: parts,
    kept: kept,
    settingsInFile: snapshot.settings.length,
    settingsChanged: changed,
    accounts: accounts,
    skipped: snapshot.skipped.length,
  );
}
