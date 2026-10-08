import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/hls_master.dart';
import 'package:live_core/src/html.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'steambroadcast';

/// A broadcast's state, from `getbroadcastmpd`'s `success` (room entry,
/// recording, recovery) or `getbroadcastinfo` (refresh, 27-2).
enum SteamBroadcastState {
  /// `ready`, or `missing_subscription` (a broadcast for subscribers only,
  /// [SteamBroadcast.restriction]); `getbroadcastinfo` online.
  live,

  /// A replay (`is_replay`, which Steam's player plays as one): `ready`
  /// with its master, or `getbroadcastinfo` online. Played like a live.
  replay,

  /// `unavailable`, `offline`, `not_live`, `no_broadcast`;
  /// `getbroadcastinfo`'s `success: 42` or not online.
  offline,

  /// `user_restricted`. Steam's watch page says "`%s`'s account is
  /// currently restricted from broadcasting on Steam" (its
  /// `broadcast_watch.js`): there is no broadcast to watch, whoever asks.
  /// 3.x read it as a viewer restriction and showed the room as unknown;
  /// it is shown as banned.
  accountRestricted,

  /// `waiting`, `waiting_to_start`, `waiting_for_start` and any other value
  /// (3.x).
  unknown,
}

/// One variant of a broadcast's HLS master, as Steam's own player lists it
/// (`<height>p`, the frame rate added above 30 fps: `1080p60`, 27-7). The
/// quality of a variant is played from the master restricted to this
/// variant and its audio (Steam's variants carry no audio of their own), so
/// the variant is a selector that holds across fresh copies of the master
/// (the CDN host and paths change between answers): see [selectIn].
@immutable
final class SteamBroadcastVariant implements HlsVariantSelector {
  /// Creates the variant.
  const new({
    required this.id,
    required this.width,
    required this.height,
    required this.bandwidth,
    this.frameRate = 0,
    this.codec,
  });

  /// The quality id and name: `720p`, `1080p60`.
  final String id;

  /// The width in pixels.
  final int width;

  /// The height in pixels.
  final int height;

  /// The `FRAME-RATE`; 0 when not given.
  final double frameRate;

  /// The `BANDWIDTH` in bits per second.
  final int bandwidth;

  /// The video codec (`avc`, `hevc`), when named.
  final String? codec;

  /// This variant (and its audio) in [text], a copy of the master at
  /// [source]: the variant of the same [id] whose bandwidth is closest to
  /// [bandwidth]. Throws [FormatException] when the master cannot be read
  /// or has no such variant.
  @override
  HlsMasterSelection selectIn(String text, {required Uri source}) {
    final playlist = HlsMasterPlaylist.parse(source, text);
    HlsMasterVariant? best;
    var distance = 0;
    for (final variant in playlist.variants) {
      final size = _resolution(variant);
      if (size == null || SteamBroadcastApi.variantId(size.height, _frameRate(variant)) != id) continue;
      final gap = (int.parse(variant.attributes['BANDWIDTH']!) - bandwidth).abs();
      if (best == null || gap < distance) {
        best = variant;
        distance = gap;
      }
    }
    if (best == null) throw FormatException('Steam variant $id is not in the master');
    return playlist.select(video: best.uri);
  }

  @override
  bool operator ==(Object other) =>
      other is SteamBroadcastVariant &&
      other.id == id &&
      other.width == width &&
      other.height == height &&
      other.frameRate == frameRate &&
      other.bandwidth == bandwidth &&
      other.codec == codec;

  @override
  int get hashCode => Object.hash(id, width, height, frameRate, bandwidth, codec);

  @override
  String toString() => 'SteamBroadcastVariant($id, ${width}x$height, $bandwidth)';
}

/// One broadcast: a directory card, or a room read from its answers (the
/// mini profile or watch page, `getbroadcastinfo` and `getbroadcastmpd`,
/// and on room entry its checked HLS master).
@immutable
final class SteamBroadcast {
  /// Creates the broadcast.
  new({
    required this.steamId,
    required this.state,
    this.broadcaster = '',
    this.title = '',
    this.game = '',
    this.cover = '',
    this.avatar = '',
    this.viewers,
    this.restriction,
    this.broadcastId,
    this.master,
    this.masterChecked = false,
    this.codec,
    Iterable<SteamBroadcastVariant> variants = const [],
    this.mediaError,
  }) : variants = List.unmodifiable(variants);

  /// The broadcaster's 64-bit Steam id: the room's identity.
  final String steamId;

  /// The broadcaster's name: the card's author, the mini profile's
  /// `persona_name` or the watch page's title; '' when none is known (a
  /// name that is only the id is none: Steam writes the id for an account
  /// that does not exist, X-2).
  final String broadcaster;

  /// The broadcast's title, else its game (the card's content type, or
  /// `getbroadcastinfo`'s `title`, else `app_title`); '' when unknown
  /// (3.x wrote `Steam Broadcast`, X-2).
  final String title;

  /// The game; '' when unknown (3.x showed `Steam Community`, X-2).
  final String game;

  /// The live thumbnail (3.x's host and path rule); '' when there is none.
  final String cover;

  /// The broadcaster's avatar (any https host, 184 px), '' when there is
  /// none or it is Steam's default avatar (27-1).
  final String avatar;

  /// Concurrent viewers, when given.
  final int? viewers;

  /// The broadcast's state.
  final SteamBroadcastState state;

  /// Who may watch, when the answer says: [LiveRestriction.none] for
  /// `ready`, [LiveRestriction.subscribersOnly] for `missing_subscription`;
  /// null otherwise (a refresh, a card, not live).
  final LiveRestriction? restriction;

  /// `getbroadcastmpd`'s `broadcastid` of the current broadcast, when one
  /// (the chat's key besides the Steam id, 27-6).
  final String? broadcastId;

  /// The HLS master of a live broadcast or replay (3.x's host and path
  /// rule, CDN parameters appended), when `getbroadcastmpd` gave a usable
  /// one.
  final Uri? master;

  /// Whether [master] was fetched and passed 3.x's check (room entry).
  final bool masterChecked;

  /// The video codec the checked master names (`avc`, `hevc`), when one.
  final String? codec;

  /// The checked master's variants, best first, when it has more than one
  /// (27-7); empty otherwise.
  final List<SteamBroadcastVariant> variants;

  /// Why the broadcast's media cannot be played, when known: an unusable
  /// `hls_url`, or a master that failed to load or 3.x's check. It never
  /// fails the room itself (3.x failed the whole detail, refresh included).
  final SiteError? mediaError;

