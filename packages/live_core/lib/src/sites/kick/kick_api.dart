import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'kick';
const _web = 'https://kick.com';

/// What a danmaku connection needs to read one channel's public chat.
///
/// The chatroom id is not the channel id (`xqcisoffline`: channel 101691,
/// chatroom 101689), so it comes from the channel answer of room entry and
/// is never guessed; the channel id names the channel's own events (the end
/// of the broadcast).
@immutable
final class KickDanmakuArgs {
  /// Creates the arguments.
  const new({required this.chatroomId, required this.channelId, required this.slug});

  /// `chatroom.id`: the Pusher channel `chatrooms.<id>.v2` carries the chat.
  final int chatroomId;

  /// The channel's numeric id (`channel.<id>` carries its broadcast events).
  final int channelId;

  /// The channel slug, the room id.
  final String slug;

  @override
  bool operator ==(Object other) =>
      other is KickDanmakuArgs && other.chatroomId == chatroomId && other.channelId == channelId && other.slug == slug;

  @override
  int get hashCode => Object.hash(chatroomId, channelId, slug);

  @override
  String toString() => 'KickDanmakuArgs($slug, chatroom $chatroomId, channel $channelId)';
}

/// The stream of a live room, read on room entry: the signed master
/// playlist and its qualities.
@immutable
final class KickRoomData {
  /// Creates the data.
  new({
    required this.slug,
    required this.master,
    required List<LivePlayQuality> qualities,
    Map<String, String> codecs = const {},
    this.tokenExpiresAt,
  }) : qualities = List.unmodifiable(qualities),
       codecs = Map.unmodifiable(codecs);

  /// The channel slug, the room id.
  final String slug;

  /// The IVS master playlist with its playback token.
  final Uri master;

  /// Qualities of [master], best first; `data` holds each variant playlist.
  final List<LivePlayQuality> qualities;

  /// The codec family (`avc`, `hevc`, `av1`) of each quality id, from the
  /// master's `CODECS`.
  final Map<String, String> codecs;

  /// When the master's playback token expires (its JWT `exp`), if it says.
  /// The variant playlists it lists outlive it (as Twitch's do); recovery
  /// asks for a new master anyway.
  final DateTime? tokenExpiresAt;
}

/// A channel answer (`api/v2/channels/<slug>`).
@immutable
final class KickChannel {
  /// Creates the answer.
  const new({required this.room, required this.channelId, this.chatroomId, this.master});

  /// The room, without stream data or danmaku arguments.
  final LiveRoom room;

  /// The channel's numeric id.
  final int channelId;

  /// The chatroom's id, when the answer has one.
  final int? chatroomId;

  /// The signed master playlist when the channel is live, else null.
  final Uri? master;
}

/// One of Kick's top-level categories (`api/v1/categories`).
typedef KickMainCategory = ({String slug, String name});

/// Pure parsing of Kick's public web API, after pure_live_TV's `KickApi`
/// (e1cca224): each function takes a response text and status and returns
/// the app's models or throws a `SiteError`.
///
/// A bad row is left out; only an answer without any usable row fails
/// (`ApiChanged`), so a change of format is not shown as an empty list.
abstract final class KickApi {
  /// Desktop Chrome 140, as pure_live_TV sends.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/140.0.0.0 Safari/537.36';

  /// Web origin.
  static const String origin = _web;

  /// Host of the API. Cloudflare refuses dart:io's TLS handshake there
  /// (403 "Request blocked by security policy.", 2026-10-01, also on
  /// `web.kick.com`); Android's system TLS stack and curl pass.
  static const String apiHost = 'kick.com';

  /// Headers of every API request, names in lower case.
  static const Map<String, String> headers = {
    'user-agent': userAgent,
    'accept': 'application/json, text/plain, */*',
    'accept-language': 'en-US,en;q=0.9',
    'origin': _web,
    'referer': '$_web/',
  };

  /// Headers of the media requests of channel [slug] (pure_live_TV's
  /// `mediaHeaders`): the IVS playback token names kick.com as its origin.
  static Map<String, String> mediaHeaders(String slug) => {
    'user-agent': userAgent,
    'origin': _web,
    'referer': '${roomPageUrl(slug)}/',
  };

  /// Largest live list page asked for; 30 is pure_live_TV's page.
  static const int pageSize = 30;

  /// Subcategories asked for per top-level category: the most the API gives
  /// in one page (`limit` above 32 is answered with 32).
  static const int subcategoryLimit = 32;

