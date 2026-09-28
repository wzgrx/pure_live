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

/// A channel's state as the platform answers it.
enum Fc2LiveState {
  /// `is_publish` 1 and open to anonymous viewers.
  live,

  /// Not broadcasting (`is_publish` other than 1).
  offline,

  /// Broadcasting, but paid, ticketed, for signed-in viewers only or
  /// restricted by FC2 ([Fc2LiveChannel.restriction] says which). The room
  /// is live and marked with the restriction (26-9; 3.x showed it with an
  /// unknown state); playback refuses it with the reason.
  restricted,
}

/// One channel of the directory or of a member answer (3.x's `Fc2Room`).
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
    this.avatar = '',
    this.currentViewers,
    this.totalViewers,
    this.startedAt,
    this.restriction,
    this.isAdult = false,
  });

  /// The channel number, the room id.
  final String channelId;

  /// The owner's name (`name`; `profile_data.name`, else `tname`), HTML
  /// entities decoded (26-4); empty when the platform has none (3.x wrote
  /// the channel number, a placeholder).
  final String userName;

  /// `title`, else [userName], HTML entities decoded (26-4); empty when
  /// both are.
  final String title;

  /// `channel_data.info` (member answers only), HTML entities decoded and
  /// whitespace collapsed.
  final String description;

  /// `image` when it is an https image on `fc2.com` or a subdomain, else
  /// empty.
  final String cover;

  /// The owner's picture (member answers only, 26-5): `profile_data.icon`,
  /// else `profile_data.image`, checked as [cover]; else empty.
  final String avatar;

  /// `category` (0–99).
  final int categoryId;

  /// The area name of [categoryId] ([Fc2LiveApi.areaName]), the same for
  /// cards and details (26-6).
  final String categoryName;

  /// `count`: viewers now.
  final int? currentViewers;

  /// `total`: viewers of this broadcast so far.
  final int? totalViewers;

  /// When the broadcast started (`start_time`, `start`), when on air.
  final DateTime? startedAt;

  /// What keeps viewers out of a broadcast on air: [LiveRestriction.none]
  /// when nothing does; null when offline.
  final LiveRestriction? restriction;

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
  const new({
    required this.channelId,
    required this.state,
    required this.categoryId,
    this.restriction,
    this.isAdult = false,
  });

  /// The channel the data belongs to.
  final String channelId;

  /// Broadcast state.
  final Fc2LiveState state;

  /// `category`: the interface names the area by it (26-6, M13).
  final int categoryId;

  /// The broadcast's restriction ([Fc2LiveChannel.restriction]).
  final LiveRestriction? restriction;

  /// Marked adult by the platform.
  final bool isAdult;
}

/// What the comment connection needs (26-3, M5): the channel. Comments
/// travel on a control socket of their own: the connection takes a grant
/// with `Fc2LiveSite.controlGrant` (again after every
/// `control_disconnection`), connects [Fc2LiveGrant.endpoint] with
/// [Fc2LiveGrant.handshakeHeaders] and reads `comment` and `user_count`
/// messages (archive spec §7).
@immutable
final class Fc2LiveDanmakuArgs {
  /// Creates the arguments.
  const new(this.channelId);

  /// The channel number.
  final String channelId;

  @override
  bool operator ==(Object other) => other is Fc2LiveDanmakuArgs && other.channelId == channelId;

  @override
  int get hashCode => channelId.hashCode;

  @override
  String toString() => 'Fc2LiveDanmakuArgs($channelId)';
}

/// The playlist a control plays and the quality it is (26-2).
typedef Fc2LivePlaylist = ({String quality, Uri url});

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
/// and the quality. There is no URL to export: playback and recording each
/// take a grant, hold its control socket while they play and read the
/// playlist it announces for the quality (`Fc2LiveSite.openControl`; M7,
/// M8).
@immutable
final class Fc2LiveInputRecipe implements LiveInputRecipe {
  /// Creates the recipe of [channelId], a channel number, in [quality], one
  /// of [Fc2LiveApi.qualityIds] (3.x's recipes were all `auto`).
  new(this.channelId, {this.quality = Fc2LiveApi.autoQualityId}) {
    if (!Fc2LiveApi.isChannelId(channelId)) throw ArgumentError.value(channelId, 'channelId', 'not an FC2 channel');
    if (!Fc2LiveApi.qualityIds.contains(quality)) throw ArgumentError.value(quality, 'quality', 'not an FC2 quality');
  }

