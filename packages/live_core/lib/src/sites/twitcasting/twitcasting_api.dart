import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'twitcasting';

/// What `streamserver.php` said about a channel's broadcast (3.x kept the
/// qualities made of it in `data`). Only `movie.live` is authoritative: an
/// offline answer still carries the HLS URLs of another broadcast, which are
/// never kept (REG-TWITCASTING-001).
@immutable
final class TwitcastingRoomData {
  /// Creates the data.
  const new({required this.live, this.movieId, this.streams = const {}, this.secretWord = false});

  /// `movie.live`: whether the channel is broadcasting.
  final bool live;

  /// `movie.id`: the broadcast (a new one each time the channel goes live).
  final int? movieId;

  /// `tc-hls.streams` of a live channel by tier (`high`, `medium`, `low`),
  /// as answered and not yet checked; null when the answer had none. Empty
  /// when offline.
  final Map<String, String>? streams;

  /// Whether the channel page of the same room detail asked for the secret
  /// word: the broadcast is password-protected and is not played (the
  /// unified rule for restricted rooms). False when only `streamserver.php`
  /// was asked (a follow refresh).
  final bool secretWord;
}

/// What a comment connection of a live TwitCasting room needs (M5): the
/// channel and the broadcast, whose id `eventpubsuburl.php` takes as
/// `movie_id`. A room entry hands them over in `danmakuData`, without a
/// request; a channel that goes live again has a new broadcast and needs a
/// new room detail.
@immutable
final class TwitcastingDanmakuArgs {
  /// Creates the arguments.
  const new({required this.channel, required this.movieId});

  /// The lower-case channel (screen id).
  final String channel;

  /// `movie.id` of the live broadcast.
  final int movieId;

  @override
  String toString() => 'TwitcastingDanmakuArgs($channel, $movieId)';
}

/// What a channel page says, before `streamserver.php` gives the state:
/// the channel and the broadcast the page shows (the live one, or the last
/// recording when offline).
@immutable
final class TwitcastingChannelPage {
  /// Creates the page.
  const new({required this.room, this.movieId, this.liveStartedAt, this.secretWord = false});

  /// Names, pictures and the title; no state.
  final LiveRoom room;

  /// `data-movie-id`: the broadcast the page shows.
  final int? movieId;

  /// `data-started-at` of the duration timer when it counts a live
  /// broadcast (`data-live-type="live"`); null for a recording.
  final DateTime? liveStartedAt;

  /// Whether the page asks for the secret word (a protected broadcast).
  final bool secretWord;
}

/// Pure parsing of TwitCasting responses (3.x's `TwitcastingApi`: the
/// homepage tabs, the `top/category` window, the text search page, the
/// channel page and `streamserver.php`). Each function takes the response
/// text and status and returns 3.x's models or throws a `SiteError`.
abstract final class TwitcastingApi {
  /// Web origin: the channel pages, `Referer` (with a slash) and `Origin`.
  static const String origin = 'https://twitcasting.tv';

  /// What 3.x sent with every request and every media request
  /// (`TwitcastingApi.playHeaders`, used by its `PlaybackHeaderResolver`):
  /// a bare `Mozilla/5.0` UA and no `Accept-Language`, to which the site
  /// answers with the same English tab names as sample S01 (2026-09-28).
  static const Map<String, String> headers = {'referer': '$origin/', 'origin': origin, 'user-agent': 'Mozilla/5.0'};

  /// The one window `top/category` answers: 60 broadcasts, no other page.
  /// 3.x's popular and area pages ask for it whole and page it locally.
  static const int directoryWindow = 60;

  /// Live results the search page shows at most, all in one page.
  static const int searchWindow = 50;

  /// Tiers of `tc-hls.streams`, best first. The qualities keep 3.x's names
  /// (`HLS high`…) and ids: no rename or merge was decided for TwitCasting,
  /// so there is no old → new id table for stored preferences (M9).
  static const List<String> qualityKeys = ['high', 'medium', 'low'];

  /// A channel (screen) id, lower case: an optional `c:` (TwitCasting),
  /// `g:` (Google), `f:` (Facebook) or `ig:` (Instagram) prefix and
  /// `[a-z0-9_]`.
  static final RegExp channelPattern = RegExp(r'^(?:(?:c|g|f|ig):)?[a-z0-9_]{1,64}$');

  /// Site pages that look like channels.
  static const Set<String> reservedPaths = {
    'search',
    'help',
    'login',
    'logout',
    'settings',
    'signup',
    'register',
    'terms',
    'privacy',
    'about',
    'index',
    'show',
    'categories',
  };

