import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = '17live';

/// Pure parsing of 17LIVE responses (spec/sites/17live.md).
abstract final class SeventeenliveParse {
  /// §1 a room id (`liveStreamID`, the streamer's `roomID`).
  static final RegExp roomIdPattern = RegExp(r'^[1-9][0-9]{0,11}$');

  /// §2 the directory regions, in order.
  static const areas = [
    Area(id: 'JP', name: '日本', categoryId: 'region'),
    Area(id: 'TW', name: '台湾', categoryId: 'region'),
    Area(id: 'HK', name: '香港', categoryId: 'region'),
  ];

  /// §2 the one category.
  static const category = Category(id: 'region', name: '17LIVE', areas: areas);

  /// §2 sections that hold no current broadcasts.
  static const skippedSections = {'TopBanner', 'ArchiveVideo', 'ArchiveClip', 'Vod'};

  static Object? _json(String body, String what) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
  }

  /// §9 status mapping; errors carry `errorCode` and `errorMessage`
  /// (unknown rooms: HTTP 520 `stream not found`; bad parameters: HTTP 420
  /// `errorCode 7`).
  static Object? root(String body, {required String what, int status = 200}) {
    if (status == 429) throw RateLimited(_site, detail: '$what HTTP 429');
    if (status == 401 || status == 403) throw RiskControl(_site, detail: '$what HTTP $status');
    if (status == 404) throw NotFound(_site, '$what HTTP 404');
    if (status < 200 || status >= 300) {
      final error = _errorMessage(body);
      if (error == 'stream not found') throw NotFound(_site, '$what: $error');
      if (status >= 500) throw NetworkFailure(_site, '$what HTTP $status ${error ?? ''}'.trim());
      throw ApiChanged(_site, '$what HTTP $status ${error ?? ''}'.trim());
    }
    return _json(body, what);
  }

  static String? _errorMessage(String body) {
    try {
      final data = jsonDecode(body);
      return data is Map ? jsonString(data['errorMessage']) : null;
    } on FormatException {
      return null;
    }
  }

  /// §2.3 images: absolute `cdn.17app.co` / `assets-17app.akamaized.net`
  /// URLs (http is upgraded) or bare file names on `cdn.17app.co`.
  static Uri? image(Object? value) {
    final text = jsonString(value);
    if (text == null) return null;
    if (RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(text)) return Uri.https('cdn.17app.co', '/$text');
    final url = Uri.tryParse(text);
    if (url == null || (url.scheme != 'https' && url.scheme != 'http')) return null;
    final host = url.host.toLowerCase();
    if (host != 'cdn.17app.co' && host != 'assets-17app.akamaized.net') return null;
    return url.replace(scheme: 'https');
  }

  static int? _count(Object? value) {
    final count = jsonInt(value);
    return count != null && count >= 0 ? count : null;
  }

  /// §1 the room page.
  static Uri link(String roomId) => Uri.https('17.live', '/ja/live/$roomId');

  /// §2.3 a card from a stream object (section grids, search rows, the
  /// room itself); null when it names no room.
  static RoomCard? card(Map<dynamic, dynamic> stream) {
    final id = '${jsonInt(stream['liveStreamID']) ?? ''}';
    if (!roomIdPattern.hasMatch(id)) return null;
    final user = stream['userInfo'] is Map ? stream['userInfo'] as Map : const <String, Object?>{};
    final live = jsonInt(stream['status']) == 2;
    final name = jsonString(user['displayName']) ?? jsonString(user['openID']) ?? id;
    final begin = jsonInt(stream['beginTime']);
    return RoomCard(
      ref: RoomRef(_site, id),
      title: jsonString(stream['caption']) ?? name,
      anchorName: name,
      state: live ? LiveState.live : LiveState.offline,
      cover: image(stream['coverPhoto']) ?? image(stream['thumbnail']),
      area: jsonInt(stream['audioOnly']) == 1 ? '音频直播' : null,
      audience: live
          ? Audience(online: _count(stream['liveViewerCount']), cumulative: _count(stream['viewerCount']))
          : Audience.none,
      liveSince: live && begin != null && begin > 0
          ? DateTime.fromMillisecondsSinceEpoch(begin * 1000, isUtc: true)
          : null,
      avatar: image(user['picture']),
      followers: jsonCount(user['followerCount']),
    );
  }

  /// §2.2 a `sections` page: the live broadcasts of every section except
  /// banners and archives, first appearance kept; the next cursor unless it
  /// is empty or repeats [cursor].
  static Page<RoomCard> sectionsPage(String body, {String? cursor, int status = 200}) {
    final data = root(body, what: 'sections', status: status);
    if (data is! Map || data['sections'] is! List) throw const ApiChanged(_site, 'sections: no list');
    final seen = <String>{};
    final cards = <RoomCard>[];
    for (final section in data['sections'] as List) {
      if (section is! Map || skippedSections.contains(section['id'])) continue;
      final grids = section['grids'];
      for (final grid in grids is List ? grids : const <Object?>[]) {
        final stream = grid is Map ? grid['stream'] : null;
        if (stream is! Map) continue;
        final c = card(stream);
        if (c != null && c.state == LiveState.live && seen.add(c.ref.roomId)) cards.add(c);
      }
    }
    final next = jsonString(data['cursor']);
    return Page(cards, next: next != null && next != cursor ? PageCursor(next) : null);
  }

  /// §3 `liveStreams/search`: current broadcasts only, one page.
  static Page<RoomCard> searchPage(String body, {int status = 200}) {
    final data = root(body, what: 'liveStreams/search', status: status);
    if (data is! List) throw const ApiChanged(_site, 'liveStreams/search: not a list');
    final seen = <String>{};
    return Page([
      for (final row in data)
        if (row is Map)
          if (card(row) case final RoomCard c when c.state == LiveState.live && seen.add(c.ref.roomId)) c,
    ]);
  }

  static Map<String, dynamic> _room(String body, {required String roomId, int status = 200}) {
    final data = root(body, what: 'lives/$roomId', status: status);
    if (data is! Map<String, dynamic>) throw ApiChanged(_site, 'lives/$roomId: not an object');
    final id = '${jsonInt(data['liveStreamID']) ?? ''}';
    final user = data['userInfo'];
    final owner = user is Map ? jsonInt(user['roomID']) : null;
    if (id != roomId || (owner != null && '$owner' != roomId)) {
      throw ApiChanged(_site, 'lives/$roomId: answer for room $id (owner $owner)');
    }
    final state = jsonInt(data['status']);
    if (state != 0 && state != 2) throw ApiChanged(_site, 'lives/$roomId: status $state');
    return data;
  }

  /// §4 the room from `lives/<id>`.
  static RoomDetail detail(String body, {required String roomId, int status = 200}) {
    final data = _room(body, roomId: roomId, status: status);
    final c = card(data)!;
    final user = data['userInfo'] is Map ? data['userInfo'] as Map : const <String, Object?>{};
    return RoomDetail(
      card: c,
      link: link(roomId),
      avatar: c.avatar,
      introduction: jsonString(user['bio']),
      danmakuKeys: {if (c.state == LiveState.live) 'roomId': roomId},
    );
  }

  /// §5 qualities in display order: pull URL fields of each provider.
  static const qualityFields = {
    'source': ['urlHighQuality', 'urlLowQuality', 'webUrlLowQuality'],
    'enhanced': ['urlQualityEnhancedHD'],
    'hd': ['urlLowBitrateHD', 'webUrl', 'url'],
    'h264': ['url264'],
  };

  static const _labels = {'source': '原画', 'enhanced': '增强高清', 'hd': '高清', 'h264': 'H.264'};

  /// §5 the quality chosen when none is asked for: the H.264 transcode, the
  /// only one that is never FLV codec 12 (HEVC) (§6.4).
  static const defaultQuality = 'h264';

  static final _pullHost = RegExp(r'^[a-z0-9-]*pull-rtmp[a-z0-9-]*\.17app\.co$');

  /// §5 a pull URL: an `.flv` on a `*pull-rtmp*.17app.co` host, upgraded to
  /// https.
  static Uri? pullUrl(Object? value) {
    final url = jsonUrl(value);
    if (url == null || (url.scheme != 'http' && url.scheme != 'https')) return null;
    if (!_pullHost.hasMatch(url.host.toLowerCase()) || !url.path.toLowerCase().endsWith('.flv')) return null;
    return url.replace(scheme: 'https');
  }

  /// §5 the qualities and lines of a live room: one line per provider in
  /// the answer's order (the first is the one that serves; §6.2).
  static StreamSet streams(
    String body, {
    required String roomId,
    required Map<String, String> headers,
    String? wanted,
    int status = 200,
  }) {
    final data = _room(body, roomId: roomId, status: status);
    if (jsonInt(data['status']) != 2) throw const StreamUnavailable(_site, 'room is offline');
    final pull = data['pullURLsInfo'];
    final providers = pull is Map && pull['rtmpURLs'] is List ? pull['rtmpURLs'] as List : data['rtmpUrls'];
    final offered = <Quality, List<Uri>>{};
    var rank = qualityFields.length;
    for (final MapEntry(key: id, value: fields) in qualityFields.entries) {
      final urls = <Uri>[];
      for (final provider in providers is List ? providers : const <Object?>[]) {
        if (provider is! Map) continue;
        for (final field in fields) {
          final url = pullUrl(provider[field]);
          if (url != null) {
            if (!urls.contains(url)) urls.add(url);
            break;
          }
        }
      }
      if (urls.isNotEmpty) offered[Quality(id: id, label: _labels[id]!, rank: rank)] = urls;
      rank--;
    }
    if (offered.isEmpty) throw const StreamUnavailable(_site, 'no pull URL');
    final qualities = offered.keys.toList();
    final selected =
        qualities.where((q) => q.id == wanted).firstOrNull ??
        qualities.where((q) => q.id == defaultQuality).firstOrNull ??
        qualities.first;
    return StreamSet(
      qualities: qualities,
      selected: selected,
      lines: [
        for (final url in offered[selected]!)
          StreamLine(
            url: url,
            format: StreamFormat.flv,
            lineId: url.host.split('-').first,
            requested: selected,
            confirmed: selected,
            headers: headers,
            codec: selected.id == 'h264' ? 'avc' : null,
          ),
      ],
    );
  }

  /// §1 the room a link names (also inside share text); null otherwise.
  static String? roomIdOf(String input) {
    final text = input.trim();
    final match = RegExp(r'https?://[^\s，。！？、]+').firstMatch(text);
    final url = Uri.tryParse(match?.group(0) ?? text);
    if (url == null || !url.hasScheme) return null;
    final host = url.host.toLowerCase();
    if (host != '17.live' && host != 'www.17.live') return null;
    var segments = url.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (segments.isNotEmpty && RegExp(r'^[a-z]{2}(-[a-z]{2,4})?$', caseSensitive: false).hasMatch(segments.first)) {
      segments = segments.sublist(1);
    }
    final id = switch (segments) {
      ['live', final id] => id,
      ['profile', 'r', final id] => id,
      _ => null,
    };
    return id != null && roomIdPattern.hasMatch(id) ? id : null;
  }
}