  /// The channel number.
  final String channelId;

  /// The quality id: a tier (`50`, `40`, `30`, `20`, `10`, 26-2) or
  /// `auto`.
  final String quality;

  /// `fc2live:<channel>:<quality>` (3.x's `fc2live:<channel>:auto`).
  @override
  String get identity => 'fc2live:$channelId:$quality';

  @override
  bool operator ==(Object other) => other is Fc2LiveInputRecipe && other.identity == identity;

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

  /// Id of [autoQuality].
  static const String autoQualityId = 'auto';

  /// 3.x's one quality: the site's adaptive HLS master (label from its
  /// zh.json `fc2live_quality_auto`). Kept, after the tiers (26-2): id and
  /// label are 3.x's.
  static const LivePlayQuality autoQuality = LivePlayQuality(id: autoQualityId, quality: '自适应 HLS');

  /// The tiers of 26-2, best first. The id is the tier's playlist mode in
  /// the control's HLS answer; the site transcodes every tier, none is the
  /// source. The labels follow the site's player (`mode10`…`mode50`):
  /// - `50` 3 Mbps (β) and `40` 2 Mbps, offered only for some channels
  ///   (a 1080p broadcast in control/S07-control-hd): 超清 with the rate;
  /// - `30` 1.2 Mbps, `20` 400 Kbps and `10` 150 Kbps, offered for every
  ///   channel recorded: the shared names of high, standard and low
  ///   (`LiveQualityLabel`).
  static const List<LivePlayQuality> tierQualities = [
    LivePlayQuality(id: '50', quality: '超清 3M（β）', sort: 50),
    LivePlayQuality(id: '40', quality: '超清 2M', sort: 40),
    LivePlayQuality(id: '30', quality: '高清', sort: 30),
    LivePlayQuality(id: '20', quality: '标清', sort: 20),
    LivePlayQuality(id: '10', quality: '流畅', sort: 10),
  ];

  /// The playlist modes of [tierQualities], best first.
  static const List<int> tierModes = [50, 40, 30, 20, 10];

  /// Every quality a live room can have, in menu order (26-2): the tiers,
  /// best first, then [autoQuality]. A room lists those its channel offers
  /// ([qualitiesOf]).
  static const List<LivePlayQuality> qualities = [...tierQualities, autoQuality];

  /// The ids of [qualities]. 3.x's one id, `auto`, is unchanged, so stored
  /// quality ids need no mapping (M9).
  static const Set<String> qualityIds = {'50', '40', '30', '20', '10', autoQualityId};

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

  /// The area name of a room in [category] (26-6): the name of the catalog
  /// area that holds it ([areaNames], 3.x's zh.json), for cards and details
  /// alike; the interface shows its own translation by
  /// [Fc2LiveRoomData.categoryId] (M13). 3.x named cards in English and
  /// details in the site's Japanese (`雑談`). Categories outside the catalog
  /// (0 and 8 are the site's "unknown", 6 premium, 7 official) have no name.
  static String areaName(int category) => switch (category) {
    1 || 4 || 5 || 9 => areaNames['$category']!,
    2 || 3 => areaNames['2']!,
    _ => '',
  };

