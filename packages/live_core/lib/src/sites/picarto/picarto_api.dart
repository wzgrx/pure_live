import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'picarto';
const _web = 'https://picarto.tv';

/// What a danmaku connection needs to join one channel's chat.
///
/// 3.x had no Picarto danmaku (`EmptyDanmaku`); the archived v4 connected
/// with these two keys (a JWT asked for the channel name, then the chat
/// socket). Whether the app shows Picarto danmaku is the danmaku module's
/// decision (M5); room entry only hands them over, without a request.
@immutable
final class PicartoDanmakuArgs {
  /// Creates the arguments.
  const new({required this.channelName, required this.channelId});

  /// The channel name as the platform writes it (`generateJwtToken` takes
  /// it).
  final String channelName;

  /// The channel's numeric id; chat messages name their channel by it.
  final int channelId;

  @override
  String toString() => 'PicartoDanmakuArgs($channelName, $channelId)';
}

/// The stream behind a live room: 3.x parsed the master playlist on room
/// entry and kept its qualities in `data`.
@immutable
final class PicartoRoomData {
  /// Creates the data.
  new({
    required this.name,
    required this.channelId,
    required this.master,
    required List<LivePlayQuality> qualities,
    String? requestedId,
  }) : qualities = List.unmodifiable(qualities),
       requestedId = requestedId ?? name;

  /// The channel name as the platform writes it (`TheBaker`), which is also
  /// the room id.
  final String name;

  /// The name as it was asked for (`thebaker` from a lower-case link); kept
  /// for reference only.
  final String requestedId;

  /// The channel's numeric id, which picks its own stream in a multistream
  /// group.
  final int channelId;

  /// The HLS master playlist on the edge the load balancer chose.
  final Uri master;

  /// Qualities of [master], best first; `data` holds each one's playlist
  /// URLs.
  final List<LivePlayQuality> qualities;
}

/// A `channel/detail` answer: the room under the platform's spelling of its
/// name, and what streams and danmaku need.
@immutable
final class PicartoChannel {
  /// Creates the answer.
  const new({required this.room, required this.name, required this.channelId, required this.requestedId, this.master});

  /// The room, without stream data or danmaku arguments.
  final LiveRoom room;

  /// The channel name as the platform writes it, the room id.
  final String name;

  /// The name as it was asked for.
  final String requestedId;

  /// The channel's numeric id.
  final int channelId;

  /// The HLS master playlist when the channel is live, else null.
  final Uri? master;
}

/// Pure parsing of Picarto responses (3.x's `PicartoApi` and
/// `parsePicartoHls`, with the archived v4 parser's additions). Each
/// function takes the response text and status and returns 3.x's models or
/// throws a `SiteError`.
///
/// Answers are checked as 3.x did (a page that does not match its request
/// is `ApiChanged`), except that a bad row is left out and only an answer
/// without any usable row fails (11-3), so a change of format is still not
/// shown as an empty list.
abstract final class PicartoApi {
  /// Desktop Chrome 140, the UA 3.x's player sent to the media servers
  /// (`PlaybackHeaderResolver`).
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/140.0.0.0 Safari/537.36';

  /// Web origin: `Origin`, and with a trailing `/` `Referer`, of every
  /// request.
  static const String origin = _web;

  /// Host of the site's internal API.
  static const String apiHost = 'ptvintern.picarto.tv';

  /// Host of the public API (v1). Of its answers only the start of the
  /// broadcast on air (`last_live`) is used: the internal API has none.
  static const String publicApiHost = 'api.picarto.tv';

  /// The title Picarto gives a channel whose streamer never set one (11 of
  /// 186 live channels on 2026-09-28). A placeholder: it is left empty, so
  /// it never replaces a follow's stored title (the unified rule, X-2).
  static const String placeholderTitle = 'My Channel Title';

