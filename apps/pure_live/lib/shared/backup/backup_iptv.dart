import 'package:live_iptv/live_iptv.dart';

// The IPTV playlists in a full backup (new in v4, F.5a item 5): 3.x's
// backup carried the IPTV settings only (section `iptv`), so a new device or
// a reinstall had to import every playlist again. The section is
// `iptvLibrary` beside 3.x's `iptv`; 3.x and `BackupService` ignore it.

/// The backup section of the IPTV playlists and guide sources.
const String iptvLibrarySection = 'iptvLibrary';

/// The playlists of the backup section: one playlist with its channels (the
/// ids kept, so followed IPTV channels still match) and its guide mappings.
typedef IptvBackupPlaylist = ({IptvPlaylist playlist, List<IptvChannel> channels, List<EpgMapping> mappings});

/// What the section holds.
typedef IptvBackup = ({List<IptvBackupPlaylist> playlists, List<EpgSource> guides});

/// The section of [library]: every playlist but the built-in hot one with
/// its channels and mappings, and the guide sources by name and address
/// (their programmes are fetched again by the next sync).
Future<Map<String, Object?>> exportIptvLibrary(IptvLibrary library) async => {
  'playlists': [
    for (final playlist in await library.playlists())
      if (!playlist.isHot)
        {
          ..._playlistJson(playlist),
          'channels': [for (final channel in await library.channels(playlist.id)) _channelJson(channel)],
          'mappings': [for (final mapping in await library.mappings(playlist.id)) _mappingJson(mapping)],
        },
  ],
  'guides': [for (final source in await library.guideSources()) _guideJson(source)],
};

/// The section of a backup file, or null when the file has none (3.x's
/// files). Entries that cannot be read, and a playlist id met again, are
/// left out.
IptvBackup? iptvBackupIn(Map<String, Object?> json) {
  final section = json[iptvLibrarySection];
  if (section is! Map) return null;
  final playlists = <IptvBackupPlaylist>[];
  final seen = <String>{};
  for (final item in _maps(section['playlists'])) {
    final playlist = _playlist(item);
    if (playlist == null || playlist.isHot || !seen.add(playlist.id)) continue;
    playlists.add((
      playlist: playlist,
      channels: [for (final channel in _maps(item['channels'])) ?_channel(channel, playlist.id)],
      mappings: [for (final mapping in _maps(item['mappings'])) ?_mapping(mapping, playlist.id)],
    ));
  }
  return (playlists: playlists, guides: [for (final guide in _maps(section['guides'])) ?_guide(guide)]);
}

/// Applies [backup] to [library]: the playlists become the file's (the
/// built-in hot one stays), the guide sources the file has and the library
/// lacks (by id or address) are added without programmes.
Future<void> restoreIptvLibrary(IptvLibrary library, IptvBackup backup) async {
  final guides = await library.guideSources();
  for (final guide in backup.guides) {
    final known = guides.any((saved) => saved.id == guide.id || saved.source.trim() == guide.source.trim());
    if (!known) await library.saveGuide(guide, const [], const [], expected: null);
  }
  // Removed first: a channel id moving between playlists cannot collide.
  for (final saved in await library.playlists()) {
    if (!saved.isHot) await library.deletePlaylist(saved);
  }
  for (final (:playlist, :channels, :mappings) in backup.playlists) {
    final kept = {for (final channel in channels) channel.id};
    await library.savePlaylist(
      playlist,
      channels,
      expected: null,
      mappings: (
        upserts: [
          for (final mapping in mappings)
            if (kept.contains(mapping.channelId)) mapping,
        ],
        deletes: const [],
      ),
    );
  }
}

Iterable<Map<Object?, Object?>> _maps(Object? value) =>
    value is List ? value.whereType<Map<Object?, Object?>>() : const [];

String? _string(Object? value) => value is String ? value : null;

int? _int(Object? value) => value is num ? value.toInt() : null;

double? _double(Object? value) => value is num ? value.toDouble() : null;

DateTime? _time(Object? value) => value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;

Map<String, Object?> _playlistJson(IptvPlaylist playlist) => {
  'id': playlist.id,
  'name': playlist.name,
  'format': playlist.format.name,
  'source': playlist.source,
  'sortOrder': playlist.sortOrder,
  'lastRefresh': playlist.lastRefresh?.millisecondsSinceEpoch,
  'createdAt': playlist.createdAt?.millisecondsSinceEpoch,
  'autoUpdate': playlist.autoUpdate,
};