  /// The English area name 3.x gave directory cards; the keyword search
  /// still matches it, so 3.x's searches find the same rooms.
  static String legacyAreaName(int category) => switch (category) {
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
  /// skipped; restricted rooms (`pay`, `login` or `tid` not 0) stay, live
  /// and marked ([directoryRestriction], 26-9); a channel listed twice is
  /// kept once. The list must be there: `time` a positive integer and at
  /// most 1000 rows (3.x's checks, `ApiChanged`). A row that cannot be read
  /// (not an object, no integer `type`; a public row without a channel
  /// number, integer `pay`, `login`, `tid` or a `category` 0–99, or with a
  /// name, title or count of the wrong type) is skipped alone (26-7; 3.x
  /// failed the whole list); unreadable rows without a single readable
  /// public one are `ApiChanged`, so a changed API never looks like an
  /// empty directory.
  static List<Fc2LiveChannel> directory(String body, {int status = 200}) {
    final root = _json(body, status, 'allchannellist');
    if (_int(root['time'], 'allchannellist time') < 1) throw const ApiChanged(_site, 'allchannellist: time');
    final rows = root['channel'];
    if (rows is! List || rows.length > 1000) throw const ApiChanged(_site, 'allchannellist: no channel list');
    final seen = <String>{};
    final channels = <Fc2LiveChannel>[];
    var unreadable = 0;
    for (final row in rows) {
      final Fc2LiveChannel channel;
      try {
        final data = _object(row, 'allchannellist row');
        // Open chat and private two-shot entries are not public media rooms.
        if (_int(data['type'], 'allchannellist type') != 1) continue;
        channel = _directoryChannel(data);
      } on ApiChanged {
        unreadable++;
        continue;
      }
      if (seen.add(channel.channelId)) channels.add(channel);
    }
    if (channels.isEmpty && unreadable > 0) {
      throw ApiChanged(_site, 'allchannellist: none of $unreadable rows can be read');
    }
    return List.unmodifiable(channels);
  }

  static Fc2LiveChannel _directoryChannel(Map<String, dynamic> data) {
    final id = _channelNumber(data['id'], 'allchannellist id');
    final restriction = directoryRestriction(
      pay: _int(data['pay'], 'allchannellist pay'),
      ticket: _int(data['tid'], 'allchannellist tid'),
      login: _int(data['login'], 'allchannellist login'),
    );
    final category = _category(data['category'], 'allchannellist');
    final name = _displayText(data['name'], 'allchannellist name');
    return Fc2LiveChannel(
      channelId: id,
      userName: name,
      title: _firstOptional([_displayText(data['title'], 'allchannellist title'), name], 'allchannellist title'),
      cover: _image(data['image']),
      categoryId: category,
      categoryName: areaName(category),
      currentViewers: _count(data['count'], 'allchannellist count'),
      totalViewers: _count(data['total'], 'allchannellist total'),
      startedAt: startTime(data['start_time']),
      restriction: restriction,
      state: restriction == LiveRestriction.none ? Fc2LiveState.live : Fc2LiveState.restricted,
    );
  }

  /// The restriction of a directory row (26-9), by the site's card marks
  /// in their order: `pay` 1 (pay per minute in points) and `tid` (a
  /// ticket or premium broadcast) are [LiveRestriction.paid]; `login` 1
  /// (for signed-in viewers) and 2 (for signed-in viewers holding points,
  /// free to watch) are [LiveRestriction.needsLogin]; all 0 is
  /// [LiveRestriction.none].
  static LiveRestriction directoryRestriction({required int pay, required int ticket, required int login}) {
    if (pay != 0 || ticket != 0) return LiveRestriction.paid;
    if (login != 0) return LiveRestriction.needsLogin;
    return LiveRestriction.none;
  }

  /// The restriction of a live member answer (26-9): `is_limited`
  /// (the site shows "配信規制中", its broadcast is restricted by FC2, and
  /// sends every viewer out) is [LiveRestriction.unplayable]; `fee` (pay
  /// per minute), `ticketid` and `ticket_only` are [LiveRestriction.paid];
  /// `login_only` (1 signed-in viewers, 2 those holding points, as the
  /// directory's `login`) is [LiveRestriction.needsLogin]; all 0 is
  /// [LiveRestriction.none].
  static LiveRestriction memberRestriction({
    required int limited,
    required int fee,
    required int ticketId,
    required int ticketOnly,
    required int loginOnly,
  }) {
    if (limited != 0) return LiveRestriction.unplayable;
    if (fee != 0 || ticketId != 0 || ticketOnly != 0) return LiveRestriction.paid;
    if (loginOnly != 0) return LiveRestriction.needsLogin;
    return LiveRestriction.none;
  }

  /// The error that refuses to play a broadcast with [restriction]
  /// (M2.1's table), or null when nothing does: [LiveRestriction.needsLogin]
  /// is `NeedsLogin` (this app has no FC2 account), the others are
  /// `StreamUnavailable` with the reason.
  static SiteError? refusal(LiveRestriction? restriction, String channelId) => switch (restriction) {
    null || LiveRestriction.none => null,
    LiveRestriction.needsLogin => NeedsLogin(_site, 'channel $channelId is for signed-in viewers only'),
    LiveRestriction.paid => StreamUnavailable(_site, 'channel $channelId is a paid or ticketed broadcast'),
    LiveRestriction.unplayable => StreamUnavailable(_site, 'channel $channelId is restricted by FC2 (配信規制中)'),
    final LiveRestriction other => StreamUnavailable(_site, 'channel $channelId is restricted (${other.name})'),
  };

  /// A start time in Unix milliseconds (`start_time`, `start`) as UTC; null
  /// for 0, anything before 2000 or after 2100, and anything that is not
  /// an integer.
  static DateTime? startTime(Object? value) {
    final milliseconds = jsonInt(value);
    if (milliseconds == null || milliseconds < 946684800000 || milliseconds > 4102444800000) return null;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
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

  /// The channels whose number, name, title or area name (the room's, or
  /// 3.x's English one, [legacyAreaName]) contains [keyword] (trimmed, case
  /// ignored), in the directory's order (3.x's local search; the site has
  /// no search API). Names and titles are matched as shown, with HTML
  /// entities decoded (26-4).
  static List<Fc2LiveChannel> search(List<Fc2LiveChannel> channels, String keyword) {
    final query = keyword.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return [
      for (final channel in channels)
        if (channel.channelId.contains(query) ||
            channel.userName.toLowerCase().contains(query) ||
            channel.title.toLowerCase().contains(query) ||
            (channel.categoryName.isNotEmpty &&
                (channel.categoryName.toLowerCase().contains(query) ||
                    legacyAreaName(channel.categoryId).toLowerCase().contains(query))))
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
  /// of the five restriction flags is restricted ([memberRestriction]),
  /// still live (26-9). `version` is kept for the control grant: 3.x
  /// required it, but the site answers `''` for every channel that is not
  /// on air (S02-member-offline), so 3.x failed on every offline channel.
  /// A live channel carries its start time (`start`) and restriction; the
  /// owner's picture ([Fc2LiveChannel.avatar]) is read leniently, a field
  /// 3.x did not read never fails the answer.
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
    int flag(String key) => _int(channel[key], 'memberApi $key');
    final restriction = memberRestriction(
      limited: flag('is_limited'),
      fee: flag('fee'),
      ticketId: flag('ticketid'),
      ticketOnly: flag('ticket_only'),
      loginOnly: flag('login_only'),
    );
    final category = _category(channel['category'], 'memberApi');
    final version = _optionalText(channel['version'], 'memberApi version');
    if (version.length > 256) throw const ApiChanged(_site, 'memberApi: version over 256 characters');
    final name = _firstOptional([
      _displayText(profile?['name'], 'memberApi name'),
      _displayText(channel['tname'], 'memberApi tname'),
    ], 'memberApi name');
    return (
      channel: Fc2LiveChannel(
        channelId: id,
        userName: name,
        title: _firstOptional([_displayText(channel['title'], 'memberApi title'), name], 'memberApi title'),
        description: _displayText(channel['info'], 'memberApi info'),
        cover: _image(channel['image']),
        avatar: _firstOptional([_lenientImage(profile?['icon']), _lenientImage(profile?['image'])], 'avatar'),
        categoryId: category,
        categoryName: areaName(category),
        currentViewers: _count(channel['count'], 'memberApi count'),
        totalViewers: _count(channel['total'], 'memberApi total'),
        startedAt: published ? startTime(channel['start']) : null,
        restriction: published ? restriction : null,
        state: !published
            ? Fc2LiveState.offline
            : restriction != LiveRestriction.none
            ? Fc2LiveState.restricted
            : Fc2LiveState.live,
        isAdult: _int(channel['adult'], 'memberApi adult') == 1,
      ),
      version: version.isEmpty ? null : version,
    );
  }

  // Rooms ---------------------------------------------------------------------

  /// The room of [channel] (3.x's `Fc2Site._room`): live (restricted ones
  /// too, marked with their restriction, 26-9; 3.x showed them unknown) or
  /// offline; viewers now as the audience and the broadcast's total as
  /// `totalViewers`, both only while on air (26-8; 3.x wrote an offline
  /// channel's 0); the start time while on air; the owner's picture as the
  /// avatar, else the cover (26-5; 3.x always the cover); the link is the
  /// channel page; 3.x's notice ([notice]); the introduction from a member
  /// answer's `info` (3.x parsed it but left it out); [Fc2LiveRoomData]
  /// for the interface and the streams; with [danmaku] (room entry and
  /// recording) the comment arguments (26-3, M5). No `httpHeaders`: that
  /// field is IPTV's, the media headers travel with the control session.
  static LiveRoom room(Fc2LiveChannel channel, {bool danmaku = false}) {
    final live = channel.state != Fc2LiveState.offline;
    final viewers = live ? channel.currentViewers?.toString() : null;
    return LiveRoom(
      platform: _site,
      roomId: channel.channelId,
      userId: channel.channelId,
      title: channel.title,
      nick: channel.userName,
      avatar: channel.avatar.isEmpty ? channel.cover : channel.avatar,
      cover: channel.cover,
      area: channel.categoryName,
      link: channelUrl(channel.channelId),
      liveStatus: live ? LiveStatus.live : LiveStatus.offline,
      watching: viewers ?? '',
      onlineViewers: viewers ?? '',
      totalViewers: (live ? channel.totalViewers?.toString() : null) ?? '',
      audienceMetricType: channel.currentViewers == null
          ? AudienceMetricType.unknown
          : AudienceMetricType.onlineViewers,
      notice: notice(channel),
      introduction: channel.description.isEmpty ? null : channel.description,
      startedAt: live ? channel.startedAt : null,
      restriction: live ? channel.restriction : null,
      danmakuData: danmaku ? Fc2LiveDanmakuArgs(channel.channelId) : null,
      data: Fc2LiveRoomData(
        channelId: channel.channelId,
        state: channel.state,
        categoryId: channel.categoryId,
        restriction: live ? channel.restriction : null,
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

  /// The playlist families of the control's HLS answer: low latency (the
  /// one 3.x read, modes 0, 10, 20, 30, 90), high latency (mode + 1) and
  /// middle latency (mode + 2).
  static const List<String> playlistFamilies = ['playlists', 'playlists_high_latency', 'playlists_middle_latency'];

  /// The control socket's `get_hls_information` answer (3.x's
  /// `Fc2ControlSession.parseHlsResponse`): every playlist of
  /// [playlistFamilies] by mode (26-2). A mode below 10 is a family's
  /// master (0 is the low-latency master 3.x played), the others are single
  /// variants (`<tier>` + the family's offset; 90 is sound only).
  ///
  /// `arguments.status` other than 0 is `StreamUnavailable`; rows whose
  /// `status` is not 0 are skipped. A playlist must be https on
  /// `live.fc2.com` or a subdomain, without user info or fragment, at
  /// `/a/stream/<channelId>/<mode>/master_playlist` (a master) or
  /// `/a/stream/<channelId>/<mode>/playlist` (a variant), with exactly the
  /// query parameters `c`, `d` (1–1024 characters) and, for a master only,
  /// `targets` (up to 16 numbers of 1–3 digits). A row or a family that
  /// breaks these rules is skipped alone (3.x's checks, which failed the
  /// whole answer, now only make that playlist unavailable); a wrong
  /// message or an answer without a usable playlist is `ApiChanged`.
  static Map<int, Uri> hlsPlaylists(Map<String, dynamic> response, {required String channelId}) {
    if (response['name'] != '_response_' || response['id'] != 1) {
      throw const ApiChanged(_site, 'control: not the answer to get_hls_information');
    }
    final arguments = _object(response['arguments'], 'control arguments');
    final result = _integer(arguments['status'], 'control status');
    if (result != 0) throw StreamUnavailable(_site, 'get_hls_information: status $result');
    final found = <int, Uri>{};
    for (final family in playlistFamilies) {
      final rows = arguments[family];
      if (rows is! List || rows.length > 32) continue;
      for (final row in rows) {
        if (row is! Map) continue;
        final mode = jsonInt(row['mode']);
        if (mode == null || mode < 0 || mode > 999 || jsonInt(row['status']) != 0) continue;
        final uri = _playlist(row['url'], channelId: channelId, mode: mode);
        if (uri != null) found.putIfAbsent(mode, () => uri);
      }
    }
    if (found.isEmpty) throw const ApiChanged(_site, 'control: no playlist');
    return Map.unmodifiable(found);
  }

  static Uri? _playlist(Object? url, {required String channelId, required int mode}) {
    if (url is! String || url.isEmpty || url.length > 65536) return null;
    final uri = Uri.tryParse(url);
    final master = mode < 10;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        !_isFc2Live(uri.host) ||
        uri.path != '/a/stream/$channelId/$mode/${master ? 'master_playlist' : 'playlist'}' ||
        uri.hasFragment) {
      return null;
    }
    final Map<String, String> query;
    try {
      query = uri.queryParameters;
    } on FormatException {
      return null;
    }
    final keys = master ? const {'targets', 'c', 'd'} : const {'c', 'd'};
    if (!_mediaToken(query['c']) ||
        !_mediaToken(query['d']) ||
        (master && !_targets(query['targets'])) ||
        query.keys.any((key) => !keys.contains(key))) {
      return null;
    }
    return uri;
  }

  /// The qualities a channel offers by its HLS answer's [playlists]
  /// ([hlsPlaylists]), in menu order (26-2): each tier with a variant in
  /// any family (so `50` and `40` only for the channels that have them),
  /// then [autoQuality] when a master is there. Empty when the answer has
  /// neither (sound only).
  static List<LivePlayQuality> qualitiesOf(Map<int, Uri> playlists) => [
    for (final quality in tierQualities)
      if ([0, 1, 2].any((offset) => playlists.containsKey(int.parse('${quality.id}') + offset))) quality,
    if ([0, 1, 2].any(playlists.containsKey)) autoQuality,
  ];

  /// The low-latency master (mode 0) of the HLS answer, the one 3.x played
  /// (see [hlsPlaylists]); an answer without it is `ApiChanged`.
  static Uri hlsMaster(Map<String, dynamic> response, {required String channelId}) =>
      hlsPlaylists(response, channelId: channelId)[0] ?? (throw const ApiChanged(_site, 'control: no master playlist'));

  /// The playlist to play for [quality] among [playlists] (26-2), or null
  /// when there is none:
  /// - a tier plays a single variant: its high-latency one (mode + 1; the
  ///   archived v4 found that ffmpeg reading a master fetches every variant
  ///   and stalls, and long segments suit the relay), else its low-latency
  ///   one, else its middle-latency one. A tier the channel does not offer
  ///   falls back to the next lower tier, then the next higher, then to a
  ///   master; the result names the quality that plays;
  /// - `auto` plays the low-latency master (3.x), else the high- or
  ///   middle-latency master, else the best tier.
  static Fc2LivePlaylist? playlistFor(Map<int, Uri> playlists, String quality) {
    Fc2LivePlaylist? tier(int mode) {
      for (final offset in const [1, 0, 2]) {
        if (playlists[mode + offset] case final url?) return (quality: '$mode', url: url);
      }
      return null;
    }

    Fc2LivePlaylist? master() {
      for (final mode in const [0, 1, 2]) {
        if (playlists[mode] case final url?) return (quality: autoQualityId, url: url);
      }
      return null;
    }

    if (quality == autoQualityId) return master() ?? tierModes.map(tier).nonNulls.firstOrNull;
    final requested = int.tryParse(quality);
    if (requested == null || !tierModes.contains(requested) || '$requested' != quality) return null;
    final lower = tierModes.where((mode) => mode < requested);
    final higher = tierModes.reversed.where((mode) => mode > requested);
    return [requested, ...lower, ...higher].map(tier).nonNulls.firstOrNull ?? master();
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

  /// A name, title or introduction as shown: [_optionalText] with HTML
  /// entities decoded (26-4; the site's own pages decode them), whitespace
  /// collapsed again afterwards.
  static String _displayText(Object? value, String what) {
    final text = _optionalText(value, what);
    return text.contains('&') ? _optionalText(decodeHtmlEntities(text), what) : text;
  }

  /// [_image] of a field 3.x never read: anything it would refuse is no
  /// image, never a failure.
  static String _lenientImage(Object? value) {
    try {
      return _image(value);
    } on ApiChanged {
      return '';
    }
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
