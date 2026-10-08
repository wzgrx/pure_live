import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:live_core/src/aes.dart';
import 'package:live_core/src/audience.dart';
import 'package:live_core/src/input_recipe.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'bigo';

/// Who may watch a studio anonymously (3.x's `BigoAccess`).
enum BigoAccess {
  /// Anyone with the web token, as far as the answer says (a later use of a
  /// token does not say whether the room has a password, see
  /// [BigoStudio.complete]).
  public,

  /// `needLogin`: checked before everything else, as the official player
  /// does. The anonymous web token normally clears it; the site also sends
  /// it when it turns a token away (24-4, see `BigoSite`).
  loginRequired,

  /// `passRoom` (a password) or `isPaidShow` `"1"` (a paid show).
  restricted,
}

/// What a room detail carries besides 3.x's fields: the studio's identity
/// and access, for the stream checks and for the interface to show the
/// notice in its own language (M13). Holds no media address: every
/// playback and recording asks the studio again ([BigoInputRecipe]).
@immutable
final class BigoRoomData {
  /// Creates the data.
  const new({
    required this.siteId,
    required this.ownerId,
    required this.access,
    this.alive,
    this.broadcastId,
    this.hasStream = false,
    this.complete = true,
    this.restriction,
  });

  /// `clientBigoId`: the room's identity.
  final String siteId;

  /// `uid`: the streamer's account.
  final int ownerId;

  /// Who may watch.
  final BigoAccess access;

  /// Whether the studio is live, or null when the answer hides it (see
  /// [BigoStudio.alive]).
  final bool? alive;

  /// `roomId`: the streamer's int64 room id as written (the same for every
  /// broadcast: 7232856282170115001 in the list of 2026-09-27 and the
  /// studio of 2026-09-28); null when the answer gives none (`"0"`, offline
  /// or gated). For the chat (M5).
  final String? broadcastId;

  /// Whether the studio gave its media playlist (`hls_src`).
  final bool hasStream;

  /// Whether the answer was a token's first use, which says whether the
  /// room has a password and gives the playlist when there is one (see
  /// [BigoStudio.complete]).
  final bool complete;

  /// The restriction of the answer (see [BigoStudio.restriction]).
  final LiveRestriction? restriction;

  /// Why this studio's stream cannot be played, or null: a login gate is
  /// `NeedsLogin`; a password or paid room (named), an offline one or a
  /// live one whose complete answer gave no playlist are
  /// `StreamUnavailable`. A live answer that says nothing about the lock
  /// (a refresh, 24-4) is let through: the input asks the studio again.
  SiteError? get streamError => switch (access) {
    BigoAccess.loginRequired => NeedsLogin(_site, '$siteId: needLogin'),
    BigoAccess.restricted => StreamUnavailable(
      _site,
      '$siteId: ${restriction == LiveRestriction.paid ? 'paid show' : 'password room'}',
    ),
    BigoAccess.public when alive != true => StreamUnavailable(_site, '$siteId is offline'),
    BigoAccess.public when complete && !hasStream => StreamUnavailable(_site, '$siteId: live without hls_src'),
    BigoAccess.public => null,
  };
}

/// One `getInternalStudioInfo` answer as 3.x read it (its `BigoStudioRoom`
/// and `BigoStudioStatus`).
@immutable
final class BigoStudio {
  /// Creates the answer.
  const new({
    required this.requestedSiteId,
    required this.siteId,
    required this.ownerId,
    required this.access,
    required this.roomStatus,
    required this.roomType,
    this.alive,
    this.broadcastId,
    this.nickname = '',
    this.title = '',
    this.category = '',
    this.avatar = '',
    this.snapshot = '',
    this.hls,
    this.password,
    this.paid = false,
    this.complete = true,
  });

  /// The Bigo id the studio was asked for (a numeric id or the streamer's
  /// chosen one).
  final String requestedSiteId;

  /// `clientBigoId`: the id as the site writes it, the room's identity
  /// whatever it was asked for by (3.x).
  final String siteId;

  /// `uid`.
  final int ownerId;

  /// Who may watch.
  final BigoAccess access;

  /// `alive`, or null when it is no observation: a login gate zeroes the
  /// answer (3.x), and a password or paid room's `alive: 0` is not taken as
  /// offline (3.x). A password or paid room that says `alive: 1` is live
  /// (the unified rule: a restricted broadcast is still live).
  final bool? alive;

  /// `roomStatus`.
  final int roomStatus;

  /// `roomType`.
  final String roomType;

  /// `roomId`: the streamer's room id, or null (see
  /// [BigoRoomData.broadcastId]).
  final String? broadcastId;

  /// `nick_name`.
  final String nickname;

  /// `roomTopic`.
  final String title;

  /// `gameTitle`.
  final String category;

  /// `avatar`; '' when there is none.
  final String avatar;

  /// `snapshot`: the broadcast's screenshot (the last one when offline);
  /// '' when there is none (24-1).
  final String snapshot;

  /// `hls_src`: the media playlist, given only for a public live studio and
  /// only on a token's first use.
  final Uri? hls;