  /// This broadcast with its fields replaced where given.
  SteamBroadcast _copy({
    String? broadcaster,
    String? title,
    String? game,
    String? cover,
    String? avatar,
    int? viewers,
    bool? masterChecked,
    String? codec,
    Iterable<SteamBroadcastVariant>? variants,
    SiteError? mediaError,
  }) => SteamBroadcast(
    steamId: steamId,
    state: state,
    broadcaster: broadcaster ?? this.broadcaster,
    title: title ?? this.title,
    game: game ?? this.game,
    cover: cover ?? this.cover,
    avatar: avatar ?? this.avatar,
    viewers: viewers ?? this.viewers,
    restriction: restriction,
    broadcastId: broadcastId,
    master: master,
    masterChecked: masterChecked ?? this.masterChecked,
    codec: codec ?? this.codec,
    variants: variants ?? this.variants,
    mediaError: mediaError ?? this.mediaError,
  );

  /// This room with the fields its answers lack taken from [known], an
  /// earlier card or room of the same broadcaster (3.x's `enrich`): the
  /// name, title, game, cover and avatar when empty; the viewers only while
  /// this broadcast is live and has none of its own (27-5: 3.x kept the
  /// last card's count after the broadcast ended). State, restriction and
  /// media stay this room's.
  SteamBroadcast enrich(SteamBroadcast known) => _copy(
    broadcaster: broadcaster.isEmpty ? known.broadcaster : broadcaster,
    title: title.isEmpty ? known.title : title,
    game: game.isEmpty ? known.game : game,
    cover: cover.isEmpty ? known.cover : cover,
    avatar: avatar.isEmpty ? known.avatar : avatar,
    viewers: viewers ?? (state == SteamBroadcastState.live ? known.viewers : null),
  );

  /// This `getbroadcastmpd` room with `getbroadcastinfo`'s title, game and
  /// cover (27-2) where [info] has them; its viewers only when this room
  /// has none.
  SteamBroadcast withInfo(SteamBroadcast info) => _copy(
    title: info.title.isEmpty ? null : info.title,
    game: info.game.isEmpty ? null : info.game,
    cover: info.cover.isEmpty ? null : info.cover,
    viewers: viewers ?? info.viewers,
  );

  /// This broadcast with its master checked ([codec] and [variants] as it
  /// names them), or with [mediaError] when loading or checking it failed.
  SteamBroadcast withMaster({
    String? codec,
    Iterable<SteamBroadcastVariant> variants = const [],
    SiteError? mediaError,
  }) => _copy(masterChecked: mediaError == null, codec: codec, variants: variants, mediaError: mediaError);
}

/// The broadcaster's name and avatar (the mini profile, or the watch page's
/// name when it fails; 27-2).
typedef SteamBroadcastProfile = ({String name, String avatar});

/// One page of the trending broadcasts.
@immutable
final class SteamBroadcastPage {
  /// Creates the page.
  new({required Iterable<SteamBroadcast> broadcasts, required this.hasMore})
    : broadcasts = List.unmodifiable(broadcasts);

  /// The page's broadcasts, once per broadcaster, in page order.
  final List<SteamBroadcast> broadcasts;

  /// Whether another page exists.
  final bool hasMore;
}

/// What a room detail carries besides 3.x's fields: the broadcast's state
/// and restriction and, after room entry, its checked master and variants.
/// The interface shows the notice of [state] in its own language (M13).
@immutable
final class SteamBroadcastRoomData {
  /// Creates the data.
  new({
    required this.steamId,
    required this.state,
    this.restriction,
    this.master,
    this.codec,
    Iterable<SteamBroadcastVariant> variants = const [],
    this.mediaError,
  }) : variants = List.unmodifiable(variants);

  /// The room's Steam id.
  final String steamId;

  /// The broadcast's state.
  final SteamBroadcastState state;

  /// Who may watch, when the answer said (see [SteamBroadcast.restriction]).
  final LiveRestriction? restriction;

  /// The HLS master, checked on room entry (3.x fetched it then); null for a
  /// refresh, which does not load it (3.x left refreshed rooms without data).
  final Uri? master;

  /// The video codec the master names, when one.
  final String? codec;

  /// The master's variants, best first, when it has more than one (27-7).
  final List<SteamBroadcastVariant> variants;

  /// Why the broadcast's media cannot be played, when known.
  final SiteError? mediaError;

  /// The qualities: 3.x's adaptive master first (the player chooses), then
  /// one per variant (27-7), each with its [SteamBroadcastVariant] as data.
  List<LivePlayQuality> get qualities => [
    SteamBroadcastApi.quality,
    for (final variant in variants) LivePlayQuality(quality: variant.id, id: variant.id, data: variant),
  ];

  /// Why this room cannot be played, or null: not live (offline, restricted
  /// account, waiting or unknown) is `StreamUnavailable`, and so is a
  /// broadcast for subscribers only; a live one with a media problem says
  /// what; a live one without a checked master (a refresh) is
  /// `StreamUnavailable` until the room is entered.
  SiteError? get streamError => switch (state) {
    SteamBroadcastState.offline => StreamUnavailable(_site, '$steamId is offline'),
    SteamBroadcastState.accountRestricted => StreamUnavailable(
      _site,
      "$steamId: the broadcaster's account is restricted from broadcasting (user_restricted)",
    ),
    SteamBroadcastState.unknown => StreamUnavailable(_site, '$steamId: broadcast state unknown'),
    _ when restriction == LiveRestriction.subscribersOnly => StreamUnavailable(
      _site,
      "$steamId: a broadcast for the broadcaster's subscribers only (missing_subscription)",
    ),
    _ when mediaError != null => mediaError,
    _ when master == null => StreamUnavailable(_site, '$steamId: no checked master; enter the room'),
    _ => null,
  };
}

/// What the danmaku module needs for a room (M5, 27-6): the broadcaster's
/// Steam id and, when the room is live, the current `broadcastid` (the
/// chat's `getchatinfo` needs it; the archived v4 asked `getbroadcastmpd`
/// for it first, which room entry already did). A new broadcast gets a new
/// id: the chat asks `getbroadcastmpd` again when it changes or is absent.
@immutable
final class SteamBroadcastDanmakuArgs {
  /// Creates the arguments.
  const new(this.steamId, {this.broadcastId});

  /// The broadcaster's Steam id.
  final String steamId;

  /// The current broadcast's id, when known.
  final String? broadcastId;

  @override
  bool operator ==(Object other) =>
      other is SteamBroadcastDanmakuArgs && other.steamId == steamId && other.broadcastId == broadcastId;

  @override
  int get hashCode => Object.hash(steamId, broadcastId);

