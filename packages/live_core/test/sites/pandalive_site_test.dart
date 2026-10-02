// PandaLiveSite over the recorded PandaTV responses (ReplayHttp) and a few
// synthetic ones: the requests (URL, form, headers, redirects, order) and
// their counts, compared with the requests 3.x made (expected.json), the
// catalog and the directories, the two-source search with its exact and
// link lookups, room details for entry, refresh and recording, the refusals
// of live/play, streams with their lines and recovery, the chat arguments,
// cancellation, links through the link parser and the error mapping. Ports
// the orchestration parts of 3.x's pandalive_site_test.dart and
// pandalive_native_search_test.dart. The M4.U upgrades are named by their
// item of docs/specs/UPGRADES.md; the room fields they change are checked value
// by value in pandalive_api_test.dart.
import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/pandalive';

/// Every sample of the live broadcaster's room entry.
const _liveSamples = ['S04-member-live', 'S05-play-live', 'S06-master'];

/// Answers every request with [answer].
final class _Scripted implements LiveHttp {
  new(this.answer);

  final FutureOr<LiveResponse> Function(LiveRequest request) answer;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    return await answer(request);
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

LiveResponse _response(LiveRequest request, String body, {int status = 200}) =>
    LiveResponse(status: status, bytes: utf8.encode(body), url: request.url);

typedef _Setup = ({PandaLiveSite site, ReplayHttp http});

/// A site over [samples] (and [extra]). The samples' IVS tokens are
/// scrubbed, so they are left out of matching; everything else, the
/// `member/bj` form included (25-9: the samples were recorded with
/// `info=media`, which 3.x did not send), must match.
_Setup _setup(List<String> samples, {List<ReplaySample> extra = const []}) {
  final http = ReplayHttp(
    [...extra, for (final sample in samples) ReplaySample.load('$_root/$sample')],
    ignoredQuery: const {'token'},
  );
  return (site: PandaLiveSite(http, now: () => _issuedAt), http: http);
}

final DateTime _issuedAt = Fixture.load('pandalive', 'S06-master').capturedAt;

Map<String, dynamic> _legacy(String sample) => Fixture.load('pandalive', sample).legacy as Map<String, dynamic>;

Map<String, dynamic> _outcome(String sample, String key) => _legacy(sample)[key] as Map<String, dynamic>;

Object? _legacyValue(String sample, String key) => _outcome(sample, key)['value'];

List<Map<String, dynamic>> _legacyRequests(Map<String, dynamic> outcome) =>
    (outcome['requests'] as List).cast<Map<String, dynamic>>();

/// A request as the legacy harness recorded it: the IVS token left out.
Map<String, Object?> _described(LiveRequest request) {
  final url = request.url;
  final query = {...url.queryParameters}..remove('token');
  final base = '${url.scheme}://${url.host}${url.path}';
  return {
    'method': request.method,
    'url': query.isEmpty ? base : '$base?${Uri(queryParameters: query).query}',
    if (request.method == 'POST') 'form': Uri.splitQueryString(utf8.decode(request.body!)),
    'referer': request.headers['referer'],
  };
}

/// A request 3.x made, as the upgrades send it: the room's page is the
/// website's `/play/<id>` (25-4; 3.x's `/live/play/<id>`), and `member/bj`
/// asks for the broadcast alone (25-9; 3.x: `info=media fanGrade`).
Map<String, Object?> _upgraded(Map<String, dynamic> request) => {
  ...request,
  'referer': (request['referer'] as String?)?.replaceFirst('/live/play/', '/play/'),
  if (request['url'] == 'https://api.pandalive.co.kr/v1/member/bj')
    'form': {...(request['form'] as Map), 'info': 'media'},
};

/// Asserts that [requests] are the ones 3.x made for [outcome] (as
/// [_upgraded]), in order, with the fields in 3.x's order.
void _expectLegacyRequests(List<LiveRequest> requests, Map<String, dynamic> outcome) {
  final legacy = _legacyRequests(outcome);
  expect(requests.map(_described), legacy.map(_upgraded));
  for (final (index, request) in requests.indexed) {
    if (request.method != 'POST') continue;
    final sent = utf8.decode(request.body!).split('&').map((field) => field.split('=').first);
    expect(sent, (legacy[index]['form'] as Map).keys, reason: 'field order');
  }
}

/// Room keys the upgrades change (value by value in pandalive_api_test):
/// `httpHeaders` (M4.25), `link` (25-4), `notice` (25-7), `area` (25-8) and
/// the cards' `userId` (25-10).
const _changed = {'httpHeaders', 'link', 'notice', 'area', 'userId'};

void _expectParity(Map<String, Object?> actual, Map<String, dynamic> legacy, {String? reason}) {
  for (final MapEntry(:key, :value) in legacy.entries) {
    if (_changed.contains(key)) continue;
    expect(actual[key] ?? '', value ?? '', reason: '${reason ?? ''} $key');
  }
}

Map<String, Object?> _projection(LiveRoom room) => {...room.toJson(), 'link': room.link};

List<String> _paths(List<LiveRequest> requests) => [for (final request in requests) request.url.path];

final Matcher _cancelled = throwsA(
  isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled),
);

Map<String, Object?> _media({String id = 'fixture_101', int index = 101, Map<String, Object?> changes = const {}}) => {
  'title': 'Fixture live',
  'userId': id,
  'userIdx': index,
  'userNick': 'Fixture owner',
  'category': 'talk',
  'isAdult': false,
  'isPw': false,
  'user': 127,
  'isLive': true,
  'fanCnt': 9371,
  'thumbUrl': 'https://cdn.pandalive.co.kr/cover.jpg',
  'userImg': 'https://cdn.pandalive.co.kr/avatar.jpg',
  ...changes,
};

String _memberAnswer({String id = 'fixture_101', int index = 101, Object? media}) => jsonEncode({
  'media': ?media,
  'bjInfo': {
    'idx': index,
    'id': id,
    'nick': 'Fixture owner',
    'thumbUrl': 'https://cdn.pandalive.co.kr/avatar.jpg',
    'channelTitle': 'Fixture channel',
    'channelDesc': 'Fixture introduction',
    'channelBannerUrl': 'https://cdn.pandalive.co.kr/banner.jpg',
    'fanCnt': 9371,
  },
  'result': true,
  'message': '',
});

const _master = 'https://fixture.us-west-2.playback.live-video.net/api/video/v1/fixture.m3u8?token=fixture';

String _playAnswer({Object? media}) => jsonEncode({
  'media': media ?? _media(),
  'PlayList': {
    'hls3': [
      {'name': '자동', 'sort': 1, 'url': _master},
    ],
  },
  'channel': 101,
  'token': 'chat-token',
  'result': true,
  'message': '시청이 시작되었습니다.',
});

