import 'package:live_iptv/live_iptv.dart';
import 'package:live_store/live_store.dart';

/// `live_iptv`'s repository over the app database (spec/modules/iptv.md §5):
/// live_store only depends on live_core, so the app converts between its
/// records and the IPTV models.
final class StoreIptvRepository implements IptvRepository {
  const new(this._store);

  final IptvStore _store;

  @override
  Future<List<IptvPlaylistInfo>> playlists() async => [
    for (final playlist in await _store.playlists()) IptvPlaylistInfo(id: '${playlist.id}', name: playlist.name),
  ];

  @override
  Future<List<String>> groups(String playlistId) async {
    final id = int.tryParse(playlistId);
    return id == null ? const [] : await _store.groups(id);
  }

  @override
  Future<List<IptvChannelInfo>> channels({
    required int offset,
    required int limit,
    String? playlistId,
    String? group,
    String? search,
  }) async {
    final id = playlistId == null ? null : int.tryParse(playlistId);
    if (playlistId != null && id == null) return const [];
    return [
      for (final entry in await _store.channels(
        offset: offset,
        limit: limit,
        playlistId: id,
        group: group,
        search: search,
      ))
        IptvChannelInfo(
          name: entry.name,
          group: entry.group,
          logo: entry.logo,
          tvgId: entry.tvgId,
          tvgName: entry.tvgName,
        ),
    ];
  }

  @override
  Future<List<IptvSource>> sources(String name) async => [
    for (final source in await _store.sources(name))
      IptvSource(entry: entryOf(source.entry), playlistId: '${source.playlistId}', userAgent: source.userAgent),
  ];

  @override
  Future<IptvGuideInfo?> selectedGuide() async {
    final source = await _store.selectedGuideSource();
    final synced = source?.lastSyncAt;
    if (source == null || synced == null) return null;
    return IptvGuideInfo(id: '${source.id}', revision: synced.millisecondsSinceEpoch);
  }

  @override
  Future<List<IptvGuideChannel>> guideChannels(String guideId) async {
    final id = int.tryParse(guideId);
    if (id == null) return const [];
    return [
      for (final channel in await _store.guideChannels(id))
        IptvGuideChannel(id: channel.channelId, names: channel.names, icon: channel.icon),
    ];
  }

  @override
  Future<List<IptvProgramme>> programmes(
    String guideId,
    String channelId, {
    required DateTime from,
    required DateTime to,
  }) async {
    final id = int.tryParse(guideId);
    if (id == null) return const [];
    return [for (final record in await _store.programmes(id, channelId, from: from, to: to)) programmeOf(record)];
  }

  @override
  Future<Map<String, IptvProgramme>> programmesAt(String guideId, Set<String> channelIds, DateTime at) async {
    final id = int.tryParse(guideId);
    if (id == null) return const {};
    return {
      for (final MapEntry(:key, :value) in (await _store.programmesAt(id, channelIds, at)).entries)
        key: programmeOf(value),
    };
  }

  /// A stored entry as an IPTV entry.
  static IptvEntry entryOf(IptvEntryRecord record) => IptvEntry(
    name: record.name,
    url: record.url,
    group: record.group,
    tvgId: record.tvgId,
    tvgName: record.tvgName,
    logo: record.logo,
    catchup: IptvCatchup(
      mode: record.catchupMode,
      source: record.catchupSource,
      days: record.catchupDays,
      correction: record.catchupCorrection,
    ),
    headers: record.headers,
  );

  /// A parsed entry as a stored one.
  static IptvEntryRecord recordOf(IptvEntry entry) => IptvEntryRecord(
    name: entry.name,
    url: entry.url,
    group: entry.group,
    tvgId: entry.tvgId,
    tvgName: entry.tvgName,
    logo: entry.logo,
    catchupMode: entry.catchup.mode,
    catchupSource: entry.catchup.source,
    catchupDays: entry.catchup.days,
    catchupCorrection: entry.catchup.correction,
    headers: entry.headers,
  );

  /// A stored programme as an IPTV programme.
  static IptvProgramme programmeOf(IptvProgrammeRecord record) => IptvProgramme(
    channelId: record.channelId,
    start: record.start,
    stop: record.stop,
    title: record.title,
    subtitle: record.subtitle,
    description: record.description,
    catchupId: record.catchupId,
  );
}