  /// The headers of every request, names in lower case: 3.x's
  /// `PicartoApi.playHeaders` (`Referer`, `Origin`) with the desktop UA its
  /// player added. 3.x's API and master playlist requests carried no UA of
  /// their own (dart:io's `Dart/…` went out).
  static const Map<String, String> headers = {'user-agent': userAgent, 'referer': '$_web/', 'origin': _web};

  /// The explore page size 3.x's directory pager used.
  static const int pageSize = 30;

  /// Largest page 3.x asked for (`first`); larger sizes are clamped.
  static const int maxPageSize = 60;

  /// Longest search keyword 3.x sent.
  static const int maxKeywordLength = 100;

  /// Largest answer 3.x accepted (1 MiB); a larger one is `ApiChanged`.
  static const int responseLimit = 1024 * 1024;

  /// The single category of the catalog (3.x's `LiveCategory(id: 'picarto',
  /// name: 'Picarto')`).
  static const ({String id, String name}) category = (id: _site, name: 'Picarto');

  /// The first area of the catalog: every public live channel, adult
  /// content excluded (the recommendations). The name is 3.x's Chinese text
  /// of `picarto_public_directory`; the interface may show its own
  /// translation for `areaType: 'directory'` (M13).
  static const LiveArea publicDirectory = LiveArea(
    platform: _site,
    areaType: 'directory',
    typeName: 'Picarto',
    areaId: 'live',
    areaName: '公开直播（不含成人内容）',
  );

  /// Channel names: letters, digits and `_`, 1–50 characters.
  static final RegExp namePattern = RegExp(r'^[a-zA-Z0-9_]{1,50}$');

  /// Site paths that are never channels (3.x's list, case ignored).
  static const Set<String> reservedNames = {
    'explore',
    'search',
    'settings',
    'login',
    'signup',
    'register',
    'password',
    'terms',
    'privacy',
    'help',
    'about',
  };

  /// Whether [name] is a channel name (3.x's `channelName`).
  static bool isChannelName(String name) => namePattern.hasMatch(name) && !reservedNames.contains(name.toLowerCase());

  /// The channel page of [name].
  static String roomPageUrl(String name) => '$_web/${Uri.encodeComponent(name.trim())}';

  // Catalog -------------------------------------------------------------------

  /// `api/languages-categories`: the platform's categories in answer order,
  /// each an area of [category] (`areaType: 'category'`). An entry without
  /// a valid id or label, or repeating an id, is left out (11-3; 3.x failed
  /// the catalog); no list, more than 200 entries or no valid entry at all
  /// is `ApiChanged` (3.x surfaced them rather than an empty catalog).
  static List<LiveArea> categories(String body, {int status = 200}) {
    final root = _root(body, status: status, what: 'languages-categories');
    final rows = root['categories'];
    if (rows is! List || rows.isEmpty || rows.length > 200) {
      throw ApiChanged(_site, 'languages-categories: no category list (${_snippet(body)})');
    }
    final areas = <String, LiveArea>{};
    for (final raw in rows) {
      final item = _object(raw);
      final id = jsonInt(item?['id']);
      final label = jsonString(item?['label']) ?? '';
      if (id == null || id <= 0 || label.length > 100 || label.isEmpty || areas.containsKey('$id')) continue;
      areas['$id'] = LiveArea(
        platform: _site,
        areaType: 'category',
        typeName: category.name,
        areaId: '$id',
        areaName: label,
      );
    }
    if (areas.isEmpty) throw ApiChanged(_site, 'languages-categories: no valid category (${_snippet(body)})');
    return List.unmodifiable(areas.values);
  }

  /// The catalog 3.x showed: one category holding [publicDirectory] and then
  /// the areas of [categories].
  static LiveCategory catalog(String body, {int status = 200}) => LiveCategory(
    id: category.id,
    name: category.name,
    children: [
      publicDirectory,
      ...categories(body, status: status),
    ],
  );

  // Directory -----------------------------------------------------------------