  /// `passRoom`; null when the answer does not say (a token's later use).
  final bool? password;

  /// `isPaidShow` is `"1"`.
  final bool paid;

  /// Whether this is a token's first use (`passRoom` given): only such an
  /// answer says whether the room has a password and gives the playlist.
  /// Every later use of the same token (a minute or hours later, sample
  /// S03-studio-reused), and a login-gated answer completed by one, leaves
  /// out `passRoom` and `hls_src` but still gives the state, names and
  /// pictures (24-4).
  final bool complete;

  /// The state: live when `alive` says so, whatever the access (a restricted
  /// live room is live, M2.1); offline when a public studio says not alive;
  /// unknown when the answer hides it (a login gate, or a password or paid
  /// room not alive, as 3.x). A complete public answer that is alive
  /// without a playlist is live and [LiveRestriction.unplayable] (3.x:
  /// unknown).
  LiveStatus get liveStatus => switch (alive) {
    true => LiveStatus.live,
    false => LiveStatus.offline,
    null => LiveStatus.unknown,
  };

  /// What keeps a viewer out: `needsLogin` behind the login gate,
  /// `password` or `paid` for a restricted room, `none` for a complete
  /// public live answer with a playlist and `unplayable` without one. Null
  /// when the answer cannot tell (offline, or a token's later use that is
  /// neither gated nor paid).
  LiveRestriction? get restriction => switch (access) {
    BigoAccess.loginRequired => LiveRestriction.needsLogin,
    BigoAccess.restricted => (password ?? false) ? LiveRestriction.password : LiveRestriction.paid,
    BigoAccess.public when alive != true || !complete => null,
    BigoAccess.public => hls == null ? LiveRestriction.unplayable : LiveRestriction.none,
  };

  /// This answer (a token's later use) behind the login gate that a first
  /// use of the same token reported: the gate stays, the state is this
  /// answer's (24-4).
  BigoStudio gated() => BigoStudio(
    requestedSiteId: requestedSiteId,
    siteId: siteId,
    ownerId: ownerId,
    access: BigoAccess.loginRequired,
    roomStatus: roomStatus,
    roomType: roomType,
    alive: alive,
    broadcastId: broadcastId,
    nickname: nickname,
    title: title,
    category: category,
    avatar: avatar,
    snapshot: snapshot,
    password: password,
    paid: paid,
    complete: false,
  );

  /// The room data of this answer.
  BigoRoomData get data => BigoRoomData(
    siteId: siteId,
    ownerId: ownerId,
    access: access,
    alive: alive,
    broadcastId: broadcastId,
    hasStream: hls != null,
    complete: complete,
    restriction: restriction,
  );
}

/// What a chat connection needs to join one Bigo studio's chat (24-3, M5.20):
/// the room the website's chat socket enters (`roomId`) and the streamer
/// whose audience it asks for (`uid`), both from the studio answer.
///
/// 3.x had no Bigo chat (`EmptyDanmaku`). Room entry and recording details
/// of a studio the website would open its chat for hand these over in
/// `danmakuData` ([BigoApi.danmakuArgs]), without a request; the connection
/// itself is the danmaku module's.
@immutable
final class BigoDanmakuArgs {
  /// Creates the arguments.
  const new({required this.siteId, required this.ownerId, required this.roomId});

  /// `clientBigoId`: the room's identity.
  final String siteId;

  /// `uid`: the streamer's account.
  final int ownerId;

  /// `roomId`: the streamer's int64 room id, as written.
  final String roomId;

  @override
  String toString() => 'BigoDanmakuArgs($siteId, $ownerId, $roomId)';
}

/// The public recipe of a Bigo input (3.x's `BigoInputRecipe`): the room's
/// Bigo id. There is no URL to export: playback and recording each ask the
/// studio for a fresh web token and playlist (`BigoSite.resolveInput`) and
/// restore the scrambled segments on the way ([BigoHlsProtection]; M7, M8).
@immutable
final class BigoInputRecipe implements LiveInputRecipe {
  /// Creates the recipe; [siteId] must be a Bigo id.
  new(this.siteId) {
    if (!BigoApi.isSiteId(siteId)) throw ArgumentError.value(siteId, 'siteId', 'not a Bigo id');
  }

  /// The room's Bigo id.
  final String siteId;

  @override
  String get identity => 'bigo:$siteId:live';

  @override
  bool operator ==(Object other) => other is BigoInputRecipe && other.identity == identity;

  @override
  int get hashCode => identity.hashCode;

  @override
  String toString() => 'BigoInputRecipe($identity)';
}

/// Pure parsing of Bigo Live answers (3.x's `BigoApi`, `BigoTokenCodec`,
/// `BigoLink` and the models of its `BigoSite`). Each function takes the
/// answer and its status and returns 3.x's models or throws a `SiteError`.
abstract final class BigoApi {
  /// The website.
  static const String webOrigin = 'https://www.bigo.tv';

  /// The desktop browser user agent of [headers] and the chat handshake.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

