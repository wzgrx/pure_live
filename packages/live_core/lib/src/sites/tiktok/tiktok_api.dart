import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'tiktok';

/// A user's LIVE state (3.x's `TikTokState`).
enum TikTokState {
  /// `status` 2: broadcasting.
  live,

  /// `status` 4: not broadcasting.
  offline,

  /// A private account, a subscriber-only or a paid LIVE (see
  /// [TikTokRestriction]); shown as banned, as in 3.x.
  restricted,

  /// Any other `status`, or none.
  unknown,
}

/// Why a LIVE is [TikTokState.restricted], in 3.x's order of checks.
enum TikTokRestriction {
  /// `user.secret`: a private account.
  privateAccount,

  /// `liveRoom.liveSubOnly` 1: subscribers only.
  subscriberOnly,

  /// `liveRoom.paidEvent.paid_type` above 0: a paid LIVE.
  paid,
}

/// One of 3.x's stream choices: a quality tier ([qualityId], the
/// `stream_data` key) in one codec and one protocol, with its URLs. Its [id]
/// `<codec>:<qualityId>:<protocol>` is the quality's id.
@immutable
final class TikTokStream {
  /// Creates the stream.
  const new({
    required this.id,
    required this.qualityId,
    required this.protocol,
    required this.codec,
    required this.urls,
    this.resolution = '',
    this.bitrate,
  });

  /// `h264:hd:flv`.
  final String id;

  /// `origin`, `uhd_60`, `hd_60`, `uhd`, `hd`, `sd`, `ld`, `auto` or another
  /// key the site sends, lower case.
  final String qualityId;

  /// `flv` or `hls`.
  final String protocol;

  /// `h264` or `h265`.
  final String codec;

  /// `720x1280` or `720p` from `sdk_params`, else empty.
  final String resolution;

  /// `sdk_params.vbitrate`, bits per second.
  final int? bitrate;

  /// The URLs, each once, in the order read (`streamData` before
  /// `hevcStreamData`).
  final List<Uri> urls;
}

/// What a room's entry knows besides its card: the user behind the
/// username, the current LIVE and its streams. The username is the room
/// (3.x); the numeric LIVE room id changes with every broadcast.
@immutable
final class TikTokRoomData {
  /// Creates the data.
  const new({
    required this.username,
    required this.userId,
    required this.state,
    required this.issuedAt,
    this.status,
    this.restriction,
    this.secUid = '',
    this.liveRoomId = '',
    this.streamId = '',
    this.streams = const [],
  });

  /// `user.uniqueId`, lower case: the room id.
  final String username;

  /// `user.id`, the account behind the username (the room's `userId`).
  final String userId;

  /// `user.secUid`.
  final String secUid;

  /// `user.roomId`: the current (or last) LIVE room, the key of its chat and
  /// of `share/live` links; empty when the site sends none.
  final String liveRoomId;

  /// `liveRoom.streamId`.
  final String streamId;

  /// The state 3.x derived.
  final TikTokState state;

  /// `liveRoom.status` (else `user.status`) as sent.
  final int? status;

  /// Why the LIVE is restricted, when it is.
  final TikTokRestriction? restriction;

  /// The streams of a live, unrestricted LIVE, best first (3.x's order);
  /// empty otherwise.
  final List<TikTokStream> streams;

  /// When the answer arrived: the start of the URLs' lifetime.
  final DateTime issuedAt;
}

/// A TikTok link (3.x's `TikTokLink`): a user or a LIVE room.
enum TikTokLinkKind {
  /// `@<username>`: the room itself.
  username,

  /// `share/live/<LIVE room id>` (3.x's `roomId` kind): its owner is the
  /// room, found by one request.
  liveRoom,
}

/// A parsed TikTok link or search keyword (3.x's `TikTokLink`).
@immutable
final class TikTokLink {
  /// Creates the link.
  const new(this.kind, this.id);

  /// What [id] is.
  final TikTokLinkKind kind;

  /// A normalized username or LIVE room id.
  final String id;

