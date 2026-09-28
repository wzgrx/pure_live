import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/quality_label.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'cc';

/// What 3.x's streams are made of, apart from the room's identity (3.x kept
/// them in `data` and `link`): the live channel's tier list and the redirect
/// playlist its signatures are appended to. Rooms without a live channel
/// (offline, refreshed without one, list cards) have none.
@immutable
final class CcRoomData {
  /// Creates the data.
  const new({this.streams, this.playlist});

  /// The channel's `quickplay`, else its `stream_list`: tier → CDN → URL or
  /// signature.
  final Map<String, dynamic>? streams;

  /// The channel's `m3u8`: `cgi.v.cc.163.com/redirect/video/{ccid}.m3u8`.
  final String? playlist;
}

/// Pure parsing of NetEase CC responses (3.x's `CCSite` and `CCCatalog`,
/// with the archived v4 parser's room page and `video_play_url` as the
/// fallbacks where 3.x had nothing). Each function takes the response text
/// and status and returns 3.x's models or throws a `SiteError`.
abstract final class CcApi {
  /// Desktop Chrome 140, the UA 3.x sent to CC and to its media CDN
  /// (`PlaybackHeaderResolver`).
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/140.0.0.0 Safari/537.36';

  /// Web origin; also the API requests' `Referer` (with a slash) and the
  /// media requests' `Origin`.
  static const String origin = 'https://cc.163.com';

  /// Identity of the Dashen configuration whose "直播入口列表" is the
  /// catalog (3.x's `CCCatalog.configurationId`).
  static const String catalogConfigurationId = '67b32cdd1801fc391a6c2657';

  /// Name of the catalog's first category: the numeric live areas.
  static const String categoryLabel = '直播分类';

  /// Name of the catalog's second category: official rooms and events,
  /// opened on the website instead of listed (3.x's `official:` areas).
  static const String officialLabel = '官方房间/专题';

  /// Rows one directory page asks for (3.x's `_CCCategoryDirectory`).
  static const int directoryPageSize = 30;

  /// How long before `auth_key` expires a play URL is renewed (at most a
  /// quarter of its lifetime).
  static const Duration leaseLead = Duration(seconds: 60);

  /// A CC id (`ccid`, `cuteid`): a positive decimal number.
  static final RegExp ccidPattern = RegExp(r'^[1-9]\d{0,15}$');

  static final RegExp _areaId = RegExp(r'^[1-9][0-9]{0,15}$');

  // Catalog -------------------------------------------------------------------

