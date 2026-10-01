import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:live_iptv/live_iptv.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// 3.x's IPTV databases beside its settings boxes: 3.x kept
/// `<root>/HIVE_DB/app_settings.hive` and
/// `<root>/IPTV_CACHE/pure_live_tv/pure_live_tv.db` under the same data root
/// (`AppPathManager.dirIptvCache`, `iptvTable`). Only existing files are
/// returned, without duplicates (case-insensitive).
List<String> legacyIptvDatabases(Iterable<String> hiveFiles) {
  final found = <String, String>{};
  for (final hive in hiveFiles) {
    var root = p.dirname(hive);
    if (p.basename(root).toUpperCase() == 'HIVE_DB') root = p.dirname(root);
    final database = p.join(root, 'IPTV_CACHE', 'pure_live_tv', 'pure_live_tv.db');
    if (File(database).existsSync()) found.putIfAbsent(p.normalize(database).toLowerCase(), () => database);
  }
  return found.values.toList();
}

/// What the 3.x IPTV import read and wrote.
final class LegacyIptvReport {
  /// Databases read in this run.
  int importedSources = 0;

  /// Databases skipped because they were imported before.
  int alreadyImported = 0;

  /// Databases that could not be read (retried next time).
  final List<String> failedSources = [];

  /// Playlists added.
  int playlists = 0;

  /// Channels added.
  int channels = 0;

  /// Guide sources added.
  int guides = 0;

  /// What was left out: playlists or guides the library already has, unknown
  /// playlist formats, channels whose id is taken.
  final List<String> skipped = [];

  @override
  String toString() =>
      'LegacyIptvReport(imported: $importedSources, before: $alreadyImported, failed: ${failedSources.length}, '
      'playlists: $playlists, channels: $channels, guides: $guides, skipped: ${skipped.length})';
}

/// The IPTV data of one 3.x database (schema 9), read into M6's model.
final class LegacyIptvSnapshot {
  /// Creates a snapshot.
  new({
    required this.playlists,
    required this.channels,
    required this.mappings,
    required this.guides,
    required this.guideChannels,
    required this.programmes,
    required this.skipped,
  });

  /// Playlists (3.x `providers`), in 3.x's order.
  final List<IptvPlaylist> playlists;

  /// Channels by playlist id, in 3.x's order; ids as 3.x stored them.
  final Map<String, List<IptvChannel>> channels;

  /// Guide mappings by playlist id.
  final Map<String, List<EpgMapping>> mappings;

  /// Guide sources.
  final List<EpgSource> guides;

  /// Guide channels by source id.
  final Map<String, List<EpgChannel>> guideChannels;

  /// Programmes by source id that had not ended before the retention window.
  final Map<String, List<EpgProgramme>> programmes;

  /// Rows that could not be read.
  final List<String> skipped;
}

/// Imports 3.x's IPTV database (`pure_live_tv.db`) into an [IptvLibrary]
/// (M12.1; 3.x kept it apart from the settings box that M9 imports).
///
/// The 3.x file is only read: it and its `-wal`/`-journal` companions are
/// copied into a temporary folder and the copy is opened, so SQLite never
/// creates, locks or rolls back anything beside 3.x's file. Like M9's
/// import, a database is recorded by `path|size|modified` under
/// [ledgerKey] and skipped next time; one that fails is not recorded and is
/// retried on the next start. Data already in the library wins: playlists
/// and guide sources with a saved id or name, and channels whose id is
/// taken, are left out. Channel ids stay as 3.x stored them, so 3.x rooms,
/// follows and history keep pointing at them.
abstract final class LegacyIptvMigration {
  /// `meta` key of the ledger.
  static const ledgerKey = 'legacy.iptvImportedSources';