  @override
  String toString() => steamId;
}

/// Pure parsing of Steam broadcast answers (3.x's `SteamBroadcastApi`,
/// `SteamBroadcastLink` and the models of its `SteamBroadcastSite`, and the
/// answers M4.U added: the mini profile, `getbroadcastinfo`, profile XML).
/// Each function takes the answer and its status and returns the models or
/// throws a `SiteError`.
abstract final class SteamBroadcastApi {
  /// Steam Community.
  static const String origin = 'https://steamcommunity.com';

  /// 3.x's browser user agent of every request.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

  /// The largest answer 3.x read, in UTF-8 bytes.
  static const int responseLimit = 4 * 1024 * 1024;

  /// The largest HLS master 3.x checked, in characters.
  static const int masterLimit = 1024 * 1024;

  /// The platform's name (3.x's `name`): the category and the area's type.
  static const String siteName = 'Steam Broadcasts';

  /// `areaType` of the one area.
  static const String areaType = 'community';

  /// `areaId` of the one area: the trending broadcasts.
  static const String areaId = 'trending';

  /// The one area's name (3.x's zh.json `steambroadcast_category_trending`;
  /// the interface translates it by id, M13).
  static const String areaName = '热门社区直播';

  /// 3.x's area of a room whose game was not known. No longer written (X-2);
  /// M9 may treat a stored area equal to it as empty.
  static const String legacyArea = 'Steam Community';

  /// 3.x's title of a room whose broadcast had none. No longer written
  /// (X-2); M9 may treat a stored title equal to it as empty.
  static const String legacyTitle = 'Steam Broadcast';

  /// 3.x's name of a broadcaster the watch page did not name. No longer
  /// written (X-2); M9 may treat a stored name equal to it as empty.
  static const String legacyBroadcaster = 'Steam broadcaster';

  /// The notice of a room (3.x's zh.json key `steambroadcast_chat_notice`,
  /// rewritten for viewers; M13 translates it). The chat is shown since
  /// M5.23, so it only explains the viewers (M4.U's text began with
  /// "Steam 直播的聊天暂时不能在这里显示。").
  static const String chatNotice = '人数是正在观看的人数。';

  /// 3.x's text of `steambroadcast_chat_notice`, which its rooms and follows
  /// carry; kept for the parity tests and the 3.x migration (M9).
  static const String legacyChatNotice = 'Steam 远端聊天尚待接入；界面人数来自平台明确返回的当前并发观看数。';

  /// The notice of a broadcaster whose account may not broadcast (key
  /// `steambroadcast_restricted_notice`, rewritten: 3.x said the broadcast
  /// was limited to some viewers and kept its state unknown).
  static const String restrictedNotice = '这位主播的 Steam 账号目前被限制直播，暂时不能观看。';

  /// Id of the adaptive quality.
  static const String qualityId = 'auto';

  /// The adaptive quality: the HLS master, variants left to the player
  /// (3.x: `auto`, zh.json `steambroadcast_quality_auto`). First, and the
  /// default, as in 3.x; the variants follow it (27-7).
  static const LivePlayQuality quality = LivePlayQuality(quality: '自适应 HLS', id: qualityId);

  /// The one line's id: the CDN host changes between answers
  /// (`cache6-lax1`, `cache7-lax1`), so it is not the line's identity.
  static const String lineId = 'steamcontent';

  /// Broadcasts per directory page (3.x's `numperpage`).
  static const int pageSize = 10;

  /// The last directory page 3.x asked for.
  static const int maxPage = 10000;

  /// The largest page size of 3.x's recommendations.
  static const int maxRecommendSize = 60;

  /// The largest page size of 3.x's search; a larger one gives nothing.
  static const int maxSearchSize = 100;

  /// The first 64-bit Steam id of an individual account; a Steam id minus
  /// it is the account id of the mini profile.
  static final BigInt _accountBase = BigInt.parse('76561197960265728');

  /// The one area.
  static const LiveArea area = LiveArea(
    platform: _site,
    areaType: areaType,
    typeName: siteName,
    areaId: areaId,
    areaName: areaName,
  );

  /// The headers of the directory (3.x's `directoryHeaders`).
  static const Map<String, String> directoryHeaders = {
    'user-agent': userAgent,
    'accept': 'text/html, */*; q=0.8',
    'accept-language': 'en-US,en;q=0.9',
    'referer': '$origin/?subsection=broadcasts',
    'x-requested-with': 'XMLHttpRequest',
  };

  /// The headers of the watch page, or with [json] of `getbroadcastmpd`
  /// (3.x's `roomHeaders`), `getbroadcastinfo` and the mini profile.
  static Map<String, String> roomHeaders(String steamId, {bool json = false}) => {
    'user-agent': userAgent,
    'accept': json ? 'application/json, text/javascript, */*; q=0.8' : 'text/html,application/xhtml+xml,*/*;q=0.8',
    'accept-language': 'en-US,en;q=0.9',
    'referer': link(steamId),
    if (json) 'x-requested-with': 'XMLHttpRequest',
  };

  /// The headers of a profile's XML (a custom address's Steam id, 27-4).
  static const Map<String, String> xmlHeaders = {
    'user-agent': userAgent,
    'accept': 'text/xml, application/xml, */*; q=0.8',
    'accept-language': 'en-US,en;q=0.9',
  };

  /// 3.x's `mediaHeaders`: what it sent for the master it checked on room
  /// entry, and wrote into rooms (`httpHeaders`, in 3.x's JSON). Its player
  /// and recorder sent none of them (`PlaybackHeaderResolver` had no Steam
  /// branch), so lines carry none either.
  static Map<String, String> mediaHeaders(String steamId) => {
    'user-agent': userAgent,
    'origin': origin,
    'referer': link(steamId),
  };

  static final RegExp _steamId = RegExp(r'^7656119\d{10}$');

  /// Whether [value] is a 64-bit Steam id of an individual account.
  static bool isSteamId(String value) => _steamId.hasMatch(value);

  /// The watch page of [steamId] (3.x's `watchUrl`), also the room's link.
  static String link(String steamId) => '$origin/broadcast/watch/$steamId';

