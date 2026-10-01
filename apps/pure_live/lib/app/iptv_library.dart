import 'dart:io';

import 'package:drift/drift.dart' show Batch;
import 'package:live_iptv/live_iptv.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;

/// Where the importer keeps copies of local playlists: `<data folder>/iptv`.
Directory iptvPlaylistDirectory(Directory dataRoot) => Directory(p.join(dataRoot.path, 'iptv'));

/// Names of the IPTV tables in `pure_live.db`, for change notifications
/// (`store.database.watch(IptvTables.all, ...)`).
abstract final class IptvTables {
  /// Playlists.
  static const playlists = 'iptv_playlists';

  /// Playlist channels.
  static const channels = 'iptv_channels';

  /// Channel to guide channel mappings.
  static const mappings = 'iptv_epg_mappings';

  /// Guide sources.
  static const guideSources = 'iptv_epg_sources';

  /// Guide channels.
  static const guideChannels = 'iptv_epg_channels';

  /// Guide programmes.
  static const programmes = 'iptv_epg_programmes';

  /// Every IPTV table.
  static const Set<String> all = {playlists, channels, mappings, guideSources, guideChannels, programmes};
}

/// The IPTV tables (M12.1). Times are microseconds since the epoch, flags
/// 0/1, request headers JSON (`HttpHeaderPolicy.encode`). `position` keeps
/// import order (playlists, sources) and file order (channels).
const List<String> _schema = [
  'CREATE TABLE IF NOT EXISTS iptv_playlists (id TEXT NOT NULL PRIMARY KEY, position INTEGER NOT NULL, name TEXT NOT NULL, format TEXT NOT NULL, source TEXT NOT NULL, sort_order INTEGER NOT NULL, last_refresh INTEGER, created_at INTEGER, auto_update INTEGER NOT NULL)',
  'CREATE TABLE IF NOT EXISTS iptv_channels (id TEXT NOT NULL PRIMARY KEY, playlist_id TEXT NOT NULL, position INTEGER NOT NULL, name TEXT NOT NULL, stream_url TEXT NOT NULL, tvg_id TEXT, tvg_name TEXT, tvg_logo TEXT, group_title TEXT, channel_number INTEGER, stream_type TEXT NOT NULL, catchup_mode TEXT, catchup_source TEXT, catchup_days REAL, catchup_correction_hours REAL, http_headers TEXT, favorite INTEGER NOT NULL, hidden INTEGER NOT NULL, sort_order INTEGER NOT NULL, auto_update INTEGER NOT NULL)',
  'CREATE INDEX IF NOT EXISTS iptv_channels_playlist ON iptv_channels (playlist_id, position)',
  'CREATE TABLE IF NOT EXISTS iptv_epg_mappings (playlist_id TEXT NOT NULL, channel_id TEXT NOT NULL, epg_channel_key TEXT NOT NULL, epg_source_id TEXT NOT NULL, origin TEXT NOT NULL, locked INTEGER NOT NULL, PRIMARY KEY (playlist_id, channel_id))',
  'CREATE TABLE IF NOT EXISTS iptv_epg_sources (id TEXT NOT NULL PRIMARY KEY, position INTEGER NOT NULL, name TEXT NOT NULL, source TEXT NOT NULL, last_refresh INTEGER, created_at INTEGER, auto_update INTEGER NOT NULL)',
  'CREATE TABLE IF NOT EXISTS iptv_epg_channels (source_id TEXT NOT NULL, position INTEGER NOT NULL, channel_id TEXT NOT NULL, display_name TEXT NOT NULL, icon_url TEXT)',
  'CREATE INDEX IF NOT EXISTS iptv_epg_channels_source ON iptv_epg_channels (source_id, position)',
  'CREATE TABLE IF NOT EXISTS iptv_epg_programmes (source_id TEXT NOT NULL, channel_key TEXT NOT NULL, channel_id TEXT NOT NULL, start INTEGER NOT NULL, stop INTEGER NOT NULL, title TEXT NOT NULL, subtitle TEXT, description TEXT, category TEXT, episode_num TEXT, catchup_id TEXT)',
  'CREATE INDEX IF NOT EXISTS iptv_epg_programmes_channel ON iptv_epg_programmes (channel_key, start)',
  'CREATE INDEX IF NOT EXISTS iptv_epg_programmes_source ON iptv_epg_programmes (source_id)',
];

