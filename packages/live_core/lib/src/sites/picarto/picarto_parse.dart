import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/hls_playlist.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'picarto';

/// Pure parsing of Picarto responses (spec/sites/picarto.md).
abstract final class PicartoParse {
  /// §1 a channel name.
  static final RegExp namePattern = RegExp(r'^[A-Za-z0-9_]{1,50}$');

  /// §1 site paths that are not channels.
  static const reserved = {
    'explore', 'search', 'settings', 'login', 'signup', 'register', 'password', 'terms', 'privacy', //
    'help', 'about', 'videos', 'communities', 'subscriptions', 'following', 'shop', 'commissions',
  };

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

  static Map<String, dynamic> _root(String body, {required String what, int status = 200}) {
    if (status == 429) throw RateLimited(_site, detail: '$what HTTP 429');
    if (status == 401 || status == 403) throw RiskControl(_site, detail: '$what HTTP $status');
    if (status == 404) throw NotFound(_site, '$what HTTP 404');
    if (status >= 500) throw NetworkFailure(_site, '$what HTTP $status');
    if (status < 200 || status >= 300) throw ApiChanged(_site, '$what HTTP $status');
    return _map(_json(body, what), what);
  }

  /// §2.1 `api/languages-categories`: one category holding the platform's
  /// categories in response order.
  static List<Category> categories(String body, {int status = 200}) {
    final root = _root(body, what: 'languages-categories', status: status);
    return [
      Category(
        id: 'category',
        name: 'Picarto',
        areas: [
          for (final raw in _list(root['categories'], 'categories'))
            if (raw is Map && jsonInt(raw['id']) != null && jsonString(raw['label']) != null)
              Area(id: '${jsonInt(raw['id'])}', name: jsonString(raw['label'])!, categoryId: 'category'),
        ],
      ),
    ];
  }

  static RoomCard? _card(Map<dynamic, dynamic> row) {
    final name = jsonString(row['name']);
    if (name == null || !namePattern.hasMatch(name)) return null;
    final online = row['online'] == true;
    final viewers = jsonInt(row['viewers']);
    final categories = row['categories'];
    return RoomCard(
      ref: RoomRef(_site, name),
      title: decodeHtmlEntities(jsonString(row['title']) ?? name),
      anchorName: name,
      state: online ? LiveState.live : LiveState.offline,
      cover: jsonUrl(row['image_thumbnail']) ?? jsonUrl(row['thumbnail_image']),
      area: categories is List
          ? categories.whereType<Map<dynamic, dynamic>>().map((c) => jsonString(c['name'])).nonNulls.join(' / ')
          : null,
      audience: Audience(online: online && viewers != null && viewers >= 0 ? viewers : null),
      avatar: jsonUrl(row['avatar']),
    );
  }

  /// §2.2 an `api/explore` page: live, non-adult channels (the request
  /// filters adult; rows marked adult are dropped anyway). Ends at
  /// `last_page` or on an empty page.
  static Page<RoomCard> explorePage(String body, {required int page, int status = 200}) {
    final root = _root(body, what: 'explore', status: status);
    final rows = _list(root['data'] ?? const [], 'explore.data');
    final seen = <String>{};
    final rooms = [
      for (final row in rows)
        if (row is Map && row['adult'] != true && row['online'] == true)
          if (_card(row) case final card? when seen.add(card.ref.roomId.toLowerCase())) card,
    ];
    final last = jsonInt(root['last_page']) ?? page;
    return Page(rooms, next: rows.isNotEmpty && page < last ? PageCursor('${page + 1}') : null);
  }

  /// §3 an `api/search` (`searchProfiles`) page: live and offline
  /// channels; the title is the name (profiles have no stream title). The
  /// `count` is not reliable, so a full page means "maybe more".
  static Page<RoomCard> searchPage(String body, {required int page, required int size, int status = 200}) {
    final root = _root(body, what: 'search', status: status);
    final result = _map(root['searchProfiles'], 'searchProfiles');
    final rows = _list(result['data'] ?? const [], 'searchProfiles.data');
    final seen = <String>{};
    final rooms = [
      for (final row in rows)
        if (row is Map)
          if (_card(row) case final card? when seen.add(card.ref.roomId.toLowerCase())) card,
    ];
    return Page(rooms, next: rows.length >= size ? PageCursor('${page + 1}') : null);
  }

