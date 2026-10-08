// MissevanSite over the recorded Missevan responses (ReplayHttp) and a few
// synthetic ones: the request headers, the catalog, native directory pages
// per namespace, keyword and exact search, room details for entry, refresh
// and recording, streams with their leases and recovery, cancellation,
// links and the error mapping; and the M4.U upgrades (13-1 to 13-4).
import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/missevan';
const _api = 'https://fm.missevan.com/api/v2';
const _live = '453091860';
const _offline = '507069668';

const _hls = 'http://d1-missevan104.bilivideo.com/live/sample.m3u8?expires=1900000000&sign=fixture%2Bonly';
const _flv = 'http://d1-missevan04.bilivideo.com/live/sample.flv?expires=1900000000&sign=fixture';

ReplaySample _synthetic(String url, Object body, {int status = 200}) => ReplaySample(
  method: 'GET',
  url: Uri.parse(url),
  status: status,
  bytes: utf8.encode(body is String ? body : jsonEncode(body)),
);

String _ok(Object? info) => jsonEncode({'code': 0, 'info': info});

/// 3.x's test detail of room 100.
Map<String, dynamic> _detail({int open = 1, String hls = _hls}) => {
  'room': {
    'room_id': 100,
    'creator_id': 200,
    'creator_username': 'Fixture',
    'name': '音频测试',
    'status': {'open': open},
    'statistics': {'score': 321, 'attention_count': 12},
    'channel': {'hls_pull_url': hls, 'flv_pull_url': _flv},
  },
  'creator': {'user_id': 200, 'iconurl': 'https://static.maoercdn.com/avatar.png', 'introduction': 'fixture'},
};

/// Answers every request with [answer].
final class _Scripted implements LiveHttp {
  new(this.answer);

  final LiveResponse Function(LiveRequest request) answer;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    return answer(request);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw UnsupportedError('open');

  @override
  void close() {}
}

final class _Failing implements LiveHttp {
  new(this.reason);

  final TransportReason reason;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    throw TransportFailure('missevan', reason, 'test');
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('missevan', reason, 'test');

  @override
  void close() {}
}

LiveResponse _response(LiveRequest request, String body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);

typedef _Setup = ({MissevanSite site, ReplayHttp http});

_Setup _setup(List<String> samples, {List<ReplaySample> extra = const []}) {
  final http = ReplayHttp([...extra, for (final name in samples) ReplaySample.load('$_root/$name')]);
  return (site: MissevanSite(http), http: http);
}

List<Map<String, String>> _queries(List<LiveRequest> requests) => [
  for (final request in requests) request.url.queryParameters,
];

List<String> _paths(List<LiveRequest> requests) => [for (final request in requests) request.url.path];

