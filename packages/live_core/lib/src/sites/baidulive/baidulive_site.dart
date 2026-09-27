import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/baidulive/baidulive_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'baidulive';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// The Baidu Live adapter (spec/sites/baidulive.md): the signed channel
/// feed, the room command 371 and the per-resolution FLV/HLS addresses.
final class BaiduLiveSite implements LiveSite, CatalogSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter. [deviceId] (`pc-…`) identifies this client to the
  /// feed; [now] is injectable for tests.
  new(this.http, {String? deviceId, DateTime Function()? now, Random? random})
    : _now = now ?? DateTime.now,
      deviceId =
          deviceId ??
          'pc-${List.generate(20, (_) => (random ?? Random.secure()).nextInt(36).toRadixString(36)).join()}';

  /// Transport.
  final LiveHttp http;

  /// Anonymous device id sent as `uid`.
  final String deviceId;
  final DateTime Function() _now;

  @override
  String get id => _site;

  @override
  String get name => '百度直播';

  static const Map<String, String> _headers = {
    'accept': 'application/json, text/plain, */*',
    'origin': 'https://live.baidu.com',
    'referer': 'https://live.baidu.com/',
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

  /// §2.2 one signed feed request.
  Future<String> _feed(String tab, int channel, ({String session, int index})? after) {
    final first = after == null;
    final form = <String, String>{
      'appname': 'pclive',
      'sid': '',
      'ua': '320_480_pc_1.0_0',
      'uid': deviceId,
      'timestamp': '${_now().millisecondsSinceEpoch ~/ 1000}',
      'source': 'pclive',
      'resource': first ? 'banner,tab,feed' : 'feed',
      'scene': 'pc_channel',
      'session_id': after?.session ?? '',
      'refresh_type': first ? '0' : '1',
      'refresh_index': '${first ? 1 : after.index + 1}',
      'tab': tab,
      'channel_id': '$channel',
    };
    form['sign'] = BaiduLiveParse.feedSign(form);
    return _send(
      LiveRequest.form(
        site: _site,
        url: Uri.parse('https://tiebac.baidu.com/livefeed/feed'),
        headers: _headers,
        fields: form,
      ),
    );
  }

  @override
  Future<List<Category>> categories() async => BaiduLiveParse.categories(
    await _feed(BaiduLiveParse.recommendTab.tab, BaiduLiveParse.recommendTab.channel, null),
  );

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async {
    final key = BaiduLiveParse.areaKey(area.id);
    if (key == null) throw NotFound(_site, 'no area ${area.id}');
    return BaiduLiveParse.feed(await _feed(key.tab, key.channel, BaiduLiveParse.cursor(cursor)));
  }

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) async => BaiduLiveParse.feed(
    await _feed(BaiduLiveParse.recommendTab.tab, BaiduLiveParse.recommendTab.channel, BaiduLiveParse.cursor(cursor)),
  );

  Future<BaiduLiveRoom> _room(String roomId) async {
    if (!BaiduLiveParse.roomId.hasMatch(roomId)) throw NotFound(_site, 'not a room id: $roomId');
    final data = jsonEncode({
      'data': {'room_id': roomId, 'device_id': deviceId, 'source_type': 0},
      'replay_slice': 0,
      'nid': '',
      'schemeParams': {
        'src_pre': 'pc',
        'src_suf': 'other',
        'bd_vid': '',
        'share_uid': '',
        'share_cuk': '',
        'share_ecid': '',
        'zb_tag': '',
        'shareTaskInfo': jsonEncode({'room_id': roomId}),
        'share_from': '',
        'ext_params': '',
        'nid': '',
      },
    });
    final url = Uri.https('mbd.baidu.com', '/searchbox', {
      'cmd': '371',
      'action': 'star',
      'service': 'bdbox',
      'osname': 'pc',
      'data': data,
      'ua': '360_740_ANDROID_0',
      'bd_vid': '',
      'uid': deviceId,
      '_': '${_now().millisecondsSinceEpoch}',
    });
    return BaiduLiveParse.room(
      await _send(LiveRequest(site: _site, url: url, headers: _headers)),
      expectedId: roomId,
    );
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async => (await _room(ref.roomId)).detail;

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final fresh = await _room(room.ref.roomId);
    final qualities = BaiduLiveParse.qualities(fresh.video);
    if (qualities.isEmpty) {
      // Not live, paid or blocked rooms report why before "no quality".
      BaiduLiveParse.lines(fresh, BaiduLiveParse.origin, headers: const {});
      throw const StreamUnavailable(_site, 'no quality');
    }
    final requested = qualities.where((q) => q.id == quality?.id).firstOrNull ?? qualities.first;
    final lines = BaiduLiveParse.lines(
      fresh,
      requested,
      headers: const {
        'origin': 'https://live.baidu.com',
        'referer': 'https://live.baidu.com/',
        'user-agent': _userAgent,
      },
    );
    return StreamSet(qualities: qualities, selected: requested, lines: lines);
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (BaiduLiveParse.roomId.hasMatch(text)) return RoomRef(_site, text);
    final match = RegExp(r'https?://[^\s，。！？、“”"<>]+').firstMatch(text);
    final url = match == null ? null : Uri.tryParse(match.group(0)!);
    if (url == null || url.host.toLowerCase() != 'live.baidu.com') return null;
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments case ['m', 'room', final id] when BaiduLiveParse.roomId.hasMatch(id)) return RoomRef(_site, id);
    final query = url.queryParameters['room_id'];
    final path = '/${segments.join('/')}';
    final known =
        path == '/m/media/pclive/pchome/live.html' ||
        (segments.length == 6 && segments.take(5).join('/') == 'm/media/multipage/liveshow/index');
    if (known && query != null && BaiduLiveParse.roomId.hasMatch(query)) return RoomRef(_site, query);
    return null;
  }
}
