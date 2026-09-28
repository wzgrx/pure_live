import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/input_recipe.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'fc2live';

/// A channel's state as 3.x read it.
enum Fc2LiveState {
  /// `is_publish` 1 and open to anonymous viewers.
  live,

  /// Not broadcasting (`is_publish` other than 1).
  offline,

  /// Broadcasting, but paid, login-only, ticketed or limited: 3.x kept the
  /// room visible with an unknown state and a notice, never "offline".
  restricted,
}

/// One channel of the directory or of a member answer (3.x's `Fc2Room`,
/// without the start time 3.x parsed but never showed).
@immutable
final class Fc2LiveChannel {
  /// Creates the channel.
  const new({
    required this.channelId,
    required this.userName,
    required this.title,
    required this.cover,
    required this.categoryId,
    required this.categoryName,
    required this.state,
    this.description = '',
    this.currentViewers,
    this.totalViewers,
    this.isAdult = false,
  });

  /// The channel number, the room id.
  final String channelId;

  /// The owner's name (`name`; `profile_data.name`, else `tname`), else the
  /// channel number.
  final String userName;

  /// `title`, else the owner's name, else the channel number.
  final String title;

  /// `channel_data.info` (member answers only), whitespace collapsed.
  final String description;

  /// `image` when it is an https image on `fc2.com` or a subdomain, else
  /// empty.
  final String cover;

  /// `category` (0–99).
  final int categoryId;

  /// The directory's English name of [categoryId]; a member answer's own
  /// `category_name` (Japanese) when it has one.
  final String categoryName;

  /// `count`: viewers now.
  final int? currentViewers;

  /// `total`: viewers of this broadcast so far.
  final int? totalViewers;

  /// Broadcast state.
  final Fc2LiveState state;

  /// `adult` 1 (member answers only).
  final bool isAdult;

  @override
  String toString() => 'Fc2LiveChannel($channelId, ${state.name})';
}

/// A member answer: the channel and its `version`, which the control grant
/// needs. An offline channel has no version (the site answers `''`).
typedef Fc2LiveMember = ({Fc2LiveChannel channel, String? version});

/// What a room carries besides 3.x's fields (never stored): the state and
/// flags behind its notice and area, so the interface can show them in its
/// own language (M13), and so a restricted room is refused before any
/// request.
@immutable
final class Fc2LiveRoomData {
  /// Creates the data.
  const new({required this.channelId, required this.state, required this.categoryId, this.isAdult = false});

  /// The channel the data belongs to.
  final String channelId;

  /// Broadcast state.
  final Fc2LiveState state;

  /// `category`.
  final int categoryId;

  /// Marked adult by the platform.
  final bool isAdult;
}

/// An anonymous control grant (`getControlServer.php`, 3.x's
/// `Fc2ControlGrant`): the control socket of one channel and its session.
@immutable
final class Fc2LiveGrant {
  /// Creates the grant.
  const new({required this.channelId, required this.socket, required this.controlToken, required this.orz});

  /// The channel.
  final String channelId;

  /// `wss://<node>.live.fc2.com/control/channels/<channel>`.
  final Uri socket;

  /// `control_token`, a JWT; it expires about a minute after the grant.
  final String controlToken;

  /// `orz_raw`, sent as the `l_ortkn` cookie of the handshake.
  final String orz;

  /// The socket with its `control_token`.
  Uri get endpoint => socket.replace(queryParameters: {'control_token': controlToken});

  /// 3.x's handshake headers: the site's origin and UA, and the session
  /// cookie.
  Map<String, String> get handshakeHeaders => {
    'origin': Fc2LiveApi.origin,
    'user-agent': Fc2LiveApi.userAgent,
    'cookie': 'l_ortkn=$orz',
  };

  @override
  String toString() => 'Fc2LiveGrant($channelId, ${socket.host})';
}

/// The public recipe of an FC2 input (3.x's `Fc2InputRecipe`): the channel
/// only. There is no URL to export: playback and recording each take a
/// grant, hold its control socket while they play and read the master it
/// announces (M7, M8).
@immutable
final class Fc2LiveInputRecipe implements LiveInputRecipe {
  /// Creates the recipe of [channelId], a channel number.
  new(this.channelId) {
    if (!Fc2LiveApi.isChannelId(channelId)) throw ArgumentError.value(channelId, 'channelId', 'not an FC2 channel');
  }