  /// Longest search keyword sent (pure_live_TV).
  static const int maxKeywordLength = 50;

  /// Largest answer read (pure_live_TV's budget).
  static const int responseLimit = 4 * 1024 * 1024;

  /// The top-level categories in Chinese; others keep Kick's name.
  static const Map<String, String> categoryNames = {
    'games': '游戏',
    'irl': '生活',
    'music': '音乐',
    'gambling': '博彩',
    'creative': '创作',
    'alternative': '其他',
  };

  /// The room notice of a broadcast Kick marks as mature.
  static const String matureNotice = '该直播已被 Kick 标记为成人内容（18+）。';

  /// Kick's own pages, never channels.
  static const Set<String> reservedSlugs = {
    'about', 'auth', 'browse', 'categories', 'category', 'clips', 'community-guidelines', 'dashboard', //
    'dmca-policy', 'following', 'legal', 'popout', 'privacy-policy', 'search', 'settings', 'subscriptions',
    'terms-of-service', 'video', 'videos',
  };

  static final RegExp _slug = RegExp(r'^[a-z0-9_-]{1,100}$');

  /// [raw] as a channel slug (lower case), or null when it cannot be one.
  static String? normalizeSlug(String raw) {
    final slug = raw.trim().toLowerCase();
    return _slug.hasMatch(slug) && !reservedSlugs.contains(slug) ? slug : null;
  }

  /// The channel page of [slug].
  static String roomPageUrl(String slug) => '$_web/${slug.trim().toLowerCase()}';

  // Catalog -------------------------------------------------------------------

  /// The top-level categories (`api/v1/categories`), in Kick's order.
  static List<KickMainCategory> mainCategories(String body, {int status = 200}) {
    final root = _decode(body, status: status, what: 'categories');
    if (root is! List || root.length > 64) throw ApiChanged(_site, 'categories: not a list (${_snippet(body)})');
    final result = <String, KickMainCategory>{};
    for (final raw in root) {
      final row = _object(raw);
      final slug = jsonString(row?['slug'])?.toLowerCase();
      final name = jsonString(row?['name']);
      if (slug == null || name == null || !_slug.hasMatch(slug)) continue;
      result.putIfAbsent(slug, () => (slug: slug, name: categoryNames[slug] ?? name));
    }
    if (result.isEmpty) throw ApiChanged(_site, 'categories: no usable category (${_snippet(body)})');
    return List.unmodifiable(result.values);
  }

  /// The subcategories of [parent] (`api/v1/subcategories?category=…`), by
  /// viewers as Kick orders them: areas of type `subcategory` named by slug.
  static List<LiveArea> subcategories(String body, {required KickMainCategory parent, int status = 200}) {
    final rows = _object(_decode(body, status: status, what: 'subcategories'))?['data'];
    if (rows is! List || rows.length > 100) {
      throw ApiChanged(_site, 'subcategories: no data list (${_snippet(body)})');
    }
    final areas = <String, LiveArea>{};
    for (final raw in rows) {
      final row = _object(raw);
      final slug = jsonString(row?['slug']);
      final name = jsonString(row?['name']);
      final owner = jsonString(_object(row?['category'])?['slug'])?.toLowerCase();
      if (slug == null || name == null || slug.length > 100 || (owner != null && owner != parent.slug)) continue;
      areas.putIfAbsent(
        slug.toLowerCase(),
        () => LiveArea(
          platform: _site,
          areaType: 'subcategory',
          typeName: parent.name,
          areaId: slug,
          areaName: name,
          areaPic: normalizeImageUrl(_object(row?['banner'])?['url']),
        ),
      );
    }
    if (rows.isNotEmpty && areas.isEmpty) throw ApiChanged(_site, 'subcategories: no usable row (${_snippet(body)})');
    return List.unmodifiable(areas.values);
  }

  // Lists ---------------------------------------------------------------------

