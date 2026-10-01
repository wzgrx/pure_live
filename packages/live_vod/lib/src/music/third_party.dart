import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// Platform id of third-party requests (playlist mirrors, lyric services):
/// the app routes it through the proxy setting like any platform. From the
/// test machine the NetEase mirror reset the TLS handshake when direct and
/// answered through the proxy (M14.0).
const String thirdPartySite = 'music_third_party';

const String _browser =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';

/// Addresses of the third-party services music mode uses. Every one is run
/// by someone else: an import sends the playlist id to the mirror, a lyric
/// lookup sends the song title and artist to the lyric service. The
/// defaults are pure_live_TV's (`b9d2f739` `music_provider.dart`,
/// `third_party_lyric_api.dart`); settings can point them elsewhere (a
/// self-hosted NeteaseCloudMusicApi / KuGouMusicApi works the same).
@immutable
final class ThirdPartyEndpoints {
  /// Creates the endpoints.
  const new({
    this.neteasePlaylist = 'https://rp.u2x1.work',
    this.kugouPlaylist = 'https://kg.u2x1.work',
    this.tencentPlaylist = 'https://api.timelessq.com',
    this.rangotecLyric = 'https://tools.rangotec.com',
    this.lrcCxLyric = 'https://api.lrc.cx',
    this.neteaseLyric = 'https://music.163.com',
  });

  /// Reads the settings shape written by [toJson]; missing or invalid
  /// addresses keep their defaults.
  factory fromJson(Map<String, Object?> json) {
    String pick(String key, String fallback) {
      final value = jsonString(json[key]);
      final uri = value == null ? null : Uri.tryParse(value);
      return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty
          ? value!.replaceFirst(RegExp(r'/+$'), '')
          : fallback;
    }

    const defaults = ThirdPartyEndpoints();
    return ThirdPartyEndpoints(
      neteasePlaylist: pick('neteasePlaylist', defaults.neteasePlaylist),
      kugouPlaylist: pick('kugouPlaylist', defaults.kugouPlaylist),
      tencentPlaylist: pick('tencentPlaylist', defaults.tencentPlaylist),
      rangotecLyric: pick('rangotecLyric', defaults.rangotecLyric),
      lrcCxLyric: pick('lrcCxLyric', defaults.lrcCxLyric),
      neteaseLyric: pick('neteaseLyric', defaults.neteaseLyric),
    );
  }

  /// NeteaseCloudMusicApi instance (`/playlist/track/all?id=`).
  final String neteasePlaylist;

  /// KuGouMusicApi instance (`/playlist/track/all?id=&pagesize=`).
  final String kugouPlaylist;

  /// QQ Music songlist proxy (`/music/tencent/songList?disstid=`).
  final String tencentPlaylist;

  /// rangotec LRC service (`/api/anon/lrc?title=&artist=`).
  final String rangotecLyric;

  /// lrc.cx (`/lyrics?title=&artist=`).
  final String lrcCxLyric;

  /// NetEase's own web API (search and lyric), used as the last lyric
  /// fallback.
  final String neteaseLyric;

  /// The settings shape.
  Map<String, Object?> toJson() => {
    'neteasePlaylist': neteasePlaylist,
    'kugouPlaylist': kugouPlaylist,
    'tencentPlaylist': tencentPlaylist,
    'rangotecLyric': rangotecLyric,
    'lrcCxLyric': lrcCxLyric,
    'neteaseLyric': neteaseLyric,
  };
}

/// Where an imported playlist comes from.
enum PlaylistPlatform {
  /// 网易云音乐.
  netease,

  /// 酷狗音乐.
  kugou,

  /// QQ 音乐 (the TV client's third source).
  tencent,
}

/// One song of an imported playlist: what the matcher searches for.
@immutable
final class ImportedTrack {
  /// Creates a song.
  const new({required this.name, required this.artist, required this.duration});

  /// Song name.
  final String name;

  /// Artists, joined.
  final String artist;

  /// Length.
  final Duration duration;

  @override
  String toString() => '$name - $artist (${duration.inSeconds}s)';
}

