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
import 'package:meta/meta.dart';

const _site = 'chzzk';

/// One entry of `categories/live` (spec §2.1).
typedef ChzzkCategoryItem = ({String type, String id, String name, Uri? poster});

/// One `categories/live` page: entries and the next page's query.
typedef ChzzkCategoryPage = ({List<ChzzkCategoryItem> items, Map<String, String>? next});

/// A CHZZK live's playback facts from `live-detail` (spec §4, §9): what
/// the stream request needs besides the room.
@immutable
final class ChzzkPlayback {
  /// Creates the facts.
  const new({required this.state, required this.adult, required this.regionLocked, required this.media});

  /// Live or offline.
  final LiveState state;

  /// `adult == true`.
  final bool adult;

  /// `krOnlyViewing == true` or `blindType == ABROAD`.
  final bool regionLocked;

  /// §5.1 HLS master playlists in `livePlaybackJson` order: `HLS`, `LLHLS`.
  final List<({String id, Uri url})> media;
}

/// Pure parsing of CHZZK responses (spec/sites/chzzk.md). Every function
/// takes the raw response the adapter received and returns domain values or
/// throws a `SiteError`.
abstract final class ChzzkParse {
  /// §1 a channel id: 32 lower-case hex digits.
  static final RegExp channelIdPattern = RegExp(r'^[0-9a-f]{32}$');

  /// §2.1 names of the `categoryType` values.
  static const categoryTypeNames = {'GAME': '游戏', 'ENTERTAINMENT': '娱乐', 'SPORTS': '体育', 'ETC': '其它'};

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

  /// §9 the `content` of an API response; maps the HTTP status first.
  /// Returns null when `content` is null.
  static Object? content(String body, {required String what, int status = 200}) {
    if (status == 429) throw RateLimited(_site, detail: '$what HTTP 429');
    if (status == 401 || status == 403) throw RiskControl(_site, detail: '$what HTTP $status');
    if (status == 404) throw NotFound(_site, '$what HTTP 404');
    if (status >= 500) throw NetworkFailure(_site, '$what HTTP $status');
    if (status < 200 || status >= 300) throw ApiChanged(_site, '$what HTTP $status');
    final root = _map(_json(body, what), what);
    final code = jsonInt(root['code']);
    if (code != 200) throw ApiChanged(_site, '$what code $code: ${jsonString(root['message']) ?? ''}');
    return root['content'];
  }

  /// §2.3 `liveImageUrl` with `{type}` set to 480, else the default thumbnail.
  static Uri? cover(Object? primary, Object? fallback) {
    for (final value in [primary, fallback]) {
      final text = jsonString(value);
      if (text == null) continue;
      final url = jsonUrl(text.replaceAll('{type}', '480'));
      if (url != null) return url;
    }
    return null;
  }

  /// §2.3 `concurrentUserCount` only when `cvExposure == true`.
  static int? _online(Map<String, dynamic> data) =>
      data['cvExposure'] == true ? jsonInt(data['concurrentUserCount']) : null;

