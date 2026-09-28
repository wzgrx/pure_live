import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/html.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'steambroadcast';

/// A broadcast's state as 3.x read `getbroadcastmpd`'s `success`.
enum SteamBroadcastState {
  /// `ready`: live, with an HLS master.
  live,

  /// `unavailable`, `offline`, `not_live`, `no_broadcast`.
  offline,

  /// `user_restricted`: the broadcaster limits who may watch. 3.x shows the
  /// room as unknown with its own notice, never as offline.
  restricted,

  /// `waiting`, `waiting_to_start`, `waiting_for_start` and any value 3.x did
  /// not know.
  unknown,
}

/// One broadcast as 3.x's `SteamBroadcastRoom` held it: a directory card, or
/// a room read from its watch page and `getbroadcastmpd` (and, on room entry,
/// its checked HLS master).
@immutable
final class SteamBroadcast {
  /// Creates the broadcast.
  const new({
    required this.steamId,
    required this.broadcaster,
    required this.title,
    required this.state,
    this.game = '',
    this.cover = '',
    this.avatar = '',
    this.viewers,
    this.master,
    this.masterChecked = false,
    this.codec,
    this.mediaError,
  });

  /// The broadcaster's 64-bit Steam id: the room's identity.
  final String steamId;

  /// The broadcaster's name: the card's author, or the watch page's title
  /// (`Steam broadcaster` when it has none, 3.x).
  final String broadcaster;

  /// The card's game (its `: Broadcast` type stripped), or `getbroadcastmpd`'s
  /// `title` (`Steam Broadcast` when empty, 3.x; Steam leaves it empty).
  final String title;

  /// The card's game; '' for a room (the room answers have none).
  final String game;

  /// The card's thumbnail (3.x's host and path rule); '' when there is none.
  final String cover;

  /// The card's avatar, any https host (3.x kept only
  /// `avatars.akamai.steamstatic.com`; see [SteamBroadcastApi.room]).
  final String avatar;

  /// Concurrent viewers, when given.
  final int? viewers;

  /// The broadcast's state.
  final SteamBroadcastState state;

  /// The HLS master of a live broadcast (3.x's host and path rule, CDN
  /// parameters appended), when `getbroadcastmpd` gave a usable one.
  final Uri? master;

  /// Whether [master] was fetched and passed 3.x's check (room entry).
  final bool masterChecked;

  /// The video codec the checked master names (`avc`, `hevc`), when one.
  final String? codec;

  /// Why the live broadcast's media cannot be played, when known: an
  /// unusable `hls_url`, or a master that failed to load or 3.x's check. It
  /// never fails the room itself (3.x failed the whole detail, refresh
  /// included).
  final SiteError? mediaError;

  /// This room with the fields its answers lack taken from [known], an
  /// earlier card or room of the same broadcaster (3.x's `enrich`): the
  /// name when it is the id or the placeholder, the title when it is the
  /// placeholder, the game, cover and avatar when empty, the viewers when
  /// not given. State and media stay this room's.
  SteamBroadcast enrich(SteamBroadcast known) => SteamBroadcast(
    steamId: steamId,
    broadcaster: broadcaster == steamId || broadcaster == SteamBroadcastApi.defaultBroadcaster
        ? known.broadcaster
        : broadcaster,
    title: title == SteamBroadcastApi.defaultTitle ? known.title : title,
    game: game.isEmpty ? known.game : game,
    cover: cover.isEmpty ? known.cover : cover,
    avatar: avatar.isEmpty ? known.avatar : avatar,
    viewers: viewers ?? known.viewers,
    state: state,
    master: master,
    masterChecked: masterChecked,
    codec: codec,
    mediaError: mediaError,
  );

  /// This broadcast with its master checked ([codec] as it names it), or
  /// with [mediaError] when loading or checking it failed.
  SteamBroadcast withMaster({String? codec, SiteError? mediaError}) => SteamBroadcast(
    steamId: steamId,
    broadcaster: broadcaster,
    title: title,
    game: game,
    cover: cover,
    avatar: avatar,
    viewers: viewers,
    state: state,
    master: master,
    masterChecked: mediaError == null,
    codec: codec,
    mediaError: mediaError,
  );
}

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
/// and, after room entry, its checked master. The interface shows the notice
/// of [state] in its own language (M13).
@immutable
final class SteamBroadcastRoomData {
  /// Creates the data.
  const new({required this.steamId, required this.state, this.master, this.codec, this.mediaError});