String _refusal(String code) => jsonEncode({
  'result': false,
  'message': 'refused',
  'errorData': {'code': code},
});

String _masterText(List<String> heights) => [
  '#EXTM3U',
  for (final height in heights) ...[
    '#EXT-X-STREAM-INF:BANDWIDTH=1000,RESOLUTION=1280x$height,CODECS="avc1.4D401F,mp4a.40.2",FRAME-RATE=30.000',
    'https://fixture.playlist.live-video.net/$height.m3u8',
  ],
].join('\n');

/// A paged answer echoing the request's offset and limit.
String _pageFor(LiveRequest request, List<Object?> rows, {int? total}) {
  final form = Uri.splitQueryString(utf8.decode(request.body!));
  final offset = int.parse(form['offset']!);
  final limit = int.parse(form['limit']!);
  return jsonEncode({
    'list': rows,
    'page': {'offset': offset, 'limit': limit, 'total': total ?? offset + rows.length, 'page': offset ~/ limit + 1},
    'result': true,
    'message': '',
  });
}

/// A PandaTV where fixture_101 is live: [member], [play] and [master]
/// answer their requests, and the searches answer [search].
_Scripted _world({
  FutureOr<LiveResponse> Function(LiveRequest request)? member,
  FutureOr<LiveResponse> Function(LiveRequest request)? play,
  FutureOr<LiveResponse> Function(LiveRequest request)? master,
  FutureOr<LiveResponse> Function(LiveRequest request)? search,
}) => _Scripted((request) {
  switch (request.url.path) {
    case '/v1/member/bj':
      return member?.call(request) ?? _response(request, _memberAnswer(media: _media()));
    case '/v1/live/play':
      return play?.call(request) ?? _response(request, _playAnswer());
    case '/v1/live/index' || '/v1/live/bj_list':
      return search?.call(request) ?? _response(request, _pageFor(request, const []));
    default:
      return master?.call(request) ?? _response(request, _masterText(['1080', '720']));
  }
});

/// `S04-member-live` as the `member/bj` answer of broadcaster [userId]
/// number [index] (the legacy harness's answer for the refused `live/play`
/// samples).
ReplaySample _syntheticMember(String userId, int index, {required bool adult}) {
  final member = jsonDecode(Fixture.load('pandalive', 'S04-member-live').body) as Map<String, dynamic>;
  (member['media'] as Map<String, dynamic>)
    ..['userId'] = userId
    ..['userIdx'] = index
    ..['isAdult'] = adult;
  (member['bjInfo'] as Map<String, dynamic>)
    ..['id'] = userId
    ..['idx'] = index;
  return ReplaySample(
    method: 'POST',
    url: Uri.https(PandaLiveApi.apiHost, '/v1/member/bj'),
    status: 200,
    bytes: utf8.encode(jsonEncode(member)),
    form: {'userId': userId, 'info': 'media'},
  );
}