  /// The path segments of [raw] when it is an http(s) link of
  /// `steamcommunity.com` (exactly that host, no user info, no fragment,
  /// the default ports; a query allowed), empty segments left out; null for
  /// anything else.
  static List<String>? _communityPath(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        uri.host.toLowerCase() != 'steamcommunity.com' ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != 80 && uri.port != 443)) {
      return null;
    }
    try {
      return uri.pathSegments.where((segment) => segment.isNotEmpty).toList(growable: false);
    } on FormatException {
      return null;
    }
  }

  /// The Steam id of [raw]: a bare id, a watch link
  /// `steamcommunity.com/broadcast/watch/<id>` (3.x's
  /// `SteamBroadcastLink.parseSteamId`) or a profile link
  /// `steamcommunity.com/profiles/<id>` (27-4), without a request; null for
  /// anything else (a custom address `/id/<name>` needs one, see
  /// [vanityOf]).
  static String? steamIdOf(String raw) {
    final value = raw.trim();
    if (isSteamId(value)) return value;
    return switch (_communityPath(value)) {
      ['broadcast', 'watch', final id] || ['profiles', final id] when isSteamId(id) => id,
      _ => null,
    };
  }

  static final RegExp _vanity = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  /// The custom address of a profile link `steamcommunity.com/id/<name>`
  /// (27-4; letters, digits, `_` and `-`), or null.
  static String? vanityOf(String raw) => switch (_communityPath(raw)) {
    ['id', final name] when _vanity.hasMatch(name) => name,
    _ => null,
  };

  // Requests ------------------------------------------------------------------

  /// The trending broadcasts, page [page] (3.x's `directory`).
  static Uri directoryUrl(int page) => Uri.https('steamcommunity.com', '/apps/allcontenthome', {
    'l': 'english',
    'browsefilter': 'trend',
    'appHubSubSection': '13',
    'forceanon': '1',
    'p': '$page',
    'broadcastsoffset': '${(page - 1) * pageSize}',
    'numperpage': '$pageSize',
  });

  /// The watch page of [steamId].
  static Uri watchUrl(String steamId) => Uri.parse(link(steamId));

  /// `getbroadcastmpd` of [steamId]'s current broadcast.
  static Uri mpdUrl(String steamId) => Uri.https('steamcommunity.com', '/broadcast/getbroadcastmpd/', {
    'broadcastid': '0',
    'steamid': steamId,
    'viewertoken': '0',
    'sessionid': '',
  });

  /// `getbroadcastinfo` of [steamId]'s current broadcast (27-2; the watch
  /// page asks it for the title, game and viewers).
  static Uri infoUrl(String steamId) => Uri.https('steamcommunity.com', '/broadcast/getbroadcastinfo/', {
    'steamid': steamId,
    'broadcastid': '0',
    'location': '5',
  });

  /// The mini profile of [steamId] (27-2): its name and avatar.
  static Uri profileUrl(String steamId) =>
      Uri.https('steamcommunity.com', '/miniprofile/${BigInt.parse(steamId) - _accountBase}/json');

  /// The XML of the profile at the custom address [vanity] (27-4).
  static Uri vanityUrl(String vanity) => Uri.https('steamcommunity.com', '/id/$vanity/', {'xml': '1'});

  // Catalog -------------------------------------------------------------------

  /// 3.x's one category `Steam Broadcasts` with the one area.
  static List<LiveCategory> categories() => [
    LiveCategory(id: _site, name: siteName, children: const [area]),
  ];

  /// Whether [category] is the one area.
  static bool isArea(LiveArea category) =>
      category.platform == _site && category.areaType == areaType && category.areaId == areaId;

  // Directory -----------------------------------------------------------------

  /// `allcontenthome` (an HTML fragment): one `Broadcast_Card` per broadcast,
  /// read as 3.x did (`parseDirectoryHtml`): the watch link's id (a card
  /// without one, a repeated broadcaster, or one that cannot be read is
  /// skipped), the content type without `: Broadcast` as title (else the
  /// game), the game, the author's name (else none, X-2), 3.x's thumbnail
  /// rule, the avatar at 184 px (27-1), `N viewers`, all live. The hidden
  /// form says whether page [page] has a next one: `p == page + 1` and
  /// `broadcastsoffset == page × 10`, with cards.
  static SteamBroadcastPage directory(String body, {required int page, int status = 200}) {
    _checkStatus(body, status: status, what: 'allcontenthome');
    final root = HtmlElement.parseFragment(body);
    final seen = <String>{};
    final broadcasts = <SteamBroadcast>[];
    for (final card in root.queryAll((element) => element.hasClass('Broadcast_Card'))) {
      final watch = card.query(
        (element) => element.tag == 'a' && (element.attributes['href'] ?? '').contains('/broadcast/watch/'),
      );
      final href = watch?.attributes['href'] ?? '';
      final steamId = switch (_communityPath(href)) {
        ['broadcast', 'watch', final id] when isSteamId(id) => id,
        _ => null,
      };
      if (steamId == null || seen.contains(steamId)) continue;
      try {
        broadcasts.add(_card(card, steamId));
        seen.add(steamId);
      } on SiteError {
        // One card that cannot be read only loses itself.
      }
    }
    String? hidden(String name) =>
        root.query((element) => element.tag == 'input' && element.attributes['name'] == name)?.attributes['value'];
    final nextPage = int.tryParse(hidden('p') ?? '');
    final nextOffset = int.tryParse(hidden('broadcastsoffset') ?? '');
    return SteamBroadcastPage(
      broadcasts: broadcasts,
      hasMore: broadcasts.isNotEmpty && nextPage == page + 1 && nextOffset == page * pageSize,
    );
  }

  static SteamBroadcast _card(HtmlElement card, String steamId) {
    HtmlElement? classed(String name) => card.query((element) => element.hasClass(name));
    final contentType = _elementText(classed('apphub_CardContentType'));
    final game = _elementText(classed('apphub_CardContentTitle'));
    final authorLink = card.query(
      (element) =>
          element.tag == 'a' &&
          element.ancestors
              .takeWhile((ancestor) => !identical(ancestor, card))
              .any((ancestor) => ancestor.hasClass('apphub_CardContentAuthorName')),
    );
    final broadcaster = [
      _clean(authorLink?.text ?? ''),
      _elementText(classed('apphub_CardContentAuthorName')),
    ].firstWhere((name) => name.isNotEmpty, orElse: () => '');
    final avatarImage = card.query(
      (element) =>
          element.tag == 'img' &&
          element.ancestors
              .takeWhile((ancestor) => !identical(ancestor, card))
              .any((ancestor) => ancestor.hasClass('appHubIconHolder')),
    );
    return SteamBroadcast(
      steamId: steamId,
      broadcaster: broadcaster == steamId ? '' : broadcaster,
      title: _stripBroadcastSuffix(contentType.isEmpty ? game : contentType),
      game: game,
      cover: _thumbnail(classed('apphub_CardContentPreviewImage')?.attributes['src'], steamId),
      avatar: _avatar(avatarImage?.attributes['src']),
      viewers: viewerCount(_elementText(classed('apphub_CardContentViewers'))),
      state: SteamBroadcastState.live,
    );
  }

  /// `6,763 viewers` → 6763 (3.x's `parseViewerCount`): digits with `,`, `.`,
  /// `_` or spaces, then `viewer(s)`; null for anything else or more than 12
  /// digits.
  static int? viewerCount(String text) {
    final match = RegExp(r'^\s*([0-9][0-9,._\s]*)\s+viewers?\b', caseSensitive: false).firstMatch(text);
    final digits = match?.group(1)?.replaceAll(RegExp('[^0-9]'), '') ?? '';
    if (digits.isEmpty || digits.length > 12) return null;
    return int.tryParse(digits);
  }

  /// The broadcasts of [broadcasts] whose id contains [query] (trimmed and
  /// lower-cased by the caller), or whose name, title or game does, case
  /// ignored (3.x's search over one directory page).
  static List<SteamBroadcast> filter(List<SteamBroadcast> broadcasts, String query) => [
    for (final broadcast in broadcasts)
      if (broadcast.steamId.contains(query) ||
          broadcast.broadcaster.toLowerCase().contains(query) ||
          broadcast.title.toLowerCase().contains(query) ||
          broadcast.game.toLowerCase().contains(query))
        broadcast,
  ];

  // Room ----------------------------------------------------------------------

  static final RegExp _pageTitle = RegExp(r'^Steam Community\s*::\s*(.+?)\s*::\s*Broadcast$', caseSensitive: false);

  /// The watch page of [steamId] (3.x's `parseWatchHtml`, now the fallback
  /// when the mini profile fails, 27-2): its application config must name
  /// the same account (`data-broadcastsinfo`, JSON), the broadcaster's name
  /// is in `og:title` (else `<title>`), `Steam Community :: <name> :: Broadcast`;
  /// '' when it names nobody or only the id (3.x:
  /// [legacyBroadcaster] or the id, X-2). A page without the config is
  /// `NotFound`, another account or a broken config `ApiChanged`. An
  /// account that does not exist still has a page; its title names the id.
  static String broadcaster(String body, {required String steamId, int status = 200}) {
    const what = 'watch page';
    _checkStatus(body, status: status, what: what);
    final root = HtmlElement.parseFragment(body);
    final config = root
        .query((element) => element.attributes['id'] == 'application_config')
        ?.attributes['data-broadcastsinfo'];
    if (config == null) throw NotFound(_site, '$what of $steamId has no broadcast config');
    Object? decoded;
    try {
      decoded = jsonDecode(config);
    } on FormatException {
      throw ApiChanged(_site, '$what: broadcast config is not JSON (${_snippet(config)})');
    }
    if (decoded is! Map) throw const ApiChanged(_site, '$what: broadcast config is not an object');
    final owner = _requiredText(decoded['steamid'], '$what steamid');
    if (owner != steamId) throw ApiChanged(_site, '$what of $steamId names $owner');
    final title =
        root
            .query((element) => element.tag == 'meta' && element.attributes['property'] == 'og:title')
            ?.attributes['content'] ??
        root.query((element) => element.tag == 'title')?.text ??
        '';
    final name = _pageTitle.firstMatch(title)?.group(1)?.trim() ?? '';
    return name == steamId ? '' : name;
  }

  /// The mini profile of [steamId] (27-2): `persona_name` (HTML characters
  /// decoded; '' when it is only the id, which Steam writes for an account
  /// that does not exist) and `avatar_url` (see [directory]'s avatar rule;
  /// Steam's default avatar is none). Not an object, or a `persona_name`
  /// that is not text, is `ApiChanged`.
  static SteamBroadcastProfile profile(String body, {required String steamId, int status = 200}) {
    const what = 'miniprofile';
    final decoded = _object(body, status: status, what: what);
    final name = decoded['persona_name'];
    if (name is! String) throw ApiChanged(_site, '$what: persona_name is $name');
    final cleaned = _clean(decodeHtmlEntities(name));
    final avatar = decoded['avatar_url'];
    return (name: cleaned == steamId ? '' : cleaned, avatar: _avatar(avatar is String ? avatar : null));
  }

  /// `getbroadcastinfo` of [steamId] (27-2; the state of a refresh):
  /// `success: 42` is offline; `success: 1` is live, or a replay with
  /// `is_replay`, when `is_online`, else offline; any other `success` is
  /// `ApiChanged`. While online: the title (`title`, else `app_title`), the
  /// game (`app_title`, HTML characters decoded), the cover
  /// (`thumbnail_url`, 3.x's thumbnail rule) and `viewer_count`. Fields
  /// that only fill the card are left empty when malformed. The name and
  /// avatar are [profile]'s.
  static SteamBroadcast info(
    String body, {
    required String steamId,
    SteamBroadcastProfile profile = (name: '', avatar: ''),
    int status = 200,
  }) {
    const what = 'getbroadcastinfo';
    final decoded = _object(body, status: status, what: what);
    final success = jsonInt(decoded['success']);
    if (success != 1 && success != 42) throw ApiChanged(_site, '$what: success ${decoded['success']}');
    final online = success == 1 && _flag(decoded['is_online']);
    if (!online) {
      return SteamBroadcast(
        steamId: steamId,
        state: SteamBroadcastState.offline,
        broadcaster: profile.name,
        avatar: profile.avatar,
      );
    }
    final game = _lenientText(decoded['app_title']);
    final title = _lenientText(decoded['title']);
    final thumbnail = decoded['thumbnail_url'];
    return SteamBroadcast(
      steamId: steamId,
      state: _flag(decoded['is_replay']) ? SteamBroadcastState.replay : SteamBroadcastState.live,
      broadcaster: profile.name,
      avatar: profile.avatar,
      title: title.isEmpty ? game : title,
      game: game,
      cover: _thumbnail(thumbnail is String ? thumbnail : null, steamId),
      viewers: _viewers(decoded['viewer_count']),
    );
  }

  /// `getbroadcastmpd` of [steamId] (3.x's `parseBroadcastJson`): the state
  /// of `success` (see [SteamBroadcastState]; `ready` with `is_replay` is a
  /// replay), its restriction (`none` for `ready`, subscribers only for
  /// `missing_subscription`), the title ('' when empty), `num_viewers` (a
  /// count, or null) and `broadcastid`; for `ready` the HLS master of
  /// `hls_url` with `cdn_auth_url_parameters` appended. A missing or
  /// non-text `success` or `title` is `ApiChanged`. A `ready` answer whose
  /// `hls_url` or CDN parameters break 3.x's rules keeps its state and
  /// carries the reason as [SteamBroadcast.mediaError] (3.x failed the
  /// room, refresh included). The name and avatar are [profile]'s.
  static SteamBroadcast broadcast(
    String body, {
    required String steamId,
    SteamBroadcastProfile profile = (name: '', avatar: ''),
    int status = 200,
  }) {
    const what = 'getbroadcastmpd';
    _checkStatus(body, status: status, what: what);
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON (${_snippet(body)})');
    }
    if (decoded is! Map) throw const ApiChanged(_site, '$what: not an object');
    final success = _requiredText(decoded['success'], '$what success').toLowerCase();
    final (state, restriction) = switch (success) {
      'ready' => (
        _flag(decoded['is_replay']) ? SteamBroadcastState.replay : SteamBroadcastState.live,
        LiveRestriction.none,
      ),
      'missing_subscription' => (SteamBroadcastState.live, LiveRestriction.subscribersOnly),
      'unavailable' || 'offline' || 'not_live' || 'no_broadcast' => (SteamBroadcastState.offline, null),
      'user_restricted' => (SteamBroadcastState.accountRestricted, null),
      _ => (SteamBroadcastState.unknown, null),
    };
    Uri? master;
    SiteError? mediaError;
    if (success == 'ready') {
      try {
        master = _withCdnAuth(_master(decoded['hls_url'], steamId), decoded['cdn_auth_url_parameters']);
      } on ApiChanged catch (error) {
        mediaError = error;
      }
    }
    final broadcastId = switch (decoded['broadcastid']) {
      final String id when RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(id) => id,
      final int id when id > 0 => '$id',
      _ => null,
    };
    return SteamBroadcast(
      steamId: steamId,
      broadcaster: profile.name,
      avatar: profile.avatar,
      title: _optionalText(decoded['title'], '$what title'),
      viewers: _viewers(decoded['num_viewers']),
      state: state,
      restriction: restriction,
      broadcastId: broadcastId,
      master: master,
      mediaError: mediaError,
    );
  }

  /// The Steam id in the XML of a profile's custom address (27-4):
  /// `<steamID64>`; null when Steam says the profile does not exist
  /// (`<error>`); anything else is `ApiChanged`.
  static String? steamIdOfProfileXml(String body, {int status = 200}) {
    const what = 'profile XML';
    _checkStatus(body, status: status, what: what);
    final id = RegExp(r'<steamID64>\s*(\d+)\s*</steamID64>').firstMatch(body)?.group(1);
    if (id != null && isSteamId(id)) return id;
    if (RegExp(r'<response>\s*<error>').hasMatch(body)) return null;
    throw ApiChanged(_site, '$what: no steamID64 (${_snippet(body)})');
  }

  /// 3.x's `validateMaster` of the HLS master at [master]: `#EXTM3U`, at most
  /// [masterLimit] characters, 1–16 variants, and every variant and
  /// rendition an https URL on the master's host, under
  /// `/broadcast/<steamId>/…/hls_manifest/0/`, with a Steam
  /// `broadcast_origin`. Returns the video codec the variants name (`avc`,
  /// `hevc`, or null when they name none or several); anything else is
  /// `ApiChanged`.
  static String? checkMaster(String body, {required Uri master, required String steamId, int status = 200}) {
    const what = 'HLS master';
    _checkStatus(body, status: status, what: what);
    if (body.length > masterLimit || !body.trimLeft().startsWith('#EXTM3U')) {
      throw ApiChanged(_site, '$what: not an HLS master (${_snippet(body)})');
    }
    final lines = const LineSplitter().convert(body);
    final codecs = <String?>{};
    var variants = 0;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        variants++;
        var next = index + 1;
        while (next < lines.length && lines[next].trim().startsWith('#')) {
          next++;
        }
        if (next >= lines.length || !_validChild(lines[next].trim(), steamId, master.host)) {
          throw ApiChanged(_site, '$what: variant ${next < lines.length ? _snippet(lines[next]) : 'missing'}');
        }
        codecs.add(_videoCodec(line));
      }
      if (line.startsWith('#EXT-X-MEDIA:')) {
        final uri = RegExp('URI="([^"]+)"').firstMatch(line)?.group(1);
        if (uri == null || !_validChild(uri, steamId, master.host)) {
          throw ApiChanged(_site, '$what: rendition ${_snippet(line)}');
        }
      }
    }
    if (variants < 1 || variants > 16) throw ApiChanged(_site, '$what: $variants variants');
    return codecs.length == 1 ? codecs.single : null;
  }

  /// The id and name of a variant [height] pixels high at [frameRate], as
  /// Steam's player writes it: `<height>p`, with the rounded frame rate
  /// above 30 fps (`1080p60`).
  static String variantId(int height, double frameRate) => '${height}p${frameRate > 30 ? frameRate.round() : ''}';

  static final RegExp _variantId = RegExp(r'^[1-9][0-9]{0,4}p(?:[1-9][0-9]{0,3})?$');

  /// Whether [id] has the shape of a variant id ([variantId]).
  static bool isVariantId(String id) => _variantId.hasMatch(id);

  /// The variants of [text], the master at [master] that passed
  /// [checkMaster], best first (height, frame rate, then bandwidth), one per
  /// [variantId] (the highest bandwidth), when there are at least two
  /// (27-7; Steam's player too offers a choice only then). A variant
  /// without a resolution, or whose audio cannot be selected with it, is
  /// left out; a master the shared parser refuses gives none, which leaves
  /// the adaptive quality alone.
  static List<SteamBroadcastVariant> variants(String text, {required Uri master}) {
    final HlsMasterPlaylist playlist;
    try {
      playlist = HlsMasterPlaylist.parse(master, text);
    } on FormatException {
      return const [];
    }
    final byId = <String, SteamBroadcastVariant>{};
    for (final variant in playlist.variants) {
      final size = _resolution(variant);
      if (size == null) continue;
      try {
        playlist.select(video: variant.uri);
      } on FormatException {
        continue;
      }
      final frameRate = _frameRate(variant);
      final choice = SteamBroadcastVariant(
        id: variantId(size.height, frameRate),
        width: size.width,
        height: size.height,
        frameRate: frameRate,
        bandwidth: int.parse(variant.attributes['BANDWIDTH']!),
        codec: _videoCodec(variant.line),
      );
      final current = byId[choice.id];
      if (current == null || choice.bandwidth > current.bandwidth) byId[choice.id] = choice;
    }
    if (byId.length < 2) return const [];
    return List.unmodifiable(
      byId.values.toList()..sort((a, b) {
        final byHeight = b.height.compareTo(a.height);
        if (byHeight != 0) return byHeight;
        final byRate = b.frameRate.compareTo(a.frameRate);
        return byRate != 0 ? byRate : b.bandwidth.compareTo(a.bandwidth);
      }),
    );
  }

  /// The card or room of [broadcast] (3.x's `_room`): the Steam id as room
  /// and user id; the title, name, avatar (27-1: the broadcaster's own, no
  /// longer the cover), cover and game ('' when unknown, X-2); the viewers
  /// as concurrent audience; the state (a restricted account is banned,
  /// waiting and unknown are unknown, never offline) and restriction;
  /// the notice; 3.x's headers; [data] and [danmaku] as given.
  static LiveRoom room(SteamBroadcast broadcast, {SteamBroadcastRoomData? data, SteamBroadcastDanmakuArgs? danmaku}) {
    final viewers = broadcast.viewers?.toString() ?? '';
    return LiveRoom(
      roomId: broadcast.steamId,
      platform: _site,
      userId: broadcast.steamId,
      link: link(broadcast.steamId),
      title: broadcast.title,
      nick: broadcast.broadcaster,
      avatar: broadcast.avatar,
      cover: broadcast.cover,
      area: broadcast.game,
      watching: viewers,
      onlineViewers: viewers,
      audienceMetricType: viewers.isEmpty ? AudienceMetricType.unknown : AudienceMetricType.onlineViewers,
      liveStatus: switch (broadcast.state) {
        SteamBroadcastState.live => LiveStatus.live,
        SteamBroadcastState.replay => LiveStatus.replay,
        SteamBroadcastState.offline => LiveStatus.offline,
        SteamBroadcastState.accountRestricted => LiveStatus.banned,
        SteamBroadcastState.unknown => LiveStatus.unknown,
      },
      restriction: broadcast.restriction,
      notice: broadcast.state == SteamBroadcastState.accountRestricted ? restrictedNotice : chatNotice,
      httpHeaders: mediaHeaders(broadcast.steamId),
      data: data,
      danmakuData: danmaku,
    );
  }

  /// The room data of [broadcast]: the master and its variants only when it
  /// was checked.
  static SteamBroadcastRoomData roomData(SteamBroadcast broadcast) => SteamBroadcastRoomData(
    steamId: broadcast.steamId,
    state: broadcast.state,
    restriction: broadcast.restriction,
    master: broadcast.masterChecked ? broadcast.master : null,
    codec: broadcast.codec,
    variants: broadcast.masterChecked ? broadcast.variants : const [],
    mediaError: broadcast.mediaError,
  );

  /// The one line of a checked master: HLS, the codec it names, no headers
  /// (3.x's player and recorder sent none; the CDN answers without them,
  /// 2026-09-28) and no lease (no expiry in the address; Steam needs no
  /// heartbeat, archive spec §6). A variant's quality plays the same line
  /// restricted to its variant: the resolution names the variant as the
  /// line's selector ([SteamBroadcastVariant.selectIn], G01.4).
  static LivePlayLine line(Uri master, {String? codec}) =>
      LivePlayLine('$master', format: StreamFormat.hls, codec: codec, lineId: lineId);
}

