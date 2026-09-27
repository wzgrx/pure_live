import 'dart:async';
import 'dart:math';

import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/liveme/liveme_parse.dart';
import 'package:live_core/src/sites/liveme/liveme_sign.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'liveme';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// The LiveMe adapter (spec/sites/liveme.md): the featured list, streamer
/// search, details from three guest endpoints and signed stream URLs.
final class LiveMeSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter; [now] and [random] are injectable for tests.
  new(this.http, {DateTime Function()? now, Random? random})
    : _now = now ?? DateTime.now,
      _signer = LiveMeSigner(random: random);

  /// Transport.
  final LiveHttp http;
  final DateTime Function() _now;
  final LiveMeSigner _signer;

  @override
  String get id => _site;

  @override
  String get name => 'LiveMe';

  static Map<String, String> _headers({String? shortId}) => {
    'accept': 'application/json, text/plain, */*',
    'accept-language': 'en-US,en;q=0.9',
    'origin': 'https://www.liveme.com',
    'referer': shortId == null ? 'https://www.liveme.com/livehot' : LiveMeParse.link(shortId).toString(),
    'user-agent': _userAgent,
  };

  /// §6.4 media headers.
  static Map<String, String> _mediaHeaders(String shortId) => {
    'origin': 'https://www.liveme.com',
    'referer': LiveMeParse.link(shortId).toString(),
    'user-agent': _userAgent,
  };

  Map<String, String> _guest() => {
    'alias': 'liveme',
    'tongdun_black_box': '1',
    'os': 'web',
    '_time': '${_now().millisecondsSinceEpoch}',
    'h5': '1',
    'thirdchannel': '6',
  };

  Future<LiveResponse> _send(LiveRequest request) async {
    final LiveResponse response;
    try {
      response = await http.send(request);
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
    final status = response.status;
    if (status == 401 || status == 403) throw RiskControl(_site, detail: 'HTTP $status');
    if (status == 420 || status == 429) throw RateLimited(_site, detail: 'HTTP $status');
    if (status >= 500) throw NetworkFailure(_site, 'HTTP $status');
    if (status != 200) throw ApiChanged(_site, 'HTTP $status ${request.url.path}');
    return response;
  }

  Future<String> _get(Uri url, {String? shortId}) async => (await _send(
    LiveRequest(
      site: _site,
      url: url,
      headers: _headers(shortId: shortId),
    ),
  )).text;

  @override
  Future<List<Category>> categories() async => const [];

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async =>
      throw NotFound(_site, 'no area ${area.id}: LiveMe has no categories');

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) async {
    final page = int.tryParse(cursor?.value ?? '') ?? 1;
    final url = Uri.https('lvapi.liveme.com', '/live/featurelist', {
      'countryCode': 'GLOBAL',
      'page_index': '$page',
      'page_size': '20',
      'pid': '3',
      'posid': '3002',
      'h5': '1',
    });
    return LiveMeParse.featured(await _get(url), page: page);
  }

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final query = keyword.trim();
    if (query.isEmpty) return const Page.empty();
    final page = int.tryParse(cursor?.value ?? '') ?? 1;
    final url = Uri.https('live.liveme.com', '/search/searchKeyword', {
      ..._guest(),
      'type': '1',
      'page': '$page',
      'pageSize': '30',
      'keyword': query,
      'tuid': '',
      'uid': '',
      'token': '',
      'androidid': '',
    });
    return LiveMeParse.search(await _get(url), page: page);
  }

  Future<({String userId, String? videoId})> _mapping(String shortId) async {
    final url = Uri.https('live.liveme.com', '/liveme_ent/v1/user/uid_vid_by_short_id', {
      ..._guest(),
      'short_id': shortId,
    });
    return LiveMeParse.mapping(await _get(url, shortId: shortId));
  }

  Future<LiveMeProfile> _profile(String userId) async {
    final url = Uri.https('live.liveme.com', '/user/getinfo', {..._guest(), 'userid': userId});
    return LiveMeParse.profile(await _get(url));
  }

  Future<Map<String, dynamic>> _video(String videoId, {String? shortId}) async {
    const query = {'alias': 'liveme', 'tongdun_black_box': '1', 'os': 'web'};
    final signed = _signer.sign(
      query: query,
      form: {
        '_time': '${_now().millisecondsSinceEpoch}',
        'thirdchannel': '6',
        'videoid': videoId,
        'area': 'en',
        'vali': _signer.vali(),
      },
      now: _now(),
    );
    final response = await _send(
      LiveRequest.form(
        site: _site,
        url: Uri.https('live.liveme.com', '/live/queryinfosimple', query),
        headers: {
          ..._headers(shortId: shortId),
          'lm-s-sign': signed.signature,
        },
        fields: signed.fields,
      ),
    );
    return LiveMeParse.video(response.text, expectedVideoId: videoId);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    final shortId = ref.roomId;
    if (!LiveMeParse.shortId.hasMatch(shortId)) throw NotFound(_site, 'not a short id: $shortId');
    final mapping = await _mapping(shortId);
    final videoId = mapping.videoId;
    final profile = await _profile(mapping.userId);
    final video = videoId == null ? null : await _video(videoId, shortId: shortId);
    if (profile.shortId != shortId) throw ApiChanged(_site, 'getinfo returned ${profile.shortId} for $shortId');
    return LiveMeParse.detail(profile, video);
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final shortId = room.ref.roomId;
    final videoId = (await _mapping(shortId)).videoId;
    if (videoId == null) throw const StreamUnavailable(_site, 'not broadcasting');
    final video = await _video(videoId, shortId: shortId);
    if (LiveMeParse.state(video) != LiveState.live) throw const StreamUnavailable(_site, 'not live');
    final qualities = LiveMeParse.qualities(video);
    if (qualities.isEmpty) throw const StreamUnavailable(_site, 'no media URL');
    final requested = qualities.where((q) => q.id == quality?.id).firstOrNull ?? qualities.first;
    final lines = LiveMeParse.lines(video, requested, headers: _mediaHeaders(shortId));
    return StreamSet(qualities: qualities, selected: requested, lines: lines);
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (LiveMeParse.shortId.hasMatch(text)) return RoomRef(_site, text);
    final match = RegExp(r'https?://[^\s，。！？、“”"<>]+').firstMatch(text);
    final url = match == null ? null : Uri.tryParse(match.group(0)!);
    if (url == null) return null;
    final host = url.host.toLowerCase();
    if (host != 'liveme.com' && host != 'www.liveme.com') return null;
    var segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    // §1 an optional locale segment (`us`, `pe`, `zh-tw`) comes first.
    if (segments.isNotEmpty && RegExp(r'^[a-z]{2}(?:-[a-z]{2,4})?$', caseSensitive: false).hasMatch(segments.first)) {
      segments = segments.sublist(1);
    }
    switch (segments) {
      case ['livehot', 'streaming', final id] when LiveMeParse.shortId.hasMatch(id):
        return RoomRef(_site, id);
      case ['u', final userId] when LiveMeParse.longId.hasMatch(userId):
        return RoomRef(_site, (await _profile(userId)).shortId);
      case ['v', final videoId] || ['m', 'v', final videoId, 'index.html'] when LiveMeParse.longId.hasMatch(videoId):
        final short = _shortIdOf(await _video(videoId));
        return RoomRef(_site, short);
      default:
        return null;
    }
  }

  static String _shortIdOf(Map<String, dynamic> video) {
    final id = video['ushortid']?.toString().trim();
    if (id == null || !LiveMeParse.shortId.hasMatch(id)) throw ApiChanged(_site, 'video without a short id: $id');
    return id;
  }
}