IptvPlaylist? _playlist(Map<Object?, Object?> json) {
  final id = _string(json['id'])?.trim() ?? '';
  final name = _string(json['name'])?.trim() ?? '';
  final format = IptvPlaylistFormat.fromType(_string(json['format']));
  if (id.isEmpty || name.isEmpty || format == null) return null;
  return IptvPlaylist(
    id: id,
    name: name,
    format: format,
    source: _string(json['source']) ?? '',
    sortOrder: _int(json['sortOrder']) ?? 0,
    lastRefresh: _time(json['lastRefresh']),
    createdAt: _time(json['createdAt']),
    autoUpdate: json['autoUpdate'] != false,
  );
}

Map<String, Object?> _channelJson(IptvChannel channel) {
  final entry = channel.entry;
  return {
    'id': channel.id,
    'name': entry.name,
    'url': entry.streamUrl,
    'tvgId': entry.tvgId,
    'tvgName': entry.tvgName,
    'tvgLogo': entry.tvgLogo,
    'group': entry.groupTitle,
    'number': entry.channelNumber,
    'type': entry.streamType.name,
    'catchupMode': entry.catchupMode,
    'catchupSource': entry.catchupSource,
    'catchupDays': entry.catchupDays,
    'catchupCorrectionHours': entry.catchupCorrectionHours,
    'headers': entry.httpHeaders,
    'favorite': channel.favorite,
    'hidden': channel.hidden,
    'sortOrder': channel.sortOrder,
    'autoUpdate': channel.autoUpdate,
  };
}

IptvChannel? _channel(Map<Object?, Object?> json, String playlistId) {
  final id = _string(json['id'])?.trim() ?? '';
  final url = _string(json['url'])?.trim() ?? '';
  if (id.isEmpty || url.isEmpty) return null;
  final headers = json['headers'];
  return IptvChannel(
    id: id,
    playlistId: playlistId,
    entry: IptvEntry(
      name: _string(json['name']) ?? '',
      streamUrl: url,
      tvgId: _string(json['tvgId']),
      tvgName: _string(json['tvgName']),
      tvgLogo: _string(json['tvgLogo']),
      groupTitle: _string(json['group']),
      channelNumber: _int(json['number']),
      streamType: IptvStreamType.fromName(_string(json['type'])),
      catchupMode: _string(json['catchupMode']),
      catchupSource: _string(json['catchupSource']),
      catchupDays: _double(json['catchupDays']),
      catchupCorrectionHours: _double(json['catchupCorrectionHours']),
      httpHeaders: {
        if (headers is Map)
          for (final MapEntry(:key, :value) in headers.entries)
            if (key is String && value is String) key: value,
      },
    ),
    favorite: json['favorite'] == true,
    hidden: json['hidden'] == true,
    sortOrder: _int(json['sortOrder']) ?? 0,
    autoUpdate: json['autoUpdate'] != false,
  );
}

Map<String, Object?> _mappingJson(EpgMapping mapping) => {
  'channelId': mapping.channelId,
  'channelKey': mapping.epgChannelKey,
  'sourceId': mapping.epgSourceId,
  'origin': mapping.origin,
  'locked': mapping.locked,
};

EpgMapping? _mapping(Map<Object?, Object?> json, String playlistId) {
  final channel = _string(json['channelId']) ?? '';
  final key = _string(json['channelKey']) ?? '';
  final source = _string(json['sourceId']) ?? '';
  if (channel.isEmpty || key.isEmpty || source.isEmpty) return null;
  return EpgMapping(
    channelId: channel,
    playlistId: playlistId,
    epgChannelKey: key,
    epgSourceId: source,
    origin: _string(json['origin']) ?? EpgMapping.autoOrigin,
    locked: json['locked'] == true,
  );
}

Map<String, Object?> _guideJson(EpgSource source) => {
  'id': source.id,
  'name': source.name,
  'source': source.source,
  'lastRefresh': source.lastRefresh?.millisecondsSinceEpoch,
  'createdAt': source.createdAt?.millisecondsSinceEpoch,
  'autoUpdate': source.autoUpdate,
};

EpgSource? _guide(Map<Object?, Object?> json) {
  final id = _string(json['id'])?.trim() ?? '';
  final name = _string(json['name'])?.trim() ?? '';
  final source = _string(json['source'])?.trim() ?? '';
  if (id.isEmpty || name.isEmpty || source.isEmpty) return null;
  return EpgSource(
    id: id,
    name: name,
    source: source,
    lastRefresh: _time(json['lastRefresh']),
    createdAt: _time(json['createdAt']),
    autoUpdate: json['autoUpdate'] != false,
  );
}