  static const Set<String> _hosts = {'tiktok.com', 'www.tiktok.com', 'm.tiktok.com'};
  static const Set<String> _shortHosts = {'vm.tiktok.com', 'vt.tiktok.com'};
  static final RegExp _username = RegExp(r'^[a-z0-9_](?:[a-z0-9._]{0,22}[a-z0-9_])?$');
  static final RegExp _liveRoomId = RegExp(r'^[1-9][0-9]{14,24}$');

  /// [raw] trimmed and lower case when it is a username (letters, digits,
  /// `_` and `.`, at most 24, not starting or ending with a dot), else null.
  static String? normalizeUsername(String raw) {
    final value = raw.trim().toLowerCase();
    return _username.hasMatch(value) ? value : null;
  }

  /// [raw] trimmed when it is a LIVE room id (15–25 digits), else null.
  static String? normalizeLiveRoomId(String raw) {
    final value = raw.trim();
    return _liveRoomId.hasMatch(value) ? value : null;
  }

  /// A TikTok web link (3.x's rules): http(s) on `tiktok.com`,
  /// `www.tiktok.com` or `m.tiktok.com`, without user info or fragment, whose
  /// path is exactly `/@<user>`, `/@<user>/live` or
  /// `/share/live/<LIVE room id>` (a trailing slash allowed, dot segments
  /// refused). A video (`/@<user>/video/…`) is no room.
  static TikTokLink? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !_isWeb(uri) || uri.hasFragment || !_hosts.contains(uri.host.toLowerCase())) return null;
    final segments = _segments(uri);
    if (segments == null || segments.any((segment) => segment == '.' || segment == '..')) return null;
    if (segments case [final at] || [final at, _] when at.startsWith('@')) {
      if (segments.length == 2 && segments[1].toLowerCase() != 'live') return null;
      final user = normalizeUsername(at.substring(1));
      return user == null ? null : TikTokLink(TikTokLinkKind.username, user);
    }
    if (segments case [final share, final live, final room]
        when share.toLowerCase() == 'share' && live.toLowerCase() == 'live') {
      final id = normalizeLiveRoomId(room);
      return id == null ? null : TikTokLink(TikTokLinkKind.liveRoom, id);
    }
    return null;
  }

  /// What a search keyword names (3.x's `parseOrUsername`): a link (see
  /// [parse]), else a username with or without `@`.
  static TikTokLink? lookup(String keyword) {
    final link = parse(keyword);
    if (link != null) return link;
    final text = keyword.trim();
    final user = normalizeUsername(text.startsWith('@') ? text.substring(1) : text);
    return user == null ? null : TikTokLink(TikTokLinkKind.username, user);
  }

  /// A share short link, whose redirect leads to the room: `vm.tiktok.com/<code>`
  /// and `vt.tiktok.com/<code>` (3.x), and `www.tiktok.com/t/<code>` (the
  /// app's newer form, which 3.x did not know); null for anything else.
  static Uri? shortLink(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !_isWeb(uri)) return null;
    final host = uri.host.toLowerCase();
    final segments = _segments(uri);
    if (segments == null || segments.isEmpty) return null;
    if (_shortHosts.contains(host)) return uri;
    return _hosts.contains(host) && segments.length == 2 && segments.first == 't' ? uri : null;
  }

  static bool _isWeb(Uri uri) => (uri.scheme == 'http' || uri.scheme == 'https') && uri.userInfo.isEmpty;

  /// The non-empty path segments, or null when the path does not decode.
  static List<String>? _segments(Uri uri) {
    try {
      return uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    } on FormatException {
      return null;
    }
  }
}

/// Pure parsing of TikTok LIVE responses (3.x's `TikTokApi`, `TikTokLink`
/// and the card of `TikTokSite`). Each function takes the response text and
/// status and returns 3.x's models or throws a `SiteError`.
///
/// Two anonymous endpoints: a user's LIVE (`www.tiktok.com/api-live/user/room`,
/// `{statusCode, message, data: {user, stats, liveRoom}}`, the pull URLs in
/// JSON strings inside it) and a LIVE room's owner
/// (`webcast.tiktok.com/webcast/room/info`, `{status_code, data}`). There is
/// no anonymous directory, search or chat.
abstract final class TikTokApi {
  /// Website origin.
  static const String origin = 'https://www.tiktok.com';