  /// The channel number.
  final String channelId;

  @override
  String get identity => 'fc2live:$channelId:auto';

  @override
  bool operator ==(Object other) => other is Fc2LiveInputRecipe && other.channelId == channelId;

  @override
  int get hashCode => identity.hashCode;

  @override
  String toString() => 'Fc2LiveInputRecipe($identity)';
}

/// Pure parsing of FC2 Live answers (3.x's `Fc2Api`, `Fc2Link` and the
/// room building of its `Fc2Site`). Each function takes the answer and its
/// status and returns 3.x's models or throws a `SiteError`; the checks are
/// 3.x's, strict: a field of the wrong type fails the whole answer.
abstract final class Fc2LiveApi {
  /// The site.
  static const String origin = 'https://live.fc2.com';

  /// Desktop Chrome 140, the UA 3.x sent with every request.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/140.0.0.0 Safari/537.36';

  /// 3.x's headers of every API request (all are form POSTs).
  static const Map<String, String> headers = {
    'user-agent': userAgent,
    'accept': 'application/json, text/javascript, */*; q=0.01',
    'accept-language': 'ja,en-US;q=0.9,en;q=0.8',
    'origin': origin,
    'referer': '$origin/',
    'x-requested-with': 'XMLHttpRequest',
  };

  /// The media request headers of a channel (3.x's `Fc2Api.mediaHeaders`,
  /// which its HLS relay sent): UA, origin and the channel page as referer.
  static Map<String, String> mediaHeaders(String channelId) => {
    'user-agent': userAgent,
    'origin': origin,
    'referer': channelUrl(channelId),
  };

  /// The largest answer 3.x accepted, in UTF-8 bytes.
  static const int responseLimit = 4 * 1024 * 1024;

  /// Rooms per native directory page (3.x's `getDirectoryPage`).
  static const int directoryPageSize = 20;

  /// Largest slice 3.x served; a larger page size gives nothing.
  static const int maxPageSize = 100;

  /// Id of the one category: the platform id (3.x).
  static const String categoryId = _site;

  /// Name of the one category and `typeName` of its areas: 3.x's site name.
  static const String categoryName = 'FC2 Live';

  /// `areaType` of the areas.
  static const String areaType = 'public';

  /// The areas in 3.x's order with 3.x's zh.json names
  /// (`fc2live_category_*`); the interface shows its own translation by
  /// area id (M13). `2` also holds category 3 (the site's "game / work").
  static const Map<String, String> areaNames = {
    'all': '全部公开直播',
    '1': '闲聊',
    '2': '游戏 / 作业',
    '4': '视频',
    '9': '音频',
    '5': '其他',
  };

  /// 3.x's zh.json text of the notices, by key.
  static const Map<String, String> noticeText = {
    'fc2live_chat_notice': 'FC2 远端聊天尚待接入；媒体控制 WebSocket 由播放或录制独占，并保持到原生输入完整释放。',
    'fc2live_access_restricted': '该 FC2 直播需要登录、积分、门票或付费；界面保留受限状态，不将其显示成未开播。',
    'fc2live_adult_notice': '该房间由平台标记为成人内容，不进入普通公开目录。',
  };

  /// 3.x's one quality: the site's adaptive HLS master (label from its
  /// zh.json `fc2live_quality_auto`).
  static const LivePlayQuality autoQuality = LivePlayQuality(id: 'auto', quality: '自适应 HLS');

  static final RegExp _channelId = RegExp(r'^[1-9]\d{0,11}$');

  /// Language prefixes of channel links (`/ja/<channel>/`).
  static const Set<String> locales = {'en', 'es', 'de', 'fr', 'id', 'ja', 'ko', 'pt', 'ru', 'th', 'tw', 'vi', 'zh'};

  // Channels and links --------------------------------------------------------

  /// Whether [value] is a channel number: 1–12 digits, no leading zero.
  static bool isChannelId(String value) => _channelId.hasMatch(value);

