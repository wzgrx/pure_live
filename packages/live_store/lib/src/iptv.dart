import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:live_store/src/database/database.dart';
import 'package:meta/meta.dart';

/// Whether [source] is a downloadable URL rather than the path of a kept file.
bool isRemoteSource(String source) {
  final lower = source.trim().toLowerCase();
  // `xtream:<id>` is an account in the secret store (F-IPTV-07).
  return lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('xtream:');
}

/// A stored IPTV playlist (spec/modules/iptv.md §7).
@immutable
final class IptvPlaylistRecord {
  /// Creates a record.
  const new({
    required this.id,
    required this.name,
    required this.source,
    required this.order,
    this.userAgent,
    this.autoSync = true,
    this.guideUrl,
    this.lastSyncAt,
    this.lastAttemptAt,
    this.lastError,
    this.entryCount = 0,
    this.channelCount = 0,
  });

  /// Row id.
  final int id;

  /// Display name.
  final String name;

  /// URL or path of the kept file.
  final String source;

  /// Position in the user's order.
  final int order;

  /// The playlist's own User-Agent.
  final String? userAgent;

  /// Whether automatic sync includes it.
  final bool autoSync;

  /// Guide URL the playlist names.
  final String? guideUrl;

  /// Last successful sync.
  final DateTime? lastSyncAt;

  /// Last attempt.
  final DateTime? lastAttemptAt;

  /// Error of the last attempt, if it failed.
  final String? lastError;

  /// Stored entries (streams).
  final int entryCount;

  /// Distinct channel names.
  final int channelCount;

  /// Whether the source is a URL.
  bool get isRemote => isRemoteSource(source);
}

/// One stored playlist entry: the storage mirror of `live_iptv`'s
/// `IptvEntry` (live_store only depends on live_core).
@immutable
final class IptvEntryRecord {
  /// Creates a record.
  const new({
    required this.name,
    required this.url,
    this.group = '',
    this.tvgId,
    this.tvgName,
    this.logo,
    this.catchupMode,
    this.catchupSource,
    this.catchupDays,
    this.catchupCorrection,
    this.headers = const {},
  });

  /// Channel name.
  final String name;

  /// Stream URL.
  final String url;

  /// Group; empty when none.
  final String group;

  /// `tvg-id`.
  final String? tvgId;

  /// `tvg-name`.
  final String? tvgName;

  /// Logo URL.
  final String? logo;

  /// Catch-up mode.
  final String? catchupMode;

  /// Catch-up template.
  final String? catchupSource;

  /// Catch-up window in days.
  final double? catchupDays;

  /// Catch-up correction in hours.
  final double? catchupCorrection;

  /// Request headers.
  final Map<String, String> headers;
}

/// An entry with its playlist's id and User-Agent.
@immutable
final class IptvSourceRecord {
  /// Creates a record.
  const new({required this.entry, required this.playlistId, this.userAgent});

  /// The entry.
  final IptvEntryRecord entry;

  /// Playlist id.
  final int playlistId;

  /// The playlist's User-Agent.
  final String? userAgent;
}

/// A stored programme guide source.
@immutable
final class IptvGuideSourceRecord {
  /// Creates a record.
  const new({
    required this.id,
    required this.name,
    required this.source,
    required this.order,
    this.autoSync = true,
    this.selected = false,
    this.lastSyncAt,
    this.lastAttemptAt,
    this.lastError,
    this.channelCount = 0,
  });

  /// Row id.
  final int id;

  /// Display name.
  final String name;

  /// URL or path of the kept file.
  final String source;

  /// Position in the user's order.
  final int order;

  /// Whether automatic sync includes it.
  final bool autoSync;

  /// Whether it is the selected guide.
  final bool selected;

  /// Last successful sync.
  final DateTime? lastSyncAt;

  /// Last attempt.
  final DateTime? lastAttemptAt;

  /// Error of the last attempt, if it failed.
  final String? lastError;