/// 3.x's `_mediaUri`: https on `steamcontent.com` or a subdomain (port 443),
/// no user info or fragment, the path
/// `/broadcast/<steamId>/<digits>/hls_manifest/0/<host>/master.m3u8` (the
/// same host), a Steam `broadcast_origin`; at most 8192 characters without
/// spaces or control characters.
Uri _master(Object? value, String steamId) {
  final raw = _requiredText(value, 'getbroadcastmpd hls_url');
  final uri = raw.length > 8192 || RegExp(r'[\s\x00-\x1f]').hasMatch(raw) ? null : Uri.tryParse(raw);
  final host = uri?.host.toLowerCase() ?? '';
  final path = RegExp('^/broadcast/${RegExp.escape(steamId)}/[1-9][0-9]{0,19}/hls_manifest/0/([^/]+)/master[.]m3u8\$')
      .firstMatch(uri?.path ?? '');
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      !(host == 'steamcontent.com' || host.endsWith('.steamcontent.com')) ||
      (uri.hasPort && uri.port != 443) ||
      path == null ||
      path.group(1)?.toLowerCase() != host ||
      !_steamOrigin(uri.queryParameters['broadcast_origin'])) {
    throw ApiChanged(_site, 'getbroadcastmpd: hls_url ${_snippet(raw)}');
  }
  return uri;
}