  /// A homepage tab key (`data-channel`).
  static final RegExp areaIdPattern = RegExp(r'^[a-zA-Z0-9_]{1,80}$');

  /// Hosts of the channel pages.
  static const Set<String> hosts = {'twitcasting.tv', 'www.twitcasting.tv'};

  /// [value] as a channel id (trimmed, lower case), or null when it is not
  /// one or names a site page.
  static String? channelName(String value) {
    final name = value.trim().toLowerCase();
    return channelPattern.hasMatch(name) && !reservedPaths.contains(name) ? name : null;
  }

  /// The channel of a channel page `http(s)://(www.)twitcasting.tv/{id}`
  /// (query and one trailing slash allowed). Movie and archive links name
  /// one old broadcast, not the channel's current one, and are not channels
  /// (REG-TWITCASTING-003); nor are other hosts, ports, user info or
  /// undecodable paths.
  static String? channelFromUri(Uri uri) {
    if (!(uri.isScheme('http') || uri.isScheme('https')) ||
        !hosts.contains(uri.host.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.isScheme('https') ? 443 : 80))) {
      return null;
    }
    try {
      final parts = uri.pathSegments.toList();
      if (parts.isNotEmpty && parts.last.isEmpty) parts.removeLast();
      return parts.length == 1 ? channelName(parts.single) : null;
    } on FormatException {
      return null;
    }
  }

  // Catalog -------------------------------------------------------------------

  /// The homepage's top tabs (`a.tw-top-tab-item[data-channel]`) as the
  /// areas of one category, in page order ("For You" has no key and is left
  /// out). A tab without a valid key or label, no tab or more than 100 fail
  /// the catalog (`ApiChanged`), as in 3.x.
  static List<LiveCategory> categories(String body, {int status = 200}) {
    _checkStatus(status, 'home');
    final page = _Html(body);
    final areas = <String, LiveArea>{};
    for (final tag in page.tags()) {
      final key = tag.attributes['data-channel'];
      if (tag.name != 'a' || key == null || !tag.hasClass('tw-top-tab-item')) continue;
      final label = page.textOf(tag).trim();
      if (!areaIdPattern.hasMatch(key) || label.isEmpty) throw ApiChanged(_site, 'home: tab "$key" "$label"');
      areas.putIfAbsent(
        key,
        () => LiveArea(platform: _site, areaId: key, areaType: 'directory', areaName: label, typeName: 'TwitCasting'),
      );
    }
    if (areas.isEmpty || areas.length > 100) throw ApiChanged(_site, 'home: ${areas.length} category tabs');
    return [
      LiveCategory(id: _site, name: 'TwitCasting', children: [...areas.values]),
    ];
  }

  /// The `top/category` window, one entry per row in the site's order: the
  /// room a row shows, or null when it is left out. Left out are ended,
  /// deleted and group broadcasts (3.x; what a group broadcast is was never
  /// seen, 0 of 837 rows on 2026-09-29) and a malformed row (a flag that is
  /// not a boolean, a bad channel, broadcast, `live_url` or viewer count),
  /// which 3.x let fail the whole list (the unified fault-tolerance rule).
  /// A window whose every row is malformed, over 60 rows or not the list is
  /// `ApiChanged`.
  ///
  /// A locked broadcast (the secret word) is a live room restricted to
  /// [LiveRestriction.password], where 3.x left it out; any other is
  /// [LiveRestriction.none]. The start time is [now] less `elapsed_time`
  /// (seconds), when [now] is given.
  static List<LiveRoom?> directoryRows(String body, {int status = 200, DateTime? now}) {
    _checkStatus(status, 'top/category');
    final rows = _object(_decode(body, 'top/category'), 'top/category')['movies'];
    if (rows is! List || rows.length > directoryWindow) {
      throw ApiChanged(_site, 'top/category: movies is ${rows is List ? '${rows.length} rows' : rows.runtimeType}');
    }
    final window = [for (final row in rows) _directoryRow(row, now)];
    if (rows.isNotEmpty && window.every((row) => row.malformed)) {
      throw ApiChanged(_site, 'top/category: all ${rows.length} rows malformed');
    }
    return [for (final row in window) row.room];
  }

  /// One `top/category` row: its room, or none when it is left out or
  /// malformed.
  static ({LiveRoom? room, bool malformed}) _directoryRow(Object? raw, DateTime? now) {
    const malformed = (room: null, malformed: true);
    if (raw is! Map) return malformed;
    final row = raw.cast<Object?, Object?>();
    final flags = ['is_live', 'is_locked', 'is_group', 'is_deleted'];
    if (flags.any((flag) => row[flag] is! bool)) return malformed;
    if (row['is_live'] != true || row['is_group'] != false || row['is_deleted'] != false) {
      return (room: null, malformed: false);
    }
    final channel = channelName(_text(row['user_id']));
    final movie = _integer(row['id']);
    final link = Uri.tryParse(_text(row['live_url']));
    final count = _integer(row['current_viewer_count']);
    if (channel == null ||
        movie == null ||
        movie <= 0 ||
        link == null ||
        link.hasAuthority ||
        link.hasQuery ||
        link.hasFragment ||
        _segments(link) != '$channel/movie/$movie' ||
        count == null ||
        count < 0) {
      return malformed;
    }
    final telop = _text(row['telop']);
    final elapsed = _integer(row['elapsed_time']);
    final started = now == null || elapsed == null || elapsed < 0 ? null : startedBefore(now, elapsed);
    final room = LiveRoom(
      roomId: channel,
      platform: _site,
      userId: channel,
      link: '$origin/$channel',
      title: telop.isNotEmpty ? telop : _text(row['title']),
      nick: _text(row['user_name']),
      cover: _picture(row['thumbnail_url']),
      avatar: _picture(row['user_icon_url']),
      watching: '$count',
      onlineViewers: '$count',
      audienceMetricType: AudienceMetricType.onlineViewers,
      liveStatus: LiveStatus.live,
      startedAt: started != null && started.millisecondsSinceEpoch > 0 ? started : null,
      restriction: row['is_locked'] == true ? LiveRestriction.password : LiveRestriction.none,
    );
    return (room: room, malformed: false);
  }

  /// Rows [offset] to [offset] + [pageSize] of a list [window], as 3.x
  /// sliced it: the rows left out are dropped after slicing, so a page may
  /// hold fewer rooms, and a channel repeated on the page is shown once.
  static List<LiveRoom> slice(List<LiveRoom?> window, {required int offset, required int pageSize}) {
    final rooms = <String, LiveRoom>{};
    for (final room in window.skip(offset).take(pageSize)) {
      if (room != null) rooms.putIfAbsent(room.roomId, () => room);
    }
    return List.unmodifiable(rooms.values);
  }

  /// Page [offset]/[pageSize] of the `top/category` window ([directoryRows]
  /// sliced by [slice]).
  static List<LiveRoom> directory(
    String body, {
    required int offset,
    required int pageSize,
    int status = 200,
    DateTime? now,
  }) => slice(
    directoryRows(body, status: status, now: now),
    offset: offset,
    pageSize: pageSize,
  );

  /// [now] less [seconds], to the whole second: the start of a broadcast
  /// the site says has run that long.
  static DateTime startedBefore(DateTime now, int seconds) {
    final utc = now.toUtc();
    return DateTime.fromMillisecondsSinceEpoch(
      utc.millisecondsSinceEpoch - utc.millisecondsSinceEpoch % 1000,
      isUtc: true,
    ).subtract(Duration(seconds: seconds));
  }

  // Search --------------------------------------------------------------------

  /// The search page's live section (`#tw-search-result-live`; the user,
  /// Premier and recording sections are not live), one entry per row in the
  /// page's order: the room a row shows, or null when it is left out.
  ///
  /// - A row with the LIVE badge that can be played is a live room without
  ///   restriction ([LiveRestriction.none]).
  /// - A private broadcast (the "Private" badge, `data-can-play="false"`) is
  ///   a live room restricted to [LiveRestriction.private] (12-5; M4.12 left
  ///   it out, 3.x failed the whole page). Another row the site will not
  ///   play is [LiveRestriction.unplayable].
  /// - A row that can be played without the LIVE badge is left out (3.x),
  ///   and so is a malformed row (links that do not agree), which 3.x let
  ///   fail the page (the unified fault-tolerance rule).
  ///
  /// The start time is the row's `time[datetime]`. No audience: the page
  /// shows viewers only for private rows. A page without the live section
  /// (a challenge), over 50 rows or rows that are all malformed are
  /// `ApiChanged`.
  static List<LiveRoom?> searchRows(String body, {int status = 200}) {
    _checkStatus(status, 'search');
    final html = _Html(body);
    final section = html.first((tag) => tag.attributes['id'] == 'tw-search-result-live');
    if (section == null) throw const ApiChanged(_site, 'search: no live section');
    final rows = html.all((tag) => tag.hasClass('tw-search-result-row'), within: section);
    if (rows.length > searchWindow) throw ApiChanged(_site, 'search: ${rows.length} live rows');
    final window = [for (final row in rows) _searchRow(html, row)];
    if (rows.isNotEmpty && window.every((row) => row.malformed)) {
      throw ApiChanged(_site, 'search: all ${rows.length} live rows malformed');
    }
    return [for (final row in window) row.room];
  }

  /// Page [page] of [pageSize] rows of the search page's live section
  /// ([searchRows] sliced as 3.x did, [slice]).
  static List<LiveRoom> searchRooms(String body, {required int page, required int pageSize, int status = 200}) => slice(
    searchRows(body, status: status),
    offset: (page - 1) * pageSize,
    pageSize: pageSize,
  );

  /// One live search row: its room, or none when it is left out or
  /// malformed.
  static ({LiveRoom? room, bool malformed}) _searchRow(_Html html, _Tag row) {
    final badges = html.all((tag) => tag.hasClass('tw-movie-thumbnail2-badge'), within: row);
    final playable = html.first(
      (tag) => tag.hasClass('tw-movie-thumbnail2-image-wrapper') && tag.attributes['data-can-play'] == 'true',
      within: row,
    );
    final LiveRestriction restriction;
    if (playable != null) {
      if (!badges.any((badge) => badge.attributes['data-status'] == 'live')) return (room: null, malformed: false);
      restriction = LiveRestriction.none;
    } else {
      final private = badges.any((badge) => html.textOf(badge).trim().toLowerCase() == 'private');
      restriction = private ? LiveRestriction.private : LiveRestriction.unplayable;
    }
    final user = html.first((tag) => tag.hasClass('tw-search-result-row-user-name'), within: row);
    final userText = user == null ? null : html.first((tag) => tag.hasClass('usertext'), within: user);
    final channelHref = userText == null ? null : html.first((tag) => tag.name == 'a', within: userText);
    final movieHref = html.first((tag) => tag.name == 'a' && tag.hasClass('tw-movie-thumbnail2'), within: row);
    final channel = _searchChannel(movieHref?.attributes['href'] ?? '', channelHref?.attributes['href'] ?? '');
    if (channel == null) return (room: null, malformed: true);
    final title = html.first((tag) => tag.hasClass('tw-movie-thumbnail-title'), within: row);
    final name = user == null ? null : html.first((tag) => tag.hasClass('username'), within: user);
    final cover = html.first((tag) => tag.hasClass('tw-movie-thumbnail2-image'), within: row);
    final avatarBox = html.first((tag) => tag.hasClass('userimage32'), within: row);
    final avatar = avatarBox == null ? null : html.first((tag) => tag.name == 'img', within: avatarBox);
    final date = html.first((tag) => tag.name == 'time' && tag.hasClass('tw-movie-thumbnail-date'), within: row);
    final room = LiveRoom(
      roomId: channel,
      platform: _site,
      userId: channel,
      link: '$origin/$channel',
      title: title == null ? '' : html.textOf(title).trim(),
      nick: name == null ? channel : html.textOf(name).trim(),
      cover: _picture(cover?.attributes['src']),
      avatar: _picture(avatar?.attributes['src']),
      watching: '',
      audienceMetricType: AudienceMetricType.unknown,
      liveStatus: LiveStatus.live,
      startedAt: pageDate(date?.attributes['datetime'] ?? ''),
      restriction: restriction,
    );
    return (room: room, malformed: false);
  }

  /// The channel of a live search row, or null when `/{channel}` and
  /// `/{channel}/movie/{movie}` do not agree (3.x's checks).
  static String? _searchChannel(String movieHref, String channelHref) {
    final movieUri = Uri.tryParse(movieHref);
    final channelUri = Uri.tryParse(channelHref);
    if (movieUri == null ||
        channelUri == null ||
        movieUri.hasAuthority ||
        channelUri.hasAuthority ||
        movieUri.hasQuery ||
        movieUri.hasFragment ||
        channelUri.hasQuery ||
        channelUri.hasFragment) {
      return null;
    }
    try {
      final channelParts = channelUri.pathSegments;
      final movieParts = movieUri.pathSegments;
      if (channelParts.length != 1 || movieParts.length != 3) return null;
      final channel = channelName(channelParts.single);
      final movie = _integer(movieParts.last);
      if (channel == null ||
          movieParts.first.toLowerCase() != channel ||
          movieParts[1] != 'movie' ||
          movie == null ||
          movie <= 0) {
        return null;
      }
      return channel;
    } on FormatException {
      return null;
    }
  }

  static final RegExp _pageDate = RegExp(
    r'^(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun), (\d{1,2}) ([A-Z][a-z]{2}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) ([+-])(\d{2})(\d{2})$',
  );

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// A page's `datetime` (`Sun, 27 Sep 2026 23:26:34 +0900`, Japan time on
  /// the samples) in UTC, or null when it is not one or not after 1970.
  static DateTime? pageDate(String text) {
    final match = _pageDate.firstMatch(text.trim());
    if (match == null) return null;
    final month = _months.indexOf(match.group(2)!) + 1;
    final [day, year, hour, minute, second, offsetHours, offsetMinutes] = [
      for (final group in [1, 3, 4, 5, 6, 8, 9]) int.parse(match.group(group)!),
    ];
    if (month == 0 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 59 || offsetMinutes > 59) {
      return null;
    }
    final local = DateTime.utc(year, month, day, hour, minute, second);
    if (local.day != day) return null;
    final offset = Duration(hours: offsetHours, minutes: offsetMinutes);
    final utc = match.group(7) == '+' ? local.subtract(offset) : local.add(offset);
    return utc.millisecondsSinceEpoch > 0 ? utc : null;
  }

  // Rooms ---------------------------------------------------------------------

  /// The channel page of [channel] ([roomId] as the user asked for it): who
  /// the channel is and which broadcast the page shows, before its state is
  /// asked for.
  ///
  /// - A redirect is an unknown channel: the site sends it to the homepage
  ///   (3.x followed it and reported a schema failure);
  /// - a page asking for the secret word is a protected broadcast: the room
  ///   carries no names (the page shows none that could be checked; a
  ///   follow keeps what it stored) and [TwitcastingChannelPage.secretWord]
  ///   (3.x and M4.12 failed it with `NeedsLogin`);
  /// - otherwise the `twitter:creator` meta and the header's `data-user-id`
  ///   must name [channel] (`ApiChanged`).
  ///
  /// The title is the broadcast's telop, the text the page shows under its
  /// title (`span.tw-player-page-title-description`, without the hashtags
  /// inside it; 12-1, REG-TWITCASTING-004); without one, the page's
  /// `twitter:title` as 3.x showed it ("Live #…" when the streamer set
  /// none). `twitter:description` is not used: without a telop it is the
  /// channel's profile text (sample S04-page-live-tags).
  static TwitcastingChannelPage channelPage(
    String body, {
    required String roomId,
    required String channel,
    int status = 200,
  }) {
    if (status >= 300 && status < 400) throw NotFound(_site, 'channel page of $channel: HTTP $status (sent home)');
    _checkStatus(status, 'channel page');
    if (body.contains('Enter the secret word to access')) {
      return TwitcastingChannelPage(
        room: LiveRoom(roomId: roomId, platform: _site, userId: channel, link: '$origin/$channel', watching: ''),
        secretWord: true,
      );
    }
    final page = _Html(body);
    String? meta(String attribute, String name) =>
        page.first((tag) => tag.name == 'meta' && tag.attributes[attribute] == name)?.attributes['content'];
    final creators = [
      for (final tag in page.tags())
        if (tag.name == 'meta' && tag.attributes['name'] == 'twitter:creator') tag.attributes['content'] ?? '',
    ];
    if (creators.length != 1 || channelName(creators.single) != channel) {
      throw ApiChanged(_site, 'channel page of $channel: twitter:creator $creators');
    }
    final header = page.first((tag) => tag.hasClass('tw-user-header'));
    if (header == null || channelName(header.attributes['data-user-id'] ?? '') != channel) {
      throw ApiChanged(_site, 'channel page of $channel: header of ${header?.attributes['data-user-id']}');
    }
    final title = meta('name', 'twitter:title') ?? '';
    final telopTag = page.first((tag) => tag.hasClass('tw-player-page-title-description'));
    final telop = telopTag == null ? '' : page.ownText(telopTag).trim();
    final name = page.first((tag) => tag.hasClass('tw-user-nav2-name'));
    final icon = page.first((tag) => tag.hasClass('tw-user-nav2-icon'));
    final avatar = icon == null ? null : page.first((tag) => tag.name == 'img', within: icon);
    final timer = page.first((tag) => tag.hasClass('tw-player-duration-time') && tag.attributes['id'] == 'updatetimer');
    final started = _integer(timer?.attributes['data-started-at']);
    final movie = page.first((tag) => tag.attributes.containsKey('data-movie-id'));
    return TwitcastingChannelPage(
      room: LiveRoom(
        roomId: roomId,
        platform: _site,
        userId: channel,
        link: '$origin/$channel',
        title: telop.isNotEmpty ? telop : (title.trim().isEmpty ? '' : title),
        nick: name == null ? channel : page.textOf(name).trim(),
        avatar: _picture(avatar?.attributes['src']),
        cover: _picture(meta('property', 'og:image')),
        watching: '',
      ),
      movieId: _integer(movie?.attributes['data-movie-id']),
      liveStartedAt: timer?.attributes['data-live-type'] == 'live' && started != null && started > 0
          ? DateTime.fromMillisecondsSinceEpoch(started, isUtc: true)
          : null,
    );
  }

  /// `streamserver.php`: the broadcast state and, when live, its HLS tiers
  /// (checked only when played). `{}` is a channel that does not exist; no
  /// boolean `movie.live` is `ApiChanged`. A private broadcast is not live
  /// here, for an anonymous client (sample S05-stream-private).
  static TwitcastingRoomData streamServer(String body, {int status = 200}) {
    _checkStatus(status, 'streamserver');
    final decoded = _decode(body, 'streamserver');
    if (decoded is Map && decoded.isEmpty) throw const NotFound(_site, 'streamserver: {} (no such channel)');
    final root = _object(decoded, 'streamserver');
    final movie = root['movie'];
    if (movie is! Map || movie['live'] is! bool) throw const ApiChanged(_site, 'streamserver: no movie.live');
    final live = movie['live'] == true;
    final id = _integer(movie['id']);
    if (!live) return TwitcastingRoomData(live: false, movieId: id);
    final hls = root['tc-hls'];
    final streams = hls is Map ? hls['streams'] : null;
    return TwitcastingRoomData(
      live: true,
      movieId: id,
      streams: streams is Map
          ? {
              for (final key in qualityKeys)
                if (streams.containsKey(key)) key: _text(streams[key]),
            }
          : null,
    );
  }

  /// The room of [page] in the state [stream] reports, carrying it for the
  /// streams. When live:
  /// - the start time is the page's, if the page shows the same broadcast
  ///   (a channel that went live between the two requests has none);
  /// - the restriction is [LiveRestriction.password] when the page asked
  ///   for the secret word, else [LiveRestriction.none]: a private broadcast
  ///   is never live to an anonymous client (samples S04/S05-private), so a
  ///   live broadcast is one it can watch;
  /// - the comment arguments are [TwitcastingDanmakuArgs] (12-3, M5).
  ///
  /// Offline, it has neither a start time nor a restriction (unified rule).
  static LiveRoom roomDetail(TwitcastingChannelPage page, TwitcastingRoomData stream) {
    final movie = stream.movieId;
    if (!stream.live) return page.room.copyWith(liveStatus: LiveStatus.offline, data: stream);
    final sameBroadcast = page.movieId == null || movie == null || page.movieId == movie;
    return page.room.copyWith(
      liveStatus: LiveStatus.live,
      startedAt: sameBroadcast ? page.liveStartedAt : null,
      restriction: page.secretWord ? LiveRestriction.password : LiveRestriction.none,
      data: TwitcastingRoomData(live: true, movieId: movie, streams: stream.streams, secretWord: page.secretWord),
      danmakuData: movie == null || movie <= 0
          ? null
          : TwitcastingDanmakuArgs(channel: page.room.userId ?? page.room.roomId, movieId: movie),
    );
  }

  /// A follow refresh from `streamserver.php` alone (12-2): the state and
  /// the broadcast. Names, pictures, the title, the start time and the
  /// restriction are left empty, so a follow keeps what it stored (M2.1:
  /// the start time and restriction are cleared when the state changes);
  /// a room entry reads the channel page again.
  static LiveRoom refreshRoom(TwitcastingRoomData stream, {required String roomId, required String channel}) =>
      LiveRoom(
        roomId: roomId,
        platform: _site,
        userId: channel,
        link: '$origin/$channel',
        watching: '',
        liveStatus: stream.live ? LiveStatus.live : LiveStatus.offline,
        data: stream,
      );

  // Streams -------------------------------------------------------------------

  /// 3.x's qualities: one per tier of `tc-hls.streams`, labelled `HLS high`,
  /// `HLS medium`, `HLS low`, best first. A channel that is not broadcasting
  /// has none (`StreamUnavailable`), and neither has a password-protected
  /// broadcast ([TwitcastingRoomData.secretWord], `StreamUnavailable`
  /// naming it). A tier URL that is not an https `*.twitcasting.tv`
  /// playlist of this broadcast is left out, the other tiers still play
  /// (the unified fault-tolerance rule; 3.x rejected the whole answer); no
  /// valid tier at all is `ApiChanged`.
  static List<LivePlayQuality> qualities(TwitcastingRoomData data) {
    if (!data.live) throw const StreamUnavailable(_site, 'streamserver: not broadcasting');
    if (data.secretWord) {
      throw const StreamUnavailable(_site, 'channel page: the broadcast is password-protected (secret word)');
    }
    final movie = data.movieId;
    final streams = data.streams;
    if (movie == null || movie <= 0) throw ApiChanged(_site, 'streamserver: movie id $movie');
    if (streams == null) throw const ApiChanged(_site, 'streamserver: no tc-hls streams');
    final path = RegExp('^/tc[.]livehls/v1/streams/$movie/hls/[0-9]+[.][0-9]+/media[.]m3u8\$');
    final qualities = <LivePlayQuality>[];
    for (final key in qualityKeys) {
      final url = streams[key];
      if (url == null) continue;
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !uri.isScheme('https') ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment ||
          (uri.hasPort && uri.port != 443) ||
          !(uri.host == 'twitcasting.tv' || uri.host.endsWith('.twitcasting.tv')) ||
          !path.hasMatch(uri.path)) {
        continue;
      }
      qualities.add(LivePlayQuality(id: key, quality: 'HLS $key', sort: 3 - qualities.length, data: url));
    }
    if (qualities.isEmpty) throw ApiChanged(_site, 'streamserver: no valid tc-hls tier of movie $movie: $streams');
    return List.unmodifiable(qualities);
  }

  /// Why a room known to be restricted (a list or search card, without a
  /// broadcast) is not played, or null when it is not restricted: the
  /// unified rule's error with its reason, without a request.
  static SiteError? restricted(LiveRoom room) => switch (room.restriction) {
    null || LiveRestriction.none => null,
    LiveRestriction.password => StreamUnavailable(_site, '${room.roomId}: password-protected (secret word)'),
    LiveRestriction.private => StreamUnavailable(_site, '${room.roomId}: a private broadcast'),
    final other => StreamUnavailable(_site, '${room.roomId}: ${other.name}'),
  };

  /// The one line of [quality] in [data]: its playlist with 3.x's media
  /// headers (no cookie). The URL carries no signature or expiry, so there
  /// is no lease; the segments need the `lvhls_ssid_{movie}` cookie the
  /// playlist sets, which the player keeps (REG-TWITCASTING-002, M7). A tier
  /// [data] does not offer is `StreamUnavailable`.
  static LivePlayUrlResolution resolution(TwitcastingRoomData data, LivePlayQuality quality) {
    final key = '${quality.selectionId}';
    final offered = qualities(data).where((option) => '${option.selectionId}' == key).firstOrNull;
    if (offered == null) throw StreamUnavailable(_site, 'streamserver: tier $key is not offered');
    final url = offered.data! as String;
    return LivePlayUrlResolution.lines([
      LivePlayLine(url, headers: headers, format: StreamFormat.hls, lineId: Uri.parse(url).host),
    ], appliedQualityData: key);
  }

  // Helpers -------------------------------------------------------------------

  /// 3.x's status rules; the channel page handles redirects itself.
  static void _checkStatus(int status, String what) {
    if (status == 200) return;
    throw switch (status) {
      401 || 403 => RiskControl(_site, detail: '$what: HTTP $status'),
      404 => NotFound(_site, '$what: HTTP 404'),
      429 => RateLimited(_site, detail: '$what: HTTP 429'),
      _ => NetworkFailure(_site, '$what: HTTP $status'),
    };
  }

  static Object? _decode(String body, String what) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
  }

  static Map<String, dynamic> _object(Object? value, String what) {
    if (value is! Map || value.keys.any((key) => key is! String)) throw ApiChanged(_site, '$what: not an object');
    return value.cast<String, dynamic>();
  }

  /// The decoded path segments of [uri] joined by `/`; null when a segment
  /// does not decode.
  static String? _segments(Uri uri) {
    try {
      return uri.pathSegments.join('/');
    } on FormatException {
      return null;
    }
  }

  /// 3.x's `text`: a trimmed string, '' for anything else.
  static String _text(Object? value) => value is String ? value.trim() : '';

  /// 3.x's `integer`: an int, or a string of one.
  static int? _integer(Object? value) => value is int ? value : (value is String ? int.tryParse(value) : null);

  static String _picture(Object? value) => value is String ? normalizeImageUrl(value) : '';
}