  /// §2.3 `openDate` (`yyyy-MM-dd HH:mm:ss`, Seoul time, UTC+9) in UTC.
  static DateTime? seoulTime(Object? value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$').firstMatch(jsonString(value) ?? '');
    if (match == null) return null;
    final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
    return DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]).subtract(const Duration(hours: 9));
  }

  static String? _channelId(Object? value) {
    final id = jsonString(value)?.toLowerCase();
    return id != null && channelIdPattern.hasMatch(id) ? id : null;
  }

  /// §2.1 one `categories/live` page: the categories in order and the next
  /// page's query (null on the last page).
  static ChzzkCategoryPage categoryPage(String body, {int status = 200}) {
    final data = _map(content(body, what: 'categories/live', status: status), 'categories/live');
    final items = [
      for (final raw in _list(data['data'] ?? const [], 'categories/live.data'))
        if (raw is Map && jsonString(raw['categoryType']) != null && jsonString(raw['categoryId']) != null)
          (
            type: jsonString(raw['categoryType'])!,
            id: jsonString(raw['categoryId'])!,
            name: jsonString(raw['categoryValue']) ?? jsonString(raw['categoryId'])!,
            poster: jsonUrl(raw['posterImageUrl']),
          ),
    ];
    return (items: items, next: items.isEmpty ? null : _next(data['page']));
  }

  /// §2.1 categories from the pages in order: one [Category] per
  /// `categoryType` (first appearance), areas in list order, duplicates
  /// dropped.
  static List<Category> categories(List<ChzzkCategoryPage> pages) {
    final order = <String>[];
    final areas = <String, List<Area>>{};
    final seen = <String>{};
    for (final page in pages) {
      for (final item in page.items) {
        if (!seen.add('${item.type}/${item.id}')) continue;
        if (!areas.containsKey(item.type)) order.add(item.type);
        areas
            .putIfAbsent(item.type, () => [])
            .add(Area(id: item.id, name: item.name, categoryId: item.type, icon: item.poster));
      }
    }
    return [for (final type in order) Category(id: type, name: categoryTypeNames[type] ?? type, areas: areas[type]!)];
  }

  static Map<String, String>? _next(Object? page) {
    if (page is! Map) return null;
    final next = page['next'];
    if (next is! Map || next.isEmpty) return null;
    return {
      for (final entry in next.entries)
        if (entry.value != null) '${entry.key}': '${entry.value}',
    };
  }

  /// §2.2 / §2.3 a lives page (`v1/lives`, `v2/categories/.../lives`). All
  /// entries are live; the page ends when `page.next` is null or `data` is
  /// empty. [cursor] is the query that fetched this page: an entry with its
  /// `liveId` is dropped (the boundary), as is a channel already on the page.
  static Page<RoomCard> livesPage(String body, {int status = 200, Map<String, String>? cursor}) {
    final data = _map(content(body, what: 'lives', status: status), 'lives');
    final raw = _list(data['data'] ?? const [], 'lives.data');
    final seen = <String>{};
    final rooms = <RoomCard>[
      for (final item in raw)
        if (item is Map<String, dynamic> && '${item['liveId']}' != cursor?['liveId'])
          if (_liveCard(item) case final card? when seen.add(card.ref.roomId)) card,
    ];
    final next = raw.isEmpty ? null : _next(data['page']);
    return Page(rooms, next: next == null ? null : PageCursor(jsonEncode(next)));
  }

  static RoomCard? _liveCard(Map<String, dynamic> item) {
    final channel = item['channel'];
    final id = _channelId(channel is Map ? channel['channelId'] : item['channelId']);
    if (id == null) return null;
    final category = jsonString(item['liveCategoryValue']) ?? jsonString(item['liveCategory']);
    return RoomCard(
      ref: RoomRef(_site, id),
      title: decodeHtmlEntities(jsonString(item['liveTitle']) ?? ''),
      anchorName: channel is Map ? jsonString(channel['channelName']) ?? '' : '',
      state: LiveState.live,
      cover: cover(item['liveImageUrl'], item['defaultThumbnailImageUrl']),
      area: category,
      audience: Audience(online: _online(item)),
      liveSince: seoulTime(item['openDate']),
      avatar: channel is Map ? jsonUrl(channel['channelImageUrl']) : null,
    );
  }

  /// The query of a cursor from [livesPage] or [categoryPage].
  static Map<String, String> cursorQuery(PageCursor cursor) {
    try {
      final decoded = jsonDecode(cursor.value);
      if (decoded is Map) return {for (final entry in decoded.entries) '${entry.key}': '${entry.value}'};
    } on FormatException {
      // Not a CHZZK cursor.
    }
    throw ArgumentError.value(cursor.value, 'cursor', 'not a CHZZK cursor');
  }

  /// §3 `search/channels` page fetched at [offset]: channel cards (title is
  /// the channel name, cover the avatar), live by `openLive`. Ends on an
  /// empty page or a null `page`.
  static Page<RoomCard> searchPage(String body, {required int offset, int status = 200}) {
    final data = _map(content(body, what: 'search/channels', status: status), 'search/channels');
    final raw = _list(data['data'] ?? const [], 'search/channels.data');
    final rooms = <RoomCard>[
      for (final item in raw)
        if (item is Map && item['channel'] is Map)
          if (_channelId((item['channel'] as Map)['channelId']) case final id?)
            _channelCard(id, item['channel'] as Map),
    ];
    final next = raw.isEmpty ? null : _next(data['page']);
    final nextOffset = next == null ? null : int.tryParse(next['offset'] ?? '') ?? offset + raw.length;
    return Page(rooms, next: nextOffset == null || nextOffset <= offset ? null : PageCursor('$nextOffset'));
  }

  static RoomCard _channelCard(String id, Map<dynamic, dynamic> channel) {
    final name = jsonString(channel['channelName']) ?? '';
    final avatar = jsonUrl(channel['channelImageUrl']);
    return RoomCard(
      ref: RoomRef(_site, id),
      title: name,
      anchorName: name,
      state: channel['openLive'] == true ? LiveState.live : LiveState.offline,
      cover: avatar,
      avatar: avatar,
    );
  }

  /// §4 the channel of `v1/channels/<id>`; a null `channelId` is a channel
  /// that does not exist.
  static ({String id, String name, Uri? avatar, String? description, bool openLive}) channel(
    String body, {
    int status = 200,
  }) {
    final data = content(body, what: 'channels', status: status);
    if (data == null) throw const NotFound(_site, 'channels: no content');
    final map = _map(data, 'channels');
    final id = _channelId(map['channelId']);
    if (id == null) throw const NotFound(_site, 'channels: channelId is null');
    return (
      id: id,
      name: jsonString(map['channelName']) ?? '',
      avatar: jsonUrl(map['channelImageUrl']),
      description: jsonString(map['channelDescription']),
      openLive: map['openLive'] == true,
    );
  }

  /// §4 the room from the channel response and `v3.1 live-detail`.
  static RoomDetail detail(String channelBody, String liveBody, {int channelStatus = 200, int liveStatus = 200}) {
    final owner = channel(channelBody, status: channelStatus);
    final live = content(liveBody, what: 'live-detail', status: liveStatus);
    final link = Uri.parse('https://chzzk.naver.com/live/${owner.id}');
    if (live == null) {
      return RoomDetail(
        card: RoomCard(
          ref: RoomRef(_site, owner.id),
          title: owner.name,
          anchorName: owner.name,
          state: LiveState.offline,
          cover: owner.avatar,
          avatar: owner.avatar,
        ),
        link: link,
        avatar: owner.avatar,
        introduction: owner.description,
      );
    }
    final map = _map(live, 'live-detail');
    final liveChannel = map['channel'];
    final liveOwner = liveChannel is Map ? _channelId(liveChannel['channelId']) : null;
    if (liveOwner != null && liveOwner != owner.id) {
      throw ApiChanged(_site, 'live-detail: channel $liveOwner for ${owner.id}');
    }
    final state = liveState(map);
    final chat = jsonString(map['chatChannelId']);
    final title = decodeHtmlEntities(jsonString(map['liveTitle']) ?? owner.name);
    final cumulative = jsonInt(map['accumulateCount']);
    return RoomDetail(
      card: RoomCard(
        ref: RoomRef(_site, owner.id),
        title: title,
        anchorName: (liveChannel is Map ? jsonString(liveChannel['channelName']) : null) ?? owner.name,
        state: state,
        cover: cover(map['liveImageUrl'], map['defaultThumbnailImageUrl']),
        area: jsonString(map['liveCategoryValue']) ?? jsonString(map['liveCategory']),
        audience: Audience(
          online: state == LiveState.live ? _online(map) : null,
          cumulative: cumulative != null && cumulative > 0 ? cumulative : null,
        ),
        liveSince: state == LiveState.live ? seoulTime(map['openDate']) : null,
        avatar: (liveChannel is Map ? jsonUrl(liveChannel['channelImageUrl']) : null) ?? owner.avatar,
      ),
      link: link,
      avatar: (liveChannel is Map ? jsonUrl(liveChannel['channelImageUrl']) : null) ?? owner.avatar,
      introduction: owner.description,
      danmakuKeys: {'channelId': owner.id, 'chatChannelId': ?chat},
    );
  }

  /// §4 `status`: `OPEN` live, `CLOSE`/`CLOSED` offline, anything else is
  /// an unknown shape.
  static LiveState liveState(Map<String, dynamic> live) => switch (jsonString(live['status'])) {
    'OPEN' => LiveState.live,
    'CLOSE' || 'CLOSED' => LiveState.offline,
    final other => throw ApiChanged(_site, 'live-detail: status $other'),
  };

  /// §4/§5.1 the playback facts of `v3.1 live-detail`.
  static ChzzkPlayback playback(String liveBody, {int status = 200}) {
    final live = content(liveBody, what: 'live-detail', status: status);
    if (live == null) {
      return const ChzzkPlayback(state: LiveState.offline, adult: false, regionLocked: false, media: []);
    }
    final map = _map(live, 'live-detail');
    final state = liveState(map);
    final media = <({String id, Uri url})>[];
    final raw = map['livePlaybackJson'];
    if (state == LiveState.live && raw is String && raw.trim().isNotEmpty) {
      final playback = _map(_json(raw, 'livePlaybackJson'), 'livePlaybackJson');
      final seen = <Uri>{};
      for (final item in _list(playback['media'] ?? const [], 'livePlaybackJson.media')) {
        if (item is! Map || jsonString(item['protocol']) != 'HLS') continue;
        final id = jsonString(item['mediaId']);
        if (id != 'HLS' && id != 'LLHLS') continue;
        final url = jsonUrl(item['path']);
        if (url != null && seen.add(url)) media.add((id: id!, url: url));
      }
    }
    return ChzzkPlayback(
      state: state,
      adult: map['adult'] == true,
      regionLocked: map['krOnlyViewing'] == true || jsonString(map['blindType']) == 'ABROAD',
      media: media,
    );
  }

  /// §9 why a live without playback data cannot play.
  static SiteError noPlayback(ChzzkPlayback playback) {
    if (playback.state != LiveState.live) return const StreamUnavailable(_site, 'not live');
    if (playback.regionLocked) return const RegionBlocked(_site, 'krOnlyViewing');
    if (playback.adult) return const NeedsLogin(_site, 'adult live');
    return const StreamUnavailable(_site, 'live without playback');
  }

  /// §5.2 the quality of a variant: `<height>p`, plus `60` at 50 fps or
  /// more; null for a variant without a height (audio only).
  static Quality? quality(HlsVariant variant) {
    final height = variant.height;
    if (height == null || height <= 0 || variant.audioOnly) return null;
    final id = '${height}p${(variant.frameRate ?? 0) >= 50 ? '60' : ''}';
    return Quality(id: id, label: id, rank: height * 100000000 + variant.bandwidth.clamp(0, 99999999));
  }

  /// §6.2 lease of a variant: `exp` of the variant path's `hdntl`, else of
  /// the master's `hdnts`; refresh 10 minutes (at most a quarter of the
  /// lifetime) before; expiry refuses new segments, so it cuts playback.
  static Lease? lease(Uri variant, {required Uri master, required DateTime issuedAt}) {
    final exp =
        RegExp(r'exp=(\d{9,})').firstMatch(Uri.decodeFull(variant.path))?.group(1) ??
        RegExp(r'exp=(\d{9,})').firstMatch(master.queryParameters['hdnts'] ?? '')?.group(1);
    if (exp == null) return null;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(int.parse(exp) * 1000, isUtc: true);
    final lifetime = expiresAt.difference(issuedAt);
    if (lifetime <= Duration.zero) return null;
    final quarter = lifetime ~/ 4;
    const lead = Duration(minutes: 10);
    return Lease(
      refreshAt: expiresAt.subtract(quarter < lead ? quarter : lead),
      expiresAt: expiresAt,
      cutsConnection: true,
    );
  }

  /// §5/§6 the stream set from the fetched masters ([masters] in media
  /// order; a null body is a master that failed): qualities best first,
  /// two lines (HLS, LLHLS) at [wanted], or at the best quality when
  /// [wanted] is not offered.
  static StreamSet streams(
    List<({String id, Uri url, String? body})> masters, {
    required DateTime issuedAt,
    required Map<String, String> headers,
    String? wanted,
  }) {
    final qualities = <String, Quality>{};
    final variants = <String, Map<String, HlsVariant>>{};
    for (final master in masters) {
      final body = master.body;
      if (body == null) continue;
      final List<HlsVariant> parsed;
      try {
        parsed = HlsPlaylist.variants(body, source: master.url);
      } on FormatException {
        throw ApiChanged(_site, '${master.id} master: not a playlist');
      }
      for (final variant in parsed) {
        final q = quality(variant);
        if (q == null) continue;
        final best = qualities[q.id];
        if (best == null || q.rank > best.rank) qualities[q.id] = q;
        variants.putIfAbsent(master.id, () => {}).putIfAbsent(q.id, () => variant);
      }
    }
    if (qualities.isEmpty) throw const StreamUnavailable(_site, 'no video variant');
    final ordered = qualities.values.toList()..sort((a, b) => b.rank.compareTo(a.rank));
    final selected = qualities[wanted] ?? ordered.first;
    final lines = <StreamLine>[
      for (final master in masters)
        if (variants[master.id]?[selected.id] case final variant?)
          StreamLine(
            url: variant.url,
            format: StreamFormat.hls,
            lineId: master.id,
            requested: selected,
            confirmed: selected,
            headers: headers,
            codec: variant.videoCodec,
            lease: lease(variant.url, master: master.url, issuedAt: issuedAt),
          ),
    ];
    return StreamSet(qualities: ordered, selected: selected, lines: lines);
  }
}
