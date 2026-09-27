import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'acfun';

/// Rooms a directory request asks for (spec/sites/acfun.md §2.2).
const acfunPageSize = 30;

/// Users a search page holds (spec §3).
const acfunSearchPageSize = 30;

/// The anonymous visitor session of `visitor/login` (spec §6.1).
typedef AcfunVisitor = ({String userId, String token, String security});

/// What `startPlay` gives for a live room (spec §6.2).
typedef AcfunPlay = ({
  String liveId,
  List<Quality> qualities,
  Map<String, List<Uri>> urls,
  List<String> tickets,
  String? attach,
});

/// Pure parsing of AcFun responses (spec/sites/acfun.md). Every function
/// takes the raw response text and returns domain values or throws a
/// `SiteError`.
abstract final class AcfunParse {
  static Object? _json(String body, String what) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
  }

  static Map<String, dynamic> _map(Object? value, String what) {
    if (value is Map<String, dynamic>) return value;
    throw ApiChanged(_site, '$what: expected an object');
  }

  static List<dynamic> _list(Object? value, String what) {
    if (value is List) return value;
    throw ApiChanged(_site, '$what: expected a list');
  }

  /// An author id (the room id): a positive decimal number.
  static bool isAuthor(String value) => RegExp(r'^[1-9]\d{0,19}$').hasMatch(value);

  static Uri? _image(Object? value) {
    var text = jsonString(value);
    if (text == null) return null;
    if (text.startsWith('//')) text = 'https:$text';
    return jsonUrl(text);
  }

  /// §2.1 `channelFilters`: the area filters (type, id) except `全部`.
  static List<Area> areas(String body) {
    final root = _map(_json(body, 'channel/list'), 'channel/list');
    final filters = _map(root['channelFilters'], 'channelFilters');
    final seen = <String>{};
    return [
      for (final group in _list(filters['liveChannelDisplayFilters'], 'liveChannelDisplayFilters'))
        if (group is Map)
          for (final filter in _list(group['displayFilters'] ?? const [], 'displayFilters'))
            if (filter is Map)
              if ((jsonInt(filter['filterType']), jsonInt(filter['filterId'])) case (final type?, final id?)
                  when id != 0 && seen.add('$type:$id'))
                Area(
                  id: '$id',
                  name: jsonString(filter['name']) ?? '$id',
                  categoryId: '$type',
                  icon: _image(filter['cover']),
                ),
    ];
  }

  /// §2.2 the `filters` query value of an area.
  static String filterQuery(Area area) => jsonEncode([
    {'filterType': int.tryParse(area.categoryId) ?? 1, 'filterId': int.tryParse(area.id) ?? 0},
  ]);

  static RoomCard _card(Map<dynamic, dynamic> item, {required String author}) {
    final user = item['user'] is Map ? item['user'] as Map : const <String, dynamic>{};
    final covers = item['coverUrls'];
    final type = item['type'];
    final created = jsonInt(item['createTime']);
    return RoomCard(
      ref: RoomRef(_site, author),
      title: decodeHtmlEntities(jsonString(item['title']) ?? ''),
      anchorName: decodeHtmlEntities(jsonString(user['name']) ?? ''),
      state: jsonString(item['liveId']) == null ? LiveState.offline : LiveState.live,
      cover: covers is List && covers.isNotEmpty ? _image(covers.first) : null,
      area: type is Map ? jsonString(type['name']) : null,
      audience: Audience(online: jsonInt(item['onlineCount'])),
      liveSince: created == null || created <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(created, isUtc: true),
      avatar: _image(user['headUrl']),
    );
  }

  /// §2.2/§2.3 `api/channel/list`: live rooms; the next page is the opaque
  /// `pcursor`, `no_more` (or empty) ends the list.
  static Page<RoomCard> listPage(String body) {
    final root = _map(_json(body, 'channel/list'), 'channel/list');
    final data = _map(root['channelListData'] ?? root, 'channelListData');
    if (jsonInt(data['result']) != 0) throw ApiChanged(_site, 'channel/list result ${data['result']}');
    final rooms = <RoomCard>[
      for (final item in _list(data['liveList'] ?? const [], 'liveList'))
        if (item is Map)
          if (jsonString(item['authorId']) case final author? when isAuthor(author)) _card(item, author: author),
    ];
    final cursor = jsonString(data['pcursor']);
    final more = rooms.isNotEmpty && cursor != null && cursor != 'no_more';
    return Page(rooms, next: more ? PageCursor(cursor) : null);
  }

  static final _searchCard = RegExp(
    r'''<div class="search-up" data-up-exposure-log='(\{[^']*\})'>([\s\S]*?)(?=<div class="search-up" |$)''',
  );
  static final _name = RegExp(r'up__main__name[^>]*>\s*<a [^>]*href="/u/(\d+)"[^>]*>([^<]*)</a>');
  static final _avatar = RegExp('<img class="up__avatar[^"]*" src="([^"]*)"');
  static final _intro = RegExp('<div class="up__main__intro[^"]*">([^<]*)</div>');
  static final _total = RegExp(r'data-total="(\d*)"');

  /// §3 `www.acfun.cn/search?type=user&ajaxpipe=1`: authors (live or not)
  /// from the page fragment in `html`; ends when a page is empty or the
  /// pages reach `data-total`.
  static Page<RoomCard> searchPage(String body, {required int page}) {
    final end = body.indexOf('/*<!-- fetch-stream -->*/');
    final root = _map(_json(end < 0 ? body : body.substring(0, end), 'search'), 'search');
    final html = root['html'];
    if (html is! String) throw const ApiChanged(_site, 'search: no html');
    final total = int.tryParse(_total.firstMatch(html)?.group(1) ?? '') ?? 0;
    final rooms = <RoomCard>[];
    final seen = <String>{};
    for (final card in _searchCard.allMatches(html)) {
      Map<String, dynamic> log;
      try {
        log = _map(jsonDecode(decodeHtmlEntities(card.group(1)!)), 'search card');
      } on FormatException {
        continue;
      }
      final author = jsonString(log['up_id']);
      final name = _name.firstMatch(card.group(2)!);
      if (author == null || !isAuthor(author) || name == null || !seen.add(author)) continue;
      final live = jsonString(log['is_on_live']) != null;
      final intro = _intro.firstMatch(card.group(2)!)?.group(1)?.trim();
      rooms.add(
        RoomCard(
          ref: RoomRef(_site, author),
          title: decodeHtmlEntities(intro ?? ''),
          anchorName: decodeHtmlEntities(name.group(2)!.trim()),
          state: live ? LiveState.live : LiveState.offline,
          avatar: _image(_avatar.firstMatch(card.group(2)!)?.group(1)),
        ),
      );
    }
    final more = rooms.isNotEmpty && page * acfunSearchPageSize < total;
    return Page(rooms, next: more ? PageCursor('${page + 1}') : null);
  }

  /// §4 `api/live/info?authorId=`: the room; `user.id == "0"` is an unknown
  /// author, no `liveId` a room that is not broadcasting.
  static RoomDetail detail(String body, {required String author}) {
    final root = _map(_json(body, 'live/info'), 'live/info');
    final user = root['user'];
    if (user is! Map || user.isEmpty) throw NotFound(_site, 'live/info: no user for $author');
    final id = jsonString(user['id']);
    if (id == null || id == '0' || jsonString(user['name']) == null) {
      throw NotFound(_site, 'live/info: unknown author $author');
    }
    if (jsonInt(root['result']) != 0) throw ApiChanged(_site, 'live/info result ${root['result']}');
    if (id != author) throw ApiChanged(_site, 'live/info answered author $id for $author');
    final card = _card(root, author: author);
    final signature = jsonString(user['signature']);
    return RoomDetail(
      card: card,
      link: Uri.parse('https://live.acfun.cn/live/$author'),
      avatar: card.avatar,
      introduction: signature == null ? null : decodeHtmlEntities(signature),
      danmakuKeys: {'author': author, 'liveId': ?jsonString(root['liveId'])},
    );
  }

  /// §6.1 `visitor/login`: the anonymous session.
  static AcfunVisitor visitor(String body) {
    final root = _map(_json(body, 'visitor/login'), 'visitor/login');
    if (jsonInt(root['result']) != 0) throw RiskControl(_site, detail: 'visitor/login result ${root['result']}');
    final userId = jsonString(root['userId']);
    final token = jsonString(root['acfun.api.visitor_st']);
    final security = jsonString(root['acSecurity']);
    if (userId == null || token == null || security == null) {
      throw const ApiChanged(_site, 'visitor/login: incomplete session');
    }
    return (userId: userId, token: token, security: security);
  }

  /// §6.2 `startPlay`: `result == 1` is live; 129004 (`直播已关播`) has no
  /// stream. Qualities by `level`, best first; URLs by quality, one per
  /// adaptive manifest (CDN).
  static AcfunPlay play(String body, {int status = 200}) {
    if (status >= 500) throw NetworkFailure(_site, 'startPlay HTTP $status');
    final root = _map(_json(body, 'startPlay'), 'startPlay');
    final result = jsonInt(root['result']);
    if (result == 129004) throw StreamUnavailable(_site, 'startPlay: ${root['error_msg'] ?? 'closed'}');
    if (result != 1) {
      throw RiskControl(_site, detail: 'startPlay result $result: ${jsonString(root['error_msg']) ?? ''}');
    }
    final data = _map(root['data'], 'startPlay.data');
    final liveId = jsonString(data['liveId']);
    if (liveId == null) throw const ApiChanged(_site, 'startPlay: no liveId');
    var res = data['videoPlayRes'];
    if (res is String) res = _json(res, 'videoPlayRes');
    final manifests = _list(_map(res, 'videoPlayRes')['liveAdaptiveManifest'], 'liveAdaptiveManifest');
    final levels = <String, ({String label, int level})>{};
    final urls = <String, List<Uri>>{};
    for (final manifest in manifests) {
      final set = manifest is Map ? manifest['adaptationSet'] : null;
      for (final item in set is Map ? (set['representation'] as List?) ?? const [] : const []) {
        if (item is! Map || item['hidden'] == true) continue;
        final url = jsonUrl(item['url']);
        final id = jsonString(item['qualityType']) ?? jsonString(item['id']);
        if (url == null || id == null) continue;
        levels.putIfAbsent(
          id,
          () => (label: jsonString(item['name']) ?? id, level: jsonInt(item['level']) ?? jsonInt(item['bitrate']) ?? 0),
        );
        (urls[id] ??= []).add(url);
      }
    }
    if (levels.isEmpty) throw const StreamUnavailable(_site, 'startPlay: no representation');
    final ordered = levels.entries.toList()..sort((a, b) => b.value.level.compareTo(a.value.level));
    final tickets = data['availableTickets'];
    return (
      liveId: liveId,
      qualities: [
        for (final (index, entry) in ordered.indexed)
          Quality(id: entry.key, label: entry.value.label, rank: ordered.length - index),
      ],
      urls: urls,
      tickets: [for (final ticket in tickets is List ? tickets : const []) ?jsonString(ticket)],
      attach: jsonString(data['enterRoomAttach']),
    );
  }

  /// §6.3 lease: the first field of `auth_key` is the expiry (30 days out
  /// at issue); connections are not known to be cut, the lease only renews
  /// the URL for new connections. No key or one already past: null.
  static Lease? lease(Uri url, DateTime issuedAt) {
    final expiry = int.tryParse(url.queryParameters['auth_key']?.split('-').first ?? '');
    if (expiry == null) return null;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true);
    final lifetime = expiresAt.difference(issuedAt);
    if (lifetime <= Duration.zero) return null;
    final lead = lifetime ~/ 4 < const Duration(minutes: 10) ? lifetime ~/ 4 : const Duration(minutes: 10);
    return Lease(refreshAt: expiresAt.subtract(lead), expiresAt: expiresAt, cutsConnection: false);
  }

  /// §6.4 container by the URL path.
  static StreamFormat format(Uri url) => url.path.toLowerCase().endsWith('.m3u8') ? StreamFormat.hls : StreamFormat.flv;
}
