// LiveMeSite over the recorded LiveMe responses (ReplayHttp) and a few
// synthetic ones: the request headers, signature and counts (compared with
// the requests 3.x sent, from expected.json), the featured list, keyword and
// exact search, room details for entry, refresh and recording, streams and
// recovery onto a new broadcast, cancellation, links through the link parser
// and the error mapping. The M4.U upgrades (21-1 to 21-8) are named where
// they change what 3.x did.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/liveme';
const _shortId = '209683072';
const _userId = '932385543319330816';
const _videoId = '17904580585651396476';
const _offlineShortId = '17709377';
const _offlineUserId = '560875115161059328';
const _first = '1111111111111111111';
const _second = '2222222222222222222';

/// Clock and signature fields whose recorded values differ per run.
const _ignored = {'_time', 'vali', 'lm_s_ts', 'lm_s_str'};

final _now = DateTime.utc(2026, 9, 27, 17, 25, 41, 900);

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
  Future<LiveStreamedResponse> open(LiveRequest request) async {
    final response = await send(request);
    return LiveStreamedResponse(
      status: response.status,
      headers: response.headers,
      body: Stream.value(response.bytes),
      url: response.url,
      contentLength: response.bytes.length,
    );
  }

  @override
  void close() {}
}

final class _Failing implements LiveHttp {
  new(this.reason);

  final TransportReason reason;

  @override
  Future<LiveResponse> send(LiveRequest request) async => throw TransportFailure('liveme', reason, 'test');

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('liveme', reason, 'test');

  @override
  void close() {}
}

LiveResponse _response(LiveRequest request, String body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);

typedef _Setup = ({LiveMeSite site, ReplayHttp http});

_Setup _setup(List<String> samples) {
  final http = ReplayHttp.fixtures(_root, samples, ignoredQuery: _ignored);
  return (site: LiveMeSite(http, now: () => _now), http: http);
}

Map<String, String> _form(LiveRequest request) => Uri.splitQueryString(utf8.decode(request.body!));

/// A request as the legacy harness wrote it: the clock value as `<time>`,
/// a POST with its `videoid`.
String _describe(LiveRequest request) {
  final url = request.url.toString().replaceFirst(RegExp('_time=[0-9]+'), '_time=<time>');
  return request.method == 'POST' ? 'POST $url videoid=${_form(request)['videoid']}' : 'GET $url';
}

List<String> _described(List<LiveRequest> requests) => [for (final request in requests) _describe(request)];

List<String> _paths(List<LiveRequest> requests) => [for (final request in requests) request.url.path];

Map<String, dynamic> _legacy(String sample) => Fixture.load('liveme', sample).legacy as Map<String, dynamic>;

/// The requests 3.x sent for [key] of [sample].
List<String> _legacyRequests(String sample, String key) =>
    ((_legacy(sample)[key] as Map<String, dynamic>)['requests'] as List).cast<String>();

final Matcher _cancelled = throwsA(
  isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled),
);

// A synthetic world: the anchor 12345678 (user 1234567890123456789), whose
// current broadcast is `current` ('' when not broadcasting).

const _worldShortId = '12345678';
const _worldUserId = '1234567890123456789';

String _envelope(Object? data) => jsonEncode({'status': '200', 'msg': '', 'data': data});

String _media(String videoId, {String extension = 'flv', String secret = 'a'}) =>
    'http://game.live11.linkv.fun/yolo/$videoId.$extension?wsSecret=$secret&wsABStime=6ab98a4a';

Map<String, Object?> _worldVideo(String videoId, Map<String, Object?> changes) => {
  'vid': videoId,
  'ushortid': _worldShortId,
  'userid': _worldUserId,
  'uname': 'Fixture',
  'title': 'Live',
  'online': '1',
  'status': '0',
  'roomstate': '0',
  'playnumber': '5',
  'heat': '9',
  'watchnumber': '12',
  'videosource': _media(videoId),
  'hlsvideosource': _media(videoId, extension: 'm3u8'),
  ...changes,
};