/// 3.x's `_appendCdnAuth`: `cdn_auth_url_parameters` (text, leading `&` and
/// `?` removed) appended with `&`; null or blank adds nothing. At most 4096
/// characters without spaces or `#`, 1–16 names of `[A-Za-z0-9_.~-]`, each
/// with 1–8 non-empty values of at most 2048 characters, no
/// `broadcast_origin`; anything else is `ApiChanged`.
Uri _withCdnAuth(Uri master, Object? value) {
  if (value == null) return master;
  if (value is! String) throw ApiChanged(_site, 'getbroadcastmpd: cdn_auth_url_parameters is $value');
  var raw = value.trim();
  if (raw.isEmpty) return master;
  while (raw.startsWith('&') || raw.startsWith('?')) {
    raw = raw.substring(1);
  }
  final problem = ApiChanged(_site, 'getbroadcastmpd: cdn_auth_url_parameters ${_snippet(value)}');
  if (raw.isEmpty || raw.length > 4096 || RegExp(r'[\s#]').hasMatch(raw)) throw problem;
  final Map<String, List<String>> parameters;
  try {
    parameters = Uri(query: raw).queryParametersAll;
  } on FormatException {
    throw problem;
  }
  if (parameters.isEmpty || parameters.length > 16 || parameters.containsKey('broadcast_origin')) throw problem;
  for (final MapEntry(:key, :value) in parameters.entries) {
    if (!RegExp(r'^[A-Za-z0-9_.~-]{1,128}$').hasMatch(key) ||
        value.isEmpty ||
        value.length > 8 ||
        value.any((item) => item.isEmpty || item.length > 2048)) {
      throw problem;
    }
  }
  return Uri.parse('$master&$raw');
}

