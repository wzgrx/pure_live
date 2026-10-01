import 'package:live_core/live_core.dart';
import 'package:live_iptv/src/guide/matcher.dart';
import 'package:live_iptv/src/importer.dart';
import 'package:live_iptv/src/library.dart';
import 'package:live_iptv/src/model.dart';
import 'package:live_iptv/src/playlist/m3u_parser.dart';
import 'package:live_iptv/src/playlist/txt_parser.dart';

/// The IPTV platform (3.x `IptvSite`): imported playlists shown like a live
/// platform.
///
/// - Categories are the playlists (the built-in hot one excepted); their
///   areas are the channels, and a channel's area opens its room directly.
/// - Recommendations are the hot playlist, imported on first use.
/// - Search matches channel names.
/// - A room is one channel: always live, one quality `默认` (`default`)
///   with the channel URL; the room carries the catch-up attributes, the
///   stream's request headers and, with a selected guide, the guide channel
///   and the programme on air.
/// - Lists are not paged: page 1 holds everything and later pages are empty
///   (3.x returned the whole list for every page).
final class IptvSite extends LiveSite implements LiveSiteRecordRoomResolver {
  /// Creates the platform.
  new({required this.library, required this.importer, required this.selectedGuideSourceId, this.now = DateTime.now});

  /// Storage.
  final IptvLibrary library;

  /// Imports the hot playlist on first use.
  final IptvImporter importer;

  /// The selected guide source id (3.x setting `selectedSourceId`).
  final String Function() selectedGuideSourceId;

  /// Clock for the programme on air.
  final DateTime Function() now;

  /// The quality id of the single quality.
  static const String qualityId = 'default';

  @override
  String get id => SiteIds.iptv;

  @override
  String get name => '网络';

  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    if (page > 1) return const [];
    return [
      for (final playlist in await library.playlists())
        if (!playlist.isHot)
          LiveCategory(
            id: playlist.id,
            name: playlist.name,
            children: [
              for (final channel in await library.channels(playlist.id))
                LiveArea(
                  platform: id,
                  areaType: playlist.id,
                  typeName: playlist.name,
                  areaId: channel.id,
                  areaName: channel.name,
                  areaPic: channel.entry.tvgLogo ?? '',
                ),
            ],
          ),
    ];
  }

  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    if (page > 1) return const [];
    final channel = await library.channel(category.areaId);
    if (channel == null) return const [];
    final guide = await _guide(channel);
    return [_room(channel, nick: channel.entry.groupTitle ?? '', guide: guide)];
  }

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (page > 1) return const [];
    var channels = await library.channels(IptvPlaylist.hotId);
    if (channels.isEmpty) {
      await importer.loadHotPlaylist();
      channels = await library.channels(IptvPlaylist.hotId);
    }
    return [for (final channel in channels) _room(channel, nick: '', introduction: channel.name)];
  }

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    if (page > 1 || keyword.trim().isEmpty) return const [];
    return [
      for (final channel in await library.searchChannels(keyword)) _room(channel, nick: channel.entry.groupTitle ?? ''),
    ];
  }

  /// The room of channel [roomId]. A room id that is itself a stream URL
  /// (3.x played such ids as they are) gives a room playing that URL; any
  /// other unknown id is [NotFound] (3.x returned an empty "live" room that
  /// failed only when played).
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    final channel = await library.channel(roomId);
    if (channel == null) {
      final url = roomId.trim();
      if (!isSupportedStreamUrl(url, {...M3uParser.schemes, ...TxtParser.schemes})) throw NotFound(id, roomId);
      return LiveRoom(roomId: roomId, platform: id, link: url, data: url, watching: '', liveStatus: LiveStatus.live);
    }
    final guide = await _guide(channel);
    return _room(channel, nick: channel.entry.tvgName ?? channel.name, guide: guide);
  }

  /// The stored channel is authoritative, so the recording detail is the
  /// room detail.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => getRoomDetail(roomId: roomId);

  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    final url = detail.data?.toString().trim() ?? '';
    if (url.isEmpty) return const [];
    return [
      LivePlayQuality(quality: '默认', id: qualityId, sort: 1, data: [url]),
    ];
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    final data = quality.data;
    if (data is! List) return const [];
    return [
      for (final item in data)
        if (item.toString().trim() case final url when url.isNotEmpty) url,
    ];
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async => true;

  Future<({String key, EpgProgramme? programme})?> _guide(IptvChannel channel) async {
    final sourceId = selectedGuideSourceId();
    if (sourceId.isEmpty) return null;
    final mappings = await library.mappings(channel.playlistId);
    final key = resolveGuideChannel(
      channel: channel,
      sourceId: sourceId,
      guideChannels: await library.guideChannels(sourceId),
      mapping: mappings.where((mapping) => mapping.channelId == channel.id).firstOrNull,
    );
    if (key == null) return null;
    final onAir = await library.programmesAt({key}, now());
    return (key: key, programme: onAir.firstOrNull);
  }

  LiveRoom _room(
    IptvChannel channel, {
    required String nick,
    ({String key, EpgProgramme? programme})? guide,
    String? introduction,
  }) {
    final entry = channel.entry;
    return LiveRoom(
      roomId: channel.id,
      platform: id,
      title: entry.name,
      nick: nick,
      cover: entry.tvgLogo ?? '',
      area: entry.groupTitle ?? '',
      watching: '',
      liveStatus: LiveStatus.live,
      introduction: introduction,
      link: entry.streamUrl,
      data: entry.streamUrl,
      epgId: guide?.key,
      currentProgramme: guide?.programme?.title,
      currentProgrammeDescription: guide?.programme?.description,
      catchUp: CatchUp(
        mode: entry.catchupMode,
        source: entry.catchupSource,
        days: entry.catchupDays,
        correctionHours: entry.catchupCorrectionHours,
      ),
      httpHeaders: entry.httpHeaders,
    );
  }
}