/// A start tag of an [_Html] page.
final class _Tag {
  new(this.name, this.attributes, this.contentStart);

  /// Lower-case element name.
  final String name;

  /// Attributes by lower-case name, values with character references decoded.
  final Map<String, String> attributes;

  /// Where the element's content starts (after `>`).
  final int contentStart;

  bool hasClass(String name) => (attributes['class'] ?? '').split(_Html._space).contains(name);
}

/// Just enough of an HTML reader for 3.x's selectors (tag, class, attribute,
/// descendant) on the TwitCasting pages; 3.x used package:html. Scripts,
/// styles and comments are blanked first, so markup inside them never
/// matches.
final class _Html {
  /// Reads [source]; line breaks are normalized first, as an HTML parser
  /// does (CR LF and CR become LF).
  factory(String source) {
    final normalized = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return _Html._(normalized.replaceAllMapped(_raw, (match) => ' ' * match.group(0)!.length), normalized);
  }

  new _(this.text, this._source);

  /// The page with scripts, styles and comments blanked.
  final String text;
  final String _source;
  final Map<_Tag, int> _ends = {};

  static final RegExp _space = RegExp(r'\s+');
  static final RegExp _raw = RegExp(r'<!--[\s\S]*?-->|<(script|style)\b[^>]*>[\s\S]*?</\1\s*>', caseSensitive: false);
  static final RegExp _startTag = RegExp('''<([a-zA-Z][a-zA-Z0-9-]*)((?:[^>"']|"[^"]*"|'[^']*')*)>''');
  static final RegExp _attribute = RegExp(r'''([^\s=/>"']+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+)))?''');
  static final RegExp _anyTag = RegExp('<[^>]*>');
  static final RegExp _tagToken = RegExp('''<(/?)([a-zA-Z][a-zA-Z0-9-]*)((?:[^>"']|"[^"]*"|'[^']*')*)>''');
  static const Set<String> _void = {
    'area',
    'base',
    'br',
    'col',
    'embed',
    'hr',
    'img',
    'input',
    'link',
    'meta',
    'source',
    'wbr',
  };