  /// An `api/explore` page: live, non-adult channels by viewers, one per
  /// name (case ignored). The page must be the one asked for ([page],
  /// [pageSize]). A row that is no channel (no valid name, id, state or
  /// `adult` flag) or, with [categoryId], not of that category is left out
  /// (11-3; 3.x failed the page); a page none of whose rows is usable is
  /// `ApiChanged` (a changed format, or a category filter the API ignored).
  /// More pages follow while [page] is below `last_page` (the row count
  /// proves nothing: offline and adult rows are left out). Rows say nothing
  /// about private channels or start times: `restriction` and `startedAt`
  /// stay null.
  static LiveDirectoryPage directoryPage(
    String body, {
    required int page,
    required int pageSize,
    int? categoryId,
    int status = 200,
  }) {
    final root = _root(body, status: status, what: 'explore');
    final rows = root['data'];
    final last = jsonInt(root['last_page']);
    final total = jsonInt(root['total']);
    if (rows is! List ||
        rows.length > pageSize ||
        jsonInt(root['current_page']) != page ||
        jsonInt(root['per_page']) != pageSize ||
        last == null ||
        last < 1 ||
        total == null ||
        total < 0 ||
        (page > last && rows.isNotEmpty)) {
      throw ApiChanged(_site, 'explore: not page $page of $pageSize (${_snippet(body)})');
    }
    final rooms = <String, LiveRoom>{};
    var usable = 0;
    for (final raw in rows) {
      final row = _object(raw);
      if (row == null || row['adult'] is! bool || !_isChannel(row)) continue;
      if (categoryId != null) {
        final categories = row['categories'];
        if (categories is! List || !categories.any((value) => jsonInt(_object(value)?['id']) == categoryId)) continue;
      }
      usable++;
      final room = _card(row);
      // Filtering, not an invented offline state: adult and offline rows
      // are left out, and a short page is not topped up from the next.
      if (row['adult'] != false || !room.isLiveNow) continue;
      rooms.putIfAbsent(room.roomId.toLowerCase(), () => room);
    }
    if (rows.isNotEmpty && usable == 0) {
      throw ApiChanged(
        _site,
        'explore: no usable row${categoryId == null ? '' : ' of category $categoryId'} (${_snippet(body)})',
      );
    }
    return LiveDirectoryPage(rooms: rooms.values, page: page, hasMore: page < last);
  }

  // Search --------------------------------------------------------------------

  /// An `api/search` (`searchProfiles`) page: channel profiles, live and
  /// offline, one per name. Profiles have no stream title, cover or
  /// audience: the title is the channel name and the introduction the
  /// profile's `bio` (11-5); the followers are `follower_count`. A profile
  /// without a valid name, id or state, or with negative followers, is left
  /// out (11-3); a page none of whose profiles is usable is `ApiChanged`.
  /// `count` differs between pages and is not read (REG-PICARTO-002): the
  /// results end with an empty page.
  static List<LiveRoom> searchRooms(String body, {required int pageSize, int status = 200}) {
    final root = _root(body, status: status, what: 'search');
    final result = _object(root['searchProfiles']);
    final rows = result?['data'];
    if (rows is! List || rows.length > pageSize) {
      throw ApiChanged(_site, 'search: no searchProfiles.data of at most $pageSize (${_snippet(body)})');
    }
    final rooms = <String, LiveRoom>{};
    var usable = 0;
    for (final raw in rows) {
      final profile = _object(raw);
      final followers = jsonInt(profile?['follower_count']);
      if (profile == null || !_isChannel(profile) || (followers != null && followers < 0)) continue;
      usable++;
      final name = jsonString(profile['name'])!;
      final bio = decodeHtmlEntities(jsonString(profile['bio']) ?? '').trim();
      rooms.putIfAbsent(
        name.toLowerCase(),
        () => LiveRoom(
          roomId: name,
          platform: _site,
          userId: '${jsonInt(profile['id'])}',
          title: name,
          nick: name,
          link: roomPageUrl(name),
          avatar: normalizeImageUrl(profile['avatar']),
          watching: '',
          followers: followers == null ? '' : '$followers',
          audienceMetricType: AudienceMetricType.unknown,
          liveStatus: profile['online'] == true ? LiveStatus.live : LiveStatus.offline,
          introduction: bio.isEmpty ? null : bio,
        ),
      );
    }
    if (rows.isNotEmpty && usable == 0) throw ApiChanged(_site, 'search: no usable profile (${_snippet(body)})');
    return List.unmodifiable(rooms.values);
  }