/// 3.x's `_validChild`: an https URL on [host] under `/broadcast/<steamId>/`
/// with `/hls_manifest/0/` and a Steam `broadcast_origin`.
bool _validChild(String raw, String steamId, String host) {
  final uri = Uri.tryParse(raw);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment &&
      uri.host.toLowerCase() == host.toLowerCase() &&
      uri.path.startsWith('/broadcast/$steamId/') &&
      uri.path.contains('/hls_manifest/0/') &&
      _steamOrigin(uri.queryParameters['broadcast_origin']);
}

/// `steamserver.net` or a subdomain, at most 255 characters (3.x).
bool _steamOrigin(String? value) {
  if (value == null || value.length > 255) return false;
  final host = value.toLowerCase();
  return host == 'steamserver.net' || host.endsWith('.steamserver.net');
}

/// The video codec of an `#EXT-X-STREAM-INF` line's `CODECS`: `avc` for
/// `avc1`/`avc3`, `hevc` for `hvc1`/`hev1`; null otherwise.
String? _videoCodec(String line) {
  final codecs = RegExp('CODECS="([^"]*)"').firstMatch(line)?.group(1) ?? '';
  for (final codec in codecs.split(',')) {
    final name = codec.trim().toLowerCase();
    if (name.startsWith('avc1') || name.startsWith('avc3')) return 'avc';
    if (name.startsWith('hvc1') || name.startsWith('hev1')) return 'hevc';
  }
  return null;
}