void main() {
  group('site', () {
    test("3.x's name, notice, capabilities; the catalog without a request", () async {
      final setup = _setup(const []);
      final site = setup.site;
      expect(site.id, 'pandalive');
      expect(site.name, 'PandaTV');
      expect(site.directoryNoticeKey, _legacy('S01-index-hot')['directoryNoticeKey']);
      expect(site, isA<LiveSiteDirectoryPager>());
      expect(site, isA<LiveDirectoryNotice>());
      expect(site, isA<LiveCancellableSearch>());
      expect(site, isA<LiveSiteRoomRefresher>());
      expect(site, isA<LiveSiteRecordRoomResolver>());
      expect(site, isA<LivePlayUrlResolver>());
      expect(site, isA<LivePlayRecoveryResolver>());
      expect(site, isA<LiveSiteLinks>());
      expect(site, isNot(isA<LiveSiteCursorDirectoryPager>()));
      expect(site.getDanmaku(), isA<EmptyDanmaku>(), reason: 'the chat connection is M5 (25-2)');
      final categories = await site.getCategories(1, 30);
      expect(categories.single.children.map((area) => area.areaId), ['public', 'newbj'], reason: '25-1');
      expect(await site.getCategories(2, 30), isEmpty);
      expect(setup.http.requests, isEmpty);
    });
  });

  group('directory', () {
    test("page 1: one form POST as 3.x's (fields, headers, no redirects); the same rooms", () async {
      final setup = _setup(['S01-index-hot']);
      final page = await setup.site.getDirectoryPage();
      final request = setup.http.requests.single;
      _expectLegacyRequests(setup.http.requests, _outcome('S01-index-hot', 'getDirectoryPage(1)'));
      expect(request.method, 'POST');
      expect(request.followRedirects, isFalse);
      expect(request.site, 'pandalive');
      expect(request.headers, {
        'user-agent': PandaLiveApi.userAgent,
        'accept': 'application/json, text/plain, */*',
        'accept-language': 'ko-KR,ko;q=0.9,en;q=0.8',
        'origin': 'https://www.pandalive.co.kr',
        'referer': 'https://www.pandalive.co.kr/live',
        'content-type': 'application/x-www-form-urlencoded',
      });
      final legacy = _legacyValue('S01-index-hot', 'getDirectoryPage(1)')! as Map<String, dynamic>;
      expect(page.rooms.map((room) => room.roomId), (legacy['rooms'] as List).map((room) => (room as Map)['roomId']));
      expect(page.hasMore, legacy['hasMore']);
      expect(page.nextCursor, isNull);
    });

    test('page 5 asks offset 120 and is the last', () async {
      final setup = _setup(['S01-index-hot-last']);
      final page = await setup.site.getDirectoryPage(page: 5);
      _expectLegacyRequests(setup.http.requests, _outcome('S01-index-hot-last', 'getDirectoryPage(5)'));
      expect(page.rooms, hasLength(8));
      expect(page.hasMore, isFalse);
    });

    test('the new broadcasters (25-1): the recorded request (onlyNewBj=Y), one POST, 7 rooms', () async {
      final setup = _setup(['S02-index-newbj']);
      final area = (await setup.site.getCategories(1, 30)).single.children.last;
      expect(area.areaName, '新人主播');
      final page = await setup.site.getDirectoryPage(category: area);
      final request = setup.http.requests.single;
      expect(request.url, Uri.parse('https://api.pandalive.co.kr/v1/live/index'));
      expect(utf8.decode(request.body!), 'offset=0&limit=30&orderBy=hot&onlyNewBj=Y');
      expect(request.headers['referer'], 'https://www.pandalive.co.kr/live');
      expect(page.rooms, hasLength(7));
      expect(page.hasMore, isFalse);
      expect(await setup.site.getCategoryRooms(area), hasLength(7));
      expect(setup.http.requests, hasLength(2));
    });

    test('recommendations and the public area are the directory; the page size is not sent (3.x)', () async {
      final setup = _setup(['S01-index-hot']);
      final area = (await setup.site.getCategories(1, 30)).single.children.first;
      final recommended = await setup.site.getRecommendRooms(pageSize: 10);
      final rooms = await setup.site.getCategoryRooms(area, pageSize: 50);
      expect(recommended, hasLength(30));
      expect(rooms.map((room) => room.roomId), recommended.map((room) => room.roomId));
      expect(setup.http.requests, hasLength(2));
    });

    test('caller errors before any request: page 0 or over 1000, another area (3.x: schema, identity)', () async {
      final setup = _setup(const []);
      await expectLater(setup.site.getDirectoryPage(page: 0), throwsRangeError);
      await expectLater(setup.site.getDirectoryPage(page: 1001), throwsRangeError);
      await expectLater(
        setup.site.getDirectoryPage(
          category: const LiveArea(platform: 'pandalive', areaType: 'directory', areaId: 'hot'),
        ),
        throwsArgumentError,
      );
      expect(setup.http.requests, isEmpty);
    });
  });

  group('search', () {
    test('a keyword (40 a page): the BJ search, then the LIVE search, as 3.x; the same rooms', () async {
      final setup = _setup(['S03-search-bj', 'S03-search-live']);
      final rooms = await setup.site.searchRooms('데이지', pageSize: 40);
      final outcome = _outcome('S03-search-live', 'searchRooms');
      _expectLegacyRequests(setup.http.requests, outcome);
      final legacy = (outcome['value'] as List).cast<Map<String, dynamic>>();
      expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
      expect(rooms.map((room) => room.roomId), ['daisy00', 'chirch', 'flffl369', 'hhd006', 'candygirl35']);
      for (final (index, room) in rooms.indexed) {
        _expectParity(_projection(room), legacy[index], reason: '[$index]');
      }
      expect(rooms.first.userId, '24133575', reason: '25-10: the live card has the number too (3.x: the id)');
      expect(rooms.first.totalViewers, '903', reason: '25-3');
    });

    test("page sizes as 3.x split them; each source's own offset; one request at a time", () async {
      final forms = <String>[];
      var inFlight = 0;
      var most = 0;
      final http = _world(
        search: (request) async {
          inFlight++;
          most = inFlight > most ? inFlight : most;
          await Future<void>.delayed(const Duration(milliseconds: 2));
          inFlight--;
          final form = Uri.splitQueryString(utf8.decode(request.body!));
          forms.add('${request.url.path}:${form['offset']}:${form['limit']}');
          return _response(request, _pageFor(request, const []));
        },
      );
      final site = PandaLiveSite(http);
      for (final (page, size) in [(1, 30), (2, 4), (1, 1), (1, 2), (3, 150)]) {
        await site.searchRooms('가온', page: page, pageSize: size);
      }
      expect(forms, [
        '/v1/live/bj_list:0:15',
        '/v1/live/index:0:15',
        '/v1/live/bj_list:2:2',
        '/v1/live/index:2:2',
        '/v1/live/bj_list:0:1',
        '/v1/live/bj_list:0:1',
        '/v1/live/index:0:1',
        '/v1/live/bj_list:100:50',
        '/v1/live/index:100:50',
      ]);
      expect(most, 1);
    });

    test("3.x's merge: live cards first, a broadcaster once, offline broadcasters after", () async {
      final http = _world(
        search: (request) => _response(
          request,
          _pageFor(
            request,
            request.url.path == '/v1/live/index'
                ? [_media(id: 'gaoninc')]
                : [
                    {'userId': 'GaonInc', 'userIdx': 101, 'userNick': '가온', 'media': _media(id: 'gaoninc')},
                    {'userId': 'see994', 'userIdx': 202, 'userNick': '가온主播'},
                  ],
          ),
        ),
      );
      final rooms = await PandaLiveSite(http).searchRooms('가온', pageSize: 4);
      expect(rooms.map((room) => room.roomId), ['gaoninc', 'see994']);
      expect(rooms.first.isLiveNow, isTrue);
      expect(rooms.last.liveStatus, LiveStatus.offline);
      expect(rooms.last.onlineViewers, '');
    });

    test('one source failing leaves the other; both failing, or nothing and a failure, is the failure', () async {
      final bjDown = _world(
        search: (request) => request.url.path == '/v1/live/bj_list'
            ? _response(request, '', status: 502)
            : _response(request, _pageFor(request, [_media()])),
      );
      expect((await PandaLiveSite(bjDown).searchRooms('가온')).single.roomId, 'fixture_101');
      final liveDown = _world(
        search: (request) => request.url.path == '/v1/live/index'
            ? _response(request, '<html>')
            : _response(
                request,
                _pageFor(request, [
                  {'userId': 'see994', 'userIdx': 202, 'userNick': '가온'},
                ]),
              ),
      );
      expect((await PandaLiveSite(liveDown).searchRooms('가온')).single.roomId, 'see994');
      final empty = _world(
        search: (request) => request.url.path == '/v1/live/index'
            ? _response(request, '', status: 429)
            : _response(request, _pageFor(request, const [])),
      );
      await expectLater(PandaLiveSite(empty).searchRooms('가온'), throwsA(isA<RateLimited>()));
      final down = _world(search: (request) => _response(request, '', status: 500));
      await expectLater(PandaLiveSite(down).searchRooms('가온'), throwsA(isA<NetworkFailure>()));
      final bjOnly = _world(search: (request) => _response(request, '', status: 403));
      await expectLater(PandaLiveSite(bjOnly).searchRooms('가온', pageSize: 1), throwsA(isA<RiskControl>()));
    });

    test('a room link finds that broadcaster alone (one member/bj), on page 1 only', () async {
      final setup = _setup(['S04-member-live']);
      final searches = (_legacy('S04-member-live')['searchRooms'] as Map).cast<String, dynamic>();
      for (final link in [
        'https://www.pandalive.co.kr/live/play/daisy00',
        'https://www.pandalive.co.kr/channel/daisy00/home',
      ]) {
        final before = setup.http.requests.length;
        final rooms = await setup.site.searchRooms(link);
        final outcome = searches[link] as Map<String, dynamic>;
        _expectLegacyRequests(setup.http.requests.sublist(before), outcome);
        _expectParity(
          _projection(rooms.single),
          (outcome['value'] as List).single as Map<String, dynamic>,
          reason: link,
        );
        expect(rooms.single.data, isNull, reason: 'a refresh room: no stream data');
      }
      expect(await setup.site.searchRooms('https://www.pandalive.co.kr/live/play/daisy00', page: 2), isEmpty);
      expect(setup.http.requests, hasLength(2));
    });

    test('the live page /play/<id> is a room link too (3.x: another URL, nothing)', () async {
      final setup = _setup(['S04-member-live']);
      final legacy =
          (_legacy('S04-member-live')['searchRooms'] as Map)['https://www.pandalive.co.kr/play/daisy00'] as Map;
      expect(legacy['value'], isEmpty);
      final rooms = await setup.site.searchRooms('https://www.pandalive.co.kr/play/daisy00');
      expect(rooms.single.roomId, 'daisy00');
      expect(_paths(setup.http.requests), ['/v1/member/bj']);
    });

    test('a link to no broadcaster finds nothing', () async {
      final setup = _setup(['S04-member-notfound']);
      expect(await setup.site.searchRooms('https://www.pandalive.co.kr/channel/zxqvnouserfix'), isEmpty);
      final legacy =
          (_legacy('S04-member-notfound')['searchRooms'] as Map)['https://www.pandalive.co.kr/channel/zxqvnouserfix'];
      expect((legacy as Map)['value'], containsPair('message', 'PandaTV schema'), reason: '3.x failed the search');
    });

    test('a broadcaster id is searched too, the broadcaster first (25-11; 3.x: it alone, one member/bj)', () async {
      final outcome = (_legacy('S04-member-live')['searchRooms'] as Map)['daisy00'] as Map<String, dynamic>;
      expect(_legacyRequests(outcome).map((request) => request['url']), ['https://api.pandalive.co.kr/v1/member/bj']);
      expect(outcome['value'] as List, hasLength(1));
      final http = _world(
        member: (request) => throw StateError('the BJ search listed it'),
        search: (request) => _response(
          request,
          _pageFor(request, [
            if (request.url.path == '/v1/live/bj_list') ...[
              {'userId': 'daisy001', 'userIdx': 11, 'userNick': 'a'},
              {'userId': 'daisy00', 'userIdx': 24133575, 'userNick': '데이지ღ'},
            ],
          ]),
        ),
      );
      for (final keyword in [' daisy00 ', 'DAISY00']) {
        final before = http.requests.length;
        final rooms = await PandaLiveSite(http).searchRooms(keyword);
        expect(rooms.map((room) => room.roomId), ['daisy00', 'daisy001'], reason: keyword);
        expect(_paths(http.requests.sublist(before)), ['/v1/live/bj_list', '/v1/live/index'], reason: keyword);
      }
    });

    test('a broadcaster id the searches did not list: member/bj after them, its room first (25-11)', () async {
      final setup = _setup(
        ['S04-member-live', 'S04-member-offline'],
        extra: [
          for (final (path, form) in [
            ('/v1/live/bj_list', {'offset': '0', 'limit': '15', 'searchVal': 'daisy00'}),
            ('/v1/live/index', {'offset': '0', 'limit': '15', 'orderBy': 'user', 'searchVal': 'daisy00'}),
            ('/v1/live/bj_list', {'offset': '0', 'limit': '15', 'searchVal': 'flffl369'}),
            ('/v1/live/index', {'offset': '0', 'limit': '15', 'orderBy': 'user', 'searchVal': 'flffl369'}),
          ])
            ReplaySample(
              method: 'POST',
              url: Uri.https(PandaLiveApi.apiHost, path),
              status: 200,
              bytes: utf8.encode(
                jsonEncode({
                  'list': [
                    if (path.endsWith('bj_list')) {'userId': 'other7', 'userIdx': 7, 'userNick': 'o'},
                  ],
                  'page': {'offset': 0, 'limit': 15, 'total': path.endsWith('bj_list') ? 1 : 0, 'page': 1},
                  'result': true,
                  'message': '',
                }),
              ),
              form: form,
            ),
        ],
      );
      for (final (sample, id) in [('S04-member-live', 'daisy00'), ('S04-member-offline', 'flffl369')]) {
        final before = setup.http.requests.length;
        final rooms = await setup.site.searchRooms(' $id ');
        final sent = setup.http.requests.sublist(before);
        expect(_paths(sent), ['/v1/live/bj_list', '/v1/live/index', '/v1/member/bj'], reason: id);
        final outcome = (_legacy(sample)['searchRooms'] as Map)[id] as Map<String, dynamic>;
        expect(_described(sent.last), _upgraded(_legacyRequests(outcome).single), reason: '$id: as 3.x asked');
        expect(rooms.map((room) => room.roomId), [id, 'other7'], reason: id);
        _expectParity(_projection(rooms.first), (outcome['value'] as List).single as Map<String, dynamic>, reason: id);
      }
    });

    test('an id that is no broadcaster adds nothing (REG-PANDALIVE-001; 3.x failed the search)', () async {
      final notFound = Fixture.load('pandalive', 'S04-member-notfound');
      final legacy = (_legacy('S04-member-notfound')['searchRooms'] as Map)['zxqvnouserfix'] as Map;
      expect(legacy['value'], containsPair('message', 'PandaTV schema'));
      final http = _world(
        member: (request) => _response(request, notFound.body, status: 400),
        search: (request) => _response(
          request,
          _pageFor(request, [
            if (request.url.path == '/v1/live/bj_list') {'userId': 'zxqvnouser', 'userIdx': 9, 'userNick': 'z'},
          ]),
        ),
      );
      final rooms = await PandaLiveSite(http).searchRooms('zxqvnouserfix');
      expect(rooms.single.roomId, 'zxqvnouser');
      expect(_paths(http.requests), ['/v1/live/bj_list', '/v1/live/index', '/v1/member/bj']);
      final page2 = _world(member: (request) => throw StateError('no exact lookup after page 1'));
      await PandaLiveSite(page2).searchRooms('zxqvnouserfix', page: 2);
      expect(_paths(page2.requests), ['/v1/live/bj_list', '/v1/live/index']);
    });

    test("the exact lookup's other failures: the rows found stand; with none, the failure (3.x: always)", () async {
      final withRows = _world(
        member: (request) => _response(request, '', status: 503),
        search: (request) => _response(
          request,
          _pageFor(request, [
            if (request.url.path == '/v1/live/bj_list') {'userId': 'daisy001', 'userIdx': 9, 'userNick': 'z'},
          ]),
        ),
      );
      expect((await PandaLiveSite(withRows).searchRooms('daisy00')).single.roomId, 'daisy001');
      final nothing = _world(member: (request) => _response(request, '', status: 503));
      await expectLater(PandaLiveSite(nothing).searchRooms('daisy00'), throwsA(isA<NetworkFailure>()));
      expect(nothing.requests, hasLength(3));
      final searchesDown = _world(search: (request) => _response(request, '', status: 500));
      final rooms = await PandaLiveSite(searchesDown).searchRooms('fixture_101');
      expect(rooms.single.roomId, 'fixture_101', reason: 'member/bj found it though both searches failed');
    });

    test('nothing, without a request: page or size below 1, another URL, 1 or over 100 characters', () async {
      final http = _world(
        member: (request) => throw StateError('unexpected'),
        search: (request) => throw StateError('x'),
      );
      final site = PandaLiveSite(http);
      for (final (keyword, page, size) in [
        ('가온', 0, 30),
        ('가온', 1, 0),
        ('https://other.test/channel/gaoninc', 1, 30),
        ('https://www.pandalive.co.kr/search/daisy00', 1, 30),
        ('abc:def', 1, 30),
        ('가', 1, 30),
        (' ', 1, 30),
        ('가' * 101, 1, 30),
      ]) {
        expect(
          await site.searchRooms(keyword, page: page, pageSize: size),
          isEmpty,
          reason: keyword,
        );
      }
      expect(http.requests, isEmpty);
    });

    test('caller errors, without a request: a page over 1000, a control character (3.x: schema)', () async {
      final http = _world(
        member: (request) => throw StateError('unexpected'),
        search: (request) => throw StateError('unexpected'),
      );
      final site = PandaLiveSite(http);
      await expectLater(site.searchRooms('가온', page: 1001), throwsRangeError);
      await expectLater(site.searchRooms('daisy00', page: 1001), throwsRangeError);
      await expectLater(site.searchRooms('가\n온'), throwsArgumentError);
      expect(http.requests, isEmpty);
    });

    test('cancellation: before any request, between the two sources, before the exact lookup', () async {
      final idle = _world();
      await expectLater(PandaLiveSite(idle).searchRoomsCancellable('가온', cancel: CancelToken()..cancel()), _cancelled);
      expect(idle.requests, isEmpty);
      final cancel = CancelToken();
      final http = _world(
        search: (request) {
          cancel.cancel();
          return _response(request, _pageFor(request, const []));
        },
      );
      await expectLater(PandaLiveSite(http).searchRoomsCancellable('가온', cancel: cancel), _cancelled);
      expect(_paths(http.requests), ['/v1/live/bj_list']);
      expect(http.requests.single.cancel, same(cancel));
      final late = CancelToken();
      final exact = _world(
        search: (request) {
          if (request.url.path == '/v1/live/index') late.cancel();
          return _response(request, _pageFor(request, const []));
        },
      );
      await expectLater(PandaLiveSite(exact).searchRoomsCancellable('daisy00', cancel: late), _cancelled);
      expect(_paths(exact.requests), ['/v1/live/bj_list', '/v1/live/index']);
    });
  });

  group('rooms', () {
    test("room entry: member/bj, live/play, the master (3 requests), each as 3.x's; the same room", () async {
      final setup = _setup(_liveSamples);
      final room = await setup.site.getRoomDetail(roomId: 'daisy00');
      final outcome = _outcome('S04-member-live', 'getRoomDetail');
      _expectLegacyRequests(setup.http.requests, outcome);
      final [member, play, master] = setup.http.requests;
      expect([member.method, play.method, master.method], ['POST', 'POST', 'GET']);
      expect(setup.http.requests.map((request) => request.followRedirects), everyElement(isFalse));
      expect(
        master.headers,
        PandaLiveApi.headers('https://www.pandalive.co.kr/play/daisy00'),
        reason: '3.x read the master with its API headers; the Referer is the /play/ page (25-4)',
      );
      expect(master.url.queryParameters['token'], isNotEmpty, reason: 'the master as live/play gave it');
      _expectParity(_projection(room), outcome['value'] as Map<String, dynamic>);
      expect(room.restriction, LiveRestriction.none);
      expect(room.startedAt, DateTime.utc(2026, 9, 27, 17, 0, 35), reason: '25-12');
      expect(room.totalViewers, '903', reason: '25-3');
      final data = room.data! as PandaLiveRoomData;
      expect(data.userId, 'daisy00');
      expect(data.userIndex, 24133575);
      expect(data.qualities, hasLength(5));
    });

    test('room entry hands over the chat arguments of its live/play answer, without a request (25-2)', () async {
      final setup = _setup(_liveSamples);
      final room = await setup.site.getRoomDetail(roomId: 'daisy00');
      final play = jsonDecode(Fixture.load('pandalive', 'S05-play-live').body) as Map<String, dynamic>;
      final args = room.danmakuData! as PandaLiveDanmakuArgs;
      expect(args.userId, 'daisy00');
      expect(args.channel, '24133575');
      expect(args.token, play['token']);
      expect(setup.http.requests, hasLength(3));
      final recording = await setup.site.getRoomDetailForRecording(roomId: 'daisy00');
      expect((recording.danmakuData! as PandaLiveDanmakuArgs).channel, '24133575');
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: 'daisy00');
      expect(refreshed.danmakuData, isNull, reason: 'no live/play, no token');
      final numbered = PandaLiveSite(_world());
      expect(
        ((await numbered.getRoomDetail(roomId: 'fixture_101')).danmakuData! as PandaLiveDanmakuArgs).channel,
        '101',
        reason: 'a numeric channel',
      );
    });

    test('recording detail is room entry (3 requests, as 3.x)', () async {
      final setup = _setup(_liveSamples);
      final room = await setup.site.getRoomDetailForRecording(roomId: 'daisy00');
      final outcome = _outcome('S04-member-live', 'getRoomDetailForRecording');
      _expectLegacyRequests(setup.http.requests, outcome);
      _expectParity(_projection(room), outcome['value'] as Map<String, dynamic>);
      expect((room.data! as PandaLiveRoomData).qualities, hasLength(5));
    });

    test('refresh and live state: member/bj alone (as 3.x)', () async {
      final setup = _setup(['S04-member-live']);
      final room = await setup.site.getRoomDetailForRefresh(roomId: 'daisy00');
      final outcome = _outcome('S04-member-live', 'getRoomDetailForRefresh');
      _expectLegacyRequests(setup.http.requests, outcome);
      _expectParity(_projection(room), outcome['value'] as Map<String, dynamic>);
      expect(room.data, isNull);
      expect(room.restriction, LiveRestriction.none, reason: 'member/bj shows the flags');
      expect(await setup.site.getLiveStatus(roomId: 'daisy00'), _legacyValue('S04-member-live', 'getLiveStatus'));
      expect(setup.http.requests, hasLength(2));
    });

    test('media that says it is not live: offline everywhere, member/bj alone (25-6; 3.x: live, then '
        'live/play)', () async {
      final http = _world(
        member: (request) => _response(request, _memberAnswer(media: _media(changes: {'isLive': false}))),
        play: (request) => throw StateError('no live/play for an offline broadcaster'),
      );
      final site = PandaLiveSite(http);
      final refreshed = await site.getRoomDetailForRefresh(roomId: 'fixture_101');
      expect(refreshed.liveStatus, LiveStatus.offline);
      expect(await site.getLiveStatus(roomId: 'fixture_101'), isFalse);
      final entered = await site.getRoomDetail(roomId: 'fixture_101');
      expect(entered.liveStatus, LiveStatus.offline);
      expect(entered.title, 'Fixture channel');
      await expectLater(site.getPlayQualities(detail: entered), throwsA(isA<StreamUnavailable>()));
      final searched = await site.searchRooms('https://www.pandalive.co.kr/play/fixture_101');
      expect(searched.single.liveStatus, LiveStatus.offline);
      expect(_paths(http.requests), everyElement('/v1/member/bj'));
      expect(http.requests, hasLength(4));
    });

    test('a rerun (rec): a replay in refresh, entry and recording, played like a live broadcast (the unified '
        'rule on reruns; 3.x: live)', () async {
      const rec = {'onAirType': 'rec', 'liveType': 'rec'};
      final http = _world(
        member: (request) => _response(request, _memberAnswer(media: _media(changes: rec))),
        play: (request) => _response(request, _playAnswer(media: _media(changes: rec))),
        search: (request) => _response(request, _pageFor(request, [_media(changes: rec)])),
      );
      final site = PandaLiveSite(http);
      final card = (await site.getRecommendRooms()).single;
      expect(card.liveStatus, LiveStatus.replay);
      final refreshed = await site.getRoomDetailForRefresh(roomId: 'fixture_101');
      expect(refreshed.liveStatus, LiveStatus.replay);
      expect(refreshed.followGroup, FollowGroup.replay);
      expect(await site.getLiveStatus(roomId: 'fixture_101'), isFalse, reason: 'a replay is not live (M2.1)');
      final before = http.requests.length;
      expect(await site.getPlayQualities(detail: card), hasLength(2), reason: 'a replay card is entered first');
      expect(_paths(http.requests.sublist(before)).take(2), ['/v1/member/bj', '/v1/live/play']);
      for (final room in [
        await site.getRoomDetail(roomId: 'fixture_101'),
        await site.getRoomDetailForRecording(roomId: 'fixture_101'),
      ]) {
        expect(room.liveStatus, LiveStatus.replay);
        expect(room.restriction, LiveRestriction.none);
        expect(room.danmakuData, isA<PandaLiveDanmakuArgs>());
        final quality = (await site.getPlayQualities(detail: room)).first;
        expect((await site.resolvePlayUrls(detail: room, quality: quality)).urls, isNotEmpty);
      }
    });

    test('an offline broadcaster: member/bj alone; its channel, offline; no stream, without a request', () async {
      final setup = _setup(['S04-member-offline']);
      for (final key in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        final before = setup.http.requests.length;
        final room = await switch (key) {
          'getRoomDetail' => setup.site.getRoomDetail(roomId: 'flffl369'),
          'getRoomDetailForRefresh' => setup.site.getRoomDetailForRefresh(roomId: 'flffl369'),
          _ => setup.site.getRoomDetailForRecording(roomId: 'flffl369'),
        };
        final outcome = _outcome('S04-member-offline', key);
        _expectLegacyRequests(setup.http.requests.sublist(before), outcome);
        _expectParity(_projection(room), outcome['value'] as Map<String, dynamic>, reason: key);
        expect(room.danmakuData, isNull, reason: key);
      }
      expect(await setup.site.getLiveStatus(roomId: 'flffl369'), isFalse);
      final room = await setup.site.getRoomDetail(roomId: 'flffl369');
      final count = setup.http.requests.length;
      expect(_legacyValue('S04-member-offline', 'getPlayQualites'), isEmpty, reason: '3.x: an empty list');
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      final card = LiveRoom(platform: 'pandalive', roomId: 'flffl369', liveStatus: LiveStatus.offline);
      await expectLater(setup.site.getPlayQualities(detail: card), throwsA(isA<StreamUnavailable>()));
      expect(setup.http.requests, hasLength(count));
    });

    test('no such broadcaster is NotFound (3.x: schema), with one request', () async {
      final setup = _setup(['S04-member-notfound']);
      await expectLater(setup.site.getRoomDetail(roomId: 'zxqvnouserfix'), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getRoomDetailForRefresh(roomId: 'zxqvnouserfix'), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getLiveStatus(roomId: 'zxqvnouserfix'), throwsA(isA<NotFound>()));
      expect(setup.http.requests, hasLength(3));
      expect(_legacyRequests(_outcome('S04-member-notfound', 'getRoomDetail')), hasLength(1));
    });

    test('an id that is not a broadcaster id is NotFound without a request (3.x: identity)', () async {
      final setup = _setup(const []);
      for (final id in ['', 'a/b', '데이지', 'name@ka/evil', '../daisy00']) {
        await expectLater(setup.site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
        await expectLater(setup.site.getRoomDetailForRefresh(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(setup.http.requests, isEmpty);
    });

    test('ended (castEnd): the channel, offline, 2 requests (3.x: schema); no stream', () async {
      final setup = _setup(['S05-play-castend'], extra: [_syntheticMember('flffl369', 28103135, adult: false)]);
      final room = await setup.site.getRoomDetail(roomId: 'flffl369');
      expect(_legacyValue('S05-play-castend', 'getRoomDetail'), containsPair('message', 'PandaTV schema'));
      expect(_paths(setup.http.requests), ['/v1/member/bj', '/v1/live/play']);
      expect(
        _legacyRequests(_outcome('S05-play-castend', 'getRoomDetail')).map((request) => request['url']),
        setup.http.requests.map((request) => '${request.url}'),
      );
      expect(room.liveStatus, LiveStatus.offline);
      expect(room.danmakuData, isNull);
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      expect(setup.http.requests, hasLength(2));
    });

    test('adult (needAdult): live, adult, 2 requests (3.x: schema); the stream needs a login', () async {
      final setup = _setup(['S05-play-needlogin'], extra: [_syntheticMember('youngddo819', 1000001, adult: true)]);
      final room = await setup.site.getRoomDetailForRecording(roomId: 'youngddo819');
      expect(
        _legacyValue('S05-play-needlogin', 'getRoomDetailForRecording'),
        containsPair('message', 'PandaTV schema'),
      );
      expect(_paths(setup.http.requests), ['/v1/member/bj', '/v1/live/play']);
      expect(room.isLiveNow, isTrue);
      expect(room.restriction, LiveRestriction.adult);
      expect(room.notice, PandaLiveApi.adultNotice);
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<NeedsLogin>()));
      await expectLater(
        setup.site.getPlayUrls(
          detail: room,
          quality: const LivePlayQuality(quality: '720p', id: '720p'),
        ),
        throwsA(isA<NeedsLogin>()),
      );
      expect(room.danmakuData, isNull, reason: 'a refusal has no chat token');
    });

    test('the master refused or unreadable fails the entry (3.x); gone or without video, it is entered, '
        'unplayable', () async {
      final forbidden = _world(master: (request) => _response(request, '', status: 403));
      await expectLater(PandaLiveSite(forbidden).getRoomDetail(roomId: 'fixture_101'), throwsA(isA<RiskControl>()));
      final unreadable = _world(master: (request) => _response(request, '<html>'));
      await expectLater(PandaLiveSite(unreadable).getRoomDetail(roomId: 'fixture_101'), throwsA(isA<ApiChanged>()));
      expect((await PandaLiveSite(unreadable).getRoomDetailForRefresh(roomId: 'fixture_101')).isLiveNow, isTrue);
      for (final master in [
        (LiveRequest request) => _response(request, '', status: 404),
        (LiveRequest request) => _response(request, _masterText(const [])),
      ]) {
        final http = _world(master: master);
        final site = PandaLiveSite(http);
        final room = await site.getRoomDetail(roomId: 'fixture_101');
        expect(room.isLiveNow, isTrue);
        expect(room.restriction, LiveRestriction.unplayable);
        expect(room.danmakuData, isA<PandaLiveDanmakuArgs>(), reason: 'the chat works without the video');
        await expectLater(site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
        expect(http.requests, hasLength(3));
      }
    });

    test('live without an HLS master: entered, 2 requests, unplayable (3.x failed the entry)', () async {
      final http = _world(
        play: (request) => _response(
          request,
          jsonEncode({
            'media': _media(),
            'PlayList': {'hls3': <Object?>[], 'whip': <Object?>[]},
            'result': true,
          }),
        ),
      );
      final site = PandaLiveSite(http);
      final room = await site.getRoomDetail(roomId: 'fixture_101');
      expect(room.isLiveNow, isTrue);
      expect(room.restriction, LiveRestriction.unplayable);
      await expectLater(site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      expect(http.requests, hasLength(2));
    });

    test('the other refusals of live/play enter the room with their restriction, notice and reason', () async {
      for (final (code, changes, restriction, matcher) in [
        ('needPassword', const <String, Object?>{}, LiveRestriction.password, isA<StreamUnavailable>()),
        ('needLogin', const <String, Object?>{}, LiveRestriction.needsLogin, isA<NeedsLogin>()),
        ('needLogin', {'isPw': true}, LiveRestriction.password, isA<StreamUnavailable>()),
      ]) {
        final http = _world(
          member: (request) => _response(request, _memberAnswer(media: _media(changes: changes))),
          play: (request) => _response(request, _refusal(code), status: 400),
        );
        final site = PandaLiveSite(http);
        final room = await site.getRoomDetail(roomId: 'fixture_101');
        expect(room.restriction, restriction, reason: '$code $changes');
        expect(room.notice, PandaLiveApi.noticeOf(restriction), reason: '$code $changes');
        await expectLater(site.getPlayQualities(detail: room), throwsA(matcher), reason: '$code $changes');
      }
    });

    test('a refresh merges into the room 3.x stored: the identity is the id as asked', () async {
      final setup = _setup(['S04-member-live']);
      final stored = LiveRoom.fromJson({
        ...(_legacyValue('S04-member-live', 'getRoomDetailForRefresh')! as Map<String, dynamic>),
        'tagIds': const ['t1'],
      });
      final fresh = await setup.site.getRoomDetailForRefresh(roomId: stored.roomId);
      final merged = stored.mergeFrom(fresh);
      expect(merged.hasSameIdentity(stored), isTrue);
      expect(merged.identityKey, 'pandalive:daisy00');
      expect(merged.tagIds, ['t1']);
      expect(merged.httpHeaders, stored.httpHeaders, reason: "3.x's stored headers are kept");
      expect(merged.startedAt, fresh.startedAt);
      final card = LiveRoom.fromJson(
        ((_legacyValue('S01-index-hot', 'getDirectoryPage(1)')! as Map)['rooms'] as List)[1] as Map<String, dynamic>,
      );
      expect(card.hasSameIdentity(fresh), isTrue, reason: 'a directory card and the refresh are one room');
    });
  });

  group('streams', () {
    test("qualities and lines come from room entry, without a request; the URLs are 3.x's under the new ids "
        '(25-5)', () async {
      final setup = _setup(_liveSamples);
      final room = await setup.site.getRoomDetail(roomId: 'daisy00');
      final count = setup.http.requests.length;
      final qualities = await setup.site.getPlayQualities(detail: room);
      final legacy = (_legacyValue('S04-member-live', 'getPlayQualites')! as List).cast<Map<String, dynamic>>();
      expect(qualities.map((quality) => quality.quality), ['原画', '720p', '480p', '360p', '160p']);
      expect(
        qualities.map((quality) => quality.id),
        legacy.map((quality) => PandaLiveApi.qualityIdFromLegacy(quality['id'] as String)),
      );
      final urls = (_legacy('S04-member-live')['getPlayUrls'] as Map).cast<String, dynamic>();
      final resolved = (_legacy('S04-member-live')['resolvePlayUrlsRaw'] as Map).cast<String, dynamic>();
      for (final (index, quality) in qualities.indexed) {
        final legacyId = legacy[index]['id'] as String;
        expect(await setup.site.getPlayUrls(detail: room, quality: quality), urls[legacyId]);
        final resolution = await setup.site.resolvePlayUrls(detail: room, quality: quality);
        final legacyResolution = (resolved[legacyId] as Map)['value'] as Map;
        expect(resolution.urls, legacyResolution['urls']);
        expect(legacyResolution['appliedQualityData'], legacyId);
        expect(resolution.appliedQualityData, quality.id);
        final line = resolution.lines.single;
        expect(line.headers, PandaLiveApi.mediaHeaders('daisy00'));
        expect(line.format, StreamFormat.hls);
        expect(line.codec, 'avc');
        expect(line.lineId, 'ivs');
        expect(line.lease?.refreshAt, _issuedAt.add(PandaLiveApi.variantRefresh));
        expect(line.lease?.cutsConnection, isTrue);
      }
      expect(setup.http.requests, hasLength(count));
    });

    test('a quality 3.x stored (1080p30) plays its quality now, applied under the new id (25-5)', () async {
      final setup = _setup(_liveSamples);
      final room = await setup.site.getRoomDetail(roomId: 'daisy00');
      final urls = (_legacy('S04-member-live')['getPlayUrls'] as Map).cast<String, dynamic>();
      for (final old in ['1080p30', '360p30']) {
        final resolution = await setup.site.resolvePlayUrls(
          detail: room,
          quality: LivePlayQuality(quality: '$old · HLS', id: old),
        );
        expect(resolution.urls, urls[old], reason: old);
        expect(resolution.appliedQualityData, PandaLiveApi.qualityIdFromLegacy(old), reason: old);
      }
      expect(setup.http.requests, hasLength(3));
    });

    test('a card without stream data (a list card, a refreshed follow) is entered first (3.x: identity)', () async {
      final setup = _setup(_liveSamples);
      expect(_legacyValue('S01-index-hot', 'getPlayQualites(card)'), containsPair('message', 'PandaTV identity'));
      final card = LiveRoom(platform: 'pandalive', roomId: 'daisy00', liveStatus: LiveStatus.live);
      expect(await setup.site.getPlayQualities(detail: card), hasLength(5));
      expect(setup.http.requests, hasLength(3));
      final follow = LiveRoom(platform: 'pandalive', roomId: 'daisy00');
      expect(await setup.site.getPlayQualities(detail: follow), hasLength(5), reason: 'state unknown');
      expect(setup.http.requests, hasLength(6));
    });

    test('recovery enters the room again (3 requests, as 3.x) with the same URLs', () async {
      final setup = _setup(_liveSamples);
      final room = await setup.site.getRoomDetail(roomId: 'daisy00');
      final quality = (await setup.site.getPlayQualities(detail: room))[1];
      expect(quality.id, '720p');
      final resolution = await setup.site.resolvePlayUrlsForRecovery(detail: room, quality: quality);
      final outcome =
          (_legacy('S04-member-live')['resolvePlayUrlsForRecoveryRaw'] as Map)['720p30'] as Map<String, dynamic>;
      _expectLegacyRequests(setup.http.requests.sublist(3), outcome);
      final legacy = outcome['value'] as Map;
      expect(resolution.urls, legacy['urls']);
      expect(legacy['appliedQualityData'], '720p30');
      expect(resolution.appliedQualityData, '720p');
    });

    test('recovery onto a broadcast without the quality is StreamUnavailable; the old lines are not reused', () async {
      var heights = ['1080', '720'];
      final http = _world(master: (request) => _response(request, _masterText(heights)));
      final site = PandaLiveSite(http);
      final room = await site.getRoomDetail(roomId: 'fixture_101');
      final quality = (await site.getPlayQualities(detail: room)).first;
      expect(quality.id, '1080p');
      heights = ['720'];
      await expectLater(
        site.resolvePlayUrlsForRecovery(detail: room, quality: quality),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(http.requests, hasLength(6));
    });

    test("another broadcaster's data is not used (compared without case, as 3.x); another platform's room is a "
        'caller error', () async {
      final http = _world();
      final site = PandaLiveSite(http);
      final room = await site.getRoomDetail(roomId: 'fixture_101');
      final upper = LiveRoom(platform: 'pandalive', roomId: 'FIXTURE_101', data: room.data);
      expect(await site.getPlayQualities(detail: upper), hasLength(2));
      expect(http.requests, hasLength(3));
      final stranger = LiveRoom(
        platform: 'pandalive',
        roomId: 'someone',
        liveStatus: LiveStatus.offline,
        data: room.data,
      );
      await expectLater(site.getPlayQualities(detail: stranger), throwsA(isA<StreamUnavailable>()));
      await expectLater(
        site.getPlayQualities(
          detail: LiveRoom(platform: 'chzzk', roomId: 'fixture_101', data: room.data),
        ),
        throwsArgumentError,
      );
      expect(http.requests, hasLength(3));
    });
  });

  group('errors', () {
    test('transport failures are NetworkFailure; a cancellation stays one', () async {
      for (final reason in [TransportReason.connect, TransportReason.timeout, TransportReason.tls]) {
        final site = PandaLiveSite(_Scripted((request) => throw TransportFailure('pandalive', reason)));
        await expectLater(site.getRoomDetail(roomId: 'daisy00'), throwsA(isA<NetworkFailure>()), reason: '$reason');
      }
      final cancelled = PandaLiveSite(
        _Scripted((request) => throw const TransportFailure('pandalive', TransportReason.cancelled)),
      );
      await expectLater(cancelled.getRecommendRooms(), _cancelled);
    });

    test("statuses as 3.x's _read classed them, except that 400 is read (REG-PANDALIVE-001)", () async {
      for (final (status, matcher) in [
        (400, isA<ApiChanged>()),
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (500, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
      ]) {
        final site = PandaLiveSite(_Scripted((request) => _response(request, '', status: status)));
        await expectLater(site.getRecommendRooms(), throwsA(matcher), reason: '$status');
      }
      final refused = PandaLiveSite(
        _Scripted((request) => _response(request, jsonEncode({'result': false, 'message': '점검 중'}))),
      );
      await expectLater(refused.getRecommendRooms(), throwsA(isA<ApiChanged>()));
    });
  });

  group('links', () {
    LinkParser parser(LiveHttp http) => LinkParser(SiteRegistry({'pandalive': () => PandaLiveSite(http)}), http);

    test('live, channel and /play/ pages in a share text, without a request', () async {
      final http = ReplayHttp(const []);
      for (final (text, id) in [
        ('팬더티비 https://www.pandalive.co.kr/live/play/daisy00。快来', 'daisy00'),
        ('https://m.pandalive.co.kr/channel/1506087545%40ka/home', '1506087545@ka'),
        ('보러 와 https://www.pandalive.co.kr/play/Daisy00 !', 'Daisy00'),
      ]) {
        expect(await parser(http).parse(text), RoomLink('pandalive', id), reason: text);
      }
      expect(parser(http).containsSupportedLink('https://www.pandalive.co.kr/channel/daisy00'), isTrue);
      expect(http.requests, isEmpty);
    });

    test('other pages and hosts are not rooms; there are no short links', () async {
      final http = ReplayHttp(const []);
      for (final text in [
        'https://www.pandalive.co.kr/live',
        'https://www.pandalive.co.kr/search/daisy00',
        'https://www.pandalive.co.kr.evil.test/live/play/daisy00',
        'https://www.pandalive.co.kr:444/live/play/daisy00',
      ]) {
        expect(await parser(http).parse(text), isNull, reason: text);
      }
      final site = PandaLiveSite(http);
      expect(site.needsResolving('https://www.pandalive.co.kr/live/play/daisy00'), isFalse);
      expect(site.roomIdsInShareText('https://www.pandalive.co.kr/live/play/daisy00'), isEmpty);
      expect(http.requests, isEmpty);
    });
  });
}