  /// Imports [files] (from [legacyIptvDatabases]). Copies of 3.x's local
  /// playlists go to [playlistDirectory], so syncs do not depend on 3.x's
  /// folder.
  static Future<LegacyIptvReport> importDatabases(
    LiveStore store,
    IptvLibrary library,
    List<String> files, {
    required Directory playlistDirectory,
    DateTime Function() now = DateTime.now,
    String Function() newId = randomUuid,
  }) async {
    final report = LegacyIptvReport();
    final ledger = <String>{...?_decodeLedger(await store.meta.get(ledgerKey))};
    final imported = <String>[];
    for (final path in files) {
      final file = File(path);
      final String fingerprint;
      final LegacyIptvSnapshot snapshot;
      try {
        final stat = file.statSync();
        if (stat.type != FileSystemEntityType.file) continue;
        fingerprint = '${file.absolute.path}|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
        if (ledger.contains(fingerprint)) {
          report.alreadyImported++;
          continue;
        }
        snapshot = await _readInBackground(path, now().subtract(IptvImporter.programmeRetention));
      } on Object {
        // Unreadable, locked, or not a 3.x database: retried next start.
        report.failedSources.add(path);
        continue;
      }
      await merge(library, snapshot, report: report, playlistDirectory: playlistDirectory, newId: newId);
      report.importedSources++;
      imported.add(fingerprint);
      ledger.add(fingerprint);
    }
    if (imported.isNotEmpty) await store.meta.set(ledgerKey, jsonEncode(ledger.toList()..sort()));
    return report;
  }

  static Future<LegacyIptvSnapshot> _readInBackground(String path, DateTime since) =>
      Isolate.run(() => read(path, programmesSince: since));

  /// Reads the 3.x database at [path] through a temporary copy. Programmes
  /// that stopped before [programmesSince] are left out (the importer
  /// prunes them anyway).
  static LegacyIptvSnapshot read(String path, {required DateTime programmesSince}) {
    final work = Directory.systemTemp.createTempSync('pure_live_iptv_');
    try {
      final copy = p.join(work.path, p.basename(path));
      File(path).copySync(copy);
      for (final suffix in ['-wal', '-journal']) {
        final companion = File('$path$suffix');
        if (companion.existsSync()) companion.copySync('$copy$suffix');
      }
      final db = sqlite3.open(copy);
      try {
        return _snapshot(db, programmesSince);
      } finally {
        db.close();
      }
    } finally {
      try {
        work.deleteSync(recursive: true);
      } on FileSystemException {
        // A temporary folder left behind is harmless.
      }
    }
  }

