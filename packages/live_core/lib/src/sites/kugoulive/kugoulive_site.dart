import 'dart:async';

import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/kugoulive/kugoulive_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'kugoulive';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// The Kugou Live (Fanxing) adapter (spec/sites/kugoulive.md): home-page
/// areas, recommended and area lists, anchor search, room info and the
/// multi-line FLV addresses.
final class KugouLiveSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter; [now] is injectable for tests.
  new(this.http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;
  final DateTime Function() _now;

  @override
  String get id => _site;

  @override
  String get name => '酷狗直播';

  static Map<String, String> _headers({String? roomId}) => {
    'accept': 'application/json, text/plain, */*',
    'origin': 'https://fanxing.kugou.com',
    'referer': roomId == null ? 'https://fanxing.kugou.com/' : KugouLiveParse.link(roomId).toString(),
    'user-agent': _userAgent,
  };

  Future<String> _get(Uri url, {String? roomId, Map<String, String>? headers}) async {
    final LiveResponse response;
    try {
      response = await http.send(
        LiveRequest(
          site: _site,
          url: url,
          headers: headers ?? _headers(roomId: roomId),
        ),
      );
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
    final status = response.status;
    if (status == 401 || status == 403) throw RiskControl(_site, detail: 'HTTP $status ${url.path}');
    if (status == 429) throw RateLimited(_site, detail: 'HTTP 429 ${url.path}');
    if (status >= 500) throw NetworkFailure(_site, 'HTTP $status ${url.path}');
    if (status != 200) throw ApiChanged(_site, 'HTTP $status ${url.path}');
    return response.text;
  }

  /// §2.2 list parameters shared by the recommended and area lists.
  static Map<String, String> _listQuery(int page) => {
    'pid': '0',
    'kugouId': '0',
    'doubleLiveFirst': '1',
    'sysVersion': '0',
    'platform': '7',
    'device': 'PureLive-Web',
    'channel': '0',
    'version': '99999',
    'longitude': '0',
    'latitude': '0',
    'appid': '1010',
    'liveTypeFilter': '0',
    'isNew': '0',
    'entranceType': '0',
    'uiMode': '0',
    'page': '$page',
  };

  @override
  Future<List<Category>> categories() async {
    final html = await _get(
      Uri.parse('https://fanxing.kugou.com/'),
      headers: const {'accept': 'text/html,application/xhtml+xml,*/*;q=0.8', 'user-agent': _userAgent},
    );
    return KugouLiveParse.categories(html);
  }

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async {
    final page = int.tryParse(cursor?.value ?? '') ?? 1;
    final url = Uri.https('fx1.service.kugou.com', '/mfanxing-home/h5/cdn/room/index/list_v4', {
      ..._listQuery(page),
      'cid': area.id,
    });
    return KugouLiveParse.roomList(await _get(url), page: page);
  }

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) async {
    final page = int.tryParse(cursor?.value ?? '') ?? 1;
    final url = Uri.https('fx1.service.kugou.com', '/mfanxing-home/h5/cdn/room/index/list', _listQuery(page));
    return KugouLiveParse.roomList(await _get(url), page: page);
  }

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final query = keyword.trim();
    if (query.isEmpty || cursor != null) return const Page.empty();
    final url = Uri.https('fx1.service.kugou.com', '/pt_search/pcsearch/v1/type_all.jsonp', {
      'keywords': query,
      'nums': '200,0,0,0',
      'callback': 'pureLive${_now().millisecondsSinceEpoch}',
    });
    return KugouLiveParse.search(await _get(url));
  }

  Future<({RoomDetail detail, bool restricted})> _room(String roomId) async {
    if (!KugouLiveParse.roomId.hasMatch(roomId)) throw NotFound(_site, 'not a room id: $roomId');
    final url = Uri.https('service2.fanxing.kugou.com', '/roomcen/room/web/cdn/getEnterRoomInfo', {'roomId': roomId});
    return KugouLiveParse.detail(await _get(url), expectedId: roomId);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async => (await _room(ref.roomId)).detail;

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final roomId = room.ref.roomId;
    final fresh = await _room(roomId);
    if (fresh.detail.state != LiveState.live) throw const StreamUnavailable(_site, 'not live');
    if (fresh.restricted) throw const NeedsLogin(_site, 'limited room');
    final url = Uri.https('fx1.service.kugou.com', '/video/pc/live/pull/mutiline/streamaddr', {
      'std_rid': roomId,
      'std_plat': '7',
      'std_kid': '0',
      'streamType': '1-2-4-5-8',
      'ua': 'fx-flash',
      'targetLiveTypes': '1-5-6',
      'version': '1000',
      'supportEncryptMode': '1',
      'appid': '1010',
      '_': '${_now().millisecondsSinceEpoch}',
    });
    return KugouLiveParse.streams(
      await _get(url, roomId: roomId),
      expectedId: roomId,
      headers: {
        'origin': 'https://fanxing.kugou.com',
        'referer': KugouLiveParse.link(roomId).toString(),
        'user-agent': _userAgent,
      },
    );
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (KugouLiveParse.roomId.hasMatch(text)) return RoomRef(_site, text);
    final match = RegExp(r'https?://[^\s，。！？、“”"<>]+').firstMatch(text);
    final url = match == null ? null : Uri.tryParse(match.group(0)!);
    if (url == null) return null;
    final host = url.host.toLowerCase();
    if (host != 'fanxing.kugou.com' && host != 'mfanxing.kugou.com' && host != 'fanxing2.kugou.com') return null;
    final query = url.queryParameters['roomId'];
    if (query != null && KugouLiveParse.roomId.hasMatch(query)) return RoomRef(_site, query);
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length == 1 && KugouLiveParse.roomId.hasMatch(segments.single)) {
      return RoomRef(_site, segments.single);
    }
    return null;
  }
}