  /// The Dashen game registry ([gamesBody]) and live configuration
  /// ([configBody]) as 3.x's `CCCatalog.parse` read them: only the entries of
  /// the configuration's "直播入口列表" are areas, named and pictured by the
  /// registry. `/n/ds_category/{gametype}/` entries are live areas (category
  /// "1"), `/{ccid}/` entries official rooms (`official:{ccid}`, category
  /// "official"). A hidden configuration or group is an empty catalog; any
  /// other irregularity fails the whole catalog (`ApiChanged`), never a
  /// partial one.
  static List<LiveCategory> categories(
    String gamesBody,
    String configBody, {
    int gamesStatus = 200,
    int configStatus = 200,
  }) {
    final games = _catalogEnvelope(gamesBody, status: gamesStatus, what: 'game registry');
    final config = _catalogEnvelope(configBody, status: configStatus, what: 'live configuration');
    final metadata = <String, Map<String, dynamic>>{};
    for (final raw in _catalogList(games['result'], 2000)) {
      final row = _catalogMap(raw);
      final key = _catalogText(row['appKey'], 64);
      if (metadata.containsKey(key)) throw ApiChanged(_site, 'game registry: duplicate appKey $key');
      metadata[key] = row;
    }
    final root = _catalogMap(config['result']);
    if (root['id'] != catalogConfigurationId) throw ApiChanged(_site, 'live configuration: id ${root['id']}');
    if (_hidden(root)) return const [];
    final groups = [
      for (final raw in _catalogList(root['itemList'], 256))
        if (_catalogMap(raw) case final group when group['name'] == '直播入口列表') group,
    ];
    if (groups.length != 1) throw ApiChanged(_site, 'live configuration: ${groups.length} live entry groups');
    if (_hidden(groups.single)) return const [];
    final areas = <LiveArea>[];
    final official = <LiveArea>[];
    final identities = <String>{};
    for (final raw in _catalogList(groups.single['itemList'], 256)) {
      final entry = _catalogMap(raw);
      if (_hidden(entry)) continue;
      final key = _catalogText(entry['name'], 64);
      final game = metadata[key];
      if (game == null) throw ApiChanged(_site, 'live configuration: entry $key has no game');
      final url = Uri.tryParse(_catalogText(entry['content'], 2048));
      if (url == null ||
          url.scheme != 'https' ||
          url.host != 'cc.163.com' ||
          url.userInfo.isNotEmpty ||
          url.hasPort ||
          url.hasFragment) {
        throw ApiChanged(_site, 'live configuration: entry $key leads to ${entry['content']}');
      }
      final category = RegExp(r'^/n/ds_category/([1-9][0-9]{0,15})/$').firstMatch(url.path);
      final room = RegExp(r'^/([1-9][0-9]{0,15})/$').firstMatch(url.path);
      if (category == null && room == null) throw ApiChanged(_site, 'live configuration: unknown route ${url.path}');
      final id = category != null ? category.group(1)! : 'official:${room!.group(1)}';
      if (!identities.add(id)) throw ApiChanged(_site, 'live configuration: duplicate entry $id');
      (category != null ? areas : official).add(
        LiveArea(
          platform: _site,
          areaId: id,
          areaType: category != null ? '1' : 'official',
          typeName: category != null ? categoryLabel : officialLabel,
          areaName: _catalogText(game['name'], 200),
          areaPic: _httpsImage(game['icon']),
        ),
      );
    }
    return [
      if (areas.isNotEmpty) LiveCategory(id: '1', name: categoryLabel, children: areas),
      if (official.isNotEmpty) LiveCategory(id: 'official', name: officialLabel, children: official),
    ];
  }

  /// Whether [area] is one of the catalog's official rooms or events.
  static bool isOfficialEntry(LiveArea area) =>
      area.platform.trim().toLowerCase() == _site && area.areaId.trim().startsWith('official:');

  /// Where an official entry opens (3.x's `CCCatalog.officialEntryUri`),
  /// rebuilt from its id so a stored area can never point to another host;
  /// null for any other area.
  static Uri? officialEntryUri(LiveArea area) {
    if (!isOfficialEntry(area)) return null;
    final id = area.areaId.trim().substring('official:'.length);
    if (!_areaId.hasMatch(id)) return null;
    return Uri.https('cc.163.com', '/$id/', {'open': 'blizzardtv', 'from': '8382', 'platform': 'ds'});
  }

  /// Whether [area] is a live area `CcSite.getCategoryRooms` can list: a
  /// numeric game type of this platform, or of none (3.x's check).
  static bool isListableArea(LiveArea area) {
    final platform = area.platform.trim().toLowerCase();
    return _areaId.hasMatch(area.areaId.trim()) && (platform.isEmpty || platform == _site);
  }

  // Lists ---------------------------------------------------------------------

  /// `api/category/{gametype}/`: the area's `lives`, strictly as 3.x read
  /// them. The answer must echo [gametype] and hold a `lives` list of at
  /// most 1000 objects, each with a valid `cuteid`; otherwise the page is
  /// `ApiChanged`, never a short one. `videos` are recordings, not rooms.
  /// `status` 1 is live, 0 offline, anything else unknown.
  static List<LiveRoom> categoryRooms(String body, {required String gametype, int status = 200}) {
    final root = _object(_decode(body, status: status, what: 'category $gametype'));
    if (root == null || root['gametype']?.toString() != gametype || root['lives'] is! List) {
      throw ApiChanged(_site, 'category $gametype: unexpected answer (${_snippet(body)})');
    }
    final rows = root['lives'] as List;
    if (rows.length > 1000) throw ApiChanged(_site, 'category $gametype: ${rows.length} rows');
    return [
      for (final row in rows)
        switch (_object(row)) {
          final item? when _cuteid(item['cuteid']) != null => _listRoom(
            item,
            area: _text(item['game_name']).ifEmpty(() => _text(item['gamename'])),
            liveStatus: _status(item['status']),
          ),
          _ => throw ApiChanged(_site, 'category $gametype: a row without a valid cuteid'),
        },
    ];
  }

