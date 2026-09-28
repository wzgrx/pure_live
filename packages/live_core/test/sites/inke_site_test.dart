// InkeSite over the recorded Inke responses (ReplayHttp) and a few
// synthetic ones: the request headers, the catalog, the showcase pages and
// 3.x's slices, keyword and exact search, room details for entry, refresh
// and recording, streams from the app API with the showcase fallback,
// leases and recovery, cancellation, links and the error mapping.
import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/inke';
const _webApi = 'https://webapi.busi.inke.cn/web';
const _appApi = 'https://service.inke.cn/api/live';

/// The live anchor of S03-share-live and S04-publish-live (in S01-top).
const _live = '771067357';
const _liveId = '1790521153165881';

/// The live anchor of S05, outside every showcase.
const _unlisted = '778920027';

const _media = 'https://live-pull-ws.ikstatic.cn/live/200_t.flv?wsSecret=fixture&wsABStime=70000000';

ReplaySample _synthetic(String url, Object body, {int status = 200}) => ReplaySample(
  method: 'GET',
  url: Uri.parse(url),
  status: status,
  bytes: utf8.encode(body is String ? body : jsonEncode(body)),
);

String _web(Object? data, {int code = 0}) => jsonEncode({'error_code': code, 'message': 'ok', 'data': data});

String _app(Object? live) => jsonEncode({'dm_error': 0, 'error_msg': '操作成功', 'live': live});

/// 3.x's test room answer of anchor 100.
Map<String, dynamic> _info() => {
  'live_uid': '100',
  'liveid': '200',
  'status': 1,
  'media_info': {'inke_id': 100, 'nick': 'Fixture'},
  'live_name': 'Test',
};

/// A `now_publish` broadcast of anchor [creator].
Map<String, dynamic> _broadcast({Object creator = 100, String id = '200', String url = _media}) => {
  'creator': creator,
  'id': id,
  'status': 1,
  'stream_addr': url,
};

Map<String, dynamic> _legacy(String name) => Fixture.load('inke', name).legacy as Map<String, dynamic>;

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
    throw TransportFailure('inke', reason, 'test');
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('inke', reason, 'test');

  @override
  void close() {}
}

LiveResponse _response(LiveRequest request, String body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);

typedef _Setup = ({InkeSite site, ReplayHttp http});

_Setup _setup(List<String> samples, {List<ReplaySample> extra = const [], DateTime Function()? now}) {
  final http = ReplayHttp([...extra, for (final name in samples) ReplaySample.load('$_root/$name')]);
  return (site: InkeSite(http, now: now), http: http);
}

List<String> _paths(Iterable<LiveRequest> requests) => [for (final request in requests) request.url.path];

final Matcher _cancelled = throwsA(
  isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled),
);

