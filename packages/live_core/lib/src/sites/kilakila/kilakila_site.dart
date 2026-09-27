import 'dart:async';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/kilakila/kilakila_link.dart';
import 'package:live_core/src/sites/kilakila/kilakila_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'kilakila';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// The KilaKila (克拉克拉) adapter (spec/sites/kilakila.md). Rooms are
/// anchors: the uid is the identity, the broadcast id changes every time.
final class KilakilaSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter; [now] is injectable for tests.
  new(this.http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;
  final DateTime Function() _now;

  /// §6.3 request headers for the API and the media.
  static const Map<String, String> headers = {'user-agent': _userAgent, 'referer': 'https://live.kilakila.cn/'};

  @override
  String get id => _site;

  @override
  String get name => '克拉克拉';

  Future<LiveResponse> _get(Uri url) async {
    try {
      return await http.send(LiveRequest(site: _site, url: url, headers: headers));
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  @override
  Future<List<Category>> categories() async => [
    Category(
      id: 'timeline',
      name: '直播',
      areas: [
        for (final entry in KilakilaParse.timelines.entries)
          Area(id: entry.key, name: entry.value, categoryId: 'timeline'),
      ],
    ),
  ];

  Future<Page<RoomCard>> _timeline(String type, PageCursor? cursor) async {
    final page = int.tryParse(cursor?.value ?? '') ?? 1;
    final response = await _get(
      Uri.https('live.kilakila.cn', '/pcLive/timeline', {
        'tag': '0',
        'type': type,
        'genderType': '0',
        'pageNo': '$page',
        'pageSize': '10',
      }),
    );
    return KilakilaParse.timelinePage(response.text, page: page, type: type, status: response.status);
  }

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) {
    if (!KilakilaParse.timelines.containsKey(area.id)) {
      throw ArgumentError.value(area.id, 'area', 'not a KilaKila timeline');
    }
    return _timeline(area.id, cursor);
  }

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) => _timeline('0', cursor);

  Future<KilakilaAnchor> _anchor(String uid) async {
    final response = await _get(Uri.https('live.hongrenshuo.com.cn', '/Tg/personalH5', {'uid': uid}));
    return KilakilaParse.anchor(response.text, uid: uid, status: response.status);
  }

  Future<Map<String, dynamic>> _room(String roomId) async {
    final response = await _get(Uri.https('live.kilakila.cn', '/LiveRoom/getRoomInfo', {'roomId': roomId}));
    return KilakilaParse.roomInfo(response.text, status: response.status);
  }

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const Page.empty();
    // §3 a uid or a link finds that anchor exactly.
    final exact = KilakilaParse.idPattern.hasMatch(text) ? RoomRef(_site, text) : await resolve(text);
    if (exact != null) {
      if (cursor != null) return const Page.empty();
      try {
        return Page([(await detail(exact)).card]);
      } on NotFound {
        return const Page.empty();
      }
    }
    if (RegExp('^https?://').hasMatch(text)) return const Page.empty();
    final page = int.tryParse(cursor?.value ?? '') ?? 1;
    final keywordPath = text.length > 100 ? text.substring(0, 100) : text;
    final response = await _get(
      Uri(
        scheme: 'https',
        host: 'live.kilakila.cn',
        pathSegments: [
          'aboutus',
          'serach',
          'kw',
          keywordPath,
          if (page > 1) ...['p', '$page'],
        ],
      ),
    );
    if (response.status >= 500) throw NetworkFailure(_site, 'search HTTP ${response.status}');
    if (!response.isSuccess) throw ApiChanged(_site, 'search HTTP ${response.status}');
    final result = KilakilaParse.searchPage(response.text, page: page);
    // §3 the result page has no live state: each anchor's profile gives it.
    final cards = <RoomCard>[];
    for (final anchor in result.anchors) {
      try {
        cards.add((await detail(RoomRef(_site, anchor.uid))).card);
      } on NotFound {
        continue;
      }
    }
    return Page(cards, next: result.more ? PageCursor('${page + 1}') : null);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    if (!KilakilaParse.idPattern.hasMatch(ref.roomId)) throw NotFound(_site, 'not a uid: ${ref.roomId}');
    return KilakilaParse.detail(await _anchor(ref.roomId));
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    // §6.1 fresh: the anchor's current broadcast, then its signed URLs.
    final anchor = await _anchor(room.ref.roomId);
    final roomId = anchor.live?['roomIdStr'];
    if (roomId is! String) throw const StreamUnavailable(_site, 'no current broadcast');
    final info = await _room(roomId);
    if (KilakilaParse.anchorOf(info) != room.ref.roomId) throw const ApiChanged(_site, 'broadcast of another anchor');
    return KilakilaParse.streams(info, issuedAt: _now(), headers: headers);
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (KilakilaParse.idPattern.hasMatch(text)) return RoomRef(_site, text);
    final link = KilakilaLink.parse(text);
    if (link == null) return null;
    if (link.kind == KilakilaLinkKind.anchor) return RoomRef(_site, link.id);
    // A broadcast link names one broadcast; its anchor is the room.
    return RoomRef(_site, KilakilaParse.anchorOf(await _room(link.id)));
  }
}