  // Rooms ---------------------------------------------------------------------

  /// `api/channel/detail/<name>` for the channel asked for as
  /// [requestedId]. The platform matches names ignoring case and answers in
  /// its own spelling (`thebaker` → `TheBaker`), which is the room id, as in
  /// 3.x: 3.x's follows were stored under it, so a room opened from a
  /// lower-case link is the followed one. [requestedId] is kept in
  /// [PicartoChannel.requestedId].
  ///
  /// - `channel: null`: `NotFound`.
  /// - A channel of another name, or without id, state or `private` flag:
  ///   `ApiChanged`.
  /// - A private channel (the viewer needs the streamer's private key) is
  ///   shown as usual, live or offline, with the restriction `private` and
  ///   no stream (11-9; 3.x failed with "access denied"); any other channel
  ///   has the restriction `none`. Adult channels are not restricted: they
  ///   play without an account.
  /// - With [stream], a live channel that is not private carries the master
  ///   playlist on the load balancer's edge, of the one stream in
  ///   `getMultiStreams` that is this channel's (a multistream group lists
  ///   the others too, REG-PICARTO-001). Without an edge or exactly one own
  ///   stream the answer is `ApiChanged`, as in 3.x. Without [stream] (the
  ///   follow refresh, 11-2) these fields are not checked and there is no
  ///   master.
  ///
  /// The room is 3.x's: viewers concurrent, `total_views` cumulative; plus
  /// the description panels as the introduction and `followers_count`,
  /// which 3.x did not read. The cover is the own stream's thumbnail, of
  /// the broadcast on air or, offline, of the last one (11-6; 3.x showed no
  /// cover offline), else the channel's `image_thumbnail`. The answer has
  /// no start time (see [liveSince]).
  static PicartoChannel roomDetail(String body, {required String requestedId, int status = 200, bool stream = true}) {
    final root = _root(body, status: status, what: 'channel/detail');
    final id = requestedId.trim();
    if (root.containsKey('channel') && root['channel'] == null) {
      throw NotFound(_site, 'channel/detail: no channel "$id"');
    }
    final channel = _object(root['channel']);
    if (channel == null) throw ApiChanged(_site, 'channel/detail: no channel object (${_snippet(body)})');
    if (!_isChannel(channel) ||
        (jsonString(channel['name']) ?? '').toLowerCase() != id.toLowerCase() ||
        channel['private'] is! bool) {
      throw ApiChanged(
        _site,
        'channel "$id" without a valid name, id, state or private flag: ${_snippet(jsonEncode(channel))}',
      );
    }
    final card = _card(channel);
    final channelId = int.parse(card.userId!);
    final streams = _object(root['getMultiStreams'])?['streams'];
    final own = [
      if (streams is List && streams.length <= 100)
        for (final raw in streams)
          if (_object(raw) case final entry? when jsonInt(entry['channelId']) == channelId) entry,
    ];
    Uri? master;
    if (stream && card.isLiveNow && card.restriction != LiveRestriction.private) {
      final edge = jsonString(_object(root['getLoadBalancerUrl'])?['origin']) ?? '';
      if (edge.length > 63 || !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(edge)) {
        throw ApiChanged(_site, 'channel/detail: no load balancer edge (${_snippet(body)})');
      }
      if (streams is! List || streams.length > 100) throw const ApiChanged(_site, 'channel/detail: no stream list');
      if (own.length != 1) throw ApiChanged(_site, 'channel/detail: ${own.length} streams of channel $channelId');
      final streamName = jsonString(own.single['stream_name']) ?? '';
      if (!RegExp(r'^[a-zA-Z0-9_+-]{1,150}$').hasMatch(streamName)) {
        throw ApiChanged(_site, 'channel/detail: bad stream name "$streamName"');
      }
      master = Uri.parse('https://$edge.picarto.tv/stream/hls/$streamName/index.m3u8');
    }
    // 3.x showed the stream's thumbnail when live; the channel's is the
    // fallback.
    final thumbnail = own.length == 1 ? normalizeImageUrl(own.single['thumbnail_image']) : '';
    final followers = jsonCount(channel['followers_count']);
    return PicartoChannel(
      room: card.copyWith(
        cover: thumbnail.isEmpty ? null : thumbnail,
        followers: followers == null ? null : '$followers',
        introduction: _introduction(channel['descriptions']),
      ),
      name: card.roomId,
      channelId: channelId,
      requestedId: id,
      master: master,
    );
  }