  /// `api/category/live/`: every live room, by the site's heat order. The
  /// endpoint lists live rooms only, so every card is live (3.x). The area
  /// is `game_name` as 3.x read it: these rows carry only `gamename`, so
  /// 3.x showed them without an area, and so does this. Rows without a
  /// valid `cuteid` are skipped (3.x wrote the room id "null").
  static List<LiveRoom> recommendRooms(String body, {int status = 200}) {
    final root = _object(_decode(body, status: status, what: 'category/live'));
    final lives = root?['lives'];
    if (lives is! List) throw ApiChanged(_site, 'category/live: no lives list (${_snippet(body)})');
    return [
      for (final row in lives)
        if (_object(row) case final item? when _cuteid(item['cuteid']) != null)
          _listRoom(item, area: _text(item['game_name']), liveStatus: LiveStatus.live),
    ];
  }

  /// A room card of the directory lists: heat and concurrent viewers side by
  /// side (3.x's `parseRoomAudience`), the heat shown when there is one.
  static LiveRoom _listRoom(Map<String, dynamic> item, {required String area, required LiveStatus liveStatus}) {
    final audience = _audience(item);
    return LiveRoom(
      roomId: _cuteid(item['cuteid']),
      platform: _site,
      title: _text(item['title']),
      nick: _text(item['nickname']),
      avatar: normalizeImageUrl(item['purl']),
      cover: _image(item['cover'], item['poster']),
      area: area,
      watching: audience.popularity.ifEmpty(() => audience.online),
      popularity: audience.popularity,
      onlineViewers: audience.online,
      audienceMetricType: audience.popularity.isNotEmpty
          ? AudienceMetricType.popularity
          : AudienceMetricType.onlineViewers,
      liveStatus: liveStatus,
    );
  }

  // Search --------------------------------------------------------------------

  /// `search/anchor/`: streamers, live or not, as 3.x showed them: the
  /// portrait as both avatar and cover, the follower count as the audience,
  /// `status` 1 live and anything else offline. Rows without a valid
  /// `cuteid` are skipped.
  static List<LiveRoom> searchRooms(String body, {int status = 200}) {
    final root = _object(_decode(body, status: status, what: 'search/anchor'));
    final anchors = _object(root?['webcc_anchor']);
    if (anchors == null) throw ApiChanged(_site, 'search/anchor: no webcc_anchor (${_snippet(body)})');
    return [
      for (final row in _list(anchors['result']))
        if (_object(row) case final item? when _cuteid(item['cuteid']) != null) _searchRoom(item),
    ];
  }

  static LiveRoom _searchRoom(Map<String, dynamic> item) {
    final portrait = normalizeImageUrl(item['portrait']).ifEmpty(() => normalizeImageUrl(item['portraiturl']));
    final followers = _text(item['follower_num']);
    return LiveRoom(
      roomId: _cuteid(item['cuteid']),
      platform: _site,
      title: _text(item['title']),
      nick: _text(item['nickname']),
      avatar: portrait,
      cover: portrait,
      area: _text(item['game_name']),
      watching: followers,
      followers: followers.ifEmpty(() => '0'),
      audienceMetricType: AudienceMetricType.followers,
      liveStatus: jsonInt(item['status']) == 1 ? LiveStatus.live : LiveStatus.offline,
    );
  }

  // Rooms ---------------------------------------------------------------------

  /// `activitylives/anchor/lives`: the channel [ccid] broadcasts in, or null
  /// when it has none (an offline or unknown anchor: both answer only
  /// `is_black`). HTTP 400 (a non-numeric id) is `NotFound`; a `code` other
  /// than "OK" or no entry for [ccid] is `ApiChanged`.
  static String? liveChannel(String body, {required String ccid, int status = 200}) {
    if (status == 400) throw NotFound(_site, 'activitylives: HTTP 400 for $ccid');
    final root = _object(_decode(body, status: status, what: 'activitylives'));
    if (jsonString(root?['code']) != 'OK') throw ApiChanged(_site, 'activitylives: code ${root?['code']}');
    final entry = _object(_object(root?['data'])?[ccid]);
    if (entry == null) throw ApiChanged(_site, 'activitylives: no entry for $ccid');
    return jsonString(entry['channel_id']);
  }