_Scripted _world({
  String Function()? current,
  Map<String, Object?> changes = const {},
  Map<String, Object?> profile = const {},
}) => _Scripted((request) {
  switch (request.url.path) {
    case '/liveme_ent/v1/user/uid_vid_by_short_id':
      expect(request.url.queryParameters['short_id'], _worldShortId);
      return _response(request, _envelope({'uid': _worldUserId, 'vid': current?.call() ?? _first}));
    case '/user/getinfo':
      expect(request.url.queryParameters['userid'], _worldUserId);
      return _response(
        request,
        _envelope({
          'user': {
            'user_info': {
              'uid': _worldUserId,
              'short_id': _worldShortId,
              'nickname': 'Fixture',
              'usign': 'hello',
              'big_cover': 'https://esx.esxscloud.com/cover.jpg',
              ...profile,
            },
            'count_info': {'follower_count': '12'},
          },
        }),
      );
    case '/live/queryinfosimple':
      final videoId = _form(request)['videoid']!;
      return _response(request, _envelope({'video_info': _worldVideo(videoId, changes)}));
  }
  throw StateError('unexpected ${request.url}');
});

void main() {
  group('requests', () {
    test("3.x's headers and guest parameters on every request, redirects not followed", () async {
      final setup = _setup([
        'S01-featurelist-p1',
        'S02-search-p1',
        'S03-mapping-live',
        'S04-profile-live',
        'S05-query-live',
      ]);
      await setup.site.getDirectoryPage();
      await setup.site.searchRooms('andre');
      await setup.site.getRoomDetail(roomId: _shortId);
      expect(setup.http.requests, hasLength(5));
      for (final request in setup.http.requests) {
        final roomReferer = request.url.path.startsWith('/liveme_ent') || request.url.path == '/live/queryinfosimple';
        expect(request.headers, {
          'user-agent': LiveMeApi.userAgent,
          'accept': 'application/json, text/plain, */*',
          'accept-language': 'en-US,en;q=0.9',
          'origin': 'https://www.liveme.com',
          'referer': roomReferer
              ? 'https://www.liveme.com/livehot/streaming/$_shortId'
              : 'https://www.liveme.com/livehot',
          if (request.method == 'POST') ...{
            'lm-s-sign': isA<String>(),
            'content-type': 'application/x-www-form-urlencoded',
          },
        }, reason: '${request.url}');
        expect(request.followRedirects, isFalse);
        expect(request.site, 'liveme');
        if (request.url.host == LiveMeApi.apiHost && request.method == 'GET') {
          expect(request.url.queryParameters['_time'], '${_now.millisecondsSinceEpoch}');
        }
      }
      expect((setup.site.id, setup.site.name), ('liveme', 'LiveMe'));
      expect(setup.site.directoryNoticeKey, 'liveme_directory_scope');
      expect(await setup.site.getCategories(1, 30), isEmpty, reason: 'LiveMe has no categories');
    });

    test('the broadcast POST is signed like the web client', () async {
      final setup = _setup(['S03-mapping-live', 'S04-profile-live', 'S05-query-live']);
      await setup.site.getRoomDetail(roomId: _shortId);
      final post = setup.http.requests.last;
      expect(
        (post.method, post.url.toString()),
        ('POST', 'https://live.liveme.com/live/queryinfosimple?alias=liveme&tongdun_black_box=1&os=web'),
      );
      final form = _form(post);
      expect(form.keys, [
        '_time',
        'thirdchannel',
        'videoid',
        'area',
        'vali',
        'lm_s_id',
        'lm_s_ts',
        'lm_s_str',
        'lm_s_ver',
        'h5',
      ]);
      expect((form['_time'], form['lm_s_ts']), ('${_now.millisecondsSinceEpoch}', '${_now.millisecondsSinceEpoch}0'));
      final again = LiveMeSigner.signAt(
        query: LiveMeApi.videoQuery,
        form: {
          for (final key in ['_time', 'thirdchannel', 'videoid', 'area', 'vali']) key: form[key]!,
        },
        timestamp: form['lm_s_ts']!,
      );
      expect(post.headers['lm-s-sign'], again.signature);
    });

    test('transport failures are NetworkFailure; a cancelled transport stays cancelled', () async {
      await expectLater(
        LiveMeSite(_Failing(TransportReason.connect)).getRoomDetail(roomId: _worldShortId),
        throwsA(isA<NetworkFailure>()),
      );
      await expectLater(LiveMeSite(_Failing(TransportReason.cancelled)).getDirectoryPage(), _cancelled);
      for (final (status, matcher) in [
        (503, isA<NetworkFailure>()),
        (403, isA<RiskControl>()),
        (429, isA<RateLimited>()),
        (404, isA<NotFound>()),
        (302, isA<NetworkFailure>()),
      ]) {
        final http = _Scripted((request) => _response(request, '', status: status));
        await expectLater(LiveMeSite(http).getRoomDetail(roomId: _worldShortId), throwsA(matcher), reason: '$status');
      }
    });

    test('the cancellation goes with the request, and wins before and after the answer', () async {
      final token = CancelToken();
      final setup = _setup(['S01-featurelist-p1']);
      await setup.site.getDirectoryPage(cancel: token);
      expect(identical(setup.http.requests.single.cancel, token), isTrue);
      await expectLater(setup.site.getDirectoryPage(cancel: CancelToken()..cancel()), _cancelled);
      expect(setup.http.requests, hasLength(1), reason: 'nothing sent once cancelled');
      final afterAnswer = CancelToken();
      final late = _Scripted((request) {
        afterAnswer.cancel();
        return _response(request, _envelope({'data_info': <Object?>[]}));
      });
      await expectLater(LiveMeSite(late).searchRoomsWithCancellation('andre', cancel: afterAnswer), _cancelled);
      final afterFailure = CancelToken();
      final broken = _Scripted((request) {
        afterFailure.cancel();
        throw const TransportFailure('liveme', TransportReason.connect);
      });
      await expectLater(LiveMeSite(broken).searchRoomsCancellable(_worldShortId, cancel: afterFailure), _cancelled);
      final lookup = CancelToken();
      final world = _world();
      await LiveMeSite(world).searchRoomsCancellable(_worldShortId, cancel: lookup);
      expect(world.requests.map((request) => identical(request.cancel, lookup)), everyElement(isTrue));
    });
  });

  group('featured list', () {
    test("pages of 20, next_page decides; 3.x's requests", () async {
      final setup = _setup(['S01-featurelist-p1', 'S01-featurelist-p2']);
      final first = await setup.site.getDirectoryPage();
      final second = await setup.site.getDirectoryPage(page: 2);
      expect((first.rooms.length, first.page, first.hasMore), (20, 1, true));
      expect((second.page, second.hasMore), (2, true));
      final recommended = await setup.site.getRecommendRooms(pageSize: 20);
      expect(recommended, first.rooms);
      expect(_described(setup.http.requests), [
        ..._legacyRequests('S01-featurelist-p1', 'getDirectoryPage'),
        ..._legacyRequests('S01-featurelist-p2', 'getDirectoryPage'),
        ..._legacyRequests('S01-featurelist-p1', 'getRecommendRooms'),
      ]);
    });

    test('recommendations send their page size within 1–50 (3.x)', () async {
      final http = _Scripted((request) => _response(request, _envelope({'video_info': <Object?>[], 'next_page': 0})));
      final site = LiveMeSite(http);
      for (final (size, sent) in [(30, '30'), (0, '1'), (99, '50')]) {
        await site.getRecommendRooms(page: 3, pageSize: size);
        expect(http.requests.last.url.queryParameters, {
          'countryCode': 'GLOBAL',
          'page_index': '3',
          'page_size': sent,
          'pid': '3',
          'posid': '3002',
          'h5': '1',
        });
      }
    });

    test('a category or a page below 1 is a caller error, without a request (3.x)', () async {
      final setup = _setup([]);
      await expectLater(
        setup.site.getDirectoryPage(
          category: const LiveArea(platform: 'liveme', areaId: 'x'),
        ),
        throwsArgumentError,
      );
      await expectLater(setup.site.getDirectoryPage(page: 0), throwsArgumentError);
      await expectLater(setup.site.getRecommendRooms(page: 0), throwsArgumentError);
      expect(setup.http.requests, isEmpty);
      final legacy = _legacy('S01-featurelist-p1');
      expect((legacy['getDirectoryPage(category)'] as Map)['requests'], isEmpty);
      expect((legacy['getRecommendRooms(page 0)'] as Map)['requests'], isEmpty);
      expect(await setup.site.getCategoryRooms(const LiveArea(platform: 'liveme', areaId: 'x')), isEmpty);
    });
  });

  group('search', () {
    test("keywords: one request a page, pages of 20 keep going; 3.x's requests", () async {
      final setup = _setup(['S02-search-p1', 'S02-search-p2', 'S02-search-empty']);
      final first = await setup.site.searchRooms('andre');
      final second = await setup.site.searchRooms(' andre ', page: 2);
      final none = await setup.site.searchRooms('qzxqzxqzxpurelive');
      expect((first.length, second.length, none.length), (20, 20, 0));
      expect(first.every((room) => room.data == null), isTrue);
      expect(_described(setup.http.requests), [
        ..._legacyRequests('S02-search-p1', 'searchRooms'),
        ..._legacyRequests('S02-search-p2', 'searchRooms'),
        ..._legacyRequests('S02-search-empty', 'searchRooms'),
      ]);
    });

    test('the page size is sent within 1–40; blanks and bad pages ask nothing; long keywords are refused', () async {
      final http = _Scripted((request) => _response(request, _envelope({'data_info': <Object?>[]})));
      final site = LiveMeSite(http);
      await site.searchRooms('andre', pageSize: 20);
      await site.searchRooms('andre', pageSize: 99);
      expect([for (final request in http.requests) request.url.queryParameters['pageSize']], ['20', '40']);
      expect(http.requests.first.url.queryParameters['keyword'], 'andre');
      expect(await site.searchRooms('   '), isEmpty);
      expect(await site.searchRooms('andre', page: 0), isEmpty);
      expect(await site.searchRooms('andre', pageSize: 0), isEmpty);
      await expectLater(site.searchRooms('x' * 257), throwsArgumentError);
      expect(http.requests, hasLength(2));
      await site.searchRooms('1234');
      expect(http.requests.last.url.queryParameters['keyword'], '1234', reason: 'four digits are no short id');
      await site.searchRooms('https://example.com/livehot/streaming/12345');
      expect(http.requests.last.url.path, '/search/searchKeyword', reason: '3.x searched other links as keywords');
    });

    test("a short id or room link finds its room on page 1 only; 3.x's requests", () async {
      final setup = _setup(['S03-mapping-live', 'S04-profile-live', 'S05-query-live', 'S03-mapping-notfound']);
      final byId = (await setup.site.searchRooms(_shortId)).single;
      expect((byId.roomId, byId.isLiveNow, byId.data), (_shortId, true, null));
      final byLink = await setup.site.searchRooms('https://www.liveme.com/us/livehot/streaming/$_shortId');
      expect(byLink.single.roomId, _shortId);
      expect(await setup.site.searchRooms(_shortId, page: 2), isEmpty);
      expect(await setup.site.searchRooms('999999999'), isEmpty, reason: 'an unknown room is no result');
      expect(_described(setup.http.requests), [
        ..._legacyRequests('S03-mapping-live', 'searchRooms(shortId)'),
        ..._legacyRequests('S03-mapping-live', 'searchRooms(link)'),
        ..._legacyRequests('S03-mapping-notfound', 'searchRooms(shortId)'),
      ]);
    });

    test("anchor and share links ask for the short id first; 3.x's requests", () async {
      final setup = _setup(['S03-mapping-live', 'S04-profile-live', 'S05-query-live', 'S04-profile-notfound']);
      final anchor = await setup.site.searchRooms('https://www.liveme.com/u/$_userId');
      final shared = await setup.site.searchRooms('https://www.liveme.com/us/m/v/$_videoId/index.html?live=1');
      expect((anchor.single.roomId, shared.single.roomId), (_shortId, _shortId));
      expect(
        await setup.site.searchRooms('https://www.liveme.com/u/1000000000000000001'),
        isEmpty,
        reason: '"user not exist" is no result (3.x failed the search)',
      );
      expect(_described(setup.http.requests), [
        ..._legacyRequests('S04-profile-live', 'searchRooms(link)'),
        ..._legacyRequests('S05-query-live', 'searchRooms(shareurl)'),
        ..._legacyRequests('S04-profile-notfound', 'searchRooms(link)'),
      ]);
      expect((_legacy('S04-profile-notfound')['searchRooms(link)'] as Map)['value'], {
        'throws': 'LiveMeException',
        'message': 'LiveMe service',
      });
    });

    test('other failures of a lookup are errors (3.x)', () async {
      final broken = _Scripted((request) => _response(request, jsonEncode({'status': '200', 'data': null})));
      await expectLater(LiveMeSite(broken).searchRooms(_worldShortId), throwsA(isA<ApiChanged>()));
    });
  });

  group('rooms', () {
    test("entry, refresh, recording and live status: 3.x's three requests", () async {
      final setup = _setup(['S03-mapping-live', 'S04-profile-live', 'S05-query-live']);
      final entered = await setup.site.getRoomDetail(roomId: ' $_shortId ');
      expect(_described(setup.http.requests), _legacyRequests('S03-mapping-live', 'getRoomDetail'));
      expect((entered.roomId, entered.userId, entered.isLiveNow), (_shortId, _userId, true));
      final data = entered.data! as LiveMeRoomData;
      expect(
        (data.videoId, data.state, data.streams.length, data.restriction),
        (_videoId, LiveMeState.live, 2, LiveRestriction.none),
      );
      expect((entered.startedAt, entered.restriction), (DateTime.utc(2026, 9, 26, 21, 31, 2), LiveRestriction.none));
      expect(entered.danmakuData, isNull, reason: '3.x had no LiveMe danmaku; the chat room is data.videoId (M5)');
      for (final (key, call) in [
        ('getRoomDetailForRefresh', () => setup.site.getRoomDetailForRefresh(roomId: _shortId)),
        ('getRoomDetailForRecording', () => setup.site.getRoomDetailForRecording(roomId: _shortId)),
        ('getLiveStatus', () => setup.site.getLiveStatus(roomId: _shortId)),
      ]) {
        setup.http.requests.clear();
        final result = await call();
        expect(_described(setup.http.requests), _legacyRequests('S03-mapping-live', key), reason: key);
        if (result is LiveRoom) {
          expect(result.data == null, key == 'getRoomDetailForRefresh', reason: key);
          expect((result.startedAt, result.restriction), (entered.startedAt, LiveRestriction.none), reason: key);
        } else {
          expect(result, isTrue);
        }
      }
    });

    test("not broadcasting: the mapping and the profile, offline, no stream (3.x's requests)", () async {
      final setup = _setup(['S03-mapping-offline', 'S04-profile-offline']);
      final room = await setup.site.getRoomDetail(roomId: _offlineShortId);
      expect((room.roomId, room.effectiveLiveStatus), (_offlineShortId, LiveStatus.offline));
      expect(await setup.site.getLiveStatus(roomId: _offlineShortId), isFalse);
      expect(_described(setup.http.requests), [
        ..._legacyRequests('S03-mapping-offline', 'getRoomDetail'),
        ..._legacyRequests('S03-mapping-offline', 'getLiveStatus'),
      ]);
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      expect(setup.http.requests, hasLength(4), reason: 'the stream needs no further request');
      expect((room.data! as LiveMeRoomData).userId, _offlineUserId);
      expect(_legacy('S03-mapping-offline')['getPlayQualites'], isEmpty, reason: '3.x gave no qualities');
    });

    test('an unknown short id is NotFound; an id that is no short id asks nothing', () async {
      final setup = _setup(['S03-mapping-notfound']);
      await expectLater(setup.site.getRoomDetail(roomId: '999999999'), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getRoomDetailForRefresh(roomId: '999999999'), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getLiveStatus(roomId: '999999999'), throwsA(isA<NotFound>()));
      for (final id in ['0123456', '1234', 'abc', '', '1234567890123', _userId]) {
        await expectLater(setup.site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(setup.http.requests, hasLength(3));
    });

    test('answers of another room or anchor are ApiChanged (3.x: identity)', () async {
      for (final (changes, profile) in [
        (<String, Object?>{'ushortid': '87654321'}, <String, Object?>{}),
        (<String, Object?>{'userid': '9234567890123456789'}, <String, Object?>{}),
        (<String, Object?>{}, <String, Object?>{'short_id': '87654321'}),
        (<String, Object?>{}, <String, Object?>{'uid': '9234567890123456789'}),
      ]) {
        final site = LiveMeSite(_world(changes: changes, profile: profile));
        await expectLater(
          site.getRoomDetail(roomId: _worldShortId),
          throwsA(isA<ApiChanged>()),
          reason: '$changes $profile',
        );
      }
      final offline = LiveMeSite(_world(current: () => '', profile: {'short_id': '87654321'}));
      await expectLater(offline.getRoomDetailForRefresh(roomId: _worldShortId), throwsA(isA<ApiChanged>()));
    });

    test("a follow keeps its identity and merges; 3.x's stored follow reads back", () async {
      var current = _first;
      final site = LiveMeSite(_world(current: () => current));
      final entered = await site.getRoomDetail(roomId: _worldShortId);
      expect(jsonEncode(entered.toJson()), allOf(isNot(contains(_first)), isNot(contains('wsSecret'))));
      final legacy = _legacy('S03-mapping-live')['getRoomDetail'] as Map<String, dynamic>;
      final stored = LiveRoom.fromJson({
        ...legacy['value'] as Map<String, dynamic>,
        'tagIds': const ['kept'],
      });
      final live = await _setup(['S03-mapping-live', 'S04-profile-live', 'S05-query-live']).site
          .getRoomDetailForRefresh(roomId: stored.roomId);
      expect(live.hasSameIdentity(stored), isTrue);
      final merged = stored.mergeFrom(live);
      expect((merged.roomId, merged.area, merged.isLiveNow, merged.followers), (_shortId, 'US', true, '33933'));
      expect(merged.tagIds, ['kept']);
      expect(merged.httpHeaders, stored.httpHeaders, reason: "3.x's stored media headers are kept, not needed");
      current = '';
      final ended = await site.getRoomDetailForRefresh(roomId: _worldShortId);
      final after = entered.mergeFrom(ended);
      expect((after.effectiveLiveStatus, after.title, after.introduction), (LiveStatus.offline, 'Fixture', 'hello'));
    });

    test('21-5: a follow 3.x stored as banned reads back live and paid; the start and mark go when it ends', () async {
      var current = _first;
      final site = LiveMeSite(
        _world(current: () => current, changes: {'livebptype': '7', 'vtime': '1790458262', 'title': 'Click for fun!'}),
      );
      final stored = LiveRoom.fromJson({
        'roomId': _worldShortId,
        'platform': 'liveme',
        'title': 'Old title',
        'nick': 'Fixture',
        'liveStatus': LiveStatus.banned.index,
        'status': false,
        'isRecord': false,
        'tagIds': const ['kept'],
      });
      final live = stored.mergeFrom(await site.getRoomDetailForRefresh(roomId: _worldShortId));
      expect(
        (live.effectiveLiveStatus, live.restriction, live.startedAt, live.followGroup),
        (LiveStatus.live, LiveRestriction.paid, DateTime.utc(2026, 9, 26, 21, 31, 2), FollowGroup.live),
      );
      expect(live.title, 'Fixture', reason: "the app's default title names the room by the anchor");
      expect(live.tagIds, ['kept']);
      current = '';
      final ended = live.mergeFrom(await site.getRoomDetailForRefresh(roomId: _worldShortId));
      expect((ended.effectiveLiveStatus, ended.restriction, ended.startedAt), (LiveStatus.offline, null, null));
    });

    test('a state the answer does not give stays unknown; the live status is then an error (3.x)', () async {
      final site = LiveMeSite(_world(changes: {'online': null, 'status': null, 'roomstate': null}));
      expect((await site.getRoomDetailForRefresh(roomId: _worldShortId)).isLiveStatusPending, isTrue);
      await expectLater(site.getLiveStatus(roomId: _worldShortId), throwsA(isA<ApiChanged>()));
    });

    test('private, paid, ended or media-less broadcasts open; their stream says why (21-5; 3.x: banned)', () async {
      for (final (changes, status, restriction) in [
        (<String, Object?>{'ispvt': '1'}, LiveStatus.live, LiveRestriction.private),
        (<String, Object?>{'livebptype': '7'}, LiveStatus.live, LiveRestriction.paid),
        (<String, Object?>{'hot_label_v2': '{"text":"Paid broadcast"}'}, LiveStatus.live, LiveRestriction.paid),
        (<String, Object?>{'online': '0'}, LiveStatus.offline, null),
        (
          <String, Object?>{'videosource': 'ftp://example.com/1.flv', 'hlsvideosource': ''},
          LiveStatus.live,
          LiveRestriction.none,
        ),
      ]) {
        final http = _world(changes: changes);
        final site = LiveMeSite(http);
        for (final entered in [
          await site.getRoomDetail(roomId: _worldShortId),
          await site.getRoomDetailForRecording(roomId: _worldShortId),
        ]) {
          expect((entered.effectiveLiveStatus, entered.restriction), (status, restriction), reason: '$changes');
          final named = restriction == LiveRestriction.private || restriction == LiveRestriction.paid;
          await expectLater(
            site.getPlayQualities(detail: entered),
            throwsA(
              isA<StreamUnavailable>().having(
                (error) => error.detail,
                'detail',
                named ? contains('(${restriction!.name})') : isNot(contains('restricted')),
              ),
            ),
            reason: '$changes',
          );
        }
        expect(await site.getLiveStatus(roomId: _worldShortId), status == LiveStatus.live, reason: '$changes');
        expect(http.requests, hasLength(9), reason: 'the stream needs no further request');
      }
    });
  });

  group('streams', () {
    test("21-7: 原画 and 流畅 from room entry, no request; 3.x's URLs as lines with headers, no lease", () async {
      final setup = _setup(['S03-mapping-live', 'S04-profile-live', 'S05-query-live']);
      final room = await setup.site.getRoomDetail(roomId: _shortId);
      final qualities = await setup.site.getPlayQualities(detail: room);
      expect([for (final quality in qualities) (quality.quality, quality.id)], [('原画', 'source'), ('流畅', 'smooth')]);
      final legacy = {
        for (final quality in (_legacy('S03-mapping-live')['getPlayQualites'] as List).cast<Map<String, dynamic>>())
          quality['id'] as String: quality['getPlayUrls'] as List,
      };
      final expected = {
        'source': [...legacy['source-flv']!, ...legacy['hls']!],
        'smooth': legacy['smooth-flv'],
      };
      for (final quality in qualities) {
        final resolution = await setup.site.resolvePlayUrls(detail: room, quality: quality);
        expect(resolution.urls, expected[quality.id]);
        expect(resolution.appliedQualityData, quality.id);
        for (final line in resolution.lines) {
          expect(line.headers, LiveMeApi.mediaHeaders(_shortId));
          expect(line.lease, isNull, reason: '21-8');
        }
        expect(await setup.site.getPlayUrls(detail: room, quality: quality), resolution.urls);
      }
      for (final old in legacy.keys) {
        final resolution = await setup.site.resolvePlayUrls(
          detail: room,
          quality: LivePlayQuality(quality: 'x', id: old),
        );
        expect(resolution.urls, contains(legacy[old]!.single), reason: "3.x's $old still plays");
      }
      expect(setup.http.requests, hasLength(3));
    });

    test('a list card asks for its broadcast (mapping and broadcast); a room called offline asks nothing', () async {
      final setup = _setup(['S01-featurelist-p1', 'S03-mapping-live', 'S05-query-live']);
      final card = (await setup.site.getDirectoryPage()).rooms.first;
      expect(card.roomId, _shortId);
      expect(await setup.site.getPlayQualities(detail: card), hasLength(2));
      expect(_paths(setup.http.requests), [
        '/live/featurelist',
        '/liveme_ent/v1/user/uid_vid_by_short_id',
        '/live/queryinfosimple',
      ]);
      for (final status in [LiveStatus.offline, LiveStatus.banned]) {
        final room = LiveRoom(roomId: _shortId, platform: 'liveme', liveStatus: status);
        await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      }
      for (final kind in [LiveRestriction.private, LiveRestriction.paid]) {
        await expectLater(
          setup.site.getPlayQualities(detail: card.copyWith(restriction: kind)),
          throwsA(isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains('(${kind.name})'))),
          reason: 'a card marked restricted says why without a request',
        );
      }
      expect(setup.http.requests, hasLength(3));
    });

    test('recovery asks for the current broadcast again: a new one, new URLs, same quality ids', () async {
      var current = _first;
      final http = _world(current: () => current);
      final site = LiveMeSite(http);
      final room = await site.getRoomDetail(roomId: _worldShortId);
      final quality = (await site.getPlayQualities(detail: room)).single;
      expect(quality.selectionId, 'source');
      expect(await site.getPlayUrls(detail: room, quality: quality), [
        'https://game.live11.linkv.fun/yolo/$_first.flv?wsSecret=a&wsABStime=6ab98a4a',
        'https://game.live11.linkv.fun/yolo/$_first.m3u8?wsSecret=a&wsABStime=6ab98a4a',
      ]);
      current = _second;
      final recovered = await site.resolvePlayUrlsForRecovery(detail: room, quality: quality);
      expect(recovered.urls, [
        'https://game.live11.linkv.fun/yolo/$_second.flv?wsSecret=a&wsABStime=6ab98a4a',
        'https://game.live11.linkv.fun/yolo/$_second.m3u8?wsSecret=a&wsABStime=6ab98a4a',
      ]);
      expect(recovered.appliedQualityData, 'source');
      expect(_paths(http.requests.sublist(3)), ['/liveme_ent/v1/user/uid_vid_by_short_id', '/live/queryinfosimple']);
      current = '';
      await expectLater(
        site.resolvePlayUrlsForRecovery(detail: room, quality: quality),
        throwsA(isA<StreamUnavailable>()),
      );
      final smooth = LiveMeSite(_world(current: () => _second));
      await expectLater(
        smooth.resolvePlayUrlsForRecovery(
          detail: room,
          quality: const LivePlayQuality(quality: 'x', id: 'smooth-flv'),
        ),
        throwsA(isA<StreamUnavailable>()),
        reason: 'the new broadcast has no 360p stream',
      );
    });

    test("recovery of 3.x's source-flv plays 原画, its URL first (21-7)", () async {
      final setup = _setup(['S03-mapping-live', 'S04-profile-live', 'S05-query-live']);
      final room = await setup.site.getRoomDetail(roomId: _shortId);
      setup.http.requests.clear();
      const quality = LivePlayQuality(quality: '原始画质 · FLV', id: 'source-flv', sort: 300);
      final recovered = await setup.site.resolvePlayUrlsForRecovery(detail: room, quality: quality);
      final legacy = _legacy('S03-mapping-live')['resolvePlayUrlsForRecoveryRaw(source-flv)'] as Map<String, dynamic>;
      final value = legacy['value'] as Map<String, dynamic>;
      expect(recovered.urls.first, (value['urls'] as List).single);
      expect(recovered.lines.map((line) => line.lineId), ['flv', 'hls']);
      expect((value['appliedQualityData'], recovered.appliedQualityData), ('source-flv', 'source'));
      expect(_described(setup.http.requests), [
        (legacy['requests'] as List).first,
        (legacy['requests'] as List).last,
      ], reason: '3.x also asked for the profile, which adds nothing to a stream');
    });
  });

  group('links', () {
    test('room pages are rooms without a request; anchor and share pages need one', () {
      final site = LiveMeSite(ReplayHttp(const []));
      for (final url in [
        'https://www.liveme.com/livehot/streaming/$_shortId',
        'https://liveme.com/us/livehot/streaming/$_shortId?from=share',
      ]) {
        expect((site.roomIdFromUrl(url), site.needsResolving(url)), (_shortId, false), reason: url);
      }
      for (final url in [
        'https://www.liveme.com/u/$_userId',
        'https://www.liveme.com/v/$_videoId',
        'https://www.liveme.com/us/m/v/$_videoId/index.html?live=1',
      ]) {
        expect((site.roomIdFromUrl(url), site.needsResolving(url)), (null, true), reason: url);
      }
      for (final url in [
        'https://m.liveme.com/livehot/streaming/1234567',
        'https://www.liveme.com/%FF/u/1',
        '12345678',
      ]) {
        expect((site.roomIdFromUrl(url), site.needsResolving(url)), (null, false), reason: url);
      }
    });

    test("anchor and share links through the link parser: one request each, as 3.x's import", () async {
      final http = ReplayHttp.fixtures(_root, ['S04-profile-live', 'S05-query-live'], ignoredQuery: _ignored);
      final parser = LinkParser(SiteRegistry({'liveme': () => LiveMeSite(http, now: () => _now)}), http);
      expect(await parser.parse('看 https://www.liveme.com/u/$_userId 吧'), const RoomLink('liveme', _shortId));
      const shareUrl = 'https://www.liveme.com/us/m/v/$_videoId/index.html?live=1';
      expect(await parser.parse('Watch $shareUrl'), const RoomLink('liveme', _shortId));
      expect(await parser.parse('https://www.liveme.com/v/$_videoId'), const RoomLink('liveme', _shortId));
      expect(_described(http.requests), [
        ..._legacyRequests('S04-profile-live', 'shareImport'),
        ..._legacyRequests('S05-query-live', 'shareImport(shareurl)'),
        ..._legacyRequests('S05-query-live', 'shareImport(/v/)'),
      ]);
      for (final request in http.requests) {
        expect((request.site, request.followRedirects), ('links', false));
        expect(request.headers['referer'], 'https://www.liveme.com/livehot');
      }
      expect(http.requests[1].headers['lm-s-sign'], isNotEmpty);
      expect(
        await parser.parse('https://www.liveme.com/livehot/streaming/$_shortId'),
        const RoomLink('liveme', _shortId),
      );
      expect(http.requests, hasLength(3), reason: 'a room page needs no request');
      expect(parser.containsSupportedLink('看 $shareUrl'), isTrue);
    });

    test('a link whose anchor cannot be found is no room (3.x reported a failure)', () async {
      final notFound = ReplayHttp.fixtures(_root, ['S04-profile-notfound'], ignoredQuery: _ignored);
      final parser = LinkParser(SiteRegistry({'liveme': () => LiveMeSite(notFound)}), notFound);
      expect(await parser.parse('https://www.liveme.com/u/1000000000000000001'), isNull);
      expect(notFound.requests, hasLength(1));
      for (final (body, status) in [
        ('', 503),
        (_envelope({'video_info': _worldVideo(_second, {})}), 200),
      ]) {
        final http = _Scripted((request) => _response(request, body, status: status));
        final parser = LinkParser(SiteRegistry({'liveme': () => LiveMeSite(http)}), http);
        expect(await parser.parse('https://www.liveme.com/v/$_first'), isNull, reason: '$status');
        expect(http.requests.single.method, 'POST');
      }
    });
  });
}