  /// When the broadcast on air started: `last_live` of the public API's
  /// `api/v1/channel/name/<name>`, in UTC (`2026-09-28 16:12:10`; checked
  /// on 2026-09-28 against the stream time in the HLS segment names of four
  /// broadcasts, within 10 seconds). Null when the answer is of another
  /// channel, the channel is offline (`last_live` is then the previous
  /// broadcast's start) or the time is missing or malformed. Statuses as
  /// the internal API (404 is `NotFound`).
  static DateTime? liveSince(String body, {required String name, int status = 200}) {
    final root = _root(body, status: status, what: 'channel/name');
    if ((jsonString(root['name']) ?? '').toLowerCase() != name.trim().toLowerCase() || root['online'] != true) {
      return null;
    }
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$')
        .firstMatch((jsonString(root['last_live']) ?? '').trim());
    if (match == null) return null;
    final parts = [for (var group = 1; group <= 6; group++) int.parse(match.group(group)!)];
    final time = DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
    final exact = [time.year, time.month, time.day, time.hour, time.minute, time.second];
    for (var index = 0; index < parts.length; index++) {
      if (exact[index] != parts[index]) return null;
    }
    return time.year > 1970 ? time : null;
  }

  /// The danmaku arguments of [channel].
  static PicartoDanmakuArgs danmakuArgs(PicartoChannel channel) =>
      PicartoDanmakuArgs(channelName: channel.name, channelId: channel.channelId);

  // Streams -------------------------------------------------------------------