  /// `live/channel/?channelids=`: the room broadcasting in the channel, as
  /// 3.x's `_loadRoomDetail` read it, under the id [ccid] the user asked
  /// for. `status` 1 is live, anything else offline; an official "【重播】"
  /// rebroadcast is live, as 3.x showed it. The audience is the heat, else
  /// the viewers, else the follower count; the introduction and notice are
  /// both the streamer's `personal_label`; `userId` is the channel (`cid`,
  /// the app's `cc://join-room/{ccid}/{cid}/`). The tier list and redirect
  /// playlist go into [CcRoomData].
  ///
  /// Null when the channel no longer broadcasts (`nolive`, or no rows: the
  /// broadcast ended between the two requests). A row for another anchor is
  /// `ApiChanged`.
  static LiveRoom? channelRoom(String body, {required String ccid, int status = 200}) {
    final root = _object(_decode(body, status: status, what: 'live/channel'));
    if (root == null) throw ApiChanged(_site, 'live/channel: not an object (${_snippet(body)})');
    final rows = root['data'];
    if (rows != null && rows is! List) throw const ApiChanged(_site, 'live/channel: data is not a list');
    final room = _object((rows as List?)?.firstOrNull);
    if (room == null || jsonInt(room['nolive']) == 1) return null;
    final id = _cuteid(room['ccid'] ?? room['cuteid']);
    if (id != ccid) throw ApiChanged(_site, 'live/channel: answered ccid $id for $ccid');
    final audience = _audience(room);
    final label = _text(room['personal_label']);
    return LiveRoom(
      roomId: ccid,
      platform: _site,
      userId: jsonString(room['cid']) ?? jsonString(room['channel_id']),
      link: roomUrl(ccid),
      title: _text(room['title']),
      nick: _text(room['nickname']),
      avatar: normalizeImageUrl(room['purl']),
      cover: _image(room['cover'], room['poster']),
      area: jsonString(room['gamename']),
      watching: audience.popularity.ifEmpty(() => audience.online.ifEmpty(() => _text(room['follower_num']))),
      popularity: audience.popularity,
      onlineViewers: audience.online,
      audienceMetricType: audience.popularity.isNotEmpty
          ? AudienceMetricType.popularity
          : audience.online.isNotEmpty
          ? AudienceMetricType.onlineViewers
          : AudienceMetricType.followers,
      liveStatus: _status(room['status']) == LiveStatus.live ? LiveStatus.live : LiveStatus.offline,
      introduction: label.isEmpty ? null : label,
      notice: label.isEmpty ? null : label,
      data: CcRoomData(
        streams: _object(room['quickplay']) ?? _object(room['stream_list']),
        playlist: jsonString(room['m3u8']),
      ),
    );
  }

  /// A room whose anchor has no live channel, for follow refreshes and
  /// recordings: only the identity and the offline state, every other field
  /// "not in this response" (a merge keeps the stored ones). `activitylives`
  /// answers an unknown id the same way; only room entry asks the room page
  /// ([pageRoom]) to tell them apart.
  static LiveRoom offlineRoom(String ccid) =>
      LiveRoom(roomId: ccid, platform: _site, link: roomUrl(ccid), watching: '', liveStatus: LiveStatus.offline);

  static final RegExp _nextData = RegExp(r'<script id="__NEXT_DATA__"[^>]*>([\s\S]*?)</script>');