/// The [IptvLibrary] of the app: IPTV tables in the same SQLite database as
/// `LiveStore` (`pure_live.db`, one connection on drift's background
/// isolate), replacing 3.x's separate `pure_live_tv.db`.
///
/// It lives in the app because `live_store` may only depend on `live_core`
/// and `live_iptv` keeps storage behind its interface (M6); the app is the
/// one member that sees both. The tables are created on first use
/// (`CREATE TABLE IF NOT EXISTS`) and their version is recorded in `meta`
/// under [schemaKey] for later upgrades. Behaviour follows
/// [MemoryIptvLibrary]: every write is one transaction, `expected`
/// snapshots are compared column by column with the stored row.
final class StoreIptvLibrary implements IptvLibrary {
  /// Creates the library over [store]'s database.
  new(LiveStore store) : _db = store.database, _meta = store.meta;

  /// `meta` key of the IPTV schema version.
  static const schemaKey = 'iptv.schemaVersion';

  /// Version of the tables above.
  static const schemaVersion = 1;

  /// Bound variables per `IN (...)` list.
  static const _chunk = 500;

  final StoreDatabase _db;
  final MetaStore _meta;
  late final Future<void> _ready = _createTables();

  Future<void> _createTables() async {
    await _db.transaction(() async {
      for (final statement in _schema) {
        await _db.run(statement);
      }
    });
    if (await _meta.get(schemaKey) == null) await _meta.set(schemaKey, '$schemaVersion');
  }

  Future<List<Map<String, Object?>>> _rows(String sql, [List<Object?> args = const []]) async {
    await _ready;
    return [for (final row in await _db.rows(sql, args)) row.data];
  }

  Future<T> _write<T>(Set<String> tables, Future<T> Function() action) async {
    await _ready;
    return await _db.write(tables, action);
  }

  Future<int> _nextPosition(String table) async {
    final rows = await _db.rows('SELECT COALESCE(MAX(position), -1) + 1 AS next FROM $table');
    return rows.single.data['next']! as int;
  }

  // Playlists ---------------------------------------------------------------

  @override
  Future<List<IptvPlaylist>> playlists() async => [
    for (final row in await _rows('SELECT * FROM iptv_playlists ORDER BY position')) _playlistFrom(row),
  ];

  @override
  Future<IptvPlaylist?> playlist(String id) async {
    final rows = await _rows('SELECT * FROM iptv_playlists WHERE id = ?', [id]);
    return rows.isEmpty ? null : _playlistFrom(rows.single);
  }

  @override
  Future<List<IptvChannel>> channels(String playlistId) async => [
    for (final row in await _rows('SELECT * FROM iptv_channels WHERE playlist_id = ? ORDER BY position', [playlistId]))
      _channelFrom(row),
  ];

  @override
  Future<IptvChannel?> channel(String id) async {
    final rows = await _rows('SELECT * FROM iptv_channels WHERE id = ?', [id]);
    return rows.isEmpty ? null : _channelFrom(rows.single);
  }

  /// SQLite's `lower` folds ASCII letters only, as 3.x's `LIKE` did; `instr`
  /// keeps `%` and `_` literal.
  @override
  Future<List<IptvChannel>> searchChannels(String keyword) async => [
    for (final row in await _rows('SELECT * FROM iptv_channels WHERE instr(lower(name), lower(?)) > 0 ORDER BY name', [
      keyword,
    ]))
      _channelFrom(row),
  ];

  @override
  Future<void> savePlaylist(
    IptvPlaylist playlist,
    List<IptvChannel> channels, {
    required IptvPlaylist? expected,
    ({List<EpgMapping> upserts, List<EpgMapping> deletes}) mappings = (upserts: const [], deletes: const []),
  }) => _write({IptvTables.playlists, IptvTables.channels, IptvTables.mappings}, () async {
    final stored = await _readPlaylist(playlist.id);
    if (!_same(stored == null ? null : _playlistValues(stored), expected == null ? null : _playlistValues(expected))) {
      throw const StaleIptvSnapshot();
    }
    if (stored == null) {
      await _db.run(
        'INSERT INTO iptv_playlists (id, name, format, source, sort_order, last_refresh, created_at, auto_update, '
        'position) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [..._playlistValues(playlist), await _nextPosition(IptvTables.playlists)],
      );
    } else {
      await _updatePlaylistRow(playlist);
    }
    await _db.run('DELETE FROM iptv_channels WHERE playlist_id = ?', [playlist.id]);
    await _db.batch((batch) {
      for (final (index, channel) in channels.indexed) {
        _insertChannel(batch, playlist.id, index, channel);
      }
    });
    await _db.run(
      'DELETE FROM iptv_epg_mappings WHERE playlist_id = ? AND channel_id NOT IN '
      '(SELECT id FROM iptv_channels WHERE playlist_id = ?)',
      [playlist.id, playlist.id],
    );
    await _db.batch((batch) {
      for (final mapping in mappings.deletes) {
        batch.customStatement('DELETE FROM iptv_epg_mappings WHERE playlist_id = ? AND channel_id = ?', [
          playlist.id,
          mapping.channelId,
        ]);
      }
      for (final mapping in mappings.upserts) {
        batch.customStatement(
          'INSERT OR REPLACE INTO iptv_epg_mappings (playlist_id, channel_id, epg_channel_key, epg_source_id, origin, '
          'locked) VALUES (?, ?, ?, ?, ?, ?)',
          [
            playlist.id,
            mapping.channelId,
            mapping.epgChannelKey,
            mapping.epgSourceId,
            mapping.origin,
            _flag(mapping.locked),
          ],
        );
      }
    });
  });

