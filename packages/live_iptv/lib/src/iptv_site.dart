import 'package:live_core/live_core.dart';
import 'package:live_iptv/src/catchup.dart';
import 'package:live_iptv/src/guide/matcher.dart';
import 'package:live_iptv/src/model.dart';
import 'package:live_iptv/src/repository.dart';
import 'package:meta/meta.dart';

/// A channel with all its sources and its guide channel.
@immutable
final class IptvChannel {
  /// Creates the channel.
  const new({required this.ref, required this.sources, this.guideId, this.guideChannelId});

  /// Room identity (`iptv:<name>`).
  final RoomRef ref;

  /// Sources in line order.
  final List<IptvSource> sources;

  /// Selected guide, when one is selected.
  final String? guideId;

  /// Matched guide channel, or null.
  final String? guideChannelId;

  /// Channel name.
  String get name => sources.first.entry.name;
}

/// The "网络电视" source (spec/product.md F-IPTV-05, spec/modules/iptv.md §5):
/// channels of the user's playlists browsed and played like rooms.
///
/// - Categories are playlists, areas their groups, area rooms their channels;
///   "recommended" lists every channel, search matches channel names.
/// - A room is a channel name (`iptv:CCTV-1`); every entry with that name in
///   any playlist is one line, in playlist order (F-IPTV-11).
/// - One quality, "原画"; each line carries its headers, the playlist's
///   User-Agent or else the global one.
/// - Cards and details show the programme on air from the selected guide.
final class IptvSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the source over [_repository]. [userAgent] reads the global
  /// custom User-Agent (F-IPTV-04); [now] is injectable for tests.
  new(this._repository, {String? Function()? userAgent, DateTime Function()? now, this.pageSize = 60})
    : _userAgent = userAgent ?? (() => null),
      _now = now ?? DateTime.now;

  /// Platform id.
  static const platformId = 'iptv';

  /// Display name.
  static const displayName = '网络电视';

  /// The only quality.
  static const original = Quality(id: 'original', label: '原画', rank: 0);

  /// Name of the area of entries without a group.
  static const ungrouped = '未分组';

  /// How far back and ahead [guide] reads (the programme sheet, F-IPTV-06).
  static const guideBack = Duration(days: 2);

  /// See [guideBack].
  static const guideAhead = Duration(days: 1);

  final IptvRepository _repository;
  final String? Function() _userAgent;
  final DateTime Function() _now;

  /// Channels per page.
  final int pageSize;

  ({IptvGuideInfo guide, GuideMatcher matcher})? _matcher;

  @override
  String get id => platformId;

  @override
  String get name => displayName;

  /// The room of channel [name]. Names that [RoomRef] rejects as placeholders
  /// (`0`, `null`, …) get a `#` prefix.
  static RoomRef refOf(String name) {
    try {
      return RoomRef(platformId, name);
    } on FormatException {
      return RoomRef(platformId, '#$name');
    }
  }

  /// The channel name of [ref] (the inverse of [refOf]).
  static String nameOf(RoomRef ref) {
    final id = ref.roomId;
    if (id.startsWith('#')) {
      final rest = id.substring(1);
      try {
        RoomRef(platformId, rest);
      } on FormatException {
        return rest;
      }
    }
    return id;
  }

  // ---------------------------------------------------------------- catalog

  @override
  Future<List<Category>> categories() async => [
    for (final playlist in await _repository.playlists())
      Category(
        id: playlist.id,
        name: playlist.name,
        areas: [
          for (final group in await _repository.groups(playlist.id))
            Area(id: '${playlist.id}/$group', name: group.isEmpty ? ungrouped : group, categoryId: playlist.id),
        ],
      ),
  ];

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) {
    final prefix = '${area.categoryId}/';
    final group = area.id.startsWith(prefix) ? area.id.substring(prefix.length) : area.id;
    return _page(cursor, (offset, limit) {
      return _repository.channels(offset: offset, limit: limit, playlistId: area.categoryId, group: group);
    });
  }

  /// Every channel of every playlist.
  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) =>
      _page(cursor, (offset, limit) => _repository.channels(offset: offset, limit: limit));

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) {
    final text = keyword.trim();
    if (text.isEmpty) return Future.value(const Page.empty());
    return _page(cursor, (offset, limit) => _repository.channels(offset: offset, limit: limit, search: text));
  }

  Future<Page<RoomCard>> _page(
    PageCursor? cursor,
    Future<List<IptvChannelInfo>> Function(int offset, int limit) fetch,
  ) async {
    final offset = cursor == null ? 0 : int.tryParse(cursor.value) ?? 0;
    final channels = await fetch(offset, pageSize + 1);
    final shown = channels.take(pageSize).toList();
    final now = _now();
    final guide = await _guide();
    final ids = {
      for (final channel in shown)
        channel.name: guide?.matcher.match(name: channel.name, tvgId: channel.tvgId, tvgName: channel.tvgName),
    };
    final onAir = guide == null
        ? const <String, IptvProgramme>{}
        : await _repository.programmesAt(guide.guide.id, {...ids.values.nonNulls}, now);
    return Page([
      for (final channel in shown) _card(channel.name, channel.group, channel.logo, onAir[ids[channel.name]]),
    ], next: channels.length > pageSize ? PageCursor('${offset + pageSize}') : null);
  }

  RoomCard _card(String name, String group, String? logo, IptvProgramme? programme) => RoomCard(
    ref: refOf(name),
    title: programme?.title ?? name,
    anchorName: name,
    state: LiveState.live,
    cover: _image(logo),
    area: group.isEmpty ? null : group,
    liveSince: programme?.start,
  );

  static Uri? _image(String? url) {
    final uri = Uri.tryParse(url?.trim() ?? '');
    return uri != null && (uri.isScheme('http') || uri.isScheme('https')) && uri.host.isNotEmpty ? uri : null;
  }

  // ------------------------------------------------------------------- room

  /// The channel of [ref] with its sources; throws [NotFound] when no
  /// playlist has it any more.
  Future<IptvChannel> channel(RoomRef ref) async {
    final sources = await _repository.sources(nameOf(ref));
    if (sources.isEmpty) throw const NotFound(platformId, 'No playlist has this channel');
    final guide = await _guide();
    String? guideChannelId;
    if (guide != null) {
      for (final source in sources) {
        final entry = source.entry;
        guideChannelId = guide.matcher.match(name: entry.name, tvgId: entry.tvgId, tvgName: entry.tvgName);
        if (guideChannelId != null) break;
      }
    }
    return IptvChannel(ref: ref, sources: sources, guideId: guide?.guide.id, guideChannelId: guideChannelId);
  }

  /// The channel card with the programme on air as its title.
  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    final channel = await this.channel(ref);
    final programme = await nowPlaying(channel);
    final first = channel.sources.first.entry;
    final logo = channel.sources.map((source) => source.entry.logo).nonNulls.firstOrNull;
    return RoomDetail(
      card: _card(channel.name, first.group, logo, programme),
      link: Uri.tryParse(first.url) ?? Uri(),
      avatar: _image(logo),
      introduction: programme?.description,
    );
  }

  /// One line per source (F-IPTV-11); the quality is always "原画".
  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final channel = await this.channel(room.ref);
    return StreamSet(
      qualities: const [original],
      selected: original,
      lines: [
        for (final (index, source) in channel.sources.indexed) ?_line(index, source, Uri.tryParse(source.entry.url)),
      ],
    );
  }

  StreamLine? _line(int index, IptvSource source, Uri? url) {
    if (url == null || !url.hasScheme) return null;
    final headers = <String, String>{...source.entry.headers};
    final agent = source.userAgent ?? _userAgent();
    if (!headers.containsKey('user-agent') && agent != null && agent.trim().isNotEmpty) {
      headers['user-agent'] = agent.trim();
    }
    final path = url.path.toLowerCase();
    return StreamLine(
      url: url,
      // live_core has no MPEG-TS / RTSP format yet: every non-HLS line is
      // played directly and marked flv (it has no lease, so nothing splices).
      format: path.endsWith('.m3u8') || path.endsWith('.m3u') ? StreamFormat.hls : StreamFormat.flv,
      lineId: 'line${index + 1}',
      requested: original,
      confirmed: original,
      headers: headers,
    );
  }

  /// IPTV has no web links.
  @override
  Future<RoomRef?> resolve(String input) async => null;

  // ------------------------------------------------------------------ guide

  Future<({IptvGuideInfo guide, GuideMatcher matcher})?> _guide() async {
    final guide = await _repository.selectedGuide();
    if (guide == null) return _matcher = null;
    final cached = _matcher;
    if (cached != null && cached.guide == guide) return cached;
    final channels = await _repository.guideChannels(guide.id);
    return _matcher = (guide: guide, matcher: GuideMatcher(channels));
  }

  /// The programme on air on [channel], or null without a guide match.
  Future<IptvProgramme?> nowPlaying(IptvChannel channel) async {
    final guideId = channel.guideId;
    final channelId = channel.guideChannelId;
    if (guideId == null || channelId == null) return null;
    return (await _repository.programmesAt(guideId, {channelId}, _now()))[channelId];
  }

  /// Programmes of [channel] from [guideBack] before to [guideAhead] after
  /// now; empty without a guide match.
  Future<List<IptvProgramme>> guide(IptvChannel channel) async {
    final guideId = channel.guideId;
    final channelId = channel.guideChannelId;
    if (guideId == null || channelId == null) return const [];
    final now = _now();
    return await _repository.programmes(guideId, channelId, from: now.subtract(guideBack), to: now.add(guideAhead));
  }

  /// Whether some source of [channel] can replay [programme].
  CatchupAvailability availability(IptvChannel channel, IptvProgramme programme) {
    final now = _now();
    final results = [for (final source in channel.sources) catchupAvailability(source.entry.catchup, programme, now)];
    if (results.contains(CatchupAvailability.available)) return CatchupAvailability.available;
    if (results.contains(CatchupAvailability.expired)) return CatchupAvailability.expired;
    if (results.every((result) => result == CatchupAvailability.disabled)) return CatchupAvailability.disabled;
    return CatchupAvailability.unsupported;
  }

  /// Lines replaying [programme]: one per source that can replay it, in line
  /// order. Throws [StreamUnavailable] when none can.
  StreamSet catchupStreams(IptvChannel channel, IptvProgramme programme, {Duration? utcOffset}) {
    final now = _now();
    final lines = <StreamLine>[];
    for (final (index, source) in channel.sources.indexed) {
      final entry = source.entry;
      if (catchupAvailability(entry.catchup, programme, now) != CatchupAvailability.available) continue;
      try {
        final url = catchupUrl(
          url: entry.url,
          catchup: entry.catchup,
          programme: programme,
          now: now,
          utcOffset: utcOffset,
        );
        if (_line(index, source, url) case final line?) lines.add(line);
      } on CatchupError {
        continue;
      }
    }
    if (lines.isEmpty) throw const StreamUnavailable(platformId, 'No source can replay this programme');
    return StreamSet(qualities: const [original], selected: original, lines: lines);
  }
}