  /// The room page of an anchor without a live channel, on room entry
  /// (`cc.163.com/{ccid}/?open=blizzardtv&from=8382&platform=ds`, whose
  /// `__NEXT_DATA__` holds `props.pageProps.roomInfoInitData`): `code` 404
  /// (`no ccid`) is `NotFound`; anything else is the anchor's offline room.
  /// 3.x failed here and showed the room as unknown. Fields as in
  /// [channelRoom]: without heat or viewers the audience is the follower
  /// count; the introduction and notice are the `announcement`.
  static LiveRoom pageRoom(String html, {required String ccid, int status = 200}) {
    _checkStatus(status, 'room page');
    final script = _nextData.firstMatch(html)?.group(1);
    final data = script == null ? null : _object(_tryDecode(script));
    final info = _object(_object(_object(data?['props'])?['pageProps'])?['roomInfoInitData']);
    if (info == null) throw const ApiChanged(_site, 'room page: no roomInfoInitData');
    if (jsonInt(info['code']) == 404) {
      throw NotFound(_site, 'room page: ${jsonString(info['reason']) ?? 'no ccid'} ($ccid)');
    }
    final anchor = _fields(info['micfirst']);
    final live = _fields(info['live']);
    final id = _cuteid(anchor['ccid'] ?? info['ccid'] ?? live['ccid']);
    if (id != ccid) throw ApiChanged(_site, 'room page: answered ccid $id for $ccid');
    final nick = _text(anchor['nickname']).ifEmpty(() => _text(info['nickname']));
    if (nick.isEmpty) throw const ApiChanged(_site, 'room page: no nickname');
    final announcement = _text(info['announcement']);
    return LiveRoom(
      roomId: ccid,
      platform: _site,
      userId: jsonString(info['channel_id']) ?? jsonString(live['channel_id']),
      link: roomUrl(ccid),
      title: _text(info['live_title']).ifEmpty(() => _text(live['title'])),
      nick: nick,
      avatar: _image(anchor['purl'], anchor['portraiturl']).ifEmpty(() => normalizeImageUrl(info['purl'])),
      area: jsonString(info['gamename']) ?? jsonString(live['gamename']),
      watching: _text(info['follower_num']).ifEmpty(() => _text(live['follower_num'])),
      audienceMetricType: AudienceMetricType.followers,
      liveStatus: LiveStatus.offline,
      introduction: announcement.isEmpty ? null : announcement,
      notice: announcement.isEmpty ? null : announcement,
    );
  }

  /// The room's web page (3.x opened `https://cc.163.com/{ccid}`).
  static String roomUrl(String ccid) => '$origin/$ccid/';

  // 3.x's streams -------------------------------------------------------------

  /// 3.x's qualities of a live channel (`getPlayQualites`), what users pick
  /// from: one per tier of [CcRoomData.streams] (`stream_list`: `original`,
  /// `high`, `medium`, `low`), named by 3.x's table (原画, 高清, 标准,
  /// 低清), best first. A quality's data is its URLs: the redirect playlist
  /// with the tier's CDN signature appended (`hs`, `ks`, `ali`, `fws`, `wy`
  /// first), or the tier's own URLs in a `quickplay` object.
  ///
  /// The site ignores the appended signature: every tier plays the same
  /// 1 Mbps HLS stream, as in 3.x (REG-CC-004). [qualities] and
  /// [resolution] (`video_play_url`) are the fallback for a room without a
  /// tier list.
  static List<LivePlayQuality> legacyQualities(CcRoomData data) {
    final raw = data.streams;
    if (raw == null) return const [];
    final live = raw['resolution'] == null;
    final tiers = live ? raw : _object(raw['resolution']);
    if (tiers == null) return const [];
    final base = data.playlist?.trim() ?? '';
    final qualities = <LivePlayQuality>[];
    for (final MapEntry(:key, :value) in tiers.entries) {
      final tier = _object(value);
      if (tier == null) continue;
      final cdns = _object(tier[live ? 'CDN_FMT' : 'cdn']);
      if (cdns == null) continue;
      final preferred = <String>[];
      final others = <String>[];
      for (final MapEntry(key: cdn, value: suffix) in cdns.entries) {
        final url = live && base.isNotEmpty ? _signedPlaylist(base, suffix) : _directUrl(suffix);
        if (Uri.tryParse(url)?.hasScheme != true) continue;
        final target = _preferredCdns.contains(cdn.toLowerCase()) ? preferred : others;
        if (!target.contains(url)) target.add(url);
      }
      final urls = [...preferred, ...others];
      if (urls.isEmpty) continue;
      final kbps = int.tryParse(tier['vbr']?.toString() ?? '') ?? 0;
      qualities.add(
        LivePlayQuality(
          quality: LiveQualityLabel.normalize(
            platform: _site,
            rawLabel: _legacyNames[key] ?? key,
            id: key,
            bitrate: kbps > 0 ? kbps * 1000 : null,
          ),
          id: key,
          sort: _legacySort(key, kbps),
          data: List<String>.unmodifiable(urls),
        ),
      );
    }
    return qualities..sort((a, b) => b.sort.compareTo(a.sort));
  }