  /// The headers of every request and of the media (3.x's
  /// `PlaybackHeaderResolver` and HLS input sent the requests' headers to
  /// the media too): a full desktop browser fingerprint (E03.19, upstream
  /// pure_live 2e84d68d3). 3.x sent a bare `Mozilla/5.0`, which the site's
  /// firewall answered on 2026-10-06 (upstream's egress) with a 418 on the
  /// `www.bigo.tv` API and a `needLogin` shell from `getInternalStudioInfo`.
  /// The patrol of 2026-10-08 (through the proxy) got full answers and
  /// segments with both, so this is a precaution, not a repair.
  static const Map<String, String> headers = {
    'origin': webOrigin,
    'referer': '$webOrigin/',
    'user-agent': userAgent,
    'accept': 'application/json, text/javascript, */*; q=0.01',
    'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'x-requested-with': 'XMLHttpRequest',
  };

  /// The largest answer 3.x accepted, in UTF-8 bytes.
  static const int responseLimit = 1024 * 1024;

  /// The platform's name: the category, the area's type and the cards' area.
  static const String siteName = 'Bigo Live';

  /// `areaType` of the one area.
  static const String areaType = 'public';

  /// `areaId` of the one area: the public list `vedioList/72`.
  static const String areaId = '72';

  /// The one area's name (3.x's zh.json `bigo_category_public`; the
  /// interface translates it by id, M13).
  static const String areaName = '公开推荐';

  /// Rooms per native directory page (3.x).
  static const int directoryPageSize = 20;

  /// Largest slice 3.x served; a larger page size gives nothing.
  static const int maxPageSize = 100;

  /// The notice of a public room (the text of 3.x's key `bigo_chat_notice`,
  /// said for viewers: 3.x wrote "Bigo Live 远端聊天尚待接入；目录 user_count
  /// 仅作为当前直播在线人数，房间详情缺值时保持未知。"). Chat is shown since
  /// M5.20, whose connection also reports the room's viewers.
  static const String chatNotice = '列表里的人数是正在观看的人数；进入直播间后，人数随弹幕更新。';

  /// The notice of a login-gated room (`bigo_login_required`; 3.x: "该房间
  /// 当前要求登录，直播状态与媒体保持未知。", no longer true now that the state
  /// is read again, 24-4).
  static const String loginNotice = 'Bigo Live 现在要求登录才能观看这个直播间，暂时不能在这里播放。';

  /// The notice of a password or paid room (`bigo_access_restricted`; 3.x:
  /// "该房间受密码或付费访问限制，直播状态与媒体保持未知。", no longer true now
  /// that such a room shows live, 24-2).
  static const String restrictedNotice = '这个直播间设置了密码或付费观看，暂时不能在这里播放。';

  /// Id of the one quality.
  static const String qualityId = 'live';

  /// The one quality (3.x: `live`, zh.json `bigo_quality_live`).
  static const LivePlayQuality quality = LivePlayQuality(quality: '直播自动', id: qualityId);

  /// The one area.
  static const LiveArea area = LiveArea(
    platform: _site,
    areaType: areaType,
    typeName: siteName,
    areaId: areaId,
    areaName: areaName,
  );

  /// First path segments of `bigo.tv` that are pages, not rooms (3.x).
  static const Set<String> reservedPaths = {'about', 'download', 'index', 'live', 'login', 'search', 'signup'};

