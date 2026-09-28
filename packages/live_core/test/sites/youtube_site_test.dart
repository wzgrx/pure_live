// YouTubeSite over the recorded YouTube responses (ReplayHttp) and a few
// synthetic ones: 3.x's requests and headers for room entry, refresh,
// recording and live status, the sources kept by room entry, qualities,
// lines and leases, the recovery, the one-reference search with its
// channel lookup and cancellation, the empty catalog, links and the error
// mapping. Requests are compared with the ones 3.x sent (expected.json
// records them).
import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/youtube';

/// The live broadcast of S07 and its channel.
const _live = 'nI725iVsyoQ';
const _lofi = 'UCSJ4gkVC6NrvII8umztf0Ow';

const _liveSamples = ['S07-watch-live', 'S07-player-live', 'S07-hls-live'];

const _ended = '9njefMDxzqw';
const _upcoming = '32myp8UqPOE';
const _video = 'dQw4w9WgXcQ';
const _missing = 'aaaaaaaaaaa';

const List<String> _allSamples = [
  ..._liveSamples,
  'S07-channel-live',
  'S08-channel-offline',
  'S09-watch-ended',
  'S09-player-ended',
  'S10-watch-upcoming',
  'S10-player-upcoming',
  'S11-watch-video',
  'S11-player-video',
  'S12-watch-missing',
  'S12-player-missing',
];

typedef _Setup = ({YouTubeSite site, ReplayHttp http});

_Setup _setup([List<String> samples = _allSamples, List<ReplaySample> extra = const []]) {
  final http = ReplayHttp([...extra, for (final name in samples) ReplaySample.load('$_root/$name')]);
  return (site: YouTubeSite(http), http: http);
}

Map<String, dynamic> _legacy(String sample) => Fixture.load('youtube', sample).legacy as Map<String, dynamic>;

Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

/// 3.x's requests of a traced legacy call: method, URL and headers (names in
/// lower case).
List<Map<String, Object?>> _legacyRequests(Object? traced) => [
  for (final request in ((traced! as Map<String, dynamic>)['requests'] as List).cast<Map<String, dynamic>>())
    {
      'method': request['method'],
      'url': request['url'],
      'headers': {
        for (final MapEntry(:key, :value) in (request['headers'] as Map<String, dynamic>).entries)
          key.toLowerCase(): value,
      },
    },
];

List<Map<String, Object?>> _sent(Iterable<LiveRequest> requests) => [
  for (final request in requests)
    {
      'method': request.method,
      'url': '${request.url}',
      'headers': {for (final MapEntry(:key, :value) in request.headers.entries) key.toLowerCase(): value},
    },
];

List<String> _urls(Iterable<LiveRequest> requests) => [for (final request in requests) '${request.url}'];

/// Asserts that [room] matches 3.x's projection on every key 3.x wrote.
void _expectRoom(LiveRoom room, Object? legacy, {String reason = ''}) {
  final actual = {...room.toJson(), 'link': room.link};
  for (final MapEntry(:key, :value) in (legacy! as Map<String, dynamic>).entries) {
    expect(actual[key] ?? '', value ?? '', reason: '$reason $key');
  }
}

final Matcher _cancelled = throwsA(
  isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled),
);

ReplaySample _get(String url, Object body, {int status = 200, Map<String, List<String>> headers = const {}}) =>
    ReplaySample(
      method: 'GET',
      url: Uri.parse(url),
      status: status,
      bytes: utf8.encode(body is String ? body : jsonEncode(body)),
      headers: headers,
    );

ReplaySample _player(String videoId, Object body, {String key = YouTubeApi.fallbackApiKey, int status = 200}) =>
    ReplaySample(
      method: 'POST',
      url: YouTubeApi.playerUrl(key),
      status: status,
      bytes: utf8.encode(body is String ? body : jsonEncode(body)),
      json: YouTubeApi.playerBody(videoId),
    );

Map<String, dynamic> _livePlayer() =>
    jsonDecode(Fixture.load('youtube', 'S07-player-live').body) as Map<String, dynamic>;

