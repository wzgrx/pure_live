import 'package:live_iptv/src/model.dart';

/// Thrown when a saved playlist or guide source changed or disappeared while
/// an import or sync was running; nothing is written (3.x compared the row
/// it started from with the current one inside the transaction).
final class StaleIptvSnapshot implements Exception {
  /// Creates the error.
  const new();

  @override
  String toString() => 'Saved IPTV source changed while the import was pending';
}

/// Where IPTV data lives: playlists with their channels, guide sources with
/// their channels and programmes, and the channel-to-guide mappings (3.x's
/// drift database `pure_live_tv.db`). The app implements it over its
/// database (M9); [MemoryIptvLibrary] serves tests and tools.
///
/// Every write is atomic: it either happens completely or not at all, and a
/// write given an `expected` snapshot throws [StaleIptvSnapshot] without
/// writing when the saved row differs (or exists when null was expected).
abstract interface class IptvLibrary {
  /// Saved playlists, in import order.
  Future<List<IptvPlaylist>> playlists();

  /// Playlist [id], or null.
  Future<IptvPlaylist?> playlist(String id);

  /// Channels of playlist [playlistId], in file order.
  Future<List<IptvChannel>> channels(String playlistId);

  /// Channel [id], or null.
  Future<IptvChannel?> channel(String id);

  /// Channels of every playlist whose name contains [keyword] (ASCII
  /// letters case-insensitive), by name (3.x: SQL `LIKE`, ordered by name).
  Future<List<IptvChannel>> searchChannels(String keyword);

  /// Replaces playlist [playlist] and all its channels; channels not in
  /// [channels] are deleted with their mappings. [mappings] (from
  /// `rebuildMappings`) are applied in the same write.
  Future<void> savePlaylist(
    IptvPlaylist playlist,
    List<IptvChannel> channels, {
    required IptvPlaylist? expected,
    ({List<EpgMapping> upserts, List<EpgMapping> deletes}) mappings = (upserts: const [], deletes: const []),
  });

  /// Updates the fields of a playlist (name, auto sync) without touching
  /// its channels.
  Future<void> updatePlaylist(IptvPlaylist playlist);

  /// Deletes playlist [expected] with its channels and mappings; false when
  /// the saved row differs.
  Future<bool> deletePlaylist(IptvPlaylist expected);

  /// Mappings of playlist [playlistId].
  Future<List<EpgMapping>> mappings(String playlistId);

  /// Guide sources, in import order.
  Future<List<EpgSource>> guideSources();

  /// Guide source [id], or null.
  Future<EpgSource?> guideSource(String id);

  /// Channels of guide source [sourceId].
  Future<List<EpgChannel>> guideChannels(String sourceId);

  /// Replaces guide source [source] with its channels and programmes, and
  /// deletes the sources in [duplicates] (same name) with their data.
  Future<void> saveGuide(
    EpgSource source,
    List<EpgChannel> channels,
    List<EpgProgramme> programmes, {
    required EpgSource? expected,
    List<EpgSource> duplicates = const [],
  });

  /// Updates the fields of a guide source without touching its data.
  Future<void> updateGuideSource(EpgSource source);

  /// Deletes guide source [expected] with its channels, programmes and the
  /// mappings to it; false when the saved row differs.
  Future<bool> deleteGuideSource(EpgSource expected);

  /// Programmes of guide channel [channelKey] that start at or after
  /// [from] and stop at or before [to], by start.
  Future<List<EpgProgramme>> programmes(String channelKey, {required DateTime from, required DateTime to});

  /// Programmes of [channelKeys] on air at [at] (start ≤ at ≤ stop).
  Future<List<EpgProgramme>> programmesAt(Set<String> channelKeys, DateTime at);

  /// Deletes programmes that stopped before [before].
  Future<void> pruneProgrammes(DateTime before);
}

/// An [IptvLibrary] in memory.
final class MemoryIptvLibrary implements IptvLibrary {
  final _playlists = <String, IptvPlaylist>{};
  final _channels = <String, List<IptvChannel>>{};
  final _mappings = <String, Map<String, EpgMapping>>{};
  final _sources = <String, EpgSource>{};
  final _guideChannels = <String, List<EpgChannel>>{};
  final _programmes = <String, List<EpgProgramme>>{};

  @override
  Future<List<IptvPlaylist>> playlists() async => _playlists.values.toList();

  @override
  Future<IptvPlaylist?> playlist(String id) async => _playlists[id];

  @override
  Future<List<IptvChannel>> channels(String playlistId) async => List.of(_channels[playlistId] ?? const []);