  static final RegExp _siteId = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_.-]{0,63}$');
  static final RegExp _digits = RegExp(r'^[0-9]{1,20}$');
  static final RegExp _callback = RegExp(r'^jsonp[A-Za-z0-9_]{1,96}$');

  /// Whether [value] is a Bigo id: a numeric id or one the streamer chose
  /// (`414439909`, `qashia305`).
  static bool isSiteId(String value) => _siteId.hasMatch(value);

  /// The room page of [siteId].
  static String link(String siteId) => '$webOrigin/$siteId';

  // Catalog -------------------------------------------------------------------

  /// 3.x's one category `Bigo Live` with the one area.
  static List<LiveCategory> categories() => [
    LiveCategory(id: _site, name: siteName, children: const [area]),
  ];

  /// Whether [category] is the one area.
  static bool isArea(LiveArea category) =>
      category.platform == _site && category.areaType == areaType && category.areaId == areaId;

  /// `OInterfaceWeb/vedioList/72`: the public list (a finite snapshot of
  /// about 20 live rooms, whatever `fetchNum` asks). A row 3.x would not
  /// read (see [_card]), and a later row repeating a Bigo id or an owner,
  /// is left out on its own (24-6: 3.x failed the whole list). The answer's
  /// envelope is still checked as 3.x did, and rows none of which can be
  /// read are `ApiChanged`, so a changed API never shows as an empty list.
  /// Locked rooms stay listed, live and marked [LiveRestriction.password]
  /// (24-2; the discovery page hides them, M13).
  static List<LiveRoom> directory(String body, {int status = 200}) {
    final data = _success(body, status: status, what: 'vedioList');
    final code = data['resCode'];
    if (code is! String) throw ApiChanged(_site, 'vedioList: resCode is $code');
    if (code != '0') throw ApiChanged(_site, 'vedioList: resCode $code');
    final rows = data['data'];
    if (rows is! List || rows.length > 500) {
      throw ApiChanged(_site, 'vedioList: data is ${rows is List ? '${rows.length} rows' : 'not a list'}');
    }
    final ids = <String>{};
    final owners = <String?>{};
    final cards = <LiveRoom>[];
    for (final row in rows) {
      final LiveRoom card;
      try {
        card = _card(_object(row, 'vedioList row'));
      } on ApiChanged {
        continue;
      }
      if (ids.add(card.roomId) && owners.add(card.userId)) cards.add(card);
    }
    if (rows.isNotEmpty && cards.isEmpty) throw ApiChanged(_site, 'vedioList: none of ${rows.length} rows is readable');
    return List.unmodifiable(cards);
  }

  /// A card of the list (3.x's `parseDirectory` and `_card`), checked as
  /// 3.x did (`ApiChanged` for an irregular field): the topic as title, else
  /// the name; the cover as avatar too; `user_count` as concurrent viewers;
  /// the chat notice and 3.x's headers. `time_stamp` is the broadcast's
  /// start ([startedAt]); `is_locked` gives the restriction.
  static LiveRoom _card(Map<String, dynamic> row) {
    final siteId = _bigoId(row['bigo_id'], 'bigo_id');
    final owner = _owner(row['owner'], 'owner of $siteId');
    final broadcast = row['room_id'];
    if (broadcast is! int || broadcast < 1) throw ApiChanged(_site, 'vedioList: room_id of $siteId is $broadcast');
    _owner(row['sid'], 'sid of $siteId');
    final topic = _text(row['room_topic'], 'room_topic of $siteId');
    final nickname = _text(row['nick_name'], 'nick_name of $siteId');
    final cover = row['cover_m'] == null ? '' : normalizeImageUrl(_text(row['cover_m'], 'cover_m of $siteId'));
    final viewers = row['user_count'] == null ? '' : '${_count(row['user_count'], 'user_count of $siteId')}';
    final locked = _binary(row['is_locked'], 'is_locked of $siteId');
    _count(row['room_flag'], 'room_flag of $siteId');
    return LiveRoom(
      roomId: siteId,
      platform: _site,
      userId: '$owner',
      link: link(siteId),
      title: topic.isEmpty ? nickname : topic,
      nick: nickname,
      avatar: cover,
      cover: cover,
      area: siteName,
      watching: viewers,
      onlineViewers: viewers,
      audienceMetricType: AudienceMetricType.onlineViewers,
      liveStatus: LiveStatus.live,
      startedAt: startedAt(row['time_stamp']),
      restriction: locked ? LiveRestriction.password : LiveRestriction.none,
      notice: chatNotice,
      httpHeaders: headers,
    );
  }

  /// A list row's `time_stamp` (Unix seconds) as the broadcast's start, in
  /// UTC: it stays the same while a room is listed, also when it drops out
  /// of the list and comes back, and is new for the streamer's next
  /// broadcast (checks of 2026-09-28/29). Null for anything that is not an
  /// integer between 2000 and 2100; a bad value drops only the start time.
  static DateTime? startedAt(Object? value) {
    if (value is! int || value < 946684800 || value > 4102444800) return null;
    return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
  }

  /// Page [page] (from 1) of [cards], 20 a page (3.x's `getDirectoryPage`).
  static LiveDirectoryPage directoryPage(List<LiveRoom> cards, {required int page}) => LiveDirectoryPage(
    rooms: slice(cards, page: page, pageSize: directoryPageSize),
    page: page,
    hasMore: page * directoryPageSize < cards.length,
  );

  /// Page [page] of [pageSize] of [values] (3.x's `_page`): nothing for a
  /// page or size below 1, a size over [maxPageSize] or a page past the end.
  static List<T> slice<T>(List<T> values, {required int page, required int pageSize}) {
    if (!validSlice(page: page, pageSize: pageSize)) return const [];
    final start = (page - 1) * pageSize;
    if (start >= values.length) return const [];
    return values.sublist(start, (start + pageSize).clamp(start, values.length));
  }

  /// Whether 3.x served anything for [page] of [pageSize].
  static bool validSlice({required int page, required int pageSize}) =>
      page >= 1 && pageSize >= 1 && pageSize <= maxPageSize;

  // Search --------------------------------------------------------------------

  /// Whether 3.x's search takes [query] (trimmed) at all: not blank, at most
  /// 100 characters, no control characters, not a URL (a room link is
  /// taken before this check).
  static bool isSearchable(String query) =>
      query.isNotEmpty &&
      query.length <= 100 &&
      !RegExp(r'[\x00-\x1f]').hasMatch(query) &&
      Uri.tryParse(query)?.hasScheme != true;

  /// 3.x's `BigoLink.parseOrSiteId`: the id of a room link, else [text]
  /// (trimmed) when it is a Bigo id, else null.
  static String? siteIdOf(String text) {
    final value = text.trim();
    return siteIdFromUrl(value) ?? (isSiteId(value) ? value : null);
  }

  /// Whether 3.x's search looks [query] up as an id before filtering: a Bigo
  /// id holding a digit, `_`, `.` or `-` (a word of letters is a name
  /// first).
  static bool looksLikeId(String query) => isSiteId(query) && RegExp('[0-9_.-]').hasMatch(query);

  /// The cards whose streamer name or topic contains [query], case ignored,
  /// once per Bigo id (case ignored), in list order (3.x's snapshot filter).
  static List<LiveRoom> filter(List<LiveRoom> cards, String query) {
    final needle = query.toLowerCase();
    final seen = <String>{};
    return List.unmodifiable([
      for (final card in cards)
        if ((card.nick.toLowerCase().contains(needle) || card.title.toLowerCase().contains(needle)) &&
            seen.add(card.roomId.toLowerCase()))
          card,
    ]);
  }

  // Web token -----------------------------------------------------------------

  /// 3.x's JSONP callback name of a request made at [now].
  static String callbackName(DateTime now) =>
      'jsonpcallback_${now.millisecondsSinceEpoch}_${now.microsecondsSinceEpoch % 1000000}';

  /// Whether [name] passes 3.x's check of a callback name.
  static bool isCallbackName(String name) => _callback.hasMatch(name);

  /// `webjs/t`: the server time the token request is made for, as written
  /// (a fixed value, not the clock). The answer is JSONP of [callback];
  /// `code` must be a number and `time` 1–20 digits (3.x).
  static String serverTime(String body, {required String callback, int status = 200}) {
    final answer = _jsonp(body, callback: callback, status: status, what: 'webjs/t');
    if (answer['code'] is! int) throw ApiChanged(_site, 'webjs/t: code is ${answer['code']}');
    final time = answer['time'];
    if (time is! String || !_digits.hasMatch(time)) throw ApiChanged(_site, 'webjs/t: time is $time');
    return time;
  }

  /// `webjs/status`: the web token (JSONP of [callback]): non-empty, at most
  /// 4096 characters, without spaces or control characters (3.x).
  static String token(String body, {required String callback, int status = 200}) {
    final value = _jsonp(body, callback: callback, status: status, what: 'webjs/status')['token'];
    if (value is! String || value.isEmpty || value.length > 4096 || RegExp(r'[\x00-\x20\x7f]').hasMatch(value)) {
      throw const ApiChanged(_site, 'webjs/status: no usable token');
    }
    return value;
  }

  static const String _passphrase = 'undefinedval0x01';

  /// The `data` of the token request for the server [timestamp] (3.x's
  /// `BigoTokenCodec.buildData`): OpenSSL's `Salted__` + 8-byte salt +
  /// AES-256-CBC of `{"dr","business":"bigolive-video","scene":"",
  /// "at_time","ver":"2.0"}`, key and IV from EVP_BytesToKey (md5, one
  /// round) over the website's published passphrase; Base64. [salt] and
  /// [nonce] (32 lower-case hex digits) are random unless given.
  static String tokenData(String timestamp, {Random? random, List<int>? salt, String? nonce}) {
    if (!_digits.hasMatch(timestamp)) throw ArgumentError.value(timestamp, 'timestamp', 'not 1–20 digits');
    final generator = random ?? Random.secure();
    final actualSalt = salt ?? [for (var i = 0; i < 8; i++) generator.nextInt(256)];
    if (actualSalt.length != 8) throw ArgumentError.value(actualSalt.length, 'salt', 'not 8 bytes');
    final dr = nonce ?? [for (var i = 0; i < 32; i++) generator.nextInt(16).toRadixString(16)].join();
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(dr)) throw ArgumentError.value(dr, 'nonce', 'not 32 hex digits');
    final payload = utf8.encode(
      jsonEncode({'dr': dr, 'business': 'bigolive-video', 'scene': '', 'at_time': timestamp, 'ver': '2.0'}),
    );
    final derived = _evpBytesToKey(utf8.encode(_passphrase), actualSalt, 48);
    final encrypted = AesCbc.encrypt(
      payload,
      key: Uint8List.sublistView(derived, 0, 32),
      iv: Uint8List.sublistView(derived, 32, 48),
    );
    return base64Encode([...ascii.encode('Salted__'), ...actualSalt, ...encrypted]);
  }

  /// OpenSSL's EVP_BytesToKey with md5 and one round: `D_i = md5(D_{i-1} +
  /// password + salt)`, concatenated to [length] bytes.
  static Uint8List _evpBytesToKey(List<int> password, List<int> salt, int length) {
    final output = BytesBuilder(copy: false);
    var previous = <int>[];
    while (output.length < length) {
      previous = md5.convert([...previous, ...password, ...salt]).bytes;
      output.add(previous);
    }
    return Uint8List.sublistView(output.takeBytes(), 0, length);
  }

  // Studio --------------------------------------------------------------------

  /// `studio/getInternalStudioInfo` asked with the web token, for
  /// [requestedSiteId]. Checked as 3.x did: `code` 0, `uid`, the
  /// `needLogin`/`passRoom`/`isPaidShow` gates, `alive` 0 or 1,
  /// `clientBigoId`, `roomStatus`, `roomType`, the broadcast id, the texts,
  /// and an https `.m3u8` playlist only for a public live studio; anything
  /// else is `ApiChanged`. The exceptions:
  /// - the avatar and the snapshot: 3.x took only an https avatar and
  ///   failed the whole room on the site's `http://` ones (sample
  ///   S03-studio-live); now an http(s) picture is kept and any other is
  ///   left out;
  /// - `passRoom` may be null: every use of a web token after its first
  ///   answers without it and without `hls_src` (24-4, sample
  ///   S03-studio-reused), a [BigoStudio.complete] false answer;
  /// - an id the site does not know is answered with `code` 0 and neither
  ///   `uid` nor `clientBigoId` (sample S03-studio-unknown): `NotFound`
  ///   (3.x failed on it, so a search for an unknown id failed).
  static BigoStudio studio(String body, {required String requestedSiteId, int status = 200}) {
    const what = 'getInternalStudioInfo';
    final data = _success(body, status: status, what: what);
    if (data['uid'] == null && data['clientBigoId'] == null) {
      throw NotFound(_site, '$what: no studio for "$requestedSiteId"');
    }
    final owner = _owner(data['uid'], 'uid');
    final login = _boolean(data['needLogin'], 'needLogin');
    final password = data['passRoom'] == null ? null : _boolean(data['passRoom'], 'passRoom');
    final paid = data['isPaidShow'];
    if (paid is! String || !const {'', '0', '1'}.contains(paid)) throw ApiChanged(_site, '$what: isPaidShow is $paid');
    final alive = _binary(data['alive'], 'alive');
    final access = login
        ? BigoAccess.loginRequired
        : (password ?? false) || paid == '1'
        ? BigoAccess.restricted
        : BigoAccess.public;
    final siteId = _bigoId(data['clientBigoId'], 'clientBigoId');
    final roomStatus = _count(data['roomStatus'], 'roomStatus');
    final roomType = _text(data['roomType'], 'roomType');
    final rawBroadcast = data['roomId'];
    final broadcastId = rawBroadcast == null || rawBroadcast == '' || rawBroadcast == '0'
        ? null
        : _text(rawBroadcast, 'roomId');
    if (broadcastId != null && !RegExp(r'^[1-9][0-9]{0,31}$').hasMatch(broadcastId)) {
      throw ApiChanged(_site, '$what: roomId is $broadcastId');
    }
    final rawHls = data['hls_src'];
    final hls = rawHls == null || rawHls == '' ? null : _playlist(rawHls);
    if (hls != null && (access != BigoAccess.public || !alive)) {
      throw ApiChanged(_site, '$what: hls_src for a ${alive ? access.name : 'offline'} studio');
    }
    return BigoStudio(
      requestedSiteId: requestedSiteId,
      siteId: siteId,
      ownerId: owner,
      access: access,
      alive: switch (access) {
        BigoAccess.loginRequired => null,
        BigoAccess.restricted => alive ? true : null,
        BigoAccess.public => alive,
      },
      roomStatus: roomStatus,
      roomType: roomType,
      broadcastId: broadcastId,
      nickname: _optionalText(data['nick_name'], 'nick_name'),
      title: _optionalText(data['roomTopic'], 'roomTopic'),
      category: _optionalText(data['gameTitle'], 'gameTitle'),
      avatar: _picture(data['avatar']),
      snapshot: _picture(data['snapshot']),
      hls: hls,
      password: password,
      paid: paid == '1',
      complete: password != null,
    );
  }

  /// The room of [studio] (3.x's `_room`): the Bigo id as the site writes it
  /// (`clientBigoId`, whatever the room was asked for by); the topic as
  /// title, else the name; the snapshot as cover (24-1: 3.x used the
  /// avatar, which stays the fallback); the game as area, else `Bigo Live`;
  /// no audience (the studio has none); the notice for the access; 3.x's
  /// headers; the restriction; [BigoRoomData]. An offline studio names
  /// nobody (`nick_name` and `avatar` are empty, sample S03-studio-offline):
  /// they stay empty, so a follow keeps its stored name and picture. With
  /// [danmaku] (a room entry or recording detail) the room also carries its
  /// chat arguments ([danmakuArgs]) in `danmakuData`.
  static LiveRoom room(BigoStudio studio, {bool danmaku = false}) => LiveRoom(
    roomId: studio.siteId,
    platform: _site,
    userId: '${studio.ownerId}',
    link: link(studio.siteId),
    title: studio.title.isEmpty ? studio.nickname : studio.title,
    nick: studio.nickname,
    avatar: studio.avatar,
    cover: studio.snapshot.isEmpty ? studio.avatar : studio.snapshot,
    area: studio.category.isEmpty ? siteName : studio.category,
    liveStatus: studio.liveStatus,
    restriction: studio.restriction,
    notice: switch (studio.access) {
      BigoAccess.loginRequired => loginNotice,
      BigoAccess.restricted => restrictedNotice,
      BigoAccess.public => chatNotice,
    },
    httpHeaders: headers,
    data: studio.data,
    danmakuData: danmaku ? danmakuArgs(studio) : null,
  );

  /// The chat arguments of [studio] (M5.20), or null where the website does
  /// not open its chat (`startLive`, `startWs` and `handleNeedLogin` of its
  /// player, script `14.37bf41.js` of 2026-09-30): a studio that is not live,
  /// behind the login gate, a password room (its chat needs the password),
  /// `roomType` "1" (the page ends the live), or one without a room id. A
  /// paid show's chat is opened, as the website does.
  static BigoDanmakuArgs? danmakuArgs(BigoStudio studio) {
    final roomId = studio.broadcastId;
    if (roomId == null ||
        studio.alive != true ||
        studio.access == BigoAccess.loginRequired ||
        (studio.password ?? false) ||
        studio.roomType == '1') {
      return null;
    }
    return BigoDanmakuArgs(siteId: studio.siteId, ownerId: studio.ownerId, roomId: roomId);
  }

  /// The media playlist of a studio as a line: 3.x's headers, HLS, the CDN
  /// host as line id. The address carries no expiry (so no lease); its
  /// segments are scrambled and go through the relay ([BigoHlsProtection]).
  static LivePlayLine line(Uri hls) =>
      LivePlayLine('$hls', headers: headers, format: StreamFormat.hls, lineId: hls.host);

  // Links ---------------------------------------------------------------------

  /// The Bigo id of a room link (3.x's `BigoLink.parse`): http(s) on
  /// `bigo.tv` or any of its subdomains (`www.bigo.tv`, `m.bigo.tv`; 3.x
  /// took only the first two), on the default port and without user info,
  /// `/<id>` or `/<two-letter language>/<id>`, not a site page
  /// ([reservedPaths]); null for anything else. A fragment (`#…`) is
  /// ignored (3.x refused the link, 24-7).
  static String? siteIdFromUrl(String raw) {
    if (raw.length > 8192 || RegExp(r'[\x00-\x20\x7f]').hasMatch(raw)) return null;
    final parsed = Uri.tryParse(raw.trim());
    if (parsed == null ||
        (!parsed.isScheme('http') && !parsed.isScheme('https')) ||
        parsed.userInfo.isNotEmpty ||
        (parsed.hasPort && parsed.port != (parsed.isScheme('https') ? 443 : 80))) {
      return null;
    }
    final uri = parsed.removeFragment();
    final host = uri.host.toLowerCase();
    if (host != 'bigo.tv' && !host.endsWith('.bigo.tv')) return null;
    final List<String> segments;
    try {
      segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList(growable: false);
    } on FormatException {
      return null;
    }
    final candidate = switch (segments) {
      [final id] => id,
      [final language, final id] when RegExp(r'^[a-zA-Z]{2}$').hasMatch(language) => id,
      _ => null,
    };
    if (candidate == null || reservedPaths.contains(candidate.toLowerCase())) return null;
    return isSiteId(candidate) ? candidate : null;
  }
}

