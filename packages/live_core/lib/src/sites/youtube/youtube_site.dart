import 'dart:async';
import 'dart:convert';

import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/youtube/youtube_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'youtube';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// The YouTube live adapter (spec/sites/youtube.md): the "Live" destination,
/// live search, and details and HLS from the InnerTube player API. Needs the
/// platform's proxy route in regions where YouTube is blocked; media must use
/// the same route (the manifest is bound to the requesting IP, §5).
final class YouTubeSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter.
  new(this.http);

  /// Transport.
  final LiveHttp http;

  @override
  String get id => _site;

  @override
  String get name => 'YouTube';

  static const _web = {
    'client': {'clientName': 'WEB', 'clientVersion': '2.20260925.01.00', 'hl': 'en', 'gl': 'US'},
  };
  static const _android = {
    'client': {'clientName': 'ANDROID', 'clientVersion': '21.08.266', 'hl': 'en', 'gl': 'US'},
  };

  static const Map<String, String> _headers = {
    'content-type': 'application/json',
    'origin': 'https://www.youtube.com',
    'cookie': 'SOCS=CAI',
    'user-agent': _userAgent,
  };

  Future<String> _send(LiveRequest request) async {
    final LiveResponse response;
    try {
      response = await http.send(request);
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
    final status = response.status;
    if (status == 401 || status == 403) throw RiskControl(_site, detail: 'HTTP $status ${request.url.path}');
    if (status == 429) throw RateLimited(_site, detail: 'HTTP 429 ${request.url.path}');
    if (status >= 500) throw NetworkFailure(_site, 'HTTP $status ${request.url.path}');
    if (status != 200) throw ApiChanged(_site, 'HTTP $status ${request.url.path}');
    return response.text;
  }

  Future<String> _post(String endpoint, Map<String, Object?> body) => _send(
    LiveRequest(
      site: _site,
      method: 'POST',
      url: Uri.parse('https://www.youtube.com/youtubei/v1/$endpoint?prettyPrint=false'),
      headers: _headers,
      body: utf8.encode(jsonEncode(body)),
    ),
  );

  @override
  Future<List<Category>> categories() async => const [];

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async =>
      throw NotFound(_site, 'no area ${area.id}: YouTube has one live destination');

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) async {
    if (cursor != null) return const Page.empty();
    return YouTubeParse.destination(await _post('browse', {'context': _web, 'browseId': YouTubeParse.liveDestination}));
  }

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final query = keyword.trim();
    if (query.isEmpty) return const Page.empty();
    final body = cursor == null
        ? {'context': _web, 'query': query, 'params': YouTubeParse.liveFilter}
        : {'context': _web, 'continuation': cursor.value};
    return YouTubeParse.search(await _post('search', body));
  }

  Future<({String? video, String? channel})> _resolveUrl(String url) async =>
      YouTubeParse.resolved(await _post('navigation/resolve_url', {'context': _web, 'url': url}));

  Future<YouTubePlayer> _player(String video, {required String roomId}) async => YouTubeParse.player(
    await _post('player', {'context': _android, 'videoId': video, 'contentCheckOk': true, 'racyCheckOk': true}),
    roomId: roomId,
  );

  /// §4 a channel room: its live page names the current broadcast, if any.
  Future<YouTubePlayer?> _channelLive(String channel) async {
    final target = await _resolveUrl('https://www.youtube.com/channel/$channel/live');
    final video = target.video;
    return video == null ? null : await _player(video, roomId: channel);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    final id = ref.roomId;
    if (YouTubeParse.videoId.hasMatch(id)) return (await _player(id, roomId: id)).detail;
    if (!YouTubeParse.channelId.hasMatch(id)) throw NotFound(_site, 'not a video or channel id: $id');
    final live = await _channelLive(id);
    if (live != null) return live.detail;
    // §4 offline channel: its feed names it.
    final feed = await _send(
      LiveRequest(
        site: _site,
        url: Uri.https('www.youtube.com', '/feeds/videos.xml', {'channel_id': id}),
        headers: const {'user-agent': _userAgent},
      ),
    );
    final name = YouTubeParse.feedTitle(feed) ?? '';
    return RoomDetail(
      card: RoomCard(ref: ref, title: name, anchorName: name, state: LiveState.offline),
      link: YouTubeParse.link(id),
      danmakuKeys: {'channelId': id},
    );
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final id = room.ref.roomId;
    final player = YouTubeParse.channelId.hasMatch(id) ? await _channelLive(id) : await _player(id, roomId: id);
    final hls = player?.hls;
    if (player == null || player.detail.state != LiveState.live) throw const StreamUnavailable(_site, 'not live');
    if (hls == null) throw const StreamUnavailable(_site, 'no hlsManifestUrl');
    final line = YouTubeParse.line(hls, headers: const {'user-agent': _userAgent});
    return StreamSet(qualities: const [YouTubeParse.auto], selected: YouTubeParse.auto, lines: [line]);
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (YouTubeParse.videoId.hasMatch(text) || YouTubeParse.channelId.hasMatch(text)) return RoomRef(_site, text);
    if (RegExp(r'^@[A-Za-z0-9._-]{3,30}$').hasMatch(text)) return await _viaResolver('https://www.youtube.com/$text');
    final match = RegExp(r'https?://[^\s，。！？、“”"<>]+').firstMatch(text);
    final url = match == null ? null : Uri.tryParse(match.group(0)!);
    if (url == null) return null;
    final host = url.host.toLowerCase();
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (host == 'youtu.be') {
      final id = segments.firstOrNull;
      return id != null && YouTubeParse.videoId.hasMatch(id) ? RoomRef(_site, id) : null;
    }
    if (host != 'youtube.com' && host != 'www.youtube.com' && host != 'm.youtube.com') return null;
    // An embedded channel player names the channel (legacy L:31-37).
    if (segments case ['embed', 'live_stream']) {
      final channel = url.queryParameters['channel'];
      return channel != null && YouTubeParse.channelId.hasMatch(channel) ? RoomRef(_site, channel) : null;
    }
    final video = switch (segments) {
      ['watch'] => url.queryParameters['v'],
      ['live', final id] || ['embed', final id] || ['v', final id] => id,
      _ => null,
    };
    if (video != null) return YouTubeParse.videoId.hasMatch(video) ? RoomRef(_site, video) : null;
    if (segments case ['channel', final id, ...] when YouTubeParse.channelId.hasMatch(id)) return RoomRef(_site, id);
    if (segments.isNotEmpty && (segments.first.startsWith('@') || segments.first == 'c' || segments.first == 'user')) {
      final path = segments.first.startsWith('@') ? segments.first : '${segments.first}/${segments.elementAtOrNull(1)}';
      return await _viaResolver('https://www.youtube.com/$path');
    }
    return null;
  }

  /// §1 a handle or legacy channel path resolves to its channel id.
  Future<RoomRef> _viaResolver(String url) async {
    final target = await _resolveUrl(url);
    final channel = target.channel;
    if (channel == null) throw NotFound(_site, 'no channel behind $url');
    return RoomRef(_site, channel);
  }
}