  /// The lines of a [legacyQualities] quality: its URLs as they are, each
  /// with the media headers for [roomId] and its format; no lease (every
  /// open asks the redirect again). The quality is assumed applied, as 3.x
  /// did.
  static LivePlayUrlResolution legacyResolution(LivePlayQuality quality, {required String roomId}) {
    final headers = mediaHeaders(roomId);
    final data = quality.data;
    return LivePlayUrlResolution.lines([
      for (final item in data is List ? data : const <Object?>[])
        if ('$item'.trim() case final url when url.isNotEmpty)
          if (Uri.tryParse(url) case final uri?) LivePlayLine(url, headers: headers, format: format(uri)),
    ], appliedQualityData: quality.selectionId);
  }

  /// CDNs whose lines 3.x put first.
  static const List<String> _preferredCdns = ['hs', 'ks', 'ali', 'fws', 'wy'];

  /// 3.x's names for the tier codes.
  static const Map<String, String> _legacyNames = {
    'blueray': '原画',
    'original': '原画',
    'high': '高清',
    'medium': '标准',
    'standard': '标准',
    'low': '低清',
    'ultra': '蓝光',
  };

  /// 3.x's order: the tier's rank (a missing `vbr` must not demote 原画),
  /// then the bitrate; unknown tiers by bitrate alone.
  static int _legacySort(String code, int kbps) {
    final rank = switch (code.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '')) {
      'blueray' || 'original' || 'origin' || 'source' => 6,
      'ultra' => 5,
      'high' || 'hd' => 4,
      'medium' || 'standard' || 'sd' => 3,
      'low' || 'ld' => 2,
      _ => 0,
    };
    return rank == 0 ? kbps : rank * 1000000 + kbps.clamp(0, 999999);
  }

  /// [base] with a `CDN_FMT` value: a protocol-relative or absolute http(s)
  /// URL as it is, a signature appended to the query, nothing for another
  /// scheme (3.x's `_resolveLiveCdnUrl`).
  static String _signedPlaylist(String base, Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.startsWith('//')) return 'https:$text';
    final direct = Uri.tryParse(text);
    if (direct != null && direct.hasScheme) {
      return const {'http', 'https'}.contains(direct.scheme.toLowerCase()) ? text : '';
    }
    if (text.isEmpty) return base;
    return '$base${base.contains('?') ? '&' : '?'}${text.replaceFirst(RegExp('^[?&]+'), '')}';
  }

  static String _directUrl(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.startsWith('//') ? 'https:$text' : text;
  }

  // Fallback streams: video_play_url ------------------------------------------

  /// `vapi.cc.163.com/video_play_url/{ccid}` → its object. HTTP 410
  /// (`Gone`, "no live") and 404 are `StreamUnavailable`.
  static Map<String, dynamic> playData(String body, {int status = 200}) {
    if (status == 410 || status == 404) throw StreamUnavailable(_site, 'video_play_url: HTTP $status');
    final data = _object(_decode(body, status: status, what: 'video_play_url'));
    if (data == null) throw ApiChanged(_site, 'video_play_url: not an object (${_snippet(body)})');
    return data;
  }

  /// Qualities of a play answer: `vbrname_list` in the server's order, best
  /// first (`vbrname_sel` alone when the list is empty). The id and data are
  /// the tier code (`original`, `ultra`, `high`, `standard`, …) sent as
  /// `vbrname`; the label is the site's own name (`vbrname_mapping`), else
  /// 3.x's name for the code.
  static List<LivePlayQuality> qualities(Map<String, dynamic> data) {
    final codes = <String>[for (final raw in _list(data['vbrname_list'])) ?jsonString(raw)];
    if (codes.isEmpty) {
      final selected = jsonString(data['vbrname_sel']);
      if (selected == null) throw const ApiChanged(_site, 'video_play_url: no vbrname_list or vbrname_sel');
      codes.add(selected);
    }
    final names = _fields(data['vbrname_mapping']);
    final unique = codes.toSet().toList();
    return [
      for (final (index, code) in unique.indexed)
        LivePlayQuality(
          quality: LiveQualityLabel.normalize(
            platform: _site,
            rawLabel: jsonString(names[code]) ?? _legacyNames[code] ?? code,
            id: code,
          ),
          id: code,
          data: code,
          sort: unique.length - index,
        ),
    ];
  }

  /// The CDN codes of `cdn_list` that the answer's own lines do not cover;
  /// each is asked for once more with `cdn={code}`.
  static List<String> uncoveredCdns(Map<String, dynamic> data) {
    final covered = {for (final line in _answerLines(data)) line.cdn};
    return [
      for (final raw in _list(data['cdn_list']))
        if (jsonString(raw) case final code? when covered.add(code)) code,
    ];
  }

  /// The lines of the play answers for one quality: [answers] first the
  /// answer to the quality request, then the ones for the other CDNs.
  ///
  /// An answer has `videourl` on `cdn_sel` and `bakvideourl` on
  /// `bakcdn_sel`. The first answer's `vbrname_sel` is the applied quality;
  /// a CDN answer at another tier is dropped, and each CDN code (the line
  /// id) is kept once: a server answering `cdn=hs` with ali again gives no
  /// invented hs line. Every line carries the media headers for [roomId]
  /// and the lease of its `auth_key`. An answer without any URL is
  /// `ApiChanged`.
  static LivePlayUrlResolution resolution(
    List<({Map<String, dynamic> data, DateTime issuedAt})> answers, {
    required String roomId,
  }) {
    if (answers.isEmpty) throw const ApiChanged(_site, 'video_play_url: no answer');
    final applied = jsonString(answers.first.data['vbrname_sel']);
    final headers = mediaHeaders(roomId);
    final cdns = <String>{};
    final urls = <String>{};
    final lines = <LivePlayLine>[
      for (final (index, answer) in answers.indexed)
        if (index == 0 || jsonString(answer.data['vbrname_sel']) == applied)
          for (final line in _answerLines(answer.data))
            if (cdns.add(line.cdn) && urls.add(line.url.toString()))
              LivePlayLine(
                line.url.toString(),
                headers: headers,
                format: format(line.url),
                lineId: line.cdn,
                lease: lease(line.url, answer.issuedAt),
              ),
    ];
    if (lines.isEmpty) throw const ApiChanged(_site, 'video_play_url: no playable URL');
    return LivePlayUrlResolution.lines(lines, appliedQualityData: applied, qualityUnconfirmed: applied == null);
  }

  static List<({String cdn, Uri url})> _answerLines(Map<String, dynamic> data) => [
    for (final (urlKey, cdnKey) in const [('videourl', 'cdn_sel'), ('bakvideourl', 'bakcdn_sel')])
      if (jsonUrl(data[urlKey]) case final url?) (cdn: jsonString(data[cdnKey]) ?? url.host, url: url),
  ];

  /// The container by the URL path: `.m3u8` is HLS, `.flv` FLV (every line
  /// seen so far).
  static StreamFormat format(Uri url) {
    final path = url.path.toLowerCase();
    if (path.endsWith('.m3u8')) return StreamFormat.hls;
    if (path.endsWith('.flv')) return StreamFormat.flv;
    return StreamFormat.other;
  }

  /// Media request headers for [roomId] (3.x's `PlaybackHeaderResolver`):
  /// UA, Origin and the room page as Referer. CC has no cookie.
  static Map<String, String> mediaHeaders(String roomId) {
    final id = Uri.encodeComponent(roomId.trim());
    return {'user-agent': userAgent, 'origin': origin, 'referer': id.isEmpty ? '$origin/' : '$origin/$id/'};
  }

  /// The lease of a media URL received at [issuedAt], from the first field
  /// of its `auth_key` (`{Unix seconds}-{rand}-{uid}-{md5}`, 300 seconds
  /// after issue): renew [leaseLead] (at most a quarter of the lifetime)
  /// before. Expiry refuses new connections only; an established one keeps
  /// flowing. No key, or one already past, is no lease.
  static PlayLease? lease(Uri url, DateTime issuedAt) {
    final match = RegExp(r'(?:^|&)auth_key=(\d+)-').firstMatch(url.query);
    final expires = match == null ? null : int.tryParse(match.group(1)!);
    if (expires == null || expires <= 0) return null;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true);
    final lifetime = expiresAt.difference(issuedAt);
    if (lifetime <= Duration.zero) return null;
    final quarter = lifetime ~/ 4;
    return PlayLease(refreshAt: expiresAt.subtract(quarter < leaseLead ? quarter : leaseLead), expiresAt: expiresAt);
  }

  // Helpers -------------------------------------------------------------------

  /// 3.x's `parseRoomAudience`: heat is the first of `webcc_visitor`,
  /// `hot_score`, `visitor`, `total_visitor` (aliases of one value);
  /// concurrent viewers are `vision_visitor`, else `online_num`. Values are
  /// kept as written when they hold a digit.
  static ({String popularity, String online}) _audience(Map<String, dynamic> room) {
    String first(List<String> keys) {
      for (final key in keys) {
        final text = room[key]?.toString().trim() ?? '';
        if (text.isNotEmpty && text != 'null' && RegExp('[0-9]').hasMatch(text)) return text;
      }
      return '';
    }

    return (
      popularity: first(const ['webcc_visitor', 'hot_score', 'visitor', 'total_visitor']),
      online: first(const ['vision_visitor', 'online_num']),
    );
  }

  static LiveStatus _status(Object? value) => switch (int.tryParse(value?.toString() ?? '')) {
    1 => LiveStatus.live,
    0 => LiveStatus.offline,
    _ => LiveStatus.unknown,
  };

  static Map<String, dynamic> _catalogEnvelope(String body, {required int status, required String what}) {
    final envelope = _object(_decode(body, status: status, what: what));
    if (envelope == null || envelope['code'] != 200) throw ApiChanged(_site, '$what: code ${envelope?['code']}');
    return envelope;
  }

  static Map<String, dynamic> _catalogMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    throw const ApiChanged(_site, 'catalog: expected an object');
  }

  static List<Object?> _catalogList(Object? value, int limit) {
    if (value is List && value.length <= limit) return value.cast<Object?>();
    throw const ApiChanged(_site, 'catalog: expected a list');
  }

  static String _catalogText(Object? value, int limit) {
    if (value is String && value.trim().isNotEmpty && value.length <= limit) return value.trim();
    throw const ApiChanged(_site, 'catalog: expected a text');
  }

  static bool _hidden(Map<String, dynamic> value) {
    final hidden = value['hidden'];
    if (hidden != null && hidden is! bool) throw const ApiChanged(_site, 'catalog: hidden is not a bool');
    return hidden == true;
  }

  /// An https image with a host and no user info, else empty (3.x's catalog
  /// rule).
  static String _httpsImage(Object? value) {
    if (value is! String || value.length > 2048) return '';
    final uri = Uri.tryParse(value);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty ? value : '';
  }
}