  /// The room's Steam id.
  final String steamId;

  /// The broadcast's state.
  final SteamBroadcastState state;

  /// The HLS master, checked on room entry (3.x fetched it then); null for a
  /// refresh, which does not load it (3.x left refreshed rooms without data).
  final Uri? master;

  /// The video codec the master names, when one.
  final String? codec;

  /// Why the live broadcast's media cannot be played, when known.
  final SiteError? mediaError;

  /// Why this room cannot be played, or null: not live (offline, restricted,
  /// waiting or unknown) is `StreamUnavailable`; a live one with a media
  /// problem says what; a live one without a checked master (a refresh) is
  /// `StreamUnavailable` until the room is entered.
  SiteError? get streamError => switch (state) {
    SteamBroadcastState.offline => StreamUnavailable(_site, '$steamId is offline'),
    SteamBroadcastState.restricted => StreamUnavailable(_site, '$steamId: user_restricted'),
    SteamBroadcastState.unknown => StreamUnavailable(_site, '$steamId: broadcast state unknown'),
    SteamBroadcastState.live when mediaError != null => mediaError,
    SteamBroadcastState.live when master == null => StreamUnavailable(
      _site,
      '$steamId: no checked master; enter the room',
    ),
    SteamBroadcastState.live => null,
  };
}

/// What the danmaku module needs for a room (M5): the broadcaster's Steam
/// id. 3.x had no Steam chat (`EmptyDanmaku`); the archived v4 read the
/// chat log with this key alone (it asks `getbroadcastmpd` for the current
/// broadcast itself, so a new broadcast does not stale it). Whether the app
/// shows Steam chat is the danmaku module's decision; room entry only hands
/// it over, without a request.
@immutable
final class SteamBroadcastDanmakuArgs {
  /// Creates the arguments.
  const new(this.steamId);

  /// The broadcaster's Steam id.
  final String steamId;

  @override
  String toString() => steamId;
}

