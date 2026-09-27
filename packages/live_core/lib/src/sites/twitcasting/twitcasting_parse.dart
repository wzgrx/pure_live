import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'twitcasting';

/// Pure parsing of TwitCasting responses (spec/sites/twitcasting.md).
abstract final class TwitcastingParse {
  /// §1 a channel id: an optional `c:`/`g:`/`f:`/`ig:` prefix and
  /// `[a-z0-9_]`, compared lower-case.
  static final RegExp channelPattern = RegExp(r'^(?:(?:c|g|f|ig):)?[a-z0-9_]{1,64}$');

  /// §1 site paths that are not channels.
  static const reserved = {
    'search', 'help', 'login', 'logout', 'settings', 'signup', 'register', 'terms', 'privacy', //
    'about', 'index', 'show', 'categories', 'indexcaslist.php', 'streamserver.php',
  };

  /// §5 quality keys in `tc-hls.streams`, best first.
  static const qualityKeys = ['high', 'medium', 'low'];

  static const _labels = {'high': '高', 'medium': '中', 'low': '低'};

  static Object? _json(String body, String what) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
  }

  static void _status(int status, String what) {
    if (status == 429) throw RateLimited(_site, detail: '$what HTTP 429');
    if (status == 401 || status == 403) throw RiskControl(_site, detail: '$what HTTP $status');
    if (status == 404) throw NotFound(_site, '$what HTTP 404');
    if (status >= 500) throw NetworkFailure(_site, '$what HTTP $status');
  }

  /// §1 a channel id, lower-cased, or null.
  static String? channel(String? value) {
    final text = value?.trim().toLowerCase();
    return text != null && channelPattern.hasMatch(text) && !reserved.contains(text) ? text : null;
  }

  /// `//host/…` gets `https:`.
  static Uri? picture(Object? value) {
    var text = jsonString(value);
    if (text == null) return null;
    if (text.startsWith('//')) text = 'https:$text';
    return jsonUrl(text);
  }

  static String _textOf(String html) =>
      decodeHtmlEntities(html.replaceAll(RegExp('<[^>]+>'), ' ')).replaceAll(RegExp(r'\s+'), ' ').trim();

  /// §2.1 the homepage's top tabs (`a.tw-top-tab-item[data-channel]`) as the
  /// areas of one category, in page order.
  static List<Category> categories(String html, {int status = 200}) {
    _status(status, 'home');
    final areas = <Area>[];
    final seen = <String>{};
    for (final match in RegExp(r'<a\b([^>]*)>([\s\S]*?)</a>').allMatches(html)) {
      final attributes = match.group(1)!;
      if (!attributes.contains('tw-top-tab-item')) continue;
      final key = RegExp('data-channel="([A-Za-z0-9_]{1,80})"').firstMatch(attributes)?.group(1);
      final label = _textOf(match.group(2)!);
      if (key == null || label.isEmpty || !seen.add(key)) continue;
      areas.add(Area(id: key, name: label, categoryId: 'genre'));
    }
    if (areas.isEmpty) throw const ApiChanged(_site, 'home: no category tabs');
    return [Category(id: 'genre', name: 'TwitCasting', areas: areas)];
  }

  /// §2.2 `top/category`: one window of up to 60 live broadcasts; locked,
  /// group and deleted ones are skipped. [now] turns `elapsed_time` into a
  /// start time.
  static Page<RoomCard> topPage(String body, {DateTime? now, int status = 200}) {
    _status(status, 'top/category');
    final root = _json(body, 'top/category');
    final movies = root is Map && root['movies'] is List ? root['movies'] as List : null;
    if (movies == null) throw const ApiChanged(_site, 'top/category: no movies');
    final seen = <String>{};
    final rooms = <RoomCard>[];
    for (final movie in movies) {
      if (movie is! Map ||
          movie['is_live'] != true ||
          movie['is_locked'] == true ||
          movie['is_group'] == true ||
          movie['is_deleted'] == true) {
        continue;
      }
      final id = channel(jsonString(movie['user_id']));
      if (id == null || !seen.add(id)) continue;
      final viewers = jsonInt(movie['current_viewer_count']);
      final elapsed = jsonInt(movie['elapsed_time']);
      rooms.add(
        RoomCard(
          ref: RoomRef(_site, id),
          title: decodeHtmlEntities(jsonString(movie['telop']) ?? jsonString(movie['title']) ?? ''),
          anchorName: jsonString(movie['user_name']) ?? id,
          state: LiveState.live,
          cover: picture(movie['thumbnail_url']),
          audience: Audience(online: viewers != null && viewers >= 0 ? viewers : null),
          avatar: picture(movie['user_icon_url']),
          liveSince: now != null && elapsed != null && elapsed >= 0 ? now.subtract(Duration(seconds: elapsed)) : null,
        ),
      );
    }
    return Page(rooms);
  }

  /// §3 the live section of a text search page (`#tw-search-result-live`).
  static Page<RoomCard> searchPage(String html, {int status = 200}) {
    _status(status, 'search');
    final start = html.indexOf('id="tw-search-result-live"');
    if (start < 0) throw const ApiChanged(_site, 'search: no live section');
    final end = html.indexOf('id="tw-search-result-movie"', start);
    final section = html.substring(start, end < 0 ? html.length : end);
    final rooms = <RoomCard>[];
    final seen = <String>{};
    for (final row in section.split('class="tw-search-result-row"').skip(1)) {
      if (!row.contains('data-status="live"')) continue;
      final href = RegExp(r'class="usertext">\s*<a href="/([^"/]+)"').firstMatch(row)?.group(1);
      final id = channel(href);
      if (id == null || !seen.add(id)) continue;
      final title = RegExp(r'class="tw-movie-thumbnail-title">([\s\S]*?)</span>').firstMatch(row)?.group(1);
      final name = RegExp(r'class="username">([\s\S]*?)</span>').firstMatch(row)?.group(1);
      rooms.add(
        RoomCard(
          ref: RoomRef(_site, id),
          title: title == null ? '' : _textOf(title),
          anchorName: name == null ? id : _textOf(name),
          state: LiveState.live,
          cover: picture(RegExp('class="tw-movie-thumbnail2-image" src="([^"]+)"').firstMatch(row)?.group(1)),
          avatar: picture(RegExp(r'class="userimage32">[\s\S]*?<img src="([^"]+)"').firstMatch(row)?.group(1)),
        ),
      );
    }
    return Page(rooms);
  }

  static String? _meta(String html, String key) {
    final match = RegExp('<meta (?:name|property)="${RegExp.escape(key)}" content="([^"]*)"').firstMatch(html);
    return match == null ? null : decodeHtmlEntities(match.group(1)!).trim();
  }

  /// §4 the room from the channel page and `streamserver.php`. A page that
  /// asks for a secret word is a protected broadcast.
  static RoomDetail detail(String html, String streamBody, {required String id, int pageStatus = 200}) {
    if (pageStatus >= 300 && pageStatus < 400) throw const NotFound(_site, 'channel page redirected');
    _status(pageStatus, 'channel page');
    if (html.contains('Enter the secret word to access')) throw const NeedsLogin(_site, 'secret word');
    final creator = channel(_meta(html, 'twitter:creator'));
    if (creator != id) throw ApiChanged(_site, 'channel page of $creator for $id');
    final state = liveOf(streamBody);
    final name = RegExp('class="tw-user-nav2-name">([^<]*)<').firstMatch(html)?.group(1);
    final avatar = picture(
      RegExp(r'class="tw-user-nav2-icon"[\s\S]{0,400}?<img src="([^"]+)"').firstMatch(html)?.group(1),
    );
    final telop = _meta(html, 'twitter:description');
    final title = telop != null && telop.isNotEmpty ? telop : _meta(html, 'twitter:title') ?? '';
    final movie = RegExp(r'data-movie-id="(\d+)"').firstMatch(html)?.group(1);
    return RoomDetail(
      card: RoomCard(
        ref: RoomRef(_site, id),
        title: title,
        anchorName: name == null ? id : decodeHtmlEntities(name).trim(),
        state: state.live ? LiveState.live : LiveState.offline,
        cover: picture(_meta(html, 'og:image')),
        avatar: avatar,
      ),
      link: Uri.parse('https://twitcasting.tv/$id'),
      avatar: avatar,
      danmakuKeys: {if (state.live) 'movieId': ?(state.movie ?? movie)},
    );
  }

  /// §4 `streamserver.php`: whether the channel is live and its movie id;
  /// `{}` is a channel that does not exist.
  static ({bool live, String? movie}) liveOf(String body, {int status = 200}) {
    _status(status, 'streamserver');
    final root = _json(body, 'streamserver');
    if (root is Map && root.isEmpty) throw const NotFound(_site, 'streamserver: {}');
    final movie = root is Map ? root['movie'] : null;
    if (movie is! Map || movie['live'] is! bool) throw const ApiChanged(_site, 'streamserver: no movie.live');
    return (live: movie['live'] == true, movie: jsonInt(movie['id'])?.toString());
  }

  /// §5 the `tc-hls` streams of a live channel: one quality per key (high,
  /// medium, low), one line each. Offline answers carry stale URLs of
  /// another broadcast and never play.
  static StreamSet streams(String body, {required Map<String, String> headers, String? wanted, int status = 200}) {
    final state = liveOf(body, status: status);
    if (!state.live) throw const StreamUnavailable(_site, 'channel is offline');
    final root = _json(body, 'streamserver')! as Map;
    final hls = root['tc-hls'];
    final streams = hls is Map && hls['streams'] is Map ? hls['streams'] as Map : const <Object?, Object?>{};
    final offered = <({Quality quality, Uri url})>[];
    for (final (index, key) in qualityKeys.indexed) {
      final url = jsonUrl(streams[key]);
      if (url == null ||
          !(url.host == 'twitcasting.tv' || url.host.endsWith('.twitcasting.tv')) ||
          !url.path.startsWith('/tc.livehls/v1/streams/${state.movie}/')) {
        continue;
      }
      offered.add((quality: Quality(id: key, label: _labels[key]!, rank: qualityKeys.length - index), url: url));
    }
    if (offered.isEmpty) throw const StreamUnavailable(_site, 'no tc-hls stream');
    final chosen = offered.where((o) => o.quality.id == wanted).firstOrNull ?? offered.first;
    return StreamSet(
      qualities: [for (final o in offered) o.quality],
      selected: chosen.quality,
      lines: [
        StreamLine(
          url: chosen.url,
          format: StreamFormat.hls,
          lineId: chosen.url.host,
          requested: chosen.quality,
          confirmed: chosen.quality,
          headers: headers,
        ),
      ],
    );
  }

  /// §7.1 the comment socket URL of `eventpubsuburl.php`.
  static Uri? commentSocket(String body) {
    try {
      final root = jsonDecode(body);
      final url = root is Map ? Uri.tryParse('${root['url'] ?? ''}') : null;
      return url != null && url.scheme == 'wss' && url.host.endsWith('twitcasting.tv') ? url : null;
    } on FormatException {
      return null;
    }
  }

  /// §1 the channel of an input: a channel id or `twitcasting.tv/<id>`
  /// (also inside share text); movie links name an old broadcast and are
  /// not channels.
  static String? channelOf(String input) {
    final text = input.trim();
    final bare = channel(text);
    if (bare != null && !text.contains('/')) return bare;
    final match = RegExp(r'https?://[^\s，。！？、]+').firstMatch(text);
    final url = Uri.tryParse(match?.group(0) ?? text);
    if (url == null || !const {'twitcasting.tv', 'www.twitcasting.tv'}.contains(url.host.toLowerCase())) return null;
    final segments = url.pathSegments.where((segment) => segment.isNotEmpty).toList();
    return segments.length == 1 ? channel(segments.single) : null;
  }
}