/// Reads playlists of other music platforms through the configured mirrors
/// (pure_live_TV `b9d2f739` `MusicProvider`).
final class PlaylistImportSource {
  /// Creates the source.
  const new(this.http, {this.endpoints = const ThirdPartyEndpoints()});

  /// Transport.
  final LiveHttp http;

  /// Service addresses.
  final ThirdPartyEndpoints endpoints;

  static final RegExp _neteaseLink = RegExp(r'music\.163\.com/.*?playlist.*?[?&]id=(\d+)');
  static final RegExp _qqLink = RegExp(r'y\.qq\.com/.*?playlist/(\d+)|[?&]id=(\d+)');
  static final RegExp _kugouLink = RegExp(r'(gcid_[0-9a-z]+|collection_\d+_\d+_\d+_\d+)', caseSensitive: false);

  /// The platform and id of what the user pasted: a share link, a bare id,
  /// or `platform:id` (the TV client's prefix). [platform] is the one the
  /// user picked; links override it. Null when nothing looks like an id.
  static ({PlaylistPlatform platform, String id})? parse(String input, {PlaylistPlatform? platform}) {
    final text = input.trim();
    if (text.isEmpty) return null;
    if (_neteaseLink.firstMatch(text) case final match?) {
      return (platform: PlaylistPlatform.netease, id: match.group(1)!);
    }
    if (text.contains('kugou.com') || text.contains('collection_') || text.startsWith('gcid_')) {
      final match = _kugouLink.firstMatch(text);
      if (match != null) return (platform: PlaylistPlatform.kugou, id: match.group(1)!);
    }
    if (text.contains('y.qq.com')) {
      final match = _qqLink.firstMatch(text);
      final id = match?.group(1) ?? match?.group(2);
      if (id != null) return (platform: PlaylistPlatform.tencent, id: id);
    }
    final prefixed = RegExp(r'^(netease|kugou|tencent)\s*:\s*(\S+)$').firstMatch(text);
    if (prefixed != null) {
      return (platform: PlaylistPlatform.values.byName(prefixed.group(1)!), id: prefixed.group(2)!);
    }
    if (platform != null && RegExp(r'^[0-9A-Za-z_]+$').hasMatch(text)) return (platform: platform, id: text);
    return null;
  }

  Future<LiveResponse> _get(Uri url) async {
    try {
      return await http.send(LiveRequest(site: thirdPartySite, url: url, headers: const {'user-agent': _browser}));
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(thirdPartySite, failure.toString());
    }
  }

  Map<String, dynamic> _json(LiveResponse response, String what) {
    if (response.status == 404) throw NotFound(thirdPartySite, '$what: HTTP 404');
    if (response.status >= 500) throw NetworkFailure(thirdPartySite, '$what: HTTP ${response.status}');
    try {
      final decoded = jsonDecode(response.text);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Below.
    }
    throw ApiChanged(thirdPartySite, '$what: HTTP ${response.status}, not a JSON object');
  }

  /// The songs of a playlist. `NotFound` when the platform knows no such
  /// playlist, `NetworkFailure` when the mirror cannot be reached.
  Future<List<ImportedTrack>> fetch(PlaylistPlatform platform, String id) => switch (platform) {
    PlaylistPlatform.netease => _netease(id),
    PlaylistPlatform.kugou => _kugou(id),
    PlaylistPlatform.tencent => _tencent(id),
  };

  Future<List<ImportedTrack>> _netease(String id) async {
    final json = _json(
      await _get(Uri.parse('${endpoints.neteasePlaylist}/playlist/track/all').replace(queryParameters: {'id': id})),
      'netease playlist',
    );
    if (jsonInt(json['code']) != 200) throw NotFound(thirdPartySite, 'netease playlist: code ${json['code']}');
    return neteaseTracks(json);
  }