  /// Origin of `room/info`.
  static const String webcastOrigin = 'https://webcast.tiktok.com';

  /// Desktop Chrome 140, 3.x's UA for every TikTok request and stream.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/140.0.0.0 Safari/537.36';

  /// Largest answer 3.x accepted (12 MiB).
  static const int responseLimit = 12 * 1024 * 1024;

  /// `statusCode` of a user that does not exist (`user_not_found`).
  static const int missingUserCode = 19881007;

  /// 3.x's display name (`site_tiktok`), also every room's area.
  static const String siteName = 'TikTok LIVE';

  /// The notice on every room (3.x's `tiktok_chat_notice`).
  static const String chatNotice = 'TikTok LIVE 远端聊天尚待接入；当前观看与累计进房分别展示。';

  /// 3.x's quality names by `stream_data` key (`tiktok_quality_*`); other
  /// keys are shown upper case.
  static const Map<String, String> qualityNames = {
    'origin': '原始画质',
    'uhd_60': '超清 60 帧',
    'hd_60': '高清 60 帧',
    'uhd': '超清',
    'hd': '高清',
    'sd': '标清',
    'ld': '流畅',
    'auto': '自动',
  };

  /// How long before `expire` a pull URL is renewed (at most a quarter of
  /// its lifetime; the site signs them for about 14 days).
  static const Duration leaseLead = Duration(hours: 1);

  /// The room's web page (3.x's `TikTokLink.url`), also where "open in
  /// browser" goes and the media Referer.
  static String roomUrl(String username) => '$origin/@$username/live';

  /// Where "open in browser" goes for room [roomId] (3.x's
  /// `RoomExternalOpener`): its web page, or null for a room id that is no
  /// username (the stored link is not trusted).
  static String? externalRoomUrl(String roomId) {
    final username = TikTokLink.normalizeUsername(roomId);
    return username == null ? null : roomUrl(username);
  }

  /// The LIVE of [username], spelled as 3.x sent it.
  static Uri userRoomUrl(String username) =>
      Uri.parse('$origin/api-live/user/room/')
          .replace(queryParameters: {'aid': '1988', 'sourceType': '54', 'staleTime': '600000', 'uniqueId': username});

  /// The owner of LIVE room [liveRoomId], spelled as 3.x sent it.
  static Uri roomInfoUrl(String liveRoomId) =>
      Uri.parse('$webcastOrigin/webcast/room/info/').replace(queryParameters: {'aid': '1988', 'room_id': liveRoomId});

  /// Headers of the API requests (3.x's `requestHeaders`): the Referer is the
  /// room of [username], else the LIVE landing page.
  static Map<String, String> requestHeaders({String? username}) => {
    'user-agent': userAgent,
    'accept': 'application/json, text/plain, */*',
    'accept-language': 'en-US,en;q=0.9',
    'origin': origin,
    'referer': username == null ? '$origin/live' : roomUrl(username),
  };

  /// Headers of the media requests (3.x's `mediaHeaders`, sent by its
  /// `PlaybackHeaderResolver`).
  static Map<String, String> mediaHeaders(String username) => {
    'user-agent': userAgent,
    'origin': origin,
    'referer': roomUrl(username),
  };

  // Rooms ---------------------------------------------------------------------