  /// The master playlist [body] fetched from [master] (3.x's
  /// `parsePicartoHls`): one quality per video profile (resolution, frame
  /// rate, codecs and groups; the bandwidth and host are not part of it, so
  /// a renewed playlist keeps its ids), labelled `720p 60fps` (or
  /// `HLS 3.5 Mbps` without a resolution); `data` holds the variant URLs of
  /// the profile. The tallest first, then the highest bandwidth (11-4; 3.x
  /// ordered by bandwidth alone); `sort` says the same ([heightWeight]
  /// times the height plus the bandwidth).
  ///
  /// A master with separate audio renditions, or a media playlist, is one
  /// quality [autoQualityName] (11-4; 3.x: `HLS Auto`) whose URL is
  /// [master] itself (a bare variant would play without sound). Quality
  /// ids are 3.x's. HTTP 404 is `StreamUnavailable` (the broadcast
  /// ended since the detail); anything that is not a playlist, a variant
  /// without a bandwidth or with a malformed resolution or frame rate, or
  /// a URL that is not http(s) is `ApiChanged`.
  static List<LivePlayQuality> qualities(String body, {required Uri master, int status = 200}) {
    if (status == 404) throw const StreamUnavailable(_site, 'master playlist: HTTP 404');
    _checkStatus(status, 'master playlist');
    _checkSize(body, 'master playlist');
    if (body.trimLeft().split('\n').first.trim() != '#EXTM3U') {
      throw ApiChanged(_site, 'master playlist: not a playlist (${_snippet(body)})');
    }
    final grouped = <String, ({String label, int height, int rank, Set<String> urls})>{};
    Map<String, String>? pending;
    var externalAudio = false;
    var media = false;
    var mediaUri = false;
    for (final raw in body.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('#EXT-X-MEDIA:') && line.contains('TYPE=AUDIO') && line.contains('URI=')) {
        externalAudio = true;
      }
      if (line.startsWith('#EXTINF:')) media = true;
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        if (pending != null) throw const ApiChanged(_site, 'master playlist: a variant without a URL');
        pending = {
          for (final match in RegExp('([A-Z0-9-]+)=("[^"]*"|[^,]*)').allMatches(line.substring(18)))
            match.group(1)!: match.group(2)!.replaceAll('"', ''),
        };
        continue;
      }
      if (line.isEmpty || line.startsWith('#')) continue;
      if (pending == null) {
        if (media) {
          _webUri(master, line);
          mediaUri = true;
        }
        continue;
      }
      final attributes = pending;
      pending = null;
      final uri = _webUri(master, line);
      final bandwidth = int.tryParse(attributes['BANDWIDTH'] ?? '');
      final resolution = attributes['RESOLUTION'] ?? '';
      final size = RegExp(r'^([1-9][0-9]*)x([1-9][0-9]*)$').firstMatch(resolution);
      final fps = double.tryParse(attributes['FRAME-RATE'] ?? '0');
      if (bandwidth == null ||
          bandwidth <= 0 ||
          (resolution.isNotEmpty && size == null) ||
          fps == null ||
          !fps.isFinite ||
          fps < 0) {
        throw ApiChanged(_site, 'master playlist: bad variant ${jsonEncode(attributes)}');
      }
      final codecs = attributes['CODECS'] ?? '';
      final id = jsonEncode([
        resolution,
        fps,
        codecs,
        attributes['VIDEO'],
        attributes['AUDIO'],
        if (size == null) bandwidth,
      ]);
      final label = size == null
          ? 'HLS ${(bandwidth / 1000000).toStringAsFixed(1)} Mbps'
          : '${size.group(2)}p${fps > 0 ? ' ${fps == fps.roundToDouble() ? fps.toInt() : fps}fps' : ''}';
      final previous = grouped[id];
      grouped[id] = (
        label: previous?.label ?? label,
        height: size == null ? 0 : int.parse(size.group(2)!),
        rank: previous != null && previous.rank >= bandwidth ? previous.rank : bandwidth,
        urls: {...?previous?.urls, uri.toString()},
      );
    }
    if (pending != null || (grouped.isEmpty && !mediaUri)) {
      throw ApiChanged(_site, 'master playlist: no variant or media (${_snippet(body)})');
    }
    if (externalAudio || grouped.isEmpty) {
      return [
        LivePlayQuality(
          id: autoQualityId,
          quality: autoQualityName,
          data: List<String>.unmodifiable([master.toString()]),
        ),
      ];
    }
    final ordered = grouped.entries.indexed.toList()
      ..sort((a, b) {
        final byHeight = b.$2.value.height.compareTo(a.$2.value.height);
        if (byHeight != 0) return byHeight;
        final byRank = b.$2.value.rank.compareTo(a.$2.value.rank);
        return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
      });
    return [
      for (final (_, MapEntry(:key, :value)) in ordered)
        LivePlayQuality(
          id: key,
          quality: value.label,
          sort: value.height * heightWeight + value.rank,
          data: List<String>.unmodifiable(value.urls),
        ),
    ];
  }

  /// The id of the one quality of a master played as it is (3.x's; the
  /// label changed, the id did not).
  static const String autoQualityId = 'master';

  /// The label of [autoQualityId] (11-4; 3.x: `HLS Auto`).
  static const String autoQualityName = '自动';

  /// How much one line of height weighs in a quality's `sort` against the
  /// bandwidth (bits per second, far below it).
  static const int heightWeight = 1000000000;

  /// The video codec of [quality] (`avc`, `hevc`) from the `CODECS` in its
  /// id, or null (`HLS Auto`, or none declared).
  static String? codecOf(LivePlayQuality quality) {
    final id = quality.id;
    if (id is! String || !id.startsWith('[')) return null;
    final Object? fields;
    try {
      fields = jsonDecode(id);
    } on FormatException {
      return null;
    }
    if (fields is! List || fields.length < 3) return null;
    for (final codec in '${fields[2]}'.toLowerCase().split(',')) {
      final name = codec.trim();
      if (name.startsWith('avc1') || name.startsWith('avc3')) return 'avc';
      if (name.startsWith('hvc1') || name.startsWith('hev1')) return 'hevc';
    }
    return null;
  }

  /// The lines of [quality] on [master]'s edge: one per variant URL, with
  /// [headers], HLS, the codec and the edge host as the line id. The URLs
  /// carry no signature, so there is no lease; the edge can change between
  /// detail requests, which recovery asks again (REG-PICARTO-003). The
  /// requested quality is the applied one, as in 3.x.
  static LivePlayUrlResolution resolution(LivePlayQuality quality, {required Uri master}) {
    final data = quality.data;
    final urls = [
      if (data is List)
        for (final url in data) ?jsonString(url),
    ];
    if (urls.isEmpty) throw StreamUnavailable(_site, 'quality ${quality.quality} has no playlist');
    final codec = codecOf(quality);
    return LivePlayUrlResolution.lines([
      for (final url in urls)
        LivePlayLine(url, headers: headers, format: StreamFormat.hls, codec: codec, lineId: master.host),
    ], appliedQualityData: quality.selectionId);
  }

  // Links ---------------------------------------------------------------------

  /// First path segments of site pages that are no channel, besides
  /// [reservedNames] (the archived v4's list). Only links use them: a
  /// channel of such a name in an answer is still a channel.
  static const Set<String> pagePaths = {'videos', 'communities', 'subscriptions', 'following', 'shop', 'commissions'};

  /// The channel of a channel page (3.x's `channelFromUri`): http(s) on
  /// `picarto.tv` or `www.picarto.tv`, no user info, the default port, and
  /// exactly one path segment (a trailing `/` allowed) that is a channel
  /// name. Search, explore and other pages, `//name`, `name/videos` and
  /// undecodable paths are not.
  static String? channelFromUrl(Uri uri) {
    if (!(uri.isScheme('http') || uri.isScheme('https')) ||
        !const {'picarto.tv', 'www.picarto.tv'}.contains(uri.host.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.isScheme('https') ? 443 : 80))) {
      return null;
    }
    final List<String> parts;
    try {
      parts = uri.pathSegments.toList();
    } on FormatException {
      return null;
    }
    if (parts.isNotEmpty && parts.last.isEmpty) parts.removeLast();
    if (parts.length != 1) return null;
    final name = parts.single.trim();
    return isChannelName(name) && !pagePaths.contains(name.toLowerCase()) ? name : null;
  }

  // Helpers -------------------------------------------------------------------

  /// Whether [channel] (an explore row, a detail's channel, a search
  /// profile) is one: a valid channel name, a positive id and a boolean
  /// state (3.x's `parseChannel` checks).
  static bool _isChannel(Map<String, dynamic> channel) {
    final id = jsonInt(channel['id']);
    return isChannelName(jsonString(channel['name']) ?? '') && id != null && id > 0 && channel['online'] is bool;
  }

  /// The room of a channel that [_isChannel] accepted (3.x's
  /// `parseChannel`), under the platform's spelling of its name. The
  /// audience is `viewers` (concurrent) and `total_views` (cumulative,
  /// details only). A `private` flag gives the restriction (`private` or
  /// `none`); rows without it leave it unknown. [placeholderTitle] is left
  /// empty.
  static LiveRoom _card(Map<String, dynamic> channel) {
    final name = jsonString(channel['name'])!;
    final viewers = jsonCount(channel['viewers']);
    final total = jsonCount(channel['total_views']);
    final categories = channel['categories'];
    final title = jsonString(channel['title']) ?? '';
    final private = channel['private'];
    return LiveRoom(
      roomId: name,
      platform: _site,
      userId: '${jsonInt(channel['id'])}',
      nick: name,
      title: title.trim() == placeholderTitle ? '' : title,
      link: roomPageUrl(name),
      avatar: normalizeImageUrl(channel['avatar']),
      cover: normalizeImageUrl(channel['image_thumbnail']),
      area: categories is List
          ? [for (final category in categories) ?jsonString(_object(category)?['name'])].join(' / ')
          : '',
      watching: viewers == null ? '' : '$viewers',
      onlineViewers: viewers == null ? '' : '$viewers',
      totalViewers: total == null ? '' : '$total',
      audienceMetricType: AudienceMetricType.onlineViewers,
      liveStatus: channel['online'] == true ? LiveStatus.live : LiveStatus.offline,
      restriction: private is bool ? (private ? LiveRestriction.private : LiveRestriction.none) : null,
    );
  }

  /// The description panels' texts, entities decoded, a blank line apart;
  /// null without any.
  static String? _introduction(Object? descriptions) {
    if (descriptions is! List) return null;
    final text = [
      for (final panel in descriptions)
        if (jsonString(_object(panel)?['body']) case final body?) decodeHtmlEntities(body),
    ].join('\n\n');
    return text.isEmpty ? null : text;
  }

  /// [line] of a playlist resolved against [master]; anything but an http(s)
  /// URL without user info is `ApiChanged`.
  static Uri _webUri(Uri master, String line) {
    final Uri uri;
    try {
      uri = master.resolve(line);
    } on FormatException {
      throw ApiChanged(_site, 'master playlist: bad URL "$line"');
    }
    if (!(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw ApiChanged(_site, 'master playlist: not a web URL "$line"');
    }
    return uri;
  }
}