  /// NetEase `songs[]`: `name`, `ar[].name`, `dt` (ms).
  static List<ImportedTrack> neteaseTracks(Map<String, dynamic> json) => [
    for (final song in _rows(json['songs']))
      if (jsonString(song['name']) case final String name)
        ImportedTrack(
          name: name,
          artist: [for (final artist in _rows(song['ar'])) ?jsonString(artist['name'])].join('/'),
          duration: Duration(milliseconds: jsonInt(song['dt']) ?? 0),
        ),
  ];

  Future<List<ImportedTrack>> _kugou(String input) async {
    var id = input;
    if (id.startsWith('gcid_')) {
      // A share link's gcid names the list page, whose data names the id.
      final page = await _get(Uri.parse('https://www.kugou.com/songlist/$id/'));
      id = RegExp('"list_create_gid":"([^"]+)"').firstMatch(page.text)?.group(1) ?? id;
    }
    final tracks = <ImportedTrack>[];
    for (var page = 1; page <= 20; page++) {
      final json = _json(
        await _get(
          Uri.parse('${endpoints.kugouPlaylist}/playlist/track/all')
              .replace(queryParameters: {'id': id, 'pagesize': '300', if (page > 1) 'page': '$page'}),
        ),
        'kugou playlist',
      );
      if (jsonInt(json['status']) != 1) {
        if (page == 1) throw NotFound(thirdPartySite, 'kugou playlist: status ${json['status']}');
        break;
      }
      final data = _object(json['data']);
      final rows = kugouTracks(data);
      tracks.addAll(rows);
      if (rows.isEmpty || tracks.length >= (jsonInt(data['count']) ?? 0)) break;
    }
    return tracks;
  }

  /// KuGou `data.info[]`: `name` is `歌手 - 歌名` (artist first; the TV
  /// client split it the other way round and searched for the artist as
  /// the song), `singerinfo[].name`, `timelen` (ms).
  static List<ImportedTrack> kugouTracks(Map<String, dynamic> data) {
    final out = <ImportedTrack>[];
    for (final song in _rows(data['info'])) {
      final full = jsonString(song['name']);
      if (full == null) continue;
      final singers = [for (final singer in _rows(song['singerinfo'])) ?jsonString(singer['name'])];
      final split = full.indexOf(' - ');
      final named = split < 0 ? '' : full.substring(0, split).trim();
      final title = split < 0 ? full : full.substring(split + 3).trim();
      out.add(
        ImportedTrack(
          name: title,
          artist: singers.isNotEmpty ? singers.join('、') : named,
          duration: Duration(milliseconds: jsonInt(song['timelen']) ?? 0),
        ),
      );
    }
    return out;
  }

  Future<List<ImportedTrack>> _tencent(String id) async {
    final json = _json(
      await _get(
        Uri.parse('${endpoints.tencentPlaylist}/music/tencent/songList').replace(queryParameters: {'disstid': id}),
      ),
      'tencent playlist',
    );
    if (jsonInt(json['errno']) != 0) throw NotFound(thirdPartySite, 'tencent playlist: errno ${json['errno']}');
    final data = _object(json['data']);
    return [
      for (final song in _rows(data['songlist']))
        if (jsonString(song['songname']) case final String name)
          ImportedTrack(
            name: name,
            artist: [for (final singer in _rows(song['singer'])) ?jsonString(singer['name'])].join(', '),
            duration: Duration(seconds: jsonInt(song['interval']) ?? 0),
          ),
    ];
  }
}

/// A lyric some source offers for a song, unverified.
@immutable
final class LyricCandidate {
  /// Creates a candidate.
  const new({required this.source, required this.lrc, this.title = '', this.artist = ''});

  /// `bilibili`, `lrccx`, `rangotec`, `netease`, `manual`.
  final String source;

  /// The song the source says it is (empty when it does not say).
  final String title;

  /// Its artist.
  final String artist;

  /// LRC text as received.
  final String lrc;
}

/// The third-party lyric services (pure_live_TV `b9d2f739`
/// `third_party_lyric_api.dart`): lrc.cx, rangotec and NetEase. Each probe
/// returns nothing instead of failing, so a missing lyric never becomes an
/// error over the player.
final class ThirdPartyLyrics {
  /// Creates the client.
  const new(this.http, {this.endpoints = const ThirdPartyEndpoints()});