  @override
  Future<void> updatePlaylist(IptvPlaylist playlist) =>
      _write({IptvTables.playlists}, () => _updatePlaylistRow(playlist));

  @override
  Future<bool> deletePlaylist(IptvPlaylist expected) =>
      _write({IptvTables.playlists, IptvTables.channels, IptvTables.mappings}, () async {
        final stored = await _readPlaylist(expected.id);
        if (stored == null || !_same(_playlistValues(stored), _playlistValues(expected))) return false;
        for (final table in [IptvTables.playlists, IptvTables.channels, IptvTables.mappings]) {
          await _db.run('DELETE FROM $table WHERE ${table == IptvTables.playlists ? 'id' : 'playlist_id'} = ?', [
            expected.id,
          ]);
        }
        return true;
      });

  @override
  Future<List<EpgMapping>> mappings(String playlistId) async => [
    for (final row in await _rows('SELECT * FROM iptv_epg_mappings WHERE playlist_id = ? ORDER BY rowid', [playlistId]))
      EpgMapping(
        channelId: row['channel_id']! as String,
        playlistId: row['playlist_id']! as String,
        epgChannelKey: row['epg_channel_key']! as String,
        epgSourceId: row['epg_source_id']! as String,
        origin: row['origin']! as String,
        locked: row['locked'] == 1,
      ),
  ];

  Future<IptvPlaylist?> _readPlaylist(String id) async {
    final rows = await _db.rows('SELECT * FROM iptv_playlists WHERE id = ?', [id]);
    return rows.isEmpty ? null : _playlistFrom(rows.single.data);
  }

  Future<void> _updatePlaylistRow(IptvPlaylist playlist) => _db.run(
    'UPDATE iptv_playlists SET name = ?, format = ?, source = ?, sort_order = ?, last_refresh = ?, created_at = ?, '
    'auto_update = ? WHERE id = ?',
    [..._playlistValues(playlist).skip(1), playlist.id],
  );

  static List<Object?> _playlistValues(IptvPlaylist playlist) => [
    playlist.id,
    playlist.name,
    playlist.format.name,
    playlist.source,
    playlist.sortOrder,
    _time(playlist.lastRefresh),
    _time(playlist.createdAt),
    _flag(playlist.autoUpdate),
  ];

  static IptvPlaylist _playlistFrom(Map<String, Object?> row) => IptvPlaylist(
    id: row['id']! as String,
    name: row['name']! as String,
    format: IptvPlaylistFormat.fromType(row['format'] as String?) ?? IptvPlaylistFormat.m3u,
    source: row['source']! as String,
    sortOrder: row['sort_order']! as int,
    lastRefresh: _readTime(row['last_refresh']),
    createdAt: _readTime(row['created_at']),
    autoUpdate: row['auto_update'] == 1,
  );