/// Bigo's web HLS protection (3.x's `BigoHlsProtection`): a media playlist
/// tag carries a seed, and the first 16 bytes of each of a segment's first
/// two 188-byte TS packets are XOR-ed with a xorshift stream of it (the sync
/// byte and the PAT/PMT become unreadable). Applying [transform] twice with
/// one seed restores the input. The relay of playback and recording
/// restores the first [prefixBytes] of every segment (M7, M8).
abstract final class BigoHlsProtection {
  /// The bytes a segment's transform touches (two TS packets).
  static const int prefixBytes = 376;

  static final RegExp _tag = RegExp(r'^#EXT-X-BIGO-WEB-PROTECTION:(.*)$', multiLine: true, caseSensitive: false);
  static final RegExp _seed = RegExp(r'(?:^|,)\s*SEED=([0-9]+)\s*(?:,|$)', caseSensitive: false);

  /// The seed of media [playlist], or null when it is not protected. The
  /// seed is looked for in the tag's attribute list: 3.x wanted `SEED=`
  /// right after the colon and missed today's `VERSION=1,SEED=…` (sample
  /// S04-playlist), leaving the segments scrambled. A tag without a seed,
  /// or a seed over 2³² − 1, is a [FormatException].
  static int? seed(String playlist) {
    final attributes = _tag.firstMatch(playlist)?.group(1);
    if (attributes == null) return null;
    final value = _seed.firstMatch(attributes.trim())?.group(1);
    final seed = value == null ? null : int.tryParse(value);
    if (seed == null || seed > 0xffffffff) throw FormatException('Invalid Bigo HLS protection', attributes);
    return seed;
  }