  /// The channel [raw] names (3.x's `Fc2Link.parseChannelId`): a channel
  /// number (trimmed), or a channel link; else null.
  static String? channelId(String raw) {
    final input = raw.trim();
    return isChannelId(input) ? input : channelIdFromUrl(input);
  }

  /// The channel of a channel link (3.x's `Fc2Link`): http(s), host
  /// `live.fc2.com` in any case, no user info or fragment, and the path
  /// `/<channel>/` or `/<language>/<channel>/` (a query is allowed).
  /// Other pages (`/rank/`, `/<channel>/archive`), hosts and schemes are
  /// null.
  static String? channelIdFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        uri.host.toLowerCase() != 'live.fc2.com' ||
        uri.hasFragment) {
      return null;
    }
    final List<String> segments;
    try {
      segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList(growable: false);
    } on FormatException {
      return null;
    }
    return switch (segments) {
      [final id] when isChannelId(id) => id,
      [final locale, final id] when locales.contains(locale.toLowerCase()) && isChannelId(id) => id,
      _ => null,
    };
  }

  /// The channel page of a checked channel number (3.x's
  /// `Fc2Link.channelUrl`), also the room's link and the external-open
  /// target (M13, which checks the stored id with [channelId] first, as
  /// 3.x did).
  static String channelUrl(String channelId) => '$origin/$channelId/';

  // Catalog -------------------------------------------------------------------

  /// 3.x's one category `FC2 Live` with its six areas.
  static LiveCategory category() => LiveCategory(
    id: categoryId,
    name: categoryName,
    children: [
      for (final MapEntry(:key, :value) in areaNames.entries)
        LiveArea(platform: _site, areaType: areaType, typeName: categoryName, areaId: key, areaName: value),
    ],
  );

  /// The category an area keeps: null for `all`, else 1, 2, 4, 5 or 9. An
  /// area of another platform or type, or another id, is the caller's
  /// mistake (3.x: `identity`).
  static int? areaFilter(LiveArea area) {
    if (area.platform != _site || area.areaType != areaType) {
      throw ArgumentError.value(area, 'category', 'not an FC2 Live area');
    }
    if (area.areaId == 'all') return null;
    final value = int.tryParse(area.areaId);
    if (value == null || !const {1, 2, 4, 5, 9}.contains(value)) {
      throw ArgumentError.value(area, 'category', 'not an FC2 Live area');
    }
    return value;
  }

  /// Whether [channel] belongs to the area of [category] (null: every
  /// channel); area 2 also keeps category 3.
  static bool inArea(Fc2LiveChannel channel, int? category) =>
      category == null || channel.categoryId == category || (category == 2 && channel.categoryId == 3);

  /// The English area name 3.x gave directory cards.
  static String directoryAreaName(int category) => switch (category) {
    1 => 'Idle Chat',
    2 || 3 => 'Game / Work',
    4 => 'Video',
    5 => 'Other',
    9 => 'Audio',
    _ => 'FC2 Live',
  };

  // Directory -----------------------------------------------------------------

  /// `allchannellist.php`: every channel on air, in the site's order. Rows
  /// other than public rooms (`type` 1: open chats, private two-shots) are
  /// skipped; restricted rooms (`pay`, `login` or `tid` not 0) stay, as
  /// 3.x kept them; a channel listed twice is kept once. 3.x's checks, all
  /// `ApiChanged`: `time` a positive integer, at most 1000 rows, each an
  /// object with an integer `type`; a public row needs a channel number,
  /// integer `pay`, `login`, `tid`, a `category` 0–99, and a name, a title
  /// or its number.
  static List<Fc2LiveChannel> directory(String body, {int status = 200}) {
    final root = _json(body, status, 'allchannellist');
    if (_int(root['time'], 'allchannellist time') < 1) throw const ApiChanged(_site, 'allchannellist: time');
    final rows = root['channel'];
    if (rows is! List || rows.length > 1000) throw const ApiChanged(_site, 'allchannellist: no channel list');
    final seen = <String>{};
    final channels = <Fc2LiveChannel>[];
    for (final row in rows) {
      final data = _object(row, 'allchannellist row');
      // Open chat and private two-shot entries are not public media rooms.
      if (_int(data['type'], 'allchannellist type') != 1) continue;
      final channel = _directoryChannel(data);
      if (seen.add(channel.channelId)) channels.add(channel);
    }
    return List.unmodifiable(channels);
  }

  static Fc2LiveChannel _directoryChannel(Map<String, dynamic> data) {
    final id = _channelNumber(data['id'], 'allchannellist id');
    final restricted = ['pay', 'login', 'tid'].any((key) => _int(data[key], 'allchannellist $key') != 0);
    final category = _category(data['category'], 'allchannellist');
    return Fc2LiveChannel(
      channelId: id,
      userName: _firstText([data['name'], id], 'allchannellist name'),
      title: _firstText([data['title'], data['name'], id], 'allchannellist title'),
      cover: _image(data['image']),
      categoryId: category,
      categoryName: directoryAreaName(category),
      currentViewers: _count(data['count'], 'allchannellist count'),
      totalViewers: _count(data['total'], 'allchannellist total'),
      state: restricted ? Fc2LiveState.restricted : Fc2LiveState.live,
    );
  }

  /// Whether 3.x served a slice of [page] × [pageSize]: page 1 and up, 1–100
  /// rooms; otherwise it gave nothing.
  static bool validSlice({required int page, required int pageSize}) =>
      page >= 1 && pageSize >= 1 && pageSize <= maxPageSize;

  /// Slice [page] of [pageSize] of [values] (3.x's `_page`); empty when
  /// [validSlice] is false or past the end.
  static List<T> slice<T>(List<T> values, {required int page, required int pageSize}) {
    if (!validSlice(page: page, pageSize: pageSize)) return const [];
    final start = (page - 1) * pageSize;
    if (start >= values.length) return const [];
    return values.sublist(start, (start + pageSize).clamp(0, values.length));
  }

  /// Native directory page [page] of [channels]: 20 rooms, more while
  /// `page × 20` is below the count (3.x).
  static LiveDirectoryPage directoryPage(List<Fc2LiveChannel> channels, {required int page}) => LiveDirectoryPage(
    rooms: [for (final channel in slice(channels, page: page, pageSize: directoryPageSize)) room(channel)],
    page: page,
    hasMore: page * directoryPageSize < channels.length,
  );

  /// The channels whose number, name, title or area name contains
  /// [keyword] (trimmed, case ignored), in the directory's order (3.x's
  /// local search; the site has no search API).
  static List<Fc2LiveChannel> search(List<Fc2LiveChannel> channels, String keyword) {
    final query = keyword.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return [
      for (final channel in channels)
        if (channel.channelId.contains(query) ||
            channel.userName.toLowerCase().contains(query) ||
            channel.title.toLowerCase().contains(query) ||
            channel.categoryName.toLowerCase().contains(query))
          channel,
    ];
  }

  // Member --------------------------------------------------------------------

  /// `memberApi.php` of [channelId].
  ///
  /// `status` other than 1 (and HTTP 404) is `NotFound` (3.x's `missing`);
  /// so is a channel that never existed, which the site answers with
  /// status 1 and an empty `profile_data.userid` (S02-member-missing). The
  /// answer must be about [channelId] (`ApiChanged`). 3.x's checks, all
  /// `ApiChanged`: integer `is_publish`, `fee`, `login_only`, `ticketid`,
  /// `ticket_only`, `is_limited` and `adult`, a `category` 0–99, text
  /// fields that are strings.
  ///
  /// `is_publish` 1 is live, anything else offline; a live channel with any
  /// of the five restriction flags is restricted. `version` is kept for the
  /// control grant: 3.x required it, but the site answers `''` for every
  /// channel that is not on air (S02-member-offline), so 3.x failed on
  /// every offline channel.
  static Fc2LiveMember member(String body, {required String channelId, int status = 200}) {
    final root = _json(body, status, 'memberApi');
    if (_int(root['status'], 'memberApi status') != 1) throw NotFound(_site, 'memberApi: no channel $channelId');
    final data = _object(root['data'], 'memberApi data');
    final channel = _object(data['channel_data'], 'memberApi channel_data');
    final rawProfile = data['profile_data'];
    final profile = rawProfile == null ? null : _object(rawProfile, 'memberApi profile_data');
    final id = _channelNumber(channel['channelid'], 'memberApi channelid');
    if (id != channelId) throw ApiChanged(_site, 'memberApi: answered for channel $id, not $channelId');
    if (profile != null && jsonString(profile['userid']) == null) {
      throw NotFound(_site, 'memberApi: channel $channelId has no owner');
    }
    final published = _int(channel['is_publish'], 'memberApi is_publish') == 1;
    final restricted = [
      'fee',
      'login_only',
      'ticketid',
      'ticket_only',
      'is_limited',
    ].any((key) => _int(channel[key], 'memberApi $key') != 0);
    final category = _category(channel['category'], 'memberApi');
    final version = _optionalText(channel['version'], 'memberApi version');
    if (version.length > 256) throw const ApiChanged(_site, 'memberApi: version over 256 characters');
    return (
      channel: Fc2LiveChannel(
        channelId: id,
        userName: _firstText([profile?['name'], channel['tname'], id], 'memberApi name'),
        title: _firstText([channel['title'], profile?['name'], id], 'memberApi title'),
        description: _optionalText(channel['info'], 'memberApi info'),
        cover: _image(channel['image']),
        categoryId: category,
        categoryName: _firstOptional([
          channel['category_name'],
          directoryAreaName(category),
        ], 'memberApi category_name'),
        currentViewers: _count(channel['count'], 'memberApi count'),
        totalViewers: _count(channel['total'], 'memberApi total'),
        state: !published
            ? Fc2LiveState.offline
            : restricted
            ? Fc2LiveState.restricted
            : Fc2LiveState.live,
        isAdult: _int(channel['adult'], 'memberApi adult') == 1,
      ),
      version: version.isEmpty ? null : version,
    );
  }

  // Rooms ---------------------------------------------------------------------

  /// The room of [channel] (3.x's `Fc2Site._room`): live, offline, or
  /// unknown when restricted (3.x kept those apart from offline); viewers
  /// now as the audience, the broadcast's total as `totalViewers`; the
  /// cover also as the avatar (3.x); the link is the channel page; 3.x's
  /// notice ([notice]); the introduction from a member answer's `info`
  /// (3.x parsed it but left it out); [Fc2LiveRoomData] for the interface
  /// and the streams. No `httpHeaders`: that field is IPTV's, the media
  /// headers travel with the control session.
  static LiveRoom room(Fc2LiveChannel channel) {
    final viewers = channel.currentViewers?.toString();
    return LiveRoom(
      platform: _site,
      roomId: channel.channelId,
      userId: channel.channelId,
      title: channel.title,
      nick: channel.userName,
      avatar: channel.cover,
      cover: channel.cover,
      area: channel.categoryName,
      link: channelUrl(channel.channelId),
      liveStatus: switch (channel.state) {
        Fc2LiveState.live => LiveStatus.live,
        Fc2LiveState.offline => LiveStatus.offline,
        Fc2LiveState.restricted => LiveStatus.unknown,
      },
      watching: viewers ?? '',
      onlineViewers: viewers ?? '',
      totalViewers: channel.totalViewers?.toString() ?? '',
      audienceMetricType: viewers == null ? AudienceMetricType.unknown : AudienceMetricType.onlineViewers,
      notice: notice(channel),
      introduction: channel.description.isEmpty ? null : channel.description,
      data: Fc2LiveRoomData(
        channelId: channel.channelId,
        state: channel.state,
        categoryId: channel.categoryId,
        isAdult: channel.isAdult,
      ),
    );
  }

  /// 3.x's notice in its zh.json text: the restriction of a restricted
  /// channel, else the adult mark, else that comments are not connected.
  static String notice(Fc2LiveChannel channel) =>
      noticeText[switch (channel) {
        Fc2LiveChannel(state: Fc2LiveState.restricted) => 'fc2live_access_restricted',
        Fc2LiveChannel(isAdult: true) => 'fc2live_adult_notice',
        _ => 'fc2live_chat_notice',
      }]!;

  // Control -------------------------------------------------------------------

  /// `getControlServer.php` of [channelId] (3.x's `parseControlGrant`):
  /// `status` other than 0 is `StreamUnavailable`. The socket must be
  /// `wss://` on `live.fc2.com` or a subdomain, without user info, query or
  /// fragment, at `/control/channels/<channelId>`; `url` (≤ 2048),
  /// `control_token` (≤ 4096) and `orz_raw` (≤ 256, a cookie-safe token)
  /// are required. Anything else is `ApiChanged`.
  static Fc2LiveGrant grant(String body, {required String channelId, int status = 200}) {
    final root = _json(body, status, 'getControlServer');
    final result = _int(root['status'], 'getControlServer status');
    if (result != 0) throw StreamUnavailable(_site, 'getControlServer: status $result');
    final url = _bounded(root['url'], 2048, 'getControlServer url');
    final token = _bounded(root['control_token'], 4096, 'getControlServer control_token');
    final orz = _bounded(root['orz_raw'], 256, 'getControlServer orz_raw');
    final socket = Uri.tryParse(url);
    if (socket == null ||
        socket.scheme != 'wss' ||
        socket.userInfo.isNotEmpty ||
        !_isFc2Live(socket.host) ||
        socket.path != '/control/channels/$channelId' ||
        socket.hasQuery ||
        socket.hasFragment ||
        !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(orz)) {
      throw const ApiChanged(_site, 'getControlServer: not a control socket of the channel');
    }
    return Fc2LiveGrant(channelId: channelId, socket: socket, controlToken: token, orz: orz);
  }

  /// The control socket's `get_hls_information` answer (3.x's
  /// `Fc2ControlSession.parseHlsResponse`): the low-latency master (mode 0)
  /// of `playlists`, the one 3.x played.
  ///
  /// `arguments.status` other than 0 is `StreamUnavailable`; rows whose
  /// `status` is not 0 are skipped. The master must be https on
  /// `live.fc2.com` or a subdomain, without user info or fragment, at
  /// `/a/stream/<channelId>/0/master_playlist`, with exactly the query
  /// parameters `c`, `d` (1–1024 characters) and `targets` (up to 16
  /// numbers of 1–3 digits). A wrong message, a malformed row or no master
  /// is `ApiChanged`.
  static Uri hlsMaster(Map<String, dynamic> response, {required String channelId}) {
    if (response['name'] != '_response_' || response['id'] != 1) {
      throw const ApiChanged(_site, 'control: not the answer to get_hls_information');
    }
    final arguments = _object(response['arguments'], 'control arguments');
    final result = _integer(arguments['status'], 'control status');
    if (result != 0) throw StreamUnavailable(_site, 'get_hls_information: status $result');
    final playlists = arguments['playlists'];
    if (playlists is! List || playlists.length > 32) throw const ApiChanged(_site, 'control: no playlists');
    for (final value in playlists) {
      final item = _object(value, 'control playlist');
      if (_integer(item['mode'], 'control mode') != 0 || _integer(item['status'], 'control playlist status') != 0) {
        continue;
      }
      final url = item['url'];
      if (url is! String || url.isEmpty || url.length > 65536) throw const ApiChanged(_site, 'control: master url');
      final uri = Uri.tryParse(url);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          !_isFc2Live(uri.host) ||
          uri.path != '/a/stream/$channelId/0/master_playlist' ||
          uri.hasFragment ||
          !_mediaToken(uri.queryParameters['c']) ||
          !_mediaToken(uri.queryParameters['d']) ||
          !_targets(uri.queryParameters['targets']) ||
          uri.queryParameters.keys.any((key) => !const {'targets', 'c', 'd'}.contains(key))) {
        throw const ApiChanged(_site, 'control: not a master playlist of the channel');
      }
      return uri;
    }
    throw const ApiChanged(_site, 'control: no master playlist');
  }

  static bool _isFc2Live(String host) {
    final value = host.toLowerCase();
    return value == 'live.fc2.com' || value.endsWith('.live.fc2.com');
  }

  static bool _mediaToken(String? value) => value != null && value.isNotEmpty && value.length <= 1024;

  static final RegExp _targetList = RegExp(r'^\d{1,3}(?:,\d{1,3}){0,15}$');

  static bool _targets(String? value) => value != null && value.length <= 128 && _targetList.hasMatch(value);

  // Checks --------------------------------------------------------------------

  /// 3.x's status mapping: 400/422 `ApiChanged` (3.x's `schema`), 401/403
  /// `RiskControl`, 404 `NotFound`, 429 `RateLimited`, 5xx and anything
  /// else (redirects included) `NetworkFailure` (3.x's `service` and
  /// `transport`).
  static void _status(int status, String what) {
    switch (status) {
      case 200:
        return;
      case 400 || 422:
        throw ApiChanged(_site, '$what: HTTP $status');
      case 401 || 403:
        throw RiskControl(_site, detail: '$what: HTTP $status');
      case 404:
        throw NotFound(_site, '$what: HTTP 404');
      case 429:
        throw RateLimited(_site, detail: '$what: HTTP 429');
    }
    throw NetworkFailure(_site, '$what: HTTP $status');
  }

  static Map<String, dynamic> _json(String body, int status, String what) {
    _status(status, what);
    if (body.length > responseLimit || (body.length * 3 > responseLimit && utf8.encode(body).length > responseLimit)) {
      throw ApiChanged(_site, '$what: over ${responseLimit ~/ (1024 * 1024)} MiB');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
    return _object(decoded, what);
  }

  static Map<String, dynamic> _object(Object? value, String what) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((key, value) => MapEntry('$key', value));
    throw ApiChanged(_site, '$what: not an object');
  }

  /// 3.x's `_int`: an integer, a finite number (truncated) or an integer
  /// string, within ±2^31-1.
  static int _int(Object? value, String what) {
    final result = switch (value) {
      final int number => number,
      final num number when number.isFinite => number.toInt(),
      final String text => int.tryParse(text.trim()),
      _ => null,
    };
    if (result == null || result < -0x7fffffff || result > 0x7fffffff) throw ApiChanged(_site, '$what: $value');
    return result;
  }

  /// 3.x's control-message integer: like [_int], without the range.
  static int _integer(Object? value, String what) {
    final result = switch (value) {
      final int number => number,
      final num number when number.isFinite => number.toInt(),
      final String text => int.tryParse(text.trim()),
      _ => null,
    };
    if (result == null) throw ApiChanged(_site, '$what: $value');
    return result;
  }

  /// Null when absent, null when negative (3.x), else the count.
  static int? _count(Object? value, String what) {
    if (value == null) return null;
    final result = _int(value, what);
    return result >= 0 ? result : null;
  }

  static int _category(Object? value, String what) {
    final result = _int(value, '$what category');
    if (result < 0 || result > 99) throw ApiChanged(_site, '$what: category $result');
    return result;
  }

  /// 3.x's `_optionalText`: absent is empty; anything but a string is
  /// `ApiChanged`; trimmed, runs of whitespace made one space, at most
  /// 65536 characters.
  static String _optionalText(Object? value, String what) {
    if (value == null) return '';
    if (value is! String) throw ApiChanged(_site, '$what: not a string');
    final result = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (result.length > 65536) throw ApiChanged(_site, '$what: over 65536 characters');
    return result;
  }

  static String _firstOptional(Iterable<Object?> values, String what) {
    for (final value in values) {
      final result = _optionalText(value, what);
      if (result.isNotEmpty) return result;
    }
    return '';
  }

  static String _firstText(Iterable<Object?> values, String what) {
    final result = _firstOptional(values, what);
    if (result.isEmpty) throw ApiChanged(_site, '$what: missing');
    return result;
  }

  static String _bounded(Object? value, int max, String what) {
    final result = _optionalText(value, what);
    if (result.isEmpty || result.length > max) throw ApiChanged(_site, '$what: missing or too long');
    return result;
  }

  static String _channelNumber(Object? value, String what) {
    final text = _optionalText(value, what);
    final id = channelId(text);
    if (text.isEmpty || id == null) throw ApiChanged(_site, '$what: $value');
    return id;
  }

  /// 3.x's `_image`: an https link on `fc2.com` or a subdomain, without
  /// user info or fragment; anything else (or no image) is empty, without
  /// failing the room.
  static String _image(Object? value) {
    final raw = _optionalText(value, 'image');
    if (raw.isEmpty) return '';
    final uri = Uri.tryParse(raw);
    final host = uri?.host.toLowerCase() ?? '';
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !(host == 'fc2.com' || host.endsWith('.fc2.com'))) {
      return '';
    }
    return uri.toString();
  }
}