  static void _insertChannel(Batch batch, String playlistId, int position, IptvChannel channel) {
    final entry = channel.entry;
    batch.customStatement(
      'INSERT INTO iptv_channels (id, playlist_id, position, name, stream_url, tvg_id, tvg_name, tvg_logo, '
      'group_title, channel_number, stream_type, catchup_mode, catchup_source, catchup_days, '
      'catchup_correction_hours, http_headers, favorite, hidden, sort_order, auto_update) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        channel.id,
        playlistId,
        position,
        entry.name,
        entry.streamUrl,
        entry.tvgId,
        entry.tvgName,
        entry.tvgLogo,
        entry.groupTitle,
        entry.channelNumber,
        entry.streamType.name,
        entry.catchupMode,
        entry.catchupSource,
        entry.catchupDays,
        entry.catchupCorrectionHours,
        HttpHeaderPolicy.encode(entry.httpHeaders),
        _flag(channel.favorite),
        _flag(channel.hidden),
        channel.sortOrder,
        _flag(channel.autoUpdate),
      ],
    );
  }

  static IptvChannel _channelFrom(Map<String, Object?> row) => IptvChannel(
    id: row['id']! as String,
    playlistId: row['playlist_id']! as String,
    entry: IptvEntry(
      name: row['name']! as String,
      streamUrl: row['stream_url']! as String,
      tvgId: row['tvg_id'] as String?,
      tvgName: row['tvg_name'] as String?,
      tvgLogo: row['tvg_logo'] as String?,
      groupTitle: row['group_title'] as String?,
      channelNumber: row['channel_number'] as int?,
      streamType: IptvStreamType.fromName(row['stream_type'] as String?),
      catchupMode: row['catchup_mode'] as String?,
      catchupSource: row['catchup_source'] as String?,
      catchupDays: (row['catchup_days'] as num?)?.toDouble(),
      catchupCorrectionHours: (row['catchup_correction_hours'] as num?)?.toDouble(),
      httpHeaders: HttpHeaderPolicy.decode(row['http_headers'] as String?),
    ),
    favorite: row['favorite'] == 1,
    hidden: row['hidden'] == 1,
    sortOrder: row['sort_order']! as int,
    autoUpdate: row['auto_update'] == 1,
  );

  // Guides ------------------------------------------------------------------

  @override
  Future<List<EpgSource>> guideSources() async => [
    for (final row in await _rows('SELECT * FROM iptv_epg_sources ORDER BY position')) _sourceFrom(row),
  ];

  @override
  Future<EpgSource?> guideSource(String id) async {
    final rows = await _rows('SELECT * FROM iptv_epg_sources WHERE id = ?', [id]);
    return rows.isEmpty ? null : _sourceFrom(rows.single);
  }

  @override
  Future<List<EpgChannel>> guideChannels(String sourceId) async => [
    for (final row in await _rows('SELECT * FROM iptv_epg_channels WHERE source_id = ? ORDER BY position', [sourceId]))
      EpgChannel(
        sourceId: row['source_id']! as String,
        channelId: row['channel_id']! as String,
        displayName: row['display_name']! as String,
        iconUrl: row['icon_url'] as String?,
      ),
  ];

  @override
  Future<void> saveGuide(
    EpgSource source,
    List<EpgChannel> channels,
    List<EpgProgramme> programmes, {
    required EpgSource? expected,
    List<EpgSource> duplicates = const [],
  }) =>
      _write({IptvTables.guideSources, IptvTables.guideChannels, IptvTables.programmes, IptvTables.mappings}, () async {
        final stored = await _readSource(source.id);
        if (!_same(stored == null ? null : _sourceValues(stored), expected == null ? null : _sourceValues(expected))) {
          throw const StaleIptvSnapshot();
        }
        for (final duplicate in duplicates) {
          final saved = await _readSource(duplicate.id);
          if (saved == null || !_same(_sourceValues(saved), _sourceValues(duplicate))) throw const StaleIptvSnapshot();
        }
        for (final duplicate in duplicates) {
          await _removeSource(duplicate.id);
        }
        if (stored == null) {
          await _db.run(
            'INSERT INTO iptv_epg_sources (id, name, source, last_refresh, created_at, auto_update, position) '
            'VALUES (?, ?, ?, ?, ?, ?, ?)',
            [..._sourceValues(source), await _nextPosition(IptvTables.guideSources)],
          );
        } else {
          await _updateSourceRow(source);
        }
        await _db.run('DELETE FROM iptv_epg_channels WHERE source_id = ?', [source.id]);
        await _db.run('DELETE FROM iptv_epg_programmes WHERE source_id = ?', [source.id]);
        await _db.batch((batch) {
          for (final (index, channel) in channels.indexed) {
            batch.customStatement(
              'INSERT INTO iptv_epg_channels (source_id, position, channel_id, display_name, icon_url) '
              'VALUES (?, ?, ?, ?, ?)',
              [source.id, index, channel.channelId, channel.displayName, channel.iconUrl],
            );
          }
          for (final programme in programmes) {
            batch.customStatement(
              'INSERT INTO iptv_epg_programmes (source_id, channel_key, channel_id, start, stop, title, subtitle, '
              'description, category, episode_num, catchup_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
              [
                source.id,
                epgChannelKey(source.id, programme.channelId),
                programme.channelId,
                _time(programme.start),
                _time(programme.stop),
                programme.title,
                programme.subtitle,
                programme.description,
                programme.category,
                programme.episodeNum,
                programme.catchupId,
              ],
            );
          }
        });
      });

  @override
  Future<void> updateGuideSource(EpgSource source) => _write({IptvTables.guideSources}, () => _updateSourceRow(source));

  @override
  Future<bool> deleteGuideSource(EpgSource expected) =>
      _write({IptvTables.guideSources, IptvTables.guideChannels, IptvTables.programmes, IptvTables.mappings}, () async {
        final stored = await _readSource(expected.id);
        if (stored == null || !_same(_sourceValues(stored), _sourceValues(expected))) return false;
        await _removeSource(expected.id);
        return true;
      });

  @override
  Future<List<EpgProgramme>> programmes(String channelKey, {required DateTime from, required DateTime to}) async => [
    for (final row in await _rows(
      'SELECT * FROM iptv_epg_programmes WHERE channel_key = ? AND start >= ? AND stop <= ? ORDER BY start',
      [channelKey, _time(from), _time(to)],
    ))
      _programmeFrom(row),
  ];

  @override
  Future<List<EpgProgramme>> programmesAt(Set<String> channelKeys, DateTime at) async {
    final keys = channelKeys.toList();
    final result = <EpgProgramme>[];
    for (var offset = 0; offset < keys.length; offset += _chunk) {
      final part = keys.sublist(offset, (offset + _chunk).clamp(0, keys.length));
      final marks = List.filled(part.length, '?').join(', ');
      result.addAll([
        for (final row in await _rows(
          'SELECT * FROM iptv_epg_programmes WHERE channel_key IN ($marks) AND start <= ? AND stop >= ? ORDER BY start',
          [...part, _time(at), _time(at)],
        ))
          _programmeFrom(row),
      ]);
    }
    return result;
  }

  @override
  Future<void> pruneProgrammes(DateTime before) =>
      _write({IptvTables.programmes}, () => _db.run('DELETE FROM iptv_epg_programmes WHERE stop < ?', [_time(before)]));

  Future<EpgSource?> _readSource(String id) async {
    final rows = await _db.rows('SELECT * FROM iptv_epg_sources WHERE id = ?', [id]);
    return rows.isEmpty ? null : _sourceFrom(rows.single.data);
  }

  Future<void> _updateSourceRow(EpgSource source) => _db.run(
    'UPDATE iptv_epg_sources SET name = ?, source = ?, last_refresh = ?, created_at = ?, auto_update = ? WHERE id = ?',
    [..._sourceValues(source).skip(1), source.id],
  );

  Future<void> _removeSource(String id) async {
    for (final table in [IptvTables.guideSources, IptvTables.guideChannels, IptvTables.programmes]) {
      await _db.run('DELETE FROM $table WHERE ${table == IptvTables.guideSources ? 'id' : 'source_id'} = ?', [id]);
    }
    await _db.run('DELETE FROM iptv_epg_mappings WHERE epg_source_id = ?', [id]);
  }

  static List<Object?> _sourceValues(EpgSource source) => [
    source.id,
    source.name,
    source.source,
    _time(source.lastRefresh),
    _time(source.createdAt),
    _flag(source.autoUpdate),
  ];

  static EpgSource _sourceFrom(Map<String, Object?> row) => EpgSource(
    id: row['id']! as String,
    name: row['name']! as String,
    source: row['source']! as String,
    lastRefresh: _readTime(row['last_refresh']),
    createdAt: _readTime(row['created_at']),
    autoUpdate: row['auto_update'] == 1,
  );

  static EpgProgramme _programmeFrom(Map<String, Object?> row) => EpgProgramme(
    channelId: row['channel_id']! as String,
    sourceId: row['source_id']! as String,
    start: _readTime(row['start'])!,
    stop: _readTime(row['stop'])!,
    title: row['title']! as String,
    subtitle: row['subtitle'] as String?,
    description: row['description'] as String?,
    category: row['category'] as String?,
    episodeNum: row['episode_num'] as String?,
    catchupId: row['catchup_id'] as String?,
  );

  // Values ------------------------------------------------------------------

  static int? _time(DateTime? time) => time?.microsecondsSinceEpoch;

  /// Local time, as 3.x's drift columns read back.
  static DateTime? _readTime(Object? value) => value is int ? DateTime.fromMicrosecondsSinceEpoch(value) : null;

  static int _flag(bool value) => value ? 1 : 0;

  static bool _same(List<Object?>? a, List<Object?>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