  /// Transport.
  final LiveHttp http;

  /// Service addresses.
  final ThirdPartyEndpoints endpoints;

  Future<String?> _probe(Uri url) async {
    try {
      final response = await http.send(
        LiveRequest(
          site: thirdPartySite,
          url: url,
          headers: const {'user-agent': _browser, 'referer': 'https://music.163.com/'},
        ),
      );
      return response.status == 200 && response.text.trim().isNotEmpty ? response.text : null;
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      return null;
    }
  }

  static Object? _decode(String? body) {
    if (body == null) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  /// lrc.cx: one plain LRC.
  Future<List<LyricCandidate>> lrcCx({required String title, required String artist}) async {
    final body = await _probe(
      Uri.parse('${endpoints.lrcCxLyric}/lyrics').replace(queryParameters: {'title': title, 'artist': artist}),
    );
    if (body == null || body.trimLeft().startsWith('{')) return const [];
    return [LyricCandidate(source: 'lrccx', lrc: body)];
  }

  /// rangotec: `{code: 200, data: [{title, artist, lrc}]}`, at most [limit].
  Future<List<LyricCandidate>> rangotec({required String title, required String artist, int limit = 6}) async =>
      rangotecCandidates(
        await _probe(
          Uri.parse('${endpoints.rangotecLyric}/api/anon/lrc')
              .replace(queryParameters: {'title': title, 'artist': artist}),
        ),
        limit: limit,
      );

  /// The rangotec answer [body] as candidates.
  static List<LyricCandidate> rangotecCandidates(String? body, {int limit = 6}) {
    final decoded = _decode(body);
    if (decoded is! Map) return const [];
    final data = decoded['data'];
    final rows = data is List ? data : [if (data is Map) data];
    return [
      for (final row in _rows(rows).take(limit))
        if (jsonString(row['lrc']) case final String lrc)
          LyricCandidate(
            source: 'rangotec',
            lrc: lrc,
            title: jsonString(row['title']) ?? '',
            artist: jsonString(row['artist']) ?? '',
          ),
    ];
  }

  /// NetEase: search [text], then each hit's lyric, at most [limit].
  Future<List<LyricCandidate>> netease(String text, {int limit = 3}) async {
    final search = _decode(
      await _probe(
        Uri.parse('${endpoints.neteaseLyric}/api/search/get/web')
            .replace(queryParameters: {'s': text, 'type': '1', 'limit': '10'}),
      ),
    );
    final songs = search is Map && search['result'] is Map ? (search['result'] as Map)['songs'] : null;
    final out = <LyricCandidate>[];
    for (final song in _rows(songs)) {
      if (out.length >= limit) break;
      final id = jsonInt(song['id']);
      if (id == null) continue;
      final lyric = _decode(
        await _probe(
          Uri.parse('${endpoints.neteaseLyric}/api/song/lyric')
              .replace(queryParameters: {'id': '$id', 'lv': '1', 'kv': '1', 'tv': '-1'}),
        ),
      );
      final lrc = lyric is Map && lyric['lrc'] is Map ? jsonString((lyric['lrc'] as Map)['lyric']) : null;
      if (lrc == null) continue;
      final artists = song['artists'];
      out.add(
        LyricCandidate(
          source: 'netease',
          lrc: lrc,
          title: jsonString(song['name']) ?? '',
          artist: artists is List && artists.isNotEmpty && artists.first is Map
              ? jsonString((artists.first as Map)['name']) ?? ''
              : '',
        ),
      );
    }
    return out;
  }
}

/// The JSON objects of the array [value] (nothing when it is not one).
Iterable<Map<String, dynamic>> _rows(Object? value) =>
    value is List ? value.whereType<Map<String, dynamic>>() : const <Map<String, dynamic>>[];

/// [value] as a JSON object (empty when it is not one).
Map<String, dynamic> _object(Object? value) => value is Map<String, dynamic> ? value : const <String, dynamic>{};