Map<String, dynamic>? _object(Object? value) => value is Map<String, dynamic> ? value : null;

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}

/// 3.x's status rules: only 200 is an answer; 401 and 403 → `RiskControl`
/// (3.x's "access"); 404 → `NotFound`; 429 → `RateLimited`; 5xx and any
/// other status → `NetworkFailure` (3.x's "service" and "transport", both
/// retried by its recorder).
void _checkStatus(int status, String what) {
  if (status == 200) return;
  throw switch (status) {
    401 || 403 => RiskControl(_site, detail: '$what: HTTP $status'),
    404 => NotFound(_site, '$what: HTTP 404'),
    429 => RateLimited(_site, detail: '$what: HTTP 429'),
    _ => NetworkFailure(_site, '$what: HTTP $status'),
  };
}

/// An answer over [PicartoApi.responseLimit] UTF-8 bytes is `ApiChanged`
/// (3.x's cap). A UTF-16 unit takes at most three bytes, so only long
/// texts are encoded to count.
void _checkSize(String body, String what) {
  const limit = PicartoApi.responseLimit;
  if (body.length > limit || (body.length > limit ~/ 3 && utf8.encode(body).length > limit)) {
    throw ApiChanged(_site, '$what: answer over $limit bytes');
  }
}

/// The JSON object of an answer; see [_checkStatus] and [_checkSize].
Map<String, dynamic> _root(String body, {required int status, required String what}) {
  _checkStatus(status, what);
  _checkSize(body, what);
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    decoded = null;
  }
  if (decoded is! Map<String, dynamic>) throw ApiChanged(_site, '$what: not a JSON object (${_snippet(body)})');
  return decoded;
}