/// A `cuteid`/`ccid` (number or string) as the room id, or null.
String? _cuteid(Object? value) {
  if (value is int) return value > 0 && value <= 9007199254740991 ? '$value' : null;
  if (value is String && CcApi.ccidPattern.hasMatch(value)) return value;
  return null;
}

/// [value], else [fallback], made absolute by [normalizeImageUrl]; empty
/// when neither is an image.
String _image(Object? value, [Object? fallback]) => normalizeImageUrl(value).ifEmpty(() => normalizeImageUrl(fallback));

/// A field as 3.x wrote it (the string itself, a number as text), empty
/// when missing (3.x wrote "null" or null).
String _text(Object? value) => switch (value) {
  final String text => text,
  final num number => '$number',
  _ => '',
};

extension on String {
  String ifEmpty(String Function() other) => isEmpty ? other() : this;
}

Map<String, dynamic>? _object(Object? value) => value is Map<String, dynamic> ? value : null;

/// An object field, or an empty one: a missing field reads as empty.
Map<String, dynamic> _fields(Object? value) => value is Map<String, dynamic> ? value : const {};

List<Object?> _list(Object? value) => value is List ? value.cast<Object?>() : const [];

Object? _tryDecode(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// The JSON of a response after [_checkStatus]; a body that is not JSON is
/// `ApiChanged`.
Object? _decode(String body, {required int status, required String what}) {
  _checkStatus(status, what);
  try {
    return jsonDecode(body);
  } on FormatException {
    throw ApiChanged(_site, '$what: not JSON (${_snippet(body)})');
  }
}

/// HTTP 429 → `RateLimited`; 5xx → `NetworkFailure`; any other non-2xx →
/// `ApiChanged`.
void _checkStatus(int status, String what) {
  if (status >= 200 && status < 300) return;
  if (status == 429) throw RateLimited(_site, detail: '$what: HTTP 429');
  if (status >= 500) throw NetworkFailure(_site, '$what: HTTP $status');
  throw ApiChanged(_site, '$what: HTTP $status');
}

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}