  /// `api-live/user/room` for [username] (normalized) as 3.x read it.
  ///
  /// The answer must be that user (`uniqueId`), with 3.x's field checks
  /// (see the helpers), or it is `ApiChanged`; `statusCode` 19881007 (or a
  /// message saying so) is `NotFound`, any other code `ApiChanged`.
  ///
  /// The card: the username as the room, `user.id` as `userId`, the title
  /// (the nickname when empty; offline it is the last LIVE's), avatar and
  /// cover from trusted https hosts (see [isTrustedHost]), the signature,
  /// followers, the state (restricted is banned, as in 3.x) and, only while
  /// live, `userCount` as concurrent viewers and `enterCount` as cumulative
  /// entries. With [includeMedia] (room entry and recording) `data` is the
  /// [TikTokRoomData] and a live, unrestricted LIVE's streams are read;
  /// without it (follow refreshes, search) nothing of them is read, as in
  /// 3.x.
  static LiveRoom room(
    String body, {
    required String username,
    required bool includeMedia,
    required DateTime issuedAt,
    int status = 200,
  }) {
    final root = _envelope(body, status: status, what: 'user/room');
    final code = _integer(root['statusCode']);
    if (code != 0) {
      final message = _optionalText(root['message'], 'user/room.message');
      final lower = message.toLowerCase();
      if (code == missingUserCode || lower.contains('not exist') || lower.contains('not_found')) {
        throw NotFound(_site, 'user/room: $username ($code $message)');
      }
      throw ApiChanged(_site, 'user/room: statusCode $code $message');
    }
    final data = _object(root['data'], 'user/room.data');
    final user = _object(data['user'], 'user/room.data.user');
    final stats = _optionalObject(data['stats'], 'user/room.data.stats');
    final live = _object(data['liveRoom'], 'user/room.data.liveRoom');
    final actual = _username(user['uniqueId'], 'user.uniqueId');
    if (actual != username) throw ApiChanged(_site, 'user/room: asked $username, got $actual');

    final liveStatus = _integer(live['status'] ?? user['status']);
    final paidValue = live['paidEvent'];
    final paid = paidValue == null || (paidValue is List && paidValue.isEmpty)
        ? const <String, dynamic>{}
        : _object(paidValue, 'liveRoom.paidEvent');
    final secret = _optionalBool(user['secret'], 'user.secret') ?? false;
    final restriction = secret
        ? TikTokRestriction.privateAccount
        : _integer(live['liveSubOnly']) == 1
        ? TikTokRestriction.subscriberOnly
        : (_integer(paid['paid_type']) ?? 0) > 0
        ? TikTokRestriction.paid
        : null;
    final state = restriction != null
        ? TikTokState.restricted
        : switch (liveStatus) {
            2 => TikTokState.live,
            4 => TikTokState.offline,
            _ => TikTokState.unknown,
          };
    final roomStats = _optionalObject(live['liveRoomStats'], 'liveRoom.liveRoomStats');
    final nickname = _text(user['nickname'], 'user.nickname');
    final title = _optionalText(live['title'], 'liveRoom.title');
    final userId = _longId(user['id'], 'user.id');
    final secUid = _optionalText(user['secUid'], 'user.secUid');
    final liveRoomId = _optionalLongId(user['roomId'], 'user.roomId');
    final streamId = _optionalLongId(live['streamId'], 'liveRoom.streamId');
    final bio = _optionalText(user['signature'], 'user.signature');
    final followers = _optionalCount(stats['followerCount'], 'stats.followerCount');
    final isLive = state == TikTokState.live;
    final online = isLive ? _optionalCount(roomStats['userCount'], 'liveRoomStats.userCount') : null;
    final entered = isLive ? _optionalCount(roomStats['enterCount'], 'liveRoomStats.enterCount') : null;
    _optionalBool(user['verified'], 'user.verified');
    final streams = isLive && includeMedia ? _streams(live) : const <TikTokStream>[];
    return LiveRoom(
      platform: _site,
      roomId: username,
      userId: userId,
      nick: nickname,
      title: title.isEmpty ? nickname : title,
      avatar: _image([user['avatarLarger'], user['avatarMedium'], user['avatarThumb']]),
      cover: _image([live['coverUrl'], live['squareCoverImg']]),
      area: siteName,
      followers: followers?.toString() ?? '',
      introduction: bio,
      link: roomUrl(username),
      liveStatus: switch (state) {
        TikTokState.live => LiveStatus.live,
        TikTokState.offline => LiveStatus.offline,
        TikTokState.restricted => LiveStatus.banned,
        TikTokState.unknown => LiveStatus.unknown,
      },
      watching: online?.toString() ?? '',
      onlineViewers: online?.toString() ?? '',
      totalViewers: entered?.toString() ?? '',
      audienceMetricType: AudienceMetricType.onlineViewers,
      notice: chatNotice,
      data: includeMedia
          ? TikTokRoomData(
              username: username,
              userId: userId,
              secUid: secUid,
              liveRoomId: liveRoomId,
              streamId: streamId,
              state: state,
              status: liveStatus,
              restriction: restriction,
              streams: streams,
              issuedAt: issuedAt,
            )
          : null,
    );
  }