/// Pure parsing of Steam broadcast answers (3.x's `SteamBroadcastApi`,
/// `SteamBroadcastLink` and the models of its `SteamBroadcastSite`). Each
/// function takes the answer and its status and returns 3.x's models or
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

  /// The area of a room whose game is not known (3.x).
  static const String defaultArea = 'Steam Community';

  /// The title of a room whose broadcast has none (3.x).
  static const String defaultTitle = 'Steam Broadcast';

  /// The name of a broadcaster the watch page does not name (3.x).
  static const String defaultBroadcaster = 'Steam broadcaster';

  /// The notice of a room (3.x's zh.json `steambroadcast_chat_notice`).
  static const String chatNotice = 'Steam 远端聊天尚待接入；界面人数来自平台明确返回的当前并发观看数。';

  /// The notice of a restricted broadcast (`steambroadcast_restricted_notice`).
  static const String restrictedNotice = '该 Steam 直播受账号访问范围限制，界面保持未知状态，不将其显示成未开播。';

  /// Id of the one quality.
  static const String qualityId = 'auto';

  /// The one quality: the HLS master, variants left to the player (3.x:
  /// `auto`, zh.json `steambroadcast_quality_auto`).
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
  /// (3.x's `roomHeaders`).
  static Map<String, String> roomHeaders(String steamId, {bool json = false}) => {
    'user-agent': userAgent,
    'accept': json ? 'application/json, text/javascript, */*; q=0.8' : 'text/html,application/xhtml+xml,*/*;q=0.8',
    'accept-language': 'en-US,en;q=0.9',
    'referer': link(steamId),
    if (json) 'x-requested-with': 'XMLHttpRequest',
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

  /// The Steam id of [raw] (3.x's `SteamBroadcastLink.parseSteamId`): a bare
  /// id, or an http(s) watch link `steamcommunity.com/broadcast/watch/<id>`
  /// (exactly that host and path, a query allowed; no user info, no
  /// fragment, the default ports); null for anything else, a profile link
  /// included.
  static String? steamIdOf(String raw) {
    final value = raw.trim();
    if (isSteamId(value)) return value;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        uri.host.toLowerCase() != 'steamcommunity.com' ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != 80 && uri.port != 443)) {
      return null;
    }
    final List<String> segments;
    try {
      segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList(growable: false);
    } on FormatException {
      return null;
    }
    return switch (segments) {
      ['broadcast', 'watch', final id] when isSteamId(id) => id,
      _ => null,
    };
  }

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
  /// without one, or a repeated broadcaster, is skipped), the content type
  /// without `: Broadcast` as title (else the game), the game, the author's
  /// name (else the id), 3.x's thumbnail rule, the avatar, `N viewers`, all
  /// live. The hidden form says whether page [page] has a next one:
  /// `p == page + 1` and `broadcastsoffset == page × 10`, with cards.
  static SteamBroadcastPage directory(String body, {required int page, int status = 200}) {
    _checkStatus(body, status: status, what: 'allcontenthome');
    final root = HtmlElement.parseFragment(body);
    final seen = <String>{};
    final broadcasts = <SteamBroadcast>[];
    for (final card in root.queryAll((element) => element.hasClass('Broadcast_Card'))) {
      final watch = card.query(
        (element) => element.tag == 'a' && (element.attributes['href'] ?? '').contains('/broadcast/watch/'),
      );
      final steamId = steamIdOf(watch?.attributes['href'] ?? '');
      if (steamId == null || !seen.add(steamId)) continue;
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
        steamId,
      ].firstWhere((name) => name.isNotEmpty);
      final avatarImage = card.query(
        (element) =>
            element.tag == 'img' &&
            element.ancestors
                .takeWhile((ancestor) => !identical(ancestor, card))
                .any((ancestor) => ancestor.hasClass('appHubIconHolder')),
      );
      broadcasts.add(
        SteamBroadcast(
          steamId: steamId,
          broadcaster: broadcaster,
          title: _stripBroadcastSuffix(contentType.isEmpty ? game : contentType),
          game: game,
          cover: _thumbnail(classed('apphub_CardContentPreviewImage')?.attributes['src'], steamId),
          avatar: _avatar(avatarImage?.attributes['src']),
          viewers: viewerCount(_elementText(classed('apphub_CardContentViewers'))),
          state: SteamBroadcastState.live,
        ),
      );
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

  /// The watch page of [steamId] (3.x's `parseWatchHtml`): its application
  /// config must name the same account (`data-broadcastsinfo`, JSON), the
  /// broadcaster's name is in `og:title` (else `<title>`),
  /// `Steam Community :: <name> :: Broadcast`, or [defaultBroadcaster]. A
  /// page without the config is `NotFound`, another account or a broken
  /// config `ApiChanged`. An account that does not exist still has a page;
  /// its title names the id.
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
    return name.isEmpty ? defaultBroadcaster : name;
  }

  /// `getbroadcastmpd` of [steamId] (3.x's `parseBroadcastJson`): the state
  /// of `success`, the title (else [defaultTitle]) and `num_viewers` (a
  /// count, or null); for a live one the HLS master of `hls_url` with
  /// `cdn_auth_url_parameters` appended. A missing or non-text `success` or
  /// `title` is `ApiChanged`. A live one whose `hls_url` or CDN parameters
  /// break 3.x's rules keeps its state and carries the reason as
  /// [SteamBroadcast.mediaError] (3.x failed the room, refresh included).
  static SteamBroadcast broadcast(
    String body, {
    required String steamId,
    required String broadcaster,
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
    final state = switch (success) {
      'ready' => SteamBroadcastState.live,
      'unavailable' || 'offline' || 'not_live' || 'no_broadcast' => SteamBroadcastState.offline,
      'user_restricted' => SteamBroadcastState.restricted,
      _ => SteamBroadcastState.unknown,
    };
    Uri? master;
    SiteError? mediaError;
    if (state == SteamBroadcastState.live) {
      try {
        master = _withCdnAuth(_master(decoded['hls_url'], steamId), decoded['cdn_auth_url_parameters']);
      } on ApiChanged catch (error) {
        mediaError = error;
      }
    }
    final title = _optionalText(decoded['title'], '$what title');
    return SteamBroadcast(
      steamId: steamId,
      broadcaster: broadcaster,
      title: title.isEmpty ? defaultTitle : title,
      viewers: _viewers(decoded['num_viewers']),
      state: state,
      master: master,
      mediaError: mediaError,
    );
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

  /// The card or room of [broadcast] (3.x's `_room`): the Steam id as room
  /// and user id; the title, name, game (else [defaultArea]); the cover, and
  /// as avatar what 3.x showed, the cover (3.x kept only avatars on
  /// `avatars.akamai.steamstatic.com`, and Steam now serves them from
  /// `avatars.fastly.steamstatic.com`), the avatar only when there is no
  /// cover; the viewers as concurrent audience; the state (restricted and
  /// unknown are unknown, never offline); 3.x's notice and headers; [data]
  /// and [danmaku] as given.
  static LiveRoom room(SteamBroadcast broadcast, {SteamBroadcastRoomData? data, SteamBroadcastDanmakuArgs? danmaku}) {
    final viewers = broadcast.viewers?.toString() ?? '';
    return LiveRoom(
      roomId: broadcast.steamId,
      platform: _site,
      userId: broadcast.steamId,
      link: link(broadcast.steamId),
      title: broadcast.title,
      nick: broadcast.broadcaster,
      avatar: _legacyAvatar(broadcast.avatar)
          ? broadcast.avatar
          : broadcast.cover.isNotEmpty
          ? broadcast.cover
          : broadcast.avatar,
      cover: broadcast.cover,
      area: broadcast.game.isEmpty ? defaultArea : broadcast.game,
      watching: viewers,
      onlineViewers: viewers,
      audienceMetricType: viewers.isEmpty ? AudienceMetricType.unknown : AudienceMetricType.onlineViewers,
      liveStatus: switch (broadcast.state) {
        SteamBroadcastState.live => LiveStatus.live,
        SteamBroadcastState.offline => LiveStatus.offline,
        SteamBroadcastState.restricted || SteamBroadcastState.unknown => LiveStatus.unknown,
      },
      notice: broadcast.state == SteamBroadcastState.restricted ? restrictedNotice : chatNotice,
      httpHeaders: mediaHeaders(broadcast.steamId),
      data: data,
      danmakuData: danmaku,
    );
  }

  /// The room data of [broadcast]: the master only when it was checked.
  static SteamBroadcastRoomData roomData(SteamBroadcast broadcast) => SteamBroadcastRoomData(
    steamId: broadcast.steamId,
    state: broadcast.state,
    master: broadcast.masterChecked ? broadcast.master : null,
    codec: broadcast.codec,
    mediaError: broadcast.mediaError,
  );

  /// The one line of a checked master: HLS, the codec it names, no headers
  /// (3.x's player and recorder sent none; the CDN answers without them,
  /// 2026-09-28) and no lease (no expiry in the address; Steam needs no
  /// heartbeat, archive spec §6).
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

/// 3.x's `_avatar` without its host rule: an https URL with a host, no user
/// info or fragment; '' otherwise.
String _avatar(String? value) {
  final uri = Uri.tryParse(_clean(value ?? ''));
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty || uri.hasFragment) {
    return '';
  }
  return '$uri';
}

/// Whether 3.x kept [avatar]: on `avatars.akamai.steamstatic.com`.
bool _legacyAvatar(String avatar) =>
    avatar.isNotEmpty && Uri.tryParse(avatar)?.host.toLowerCase() == 'avatars.akamai.steamstatic.com';

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

String _stripBroadcastSuffix(String value) =>
    value.replaceFirst(RegExp(r':\s*Broadcast\s*$', caseSensitive: false), '').trim();

/// [text] trimmed with runs of white space made one space (3.x's
/// `_optionalText`); over 65536 characters is `ApiChanged`.
String _clean(String text) {
  if (text.length > 65536) throw const ApiChanged(_site, 'text over 65536 characters');
  return text.trim().replaceAll(RegExp(r'\s+'), ' ');
}

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