  /// Stored guide channels.
  final int channelCount;

  /// Whether the source is a URL.
  bool get isRemote => isRemoteSource(source);
}

/// A stored guide channel.
@immutable
final class IptvGuideChannelRecord {
  /// Creates a record.
  const new({required this.channelId, this.names = const [], this.icon});

  /// Guide channel id.
  final String channelId;

  /// Display names.
  final List<String> names;

  /// Icon URL.
  final String? icon;
}

/// A stored programme.
@immutable
final class IptvProgrammeRecord {
  /// Creates a record.
  const new({
    required this.channelId,
    required this.start,
    required this.stop,
    required this.title,
    this.subtitle,
    this.description,
    this.catchupId,
  });

  /// Guide channel id.
  final String channelId;

  /// Start (UTC).
  final DateTime start;

  /// Stop (UTC).
  final DateTime stop;

  /// Title.
  final String title;

  /// Episode title.
  final String? subtitle;

  /// Description.
  final String? description;

  /// XMLTV `catchup-id`.
  final String? catchupId;
}

/// IPTV playlists, entries, guide sources and programmes (spec/modules/iptv.md
/// §7). Replacing a playlist's entries or a guide's programmes is one
/// transaction: readers see the old or the new list, never half of each.
final class IptvStore {
  /// Wraps [_db].
  new(this._db);

  final StoreDatabase _db;

  static final String _separator = String.fromCharCode(31);

  static int _ms(DateTime time) => time.toUtc().millisecondsSinceEpoch;

  static DateTime? _time(int? ms) => ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

  // -------------------------------------------------------------- playlists

  static const _playlistQuery =
      'SELECT p.*, '
      '(SELECT COUNT(*) FROM iptv_channels c WHERE c.playlist = p.id) AS entry_count, '
      '(SELECT COUNT(DISTINCT c.name) FROM iptv_channels c WHERE c.playlist = p.id) AS channel_count '
      'FROM iptv_playlists p ORDER BY p.sort_order, p.id';

  Selectable<IptvPlaylistRecord> _playlists() => _db
      .customSelect(_playlistQuery, readsFrom: {_db.iptvPlaylists, _db.iptvChannels})
      .map(
        (row) => IptvPlaylistRecord(
          id: row.read<int>('id'),
          name: row.read<String>('name'),
          source: row.read<String>('source'),
          order: row.read<int>('sort_order'),
          userAgent: row.readNullable<String>('user_agent'),
          autoSync: row.read<bool>('auto_sync'),
          guideUrl: row.readNullable<String>('guide_url'),
          lastSyncAt: _time(row.readNullable<int>('last_sync_at')),
          lastAttemptAt: _time(row.readNullable<int>('last_attempt_at')),
          lastError: row.readNullable<String>('last_error'),
          entryCount: row.read<int>('entry_count'),
          channelCount: row.read<int>('channel_count'),
        ),
      );

  /// Playlists in the user's order with their counts.
  Future<List<IptvPlaylistRecord>> playlists() => _playlists().get();

  /// Playlists, re-emitted after every change.
  Stream<List<IptvPlaylistRecord>> watchPlaylists() => _playlists().watch();

  /// The playlist [id], or null.
  Future<IptvPlaylistRecord?> playlist(int id) async =>
      (await playlists()).where((playlist) => playlist.id == id).firstOrNull;

  /// Adds a playlist at the end of the order and returns its id. Its entries
  /// come with [replaceEntries].
  Future<int> addPlaylist({required String name, required String source, String? userAgent, DateTime? now}) async {
    return await _db.transaction(() async {
      final last = await _maxOrder('iptv_playlists');
      return await _db
          .into(_db.iptvPlaylists)
          .insert(
            IptvPlaylistsCompanion.insert(
              name: name.trim(),
              source: source.trim(),
              userAgent: Value(_blankToNull(userAgent)),
              sortOrder: last + 1,
              createdAt: _ms(now ?? DateTime.now()),
            ),
          );
    });
  }

