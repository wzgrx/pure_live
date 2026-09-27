import 'dart:async';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/cc/cc_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'cc';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// §1 path segments on cc.163.com that are pages, not rooms.
const _reserved = {'n', 'category', 'search', 'live', 'user', 'api', 'act', 'static', 'zt', 'dz'};

/// The NetEase CC adapter (spec/sites/cc.md): parsing from [CcParse],
/// requests over [LiveHttp]. Every endpoint is anonymous; CC has no account
/// cookie in v4 (spec §8).
final class CcSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter; [now] is injectable for tests.
  new(this.http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;
  final DateTime Function() _now;

  @override
  String get id => _site;

  @override
  String get name => '网易CC';

  Future<LiveResponse> _get(Uri url, {Map<String, String>? headers}) async {
    try {
      return await http.send(
        LiveRequest(
          site: _site,
          url: url,
          headers: headers ?? const {'user-agent': _userAgent, 'referer': 'https://cc.163.com/'},
        ),
      );
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  static void _requireSuccess(LiveResponse response, String what) {
    if (response.status >= 500) throw NetworkFailure(_site, '$what HTTP ${response.status}');
    if (response.status == 429) throw RateLimited(_site, detail: '$what HTTP 429');
  }

  static int _page(PageCursor? cursor) => int.tryParse(cursor?.value ?? '') ?? 1;

  @override
  Future<List<Category>> categories() async {
    Future<String> fetch(String type) async {
      final response = await _get(Uri.https('api.cc.163.com', '/v1/wapcc/gamecategory', {'catetype': type}));
      _requireSuccess(response, 'gamecategory');
      return response.text;
    }

    final names = CcParse.categoryNames(await fetch('0'));
    final areas = await Future.wait([for (final category in names) fetch(category.id)]);
    return [
      for (final (index, category) in names.indexed)
        if (CcParse.areas(areas[index], categoryId: category.id) case final list when list.isNotEmpty)
          Category(id: category.id, name: category.name, areas: list),
    ];
  }

  Future<Page<RoomCard>> _list(String path, int page, {String? gametype}) async {
    final response = await _get(
      Uri.https('cc.163.com', path, {
        'format': 'json',
        if (gametype != null) 'tag_id': '0',
        'start': '${(page - 1) * ccPageSize}',
        'size': '$ccPageSize',
      }),
    );
    _requireSuccess(response, path);
    return CcParse.roomListPage(response.text, page: page, gametype: gametype);
  }

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) =>
      _list('/api/category/${Uri.encodeComponent(area.id)}/', _page(cursor), gametype: area.id);

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) => _list('/api/category/live/', _page(cursor));

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const Page.empty();
    final page = _page(cursor);
    final response = await _get(
      Uri.https('cc.163.com', '/search/anchor/', {'query': text, 'size': '$ccSearchPageSize', 'page': '$page'}),
    );
    _requireSuccess(response, 'search/anchor');
    return CcParse.searchPage(response.text, page: page);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    final ccid = ref.roomId;
    if (!CcParse.isCcid(ccid)) throw NotFound(_site, 'not a ccid: $ccid');
    final lives = await _get(
      Uri.https('api.cc.163.com', '/v1/activitylives/anchor/lives', {'anchor_ccid': ccid}),
      headers: const {'user-agent': _userAgent},
    );
    _requireSuccess(lives, 'activitylives');
    final channel = CcParse.liveChannel(lives.text, ccid: ccid, status: lives.status);
    if (channel != null) {
      final response = await _get(Uri.https('cc.163.com', '/live/channel/', {'channelids': channel}));
      _requireSuccess(response, 'live/channel');
      final detail = CcParse.channelDetail(response.text, ccid: ccid);
      if (detail != null) return detail;
    }
    // Not broadcasting, or unknown: the room page tells them apart.
    final page = await _get(
      Uri.https('cc.163.com', '/$ccid/', {'open': 'blizzardtv', 'from': '8382', 'platform': 'ds'}),
      headers: const {'user-agent': _userAgent},
    );
    _requireSuccess(page, 'room page');
    return CcParse.pageDetail(page.text, ccid: ccid);
  }

  Future<({Map<String, dynamic> data, DateTime issuedAt})> _play(String ccid, {String? quality, String? cdn}) async {
    final issuedAt = _now();
    final response = await _get(
      Uri.https('vapi.cc.163.com', '/video_play_url/$ccid', {
        'src': 'webcc_h5',
        'vbrmode': '1',
        'use_new_vbrmap': '1',
        'secure': '1',
        'vbrname': ?quality,
        'cdn': ?cdn,
      }),
    );
    return (data: CcParse.playData(response.text, status: response.status), issuedAt: issuedAt);
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final ccid = room.ref.roomId;
    var answer = await _play(ccid, quality: quality?.id);
    final qualities = CcParse.qualities(answer.data);
    final requested = quality ?? qualities.first;
    if (quality == null && CcParse.confirmedQuality(answer.data) != requested.id) {
      answer = await _play(ccid, quality: requested.id);
    }
    final answers = [answer];
    final covered = {for (final line in CcParse.lines(answer.data)) line.cdn};
    // §5.2 the other CDNs of `cdn_list`, one request each.
    for (final cdn in CcParse.cdns(answer.data)) {
      if (covered.contains(cdn)) continue;
      try {
        final extra = await _play(ccid, quality: requested.id, cdn: cdn);
        answers.add(extra);
        covered.addAll([for (final line in CcParse.lines(extra.data)) line.cdn]);
      } on SiteError {
        // One CDN failing leaves the others (spec §9).
      }
    }
    Quality? confirmedOf(Map<String, dynamic> data) {
      final id = CcParse.confirmedQuality(data);
      if (id == null) return null;
      return qualities.where((q) => q.id == id).firstOrNull ?? Quality(id: id, label: id, rank: 0);
    }

    final seen = <String>{};
    final lines = <StreamLine>[
      for (final answer in answers)
        for (final line in CcParse.lines(answer.data))
          if (seen.add(line.cdn))
            StreamLine(
              url: line.url,
              format: CcParse.format(line.url),
              lineId: line.cdn,
              requested: requested,
              confirmed: confirmedOf(answer.data),
              headers: const {'user-agent': _userAgent, 'referer': 'https://cc.163.com/'},
              lease: CcParse.lease(line.url, answer.issuedAt),
            ),
    ];
    if (lines.isEmpty) throw const ApiChanged(_site, 'video_play_url: no playable URL');
    return StreamSet(qualities: qualities, selected: requested, lines: lines);
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (CcParse.isCcid(text)) return RoomRef(_site, text);
    final match = RegExp(r'https?://[^\s，。！？、]+').firstMatch(text);
    final url = Uri.tryParse(match?.group(0) ?? text);
    if (url == null) return null;
    final host = url.host.toLowerCase();
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    String? ccid;
    if (host == 'cc.163.com' && segments.isNotEmpty && !_reserved.contains(segments.first)) {
      ccid = segments.first;
    } else if (host == 'h5.cc.163.com' && segments.length >= 2 && segments.first == 'cc') {
      ccid = segments[1];
    } else if (host == 'ds.163.com' && segments.firstOrNull == 'glive') {
      ccid = url.queryParameters['ccid'];
    }
    return ccid != null && CcParse.isCcid(ccid) ? RoomRef(_site, ccid) : null;
  }
}
