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

/// A user's LIVE state (3.x's `TikTokState`, without its `restricted`: a
/// restricted LIVE is live now, with a [LiveRestriction], 22-1).
enum TikTokState {
  /// `status` 2: broadcasting.
  live,

  /// `status` 4: not broadcasting.
  offline,

  /// Any other `status`, or none.
  unknown,
}

/// One quality: a tier ([qualityId], the `stream_data` key) in one codec,
/// with its FLV and HLS URLs as lines that stand in for each other (22-2).
/// Its [id] `<codec>:<qualityId>` is the quality's id.
@immutable
final class TikTokStream {
  /// Creates the stream.
  const new({
    required this.id,
    required this.qualityId,
    required this.codec,
    this.flvUrls = const [],
    this.hlsUrls = const [],
    this.label = '',
    this.resolution = '',
    this.bitrate,
  });

  /// `h264:origin`.
  final String id;

  /// `origin`, `uhd_60`, `hd_60`, `uhd`, `hd`, `sd`, `ld`, `auto` or another
  /// key the site sends, lower case.
  final String qualityId;

  /// `h264` or `h265`.
  final String codec;

  /// The site's own name of the tier (`pull_data.options.qualities[].name`
  /// of the container it came from: `720p`, `1080p60`, `Original`), else
  /// empty. See [TikTokApi.qualityName].
  final String label;

  /// `720x1280` or `720p` from `sdk_params`, else empty.
  final String resolution;

  /// `sdk_params.vbitrate`, bits per second.
  final int? bitrate;

  /// The FLV URLs, each once, in the order read (`streamData` before
  /// `hevcStreamData`).
  final List<Uri> flvUrls;

  /// The HLS URLs, likewise.
  final List<Uri> hlsUrls;

