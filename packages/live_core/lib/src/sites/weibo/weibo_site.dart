import 'dart:async';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/weibo/weibo_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'weibo';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// The Weibo Live adapter (spec/sites/weibo.md): a recommendation snapshot,
/// broadcast details and one FLV line; no categories, search or chat.
final class WeiboSite implements LiveSite, CatalogSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter.
  new(this.http);

  /// Transport.
  final LiveHttp http;

  @override
  String get id => _site;

  @override
  String get name => '微博直播';

  static const Map<String, String> _headers = {
    'accept': 'application/json, text/plain, */*',
    'referer': 'https://weibo.com/l/wblive/',
    'user-agent': _userAgent,
  };

  Future<LiveResponse> _get(Uri url) async {
    final LiveResponse response;
    try {
      response = await http.send(LiveRequest(site: _site, url: url, headers: _headers));
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
    final status = response.status;
    if (status == 403) throw const RiskControl(_site, detail: 'HTTP 403');
    if (status == 429) throw const RateLimited(_site, detail: 'HTTP 429');
    if (status >= 500) throw NetworkFailure(_site, 'HTTP $status');
    if (status != 200) throw ApiChanged(_site, 'HTTP $status');
    return response;
  }

  @override
  Future<List<Category>> categories() async => const [];

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async =>
      throw NotFound(_site, 'no area ${area.id}: weibo has no categories');

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) async {
    if (cursor != null) return const Page.empty();
    final response = await _get(Uri.parse('https://weibo.com/l/!/2/wblive/pc_recommend/list.json?count=100&uid='));
    return WeiboParse.recommended(response.text);
  }

  Future<WeiboRoom> _room(String liveId) async {
    final url = Uri.parse(
      'https://weibo.com/l/!/2/wblive/room/show_pc_live.json?live_id=${Uri.encodeQueryComponent(liveId)}',
    );
    final response = await _get(url);
    return WeiboParse.room(response.text, expectedId: liveId);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async => (await _room(ref.roomId)).detail;

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final fresh = await _room(room.ref.roomId);
    final lines = WeiboParse.lines(fresh, headers: const {'user-agent': _userAgent});
    return StreamSet(qualities: const [WeiboParse.origin], selected: WeiboParse.origin, lines: lines);
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (WeiboParse.liveId.hasMatch(text)) return RoomRef(_site, text);
    final match = RegExp(r'https?://[^\s，。！？、“”"<>]+').firstMatch(text);
    if (match == null) return null;
    final url = Uri.tryParse(match.group(0)!);
    if (url == null) return null;
    final host = url.host.toLowerCase();
    String? candidate;
    if (host == 'weibo.com' || host == 'www.weibo.com') {
      final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.length == 5 &&
          segments[0] == 'l' &&
          segments[1] == 'wblive' &&
          (segments[2] == 'p' || segments[2] == 'm') &&
          segments[3] == 'show') {
        candidate = segments[4];
      }
    } else if (host == 'live.media.weibo.com' && url.path == '/live/show') {
      candidate = url.queryParameters['id'];
    }
    if (candidate == null) return null;
    final String id;
    try {
      id = Uri.decodeComponent(candidate).trim();
    } on Object {
      return null;
    }
    return WeiboParse.liveId.hasMatch(id) ? RoomRef(_site, id) : null;
  }
}
