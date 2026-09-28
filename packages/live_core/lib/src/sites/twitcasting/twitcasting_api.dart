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
  const new({required this.live, this.movieId, this.streams = const {}});

  /// `movie.live`: whether the channel is broadcasting.
  final bool live;

  /// `movie.id`: the broadcast (a new one each time the channel goes live).
  final int? movieId;

  /// `tc-hls.streams` of a live channel by tier (`high`, `medium`, `low`),
  /// as answered and not yet checked; null when the answer had none. Empty
  /// when offline.
  final Map<String, String>? streams;
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

  /// Tiers of `tc-hls.streams`, best first.
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

  /// Rows [offset] to [offset] + [pageSize] of the `top/category` window,
  /// as 3.x sliced it; locked, group, deleted and ended broadcasts are left
  /// out after slicing, repeated channels too. Anything else irregular fails
  /// the list (`ApiChanged`), never an empty or partial one (3.x).
  static List<LiveRoom> directory(String body, {required int offset, required int pageSize, int status = 200}) {
    _checkStatus(status, 'top/category');
    final rows = _object(_decode(body, 'top/category'), 'top/category')['movies'];
    if (rows is! List || rows.length > directoryWindow) {
      throw ApiChanged(_site, 'top/category: movies is ${rows is List ? '${rows.length} rows' : rows.runtimeType}');
    }
    final rooms = <String, LiveRoom>{};
    for (final raw in rows.skip(offset).take(pageSize)) {
      final row = _object(raw, 'top/category row');
      for (final flag in ['is_live', 'is_locked', 'is_group', 'is_deleted']) {
        if (row[flag] is! bool) throw ApiChanged(_site, 'top/category: $flag is ${row[flag]}');
      }
      if (row['is_live'] != true ||
          row['is_locked'] != false ||
          row['is_group'] != false ||
          row['is_deleted'] != false) {
        continue;
      }
      final channel = channelName(_text(row['user_id']));
      final movie = _integer(row['id']);
      final link = Uri.tryParse(_text(row['live_url']));
      if (channel == null ||
          movie == null ||
          movie <= 0 ||
          link == null ||
          link.hasAuthority ||
          link.hasQuery ||
          link.hasFragment ||
          _segments(link) != '$channel/movie/$movie') {
        throw ApiChanged(_site, 'top/category: row ${row['user_id']} ${row['id']} ${row['live_url']}');
      }
      final count = _integer(row['current_viewer_count']);
      if (count == null || count < 0) throw ApiChanged(_site, 'top/category: viewers of $channel');
      final telop = _text(row['telop']);
      rooms.putIfAbsent(
        channel,
        () => LiveRoom(
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
        ),
      );
    }
    return [...rooms.values];
  }

  // Search --------------------------------------------------------------------

  /// Page [page] of [pageSize] rows of the search page's live section
  /// (`#tw-search-result-live`; the user, Premier and recording sections are
  /// not live). Rows are sliced as 3.x did; a row the site marks as not
  /// playable (a private broadcast: no LIVE badge, `data-can-play="false"`)
  /// is left out, where 3.x failed the whole page. A page without the live
  /// section (a challenge) or with a malformed live row is `ApiChanged`.
  /// No audience: the page shows comments, not viewers.
  static List<LiveRoom> searchRooms(String body, {required int page, required int pageSize, int status = 200}) {
    _checkStatus(status, 'search');
    final html = _Html(body);
    final section = html.first((tag) => tag.attributes['id'] == 'tw-search-result-live');
    if (section == null) throw const ApiChanged(_site, 'search: no live section');
    final rows = html.all((tag) => tag.hasClass('tw-search-result-row'), within: section);
    if (rows.length > searchWindow) throw ApiChanged(_site, 'search: ${rows.length} live rows');
    final rooms = <String, LiveRoom>{};
    for (final row in rows.skip((page - 1) * pageSize).take(pageSize)) {
      final live = html.first(
        (tag) => tag.hasClass('tw-movie-thumbnail2-badge') && tag.attributes['data-status'] == 'live',
        within: row,
      );
      final playable = html.first(
        (tag) => tag.hasClass('tw-movie-thumbnail2-image-wrapper') && tag.attributes['data-can-play'] == 'true',
        within: row,
      );
      if (live == null || playable == null) continue;
      final user = html.first((tag) => tag.hasClass('tw-search-result-row-user-name'), within: row);
      final userText = user == null ? null : html.first((tag) => tag.hasClass('usertext'), within: user);
      final channelHref = userText == null ? null : html.first((tag) => tag.name == 'a', within: userText);
      final movieHref = html.first((tag) => tag.name == 'a' && tag.hasClass('tw-movie-thumbnail2'), within: row);
      final channel = _searchChannel(movieHref?.attributes['href'] ?? '', channelHref?.attributes['href'] ?? '');
      final title = html.first((tag) => tag.hasClass('tw-movie-thumbnail-title'), within: row);
      final name = user == null ? null : html.first((tag) => tag.hasClass('username'), within: user);
      final cover = html.first((tag) => tag.hasClass('tw-movie-thumbnail2-image'), within: row);
      final avatarBox = html.first((tag) => tag.hasClass('userimage32'), within: row);
      final avatar = avatarBox == null ? null : html.first((tag) => tag.name == 'img', within: avatarBox);
      rooms.putIfAbsent(
        channel,
        () => LiveRoom(
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
        ),
      );
    }
    return [...rooms.values];
  }

  /// The channel of a live search row: `/{channel}` and
  /// `/{channel}/movie/{movie}` must agree (3.x's checks).
  static String _searchChannel(String movieHref, String channelHref) {
    ApiChanged malformed() => ApiChanged(_site, 'search: row links $movieHref $channelHref');
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
      throw malformed();
    }
    try {
      final channelParts = channelUri.pathSegments;
      final movieParts = movieUri.pathSegments;
      if (channelParts.length != 1 || movieParts.length != 3) throw malformed();
      final channel = channelName(channelParts.single);
      final movie = _integer(movieParts.last);
      if (channel == null ||
          movieParts.first.toLowerCase() != channel ||
          movieParts[1] != 'movie' ||
          movie == null ||
          movie <= 0) {
        throw malformed();
      }
      return channel;
    } on FormatException {
      throw malformed();
    }
  }

  // Rooms ---------------------------------------------------------------------

  /// The channel page of [channel] ([roomId] as the user asked for it): who
  /// the channel is, before its broadcast state is asked for.
  ///
  /// - A redirect is an unknown channel: the site sends it to the homepage
  ///   (3.x followed it and reported a schema failure);
  /// - a page asking for the secret word is a protected broadcast
  ///   (`NeedsLogin`);
  /// - the `twitter:creator` meta and the header's `data-user-id` must name
  ///   [channel] (`ApiChanged`).
  ///
  /// The title is the page's `twitter:title`, as 3.x showed it ("Live #…"
  /// when the streamer set none); the broadcast's telop (`twitter:
  /// description`) only fills an empty one (REG-TWITCASTING-004 kept).
  static LiveRoom channelPage(String body, {required String roomId, required String channel, int status = 200}) {
    if (status >= 300 && status < 400) throw NotFound(_site, 'channel page of $channel: HTTP $status (sent home)');
    _checkStatus(status, 'channel page');
    if (body.contains('Enter the secret word to access')) {
      throw NeedsLogin(_site, 'channel $channel: the broadcast asks for a secret word');
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
    final name = page.first((tag) => tag.hasClass('tw-user-nav2-name'));
    final icon = page.first((tag) => tag.hasClass('tw-user-nav2-icon'));
    final avatar = icon == null ? null : page.first((tag) => tag.name == 'img', within: icon);
    return LiveRoom(
      roomId: roomId,
      platform: _site,
      userId: channel,
      link: '$origin/$channel',
      title: title.trim().isEmpty ? (meta('name', 'twitter:description') ?? '').trim() : title,
      nick: name == null ? channel : page.textOf(name).trim(),
      avatar: _picture(avatar?.attributes['src']),
      cover: _picture(meta('property', 'og:image')),
      watching: '',
    );
  }

  /// `streamserver.php`: the broadcast state and, when live, its HLS tiers
  /// (checked only when played). `{}` is a channel that does not exist; no
  /// boolean `movie.live` is `ApiChanged`.
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

  /// [room] in the state [stream] reports, carrying it for the streams.
  static LiveRoom roomDetail(LiveRoom room, TwitcastingRoomData stream) =>
      room.copyWith(liveStatus: stream.live ? LiveStatus.live : LiveStatus.offline, data: stream);

  // Streams -------------------------------------------------------------------

  /// 3.x's qualities: one per tier of `tc-hls.streams`, labelled `HLS high`,
  /// `HLS medium`, `HLS low`, best first. A channel that is not broadcasting
  /// has none (`StreamUnavailable`); a tier URL that is not an https
  /// `*.twitcasting.tv` playlist of this broadcast, or no tier at all, is
  /// `ApiChanged` (3.x rejected the whole answer).
  static List<LivePlayQuality> qualities(TwitcastingRoomData data) {
    if (!data.live) throw const StreamUnavailable(_site, 'streamserver: not broadcasting');
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
        throw ApiChanged(_site, 'streamserver: $key is not a playlist of movie $movie: $url');
      }
      qualities.add(LivePlayQuality(id: key, quality: 'HLS $key', sort: 3 - qualities.length, data: url));
    }
    if (qualities.isEmpty) throw ApiChanged(_site, 'streamserver: no tc-hls tier of movie $movie');
    return List.unmodifiable(qualities);
  }

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