String get _masterUrl => (_livePlayer()['streamingData'] as Map<String, dynamic>)['hlsManifestUrl'] as String;

final class _Failing implements LiveHttp {
  new(this.reason);

  final TransportReason reason;

  @override
  Future<LiveResponse> send(LiveRequest request) async => throw TransportFailure('youtube', reason, 'test');

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('youtube', reason, 'test');

  @override
  void close() {}
}

void main() {
  group('rooms', () {
    final legacy = _legacy('S07-watch-live')[_live] as Map<String, dynamic>;

    for (final (depth, count) in [
      ('getRoomDetail', 3),
      ('getRoomDetailForRefresh', 2),
      ('getRoomDetailForRecording', 3),
    ]) {
      test("$depth: 3.x's $count requests with 3.x's headers, and 3.x's room", () async {
        final setup = _setup();
        final room = await switch (depth) {
          'getRoomDetail' => setup.site.getRoomDetail(roomId: _live),
          'getRoomDetailForRefresh' => setup.site.getRoomDetailForRefresh(roomId: _live),
          _ => setup.site.getRoomDetailForRecording(roomId: _live),
        };
        expect(_sent(setup.http.requests), _legacyRequests(legacy[depth]));
        expect(setup.http.requests, hasLength(count));
        expect(setup.http.requests.every((request) => request.site == 'youtube'), isTrue);
        expect(setup.http.requests.every((request) => request.timeout == const Duration(seconds: 25)), isTrue);
        _expectRoom(room, _result(legacy[depth]), reason: depth);
        expect(room.roomId, _live, reason: 'the video id is the identity 3.x stored');
        if (count == 3) {
          final data = room.data! as YouTubeRoomData;
          expect(data.videoId, _live);
          expect(data.streams, hasLength(7));
          expect(data.streamError, isNull);
        } else {
          expect(room.data, isNull, reason: 'a refresh reads no stream');
        }
      });
    }

    test("the player request is 3.x's: POST with the page's key and the ANDROID body", () async {
      final setup = _setup();
      await setup.site.getRoomDetailForRefresh(roomId: _live);
      final player = setup.http.requests[1];
      expect(player.method, 'POST');
      expect(player.url, YouTubeApi.playerUrl(YouTubeApi.fallbackApiKey));
      expect(jsonDecode(utf8.decode(player.body!)), YouTubeApi.playerBody(_live));
      expect(player.headers['content-type'], 'application/json; charset=utf-8');
    });

    test('live status: the refresh detail (two requests, as 3.x)', () async {
      final setup = _setup();
      expect(await setup.site.getLiveStatus(roomId: _live), _result(legacy['getLiveStatus']));
      expect(_sent(setup.http.requests), _legacyRequests(legacy['getLiveStatus']));
      expect(await setup.site.getLiveStatus(roomId: _ended), isFalse);
    });

    for (final (sample, videoId) in [('S09-watch-ended', _ended), ('S10-watch-upcoming', _upcoming)]) {
      test('$sample: offline at every depth with two requests; no stream, no request for qualities', () async {
        final expected = _legacy(sample)[videoId] as Map<String, dynamic>;
        final setup = _setup();
        final entry = await setup.site.getRoomDetail(roomId: videoId);
        expect(_sent(setup.http.requests), _legacyRequests(expected['getRoomDetail']));
        _expectRoom(entry, _result(expected['getRoomDetail']));
        expect(entry.effectiveLiveStatus, LiveStatus.offline);
        expect(entry.data, isNull);
        _expectRoom(
          await setup.site.getRoomDetailForRefresh(roomId: videoId),
          _result(expected['getRoomDetailForRefresh']),
        );
        _expectRoom(
          await setup.site.getRoomDetailForRecording(roomId: videoId),
          _result(expected['getRoomDetailForRecording']),
        );
        setup.http.requests.clear();
        // 3.x gave an empty list.
        await expectLater(setup.site.getPlayQualities(detail: entry), throwsA(isA<StreamUnavailable>()));
        expect(setup.http.requests, isEmpty);
      });
    }

    test("S11 an ordinary video and S12 a missing one are NotFound after 3.x's two requests", () async {
      for (final (sample, videoId) in [('S11-watch-video', _video), ('S12-watch-missing', _missing)]) {
        final expected = _legacy(sample)[videoId] as Map<String, dynamic>;
        final setup = _setup();
        await expectLater(setup.site.getRoomDetail(roomId: videoId), throwsA(isA<NotFound>()));
        expect(_sent(setup.http.requests), _legacyRequests(expected['getRoomDetail']), reason: sample);
        await expectLater(setup.site.getLiveStatus(roomId: videoId), throwsA(isA<NotFound>()));
      }
    });

    test('a room id that is no video id is NotFound without a request (3.x: identity)', () async {
      final setup = _setup();
      for (final id in ['short', '', 'nI725iVsyoQ!', '@LofiGirl']) {
        await expectLater(setup.site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(setup.http.requests, isEmpty);
      expect((await setup.site.getRoomDetailForRefresh(roomId: ' $_live ')).roomId, _live);
    });

    test('a live room without readable sources still opens; its qualities say why (3.x failed the room)', () async {
      final bad = _livePlayer()..['streamingData'] = {'hlsManifestUrl': 'https://evil.example/index.m3u8'};
      final setup = _setup(['S07-watch-live'], [_player(_live, bad)]);
      final room = await setup.site.getRoomDetail(roomId: _live);
      expect(room.isLiveNow, isTrue);
      expect((room.data! as YouTubeRoomData).streamError, isA<ApiChanged>());
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<ApiChanged>()));

      final none = _livePlayer()..['streamingData'] = <String, Object?>{};
      final empty = _setup(['S07-watch-live'], [_player(_live, none)]);
      final silent = await empty.site.getRoomDetail(roomId: _live);
      expect((silent.data! as YouTubeRoomData).streams, isEmpty);
      await expectLater(empty.site.getPlayQualities(detail: silent), throwsA(isA<StreamUnavailable>()));
    });
  });

  group('streams', () {
    final legacy = _legacy('S07-watch-live')[_live] as Map<String, dynamic>;

    test("qualities and lines come from room entry without a request, as 3.x's", () async {
      final setup = _setup();
      final room = await setup.site.getRoomDetail(roomId: _live);
      setup.http.requests.clear();
      final qualities = await setup.site.getPlayQualities(detail: room);
      expect([
        for (final quality in qualities)
          {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort, 'data': quality.data},
      ], _result(legacy['getPlayQualites']));
      final expected = legacy['resolvePlayUrlsRaw'] as Map<String, dynamic>;
      for (final quality in qualities) {
        final want = _result(expected['${quality.id}'])! as Map<String, dynamic>;
        final resolution = await setup.site.resolvePlayUrls(detail: room, quality: quality);
        expect(resolution.urls, want['urls'], reason: '${quality.id}');
        expect(resolution.appliedQualityData, want['appliedQualityData']);
        expect(await setup.site.getPlayUrls(detail: room, quality: quality), want['urls']);
        final line = resolution.lines.single;
        expect(line.headers, room.httpHeaders);
        expect(line.lease!.expiresAt!.toIso8601String(), (want['invalidAt'] as List).single);
        expect(
          resolveAppliedPlayQuality(qualities: qualities, requested: quality, resolution: resolution),
          same(quality),
        );
      }
      expect(setup.http.requests, isEmpty);
    });

    test("lease metadata is 3.x's: expire, renewed 10 minutes before", () async {
      final setup = _setup();
      final room = await setup.site.getRoomDetail(roomId: _live);
      final expected = legacy['resolvePlayUrlsRaw'] as Map<String, dynamic>;
      for (final quality in await setup.site.getPlayQualities(detail: room)) {
        final want = _result(expected['${quality.id}'])! as Map<String, dynamic>;
        final url = (want['urls'] as List).single as String;
        expect(setup.site.getPlayUrlInvalidAt(url)?.toIso8601String(), (want['invalidAt'] as List).single);
        expect(setup.site.getPlayUrlRefreshAt(url)?.toIso8601String(), (want['refreshAt'] as List).single);
      }
    });

    test("a card or a refreshed room makes room entry's requests first (3.x: identity error)", () async {
      expect(_result(legacy['getPlayQualites (refreshed room)']), {
        'throws': 'YouTubeException',
        'message': 'YouTube identity',
      });
      final setup = _setup();
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: _live);
      setup.http.requests.clear();
      final qualities = await setup.site.getPlayQualities(detail: refreshed);
      expect(qualities, hasLength(7));
      expect(_sent(setup.http.requests), _legacyRequests(legacy['getRoomDetail']));
      final card = LiveRoom(platform: 'youtube', roomId: _live);
      expect(
        (await setup.site.resolvePlayUrlsRaw(detail: card, quality: qualities.first)).appliedQualityData,
        'hls:1080:0:h264',
      );
    });

    test('offline and banned rooms have no qualities, without a request', () async {
      final setup = _setup();
      await expectLater(
        setup.site.getPlayQualities(
          detail: LiveRoom(platform: 'youtube', roomId: _live, liveStatus: LiveStatus.offline),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      await expectLater(
        setup.site.getPlayQualities(
          detail: LiveRoom(platform: 'youtube', roomId: _live, liveStatus: LiveStatus.banned),
        ),
        throwsA(isA<NeedsLogin>()),
      );
      expect(setup.http.requests, isEmpty);
      expect(
        () => setup.site.getPlayQualities(
          detail: LiveRoom(platform: 'twitch', roomId: _live),
        ),
        throwsArgumentError,
      );
    });

    test('a card whose broadcast has since ended is StreamUnavailable after the entry requests', () async {
      final ended = _livePlayer()..['playabilityStatus'] = {'status': 'LIVE_STREAM_OFFLINE'};
      final setup = _setup(['S07-watch-live'], [_player(_live, ended)]);
      await expectLater(
        setup.site.getPlayQualities(
          detail: LiveRoom(platform: 'youtube', roomId: _live),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test("a master that cannot be read offers the master itself, as 3.x ('HLS 自动')", () async {
      for (final master in [_get(_masterUrl, '', status: 500), _get(_masterUrl, 'not a playlist')]) {
        final setup = _setup(['S07-watch-live', 'S07-player-live'], [master]);
        final room = await setup.site.getRoomDetail(roomId: _live);
        final qualities = await setup.site.getPlayQualities(detail: room);
        expect(qualities.map((quality) => quality.quality), ['HLS 自动 · HLS', 'DASH 自动 · DASH']);
        final lines = (await setup.site.resolvePlayUrlsRaw(detail: room, quality: qualities.first)).lines;
        expect(lines.single.url, _masterUrl);
        expect(lines.single.format, StreamFormat.hls);
      }
    });

    test("recovery: the player answer and the master (3.x also read the watch page), 3.x's URL", () async {
      final setup = _setup();
      final room = await setup.site.getRoomDetail(roomId: _live);
      final quality = (await setup.site.getPlayQualities(detail: room)).first;
      setup.http.requests.clear();
      final resolution = await setup.site.resolvePlayUrlsForRecovery(detail: room, quality: quality);
      final expected = legacy['resolvePlayUrlsForRecoveryRaw(hls:1080:0:h264)'];
      expect(resolution.urls, (_result(expected)! as Map<String, dynamic>)['urls']);
      expect(resolution.appliedQualityData, 'hls:1080:0:h264');
      expect(_sent(setup.http.requests), _legacyRequests(expected).skip(1));
      expect(resolution.lines.single.lease, isNotNull);
    });

    test('recovery of the DASH or the master source needs no master request', () async {
      final setup = _setup();
      final room = await setup.site.getRoomDetail(roomId: _live);
      setup.http.requests.clear();
      final dash = await setup.site.resolvePlayUrlsForRecoveryRaw(
        detail: room,
        quality: const LivePlayQuality(quality: 'DASH 自动 · DASH', id: 'dash:auto'),
      );
      expect(dash.urls.single, contains('/api/manifest/dash/'));
      final auto = await setup.site.resolvePlayUrlsForRecoveryRaw(
        detail: room,
        quality: const LivePlayQuality(quality: 'HLS 自动 · HLS', id: 'hls:auto'),
      );
      expect(auto.urls.single, _masterUrl);
      expect(_urls(setup.http.requests), everyElement(contains('/youtubei/v1/player')));
    });

    test('recovery keeps the quality: one no longer offered, or a room no longer live, is an error', () async {
      final setup = _setup();
      final room = await setup.site.getRoomDetail(roomId: _live);
      await expectLater(
        setup.site.resolvePlayUrlsForRecoveryRaw(
          detail: room,
          quality: const LivePlayQuality(quality: '2160p · H264 · HLS', id: 'hls:2160:0:h264'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      final ended = _livePlayer()..['videoDetails'] = {...(_livePlayer()['videoDetails'] as Map), 'isLive': false};
      final gone = _setup(const [], [_player(_live, ended)]);
      await expectLater(
        gone.site.resolvePlayUrlsForRecoveryRaw(
          detail: room,
          quality: const LivePlayQuality(quality: '1080p · H264 · HLS', id: 'hls:1080:0:h264'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('recovery asks the player with the key of the last watch page', () async {
      final page = Fixture.load('youtube', 'S07-watch-live').body.replaceFirst(YouTubeApi.fallbackApiKey, 'OTHERKEY');
      final setup = _setup(
        ['S07-hls-live'],
        [_get('https://www.youtube.com/watch?v=$_live', page), _player(_live, _livePlayer(), key: 'OTHERKEY')],
      );
      final room = await setup.site.getRoomDetail(roomId: _live);
      await setup.site.resolvePlayUrlsForRecoveryRaw(
        detail: room,
        quality: const LivePlayQuality(quality: 'DASH 自动 · DASH', id: 'dash:auto'),
      );
      expect(setup.http.requests.where((request) => request.method == 'POST').map((request) => request.url.query), [
        'key=OTHERKEY',
        'key=OTHERKEY',
      ]);
    });
  });

  group('search', () {
    final legacy = _legacy('S07-watch-live')['searchRooms'] as Map<String, dynamic>;

    test("a video id or video link: 3.x's two requests and one card (refresh detail)", () async {
      for (final keyword in [
        _live,
        'https://www.youtube.com/watch?v=$_live',
        'https://youtu.be/$_live',
        'https://www.youtube.com/live/$_live',
      ]) {
        final setup = _setup();
        final rooms = await setup.site.searchRoomsWithCancellation(keyword, pageSize: 20, cancel: CancelToken());
        final expected = legacy[keyword];
        expect(_sent(setup.http.requests), _legacyRequests(expected), reason: keyword);
        final want = (_result(expected)! as List).cast<Map<String, dynamic>>();
        expect(rooms, hasLength(want.length));
        _expectRoom(rooms.single, want.single, reason: keyword);
        expect(rooms.single.data, isNull);
      }
    });

    test("a handle or channel link: the channel's /live page, then the broadcast (3.x)", () async {
      final expected = _legacy('S07-channel-live')['searchRooms'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in expected.entries) {
        final setup = _setup();
        final rooms = await setup.site.searchRooms(key);
        expect(_sent(setup.http.requests), _legacyRequests(value), reason: key);
        expect(setup.http.requests.first.url.toString(), 'https://www.youtube.com/@LofiGirl/live');
        _expectRoom(rooms.single, (_result(value)! as List).single, reason: key);
        expect(rooms.single.userId, _lofi);
      }
    });

    test('an offline channel gives nothing after its /live page (3.x)', () async {
      final expected = _legacy('S08-channel-offline')['searchRooms'];
      final setup = _setup();
      expect(await setup.site.searchRooms('https://www.youtube.com/channel/UCX6OQ3DkcsbYNE6H8uQQuVA'), isEmpty);
      expect(_sent(setup.http.requests), _legacyRequests(expected));
    });

    test('an ordinary or a missing video gives nothing (3.x failed the search for the missing one)', () async {
      final setup = _setup();
      expect(await setup.site.searchRooms(_video), isEmpty);
      expect(_result(_legacy('S12-watch-missing')['searchRooms']), isA<Map<String, dynamic>>());
      expect(await setup.site.searchRooms(_missing), isEmpty);
      final ended = await setup.site.searchRooms(_ended);
      expect(ended.single.effectiveLiveStatus, LiveStatus.offline, reason: '3.x found ended broadcasts too');
    });

    test('other pages, no page size, blank or free text give nothing without a request (3.x)', () async {
      final setup = _setup();
      for (final key in ['$_live page 2', '$_live pageSize 0', 'blank', 'lofi girl']) {
        expect(_result(legacy[key]), isEmpty, reason: key);
        expect((legacy[key] as Map<String, dynamic>)['requests'], isEmpty, reason: key);
      }
      expect(await setup.site.searchRooms(_live, page: 2), isEmpty);
      expect(await setup.site.searchRooms(_live, pageSize: 0), isEmpty);
      expect(await setup.site.searchRooms('  '), isEmpty);
      expect(await setup.site.searchRooms('lofi girl'), isEmpty);
      expect(setup.http.requests, isEmpty);
    });

    test('a cancelled search sends nothing; the token reaches the requests', () async {
      final setup = _setup();
      final cancel = CancelToken()..cancel();
      await expectLater(setup.site.searchRoomsCancellable(_live, cancel: cancel), _cancelled);
      expect(setup.http.requests, isEmpty);
      final running = CancelToken();
      await setup.site.searchRoomsCancellable(_live, cancel: running);
      expect(setup.http.requests.every((request) => identical(request.cancel, running)), isTrue);
    });

    test('other failures are not "nothing found"', () async {
      final setup = _setup(const [], [_get('https://www.youtube.com/watch?v=$_live', '', status: 429)]);
      await expectLater(setup.site.searchRooms(_live), throwsA(isA<RateLimited>()));
    });
  });

  group('catalog', () {
    test("3.x's: no categories, no recommendations, one empty directory page, without a request", () async {
      final legacy = _legacy('S07-watch-live')['catalog'] as Map<String, dynamic>;
      final setup = _setup();
      expect(await setup.site.getCategories(1, 30), isEmpty);
      expect(await setup.site.getRecommendRooms(), _result(legacy['getRecommendRooms']));
      final page = await setup.site.getDirectoryPage(page: 2);
      expect(page.rooms, isEmpty);
      expect((page.page, page.hasMore), (2, false));
      expect(() => setup.site.getDirectoryPage(page: 0), throwsRangeError);
      expect(
        () => setup.site.getDirectoryPage(
          category: const LiveArea(platform: 'youtube', areaId: 'x'),
        ),
        throwsArgumentError,
      );
      expect(setup.http.requests, isEmpty);
      expect(setup.site.directoryNoticeKey, legacy['directoryNoticeKey']);
      expect((setup.site.id, setup.site.name), (legacy['id'], legacy['name']));
      expect(setup.site.getDanmaku(), isA<EmptyDanmaku>(), reason: '3.x had no YouTube chat');
    });
  });

  group('errors', () {
    test('transport failures are NetworkFailure; a cancellation stays a cancellation', () async {
      await expectLater(
        YouTubeSite(_Failing(TransportReason.timeout)).getRoomDetail(roomId: _live),
        throwsA(isA<NetworkFailure>()),
      );
      await expectLater(YouTubeSite(_Failing(TransportReason.cancelled)).getRoomDetail(roomId: _live), _cancelled);
    });

    test("3.x's status rules on the watch page and the player", () async {
      for (final (status, matcher) in [
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (503, isA<NetworkFailure>()),
        (400, isA<ApiChanged>()),
      ]) {
        final page = _setup(const [], [_get('https://www.youtube.com/watch?v=$_live', 'x', status: status)]);
        await expectLater(page.site.getRoomDetail(roomId: _live), throwsA(matcher), reason: 'page $status');
        final player = _setup(['S07-watch-live'], [_player(_live, 'x', status: status)]);
        await expectLater(player.site.getRoomDetail(roomId: _live), throwsA(matcher), reason: 'player $status');
      }
    });
  });

  group('links', () {
    LinkParser parser(ReplayHttp http) => LinkParser(SiteRegistry({'youtube': () => YouTubeSite(http)}), http);

    test('video links name their room without a request', () async {
      final setup = _setup();
      final links = parser(setup.http);
      for (final url in [
        'https://www.youtube.com/watch?v=$_live&t=42s',
        'https://youtu.be/$_live?si=x',
        'https://m.youtube.com/live/$_live',
        'https://www.youtube-nocookie.com/embed/$_live',
      ]) {
        expect(setup.site.roomIdFromUrl(url), _live, reason: url);
        expect(await links.parse('看 $url 吧'), const RoomLink('youtube', _live), reason: url);
      }
      expect(setup.site.roomIdFromUrl('https://www.youtube.com/shorts/$_live'), isNull);
      expect(setup.site.roomIdFromUrl('https://www.youtube.com/@LofiGirl'), isNull);
      expect(setup.http.requests, isEmpty);
    });

    test("a channel link is its current broadcast: one request with 3.x's headers", () async {
      final setup = _setup();
      final links = parser(setup.http);
      const url = 'https://www.youtube.com/@LofiGirl';
      expect(setup.site.needsResolving(url), isTrue);
      expect(links.containsSupportedLink('看 $url 吧'), isTrue);
      expect(await links.parse('看 $url 吧'), const RoomLink('youtube', _live));
      final request = setup.http.requests.single;
      expect('${request.url}', 'https://www.youtube.com/@LofiGirl/live');
      expect(request.headers, YouTubeApi.pageHeaders(''));
      expect(request.followRedirects, isFalse);
    });

    test('an offline channel leads nowhere; a redirect is followed', () async {
      final setup = _setup();
      expect(await parser(setup.http).parse('https://www.youtube.com/channel/UCX6OQ3DkcsbYNE6H8uQQuVA/live'), isNull);
      final redirected = _setup(const [], [
        _get(
          'https://www.youtube.com/c/LofiGirl/live',
          '',
          status: 302,
          headers: {
            'location': ['https://www.youtube.com/watch?v=$_live'],
          },
        ),
      ]);
      expect(
        await parser(redirected.http).parse('https://www.youtube.com/c/LofiGirl'),
        const RoomLink('youtube', _live),
      );
      expect(redirected.http.requests, hasLength(1));
    });

    test('other links are not YouTube rooms', () {
      final site = _setup().site;
      for (final url in [
        'https://www.youtube.com/results?search_query=lofi',
        'https://evilyoutube.com/watch?v=$_live',
        'https://www.twitch.tv/lofigirl',
      ]) {
        expect(site.roomIdFromUrl(url), isNull, reason: url);
        expect(site.needsResolving(url), isFalse, reason: url);
      }
    });
  });

  group('follows', () {
    test('a refresh merged into an entered room keeps its sources; the identity never changes', () async {
      final setup = _setup();
      final entered = await setup.site.getRoomDetail(roomId: _live);
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: _live);
      final merged = entered.mergeFrom(refreshed);
      expect(merged.data, isA<YouTubeRoomData>());
      expect(merged.identityKey, 'youtube:$_live');
      final stored = LiveRoom.fromJson(jsonDecode(jsonEncode(entered.toJson())) as Map<String, Object?>);
      expect(stored.hasSameIdentity(refreshed), isTrue);
    });
  });
}