  /// Start tags between [from] and [to], in document order.
  Iterable<_Tag> tags({int from = 0, int? to}) sync* {
    for (final match in _startTag.allMatches(text, from)) {
      if (to != null && match.start >= to) return;
      final attributes = <String, String>{};
      for (final attribute in _attribute.allMatches(match.group(2)!)) {
        final value = attribute.group(2) ?? attribute.group(3) ?? attribute.group(4) ?? '';
        attributes.putIfAbsent(attribute.group(1)!.toLowerCase(), () => decodeHtmlEntities(value));
      }
      yield _Tag(match.group(1)!.toLowerCase(), attributes, match.end);
    }
  }

  /// The first tag passing [test], inside [within] when given.
  _Tag? first(bool Function(_Tag tag) test, {_Tag? within}) {
    for (final tag in _scope(within)) {
      if (test(tag)) return tag;
    }
    return null;
  }

  /// Every tag passing [test], inside [within] when given.
  List<_Tag> all(bool Function(_Tag tag) test, {_Tag? within}) => [
    for (final tag in _scope(within))
      if (test(tag)) tag,
  ];

  Iterable<_Tag> _scope(_Tag? within) => within == null ? tags() : tags(from: within.contentStart, to: _end(within));

  /// The text of [tag]'s element, character references decoded.
  String textOf(_Tag tag) => decodeHtmlEntities(_source.substring(tag.contentStart, _end(tag)).replaceAll(_anyTag, ''));