  /// [segment] with its first two TS packets transformed by [seed] (3.x):
  /// for packet k = 0, 1 the state starts at seed XOR (k + 1) × 2654435769
  /// (1831565813 when 0), and each of the packet's first 16 bytes is XOR-ed
  /// with the low byte of the next xorshift state (13, 17, 5; 165 when 0).
  /// A segment shorter than [prefixBytes] or a seed out of range is a
  /// [FormatException].
  static Uint8List transform(List<int> segment, int seed) {
    if (seed < 0 || seed > 0xffffffff) throw FormatException('Invalid Bigo HLS protection seed', seed);
    if (segment.length < prefixBytes) throw const FormatException('Truncated Bigo HLS segment');
    final packets = Uint8List.fromList(segment);
    for (var packet = 0; packet < 2; packet++) {
      var state = (seed ^ ((packet + 1) * 2654435769)) & 0xffffffff;
      if (state == 0) state = 1831565813;
      for (var offset = 0; offset < 16; offset++) {
        state = (state ^ ((state << 13) & 0xffffffff)) & 0xffffffff;
        state = (state ^ (state >> 17)) & 0xffffffff;
        state = (state ^ ((state << 5) & 0xffffffff)) & 0xffffffff;
        final mask = state & 0xff;
        packets[packet * 188 + offset] ^= mask == 0 ? 165 : mask;
      }
    }
    return packets;
  }
}