  /// Every URL, FLV first: the order of the lines.
  List<Uri> get urls => [...flvUrls, ...hlsUrls];
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
    this.skipped = const [],
  });

  /// `user.uniqueId`, lower case: the room id.
  final String username;

  /// `user.id`, the account behind the username (the room's `userId`);
  /// empty when the site sends none that is valid.
  final String userId;

  /// `user.secUid`.
  final String secUid;

  /// `user.roomId`: the current (or last) LIVE room, the key of its chat and
  /// of `share/live` links; empty when the site sends none.
  final String liveRoomId;

  /// `liveRoom.streamId`.
  final String streamId;

  /// The LIVE's state.
  final TikTokState state;

  /// `liveRoom.status` (else `user.status`) as sent.
  final int? status;

  /// Who may watch a live LIVE ([LiveRestriction.none] for everyone, see
  /// [TikTokApi.restrictionOf]); null unless live.
  final LiveRestriction? restriction;

  /// The streams of a live, unrestricted LIVE, as read (see
  /// [TikTokApi.qualities] for their order); empty otherwise.
  final List<TikTokStream> streams;

  /// What of the stream containers was skipped as malformed (a container,
  /// a tier or one URL, with the reason), for the error when nothing is
  /// left to play; empty when everything was read.
  final List<String> skipped;

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

  /// The notice on every room, 3.x's `tiktok_chat_notice` ("TikTok LIVE
  /// 远端聊天尚待接入；当前观看与累计进房分别展示。") said for viewers (the
  /// unified rule on notices). The key stays; M13 translates it.
  static const String chatNotice = 'TikTok 直播的评论暂时不能在这里显示。在线人数是正在看的人数，累计是进过直播间的人数。';

  /// The name of the source tier `origin` (the unified rule on quality
  /// names; the site calls it `Original`).
  static const String originName = '原画';

  /// Added to the name of an H.265 quality (`720p · H.265`), which is only
  /// picked by hand while "优先 H.264" is on (22-3); it also keeps a stored
  /// preference such as 3.x's "原画" from matching the H.265 twin of a tier.
  static const String h265Suffix = ' · H.265';

  /// 3.x's quality names by `stream_data` key (`tiktok_quality_*`), the last
  /// resort of [qualityName] for a tier the site neither names nor gives a
  /// resolution; other keys are shown upper case.
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

  /// Most requests a short link typed into search is read with, one per
  /// redirect, each to a TikTok short link (22-5).
  static const int maxShortLinkHops = 3;

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
  /// The answer must be that user (`uniqueId`), or it is `ApiChanged`;
  /// `statusCode` 19881007 (or a message saying so) is `NotFound`, any
  /// other code `ApiChanged`. The fields the state, the restriction and
  /// the streams depend on keep 3.x's checks (`secret`, `paidEvent`); the
  /// others no longer fail the answer when malformed (22-6: `verified` is
  /// not read, and a bad `nickname`, `id`, `secUid`, `roomId`, `streamId`,
  /// `title`, `signature`, `stats` or count is left empty).
  ///
  /// The card: the username as the room, `user.id` as `userId`, the title
  /// (the nickname when empty; offline it is the last LIVE's), avatar and
  /// cover from trusted https hosts (see [isTrustedHost]), the signature,
  /// followers and the state. While live (restricted or not, 22-1) it also
  /// has `userCount` as concurrent viewers, `enterCount` as cumulative
  /// entries, the start ([startTime]) and who may watch ([restrictionOf]).
  /// With [includeMedia] (room entry and recording) `data` is the
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
    final live = _object(data['liveRoom'], 'user/room.data.liveRoom');
    final actual = _username(user['uniqueId'], 'user.uniqueId');
    if (actual != username) throw ApiChanged(_site, 'user/room: asked $username, got $actual');

    final liveStatus = _integer(live['status'] ?? user['status']);
    final state = switch (liveStatus) {
      2 => TikTokState.live,
      4 => TikTokState.offline,
      _ => TikTokState.unknown,
    };
    final isLive = state == TikTokState.live;
    // Checked in every state, as 3.x did; kept only while live.
    final restriction = restrictionOf(user, live);
    final stats = _lenientObject(data['stats']);
    final roomStats = _lenientObject(live['liveRoomStats']);
    final nickname = _lenientText(user['nickname']);
    final title = _lenientText(live['title']);
    final userId = _lenientLongId(user['id']);
    final followers = _lenientCount(stats['followerCount']);
    final online = isLive ? _lenientCount(roomStats['userCount']) : null;
    final entered = isLive ? _lenientCount(roomStats['enterCount']) : null;
    final read = isLive && includeMedia && restriction == LiveRestriction.none ? _streams(live) : null;
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
      introduction: _lenientText(user['signature']),
      link: roomUrl(username),
      liveStatus: switch (state) {
        TikTokState.live => LiveStatus.live,
        TikTokState.offline => LiveStatus.offline,
        TikTokState.unknown => LiveStatus.unknown,
      },
      startedAt: isLive ? startTime(live['startTime']) : null,
      restriction: isLive ? restriction : null,
      watching: online?.toString() ?? '',
      onlineViewers: online?.toString() ?? '',
      totalViewers: entered?.toString() ?? '',
      audienceMetricType: AudienceMetricType.onlineViewers,
      notice: chatNotice,
      data: includeMedia
          ? TikTokRoomData(
              username: username,
              userId: userId,
              secUid: _lenientText(user['secUid']),
              liveRoomId: _lenientLongId(user['roomId']),
              streamId: _lenientLongId(live['streamId']),
              state: state,
              status: liveStatus,
              restriction: isLive ? restriction : null,
              streams: read?.streams ?? const [],
              skipped: read?.skipped ?? const [],
              issuedAt: issuedAt,
            )
          : null,
    );
  }

  /// Who may watch the LIVE of [user] ([live] its `liveRoom`), in 3.x's
  /// order of checks: a private account (`user.secret`) is for its
  /// followers ([LiveRestriction.private]), `liveSubOnly` 1 for subscribers
  /// ([LiveRestriction.subscribersOnly]), `paidEvent.paid_type` above 0 is
  /// a paid LIVE ([LiveRestriction.paid]); else [LiveRestriction.none].
  /// `secret` must be a boolean and `paidEvent` an object (or absent, null,
  /// an empty list), as 3.x checked; anything else is `ApiChanged`.
  static LiveRestriction restrictionOf(Map<String, dynamic> user, Map<String, dynamic> live) {
    final paidValue = live['paidEvent'];
    final paid = paidValue == null || (paidValue is List && paidValue.isEmpty)
        ? const <String, dynamic>{}
        : _object(paidValue, 'liveRoom.paidEvent');
    final secret = _optionalBool(user['secret'], 'user.secret') ?? false;
    if (secret) return LiveRestriction.private;
    if (_integer(live['liveSubOnly']) == 1) return LiveRestriction.subscribersOnly;
    if ((_integer(paid['paid_type']) ?? 0) > 0) return LiveRestriction.paid;
    return LiveRestriction.none;
  }

  /// `liveRoom.startTime` (Unix seconds) as a UTC time; null when missing,
  /// not an integer, or outside 2000–2100.
  static DateTime? startTime(Object? value) {
    final seconds = _integer(value);
    if (seconds == null || seconds < 946684800 || seconds > 4102444800) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
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

  /// Where a short link answered with [status] and [locations] leads
  /// (22-5, search): the one `Location` of a redirect, resolved against
  /// [link], when it is http(s) without user info; null for an answer that
  /// is no redirect (2xx), an unknown code (400, 404, 410) or a redirect
  /// without a usable target. 401/403 is `RiskControl`, 420/429
  /// `RateLimited`, anything else `NetworkFailure`.
  static Uri? shortLinkTarget(Uri link, {required int status, List<String>? locations}) {
    if (const {301, 302, 303, 307, 308}.contains(status)) {
      if (locations == null || locations.length != 1 || locations.single.trim().isEmpty) return null;
      try {
        final target = link.resolve(locations.single.trim());
        final web = target.scheme == 'https' || target.scheme == 'http';
        return web && target.host.isNotEmpty && target.userInfo.isEmpty ? target : null;
      } on FormatException {
        return null;
      }
    }
    return switch (status) {
      >= 200 && < 300 || 400 || 404 || 410 => null,
      401 || 403 => throw RiskControl(_site, detail: 'short link: HTTP $status'),
      420 || 429 => throw RateLimited(_site, detail: 'short link: HTTP $status'),
      _ => throw NetworkFailure(_site, 'short link: HTTP $status'),
    };
  }

  /// Why the LIVE [data] describes cannot be played, or null when it can:
  /// - restricted (22-1): `StreamUnavailable` naming who may watch (the app
  ///   has no TikTok account, so no login would help);
  /// - a state 3.x did not know, or offline: `StreamUnavailable`;
  /// - live without a stream: `StreamUnavailable`, or `ApiChanged` when
  ///   streams were sent but none could be read ([TikTokRoomData.skipped]).
  static SiteError? unplayable(TikTokRoomData data) {
    final who = '@${data.username}';
    return switch (data.state) {
      TikTokState.unknown => StreamUnavailable(_site, '$who: status ${data.status} not known'),
      TikTokState.offline => StreamUnavailable(_site, '$who is offline'),
      TikTokState.live => switch (data.restriction ?? LiveRestriction.none) {
        LiveRestriction.private => StreamUnavailable(_site, "$who: a private account's LIVE, for its followers only"),
        LiveRestriction.subscribersOnly => StreamUnavailable(_site, '$who: a LIVE for subscribers only'),
        LiveRestriction.paid => StreamUnavailable(_site, '$who: a paid LIVE'),
        LiveRestriction.none when data.streams.isEmpty && data.skipped.isNotEmpty => ApiChanged(
          _site,
          '$who: no stream could be read (${data.skipped.join('; ')})',
        ),
        LiveRestriction.none when data.streams.isEmpty => StreamUnavailable(_site, '$who: live without a stream'),
        LiveRestriction.none => null,
        final other => StreamUnavailable(_site, '$who: ${other.name}'),
      },
    };
  }

  // Streams -------------------------------------------------------------------

  /// The qualities of [data], one per tier and codec (22-2), named by
  /// [qualityName] (22-4). With [preferH264] ("优先 H.264", on by default,
  /// 22-3) every H.264 quality comes first, best first, then the H.265 ones,
  /// so the default is H.264 and H.265 is only picked by hand; off, 3.x's
  /// order: best tier first, H.264 before H.265 within a tier. The `sort`
  /// is [qualitySort] either way. A name used twice gets its tier key.
  static List<LivePlayQuality> qualities(TikTokRoomData data, {bool preferH264 = true}) {
    final ordered = [...data.streams]
      ..sort(
        (a, b) => switch (qualitySort(b).compareTo(qualitySort(a))) {
          0 => a.id.compareTo(b.id),
          final rank => rank,
        },
      );
    final streams = preferH264
        ? [
            for (final stream in ordered)
              if (stream.codec == 'h264') stream,
            for (final stream in ordered)
              if (stream.codec != 'h264') stream,
          ]
        : ordered;
    final names = [for (final stream in streams) qualityName(stream)];
    return List.unmodifiable([
      for (final (index, stream) in streams.indexed)
        LivePlayQuality(
          quality: names.where((name) => name == names[index]).length > 1
              ? '${names[index]} (${stream.qualityId})'
              : names[index],
          id: stream.id,
          sort: qualitySort(stream),
        ),
    ]);
  }

  /// A stream's quality name (22-4): [originName] for `origin`, else the
  /// site's own name ([TikTokStream.label]: `720p`, `1080p60`), else one
  /// made the site's way from the resolution (`720x1280` → `720p`, and
  /// `60` for a `_60` tier), else 3.x's [qualityNames], else the key upper
  /// case; H.265 adds [h265Suffix].
  static String qualityName(TikTokStream stream) {
    final tier = stream.qualityId;
    final base = tier == 'origin'
        ? originName
        : stream.label.isNotEmpty
        ? stream.label
        : _resolutionName(stream.resolution, frames60: tier.endsWith('_60')) ??
              qualityNames[tier] ??
              tier.toUpperCase();
    return stream.codec == 'h264' ? base : '$base$h265Suffix';
  }

  /// `720x1280` or `720p` as the site names it (`720p`, `720p60`); null for
  /// no resolution.
  static String? _resolutionName(String resolution, {required bool frames60}) {
    final String lines;
    if (RegExp(r'^[0-9]+p$').hasMatch(resolution)) {
      lines = resolution.substring(0, resolution.length - 1);
    } else if (RegExp(r'^([0-9]+)x([0-9]+)$').firstMatch(resolution) case final match?) {
      final (width, height) = (int.parse(match[1]!), int.parse(match[2]!));
      lines = '${width < height ? width : height}';
    } else {
      return null;
    }
    return '${lines}p${frames60 ? '60' : ''}';
  }

  /// 3.x's rank of the tier (origin 10000 … auto 3000, others 1000), plus
  /// 100 for H.264: best first, H.264 before H.265 within a tier.
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
    return tier + (stream.codec == 'h264' ? 100 : 0);
  }

  /// The quality id for a stored one: 3.x had one quality per protocol
  /// (`<codec>:<tier>:<flv|hls>`, e.g. `h264:origin:flv`), which are now
  /// the lines of `<codec>:<tier>` (22-2); M9 migrates a stored quality
  /// with it once. Any other id is kept (trimmed); applying it twice
  /// changes nothing.
  static String qualityIdFromLegacy(String id) {
    final value = id.trim();
    final match = _legacyQualityId.firstMatch(value);
    return match == null ? value : '${match[1]!.toLowerCase()}:${match[2]!.toLowerCase()}';
  }

  static final RegExp _legacyQualityId = RegExp(r'^(h26[45]):([a-z0-9_]{1,24}):(?:flv|hls)$', caseSensitive: false);

  /// The lines of [quality] in [data] (a 3.x id is read through
  /// [qualityIdFromLegacy]; the applied quality is the current id): FLV
  /// then HLS (22-2), each with the media headers of the room, the
  /// protocol's format, the codec, `flv` or `hls` as the line id (`flv#2`
  /// for a second FLV URL) and the lease of the URL's `expire`. A quality
  /// [data] does not offer is `StreamUnavailable`.
  static LivePlayUrlResolution resolution(TikTokRoomData data, LivePlayQuality quality) {
    final id = qualityIdFromLegacy('${quality.selectionId}');
    final stream = data.streams.where((stream) => stream.id == id).firstOrNull;
    if (stream == null) throw StreamUnavailable(_site, '@${data.username}: quality $id is not offered');
    final headers = mediaHeaders(data.username);
    final codec = stream.codec == 'h264' ? 'avc' : 'hevc';
    return LivePlayUrlResolution.lines([
      for (final (protocol, format, urls) in [
        ('flv', StreamFormat.flv, stream.flvUrls),
        ('hls', StreamFormat.hls, stream.hlsUrls),
      ])
        for (final (index, url) in urls.indexed)
          LivePlayLine(
            '$url',
            headers: headers,
            format: format,
            codec: codec,
            lineId: index == 0 ? protocol : '$protocol#${index + 1}',
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
  /// `flv` and `hls` URLs and `sdk_params` (JSON in a string again); the
  /// container's `pull_data.options.qualities` name the tiers
  /// (`sdk_key` → `name`). The audio-only `ao` is left out; a tier of the
  /// same codec in both containers is one stream.
  ///
  /// A malformed part only loses itself (the unified rule on bad data; 3.x
  /// failed the whole room): a container that does not decode, a tier with
  /// a bad key, `main`, `sdk_params` or codec, one URL that is no string or
  /// not a TikTok media URL ([_mediaUrl]). Each is noted in `skipped`.
  static ({List<TikTokStream> streams, List<String> skipped}) _streams(Map<String, dynamic> live) {
    final builders = <String, _StreamBuilder>{};
    final skipped = <String>[];
    for (final (key, fallback) in const [('streamData', 'h264'), ('hevcStreamData', 'h265')]) {
      final value = live[key];
      if (value == null) continue;
      final Map<String, dynamic> tiers;
      final Map<String, String> labels;
      try {
        final pull = _object(_object(value, 'liveRoom.$key')['pull_data'], '$key.pull_data');
        final raw = _optionalText(pull['stream_data'], '$key.stream_data');
        if (raw.isEmpty || raw.length > 4 * 1024 * 1024) continue;
        tiers = _object(_object(_decode(raw, '$key.stream_data'), '$key.stream_data')['data'], '$key.data');
        if (tiers.length > 32) throw ApiChanged(_site, '$key: ${tiers.length} tiers');
        labels = _labels(pull['options']);
      } on ApiChanged catch (error) {
        skipped.add(error.detail ?? key);
        continue;
      }
      for (final MapEntry(key: rawTier, :value) in tiers.entries) {
        final String tier;
        final String codec;
        final Map<String, dynamic> main;
        final Map<String, dynamic> sdk;
        try {
          tier = _tier(rawTier, key);
          if (tier == 'ao') continue;
          main = _object(_object(value, '$key.$tier')['main'], '$key.$tier.main');
          final sdkRaw = _optionalText(main['sdk_params'], '$key.$tier.sdk_params');
          sdk = sdkRaw.isEmpty
              ? const <String, dynamic>{}
              : _object(_decode(sdkRaw, '$key.$tier.sdk_params'), '$key.$tier.sdk_params');
          codec = _codec(sdk['VCodec'] ?? sdk['v_codec'], fallback, '$key.$tier');
        } on ApiChanged catch (error) {
          skipped.add(error.detail ?? '$key.$rawTier');
          continue;
        }
        for (final protocol in const ['flv', 'hls']) {
          final Uri url;
          try {
            final text = _optionalText(main[protocol], '$key.$tier.$protocol');
            if (text.isEmpty) continue;
            url = _mediaUrl(text, '$key.$tier.$protocol');
          } on ApiChanged catch (error) {
            skipped.add(error.detail ?? '$key.$tier.$protocol');
            continue;
          }
          final id = '$codec:$tier';
          final builder = builders.putIfAbsent(id, () => _StreamBuilder(id: id, tier: tier, codec: codec));
          if (builder.label.isEmpty) builder.label = labels[tier] ?? '';
          if (builder.resolution.isEmpty) builder.resolution = _resolution(sdk['resolution']);
          builder.bitrate ??= _lenientCount(sdk['vbitrate']);
          final urls = protocol == 'flv' ? builder.flv : builder.hls;
          if (!urls.contains(url)) urls.add(url);
        }
      }
    }
    final streams = [
      for (final builder in builders.values)
        TikTokStream(
          id: builder.id,
          qualityId: builder.tier,
          codec: builder.codec,
          label: builder.label,
          resolution: builder.resolution,
          bitrate: builder.bitrate,
          flvUrls: List.unmodifiable(builder.flv),
          hlsUrls: List.unmodifiable(builder.hls),
        ),
    ];
    return (streams: List.unmodifiable(streams), skipped: List.unmodifiable(skipped));
  }

  /// A container's tier names: `options.qualities[]` as `sdk_key` (lower
  /// case) → `name` (trimmed, at most 32 characters). Entries of another
  /// shape are passed over.
  static Map<String, String> _labels(Object? options) {
    final listed = options is Map ? options['qualities'] : null;
    return {
      if (listed is List)
        for (final item in listed)
          if (item is Map)
            if ((item['sdk_key'], item['name']) case (final String key, final String name)
                when key.trim().isNotEmpty && name.trim().isNotEmpty && name.trim().length <= 32)
              key.trim().toLowerCase(): name.trim(),
    };
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
  new({required this.id, required this.tier, required this.codec});

  final String id;
  final String tier;
  final String codec;
  String label = '';
  String resolution = '';
  int? bitrate;
  final List<Uri> flv = [];
  final List<Uri> hls = [];
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

/// An object, or none (empty) for anything else (22-6: `stats` and
/// `liveRoomStats` only fill the card; 3.x failed the answer).
Map<String, dynamic> _lenientObject(Object? value) => value is Map ? _object(value, '') : const <String, dynamic>{};

/// 3.x's `_integer`: an int, an integral number or an integer string.
int? _integer(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.roundToDouble()) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

/// A count of zero or more (3.x's `_optionalNonNegativeInt`), else null
/// (22-6: 3.x failed the answer for a malformed count).
int? _lenientCount(Object? value) => switch (_integer(value)) {
  final int count when count >= 0 => count,
  _ => null,
};

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

/// A long id (see [_longId]), else empty (22-6: 3.x failed the answer for
/// a malformed `id`, `roomId` or `streamId`).
String _lenientLongId(Object? value) {
  final text = value?.toString().trim() ?? '';
  return RegExp(r'^[1-9][0-9]{14,24}$').hasMatch(text) ? text : '';
}

/// A string of at most 8192 characters, trimmed, else empty (22-6: 3.x
/// failed the answer for a blank or malformed `nickname` and a malformed
/// `title`, `signature` or `secUid`).
String _lenientText(Object? value) => value is String && value.length <= 8192 ? value.trim() : '';

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

/// 3.x's `_resolution`: `720x1280` or `720p`, else empty (also for a value
/// that is no string, which 3.x refused).
String _resolution(Object? value) {
  final text = value is String ? value.trim().toLowerCase() : '';
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