  @override
  Future<IptvChannel?> channel(String id) async {
    for (final list in _channels.values) {
      for (final channel in list) {
        if (channel.id == id) return channel;
      }
    }
    return null;
  }

  @override
  Future<List<IptvChannel>> searchChannels(String keyword) async {
    final needle = _asciiLower(keyword);
    return [
      for (final list in _channels.values)
        for (final channel in list)
          if (_asciiLower(channel.name).contains(needle)) channel,
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  static String _asciiLower(String value) =>
      String.fromCharCodes(value.codeUnits.map((unit) => unit >= 65 && unit <= 90 ? unit + 32 : unit));

  @override
  Future<void> savePlaylist(
    IptvPlaylist playlist,
    List<IptvChannel> channels, {
    required IptvPlaylist? expected,
    ({List<EpgMapping> upserts, List<EpgMapping> deletes}) mappings = (upserts: const [], deletes: const []),
  }) async {
    if (_playlists[playlist.id] != expected) throw const StaleIptvSnapshot();
    _playlists[playlist.id] = playlist;
    _channels[playlist.id] = List.of(channels);
    final kept = {for (final channel in channels) channel.id};
    final saved = _mappings.putIfAbsent(playlist.id, () => {})..removeWhere((id, _) => !kept.contains(id));
    for (final mapping in mappings.deletes) {
      saved.remove(mapping.channelId);
    }
    for (final mapping in mappings.upserts) {
      saved[mapping.channelId] = mapping;
    }
  }

  @override
  Future<void> updatePlaylist(IptvPlaylist playlist) async {
    if (_playlists.containsKey(playlist.id)) _playlists[playlist.id] = playlist;
  }

  @override
  Future<bool> deletePlaylist(IptvPlaylist expected) async {
    if (_playlists[expected.id] != expected) return false;
    _playlists.remove(expected.id);
    _channels.remove(expected.id);
    _mappings.remove(expected.id);
    return true;
  }

  @override
  Future<List<EpgMapping>> mappings(String playlistId) async => (_mappings[playlistId] ?? const {}).values.toList();

  @override
  Future<List<EpgSource>> guideSources() async => _sources.values.toList();

  @override
  Future<EpgSource?> guideSource(String id) async => _sources[id];

  @override
  Future<List<EpgChannel>> guideChannels(String sourceId) async => List.of(_guideChannels[sourceId] ?? const []);

  @override
  Future<void> saveGuide(
    EpgSource source,
    List<EpgChannel> channels,
    List<EpgProgramme> programmes, {
    required EpgSource? expected,
    List<EpgSource> duplicates = const [],
  }) async {
    if (_sources[source.id] != expected) throw const StaleIptvSnapshot();
    for (final duplicate in duplicates) {
      if (_sources[duplicate.id] != duplicate) throw const StaleIptvSnapshot();
    }
    for (final duplicate in duplicates) {
      _removeSource(duplicate.id);
    }
    _sources[source.id] = source;
    _guideChannels[source.id] = List.of(channels);
    _programmes[source.id] = List.of(programmes);
  }

  @override
  Future<void> updateGuideSource(EpgSource source) async {
    if (_sources.containsKey(source.id)) _sources[source.id] = source;
  }

  @override
  Future<bool> deleteGuideSource(EpgSource expected) async {
    if (_sources[expected.id] != expected) return false;
    _removeSource(expected.id);
    return true;
  }

  void _removeSource(String id) {
    _sources.remove(id);
    _guideChannels.remove(id);
    _programmes.remove(id);
    for (final saved in _mappings.values) {
      saved.removeWhere((_, mapping) => mapping.epgSourceId == id);
    }
  }

  @override
  Future<List<EpgProgramme>> programmes(String channelKey, {required DateTime from, required DateTime to}) async => [
    for (final list in _programmes.values)
      for (final programme in list)
        if (programme.channelKey == channelKey && !programme.start.isBefore(from) && !programme.stop.isAfter(to))
          programme,
  ]..sort((a, b) => a.start.compareTo(b.start));

  @override
  Future<List<EpgProgramme>> programmesAt(Set<String> channelKeys, DateTime at) async => [
    for (final list in _programmes.values)
      for (final programme in list)
        if (channelKeys.contains(programme.channelKey) && !programme.start.isAfter(at) && !programme.stop.isBefore(at))
          programme,
  ];

  @override
  Future<void> pruneProgrammes(DateTime before) async {
    for (final list in _programmes.values) {
      list.removeWhere((programme) => programme.stop.isBefore(before));
    }
  }
}