  /// `webcast/room/info`: the username owning LIVE room [liveRoomId]
  /// (`data.owner.display_id`). A `status_code` other than 0 is `NotFound`;
  /// an answer about another LIVE room, or without a username, `ApiChanged`.
  static String owner(String body, {required String liveRoomId, int status = 200}) {
    final root = _envelope(body, status: status, what: 'room/info');
    final code = _integer(root['status_code']);
    if (code != 0) throw NotFound(_site, 'room/info: LIVE room $liveRoomId (status_code $code)');
    final data = _object(root['data'], 'room/info.data');
    final id = _longId(data['id'], 'room/info.data.id');
    if (id != liveRoomId) throw ApiChanged(_site, 'room/info: asked $liveRoomId, got $id');
    return _username(_object(data['owner'], 'room/info.data.owner')['display_id'], 'owner.display_id');
  }

  /// Why the LIVE [data] describes cannot be played, or null when it can:
  /// - restricted: `NeedsLogin` (a follower, subscriber or buyer account;
  ///   the app has no TikTok login);
  /// - a state 3.x did not know, offline, or live without a stream:
  ///   `StreamUnavailable`.
  static SiteError? unplayable(TikTokRoomData data) => switch (data.state) {
    TikTokState.restricted => NeedsLogin(_site, '@${data.username}: ${data.restriction?.name ?? 'restricted'}'),
    TikTokState.unknown => StreamUnavailable(_site, '@${data.username}: status ${data.status} not known'),
    TikTokState.offline => StreamUnavailable(_site, '@${data.username} is offline'),
    TikTokState.live when data.streams.isEmpty => StreamUnavailable(_site, '@${data.username}: live without a stream'),
    TikTokState.live => null,
  };

  // Streams -------------------------------------------------------------------

  /// 3.x's qualities: one per stream, named by [qualityName]
  /// (`高清 · 720x1280 · H264 · FLV`), best first ([qualitySort]).
  static List<LivePlayQuality> qualities(TikTokRoomData data) => List.unmodifiable([
    for (final stream in data.streams)
      LivePlayQuality(quality: qualityName(stream), id: stream.id, sort: qualitySort(stream)),
  ]);

  /// A stream's quality name (3.x).
  static String qualityName(TikTokStream stream) {
    final resolution = stream.resolution.isEmpty ? '' : ' · ${stream.resolution}';
    final tier = qualityNames[stream.qualityId] ?? stream.qualityId.toUpperCase();
    return '$tier$resolution · ${stream.codec.toUpperCase()} · ${stream.protocol.toUpperCase()}';
  }

  /// 3.x's rank: the tier (origin 10000 … auto 3000, others 1000), then
  /// H.264 (+100) before H.265, then FLV (+20) before HLS (+10).
  static int qualitySort(TikTokStream stream) {
    final tier = switch (stream.qualityId) {
      'origin' => 10000,
      'uhd_60' => 9000,
      'hd_60' => 8000,
      'uhd' => 7000,
      'hd' => 6000,
      'sd' => 5000,
      'ld' => 4000,
      'auto' => 3000,
      _ => 1000,
    };
    return tier + (stream.codec == 'h264' ? 100 : 0) + (stream.protocol == 'flv' ? 20 : 10);
  }