  static LegacyIptvSnapshot _snapshot(Database db, DateTime programmesSince) {
    final tables = {for (final row in db.select("SELECT name FROM sqlite_master WHERE type = 'table'")) row['name']};
    if (!tables.contains('providers') || !tables.contains('channels')) {
      throw const FormatException('Not a 3.x IPTV database');
    }
    List<Row> rows(String table) =>
        tables.contains(table) ? db.select('SELECT * FROM $table ORDER BY rowid') : const [];
    final skipped = <String>[];

    final playlists = <IptvPlaylist>[];
    for (final row in rows('providers')) {
      final id = row['id'] as String?;
      final format = IptvPlaylistFormat.fromType(row['type'] as String?);
      if (id == null || format == null) {
        skipped.add('playlist $id: type ${row['type']}');
        continue;
      }
      playlists.add(
        IptvPlaylist(
          id: id,
          name: (row['name'] as String?) ?? '',
          format: format,
          source: (row['url'] as String?) ?? '',
          sortOrder: _int(row['sort_order']) ?? 0,
          lastRefresh: _time(row['last_refresh']),
          createdAt: _time(row['created_at']),
          autoUpdate: _flag(row['is_auto_update'], fallback: true),
        ),
      );
    }

    final channels = <String, List<IptvChannel>>{};
    for (final row in rows('channels')) {
      final id = row['id'] as String?;
      final playlistId = row['provider_id'] as String?;
      final name = row['name'] as String?;
      final url = row['stream_url'] as String?;
      if (id == null || playlistId == null || name == null || url == null) {
        skipped.add('channel $id');
        continue;
      }
      channels
          .putIfAbsent(playlistId, () => [])
          .add(
            IptvChannel(
              id: id,
              playlistId: playlistId,
              entry: IptvEntry(
                name: name,
                streamUrl: url,
                tvgId: row['tvg_id'] as String?,
                tvgName: row['tvg_name'] as String?,
                tvgLogo: row['tvg_logo'] as String?,
                groupTitle: row['group_title'] as String?,
                channelNumber: _int(row['channel_number']),
                streamType: IptvStreamType.fromName(row['stream_type'] as String?),
                catchupMode: row['catchup_mode'] as String?,
                catchupSource: row['catchup_source'] as String?,
                catchupDays: (row['catchup_days'] as num?)?.toDouble(),
                catchupCorrectionHours: (row['catchup_correction_hours'] as num?)?.toDouble(),
                httpHeaders: HttpHeaderPolicy.decode(row['http_headers_json'] as String?),
              ),
              favorite: _flag(row['favorite']),
              hidden: _flag(row['hidden']),
              sortOrder: _int(row['sort_order']) ?? 0,
              autoUpdate: _flag(row['is_auto_update'], fallback: true),
            ),
          );
    }

    final mappings = <String, List<EpgMapping>>{};
    for (final row in rows('epg_mappings')) {
      final channelId = row['channel_id'] as String?;
      final playlistId = row['provider_id'] as String?;
      final key = row['epg_channel_id'] as String?;
      final sourceId = row['epg_source_id'] as String?;
      if (channelId == null || playlistId == null || key == null || sourceId == null) continue;
      mappings
          .putIfAbsent(playlistId, () => [])
          .add(
            EpgMapping(
              channelId: channelId,
              playlistId: playlistId,
              epgChannelKey: key,
              epgSourceId: sourceId,
              origin: (row['source'] as String?) ?? EpgMapping.autoOrigin,
              locked: _flag(row['locked']),
            ),
          );
    }

    final guides = <EpgSource>[
      for (final row in rows('epg_sources'))
        if (row['id'] case final String id)
          EpgSource(
            id: id,
            name: (row['name'] as String?) ?? '',
            source: (row['url'] as String?) ?? '',
            lastRefresh: _time(row['last_refresh']),
            createdAt: _time(row['created_at']),
            autoUpdate: _flag(row['is_auto_update'], fallback: true),
          ),
    ];

    final guideChannels = <String, List<EpgChannel>>{};
    for (final row in rows('epg_channels')) {
      final sourceId = row['source_id'] as String?;
      final channelId = row['channel_id'] as String?;
      if (sourceId == null || channelId == null) continue;
      guideChannels
          .putIfAbsent(sourceId, () => [])
          .add(
            EpgChannel(
              sourceId: sourceId,
              channelId: channelId,
              displayName: (row['display_name'] as String?) ?? channelId,
              iconUrl: row['icon_url'] as String?,
            ),
          );
    }

    final programmes = <String, List<EpgProgramme>>{};
    for (final row in rows('epg_programmes')) {
      final sourceId = row['source_id'] as String?;
      final reference = row['epg_channel_id'] as String?;
      final start = _time(row['start']);
      final stop = _time(row['stop']);
      final title = row['title'] as String?;
      if (sourceId == null || reference == null || start == null || stop == null || title == null) continue;
      if (stop.isBefore(programmesSince)) continue;
      programmes
          .putIfAbsent(sourceId, () => [])
          .add(
            EpgProgramme(
              channelId: _guideChannelId(reference),
              sourceId: sourceId,
              start: start,
              stop: stop,
              title: title,
              subtitle: row['subtitle'] as String?,
              description: row['description'] as String?,
              category: row['category'] as String?,
              episodeNum: row['episode_num'] as String?,
              catchupId: row['catchup_id'] as String?,
            ),
          );
    }

    return LegacyIptvSnapshot(
      playlists: playlists,
      channels: channels,
      mappings: mappings,
      guides: guides,
      guideChannels: guideChannels,
      programmes: programmes,
      skipped: skipped,
    );
  }