  /// A page of live broadcasts (`stream/livestreams/en`, by viewers). With
  /// [subcategory], rows of other subcategories are left out: Kick ignores
  /// a subcategory it does not know and answers the whole directory, so a
  /// page without any row of it is `NotFound`.
  static LiveDirectoryPage directoryPage(
    String body, {
    required int page,
    required int pageSize,
    String? subcategory,
    int status = 200,
  }) {
    final root = _object(_decode(body, status: status, what: 'livestreams'));
    final rows = root?['data'];
    if (root == null || rows is! List || rows.length > pageSize * 2 || jsonInt(root['current_page']) != page) {
      throw ApiChanged(_site, 'livestreams: not page $page (${_snippet(body)})');
    }
    final wanted = subcategory?.toLowerCase();
    final rooms = <String, LiveRoom>{};
    var usable = 0;
    var matching = 0;
    for (final raw in rows) {
      final row = _object(raw);
      final room = row == null ? null : _listCard(row);
      if (room == null) continue;
      usable++;
      if (wanted != null && !_subcategorySlugs(row!['categories']).contains(wanted)) continue;
      matching++;
      rooms.putIfAbsent(room.roomId, () => room);
    }
    if (rows.isNotEmpty && usable == 0) throw ApiChanged(_site, 'livestreams: no usable row (${_snippet(body)})');
    if (wanted != null && usable > 0 && matching == 0) throw NotFound(_site, 'no subcategory "$subcategory"');
    final next = root['next_page_url'];
    return LiveDirectoryPage(rooms: rooms.values, page: page, hasMore: next is String && rows.isNotEmpty);
  }

  /// Channels matching a keyword (`api/search`): the channels first, by
  /// followers as Kick orders them (live or not), then the live broadcasts
  /// whose tags match and whose channel is not listed yet.
  static List<LiveRoom> searchRooms(String body, {int status = 200}) {
    final root = _object(_decode(body, status: status, what: 'search'));
    final channels = root?['channels'];
    final tagged = _object(root?['livestreams'])?['tags'];
    if (root == null || channels is! List || channels.length > 100 || (tagged != null && tagged is! List)) {
      throw ApiChanged(_site, 'search: no channel list (${_snippet(body)})');
    }
    final rooms = <String, LiveRoom>{};
    var usable = 0;
    for (final raw in channels) {
      final row = _object(raw);
      final room = row == null ? null : _searchCard(row);
      if (room == null) continue;
      usable++;
      rooms.putIfAbsent(room.roomId, () => room);
    }
    if (channels.isNotEmpty && usable == 0) throw ApiChanged(_site, 'search: no usable channel (${_snippet(body)})');
    if (tagged is List) {
      for (final raw in tagged.take(100)) {
        final row = _object(raw);
        final room = row == null ? null : _listCard(row);
        if (room != null) rooms.putIfAbsent(room.roomId, () => room);
      }
    }
    return List.unmodifiable(rooms.values);
  }

  // Rooms ---------------------------------------------------------------------

  /// A channel answer for [requestedSlug]: the room and, when live, the
  /// signed master playlist. A slug Kick does not know is `NotFound` (HTTP
  /// 404 "Channel not found."); an answer for another channel is
  /// `ApiChanged`.
  static KickChannel channel(String body, {required String requestedSlug, int status = 200}) {
    if (status == 404) throw NotFound(_site, 'no channel "$requestedSlug"');
    final root = _object(_decode(body, status: status, what: 'channel'));
    final slug = normalizeSlug(jsonString(root?['slug']) ?? '');
    final channelId = jsonInt(root?['id']);
    final user = _object(root?['user']);
    if (root == null || slug == null || channelId == null || channelId <= 0 || user == null) {
      throw ApiChanged(_site, 'channel: no slug, id or user (${_snippet(body)})');
    }
    if (slug != requestedSlug.trim().toLowerCase()) {
      throw ApiChanged(_site, 'channel: asked for "$requestedSlug", answered "$slug"');
    }
    final banned = root['is_banned'] == true;
    final stream = _object(root['livestream']);
    final live = !banned && stream != null && stream['is_live'] == true;
    final viewers = live ? jsonCount(stream['viewer_count']) : null;
    final followers = jsonCount(root['followers_count']);
    final chatroom = jsonInt(_object(root['chatroom'])?['id']);
    final master = live ? _master(jsonString(root['playback_url'])) : null;
    final room = LiveRoom(
      roomId: slug,
      platform: _site,
      userId: '$channelId',
      link: roomPageUrl(slug),
      nick: jsonString(user['username']) ?? '',
      title: live ? jsonString(stream['session_title']) ?? '' : '',
      avatar: normalizeImageUrl(user['profile_pic'] ?? user['profilePic']),
      cover: live
          ? normalizeImageUrl(_object(stream['thumbnail'])?['url'] ?? _object(stream['thumbnail'])?['src'])
          : normalizeImageUrl(_object(root['offline_banner_image'])?['src'] ?? _object(root['banner_image'])?['url']),
      area: live ? _subcategoryName(stream['categories']) : null,
      watching: viewers == null ? '' : '$viewers',
      onlineViewers: viewers == null ? '' : '$viewers',
      audienceMetricType: AudienceMetricType.onlineViewers,
      followers: followers == null ? '0' : '$followers',
      liveStatus: banned
          ? LiveStatus.banned
          : live
          ? LiveStatus.live
          : LiveStatus.offline,
      startedAt: live ? _time(stream['start_time']) : null,
      restriction: LiveRestriction.none,
      introduction: jsonString(user['bio']) ?? '',
      notice: live && stream['is_mature'] == true ? matureNotice : '',
      httpHeaders: mediaHeaders(slug),
    );
    return KickChannel(
      room: room,
      channelId: channelId,
      chatroomId: chatroom != null && chatroom > 0 ? chatroom : null,
      master: master,
    );
  }