  /// The lines of [quality] in [data] (one per URL, usually one), applied as
  /// asked (3.x): the media headers of the room, the protocol's format, the
  /// codec, the CDN host as the line id and the lease of the URL's
  /// `expire`. A quality [data] does not offer is `StreamUnavailable`.
  static LivePlayUrlResolution resolution(TikTokRoomData data, LivePlayQuality quality) {
    final id = '${quality.selectionId}';
    final stream = data.streams.where((stream) => stream.id == id).firstOrNull;
    if (stream == null) throw StreamUnavailable(_site, '@${data.username}: quality $id is not offered');
    final headers = mediaHeaders(data.username);
    return LivePlayUrlResolution.lines([
      for (final url in stream.urls)
        LivePlayLine(
          '$url',
          headers: headers,
          format: stream.protocol == 'flv' ? StreamFormat.flv : StreamFormat.hls,
          codec: stream.codec == 'h264' ? 'avc' : 'hevc',
          lineId: url.host,
          lease: lease(url, data.issuedAt),
        ),
    ], appliedQualityData: stream.id);
  }

  /// The lease of a pull URL received at [issuedAt], from its `expire` (Unix
  /// seconds; the site signs for about 14 days): renew [leaseLead] (at most
  /// a quarter of the lifetime) before. Expiry does not cut an established
  /// connection. No `expire`, or one already past, is no lease.
  static PlayLease? lease(Uri url, DateTime issuedAt) {
    final expire = int.tryParse(url.queryParameters['expire'] ?? '');
    if (expire == null || expire <= 0) return null;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expire * 1000, isUtc: true);
    final lifetime = expiresAt.difference(issuedAt);
    if (lifetime <= Duration.zero) return null;
    final quarter = lifetime ~/ 4;
    return PlayLease(refreshAt: expiresAt.subtract(quarter < leaseLead ? quarter : leaseLead), expiresAt: expiresAt);
  }

  /// Whether [host] may serve TikTok pictures and streams: 3.x's
  /// `tiktokcdn.com`, `tiktokv.com` and `byteoversea.com`, and the regional
  /// CDNs `tiktokcdn-us.com` (where the sample's user was served; 3.x
  /// refused it) and `tiktokcdn-eu.com`, each with its subdomains.
  static bool isTrustedHost(String host) {
    final value = host.toLowerCase();
    return _trustedRoots.any((root) => value == root || value.endsWith('.$root'));
  }

  static const List<String> _trustedRoots = [
    'tiktokcdn.com',
    'tiktokcdn-us.com',
    'tiktokcdn-eu.com',
    'tiktokv.com',
    'byteoversea.com',
  ];

  /// 3.x's reading of `streamData` (codec H.264 unless `sdk_params` says)
  /// then `hevcStreamData` (H.265 unless it says): `pull_data.stream_data` is
  /// JSON in a string, its `data` maps at most 32 tier keys to `main` with
  /// `flv` and `hls` URLs and `sdk_params` (JSON in a string again). The
  /// audio-only `ao` is left out; streams of the same codec, tier and
  /// protocol are merged. Sorted by [qualitySort], then by id.
  static List<TikTokStream> _streams(Map<String, dynamic> live) {
    final builders = <String, _StreamBuilder>{};
    for (final (key, fallback) in const [('streamData', 'h264'), ('hevcStreamData', 'h265')]) {
      final value = live[key];
      if (value == null) continue;
      final pull = _object(_object(value, 'liveRoom.$key')['pull_data'], '$key.pull_data');
      final raw = _optionalText(pull['stream_data'], '$key.stream_data');
      if (raw.isEmpty || raw.length > 4 * 1024 * 1024) continue;
      final tiers = _object(_object(_decode(raw, '$key.stream_data'), '$key.stream_data')['data'], '$key.data');
      if (tiers.length > 32) throw ApiChanged(_site, '$key: ${tiers.length} tiers');
      for (final MapEntry(key: rawTier, :value) in tiers.entries) {
        final tier = _tier(rawTier, key);
        if (tier == 'ao') continue;
        final main = _object(_object(value, '$key.$tier')['main'], '$key.$tier.main');
        final sdkRaw = _optionalText(main['sdk_params'], '$key.$tier.sdk_params');
        final sdk = sdkRaw.isEmpty
            ? const <String, dynamic>{}
            : _object(_decode(sdkRaw, '$key.$tier.sdk_params'), '$key.$tier.sdk_params');
        final codec = _codec(sdk['VCodec'] ?? sdk['v_codec'], fallback, '$key.$tier');
        final resolution = _resolution(sdk['resolution'], '$key.$tier');
        final bitrate = _optionalCount(sdk['vbitrate'], '$key.$tier.vbitrate');
        for (final protocol in const ['flv', 'hls']) {
          final text = _optionalText(main[protocol], '$key.$tier.$protocol');
          if (text.isEmpty) continue;
          final url = _mediaUrl(text, '$key.$tier.$protocol');
          final id = '$codec:$tier:$protocol';
          final builder = builders.putIfAbsent(
            id,
            () => _StreamBuilder(id: id, tier: tier, protocol: protocol, codec: codec, resolution: resolution),
          );
          if (builder.resolution.isEmpty) builder.resolution = resolution;
          builder.bitrate ??= bitrate;
          if (!builder.urls.contains(url)) builder.urls.add(url);
        }
      }
    }
    final streams =
        [
          for (final builder in builders.values)
            TikTokStream(
              id: builder.id,
              qualityId: builder.tier,
              protocol: builder.protocol,
              codec: builder.codec,
              resolution: builder.resolution,
              bitrate: builder.bitrate,
              urls: List.unmodifiable(builder.urls),
            ),
        ]..sort(
          (a, b) => switch (qualitySort(b).compareTo(qualitySort(a))) {
            0 => a.id.compareTo(b.id),
            final rank => rank,
          },
        );
    return List.unmodifiable(streams);
  }

  // Envelopes -----------------------------------------------------------------

  /// The JSON object of an answer. HTTP 400 is `ApiChanged`, 401/403
  /// `RiskControl`, 404 `NotFound`, 420/429 `RateLimited`, 5xx and any other
  /// status but 200 `NetworkFailure` (3.x read no body then). An empty body
  /// is `RiskControl` (the site's anonymous refusal); a body over
  /// [responseLimit], not JSON or not an object, `ApiChanged`.
  static Map<String, dynamic> _envelope(String body, {required int status, required String what}) {
    switch (status) {
      case 200:
        break;
      case 400:
        throw ApiChanged(_site, '$what: HTTP 400');
      case 401 || 403:
        throw RiskControl(_site, detail: '$what: HTTP $status');
      case 404:
        throw NotFound(_site, '$what: HTTP 404');
      case 420 || 429:
        throw RateLimited(_site, detail: '$what: HTTP $status');
      default:
        throw NetworkFailure(_site, '$what: HTTP $status');
    }
    if (body.isEmpty) throw RiskControl(_site, detail: '$what: empty answer');
    // A UTF-16 unit is at most three UTF-8 bytes: short bodies are not
    // encoded to be counted.
    if (body.length > responseLimit || (body.length * 3 > responseLimit && utf8.encode(body).length > responseLimit)) {
      throw ApiChanged(_site, '$what: answer over $responseLimit bytes');
    }
    return _object(_decode(body, what), what);
  }
}

