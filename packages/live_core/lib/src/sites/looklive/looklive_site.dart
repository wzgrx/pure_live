import 'dart:async';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/looklive/looklive_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'looklive';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// The LOOK Live (NetEase) adapter (spec/sites/looklive.md): the video and
/// voice recommendation lists and room details over the `weapi` envelope.
final class LookLiveSite implements LiveSite, CatalogSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter.
  new(this.http);

  /// Transport.
  final LiveHttp http;

  @override
  String get id => _site;

  @override
  String get name => 'LOOK 直播';

  static const Map<String, String> _headers = {
    'accept': 'application/json, text/plain, */*',
    'origin': 'https://look.163.com',
    'referer': 'https://look.163.com/',
    'user-agent': _userAgent,
  };

  Future<String> _post(String path, Map<String, Object?> payload) async {
    final LiveResponse response;
    try {
      response = await http.send(
        LiveRequest.form(
          site: _site,
          url: Uri.parse('https://api.look.163.com$path'),
          headers: _headers,
          fields: LookLiveParse.envelope(payload),
        ),
      );
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
    final status = response.status;
    if (status == 401 || status == 403) throw RiskControl(_site, detail: 'HTTP $status $path');
    if (status == 429) throw RateLimited(_site, detail: 'HTTP 429 $path');
    if (status >= 500) throw NetworkFailure(_site, 'HTTP $status $path');
    if (status != 200) throw ApiChanged(_site, 'HTTP $status $path');
    return response.text;
  }

  @override
  Future<List<Category>> categories() async => const [
    Category(id: LookLiveParse.categoryId, name: '分类', areas: LookLiveParse.areas),
  ];

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async {
    final page = int.tryParse(cursor?.value ?? '') ?? 1;
    final path = switch (area.id) {
      'video' => '/weapi/livestream/homepage/recommend',
      'audio' => '/weapi/livestream/listen/homepage/recommend/list',
      _ => throw NotFound(_site, 'no area ${area.id}'),
    };
    final body = await _post(path, {'offset': (page - 1) * LookLiveParse.pageSize, 'limit': LookLiveParse.pageSize});
    return LookLiveParse.list(body, area: area.id, page: page);
  }

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) => areaRooms(LookLiveParse.areas.first, cursor: cursor);

  Future<LookLiveRoom> _room(String no) async {
    if (!LookLiveParse.roomNo.hasMatch(no)) throw NotFound(_site, 'not a room number: $no');
    return LookLiveParse.room(await _post('/weapi/livestream/room/get/v3', {'liveRoomNo': no}), expectedNo: no);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async => (await _room(ref.roomId)).detail;

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final fresh = await _room(room.ref.roomId);
    final lines = LookLiveParse.lines(
      fresh,
      headers: const {'origin': 'https://look.163.com', 'referer': 'https://look.163.com/', 'user-agent': _userAgent},
    );
    return StreamSet(qualities: const [LookLiveParse.source], selected: LookLiveParse.source, lines: lines);
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (LookLiveParse.roomNo.hasMatch(text)) return RoomRef(_site, text);
    final match = RegExp(r'https?://[^\s，。！？、“”"<>]+').firstMatch(text);
    final url = match == null ? null : Uri.tryParse(match.group(0)!);
    if (url == null || url.host.toLowerCase() != 'look.163.com') return null;
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    final id = url.queryParameters['id'];
    if (segments.length == 1 && segments.single == 'live' && id != null && LookLiveParse.roomNo.hasMatch(id)) {
      return RoomRef(_site, id);
    }
    return null;
  }
}