  /// The text directly inside [tag]'s element, not inside the elements it
  /// holds (scripts, styles and comments count as blank), character
  /// references decoded.
  String ownText(_Tag tag) {
    final end = _end(tag);
    final buffer = StringBuffer();
    var depth = 0;
    var position = tag.contentStart;
    for (final match in _tagToken.allMatches(text, tag.contentStart)) {
      if (match.start >= end) break;
      if (depth == 0) buffer.write(text.substring(position, match.start));
      position = match.end;
      final name = match.group(2)!.toLowerCase();
      if (match.group(1)!.isNotEmpty) {
        if (depth > 0) depth--;
      } else if (!_void.contains(name) && !match.group(3)!.trimRight().endsWith('/')) {
        depth++;
      }
    }
    if (depth == 0 && position < end) buffer.write(text.substring(position, end));
    return decodeHtmlEntities(buffer.toString());
  }

  /// Where [tag]'s element closes: its matching end tag, counting nested
  /// elements of the same name; the end of the page when it never closes.
  int _end(_Tag tag) => _ends[tag] ??= () {
    if (_void.contains(tag.name)) return tag.contentStart;
    final pattern = RegExp('<(/?)${RegExp.escape(tag.name)}(?=[\\s/>])[^>]*>', caseSensitive: false);
    var depth = 1;
    for (final match in pattern.allMatches(text, tag.contentStart)) {
      depth += match.group(1)!.isEmpty ? 1 : -1;
      if (depth == 0) return match.start;
    }
    return text.length;
  }();
}
