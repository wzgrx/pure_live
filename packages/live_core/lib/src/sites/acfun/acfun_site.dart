import 'dart:async';
import 'dart:math';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/acfun/acfun_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'acfun';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
const _origin = 'https://live.acfun.cn';

/// §6.1 how long one visitor session is used before a new login.
const _visitorLifetime = Duration(minutes: 5);

/// The AcFun adapter (spec/sites/acfun.md): parsing from [AcfunParse],
/// requests over [LiveHttp]. Everything is anonymous; streams need a short
/// visitor session the adapter keeps in memory.
final class AcfunSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter; [now] and [random] (the visitor device id) are
  /// injectable for tests.
  new(this.http, {DateTime Function()? now, Random? random})
    : _now = now ?? DateTime.now,
      _random = random ?? Random.secure();

  /// Transport.
  final LiveHttp http;
  final DateTime Function() _now;
  final Random _random;

  ({String did, AcfunVisitor visitor, DateTime since})? _session;
  Future<({String did, AcfunVisitor visitor, DateTime since})>? _login;

  @override
  String get id => _site;

  @override
  String get name => 'AcFun';

  Future<LiveResponse> _send(LiveRequest request) async {
    try {
      final response = await http.send(request);
      if (response.status >= 500) throw NetworkFailure(_site, '${request.url.path} HTTP ${response.status}');
      return response;
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  Future<LiveResponse> _get(Uri url, {String referer = '$_origin/'}) =>
      _send(LiveRequest(site: _site, url: url, headers: {'user-agent': _userAgent, 'referer': referer}));

  static Uri _list({String cursor = '', int count = acfunPageSize, String? filters}) =>
      Uri.https('live.acfun.cn', '/api/channel/list', {'count': '$count', 'pcursor': cursor, 'filters': ?filters});

  @override
  Future<List<Category>> categories() async {
    // One room is enough: the filters come with every list answer.
    final response = await _get(_list(count: 1));
    final areas = AcfunParse.areas(response.text);
    return [
      for (final type in {for (final area in areas) area.categoryId})
        Category(
          id: type,
          name: '直播分类',
          areas: [
            for (final area in areas)
              if (area.categoryId == type) area,
          ],
        ),
    ];
  }

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async {
    final response = await _get(_list(cursor: cursor?.value ?? '', filters: AcfunParse.filterQuery(area)));
    return AcfunParse.listPage(response.text);
  }

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) async {
    final response = await _get(_list(cursor: cursor?.value ?? ''));
    return AcfunParse.listPage(response.text);
  }

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const Page.empty();
    final page = int.tryParse(cursor?.value ?? '') ?? 1;
    final response = await _get(
      Uri.https('www.acfun.cn', '/search', {
        'keyword': text,
        'type': 'user',
        'pCursor': '$page',
        'quickViewId': 'up-list',
        'reqID': '1',
        'ajaxpipe': '1',
      }),
      referer: 'https://www.acfun.cn/search',
    );
    return AcfunParse.searchPage(response.text, page: page);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    final author = ref.roomId;
    if (!AcfunParse.isAuthor(author)) throw NotFound(_site, 'not an author id: $author');
    final response = await _get(Uri.https('live.acfun.cn', '/api/live/info', {'authorId': author}));
    return AcfunParse.detail(response.text, author: author);
  }

  /// §6.1 the visitor session, reused for five minutes; concurrent callers
  /// share one login.
  Future<({String did, AcfunVisitor visitor, DateTime since})> _visitor({bool fresh = false}) {
    final current = _session;
    if (!fresh && current != null && _now().difference(current.since) < _visitorLifetime) {
      return Future.value(current);
    }
    return _login ??= () async {
      try {
        const letters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
        final did = 'web_${List.generate(16, (_) => letters[_random.nextInt(letters.length)]).join()}';
        final response = await _send(
          LiveRequest.form(
            site: _site,
            url: Uri.https('id.app.acfun.cn', '/rest/app/visitor/login'),
            headers: {'user-agent': _userAgent, 'referer': '$_origin/', 'cookie': '_did=$did;'},
            fields: const {'sid': 'acfun.api.visitor'},
          ),
        );
        final session = (did: did, visitor: AcfunParse.visitor(response.text), since: _now());
        _session = session;
        return session;
      } finally {
        _login = null;
      }
    }();
  }

  /// §6.2 `startPlay` for [author]; a refused session is replaced once.
  Future<({AcfunPlay play, DateTime issuedAt})> play(String author) async {
    for (var attempt = 0; ; attempt++) {
      final session = await _visitor(fresh: attempt > 0);
      final issuedAt = _now();
      final response = await _send(
        LiveRequest.form(
          site: _site,
          url: Uri.https('api.kuaishouzt.com', '/rest/zt/live/web/startPlay', {
            'subBiz': 'mainApp',
            'kpn': 'ACFUN_APP',
            'kpf': 'PC_WEB',
            'userId': session.visitor.userId,
            'did': session.did,
            'acfun.api.visitor_st': session.visitor.token,
          }),
          headers: const {'user-agent': _userAgent, 'referer': '$_origin/'},
          fields: {'authorId': author, 'pullStreamType': 'FLV'},
        ),
      );
      try {
        return (play: AcfunParse.play(response.text, status: response.status), issuedAt: issuedAt);
      } on RiskControl {
        _session = null;
        if (attempt > 0) rethrow;
      }
    }
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final answer = await play(room.ref.roomId);
    final qualities = answer.play.qualities;
    final requested = qualities.where((q) => q.id == quality?.id).firstOrNull ?? quality ?? qualities.first;
    final urls = answer.play.urls[requested.id];
    if (urls == null || urls.isEmpty) throw StreamUnavailable(_site, 'no representation ${requested.id}');
    final seen = <String>{};
    return StreamSet(
      qualities: qualities,
      selected: requested,
      lines: [
        for (final url in urls)
          if (seen.add(url.host))
            StreamLine(
              url: url,
              format: AcfunParse.format(url),
              lineId: url.host,
              requested: requested,
              headers: const {'user-agent': _userAgent, 'referer': '$_origin/'},
              lease: AcfunParse.lease(url, answer.issuedAt),
            ),
      ],
    );
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (AcfunParse.isAuthor(text)) return RoomRef(_site, text);
    final match = RegExp(r'https?://[^\s，。！？、]+').firstMatch(text);
    final url = Uri.tryParse(match?.group(0) ?? text);
    if (url == null) return null;
    final host = url.host.toLowerCase();
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    String? author;
    if ((host == 'live.acfun.cn' || host == 'm.acfun.cn') && segments.firstOrNull == 'live') {
      author = segments.elementAtOrNull(1) == 'detail' ? segments.elementAtOrNull(2) : segments.elementAtOrNull(1);
    } else if ((host == 'www.acfun.cn' || host == 'acfun.cn') && segments.firstOrNull == 'u') {
      author = segments.elementAtOrNull(1);
    }
    return author != null && AcfunParse.isAuthor(author) ? RoomRef(_site, author) : null;
  }
}