void main() {
  group('requests', () {
    test("3.x's headers on every API request, redirects not followed", () async {
      final setup = _setup(['S01-meta', 'S04-live']);
      await setup.site.getCategories(1, 30);
      await setup.site.getRoomDetail(roomId: _live);
      for (final request in setup.http.requests) {
        expect(request.url.host, 'fm.missevan.com');
        expect(request.url.path, startsWith('/api/v2/'));
        expect(request.headers, {
          'referer': 'https://fm.missevan.com/',
          'origin': 'https://fm.missevan.com',
          'user-agent': 'Mozilla/5.0',
        });
        expect(request.followRedirects, isFalse);
        expect(request.site, 'missevan');
      }
      expect(setup.site.id, 'missevan');
      expect(setup.site.name, '猫耳 FM');
      expect(setup.site.getDanmaku(), isA<EmptyDanmaku>(), reason: '3.x had no Missevan danmaku');
    });

    test('transport failures are NetworkFailure; a cancelled transport stays cancelled', () async {
      final failing = _Failing(TransportReason.connect);
      await expectLater(MissevanSite(failing).getRoomDetail(roomId: '100'), throwsA(isA<NetworkFailure>()));
      await expectLater(
        MissevanSite(_Failing(TransportReason.cancelled)).getRoomDetail(roomId: '100'),
        throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
      );
      final unavailable = _Scripted((request) => _response(request, '', status: 503));
      await expectLater(MissevanSite(unavailable).getCategories(1, 30), throwsA(isA<NetworkFailure>()));
      final denied = _Scripted((request) => _response(request, '', status: 403));
      await expectLater(MissevanSite(denied).getRoomDetail(roomId: '100'), throwsA(isA<RiskControl>()));
    });
  });

  group('catalog', () {
    test('the tabs grouped by namespace (13-3); one request, later pages ask nothing (3.x)', () async {
      final setup = _setup(['S01-meta']);
      final categories = await setup.site.getCategories(1, 30);
      expect(categories.map((category) => (category.id, category.name, category.children.length)), [
        ('catalog', '分区', 5),
        ('list', '团播', 1),
        ('tag', '标签', 1),
      ]);
      expect(await setup.site.getCategories(2, 30), isEmpty);
      expect(_paths(setup.http.requests), ['/api/v2/meta/data']);
    });

    test('an area 3.x stored (typeName 猫耳 FM) lists the same rooms (13-3)', () async {
      final setup = _setup(['S02-list-tag']);
      final stored = LiveArea.fromJson(const {
        'platform': 'missevan',
        'areaType': 'tag',
        'typeName': '猫耳 FM',
        'areaId': '1',
        'areaName': '新星',
      });
      expect(await setup.site.getCategoryRooms(stored), hasLength(20));
      expect(_queries(setup.http.requests), [
        {'p': '1', 'tag_id': '1'},
      ]);
    });
  });

  group('directory', () {
    test('recommendations: native pages by number, more until maxpage (REG-MISSEVAN-001)', () async {
      final setup = _setup(['S02-list-p1', 'S02-list-last', 'S02-list-beyond']);
      final first = await setup.site.getDirectoryPage();
      expect((first.page, first.rooms.length, first.hasMore), (1, 22, true));
      final last = await setup.site.getDirectoryPage(page: 29);
      expect((last.page, last.rooms.length, last.hasMore), (29, 5, false));
      final beyond = await setup.site.getDirectoryPage(page: 30);
      expect((beyond.rooms.length, beyond.hasMore), (0, false));
      expect(await setup.site.getRecommendRooms(pageSize: 20), hasLength(22), reason: "the page size is the site's");
      expect(_queries(setup.http.requests), [
        {'p': '1'},
        {'p': '29'},
        {'p': '30'},
        {'p': '1'},
      ]);
    });

    test('each namespace is asked with its own parameter (REG-MISSEVAN-003, -005)', () async {
      final setup = _setup(['S01-meta', 'S02-list-catalog', 'S02-list-tag', 'S02-list-team']);
      final areas = {
        for (final category in await setup.site.getCategories(1, 30))
          for (final area in category.children) '${area.areaType}:${area.areaId}': area,
      };
      final music = await setup.site.getDirectoryPage(category: areas['catalog:104']);
      final stars = await setup.site.getCategoryRooms(areas['tag:1']!);
      final team = await setup.site.getDirectoryPage(category: areas['list:4']);
      expect(music.rooms, hasLength(20));
      expect(stars, hasLength(20));
      expect(team.rooms, hasLength(20));
      expect(_queries(setup.http.requests).skip(1), [
        {'p': '1', 'catalog_id': '104'},
        {'p': '1', 'tag_id': '1'},
        {'p': '1', 'type': '4'},
      ]);
      expect(_paths(setup.http.requests).skip(1), everyElement('/api/v2/chatroom/open/list'));
      final stored = LiveArea.fromJson(areas['catalog:104']!.toJson());
      expect((await setup.site.getCategoryRooms(stored)).length, 20, reason: 'a followed area keeps working');
    });

    test('bad pages, page sizes and areas are caller errors, without a request (3.x)', () async {
      final setup = _setup([]);
      for (final page in [0, -1, 10001]) {
        await expectLater(setup.site.getDirectoryPage(page: page), throwsArgumentError, reason: '$page');
      }
      for (final size in [0, 101]) {
        await expectLater(setup.site.getRecommendRooms(pageSize: size), throwsArgumentError, reason: '$size');
      }
      for (final area in [
        const LiveArea(platform: 'other', areaType: 'catalog', areaId: '1'),
        const LiveArea(platform: 'missevan', areaType: 'tag', areaId: '../1'),
        const LiveArea(platform: 'missevan', areaType: 'unknown', areaId: '1'),
      ]) {
        await expectLater(setup.site.getCategoryRooms(area), throwsArgumentError, reason: area.areaType);
      }
      expect(setup.http.requests, isEmpty);
    });

    test('the cancellation goes with the request, and wins after the answer (3.x)', () async {
      final token = CancelToken();
      final setup = _setup(['S02-list-p1']);
      await setup.site.getDirectoryPage(cancel: token);
      expect(identical(setup.http.requests.single.cancel, token), isTrue);
      final cancelled = CancelToken()..cancel();
      await expectLater(
        setup.site.getDirectoryPage(cancel: cancelled),
        throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
      );
      expect(setup.http.requests, hasLength(1), reason: 'nothing sent once cancelled');
      final afterAnswer = CancelToken();
      final http = _Scripted((request) {
        afterAnswer.cancel();
        return _response(request, _ok({'pagination': <String, Object?>{}}));
      });
      await expectLater(
        MissevanSite(http).getDirectoryPage(cancel: afterAnswer),
        throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
      );
      final afterFailure = CancelToken();
      final broken = _Scripted((request) {
        afterFailure.cancel();
        throw const TransportFailure('missevan', TransportReason.connect);
      });
      await expectLater(
        MissevanSite(broken).getDirectoryPage(cancel: afterFailure),
        throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
      );
    });
  });

  group('search', () {
    test('keywords: native pages of chatroom/search, live and offline', () async {
      final setup = _setup(['S03-search', 'S03-search-p2', 'S03-search-empty']);
      final first = await setup.site.searchRooms('配音', pageSize: 20);
      final second = await setup.site.searchRooms(' 配音 ', page: 2, pageSize: 20);
      expect(first, hasLength(20));
      expect(first.where((room) => room.isLiveNow), hasLength(5));
      expect(second, hasLength(20));
      expect(await setup.site.searchRooms('zxqvnoresultfixture', pageSize: 20), isEmpty);
      expect(_paths(setup.http.requests), everyElement('/api/v2/chatroom/search'));
      expect(_queries(setup.http.requests), [
        {'s': '配音', 'p': '1', 'page_size': '20'},
        {'s': '配音', 'p': '2', 'page_size': '20'},
        {'s': 'zxqvnoresultfixture', 'p': '1', 'page_size': '20'},
      ]);
      expect(setup.site.supportsSearchPaginationFor('配音'), isTrue);
    });

    test('a room number or link finds that room, live or not, on page 1 only (3.x)', () async {
      final setup = _setup(['S04-live', 'S04-offline', 'S04-notfound']);
      final live = await setup.site.searchRooms(_live);
      expect(live.single.roomId, _live);
      expect(live.single.isLiveNow, isTrue);
      expect(live.single.data, isNull, reason: 'search never reads pull URLs');
      final offline = await setup.site.searchRooms('https://fm.missevan.com/live/$_offline/?share=1', pageSize: 1);
      expect(offline.single.isExplicitlyOfflineNow, isTrue);
      expect(await setup.site.searchRooms('1'), isEmpty, reason: 'an unknown room is no result');
      expect(await setup.site.searchRooms(_live, page: 2), isEmpty);
      expect(_paths(setup.http.requests), ['/api/v2/live/$_live', '/api/v2/live/$_offline', '/api/v2/live/1']);
      for (final input in [_live, 'https://fm.missevan.com/live/$_live']) {
        expect(setup.site.supportsSearchPaginationFor(input), isFalse, reason: input);
      }
    });

    test('other links find nothing without a request; blank input or no page size neither (3.x)', () async {
      final setup = _setup([]);
      for (final input in [
        'https://other.example/live/100',
        'https://fm.missevan.com/catalog/100',
        'https://fm.missevan.com.evil.test/live/100',
        '   ',
      ]) {
        expect(await setup.site.searchRooms(input), isEmpty, reason: input);
        expect(setup.site.supportsSearchPaginationFor(input), isFalse, reason: input);
      }
      expect(await setup.site.searchRooms('配音', pageSize: 0), isEmpty);
      expect(setup.http.requests, isEmpty);
    });

    test('a keyword with a colon is a keyword (3.x took `Re:Zero` for a link and found nothing)', () async {
      final setup = _setup(
        [],
        extra: [
          _synthetic(
            '$_api/chatroom/search?s=Re%3AZero&p=1&page_size=20',
            _ok({
              'data': [(_detail()['room'] as Map<String, dynamic>)],
              'pagination': {'p': 1, 'pagesize': 20, 'maxpage': 1, 'count': 1},
            }),
          ),
        ],
      );
      expect((await setup.site.searchRooms('Re:Zero', pageSize: 20)).single.roomId, '100');
      expect(setup.site.supportsSearchPaginationFor('Re:Zero'), isTrue);
    });

    test('a keyword over 100 characters is cut to its first 100 and searched (13-4; 3.x refused it)', () async {
      final keyword = '配音' * 60;
      final setup = _setup(
        [],
        extra: [
          _synthetic(
            Uri.https('fm.missevan.com', '/api/v2/chatroom/search', {
              's': '配音' * 50,
              'p': '2',
              'page_size': '20',
            }).toString(),
            _ok({
              'data': [(_detail()['room'] as Map<String, dynamic>)],
              'pagination': {'p': 2, 'pagesize': 20, 'maxpage': 2, 'count': 21},
            }),
          ),
        ],
      );
      expect((await setup.site.searchRooms(' $keyword ', page: 2, pageSize: 20)).single.roomId, '100');
      expect(setup.http.requests.single.url.queryParameters['s'], hasLength(100));
      expect(setup.site.supportsSearchPaginationFor(keyword), isTrue);
    });

    test('keywords, pages and sizes the site does not take are refused without a request (3.x)', () async {
      final setup = _setup([]);
      for (final keyword in ['a\nb', 'a\u0000b', '${'x' * 101}\u0007']) {
        await expectLater(setup.site.searchRooms(keyword), throwsArgumentError, reason: keyword);
      }
      await expectLater(setup.site.searchRooms('配音', page: 0), throwsArgumentError);
      await expectLater(setup.site.searchRooms('配音', page: 10001), throwsArgumentError);
      await expectLater(setup.site.searchRooms('配音', pageSize: 101), throwsArgumentError);
      expect(setup.http.requests, isEmpty);
    });

    test('only a confirmed absence is an empty result; the cancellation is forwarded (3.x)', () async {
      final token = CancelToken();
      final absent = _Scripted((request) => _response(request, '', status: 404));
      expect(await MissevanSite(absent).searchRoomsWithCancellation('100', cancel: token), isEmpty);
      expect(identical(absent.requests.single.cancel, token), isTrue);
      final denied = _Scripted((request) => _response(request, '', status: 403));
      await expectLater(MissevanSite(denied).searchRooms('100'), throwsA(isA<RiskControl>()));
      final keyword = _Scripted(
        (request) => _response(
          request,
          _ok({
            'data': const <Object?>[],
            'pagination': {'p': 1, 'pagesize': 20, 'maxpage': 0, 'count': 0},
          }),
        ),
      );
      await MissevanSite(keyword).searchRoomsCancellable('主播昵称', pageSize: 20, cancel: token);
      expect(identical(keyword.requests.single.cancel, token), isTrue);
    });
  });

  group('rooms', () {
    test('entry, refresh and recording: one request each, the room as asked for', () async {
      final setup = _setup(['S04-live']);
      final entered = await setup.site.getRoomDetail(roomId: _live);
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: ' $_live ');
      final recorded = await setup.site.getRoomDetailForRecording(roomId: _live);
      for (final room in [entered, refreshed, recorded]) {
        expect(room.roomId, _live);
        expect(room.isLiveNow, isTrue);
        expect(room.data, isA<MissevanRoomData>());
        expect(room.startedAt, DateTime.utc(2026, 9, 27, 3, 52, 30, 876), reason: 'unified principle');
        expect(room.restriction, LiveRestriction.none, reason: 'unified principle');
      }
      expect(await setup.site.getLiveStatus(roomId: _live), isTrue);
      expect(_paths(setup.http.requests), everyElement('/api/v2/live/$_live'));
      expect(setup.http.requests, hasLength(4));
    });

    test('room entry hands over the danmaku arguments, live or not, without a request (13-2)', () async {
      final setup = _setup(['S04-live', 'S04-offline']);
      final live = await setup.site.getRoomDetail(roomId: _live);
      final offline = await setup.site.getRoomDetail(roomId: _offline);
      for (final (room, id) in [(live, _live), (offline, _offline)]) {
        final args = room.danmakuData! as MissevanDanmakuArgs;
        expect(args.roomId, id);
        expect(args.url, Uri.parse('wss://im.missevan.com/ws?room_id=$id'));
      }
      expect(setup.http.requests, hasLength(2));
      expect((await setup.site.getRoomDetailForRefresh(roomId: _live)).danmakuData, isNull);
      // E05.4: the recording detail (multi-view) has them too.
      expect(
        (await setup.site.getRoomDetailForRecording(roomId: _live)).danmakuData.toString(),
        live.danmakuData.toString(),
      );
      expect(setup.site.getDanmaku(), isA<EmptyDanmaku>(), reason: 'the connection is M5');
    });

    test('an offline refresh keeps what the card knew (mergeFrom)', () async {
      final setup = _setup(['S04-offline']);
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: _offline);
      expect(refreshed.isExplicitlyOfflineNow, isTrue);
      expect((refreshed.startedAt, refreshed.restriction), (null, null));
      expect(await setup.site.getLiveStatus(roomId: _offline), isFalse);
      final stored = LiveRoom(roomId: _offline, platform: 'missevan', area: '配音', title: 'old');
      final merged = stored.mergeFrom(refreshed);
      expect(merged.area, '配音', reason: 'the detail has no area name');
      expect(merged.title, '配音交流区');
      expect(merged.isExplicitlyOfflineNow, isTrue);
    });

    test('an unknown room is NotFound; an id that is no room number asks nothing', () async {
      final setup = _setup(['S04-notfound']);
      await expectLater(setup.site.getRoomDetail(roomId: '1'), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getLiveStatus(roomId: '1'), throwsA(isA<NotFound>()));
      for (final id in ['0123', 'abc', '', '1/2']) {
        await expectLater(setup.site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(setup.http.requests, hasLength(2));
    });
  });

  group('streams', () {
    test('one quality 原画, FLV and HLS lines from the room detail: no request (13-1)', () async {
      final setup = _setup(['S04-live']);
      final room = await setup.site.getRoomDetail(roomId: _live);
      final qualities = await setup.site.getPlayQualities(detail: room);
      expect(qualities.map((quality) => (quality.quality, quality.id)), [('原画', '10000')]);
      final resolution = await setup.site.resolvePlayUrls(detail: room, quality: qualities.single);
      final [line, backup] = resolution.lines;
      expect((line.format, line.lineId), (StreamFormat.flv, 'flv'));
      expect((backup.format, backup.lineId), (StreamFormat.hls, 'hls'));
      expect(line.url, startsWith('https://d1-missevan04.bilivideo.com/'));
      expect(line.headers['referer'], 'https://fm.missevan.com/');
      expect(line.lease!.expiresAt, DateTime.fromMillisecondsSinceEpoch(1790534410 * 1000, isUtc: true));
      expect(resolution.appliedQualityData, '10000');
      expect(await setup.site.getPlayUrls(detail: room, quality: qualities.single), [
        startsWith('https://d1-missevan04.bilivideo.com/'),
        startsWith('https://d1-missevan104.bilivideo.com/'),
      ]);
      expect(setup.http.requests, hasLength(1));
      final url = line.url;
      expect(setup.site.getPlayUrlInvalidAt(url), line.lease!.expiresAt);
      expect(setup.site.getPlayUrlRefreshAt(url), line.lease!.refreshAt);
      expect(setup.site.getPlayUrlRefreshAt('https://example.org/a.flv?expires=1900000000'), isNull);
    });

    test('an offline room is StreamUnavailable without a request (3.x gave no qualities)', () async {
      final setup = _setup(['S04-offline']);
      final room = await setup.site.getRoomDetail(roomId: _offline);
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      await expectLater(
        setup.site.getPlayUrls(
          detail: room,
          quality: const LivePlayQuality(quality: 'HLS', id: 'hls'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(setup.http.requests, hasLength(1));
    });

    test('a room without pull URLs (a card, a pending state) reads its detail first', () async {
      final setup = _setup(['S04-live', 'S04-offline']);
      final pending = LiveRoom(roomId: _live, platform: 'missevan', liveStatus: LiveStatus.unknown);
      expect(await setup.site.getPlayQualities(detail: pending), hasLength(1));
      final card = LiveRoom(roomId: _offline, platform: 'missevan', liveStatus: LiveStatus.live);
      await expectLater(setup.site.getPlayQualities(detail: card), throwsA(isA<StreamUnavailable>()));
      expect(_paths(setup.http.requests), ['/api/v2/live/$_live', '/api/v2/live/$_offline']);
    });

    test('a quality the room does not offer is StreamUnavailable', () async {
      final setup = _setup(['S04-live']);
      final room = await setup.site.getRoomDetail(roomId: _live);
      await expectLater(
        setup.site.resolvePlayUrlsRaw(
          detail: room,
          quality: const LivePlayQuality(quality: 'HLS', id: 'other'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      await expectLater(
        setup.site.getPlayQualities(detail: room.copyWith(data: const MissevanRoomData())),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test("3.x's HLS and FLV qualities resolve to the one quality's lines (13-1)", () async {
      final setup = _setup(['S04-live']);
      final room = await setup.site.getRoomDetail(roomId: _live);
      for (final legacy in const [
        LivePlayQuality(quality: 'HLS', id: 'hls', sort: 2),
        LivePlayQuality(quality: 'FLV', id: 'flv', sort: 1),
      ]) {
        final resolution = await setup.site.resolvePlayUrlsRaw(detail: room, quality: legacy);
        expect(resolution.lines.map((line) => line.lineId), ['flv', 'hls']);
        expect(resolution.appliedQualityData, '10000');
      }
      expect(setup.http.requests, hasLength(1));
    });

    test('recovery reads the room again for fresh signed URLs (3.x)', () async {
      var generation = 0;
      final http = _Scripted((request) {
        expect(request.url.toString(), '$_api/live/100');
        return _response(request, _ok(_detail(hls: '$_hls&generation=${++generation}')));
      });
      final site = MissevanSite(http);
      final room = await site.getRoomDetailForRecording(roomId: '100');
      final quality = (await site.getPlayQualities(detail: room)).single;
      final recovered = await site.resolvePlayUrlsForRecovery(detail: room, quality: quality);
      expect(recovered.appliedQualityData, '10000');
      expect(recovered.urls.last, endsWith('generation=2'));
      expect((quality.data! as List).last, endsWith('generation=1'));
      expect(recovered.lines.last.lease!.cutsConnection, isTrue);
      expect(recovered.lines.first.lease!.cutsConnection, isFalse);
      expect(http.requests, hasLength(2));
    });

    test('recovery never revives a broadcast that ended (3.x)', () async {
      var calls = 0;
      final http = _Scripted((request) => _response(request, _ok(_detail(open: calls++ == 0 ? 1 : 0))));
      final site = MissevanSite(http);
      final room = await site.getRoomDetail(roomId: '100');
      final quality = (await site.getPlayQualities(detail: room)).first;
      await expectLater(
        site.resolvePlayUrlsForRecovery(detail: room, quality: quality),
        throwsA(isA<StreamUnavailable>()),
      );
    });
  });

  group('links', () {
    test('share texts with a room link, without requests (3.x)', () async {
      final http = ReplayHttp(const []);
      final site = MissevanSite(http);
      final parser = LinkParser(SiteRegistry({'missevan': () => site}), http);
      const link = 'https://fm.missevan.com/live/100';
      expect(site.roomIdFromUrl(link), '100');
      expect(site.roomIdFromUrl(' $link/ '), '100');
      expect(await parser.parse('分享 $link。'), const RoomLink('missevan', '100'));
      expect(await parser.parse('来听 https://fm.missevan.com/live/$_live 吧'), const RoomLink('missevan', _live));
      expect(parser.containsSupportedLink('分享 $link。'), isTrue);
      for (final invalid in [
        'https://fm.missevan.com.evil.test/live/100',
        'https://fm.missevan.com/catalog/100',
        'https://fm.missevan.com:8787/live/100',
        'https://name@fm.missevan.com/live/100',
        'https://www.missevan.com/live/100',
        'https://fm.missevan.com/live/0123',
      ]) {
        expect(site.roomIdFromUrl(invalid), isNull, reason: invalid);
        expect(site.needsResolving(invalid), isFalse);
        expect(await parser.parse(invalid), isNull, reason: invalid);
      }
      expect(http.requests, isEmpty);
    });
  });
}