/// A variant's `RESOLUTION`, or null.
({int width, int height})? _resolution(HlsMasterVariant variant) {
  final size = RegExp(r'^(\d+)x(\d+)$').firstMatch(variant.attributes['RESOLUTION'] ?? '');
  return size == null ? null : (width: int.parse(size[1]!), height: int.parse(size[2]!));
}

/// A variant's `FRAME-RATE`; 0 when not given.
double _frameRate(HlsMasterVariant variant) => double.tryParse(variant.attributes['FRAME-RATE'] ?? '') ?? 0;

/// 3.x's `_image`: an https thumbnail on `steambroadcast.akamaized.net`
/// under `/broadcast/<steamId>/`, no user info or fragment; '' otherwise.
String _thumbnail(String? value, String steamId) {
  final uri = Uri.tryParse(_clean(value ?? ''));
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      uri.host.toLowerCase() != 'steambroadcast.akamaized.net' ||
      !uri.path.startsWith('/broadcast/$steamId/')) {
    return '';
  }
  return '$uri';
}

/// Steam's default avatar (the question mark), which is no avatar.
const _defaultAvatar = 'fef49e7fa7e1997310d705b2a6158ff8dc1cdfeb';

final RegExp _avatarPath = RegExp(r'^/([0-9a-f]{40})(?:_medium|_full)?\.jpg$');

/// An avatar: an https URL with a host, no user info or fragment (3.x kept
/// only `avatars.akamai.steamstatic.com`; Steam serves them from
/// `avatars.fastly.steamstatic.com` now). A Steam avatar
/// (`avatars.*.steamstatic.com/<hash>.jpg`, 32 px on the cards) is taken at
/// its 184 px size `<hash>_full.jpg`, which the mini profile names (27-1);
/// Steam's default avatar is ''. '' otherwise.
String _avatar(String? value) {
  final uri = Uri.tryParse(_clean(value ?? ''));
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasFragment) {
    return '';
  }
  final host = uri.host.toLowerCase();
  final hash = host.startsWith('avatars.') && host.endsWith('.steamstatic.com')
      ? _avatarPath.firstMatch(uri.path)?.group(1)
      : null;
  if (hash == null) return '$uri';
  if (hash == _defaultAvatar) return '';
  return '${Uri.https(uri.authority, '/${hash}_full.jpg')}';
}

/// 3.x's `_nonNegativeInt`: an integer, a finite number (truncated) or an
/// integer text, when zero or more; null otherwise.
int? _viewers(Object? value) {
  final parsed = switch (value) {
    final int number => number,
    final double number when number.isFinite => number.toInt(),
    final String text => int.tryParse(text.trim()),
    _ => null,
  };
  return parsed != null && parsed >= 0 ? parsed : null;
}

/// A JSON flag: `true`, or a non-zero number.
bool _flag(Object? value) => value == true || (value is num && value != 0);

String _stripBroadcastSuffix(String value) =>
    value.replaceFirst(RegExp(r':\s*Broadcast\s*$', caseSensitive: false), '').trim();

/// [text] trimmed with runs of white space made one space (3.x's
/// `_optionalText`); over 65536 characters is `ApiChanged`.
String _clean(String text) {
  if (text.length > 65536) throw const ApiChanged(_site, 'text over 65536 characters');
  return text.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// A JSON text that only fills the card: cleaned, HTML characters decoded;
/// '' when it is not text or too long.
String _lenientText(Object? value) => value is String && value.length <= 65536 ? _clean(decodeHtmlEntities(value)) : '';

String _elementText(HtmlElement? element) => element == null ? '' : _clean(element.text);

/// 3.x's `_optionalText` of a JSON value: null is '', text is cleaned,
/// anything else is `ApiChanged`.
String _optionalText(Object? value, String what) {
  if (value == null) return '';
  if (value is! String) throw ApiChanged(_site, '$what is $value');
  return _clean(value);
}

/// 3.x's `_string`: non-empty text.
String _requiredText(Object? value, String what) {
  final text = _optionalText(value, what);
  if (text.isEmpty) throw ApiChanged(_site, '$what is empty');
  return text;
}

/// The JSON object of an answer; anything else is `ApiChanged`.
Map<Object?, Object?> _object(String body, {required int status, required String what}) {
  _checkStatus(body, status: status, what: what);
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    throw ApiChanged(_site, '$what: not JSON (${_snippet(body)})');
  }
  if (decoded is! Map) throw ApiChanged(_site, '$what: not an object');
  return decoded;
}

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}

/// 3.x's status mapping (`_throwStatus`): 200 is an answer; 400 and 422 are
/// `ApiChanged`, 401 and 403 `RiskControl` (Akamai's refusal page), 404
/// `NotFound`, 429 `RateLimited`; 5xx and every other status (redirects
/// included: 3.x did not follow them) `NetworkFailure`. An answer over
/// [SteamBroadcastApi.responseLimit] bytes is `ApiChanged`.
void _checkStatus(String body, {required int status, required String what}) {
  switch (status) {
    case 200:
      break;
    case 400 || 422:
      throw ApiChanged(_site, '$what: HTTP $status');
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
  if (body.length > SteamBroadcastApi.responseLimit ||
      (body.length * 3 > SteamBroadcastApi.responseLimit &&
          utf8.encode(body).length > SteamBroadcastApi.responseLimit)) {
    throw ApiChanged(_site, '$what: answer over ${SteamBroadcastApi.responseLimit} bytes');
  }
}