  /// §4 `api/channel/detail/<name>`: the room and, when live, the HLS
  /// master URL on the load balancer's edge.
  static ({RoomDetail detail, Uri? master}) detail(String body, {int status = 200}) {
    final root = _root(body, what: 'channel/detail', status: status);
    final channel = root['channel'];
    if (channel == null) throw const NotFound(_site, 'channel/detail: channel is null');
    final map = _map(channel, 'channel/detail.channel');
    final card = _card(map);
    if (card == null) throw const ApiChanged(_site, 'channel/detail: bad name');
    final id = jsonInt(map['id']);
    final total = jsonInt(map['total_views']);
    final descriptions = map['descriptions'];
    final intro = descriptions is List
        ? descriptions
              .whereType<Map<dynamic, dynamic>>()
              .map((d) => jsonString(d['body']))
              .nonNulls
              .map(decodeHtmlEntities)
              .join('\n\n')
        : null;
    Uri? master;
    if (card.state == LiveState.live) {
      final balancer = root['getLoadBalancerUrl'];
      final origin = balancer is Map ? jsonString(balancer['origin']) : null;
      final multi = root['getMultiStreams'];
      final streams = multi is Map && multi['streams'] is List ? multi['streams'] as List : const <Object?>[];
      final own = streams.whereType<Map<dynamic, dynamic>>().where((s) => jsonInt(s['channelId']) == id).firstOrNull;
      final streamName = own == null ? null : jsonString(own['stream_name']);
      if (origin == null || !RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(origin)) {
        throw const ApiChanged(_site, 'channel/detail: no load balancer origin');
      }
      if (streamName == null || !RegExp(r'^[A-Za-z0-9_+-]{1,150}$').hasMatch(streamName)) {
        throw const ApiChanged(_site, 'channel/detail: no stream name');
      }
      master = Uri.parse('https://$origin.picarto.tv/stream/hls/$streamName/index.m3u8');
    }
    return (
      detail: RoomDetail(
        card: RoomCard(
          ref: card.ref,
          title: card.title,
          anchorName: card.anchorName,
          state: card.state,
          cover: card.cover,
          area: card.area,
          audience: Audience(online: card.audience.online, cumulative: total != null && total >= 0 ? total : null),
          avatar: card.avatar,
        ),
        link: Uri.parse('https://picarto.tv/${card.ref.roomId}'),
        avatar: card.avatar,
        introduction: intro == null || intro.isEmpty ? null : intro,
        danmakuKeys: {'channelName': card.ref.roomId, 'channelId': ?id?.toString()},
      ),
      master: master,
    );
  }

  /// §5 the qualities and lines of master [body] fetched from [master]: one
  /// quality per variant (best first), one line each; a master without
  /// variants (a media playlist) is played as it is.
  static StreamSet streams(String body, {required Uri master, required Map<String, String> headers, String? wanted}) {
    final List<HlsVariant> variants;
    try {
      variants = HlsPlaylist.variants(body, source: master);
    } on FormatException {
      throw const ApiChanged(_site, 'master: not a playlist');
    }
    if (variants.isEmpty) {
      const auto = Quality(id: 'auto', label: '自动', rank: 0);
      return StreamSet(
        qualities: const [auto],
        selected: auto,
        lines: [
          StreamLine(url: master, format: StreamFormat.hls, lineId: master.host, requested: auto, headers: headers),
        ],
      );
    }
    final qualities = <Quality, HlsVariant>{};
    for (final variant in variants) {
      final height = variant.height;
      final fps = variant.frameRate;
      final label = height == null
          ? 'HLS ${(variant.bandwidth / 1000000).toStringAsFixed(1)} Mbps'
          : '${height}p${fps != null && fps > 0 ? ' ${fps == fps.roundToDouble() ? fps.toInt() : fps}fps' : ''}';
      final quality = Quality(id: label, label: label, rank: (height ?? 0) * 100000000 + variant.bandwidth);
      qualities.putIfAbsent(quality, () => variant);
    }
    final ordered = qualities.keys.toList()..sort((a, b) => b.rank.compareTo(a.rank));
    final selected = ordered.where((q) => q.id == wanted).firstOrNull ?? ordered.first;
    final variant = qualities[selected]!;
    return StreamSet(
      qualities: ordered,
      selected: selected,
      lines: [
        StreamLine(
          url: variant.url,
          format: StreamFormat.hls,
          lineId: master.host,
          requested: selected,
          confirmed: selected,
          headers: headers,
          codec: variant.videoCodec,
        ),
      ],
    );
  }

  /// §1 the channel of an input: a bare name or `picarto.tv/<name>` (also
  /// inside share text); null otherwise.
  static String? channelOf(String input) {
    final text = input.trim();
    if (namePattern.hasMatch(text) && !reserved.contains(text.toLowerCase())) return text;
    final match = RegExp(r'https?://[^\s，。！？、]+').firstMatch(text);
    final url = Uri.tryParse(match?.group(0) ?? text);
    if (url == null || !const {'picarto.tv', 'www.picarto.tv'}.contains(url.host.toLowerCase())) return null;
    final segments = url.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (segments.length != 1) return null;
    final name = segments.single;
    return namePattern.hasMatch(name) && !reserved.contains(name.toLowerCase()) ? name : null;
  }
}