final class _StreamBuilder {
  new({required this.id, required this.tier, required this.protocol, required this.codec, required this.resolution});

  final String id;
  final String tier;
  final String protocol;
  final String codec;
  String resolution;
  int? bitrate;
  final List<Uri> urls = [];
}

// Helpers (3.x's checks; each failure is ApiChanged naming the field) ----------

Object? _decode(String text, String what) {
  try {
    return jsonDecode(text);
  } on FormatException {
    throw ApiChanged(_site, '$what: not JSON');
  }
}

Map<String, dynamic> _object(Object? value, String what) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, value) => MapEntry('$key', value));
  throw ApiChanged(_site, '$what: expected an object');
}

Map<String, dynamic> _optionalObject(Object? value, String what) =>
    value == null ? const <String, dynamic>{} : _object(value, what);

/// 3.x's `_integer`: an int, an integral number or an integer string.
int? _integer(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

/// 3.x's `_optionalNonNegativeInt`: absent or blank is null; anything else
/// must be an integer of zero or more.
int? _optionalCount(Object? value, String what) {
  if (value == null || value == '') return null;
  final count = _integer(value);
  if (count == null || count < 0) throw ApiChanged(_site, '$what: $value');
  return count;
}

bool? _optionalBool(Object? value, String what) {
  if (value == null || value is bool) return value as bool?;
  throw ApiChanged(_site, '$what: $value');
}

String _username(Object? value, String what) {
  final user = value is String ? TikTokLink.normalizeUsername(value) : null;
  if (user == null) throw ApiChanged(_site, '$what: $value is no username');
  return user;
}

/// 3.x's `_longId`: 15–25 digits, from a string or a number.
String _longId(Object? value, String what) {
  final text = value?.toString().trim() ?? '';
  if (!RegExp(r'^[1-9][0-9]{14,24}$').hasMatch(text)) throw ApiChanged(_site, '$what: $value');
  return text;
}

String _optionalLongId(Object? value, String what) => value == null || value == '' ? '' : _longId(value, what);

/// 3.x's `_text`: a non-blank string of at most 8192 characters, trimmed.
String _text(Object? value, String what) {
  if (value is String && value.trim().isNotEmpty && value.length <= 8192) return value.trim();
  throw ApiChanged(_site, '$what: expected a name');
}

/// 3.x's `_optionalText`: absent is empty; else a string of at most 4 MiB,
/// trimmed.
String _optionalText(Object? value, String what) {
  if (value == null || value == '') return '';
  if (value is String && value.length <= 4 * 1024 * 1024) return value.trim();
  throw ApiChanged(_site, '$what: expected a string');
}

/// 3.x's `_qualityId`: a tier key, lower case, of letters, digits and `_`.
String _tier(String raw, String what) {
  final value = raw.trim().toLowerCase();
  if (!RegExp(r'^[a-z0-9_]{1,24}$').hasMatch(value)) throw ApiChanged(_site, '$what: tier "$raw"');
  return value;
}

/// 3.x's `_codec`, plus `bytevc1` (ByteDance's name for H.265, which 3.x
/// refused): empty is [fallback]; any other name is `ApiChanged`.
String _codec(Object? value, String fallback, String what) =>
    switch (_optionalText(value, '$what.VCodec').toLowerCase()) {
      '' => fallback,
      'avc' || 'h264' => 'h264',
      'hevc' || 'h265' || 'bytevc1' => 'h265',
      final other => throw ApiChanged(_site, '$what: codec $other'),
    };

/// 3.x's `_resolution`: `720x1280` or `720p`, else empty.
String _resolution(Object? value, String what) {
  final text = _optionalText(value, '$what.resolution').toLowerCase();
  return RegExp(r'^(?:[1-9][0-9]{1,4}x[1-9][0-9]{1,4}|[1-9][0-9]{2,4}p)$').hasMatch(text) ? text : '';
}

/// 3.x's `_mediaUri`: https on a trusted host ([TikTokApi.isTrustedHost]),
/// without user info, fragment, spaces or control characters, at most 64 KiB.
Uri _mediaUrl(String text, String what) {
  final uri = text.length > 65536 || RegExp(r'[\s\x00-\x1f]').hasMatch(text) ? null : Uri.tryParse(text);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      !TikTokApi.isTrustedHost(uri.host)) {
    throw ApiChanged(_site, '$what: not a TikTok media URL');
  }
  return uri;
}

/// The first of [candidates] that is an https picture on a trusted host
/// (3.x's `_image`, which tried only the first one present), else empty.
String _image(List<Object?> candidates) {
  for (final candidate in candidates) {
    final url = normalizeImageUrl(candidate is String && candidate.length <= 16384 ? candidate : null);
    final uri = Uri.tryParse(url);
    if (uri != null &&
        uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment &&
        TikTokApi.isTrustedHost(uri.host)) {
      return url;
    }
  }
  return '';
}