  Future<int> _maxOrder(String table) async {
    final row = await _db.customSelect('SELECT MAX(sort_order) AS m FROM $table').getSingle();
    return row.readNullable<int>('m') ?? -1;
  }

  static String? _blankToNull(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  /// Renames playlist [id].
  Future<void> renamePlaylist(int id, String name) =>
      _updatePlaylist(id, IptvPlaylistsCompanion(name: Value(name.trim())));

  /// Sets or clears (null or blank) the User-Agent of playlist [id].
  Future<void> setPlaylistUserAgent(int id, String? userAgent) =>
      _updatePlaylist(id, IptvPlaylistsCompanion(userAgent: Value(_blankToNull(userAgent))));

  /// Includes playlist [id] in automatic sync or not.
  Future<void> setPlaylistAutoSync(int id, {required bool enabled}) =>
      _updatePlaylist(id, IptvPlaylistsCompanion(autoSync: Value(enabled)));

  Future<void> _updatePlaylist(int id, IptvPlaylistsCompanion values) async {
    await (_db.update(_db.iptvPlaylists)..where((row) => row.id.equals(id))).write(values);
  }

  /// Deletes playlist [id] with its entries.
  Future<void> deletePlaylist(int id) async {
    await (_db.delete(_db.iptvPlaylists)..where((row) => row.id.equals(id))).go();
  }

  /// Puts the playlists in the order of [ids]; others follow in their order.
  Future<void> reorderPlaylists(List<int> ids) => _db.transaction(() async {
    final current = [for (final playlist in await playlists()) playlist.id];
    final ordered = [...ids.where(current.contains), ...current.where((id) => !ids.contains(id))];
    for (final (index, id) in ordered.indexed) {
      await _updatePlaylist(id, IptvPlaylistsCompanion(sortOrder: Value(index)));
    }
  });

  /// Replaces the entries of playlist [id] with [entries] (file order) and
  /// records a successful sync at [syncedAt]. Does nothing when the playlist
  /// was deleted meanwhile.
  Future<void> replaceEntries(int id, List<IptvEntryRecord> entries, {required DateTime syncedAt, String? guideUrl}) =>
      _db.transaction(() async {
        final exists = await (_db.select(_db.iptvPlaylists)..where((row) => row.id.equals(id))).getSingleOrNull();
        if (exists == null) return;
        await (_db.delete(_db.iptvChannels)..where((row) => row.playlist.equals(id))).go();
        await _db.batch((batch) {
          batch.insertAll(_db.iptvChannels, [
            for (final (index, entry) in entries.indexed)
              IptvChannelsCompanion.insert(
                playlist: id,
                position: index,
                name: entry.name,
                groupName: Value(entry.group),
                url: entry.url,
                tvgId: Value(entry.tvgId),
                tvgName: Value(entry.tvgName),
                logo: Value(entry.logo),
                catchupMode: Value(entry.catchupMode),
                catchupSource: Value(entry.catchupSource),
                catchupDays: Value(entry.catchupDays),
                catchupCorrection: Value(entry.catchupCorrection),
                headers: Value(entry.headers.isEmpty ? null : jsonEncode(entry.headers)),
              ),
          ]);
        });
        await _updatePlaylist(
          id,
          IptvPlaylistsCompanion(
            lastSyncAt: Value(_ms(syncedAt)),
            lastAttemptAt: Value(_ms(syncedAt)),
            lastError: const Value(null),
            guideUrl: Value(guideUrl),
          ),
        );
      });

  /// Records a failed sync of playlist [id]; its entries stay.
  Future<void> recordPlaylistFailure(int id, String error, {required DateTime at}) =>
      _updatePlaylist(id, IptvPlaylistsCompanion(lastAttemptAt: Value(_ms(at)), lastError: Value(error)));

  /// Groups of playlist [id] in the order they first appear.
  Future<List<String>> groups(int id) async {
    final rows = await _db
        .customSelect(
          'SELECT group_name, MIN(position) AS first FROM iptv_channels WHERE playlist = ? '
          'GROUP BY group_name ORDER BY first',
          variables: [Variable<int>(id)],
          readsFrom: {_db.iptvChannels},
        )
        .get();
    return [for (final row in rows) row.read<String>('group_name')];
  }

  /// Distinct channel names in playlist order then file order, each with its
  /// first entry; filtered by [playlistId], [group] and a name [search]
  /// (case-insensitive for ASCII).
  Future<List<IptvEntryRecord>> channels({
    required int offset,
    required int limit,
    int? playlistId,
    String? group,
    String? search,
  }) async {
    final where = <String>[];
    final variables = <Variable<Object>>[];
    if (playlistId != null) {
      where.add('c.playlist = ?');
      variables.add(Variable<int>(playlistId));
    }
    if (group != null) {
      where.add('c.group_name = ?');
      variables.add(Variable<String>(group));
    }
    final text = search?.trim();
    if (text != null && text.isNotEmpty) {
      where.add(r"c.name LIKE ? ESCAPE '\'");
      variables.add(Variable<String>('%${text.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}')}%'));
    }
    // SQLite returns the bare columns of the row that holds MIN(k).
    final rows = await _db
        .customSelect(
          'SELECT c.*, MIN(p.sort_order * 4294967296 + c.position) AS k FROM iptv_channels c '
          'JOIN iptv_playlists p ON p.id = c.playlist '
          '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')} '}'
          'GROUP BY c.name ORDER BY k LIMIT ? OFFSET ?',
          variables: [...variables, Variable<int>(limit), Variable<int>(offset)],
          readsFrom: {_db.iptvChannels, _db.iptvPlaylists},
        )
        .get();
    return [for (final row in rows) _entry(_db.iptvChannels.map(row.data))];
  }

  /// Every entry named [name], in playlist order then file order.
  Future<List<IptvSourceRecord>> sources(String name) async {
    final query =
        _db.select(_db.iptvChannels).join([
            innerJoin(_db.iptvPlaylists, _db.iptvPlaylists.id.equalsExp(_db.iptvChannels.playlist)),
          ])
          ..where(_db.iptvChannels.name.equals(name))
          ..orderBy([OrderingTerm.asc(_db.iptvPlaylists.sortOrder), OrderingTerm.asc(_db.iptvChannels.position)]);
    return [
      for (final row in await query.get())
        IptvSourceRecord(
          entry: _entry(row.readTable(_db.iptvChannels)),
          playlistId: row.readTable(_db.iptvPlaylists).id,
          userAgent: row.readTable(_db.iptvPlaylists).userAgent,
        ),
    ];
  }

  static IptvEntryRecord _entry(IptvChannelRow row) => IptvEntryRecord(
    name: row.name,
    url: row.url,
    group: row.groupName,
    tvgId: row.tvgId,
    tvgName: row.tvgName,
    logo: row.logo,
    catchupMode: row.catchupMode,
    catchupSource: row.catchupSource,
    catchupDays: row.catchupDays,
    catchupCorrection: row.catchupCorrection,
    headers: _headers(row.headers),
  );

  static Map<String, String> _headers(String? json) {
    if (json == null) return const {};
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return const {};
      return {
        for (final MapEntry(:key, :value) in decoded.entries)
          if (key is String && value is String) key: value,
      };
    } on FormatException {
      return const {};
    }
  }

  // ------------------------------------------------------------ guide sources

  static const _guideQuery =
      'SELECT g.*, (SELECT COUNT(*) FROM iptv_guide_channels c WHERE c.source = g.id) AS channel_count '
      'FROM iptv_guide_sources g ORDER BY g.sort_order, g.id';

  Selectable<IptvGuideSourceRecord> _guides() => _db
      .customSelect(_guideQuery, readsFrom: {_db.iptvGuideSources, _db.iptvGuideChannels})
      .map(
        (row) => IptvGuideSourceRecord(
          id: row.read<int>('id'),
          name: row.read<String>('name'),
          source: row.read<String>('source'),
          order: row.read<int>('sort_order'),
          autoSync: row.read<bool>('auto_sync'),
          selected: row.read<bool>('selected'),
          lastSyncAt: _time(row.readNullable<int>('last_sync_at')),
          lastAttemptAt: _time(row.readNullable<int>('last_attempt_at')),
          lastError: row.readNullable<String>('last_error'),
          channelCount: row.read<int>('channel_count'),
        ),
      );

  /// Guide sources in the user's order.
  Future<List<IptvGuideSourceRecord>> guideSources() => _guides().get();

  /// Guide sources, re-emitted after every change.
  Stream<List<IptvGuideSourceRecord>> watchGuideSources() => _guides().watch();

  /// The selected guide source, or null.
  Future<IptvGuideSourceRecord?> selectedGuideSource() async =>
      (await guideSources()).where((source) => source.selected).firstOrNull;

  /// Adds a guide source and returns its id; the first one is selected.
  Future<int> addGuideSource({required String name, required String source, DateTime? now}) =>
      _db.transaction(() async {
        final last = await _maxOrder('iptv_guide_sources');
        final anySelected = await (_db.select(_db.iptvGuideSources)..where((row) => row.selected)).get();
        return await _db
            .into(_db.iptvGuideSources)
            .insert(
              IptvGuideSourcesCompanion.insert(
                name: name.trim(),
                source: source.trim(),
                selected: Value(anySelected.isEmpty),
                sortOrder: last + 1,
                createdAt: _ms(now ?? DateTime.now()),
              ),
            );
      });

  /// Renames guide source [id].
  Future<void> renameGuideSource(int id, String name) =>
      _updateGuide(id, IptvGuideSourcesCompanion(name: Value(name.trim())));

  /// Includes guide source [id] in automatic sync or not.
  Future<void> setGuideAutoSync(int id, {required bool enabled}) =>
      _updateGuide(id, IptvGuideSourcesCompanion(autoSync: Value(enabled)));

  Future<void> _updateGuide(int id, IptvGuideSourcesCompanion values) async {
    await (_db.update(_db.iptvGuideSources)..where((row) => row.id.equals(id))).write(values);
  }

  /// Makes [id] the selected guide; null selects none.
  Future<void> selectGuideSource(int? id) => _db.transaction(() async {
    await _db.update(_db.iptvGuideSources).write(const IptvGuideSourcesCompanion(selected: Value(false)));
    if (id != null) await _updateGuide(id, const IptvGuideSourcesCompanion(selected: Value(true)));
  });

  /// Deletes guide source [id] with its channels and programmes. When it was
  /// selected, the first remaining source is selected.
  Future<void> deleteGuideSource(int id) => _db.transaction(() async {
    final row = await (_db.select(_db.iptvGuideSources)..where((g) => g.id.equals(id))).getSingleOrNull();
    await (_db.delete(_db.iptvGuideSources)..where((g) => g.id.equals(id))).go();
    if (row != null && row.selected) {
      final next = (await guideSources()).firstOrNull;
      if (next != null) await _updateGuide(next.id, const IptvGuideSourcesCompanion(selected: Value(true)));
    }
  });

  /// Replaces the channels and programmes of guide source [id] and records a
  /// successful sync at [syncedAt]. Does nothing when the source was deleted
  /// meanwhile.
  Future<void> replaceGuide(
    int id,
    List<IptvGuideChannelRecord> channels,
    List<IptvProgrammeRecord> programmes, {
    required DateTime syncedAt,
  }) => _db.transaction(() async {
    final exists = await (_db.select(_db.iptvGuideSources)..where((row) => row.id.equals(id))).getSingleOrNull();
    if (exists == null) return;
    await (_db.delete(_db.iptvGuideChannels)..where((row) => row.source.equals(id))).go();
    await (_db.delete(_db.iptvProgrammes)..where((row) => row.source.equals(id))).go();
    await _db.batch((batch) {
      batch
        ..insertAll(_db.iptvGuideChannels, [
          for (final channel in channels)
            IptvGuideChannelsCompanion.insert(
              source: id,
              channelId: channel.channelId,
              names: Value(channel.names.join(_separator)),
              icon: Value(channel.icon),
            ),
        ], mode: InsertMode.insertOrReplace)
        ..insertAll(_db.iptvProgrammes, [
          for (final programme in programmes)
            IptvProgrammesCompanion.insert(
              source: id,
              channelId: programme.channelId,
              start: _ms(programme.start),
              stop: _ms(programme.stop),
              title: programme.title,
              subtitle: Value(programme.subtitle),
              description: Value(programme.description),
              catchupId: Value(programme.catchupId),
            ),
        ]);
    });
    await _updateGuide(
      id,
      IptvGuideSourcesCompanion(
        lastSyncAt: Value(_ms(syncedAt)),
        lastAttemptAt: Value(_ms(syncedAt)),
        lastError: const Value(null),
      ),
    );
  });

  /// Records a failed sync of guide source [id]; its data stays.
  Future<void> recordGuideFailure(int id, String error, {required DateTime at}) =>
      _updateGuide(id, IptvGuideSourcesCompanion(lastAttemptAt: Value(_ms(at)), lastError: Value(error)));

  /// Channels of guide source [id].
  Future<List<IptvGuideChannelRecord>> guideChannels(int id) async {
    final rows = await (_db.select(_db.iptvGuideChannels)..where((row) => row.source.equals(id))).get();
    return [
      for (final row in rows)
        IptvGuideChannelRecord(
          channelId: row.channelId,
          names: row.names.isEmpty ? const [] : row.names.split(_separator),
          icon: row.icon,
        ),
    ];
  }

  static IptvProgrammeRecord _programme(IptvProgrammeRow row) => IptvProgrammeRecord(
    channelId: row.channelId,
    start: _time(row.start)!,
    stop: _time(row.stop)!,
    title: row.title,
    subtitle: row.subtitle,
    description: row.description,
    catchupId: row.catchupId,
  );

  /// Programmes of [channelId] in guide source [id] overlapping [from]..[to],
  /// by start.
  Future<List<IptvProgrammeRecord>> programmes(
    int id,
    String channelId, {
    required DateTime from,
    required DateTime to,
  }) async {
    final query = _db.select(_db.iptvProgrammes)
      ..where(
        (row) =>
            row.source.equals(id) &
            row.channelId.equals(channelId) &
            row.stop.isBiggerThanValue(_ms(from)) &
            row.start.isSmallerThanValue(_ms(to)),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.start)]);
    return [for (final row in await query.get()) _programme(row)];
  }

  /// The programme on air at [at] for each of [channelIds] in guide source
  /// [id] that has one.
  Future<Map<String, IptvProgrammeRecord>> programmesAt(int id, Set<String> channelIds, DateTime at) async {
    if (channelIds.isEmpty) return const {};
    final ms = _ms(at);
    final query = _db.select(_db.iptvProgrammes)
      ..where(
        (row) =>
            row.source.equals(id) &
            row.channelId.isIn(channelIds) &
            row.start.isSmallerOrEqualValue(ms) &
            row.stop.isBiggerThanValue(ms),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.start)]);
    return {for (final row in await query.get()) row.channelId: _programme(row)};
  }

  /// Deletes programmes that ended before [before]; returns how many.
  Future<int> pruneProgrammes(DateTime before) =>
      (_db.delete(_db.iptvProgrammes)..where((row) => row.stop.isSmallerThanValue(_ms(before)))).go();
}