  /// The danmaku arguments of [channel], or null without a chatroom id
  /// (pure_live_TV: never subscribe to a guessed chatroom).
  static KickDanmakuArgs? danmakuArgs(KickChannel channel) => switch (channel.chatroomId) {
    final int chatroom => KickDanmakuArgs(
      chatroomId: chatroom,
      channelId: channel.channelId,
      slug: channel.room.roomId,
    ),
    null => null,
  };

  /// When the playback token of [master] expires: its JWT payload's `exp`,
  /// or null when it has none.
  static DateTime? tokenExpiry(Uri master) {
    final parts = (master.queryParameters['token'] ?? '').split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload is Map ? jsonInt(payload['exp']) : null;
      return exp == null || exp <= 0 || exp > 8640000000
          ? null
          : DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    } on FormatException {
      return null;
    }
  }

  // Streams -------------------------------------------------------------------

  /// The qualities of an IVS master playlist at [master], best first. The
  /// name is the variant's video rendition (`1080p60`, `720p60`, `480p`;
  /// Kick's player shows these), else the height and frame rate; the id is
  /// the name, so a recovered master selects the same one. Each quality
  /// holds its variant playlist. A refused or gone master (403, 404) is
  /// `StreamUnavailable`: the broadcast ended or its token expired.
  static List<LivePlayQuality> qualities(String body, {required Uri master, int status = 200}) =>
      _qualities(_variants(body, master: master, status: status));

  /// Weight of the height in a quality's `sort`, above any bandwidth.
  static const int heightWeight = 1000000000;

  /// The stream of channel [slug] in the master playlist [body] read from
  /// [master]: [qualities], their codecs and the token's expiry.
  static KickRoomData roomData(String body, {required String slug, required Uri master, int status = 200}) {
    final variants = _variants(body, master: master, status: status);
    return KickRoomData(
      slug: slug,
      master: master,
      qualities: _qualities(variants),
      codecs: {for (final variant in variants) variant.name: ?variant.codec},
      tokenExpiresAt: tokenExpiry(master),
    );
  }

  static List<LivePlayQuality> _qualities(List<_Variant> variants) => [
    for (final variant in variants)
      LivePlayQuality(
        id: variant.name,
        quality: variant.name,
        sort: variant.height * heightWeight + variant.rank,
        data: List<String>.unmodifiable([variant.url]),
      ),
  ];

  static List<_Variant> _variants(String body, {required Uri master, required int status}) {
    if (status == 403 || status == 404) throw StreamUnavailable(_site, 'master playlist: HTTP $status');
    _checkStatus(status, body, 'master playlist');
    if (body.length > responseLimit) throw const ApiChanged(_site, 'master playlist: too large');
    final lines = const LineSplitter().convert(body).map((line) => line.trim()).toList();
    if (lines.isEmpty || lines.first != '#EXTM3U') {
      throw ApiChanged(_site, 'master playlist: not a playlist (${_snippet(body)})');
    }
    final names = <String, String>{};
    final variants = <String, _Variant>{};
    Map<String, String>? pending;
    for (final line in lines.skip(1)) {
      if (line.isEmpty) continue;
      if (line.startsWith('#EXT-X-MEDIA:')) {
        final media = _attributes(line.substring(13));
        if (media['TYPE'] == 'VIDEO' && media['GROUP-ID'] != null && media['NAME'] != null) {
          names[media['GROUP-ID']!] = media['NAME']!;
        }
        continue;
      }
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        if (pending != null) throw const ApiChanged(_site, 'master playlist: a variant without a URL');
        pending = _attributes(line.substring(18));
        continue;
      }
      if (line.startsWith('#')) continue;
      final attributes = pending;
      pending = null;
      if (attributes == null) continue;
      final url = master.resolve(line);
      final bandwidth = jsonInt(attributes['BANDWIDTH']);
      final size = RegExp(r'^[1-9]\d{0,4}x([1-9]\d{0,4})$').firstMatch(attributes['RESOLUTION'] ?? '');
      if (url.scheme != 'https' || url.host.isEmpty || bandwidth == null || bandwidth <= 0 || size == null) continue;
      final height = int.parse(size.group(1)!);
      final fps = double.tryParse(attributes['FRAME-RATE'] ?? '') ?? 0;
      final name = names[attributes['VIDEO']] ?? '${height}p${fps >= 50 ? '${fps.round()}' : ''}';
      final previous = variants[name];
      if (previous != null && previous.rank >= bandwidth) continue;
      variants[name] = (name: name, height: height, rank: bandwidth, codec: _codec(attributes['CODECS']), url: '$url');
    }
    if (variants.isEmpty) throw StreamUnavailable(_site, 'master playlist: no variant (${_snippet(body)})');
    return variants.values.toList()
      ..sort((a, b) => b.height != a.height ? b.height.compareTo(a.height) : b.rank.compareTo(a.rank));
  }

  /// The line of [quality] in [data]: its variant playlist with the media
  /// headers, HLS, its codec and the master's host as the line id. No
  /// lease: the variant outlives the master's token (see
  /// [KickRoomData.tokenExpiresAt]).
  static LivePlayUrlResolution resolution(KickRoomData data, LivePlayQuality quality) {
    final urls = [
      if (quality.data case final List<Object?> list)
        for (final url in list) ?jsonString(url),
    ];
    if (urls.isEmpty) throw StreamUnavailable(_site, 'quality ${quality.quality} has no playlist');
    return LivePlayUrlResolution.lines([
      for (final url in urls)
        LivePlayLine(
          url,
          headers: mediaHeaders(data.slug),
          format: StreamFormat.hls,
          codec: data.codecs[quality.id],
          lineId: data.master.host,
        ),
    ], appliedQualityData: quality.selectionId);
  }

  // Links ---------------------------------------------------------------------

  /// The channel of a `kick.com` page (`https://kick.com/xqc`,
  /// `www.kick.com/XQC/`), lower-cased; null for anything else.
  static String? slugFromUrl(Uri uri) {
    if (!(uri.isScheme('http') || uri.isScheme('https')) ||
        !const {'kick.com', 'www.kick.com', 'm.kick.com'}.contains(uri.host.toLowerCase()) ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final List<String> parts;
    try {
      parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    } on FormatException {
      return null;
    }
    return parts.length == 1 ? normalizeSlug(parts.single) : null;
  }

  // Helpers -------------------------------------------------------------------

  /// A list row (`stream/livestreams`, search tags) as a live card, or null
  /// when it has no channel slug.
  static LiveRoom? _listCard(Map<String, Object?> row) {
    final channel = _object(row['channel']);
    final slug = normalizeSlug(jsonString(channel?['slug']) ?? '');
    final channelId = jsonInt(channel?['id']) ?? jsonInt(row['channel_id']);
    if (channel == null || slug == null || channelId == null || channel['is_banned'] == true) return null;
    if (row['is_live'] == false) return null;
    final user = _object(channel['user']);
    final shown = row['show_view_count'] != false;
    final viewers = shown ? jsonCount(row['viewer_count'] ?? row['viewers']) : null;
    final thumbnail = _object(row['thumbnail']);
    return LiveRoom(
      roomId: slug,
      platform: _site,
      userId: '$channelId',
      link: roomPageUrl(slug),
      nick: jsonString(user?['username']) ?? '',
      title: jsonString(row['session_title']) ?? '',
      avatar: normalizeImageUrl(user?['profilepic'] ?? user?['profile_pic'] ?? user?['profilePic']),
      cover: normalizeImageUrl(thumbnail?['src'] ?? thumbnail?['url']),
      area: _subcategoryName(row['categories']),
      watching: viewers == null ? '' : '$viewers',
      onlineViewers: viewers == null ? '' : '$viewers',
      audienceMetricType: AudienceMetricType.onlineViewers,
      liveStatus: LiveStatus.live,
      startedAt: _time(row['start_time']),
      restriction: LiveRestriction.none,
      notice: row['is_mature'] == true ? matureNotice : '',
      httpHeaders: mediaHeaders(slug),
    );
  }

  /// A search channel (`api/search` `channels`): live or offline, without
  /// a title, cover or viewers.
  static LiveRoom? _searchCard(Map<String, Object?> row) {
    final slug = normalizeSlug(jsonString(row['slug']) ?? '');
    final channelId = jsonInt(row['id']);
    if (slug == null || channelId == null) return null;
    final user = _object(row['user']);
    final followers = jsonCount(row['followersCount'] ?? row['followers_count']);
    final banned = row['is_banned'] == true;
    final live = row['isLive'] ?? row['is_live'];
    return LiveRoom(
      roomId: slug,
      platform: _site,
      userId: '$channelId',
      link: roomPageUrl(slug),
      nick: jsonString(user?['username']) ?? '',
      avatar: normalizeImageUrl(user?['profilePic'] ?? user?['profile_pic']),
      watching: '',
      audienceMetricType: AudienceMetricType.onlineViewers,
      followers: followers == null ? '0' : '$followers',
      liveStatus: banned
          ? LiveStatus.banned
          : live == true
          ? LiveStatus.live
          : LiveStatus.offline,
      introduction: jsonString(user?['bio']) ?? '',
    );
  }

  static Set<String> _subcategorySlugs(Object? categories) => {
    if (categories is List)
      for (final category in categories) ?jsonString(_object(category)?['slug'])?.toLowerCase(),
  };

  static String _subcategoryName(Object? categories) =>
      categories is List && categories.isNotEmpty ? jsonString(_object(categories.first)?['name']) ?? '' : '';

  /// The master playlist in a channel's `playback_url`: https on IVS
  /// (`*.live-video.net`); an offline channel answers only `?token=…`.
  static Uri? _master(String? raw) {
    final uri = raw == null ? null : Uri.tryParse(raw);
    final host = uri?.host.toLowerCase() ?? '';
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty || !host.endsWith('.live-video.net')) {
      return null;
    }
    return uri;
  }

  /// `2026-09-30 19:24:14` (UTC, as Kick's web API writes it) or ISO 8601.
  static DateTime? _time(Object? value) {
    final text = jsonString(value);
    if (text == null) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]00:?00)?$')
        .firstMatch(text);
    if (match == null) return null;
    final parts = [for (var group = 1; group <= 6; group++) int.parse(match.group(group)!)];
    final time = DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
    return time.year == parts[0] && time.month == parts[1] && time.day == parts[2] && time.year > 2000 ? time : null;
  }

  static String? _codec(String? codecs) {
    for (final codec in (codecs ?? '').toLowerCase().split(',')) {
      final name = codec.trim();
      if (name.startsWith('avc1') || name.startsWith('avc3')) return 'avc';
      if (name.startsWith('hvc1') || name.startsWith('hev1')) return 'hevc';
      if (name.startsWith('av01')) return 'av1';
    }
    return null;
  }

  static Map<String, String> _attributes(String text) => {
    for (final match in RegExp('([A-Z0-9-]+)=("[^"]*"|[^,]*)').allMatches(text))
      match.group(1)!: match.group(2)!.replaceAll('"', ''),
  };

  /// The JSON of an answer; a refused, missing or failing one throws.
  static Object? _decode(String body, {required int status, required String what}) {
    _checkStatus(status, body, what);
    if (body.length > responseLimit) throw ApiChanged(_site, '$what: answer too large');
    try {
      return jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON (${_snippet(body)})');
    }
  }

  /// Kick's statuses: 403 is Cloudflare's refusal (`RiskControl`; dart:io
  /// always gets it), 404 `NotFound`, 429 `RateLimited`, 5xx a network
  /// failure; anything else but 200 `ApiChanged`.
  static void _checkStatus(int status, String body, String what) {
    if (status == 200) return;
    if (status == 401 || status == 403) {
      throw RiskControl(
        _site,
        detail: body.contains('security policy')
            ? "$what: Cloudflare refused this client (Kick needs Android's system TLS)"
            : '$what: HTTP $status',
      );
    }
    if (status == 404) throw NotFound(_site, '$what: HTTP 404');
    if (status == 429) throw RateLimited(_site, detail: '$what: HTTP 429');
    if (status >= 500) throw NetworkFailure(_site, '$what: HTTP $status');
    throw ApiChanged(_site, '$what: HTTP $status (${_snippet(body)})');
  }

  static Map<String, Object?>? _object(Object? value) =>
      value is Map ? value.map((key, value) => MapEntry('$key', value)) : null;

  static String _snippet(String text) => text.length > 120 ? '${text.substring(0, 120)}…' : text;
}

/// One variant of a master playlist.
typedef _Variant = ({String name, int height, int rank, String? codec, String url});