  /// Adds [snapshot] to [library] where the library has nothing yet.
  static Future<void> merge(
    IptvLibrary library,
    LegacyIptvSnapshot snapshot, {
    required LegacyIptvReport report,
    required Directory playlistDirectory,
    String Function() newId = randomUuid,
  }) async {
    report.skipped.addAll(snapshot.skipped);
    String fold(String name) => name.trim().toLowerCase();

    final sources = await library.guideSources();
    final sourceIds = {for (final source in sources) source.id};
    final sourceNames = {for (final source in sources) fold(source.name)};
    for (final guide in snapshot.guides) {
      if (sourceIds.contains(guide.id) || sourceNames.contains(fold(guide.name))) {
        report.skipped.add('guide ${guide.name}: already saved');
        continue;
      }
      await library.saveGuide(
        guide,
        snapshot.guideChannels[guide.id] ?? const [],
        snapshot.programmes[guide.id] ?? const [],
        expected: null,
      );
      sourceIds.add(guide.id);
      sourceNames.add(fold(guide.name));
      report.guides++;
    }

    final saved = await library.playlists();
    final playlistIds = {for (final playlist in saved) playlist.id};
    final playlistNames = {
      for (final playlist in saved)
        if (!playlist.isHot) fold(playlist.name),
    };
    final channelIds = {
      for (final playlist in saved)
        for (final channel in await library.channels(playlist.id)) channel.id,
    };
    for (final playlist in snapshot.playlists) {
      if (playlistIds.contains(playlist.id) || (!playlist.isHot && playlistNames.contains(fold(playlist.name)))) {
        report.skipped.add('playlist ${playlist.name}: already saved');
        continue;
      }
      final channels = <IptvChannel>[];
      for (final channel in snapshot.channels[playlist.id] ?? const <IptvChannel>[]) {
        if (channelIds.add(channel.id)) {
          channels.add(channel);
        } else {
          report.skipped.add('channel ${channel.id}: id taken');
        }
      }
      final kept = {for (final channel in channels) channel.id};
      await library.savePlaylist(
        playlist.copyWith(source: _copyLocal(playlist, playlistDirectory, newId)),
        channels,
        expected: null,
        mappings: (
          upserts: [
            for (final mapping in snapshot.mappings[playlist.id] ?? const <EpgMapping>[])
              if (kept.contains(mapping.channelId)) mapping,
          ],
          deletes: const [],
        ),
      );
      playlistIds.add(playlist.id);
      if (!playlist.isHot) playlistNames.add(fold(playlist.name));
      report
        ..playlists += 1
        ..channels += channels.length;
    }
  }

  /// A copy of a local playlist's file in [directory] (the importer's own
  /// naming), or the 3.x path when there is nothing to copy.
  static String _copyLocal(IptvPlaylist playlist, Directory directory, String Function() newId) {
    if (playlist.isRemote || playlist.source.isEmpty) return playlist.source;
    try {
      final file = File(playlist.source);
      if (!file.existsSync()) return playlist.source;
      directory.createSync(recursive: true);
      return file.copySync(p.join(directory.path, 'playlist_${newId()}${playlist.format.extension}')).path;
    } on FileSystemException {
      return playlist.source;
    }
  }

  /// The guide's own channel id in a 3.x programme reference: schema 7 and
  /// later store [epgChannelKey]; older rows the raw id.
  static String _guideChannelId(String reference) {
    if (reference.startsWith('epg:')) {
      try {
        final parts = jsonDecode(reference.substring(4));
        if (parts is List && parts.length == 2 && parts[1] is String) return parts[1] as String;
      } on FormatException {
        // Not a framed key.
      }
    }
    return reference;
  }

  /// drift stored `DateTime` as Unix seconds (3.x had no text-date option).
  static DateTime? _time(Object? value) => switch (value) {
    final int seconds => DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
    final String text => DateTime.tryParse(text),
    _ => null,
  };

  static int? _int(Object? value) => value is num ? value.toInt() : null;

  static bool _flag(Object? value, {bool fallback = false}) => value is num ? value != 0 : fallback;

  static List<String>? _decodeLedger(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final list = jsonDecode(raw);
      return list is List ? [for (final item in list) '$item'] : null;
    } on FormatException {
      return null;
    }
  }
}