/// 3.x's avatar made lenient, also for the snapshot: an http(s) URL with a
/// host, no user info and no fragment, as `Uri` writes it (3.x's form); ''
/// for anything else.
String _picture(Object? value) {
  if (value is! String || value.isEmpty) return '';
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (!uri.isScheme('http') && !uri.isScheme('https')) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    return '';
  }
  return '$uri';
}

/// 3.x's `_httpsUri(hls: true)`: an https `.m3u8` URL with a host, no user
/// info and no fragment; `ApiChanged` otherwise.
Uri _playlist(Object? value) {
  final uri = value is String ? Uri.tryParse(value) : null;
  if (uri == null ||
      !uri.isScheme('https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      !uri.path.toLowerCase().endsWith('.m3u8')) {
    throw ApiChanged(_site, 'getInternalStudioInfo: hls_src ${_snippet('$value')}');
  }
  return uri;
}

String _bigoId(Object? value, String what) {
  if (value is! String || !BigoApi.isSiteId(value)) throw ApiChanged(_site, '$what "$value" is not a Bigo id');
  return value;
}

/// 3.x's owner ids: an integer 1 … 2⁵³ − 1.
int _owner(Object? value, String what) {
  if (value is! int || value < 1 || value > 9007199254740991) throw ApiChanged(_site, '$what is $value');
  return value;
}

int _count(Object? value, String what) {
  if (value is! int || value < 0) throw ApiChanged(_site, '$what is $value');
  return value;
}

bool _binary(Object? value, String what) {
  if (value is! int || (value != 0 && value != 1)) throw ApiChanged(_site, '$what is $value');
  return value == 1;
}

bool _boolean(Object? value, String what) {
  if (value is! bool) throw ApiChanged(_site, '$what is $value');
  return value;
}

String _text(Object? value, String what) {
  if (value is! String) throw ApiChanged(_site, '$what is not text');
  return value;
}

String _optionalText(Object? value, String what) => value == null ? '' : _text(value, what);

Map<String, dynamic> _object(Object? value, String what) {
  if (value is Map<String, dynamic>) return value;
  throw ApiChanged(_site, '$what is not an object');
}

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}