void main() {
  group('requests', () {
    test("3.x's headers on every request, redirects not followed", () async {
      final setup = _setup(['S01-channels', 'S03-share-live', 'S04-publish-live']);
      await setup.site.getCategories(1, 30);
      final room = await setup.site.getRoomDetail(roomId: _live);
      await setup.site.resolvePlayUrls(detail: room, quality: InkeApi.flv);
      expect(setup.http.requests.map((request) => request.url.host), [
        'webapi.busi.inke.cn',
        'webapi.busi.inke.cn',
        'service.inke.cn',
      ]);
      for (final request in setup.http.requests) {
        expect(request.headers, {
          'referer': 'https://www.inke.cn/',
          'origin': 'https://www.inke.cn',
          'user-agent': 'Mozilla/5.0',
        });
        expect(request.followRedirects, isFalse);
        expect(request.site, 'inke');
      }
      expect((setup.site.id, setup.site.name), ('inke', '映客'));
      expect(setup.site.getDanmaku(), isA<EmptyDanmaku>(), reason: '3.x had no Inke danmaku');
      expect(setup.site.directoryNoticeKey, 'inke_directory_scope');
    });

    test('transport failures are NetworkFailure; a cancelled transport stays cancelled', () async {
      await expectLater(
        InkeSite(_Failing(TransportReason.connect)).getRoomDetail(roomId: '100'),
        throwsA(isA<NetworkFailure>()),
      );
      await expectLater(InkeSite(_Failing(TransportReason.cancelled)).getRoomDetail(roomId: '100'), _cancelled);
      final unavailable = _Scripted((request) => _response(request, '', status: 503));
      await expectLater(InkeSite(unavailable).getCategories(1, 30), throwsA(isA<NetworkFailure>()));
      final denied = _Scripted((request) => _response(request, '', status: 403));
      await expectLater(InkeSite(denied).getRoomDetail(roomId: '100'), throwsA(isA<RiskControl>()));
    });
  });

  group('catalog and directory', () {
    test('one category with the channels as areas; later pages ask nothing (3.x)', () async {
      final setup = _setup(['S01-channels']);
      final categories = await setup.site.getCategories(1, 30);
      expect((categories.single.id, categories.single.name), ('inke', '映客'));
      expect(categories.single.children, hasLength(6));
      expect(await setup.site.getCategories(2, 30), hasLength(_legacy('S01-channels')['getCategores(page: 2)'] as int));
      expect(_paths(setup.http.requests), ['/web/Live_channel_pc']);
    });

    test('the top list and each channel: one page, page 2 empty without a request (3.x)', () async {
      final setup = _setup(['S01-top', 'S01-channels']);
      final top = await setup.site.getDirectoryPage();
      final legacyTop = (_legacy('S01-top')['getDirectoryPage'] as Map<String, dynamic>)['result'] as Map;
      expect(top.rooms.map((room) => room.roomId), (legacyTop['rooms'] as List).map((room) => (room as Map)['roomId']));
      expect(top.hasMore, isFalse);
      final second = await setup.site.getDirectoryPage(page: 2);
      expect((second.page, second.rooms.length, second.hasMore), (2, 0, false));
      final areas = (await setup.site.getCategories(1, 30)).single.children;
      final pages = _legacy('S01-channels')['getDirectoryPage'] as Map<String, dynamic>;
      for (final area in areas) {
        final page = await setup.site.getDirectoryPage(category: LiveArea.fromJson(area.toJson()));
        final want = (pages[area.areaId] as Map<String, dynamic>)['result'] as Map;
        expect(page.rooms.map((room) => room.roomId), (want['rooms'] as List).map((room) => (room as Map)['roomId']));
      }
      expect(_paths(setup.http.requests), ['/web/Live_top_pc', ...List.filled(7, '/web/Live_channel_pc')]);
      await expectLater(
        setup.site.getDirectoryPage(
          category: const LiveArea(platform: 'inke', areaType: 'showcase', areaId: 'GONE'),
        ),
        throwsA(isA<NotFound>()),
      );
    });

    test("3.x's slices: every slice requests the one page", () async {
      final setup = _setup(['S01-top', 'S01-channels']);
      final recommended = _legacy('S01-top')['getRecommendRooms'] as Map<String, dynamic>;
      final categoryRooms = _legacy('S01-channels')['getCategoryRooms'] as Map<String, dynamic>;
      final music = (await setup.site.getCategories(1, 30)).single.children.first;
      setup.http.requests.clear();
      for (final (page, size) in [(1, 30), (1, 3), (2, 3), (3, 3), (4, 3)]) {
        final key = 'page $page, pageSize $size';
        final rooms = await setup.site.getRecommendRooms(page: page, pageSize: size);
        final want = (recommended[key] as Map<String, dynamic>)['result'] as List;
        expect(rooms.map((room) => room.roomId), want.map((room) => (room as Map)['roomId']), reason: key);
        final channel = await setup.site.getCategoryRooms(music, page: page, pageSize: size);
        final wantChannel = (categoryRooms[key] as Map<String, dynamic>)['result'] as List;
        expect(channel.map((room) => room.roomId), wantChannel.map((room) => (room as Map)['roomId']), reason: key);
      }
      expect(setup.http.requests, hasLength(10));
      const huge = 9223372036854775807;
      expect(await setup.site.getRecommendRooms(page: huge, pageSize: huge), isEmpty);
    });

    test('bad pages, sizes and areas are caller errors, without a request (3.x)', () async {
      final setup = _setup([]);
      await expectLater(setup.site.getDirectoryPage(page: 0), throwsArgumentError);
      await expectLater(setup.site.getRecommendRooms(page: 0), throwsArgumentError);
      await expectLater(setup.site.getRecommendRooms(pageSize: 0), throwsArgumentError);
      for (final area in [
        const LiveArea(platform: 'other', areaType: 'showcase', areaId: 'MUSIC'),
        const LiveArea(platform: 'inke', areaType: 'catalog', areaId: 'MUSIC'),
      ]) {
        await expectLater(setup.site.getDirectoryPage(category: area), throwsArgumentError, reason: '$area');
        await expectLater(setup.site.getCategoryRooms(area), throwsArgumentError, reason: '$area');
      }
      expect(setup.http.requests, isEmpty);
    });

    test('the cancellation goes with the request, and wins after the answer (3.x)', () async {
      final token = CancelToken();
      final setup = _setup(['S01-top']);
      await setup.site.getDirectoryPage(cancel: token);
      expect(identical(setup.http.requests.single.cancel, token), isTrue);
      await expectLater(setup.site.getDirectoryPage(cancel: CancelToken()..cancel()), _cancelled);
      await expectLater(setup.site.getDirectoryPage(page: 2, cancel: CancelToken()..cancel()), _cancelled);
      expect(setup.http.requests, hasLength(1), reason: 'nothing sent once cancelled');
      final afterAnswer = CancelToken();
      final http = _Scripted((request) {
        afterAnswer.cancel();
        return _response(request, _web({'list': <Object?>[]}));
      });
      await expectLater(InkeSite(http).getDirectoryPage(cancel: afterAnswer), _cancelled);
      final afterFailure = CancelToken();
      final broken = _Scripted((request) {
        afterFailure.cancel();
        throw const TransportFailure('inke', TransportReason.connect);
      });
      await expectLater(InkeSite(broken).getDirectoryPage(cancel: afterFailure), _cancelled);
    });
  });

  group('search', () {
    final legacy = _legacy('S01-top');
    final searches = legacy['searchRooms'] as Map<String, dynamic>;

    test('keywords filter the nicknames of the top list and the channels, as 3.x', () async {
      final setup = _setup(['S01-top', 'S01-channels']);
      for (final keyword in ['糖果', '西', '欧阳', 'mee', '🎶', 'zxqvnoresultfixture']) {
        setup.http.requests.clear();
        final rooms = await setup.site.searchRooms(keyword, pageSize: 20);
        final want = searches[keyword] as Map<String, dynamic>;
        expect(rooms.map((room) => room.roomId), (want['result'] as List).map((room) => (room as Map)['roomId']));
        expect([for (final request in setup.http.requests) request.url.toString()], want['requests'], reason: keyword);
        expect(
          setup.site.supportsSearchPaginationFor(keyword),
          (legacy['supportsSearchPaginationFor'] as Map)[keyword],
        );
      }
      for (final page in [1, 2, 3]) {
        final rooms = await setup.site.searchRooms('🎶', page: page, pageSize: 3);
        final want = (searches['🎶 page $page, pageSize 3'] as Map<String, dynamic>)['result'] as List;
        expect(rooms.map((room) => room.roomId), want.map((room) => (room as Map)['roomId']), reason: 'page $page');
      }
    });

    test('a uid or room link finds that room, live or not, on page 1 only (3.x)', () async {
      final setup = _setup(['S03-share-live', 'S03-share-offline']);
      final live = await setup.site.searchRooms(_live);
      expect((live.single.roomId, live.single.nick, live.single.isLiveNow), (_live, '木子', true));
      final offline = await setup.site.searchRooms('https://www.inke.cn/liveroom/index.html?uid=1&id=old');
      final want = ((_legacy('S03-share-offline')['searchRooms'] as Map)['result'] as List).single as Map;
      expect((offline.single.title, offline.single.nick), (want['title'], want['nick']));
      expect((offline.single.title, offline.single.isExplicitlyOfflineNow), ('UID 1', true));
      final shared = await setup.site.searchRooms('https://mlive2.inke.cn/app/hot/live?uid=$_live&liveid=$_liveId');
      expect(shared.single.roomId, _live, reason: 'the app share link');
      expect(await setup.site.searchRooms(_live, page: 2), isEmpty);
      expect(_paths(setup.http.requests), everyElement('/web/live_share_pc'));
      expect(setup.http.requests, hasLength(3));
      for (final input in [_live, 'https://www.inke.cn/liveroom/index.html?uid=$_live']) {
        expect(setup.site.supportsSearchPaginationFor(input), isFalse, reason: input);
      }
    });

    test('only a 404 is an empty exact result; other failures stay errors; the cancellation goes along', () async {
      final token = CancelToken();
      final absent = _Scripted((request) => _response(request, '', status: 404));
      expect(await InkeSite(absent).searchRoomsWithCancellation('100', cancel: token), isEmpty);
      expect(identical(absent.requests.single.cancel, token), isTrue);
      final denied = _Scripted((request) => _response(request, '', status: 403));
      await expectLater(InkeSite(denied).searchRooms('100'), throwsA(isA<RiskControl>()));
      await expectLater(InkeSite(absent).searchRoomsCancellable('100', cancel: CancelToken()..cancel()), _cancelled);
      expect(absent.requests, hasLength(1));
    });

    test('other links and blank input find nothing without a request (3.x)', () async {
      final setup = _setup([]);
      for (final input in [
        'https://www.inke.cn/',
        'https://www.inke.cn.evil.test/liveroom/index.html?uid=100',
        'https://other.example/live/100',
        '   ',
      ]) {
        expect(await setup.site.searchRooms(input), isEmpty, reason: input);
        expect(setup.site.supportsSearchPaginationFor(input), isFalse, reason: input);
      }
      expect(setup.http.requests, isEmpty);
    });

    test('a keyword with a colon is a keyword (3.x took `Re:Zero` for a link and found nothing)', () async {
      final row = {'uid': 100, 'live_id': '200', 'nick': 'Re:Zero 主播', 'stream_addr': _media};
      final setup = _setup(
        [],
        extra: [
          _synthetic('$_webApi/Live_top_pc', _web({'list': <Object?>[]})),
          _synthetic(
            '$_webApi/Live_channel_pc',
            _web({
              'list': [
                {
                  'tab_key': 'MUSIC',
                  'channel_name': '音乐',
                  'list': [row],
                },
              ],
            }),
          ),
        ],
      );
      expect((await setup.site.searchRooms('Re:Zero')).single.roomId, '100');
      expect(setup.site.supportsSearchPaginationFor('Re:Zero'), isTrue);
    });

    test('pages, sizes and keywords 3.x refused are refused without a request', () async {
      final setup = _setup([]);
      await expectLater(setup.site.searchRooms('主播', page: 0), throwsArgumentError);
      await expectLater(setup.site.searchRooms('主播', pageSize: 0), throwsArgumentError);
      await expectLater(setup.site.searchRooms('', pageSize: 0), throwsArgumentError);
      await expectLater(setup.site.searchRooms('主播', page: 10001), throwsArgumentError);
      await expectLater(setup.site.searchRooms('主播', pageSize: 61), throwsArgumentError);
      await expectLater(setup.site.searchRooms('x' * 101), throwsArgumentError);
      expect(setup.http.requests, isEmpty);
    });
  });

  group('rooms', () {
    test('entry, refresh and recording: one request each, the uid asked for (3.x: two for entry)', () async {
      final setup = _setup(['S03-share-live']);
      final legacy = _legacy('S03-share-live');
      expect((legacy['getRoomDetail'] as Map)['requests'], hasLength(2), reason: '3.x also read the top list');
      final entered = await setup.site.getRoomDetail(roomId: _live);
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: ' $_live ');
      final recorded = await setup.site.getRoomDetailForRecording(roomId: _live);
      for (final room in [entered, refreshed, recorded]) {
        expect(room.roomId, _live);
        expect(room.isLiveNow, isTrue);
        expect((room.data! as InkeRoomData).liveId, _liveId);
      }
      expect(await setup.site.getLiveStatus(roomId: _live), isTrue);
      expect(
        setup.http.requests.map((request) => request.url.toString()),
        everyElement('$_webApi/live_share_pc?uid=$_live'),
      );
      expect(setup.http.requests, hasLength(4));
    });

    test('S05: a room outside every showcase opens (3.x failed it after four requests)', () async {
      final setup = _setup(['S05-unlisted-share']);
      final room = await setup.site.getRoomDetail(roomId: _unlisted);
      expect((room.nick, room.isLiveNow), ('璇璇', true));
      expect(await setup.site.getRoomDetailForRecording(roomId: _unlisted), isNotNull);
      expect(setup.http.requests, hasLength(2));
    });

    test('an offline refresh keeps what the card knew (mergeFrom)', () async {
      final setup = _setup(['S03-share-offline']);
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: '1');
      expect(refreshed.isExplicitlyOfflineNow, isTrue);
      expect(await setup.site.getLiveStatus(roomId: '1'), isFalse);
      final stored = LiveRoom(roomId: '1', platform: 'inke', nick: '木子', title: '木子', cover: 'https://img/x.jpg');
      final merged = stored.mergeFrom(refreshed);
      expect((merged.nick, merged.title, merged.cover), ('木子', '木子', 'https://img/x.jpg'));
      expect(merged.isExplicitlyOfflineNow, isTrue);
    });

    test('an id that is not a uid is NotFound without a request; a 404 is NotFound', () async {
      final setup = _setup([]);
      for (final id in ['0123', 'abc', '', '1/2', '1234567890123456789']) {
        await expectLater(setup.site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(setup.http.requests, isEmpty);
      final absent = _Scripted((request) => _response(request, '', status: 404));
      await expectLater(InkeSite(absent).getRoomDetail(roomId: '100'), throwsA(isA<NotFound>()));
    });
  });

  group('streams', () {
    test('entry and play: the FLV quality without a request, then one now_publish with a fresh line', () async {
      final issued = Fixture.load('inke', 'S04-publish-live').capturedAt;
      final setup = _setup(['S03-share-live', 'S04-publish-live'], now: () => issued);
      final room = await setup.site.getRoomDetail(roomId: _live);
      final qualities = await setup.site.getPlayQualities(detail: room);
      expect(qualities.map((quality) => (quality.quality, quality.id)), [('FLV', 'flv')]);
      expect(setup.http.requests, hasLength(1));
      final resolution = await setup.site.resolvePlayUrls(detail: room, quality: qualities.single);
      final line = resolution.lines.single;
      final publish = jsonDecode(Fixture.load('inke', 'S04-publish-live').body) as Map<String, dynamic>;
      expect(line.url, (publish['live'] as Map<String, dynamic>)['stream_addr']);
      expect((line.format, line.codec, line.lineId), (StreamFormat.flv, 'avc', 'ws'));
      expect(line.headers['referer'], 'https://www.inke.cn/');
      expect(line.lease!.expiresAt, DateTime.fromMillisecondsSinceEpoch(0x6ab96f0b * 1000, isUtc: true));
      expect(resolution.appliedQualityData, 'flv');
      expect(setup.http.requests.last.url.toString(), '$_appApi/now_publish?id=$_live');
      expect(await setup.site.getPlayUrls(detail: room, quality: qualities.single), [line.url]);
      expect(setup.http.requests, hasLength(3), reason: 'each resolution signs anew');
    });

    test('S05: the room 3.x could not play plays (REG-INKE-001)', () async {
      final setup = _setup(['S05-unlisted-share', 'S05-unlisted-publish']);
      final room = await setup.site.getRoomDetail(roomId: _unlisted);
      final resolution = await setup.site.resolvePlayUrls(detail: room, quality: InkeApi.flv);
      expect(resolution.urls.single, startsWith('https://live-pull-ws.ikstatic.cn/live/1790588581683219_t.flv?'));
      expect(_paths(setup.http.requests), ['/web/live_share_pc', '/api/live/now_publish']);
    });

    test('an offline room or another quality is StreamUnavailable without a request', () async {
      final setup = _setup(['S03-share-offline']);
      final room = await setup.site.getRoomDetail(roomId: '1');
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      await expectLater(setup.site.getPlayUrls(detail: room, quality: InkeApi.flv), throwsA(isA<StreamUnavailable>()));
      final live = LiveRoom(roomId: _live, platform: 'inke', liveStatus: LiveStatus.live);
      await expectLater(
        setup.site.resolvePlayUrlsRaw(
          detail: live,
          quality: const LivePlayQuality(quality: 'HLS', id: 'hls'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(setup.http.requests, hasLength(1));
    });

    test('when the app says the anchor is not live, nothing else is asked', () async {
      final setup = _setup(['S04-publish-offline']);
      final card = LiveRoom(roomId: '1', platform: 'inke', liveStatus: LiveStatus.live);
      await expectLater(
        setup.site.resolvePlayUrls(detail: card, quality: InkeApi.flv),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(_paths(setup.http.requests), ['/api/live/now_publish']);
    });

    test('a pending card offers FLV and resolves through the app', () async {
      final setup = _setup(['S04-publish-live']);
      final pending = LiveRoom(roomId: _live, platform: 'inke', liveStatus: LiveStatus.unknown);
      expect(await setup.site.getPlayQualities(detail: pending), [InkeApi.flv]);
      expect((await setup.site.resolvePlayUrls(detail: pending, quality: InkeApi.flv)).urls, hasLength(1));
    });

    test("the app failing, 3.x's showcase lookup finds the room entry's broadcast: 3.x's URL", () async {
      final setup = _setup(
        ['S03-share-live', 'S01-top'],
        extra: [_synthetic('$_appApi/now_publish?id=$_live', '', status: 503)],
        now: () => Fixture.load('inke', 'S01-top').capturedAt,
      );
      final room = await setup.site.getRoomDetail(roomId: _live);
      final resolution = await setup.site.resolvePlayUrls(detail: room, quality: InkeApi.flv);
      final quality = (_legacy('S03-share-live')['getPlayQualites'] as List).single as Map;
      expect(resolution.urls, quality['getPlayUrls'], reason: 'byte for byte');
      expect(resolution.lines.single.lease, isNotNull);
      expect(_paths(setup.http.requests), ['/web/live_share_pc', '/api/live/now_publish', '/web/Live_top_pc']);
    });

    for (final (key, depth) in [('3148072/1790581274957465', 2), ('764622336/1790589556486896', 3)]) {
      test('an app broadcast without a Wangsu URL is looked for in the showcases in order ($key)', () async {
        final [uid, liveId] = key.split('/');
        final setup = _setup(
          ['S05-unlisted-top', 'S05-unlisted-hot', 'S05-unlisted-channels'],
          extra: [
            _synthetic('$_appApi/now_publish?id=$uid', _app(_broadcast(creator: int.parse(uid), id: liveId, url: ''))),
          ],
        );
        final card = LiveRoom(roomId: uid, platform: 'inke', liveStatus: LiveStatus.live);
        final resolution = await setup.site.resolvePlayUrls(detail: card, quality: InkeApi.flv);
        final want = _legacy('S05-unlisted-hot')[key] as Map<String, dynamic>;
        expect(resolution.urls, want['result']);
        expect(setup.http.requests, hasLength(1 + depth));
        expect(_paths(setup.http.requests.skip(1)), [
          for (final url in want['requests'] as List) Uri.parse(url as String).path,
        ]);
      });
    }

    test("a broadcast no showcase holds reports the app's answer", () async {
      final setup = _setup(
        ['S05-unlisted-share', 'S05-unlisted-top', 'S05-unlisted-hot', 'S05-unlisted-channels'],
        extra: [_synthetic('$_appApi/now_publish?id=$_unlisted', '', status: 503)],
      );
      final room = await setup.site.getRoomDetail(roomId: _unlisted);
      await expectLater(
        setup.site.resolvePlayUrls(detail: room, quality: InkeApi.flv),
        throwsA(isA<NetworkFailure>()),
        reason: 'transient: the app may answer the next time',
      );
      expect(setup.http.requests, hasLength(5));
      final zegoOnly = _setup(
        ['S05-unlisted-top', 'S05-unlisted-hot', 'S05-unlisted-channels'],
        extra: [
          _synthetic(
            '$_appApi/now_publish?id=$_unlisted',
            _app(_broadcast(creator: int.parse(_unlisted), id: '1790588581683219', url: '')),
          ),
        ],
      );
      final card = LiveRoom(roomId: _unlisted, platform: 'inke', liveStatus: LiveStatus.live);
      await expectLater(
        zegoOnly.site.resolvePlayUrls(detail: card, quality: InkeApi.flv),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('the app failing for a room without a known broadcast (a list card) is reported at once', () async {
      final setup = _setup([], extra: [_synthetic('$_appApi/now_publish?id=100', '{"dm_error":499}')]);
      final card = LiveRoom(roomId: '100', platform: 'inke', liveStatus: LiveStatus.live);
      await expectLater(setup.site.resolvePlayUrls(detail: card, quality: InkeApi.flv), throwsA(isA<ApiChanged>()));
      expect(_paths(setup.http.requests), ['/api/live/now_publish']);
    });

    test('recovery signs anew every time, whatever the last known state', () async {
      var generation = 0;
      final http = _Scripted((request) {
        if (request.url.path.endsWith('live_share_pc')) return _response(request, _web(_info()));
        expect(request.url.toString(), '$_appApi/now_publish?id=100');
        return _response(request, _app(_broadcast(url: '$_media&generation=${++generation}')));
      });
      final site = InkeSite(http);
      final room = await site.getRoomDetailForRecording(roomId: '100');
      final first = await site.resolvePlayUrls(detail: room, quality: InkeApi.flv);
      final recovered = await site.resolvePlayUrlsForRecovery(detail: room, quality: InkeApi.flv);
      expect(first.urls.single, endsWith('generation=1'));
      expect(recovered.urls.single, endsWith('generation=2'));
      expect(recovered.appliedQualityData, 'flv');
      final stale = room.copyWith(liveStatus: LiveStatus.offline);
      expect((await site.resolvePlayUrlsForRecovery(detail: stale, quality: InkeApi.flv)).urls.single, endsWith('=3'));
      expect(http.requests, hasLength(4));
    });

    test('recovery never revives a broadcast that ended', () async {
      final http = _Scripted((request) => _response(request, _app(null)));
      final room = LiveRoom(roomId: '100', platform: 'inke', liveStatus: LiveStatus.live);
      await expectLater(
        InkeSite(http).resolvePlayUrlsForRecovery(detail: room, quality: InkeApi.flv),
        throwsA(isA<StreamUnavailable>()),
      );
    });
  });

  group('links', () {
    test('share texts with a room or app share link, without requests (3.x, plus the app link)', () async {
      final http = ReplayHttp(const []);
      final site = InkeSite(http);
      final parser = LinkParser(SiteRegistry({'inke': () => site}), http);
      const link = 'https://www.inke.cn/liveroom/index.html?uid=100&id=199';
      expect(site.roomIdFromUrl(' $link '), '100');
      expect(await parser.parse('share $link'), const RoomLink('inke', '100'));
      expect(await parser.parse('来看 $link。'), const RoomLink('inke', '100'));
      expect(parser.containsSupportedLink('share $link'), isTrue);
      const share = 'https://mlive2.inke.cn/app/hot/live?uid=$_live&liveid=$_liveId&ctime=1790521153';
      expect(await parser.parse('映客直播 $share'), const RoomLink('inke', _live));
      for (final invalid in [
        link.replaceAll('inke.cn', 'inke.cn.evil.test'),
        link.replaceAll('www.', 'user@www.'),
        '$link&uid=101',
        'https://www.inke.cn/',
      ]) {
        expect(site.roomIdFromUrl(invalid), isNull, reason: invalid);
        expect(site.needsResolving(invalid), isFalse);
        expect(parser.containsSupportedLink(invalid), isFalse, reason: invalid);
        expect(await parser.parse(invalid), isNull, reason: invalid);
      }
      expect(http.requests, isEmpty);
    });
  });
}
