import 'dart:async';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/sixroom/sixroom_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'sixroom';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
const _mobileUserAgent = 'ios/7.830 (ios 17.0; ; iPhone 15 (A2846/A3089/A3090/A3092))';

/// The 6.cn (六间房) adapter (spec/sites/sixroom.md): the mobile live lists,
/// the search page, and room details and the FLV stream name from the room
/// page.
final class SixRoomSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter.
  new(this.http);

  /// Transport.
  final LiveHttp http;

  @override
  String get id => _site;

  @override
  String get name => '六间房';

  static const Map<String, String> _pageHeaders = {
    'accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
    'accept-language': 'zh-CN,zh;q=0.9',
    'referer': 'https://v.6.cn/',
    'user-agent': _userAgent,
  };

  Future<LiveResponse> _get(Uri url, Map<String, String> headers, {bool allowNotFound = false}) async {
    final LiveResponse response;
    try {
      response = await http.send(LiveRequest(site: _site, url: url, headers: headers));
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
    final status = response.status;
    if (allowNotFound && status == 404) return response;
    if (status == 401 || status == 403) throw RiskControl(_site, detail: 'HTTP $status ${url.path}');
    if (status == 429) throw RateLimited(_site, detail: 'HTTP 429 ${url.path}');
    if (status >= 500) throw NetworkFailure(_site, 'HTTP $status ${url.path}');
    if (status != 200) throw ApiChanged(_site, 'HTTP $status ${url.path}');
    return response;
  }

  Future<Page<RoomCard>> _list(String type, PageCursor? cursor) async {
    final page = int.tryParse(cursor?.value ?? '') ?? 1;
    final url = Uri.parse(
      'https://v.6.cn/coop/mobile/index.php?padapi=coop-mobile-getlivelistnew.php'
      '&av=3.1&encpass=&logiuid=&isnew=1&size=${SixRoomParse.pageSize}&p=$page&type=$type',
    );
    final response = await _get(url, const {
      'accept': 'application/json,text/plain,*/*',
      'accept-language': 'zh-CN,zh;q=0.9',
      'user-agent': _mobileUserAgent,
    });
    return SixRoomParse.list(response.text, type: type, page: page);
  }

  @override
  Future<List<Category>> categories() async => const [
    Category(id: SixRoomParse.categoryId, name: '分区', areas: SixRoomParse.areas),
  ];

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) {
    if (!SixRoomParse.areas.any((a) => a.id == area.id)) throw NotFound(_site, 'no area ${area.id}');
    return _list(area.id, cursor);
  }

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) => _list(SixRoomParse.recommendType, cursor);

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final query = keyword.trim();
    if (query.isEmpty || cursor != null) return const Page.empty();
    final url = Uri.https('v.6.cn', '/search.php', {'type': 'use', 'key': query});
    return SixRoomParse.search((await _get(url, _pageHeaders)).text);
  }

  Future<SixRoomPage> _page(String roomId) async {
    if (!SixRoomParse.roomId.hasMatch(roomId)) throw NotFound(_site, 'not a room number: $roomId');
    final response = await _get(SixRoomParse.link(roomId), _pageHeaders, allowNotFound: true);
    return SixRoomParse.page(response.text, expectedId: roomId, status: response.status);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async => (await _page(ref.roomId)).detail;

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final page = await _page(room.ref.roomId);
    final line = SixRoomParse.line(
      page,
      headers: {
        'origin': 'https://v.6.cn',
        'referer': SixRoomParse.link(room.ref.roomId).toString(),
        'user-agent': _userAgent,
      },
    );
    return StreamSet(qualities: const [SixRoomParse.source], selected: SixRoomParse.source, lines: [line]);
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (SixRoomParse.roomId.hasMatch(text)) return RoomRef(_site, text);
    final match = RegExp(r'https?://[^\s，。！？、“”"<>]+').firstMatch(text);
    final url = match == null ? null : Uri.tryParse(match.group(0)!);
    if (url == null) return null;
    final host = url.host.toLowerCase();
    if (host != 'v.6.cn' && host != 'm.6.cn') return null;
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    final id = switch (segments) {
      [final id] => id,
      ['profile', final id] => id,
      _ => null,
    };
    return id != null && SixRoomParse.roomId.hasMatch(id) ? RoomRef(_site, id) : null;
  }
}