/// 3.x's status mapping (`_readResponse`): 200 is an answer; 401 and 403
/// are `RiskControl`, 404 `NotFound`, 429 `RateLimited`; 5xx and every other
/// status (redirects included: 3.x did not follow them) `NetworkFailure`.
/// An answer over [BigoApi.responseLimit] bytes is `ApiChanged`.
void _checkStatus(String body, {required int status, required String what}) {
  switch (status) {
    case 200:
      break;
    case 401 || 403:
      throw RiskControl(_site, detail: '$what: HTTP $status');
    case 404:
      throw NotFound(_site, '$what: HTTP 404');
    case 429:
      throw RateLimited(_site, detail: '$what: HTTP 429');
    default:
      throw NetworkFailure(_site, '$what: HTTP $status');
  }
  // UTF-8 needs at most three bytes per UTF-16 unit, so short bodies need no
  // encoding.
  if (body.length > BigoApi.responseLimit ||
      (body.length * 3 > BigoApi.responseLimit && utf8.encode(body).length > BigoApi.responseLimit)) {
    throw ApiChanged(_site, '$what: answer over ${BigoApi.responseLimit} bytes');
  }
}

/// The `{code, data}` envelope: `code` a number and 0, `data` an object
/// (3.x's `_success`); `ApiChanged` otherwise.
Map<String, dynamic> _success(String body, {required int status, required String what}) {
  _checkStatus(body, status: status, what: what);
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw ApiChanged(_site, '$what: not JSON (${_snippet(body)})');
  }
  final root = _object(decoded, what);
  final code = root['code'];
  if (code is! int || code != 0) {
    throw ApiChanged(_site, '$what: code $code ${jsonString(root['msg']) ?? ''}'.trim());
  }
  return _object(root['data'], '$what data');
}

/// A JSONP answer of [callback] (`callback({...});`, 3.x's exact check).
Map<String, dynamic> _jsonp(String body, {required String callback, required int status, required String what}) {
  _checkStatus(body, status: status, what: what);
  final prefix = '$callback(';
  final text = body.trim();
  if (text.startsWith(prefix) && text.endsWith(');')) {
    try {
      final decoded = jsonDecode(text.substring(prefix.length, text.length - 2));
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Reported below.
    }
  }
  throw ApiChanged(_site, '$what: not JSONP of $callback (${_snippet(body)})');
}
