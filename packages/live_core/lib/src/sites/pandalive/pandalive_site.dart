import 'dart:async';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/pandalive/pandalive_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'pandalive';
const _api = 'api.pandalive.co.kr';
const _origin = 'https://www.pandalive.co.kr';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// The PandaTV adapter (spec/sites/pandalive.md).
final class PandaliveSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter; [now] stamps stream leases.
  new(this.http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  final DateTime Function() _now;

  /// Directory and search page size.
  static const pageSize = 30;

  /// Search page size per source (§3).
  static const searchSize = 20;

  /// §6.3 media headers: IVS enforces the origin on every playlist and
  /// segment.
  static const Map<String, String> mediaHeaders = {'user-agent': _userAgent, 'origin': _origin, 'referer': '$_origin/'};

  @override
  String get id => _site;

  @override
  String get name => 'PandaTV';

  Future<LiveResponse> _send(LiveRequest request) async {
    try {
      return await http.send(request);
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  /// §6.3 every API call is a form POST from the site's origin.
  Future<LiveResponse> _post(String path, Map<String, String> form, {required String referer}) => _send(
    LiveRequest.form(
      site: _site,
      url: Uri.https(_api, path),
      fields: form,
      headers: {
        'user-agent': _userAgent,
        'accept': 'application/json, text/plain, */*',
        'origin': _origin,
        'referer': '$_origin$referer',
      },
    ),
  );

  static int _offset(PageCursor? cursor) {
    final offset = int.tryParse(cursor?.value ?? '') ?? 0;
    return offset < 0 ? 0 : offset;
  }

  Future<Page<RoomCard>> _index({required int offset, bool newOnly = false}) async {
    final response = await _post('/v1/live/index', {
      'offset': '$offset',
      'limit': '$pageSize',
      'orderBy': 'hot',
      if (newOnly) 'onlyNewBj': 'Y',
    }, referer: '/live');
    return PandaliveParse.indexPage(response.text, offset: offset, status: response.status);
  }

  @override
  Future<List<Category>> categories() async => const [PandaliveParse.category];

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) => switch (area.id) {
    'hot' => _index(offset: _offset(cursor)),
    'newbj' => _index(offset: _offset(cursor), newOnly: true),
    _ => throw NotFound(_site, 'area ${area.id}'),
  };

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) => _index(offset: _offset(cursor));

  Future<Page<RoomCard>> _broadcasters(String keyword, int offset) async {
    final response = await _post('/v1/live/bj_list', {
      'offset': '$offset',
      'limit': '$searchSize',
      'searchVal': keyword,
    }, referer: '/search/bj');
    return PandaliveParse.broadcasterPage(response.text, offset: offset, status: response.status);
  }

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    var text = keyword.trim();
    if (text.isEmpty) return const Page.empty();
    // §3 a room link finds that room, live or not.
    if (RegExp('^https?://').hasMatch(text)) {
      if (cursor != null) return const Page.empty();
      final ref = await resolve(text);
      if (ref == null) return const Page.empty();
      try {
        return Page([(await detail(ref)).card]);
      } on NotFound {
        return const Page.empty();
      }
    }
    if (text.length > 100) text = text.substring(0, 100);
    if (cursor != null) return await _broadcasters(text, _offset(cursor));
    // §3 the first page: live broadcasts matching title or name, then
    // broadcasters; later pages continue the broadcaster search only.
    Page<RoomCard>? live;
    try {
      final response = await _post('/v1/live/index', {
        'offset': '0',
        'limit': '$searchSize',
        'orderBy': 'user',
        'searchVal': text,
      }, referer: '/search/live');
      live = PandaliveParse.indexPage(response.text, offset: 0, status: response.status);
    } on SiteError {
      // The broadcaster search below still answers.
    }
    final broadcasters = await _broadcasters(text, 0);
    final seen = <String>{};
    return Page([
      for (final card in [...?live?.items, ...broadcasters.items])
        if (seen.add(card.ref.roomId.toLowerCase())) card,
    ], next: broadcasters.next);
  }

  String _checkedId(RoomRef ref) {
    final id = ref.roomId;
    if (!PandaliveParse.userIdPattern.hasMatch(id)) throw NotFound(_site, 'not a broadcaster id: $id');
    return id;
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    final id = _checkedId(ref);
    final response = await _post('/v1/member/bj', {'userId': id, 'info': 'media'}, referer: '/play/$id');
    return PandaliveParse.detail(response.text, userId: id, status: response.status);
  }

  /// §6.1 `live/play` for broadcaster [userId]: a fresh chat token and a
  /// fresh single-use IVS master.
  Future<PandalivePlay> play(String userId) async {
    final response = await _post('/v1/live/play', {
      'action': 'watch',
      'userId': userId,
      'password': '',
      'shareLinkType': '',
    }, referer: '/play/$userId');
    return PandaliveParse.play(response.text, userId: userId, status: response.status);
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final id = _checkedId(room.ref);
    final session = await play(id);
    final issuedAt = _now();
    // §6.2 the master's token is single use: read it once, hand out variants.
    final response = await _send(LiveRequest(site: _site, url: session.master, headers: mediaHeaders));
    if (response.status == 403) throw const RiskControl(_site, detail: 'IVS master HTTP 403');
    if (response.status == 404) throw const StreamUnavailable(_site, 'IVS master HTTP 404');
    if (!response.isSuccess) throw NetworkFailure(_site, 'IVS master HTTP ${response.status}');
    return PandaliveParse.streams(
      response.text,
      master: session.master,
      headers: mediaHeaders,
      issuedAt: issuedAt,
      wanted: quality?.id,
    );
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final id = PandaliveParse.userIdOf(input);
    return id == null ? null : RoomRef(_site, id);
  }
}
