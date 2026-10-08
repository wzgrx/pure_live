// TikTokSite over the recorded TikTok responses (ReplayHttp) and a few
// synthetic ones: 3.x's requests and headers, the empty directory, the exact
// search, room details for entry, refresh and recording, the live status,
// streams from room entry and recovery, links through LinkParser (user
// links, share/live links, short links), cancellation and the error
// mapping. 3.x had no TikTok tests; request counts and results are compared
// with 3.x's frozen output (expected.json).
import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/tiktok';
const _userRoom = 'https://www.tiktok.com/api-live/user/room/?aid=1988&sourceType=54&staleTime=600000&uniqueId=';
const _roomInfo = 'https://webcast.tiktok.com/webcast/room/info/?aid=1988&room_id=';

/// S02-room-live's LIVE room, @qvc's broadcast in S01-user-live.
const _liveRoomId = '7690279124098681614';

final DateTime _issued = Fixture.load('tiktok', 'S01-user-live').capturedAt;

Map<String, dynamic> _legacy(String name) => Fixture.load('tiktok', name).legacy as Map<String, dynamic>;

/// The `result` of a traced legacy call.
Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

List<Object?> _requestsOf(Object? traced) => (traced! as Map<String, dynamic>)['requests'] as List<Object?>;

ReplaySample _synthetic(String url, Object body, {int status = 200, Map<String, List<String>> headers = const {}}) =>
    ReplaySample(
      method: 'GET',
      url: Uri.parse(url),
      status: status,
      bytes: utf8.encode(body is String ? body : jsonEncode(body)),
      headers: headers,
    );

typedef _Setup = ({TikTokSite site, ReplayHttp http});

/// The site over [samples] (then [extra]), its clock at the live sample's
/// capture.
_Setup _setup(List<String> samples, {List<ReplaySample> extra = const []}) {
  final http = ReplayHttp([for (final sample in samples) ReplaySample.load('$_root/$sample'), ...extra]);
  return (site: TikTokSite(http, now: () => _issued), http: http);
}

List<String> _urls(Iterable<LiveRequest> requests) => [for (final request in requests) request.url.toString()];

/// The live sample decoded, edited by [edit], as a synthetic answer for
/// @qvc.
ReplaySample _liveAnswer(void Function(Map<String, dynamic> data) edit, {String user = 'qvc'}) {
  final json = jsonDecode(Fixture.load('tiktok', 'S01-user-live').body) as Map<String, dynamic>;
  edit(json['data'] as Map<String, dynamic>);
  return _synthetic('$_userRoom$user', json);
}

Map<String, dynamic> _liveRoomOf(Map<String, dynamic> data) => data['liveRoom'] as Map<String, dynamic>;

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

final class _Failing implements LiveHttp {
  new(this.reason);

  final TransportReason reason;

  @override
  Future<LiveResponse> send(LiveRequest request) async => throw TransportFailure('tiktok', reason, 'test');

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('tiktok', reason, 'test');

  @override
  void close() {}
}

final Matcher _cancelled = throwsA(
  isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled),
);

/// avatar, cover: pictures on tiktokcdn-us.com, which 3.x did not trust;
/// httpHeaders: moved to the lines; notice: said for viewers (the unified
/// rule on notices, M4.U.22). See tiktok_api_test.dart.
const _changed = {'avatar', 'cover', 'httpHeaders', 'notice'};

void _expectParity(Map<String, Object?> actual, Map<String, dynamic> legacy, {String reason = ''}) {
  for (final MapEntry(:key, :value) in legacy.entries) {
    if (_changed.contains(key)) continue;
    expect(actual[key] ?? '', value ?? '', reason: '$reason $key');
  }
}

Map<String, Object?> _projection(LiveRoom room) => {...room.toJson(), 'link': room.link};

void main() {
  group('requests', () {
    test("3.x's URLs and headers, redirects not followed", () async {
      final setup = _setup(['S01-user-live', 'S02-room-live']);
      await setup.site.getRoomDetailForRefresh(roomId: 'qvc');
      await setup.site.searchRooms('https://www.tiktok.com/share/live/$_liveRoomId');
      expect(_urls(setup.http.requests), [
        ..._requestsOf(_legacy('S01-user-live')['getRoomDetailForRefresh(qvc)']),
        ..._requestsOf(_legacy('S02-room-live')['searchRooms(share link)']),
      ]);
      final common = {
        'user-agent': TikTokApi.userAgent,
        'accept': 'application/json, text/plain, */*',
        'accept-language': 'en-US,en;q=0.9',
        'origin': 'https://www.tiktok.com',
      };
      expect(setup.http.requests[0].headers, {...common, 'referer': 'https://www.tiktok.com/@qvc/live'});
      expect(setup.http.requests[1].headers, {...common, 'referer': 'https://www.tiktok.com/live'});
      for (final request in setup.http.requests) {
        expect((request.site, request.method, request.followRedirects), ('tiktok', 'GET', false));
        expect(request.timeout, const Duration(seconds: 20), reason: "3.x's receive deadline");
      }
    });

    test("3.x's name and capabilities, plus lines and links; no danmaku, categories or account", () async {
      final site = TikTokSite(ReplayHttp(const []));
      expect((site.id, site.name, site.directoryNoticeKey), ('tiktok', 'TikTok LIVE', 'tiktok_directory_scope'));
      expect(site, isA<LiveSiteDirectoryPager>());
      expect(site, isA<LiveDirectoryNotice>());
      expect(site, isA<LiveCancellableSearch>());
      expect(site, isA<LiveSiteRoomRefresher>());
      expect(site, isA<LiveSiteRecordRoomResolver>());
      expect(site, isA<LivePlayUrlResolver>());
      expect(site, isA<LivePlayRecoveryResolver>());
      expect(site, isA<LiveSiteLinks>());
      expect(site, isNot(isA<LiveSearchPaginationPolicy>()), reason: '3.x never paged TikTok searches');
      expect(site, isNot(isA<LivePlayUrlCursorResolver>()));
      expect(site, isNot(isA<LivePlayLeaseMetadata>()), reason: 'the lines carry their leases');
      expect(site, isNot(isA<LiveQualityDiscovery>()));
      expect(await site.getCategories(1, 30), isEmpty);
    });

    test('transport failures are NetworkFailure; a cancelled transport stays cancelled; statuses are typed', () async {
      await expectLater(
        TikTokSite(_Failing(TransportReason.timeout)).getRoomDetail(roomId: 'qvc'),
        throwsA(isA<NetworkFailure>()),
      );
      await expectLater(TikTokSite(_Failing(TransportReason.cancelled)).getRoomDetail(roomId: 'qvc'), _cancelled);
      for (final (status, matcher) in [
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (503, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
      ]) {
        final http = _Scripted(
          (request) => LiveResponse(status: status, bytes: utf8.encode('private raw body'), url: request.url),
        );
        await expectLater(TikTokSite(http).getRoomDetailForRefresh(roomId: 'qvc'), throwsA(matcher), reason: '$status');
      }
    });
  });

  group('directory', () {
    test('always empty and without a request (3.x); bad pages and categories are caller errors', () async {
      final setup = _setup([]);
      for (final page in [1, 2]) {
        final result = await setup.site.getDirectoryPage(page: page);
        final want = _result(_legacy('S01-user-live')[page == 1 ? 'getDirectoryPage' : 'getDirectoryPage(page: 2)']);
        expect({'rooms': result.rooms, 'page': result.page, 'hasMore': result.hasMore}, want);
      }
      expect(await setup.site.getRecommendRooms(), isEmpty);
      expect(await setup.site.getRecommendRooms(page: 0, pageSize: 0), isEmpty, reason: '3.x answered nothing');
      await expectLater(setup.site.getDirectoryPage(page: 0), throwsRangeError);
      await expectLater(
        setup.site.getDirectoryPage(
          category: const LiveArea(platform: 'tiktok', areaId: 'x'),
        ),
        throwsArgumentError,
      );
      await expectLater(setup.site.getDirectoryPage(cancel: CancelToken()..cancel()), _cancelled);
      expect(setup.http.requests, isEmpty);
    });
  });

  group('search', () {
    for (final (name, user) in [('S01-user-live', 'qvc'), ('S01-user-offline', 'cnn'), ('S01-user-missing', 'nasa')]) {
      test("$name: 3.x's results and requests for usernames, @usernames, links and other keywords", () async {
        final legacy = _legacy(name);
        for (final keyword in [
          user,
          '@$user',
          user.toUpperCase(),
          'https://www.tiktok.com/@$user/live',
          'not a user!',
          '',
        ]) {
          final setup = _setup([name]);
          final want = legacy['searchRooms($keyword)'];
          final rooms = await setup.site.searchRooms(keyword, pageSize: 20);
          final expected = (_result(want)! as List).cast<Map<String, dynamic>>();
          expect(rooms, hasLength(expected.length), reason: keyword);
          for (final (index, room) in rooms.indexed) {
            _expectParity(_projection(room), expected[index], reason: keyword);
            expect(room.data, isNull, reason: 'a refresh card');
          }
          expect(_urls(setup.http.requests), _requestsOf(want), reason: keyword);
        }
        final setup = _setup([name]);
        expect(await setup.site.searchRooms(user, page: 2), isEmpty);
        expect(await setup.site.searchRooms(user, pageSize: 0), isEmpty);
        expect(setup.http.requests, isEmpty);
      });
    }

    test("a share/live link: its owner, then the user (3.x's two requests and card)", () async {
      final setup = _setup(['S02-room-live', 'S01-user-live']);
      final want = _legacy('S02-room-live')['searchRooms(share link)'];
      final rooms = await setup.site.searchRooms('https://www.tiktok.com/share/live/$_liveRoomId', pageSize: 20);
      _expectParity(_projection(rooms.single), (_result(want)! as List).single as Map<String, dynamic>);
      expect(_urls(setup.http.requests), _requestsOf(want));
    });

    test('an unknown LIVE room gives nothing; another failure is thrown (3.x)', () async {
      final unknown = _setup(
        [],
        extra: [
          _synthetic('$_roomInfo$_liveRoomId', {'status_code': 4003110, 'data': <String, Object?>{}}),
        ],
      );
      expect(await unknown.site.searchRooms('https://www.tiktok.com/share/live/$_liveRoomId'), isEmpty);
      expect(unknown.http.requests, hasLength(1));
      final limited = _setup([], extra: [_synthetic('${_userRoom}qvc', '', status: 429)]);
      await expectLater(limited.site.searchRooms('qvc'), throwsA(isA<RateLimited>()));
    });

    test('the cancellation goes with the requests; cancelled searches send nothing', () async {
      final setup = _setup(['S01-user-live']);
      final token = CancelToken();
      await setup.site.searchRoomsCancellable('qvc', cancel: token);
      expect(identical(setup.http.requests.single.cancel, token), isTrue);
      await expectLater(setup.site.searchRoomsCancellable('qvc', cancel: CancelToken()..cancel()), _cancelled);
      expect(setup.http.requests, hasLength(1));
      final answered = CancelToken();
      final http = _Scripted((request) {
        answered.cancel();
        return LiveResponse(status: 200, bytes: utf8.encode('{}'), url: request.url);
      });
      await expectLater(TikTokSite(http).searchRoomsCancellable('qvc', cancel: answered), _cancelled);
    });

    ReplaySample redirect(String from, String to, {int status = 301}) => _synthetic(
      from,
      '',
      status: status,
      headers: {
        'location': [to],
      },
    );

    test('changed (22-5): a short link is read to the user it leads to (3.x found nothing)', () async {
      expect(_result(_legacy('S01-user-live')['searchRooms(https://vm.tiktok.com/ZMabcdef/)']), isEmpty);
      expect(_requestsOf(_legacy('S01-user-live')['searchRooms(https://vm.tiktok.com/ZMabcdef/)']), isEmpty);
      for (final (link, target) in [
        ('https://vm.tiktok.com/ZMabcdef/', 'https://www.tiktok.com/@qvc/live?_r=1&_t=x'),
        ('https://vt.tiktok.com/ZSabcdef/', 'https://m.tiktok.com/@QVC'),
        ('https://www.tiktok.com/t/ZTabcdef/', '/@qvc/live'),
      ]) {
        final setup = _setup(['S01-user-live'], extra: [redirect(link, target, status: 302)]);
        final rooms = await setup.site.searchRooms(' $link ');
        final want = _result(_legacy('S01-user-live')['searchRooms(qvc)'])! as List;
        _expectParity(_projection(rooms.single), want.single as Map<String, dynamic>, reason: link);
        expect(_urls(setup.http.requests), [link, '${_userRoom}qvc'], reason: link);
        final short = setup.http.requests.first;
        expect((short.site, short.followRedirects), ('tiktok', false));
        expect(short.headers, {'user-agent': TikTokApi.userAgent}, reason: "resolveUrl's headers");
      }
    });

    test('22-5: a short link to a share/live link, or through another short link; three requests at most', () async {
      final share = _setup(
        ['S02-room-live', 'S01-user-live'],
        extra: [redirect('https://vm.tiktok.com/ZMlive/', 'https://www.tiktok.com/share/live/$_liveRoomId?u=1')],
      );
      expect((await share.site.searchRooms('https://vm.tiktok.com/ZMlive/')).single.roomId, 'qvc');
      expect(_urls(share.http.requests), [
        'https://vm.tiktok.com/ZMlive/',
        '$_roomInfo$_liveRoomId',
        '${_userRoom}qvc',
      ]);
      final chain = _setup(
        ['S01-user-live'],
        extra: [
          redirect('https://vm.tiktok.com/ZMa/', 'https://vt.tiktok.com/ZSb/'),
          redirect('https://vt.tiktok.com/ZSb/', 'https://www.tiktok.com/t/ZTc/'),
          redirect('https://www.tiktok.com/t/ZTc/', 'https://www.tiktok.com/@qvc'),
        ],
      );
      expect((await chain.site.searchRooms('https://vm.tiktok.com/ZMa/')).single.roomId, 'qvc');
      expect(chain.http.requests, hasLength(4));
      final long = _setup(
        [],
        extra: [
          redirect('https://vm.tiktok.com/ZM1/', 'https://vm.tiktok.com/ZM2/'),
          redirect('https://vm.tiktok.com/ZM2/', 'https://vm.tiktok.com/ZM3/'),
          redirect('https://vm.tiktok.com/ZM3/', 'https://vm.tiktok.com/ZM4/'),
        ],
      );
      expect(await long.site.searchRooms('https://vm.tiktok.com/ZM1/'), isEmpty);
      expect(long.http.requests, hasLength(TikTokApi.maxShortLinkHops));
      final loop = _setup(
        [],
        extra: [
          redirect('https://vm.tiktok.com/ZMx/', 'https://vt.tiktok.com/ZSy/'),
          redirect('https://vt.tiktok.com/ZSy/', 'https://vm.tiktok.com/ZMx/#again'),
        ],
      );
      expect(await loop.site.searchRooms('https://vm.tiktok.com/ZMx/'), isEmpty);
      expect(loop.http.requests, hasLength(2));
    });

    test('22-5: a short link to a video, the home page, another site, or no redirect gives nothing', () async {
      for (final sample in [
        redirect('https://vm.tiktok.com/ZMv/', 'https://www.tiktok.com/@qvc/video/7300000000000000000'),
        redirect('https://vm.tiktok.com/ZMv/', 'https://www.tiktok.com/'),
        redirect('https://vm.tiktok.com/ZMv/', 'https://live.bilibili.com/1'),
        redirect('https://vm.tiktok.com/ZMv/', 'ftp://www.tiktok.com/@qvc'),
        _synthetic('https://vm.tiktok.com/ZMv/', '<html></html>'),
        _synthetic('https://vm.tiktok.com/ZMv/', 'not found', status: 404),
        _synthetic('https://vm.tiktok.com/ZMv/', '', status: 400),
        _synthetic('https://vm.tiktok.com/ZMv/', '', status: 302),
      ]) {
        final setup = _setup([], extra: [sample]);
        expect(await setup.site.searchRooms('https://vm.tiktok.com/ZMv/'), isEmpty, reason: '${sample.status}');
        expect(setup.http.requests, hasLength(1));
      }
    });

    test('22-5: refusals and failures of a short link are thrown; the cancellation goes with it', () async {
      for (final (status, matcher) in [
        (403, isA<RiskControl>()),
        (429, isA<RateLimited>()),
        (503, isA<NetworkFailure>()),
      ]) {
        final setup = _setup([], extra: [_synthetic('https://vm.tiktok.com/ZMe/', '', status: status)]);
        await expectLater(setup.site.searchRooms('https://vm.tiktok.com/ZMe/'), throwsA(matcher), reason: '$status');
      }
      await expectLater(
        TikTokSite(_Failing(TransportReason.timeout)).searchRooms('https://vm.tiktok.com/ZMe/'),
        throwsA(isA<NetworkFailure>()),
      );
      final setup = _setup([], extra: [redirect('https://vm.tiktok.com/ZMe/', 'https://www.tiktok.com/')]);
      final token = CancelToken();
      await setup.site.searchRoomsCancellable('https://vm.tiktok.com/ZMe/', cancel: token);
      expect(identical(setup.http.requests.single.cancel, token), isTrue);
      await expectLater(
        setup.site.searchRoomsCancellable('https://vm.tiktok.com/ZMe/', cancel: CancelToken()..cancel()),
        _cancelled,
      );
      expect(setup.http.requests, hasLength(1));
    });
  });

  group('rooms', () {
    test('entry, refresh and recording: one request each; only entry and recording carry the streams', () async {
      final setup = _setup(['S01-user-live']);
      final entered = await setup.site.getRoomDetail(roomId: 'qvc');
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: 'qvc');
      final recorded = await setup.site.getRoomDetailForRecording(roomId: 'qvc');
      expect(setup.http.requests, hasLength(3));
      expect((entered.data! as TikTokRoomData).streams, hasLength(7));
      expect((entered.data! as TikTokRoomData).issuedAt, _issued);
      expect((recorded.data! as TikTokRoomData).streams, hasLength(7));
      expect(refreshed.data, isNull);
      final want = _result(_legacy('S01-user-live')['getRoomDetailForRefresh(qvc)'])! as Map<String, dynamic>;
      _expectParity(_projection(refreshed), want);
      expect(
        _result(_legacy('S01-user-live')['getRoomDetail']),
        containsPair('message', 'TikTok schema'),
        reason: '3.x could not enter this room',
      );
    });

    test("3.x's identity: the username in lower case; other ids are NotFound without a request", () async {
      final setup = _setup(['S01-user-live']);
      final room = await setup.site.getRoomDetailForRefresh(roomId: ' QVC ');
      expect((room.roomId, room.identityKey), ('qvc', 'tiktok:qvc'));
      expect(_urls(setup.http.requests), ['${_userRoom}qvc']);
      for (final id in ['@qvc', 'q v c', '', '.qvc', _liveRoomId.padLeft(30, '1')]) {
        await expectLater(setup.site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(setup.http.requests, hasLength(1));
    });

    test('a 3.x follow merges the refresh: same identity, fresh state and pictures, its stored headers kept', () async {
      final follow = LiveRoom.fromJson({
        'roomId': 'qvc',
        'platform': 'tiktok',
        'userId': '6768510980420043782',
        'nick': 'QVC, Inc',
        'title': 'old',
        'avatar': '',
        'liveStatus': 1,
        'status': false,
        'httpHeaders': TikTokApi.mediaHeaders('qvc'),
        'tagIds': const ['shopping'],
      });
      final refreshed = await _setup(['S01-user-live']).site.getRoomDetailForRefresh(roomId: 'qvc');
      expect(refreshed.hasSameIdentity(follow), isTrue);
      final merged = follow.mergeFrom(refreshed);
      expect((merged.liveStatus, merged.title), (LiveStatus.live, 'Pumpkin Spice Season'));
      expect(merged.avatar, isNotEmpty);
      expect(merged.tagIds, ['shopping']);
      expect(merged.httpHeaders, TikTokApi.mediaHeaders('qvc'));
    });

    test('S01-user-missing: NotFound at every depth and for the live status (3.x: missing)', () async {
      final setup = _setup(['S01-user-missing']);
      for (final call in [
        () => setup.site.getRoomDetail(roomId: 'nasa'),
        () => setup.site.getRoomDetailForRefresh(roomId: 'nasa'),
        () => setup.site.getRoomDetailForRecording(roomId: 'nasa'),
        () => setup.site.getLiveStatus(roomId: 'nasa'),
      ]) {
        await expectLater(call(), throwsA(isA<NotFound>()));
      }
    });

    test(
      'live status: live true, offline false (3.x); a restricted LIVE is live (22-1); an unknown state no answer',
      () async {
        expect(
          await _setup(['S01-user-live']).site.getLiveStatus(roomId: 'qvc'),
          _result(_legacy('S01-user-live')['getLiveStatus']),
        );
        expect(
          await _setup(['S01-user-offline']).site.getLiveStatus(roomId: 'cnn'),
          _result(_legacy('S01-user-offline')['getLiveStatus']),
        );
        final restricted = _setup([], extra: [_liveAnswer((data) => _liveRoomOf(data)['liveSubOnly'] = 1)]);
        expect(await restricted.site.getLiveStatus(roomId: 'qvc'), isTrue, reason: '3.x: false');
        final unknown = _setup([], extra: [_liveAnswer((data) => _liveRoomOf(data)['status'] = 3)]);
        await expectLater(unknown.site.getLiveStatus(roomId: 'qvc'), throwsA(isA<StreamUnavailable>()));
      },
    );

    test('22-1: a restricted LIVE is live and marked at every depth; the refresh merges into a 3.x follow', () async {
      final setup = _setup([], extra: [_liveAnswer((data) => (data['user'] as Map)['secret'] = true)]);
      final follow = LiveRoom.fromJson(const {'roomId': 'qvc', 'platform': 'tiktok', 'liveStatus': 4});
      expect(follow.liveStatus, LiveStatus.banned, reason: "3.x's word for a restricted LIVE");
      for (final room in [
        await setup.site.getRoomDetail(roomId: 'qvc'),
        await setup.site.getRoomDetailForRefresh(roomId: 'qvc'),
        await setup.site.getRoomDetailForRecording(roomId: 'qvc'),
        (await setup.site.searchRooms('qvc')).single,
        follow.mergeFrom(await setup.site.getRoomDetailForRefresh(roomId: 'qvc')),
      ]) {
        expect(
          (room.liveStatus, room.restriction, room.followGroup),
          (LiveStatus.live, LiveRestriction.private, FollowGroup.live),
        );
        expect(room.startedAt, DateTime.utc(2026, 9, 27, 18, 12, 4));
      }
      expect(setup.http.requests, hasLength(5));
    });

    test('recording: an unrestricted live room without a stream is StreamUnavailable (3.x); offline and restricted '
        'rooms return', () async {
      final noStream = _setup(
        [],
        extra: [
          _liveAnswer(
            (data) => _liveRoomOf(data)
              ..remove('streamData')
              ..remove('hevcStreamData'),
          ),
        ],
      );
      await expectLater(noStream.site.getRoomDetailForRecording(roomId: 'qvc'), throwsA(isA<StreamUnavailable>()));
      final entered = await noStream.site.getRoomDetail(roomId: 'qvc');
      expect(entered.liveStatus, LiveStatus.live, reason: 'room entry shows the room; playing it fails');
      final unreadable = _setup(
        [],
        extra: [
          _liveAnswer(
            (data) => _liveRoomOf(data)
              ..['streamData'] = 'x'
              ..remove('hevcStreamData'),
          ),
        ],
      );
      await expectLater(unreadable.site.getRoomDetailForRecording(roomId: 'qvc'), throwsA(isA<ApiChanged>()));
      expect(
        (await _setup(['S01-user-offline']).site.getRoomDetailForRecording(roomId: 'cnn')).liveStatus,
        LiveStatus.offline,
      );
      final restricted = _setup([], extra: [_liveAnswer((data) => (data['user'] as Map)['secret'] = true)]);
      final room = await restricted.site.getRoomDetailForRecording(roomId: 'qvc');
      expect((room.liveStatus, room.restriction), (LiveStatus.live, LiveRestriction.private), reason: '3.x: banned');
    });
  });

  group('streams', () {
    test('an entered room plays from its own streams without a request; recovery reads the LIVE again', () async {
      final setup = _setup(['S01-user-live']);
      final room = await setup.site.getRoomDetail(roomId: 'qvc');
      setup.http.requests.clear();
      final qualities = await setup.site.getPlayQualities(detail: room);
      final legacy = _legacy('S01-user-live')['trustedHosts'] as Map<String, dynamic>;
      // Changed (22-2, 22-3, 22-4): 3.x's 14 ids, one per protocol, are 7.
      expect(qualities.map((quality) => quality.id), [
        'h264:origin',
        'h264:hd',
        'h265:uhd_60',
        'h265:hd_60',
        'h265:hd',
        'h265:sd',
        'h265:ld',
      ]);
      expect(
        {
          for (final quality in _result(legacy['getPlayQualites'])! as List)
            TikTokApi.qualityIdFromLegacy((quality as Map)['id'] as String),
        },
        {for (final quality in qualities) quality.id},
      );
      final resolution = await setup.site.resolvePlayUrls(detail: room, quality: qualities.first);
      expect(resolution.urls, [
        for (final id in ['h264:origin:flv', 'h264:origin:hls'])
          for (final url in _result((legacy['getPlayUrls'] as Map)[id])! as List)
            (url as String).replaceAll('tiktokcdn.com', 'tiktokcdn-us.com'),
      ]);
      expect(resolution.lines.map((line) => line.headers), everyElement(TikTokApi.mediaHeaders('qvc')));
      expect(await setup.site.getPlayUrls(detail: room, quality: qualities[2]), hasLength(2));
      expect(setup.http.requests, isEmpty, reason: '3.x played from the entered room');
      final recovered = await setup.site.resolvePlayUrlsForRecovery(detail: room, quality: qualities.first);
      expect(recovered.urls, resolution.urls);
      expect(recovered.appliedQualityData, 'h264:origin');
      expect(_urls(setup.http.requests), _requestsOf(legacy['resolvePlayUrlsForRecoveryRaw']));
    });

    test('22-3: "优先 H.264" is read at each call; off, 3.x\'s order (best tier first)', () async {
      var preferH264 = true;
      final http = ReplayHttp([ReplaySample.load('$_root/S01-user-live')]);
      final site = TikTokSite(http, preferH264: () => preferH264, now: () => _issued);
      final room = await site.getRoomDetail(roomId: 'qvc');
      Future<List<String>> names() async => [
        for (final quality in await site.getPlayQualities(detail: room)) quality.quality,
      ];
      expect(await names(), [
        '原画',
        '720p',
        '1080p60 · H.265',
        '720p60 · H.265',
        '720p · H.265',
        '540p · H.265',
        '360p · H.265',
      ]);
      preferH264 = false;
      expect(await names(), [
        '原画',
        '1080p60 · H.265',
        '720p60 · H.265',
        '720p',
        '720p · H.265',
        '540p · H.265',
        '360p · H.265',
      ]);
      expect(http.requests, hasLength(1));
      expect(
        (await _setup(['S01-user-live']).site.getPlayQualities(detail: room)).first.id,
        'h264:origin',
        reason: 'on by default',
      );
    });

    test('a card without streams (a follow, a search result) is entered first (3.x: identity error)', () async {
      final setup = _setup(['S01-user-live']);
      final card = await setup.site.getRoomDetailForRefresh(roomId: 'qvc');
      final trusted = _legacy('S01-user-live')['trustedHosts'] as Map<String, dynamic>;
      expect(trusted['getPlayQualites(refresh card)'], containsPair('message', 'TikTok identity'));
      setup.http.requests.clear();
      expect(await setup.site.getPlayQualities(detail: card), hasLength(7));
      expect(setup.http.requests, hasLength(1));
      final stored = LiveRoom(roomId: 'qvc', platform: 'tiktok');
      final resolution = await setup.site.resolvePlayUrls(
        detail: stored,
        quality: const LivePlayQuality(quality: '', id: 'h265:sd:hls'),
      );
      expect(resolution.lines.map((line) => line.format), [StreamFormat.flv, StreamFormat.hls], reason: '3.x id');
      expect(resolution.appliedQualityData, 'h265:sd');
    });

    test('a room known to be offline is refused without a request (3.x listed nothing); banned asks again', () async {
      final setup = _setup(['S01-user-offline']);
      final offline = await setup.site.getRoomDetail(roomId: 'cnn');
      setup.http.requests.clear();
      await expectLater(setup.site.getPlayQualities(detail: offline), throwsA(isA<StreamUnavailable>()));
      final card = LiveRoom(roomId: 'cnn', platform: 'tiktok', liveStatus: LiveStatus.offline);
      await expectLater(setup.site.getPlayQualities(detail: card), throwsA(isA<StreamUnavailable>()));
      const quality = LivePlayQuality(quality: '', id: 'h264:hd');
      await expectLater(
        setup.site.resolvePlayUrls(detail: offline, quality: quality),
        throwsA(isA<StreamUnavailable>()),
      );
      await expectLater(
        setup.site.resolvePlayUrlsForRecovery(detail: offline, quality: quality),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(setup.http.requests, isEmpty);
      // 3.x stored a restricted LIVE as banned: no longer a state of its own
      // (22-1), so the room is asked again (3.x refused it: NeedsLogin).
      final banned = LiveRoom(roomId: 'cnn', platform: 'tiktok', liveStatus: LiveStatus.banned);
      await expectLater(setup.site.getPlayQualities(detail: banned), throwsA(isA<StreamUnavailable>()));
      expect(_urls(setup.http.requests), ['${_userRoom}cnn']);
    });

    test("an entered room that a refresh found offline plays nothing (3.x read the room's state first)", () async {
      final setup = _setup(['S01-user-live']);
      final entered = await setup.site.getRoomDetail(roomId: 'qvc');
      final ended = entered.mergeFrom(LiveRoom(roomId: 'qvc', platform: 'tiktok', liveStatus: LiveStatus.offline));
      expect(ended.data, isA<TikTokRoomData>(), reason: 'mergeFrom keeps the old streams');
      setup.http.requests.clear();
      await expectLater(setup.site.getPlayQualities(detail: ended), throwsA(isA<StreamUnavailable>()));
      expect(setup.http.requests, isEmpty);
    });

    test('restricted, live without a stream, a state 3.x did not know: typed reasons, no further request', () async {
      for (final (edit, matcher) in <(void Function(Map<String, dynamic>), Matcher)>[
        // 3.x's NeedsLogin-like "access": no TikTok login would help (22-1).
        ((data) => _liveRoomOf(data)['liveSubOnly'] = 1, isA<StreamUnavailable>()),
        ((data) => (_liveRoomOf(data)['paidEvent'] as Map)['paid_type'] = 1, isA<StreamUnavailable>()),
        ((data) => (data['user'] as Map)['secret'] = true, isA<StreamUnavailable>()),
        (
          (data) => _liveRoomOf(data)
            ..remove('streamData')
            ..remove('hevcStreamData'),
          isA<StreamUnavailable>(),
        ),
        ((data) => _liveRoomOf(data)['hevcStreamData'] = 'x', isA<StreamUnavailable>()),
        ((data) => _liveRoomOf(data)['status'] = 3, isA<StreamUnavailable>()),
      ]) {
        final setup = _setup([], extra: [_liveAnswer(edit)]);
        final room = await setup.site.getRoomDetail(roomId: 'qvc');
        if ((room.data! as TikTokRoomData).streams.isNotEmpty) {
          // hevcStreamData unreadable: streamData still plays.
          expect(await setup.site.getPlayQualities(detail: room), hasLength(1));
          continue;
        }
        await expectLater(setup.site.getPlayQualities(detail: room), throwsA(matcher));
        await expectLater(
          setup.site.resolvePlayUrlsForRecovery(
            detail: room,
            quality: const LivePlayQuality(quality: '', id: 'h264:hd'),
          ),
          throwsA(matcher),
        );
        expect(setup.http.requests, hasLength(1));
      }
    });

    test('recovery: the quality must still be offered; a LIVE that ended is StreamUnavailable (3.x)', () async {
      final ended = _setup([], extra: [_liveAnswer((data) => _liveRoomOf(data)['status'] = 4)]);
      final room = await _setup(['S01-user-live']).site.getRoomDetail(roomId: 'qvc');
      const origin = LivePlayQuality(quality: '', id: 'h264:origin');
      await expectLater(
        ended.site.resolvePlayUrlsForRecovery(detail: room, quality: origin),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(ended.http.requests, hasLength(1));
      final fewer = _setup([], extra: [_liveAnswer((data) => _liveRoomOf(data).remove('hevcStreamData'))]);
      await expectLater(
        fewer.site.resolvePlayUrlsForRecovery(detail: room, quality: origin),
        throwsA(isA<StreamUnavailable>()),
      );
      for (final id in ['h264:hd', 'h264:hd:flv', 'h264:hd:hls']) {
        expect(
          (await fewer.site.resolvePlayUrlsForRecovery(
            detail: room,
            quality: LivePlayQuality(quality: '', id: id),
          )).appliedQualityData,
          'h264:hd',
          reason: id,
        );
      }
      await expectLater(
        _setup([]).site.resolvePlayUrls(
          detail: room,
          quality: const LivePlayQuality(quality: 'x'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test("another platform's room is a caller error", () async {
      await expectLater(
        _setup([]).site.getPlayQualities(
          detail: LiveRoom(roomId: 'qvc', platform: 'douyin'),
        ),
        throwsArgumentError,
      );
    });
  });

  group('links', () {
    LinkParser parser(ReplayHttp http) => LinkParser(SiteRegistry({'tiktok': () => TikTokSite(http)}), http);

    test('user links without a request (3.x: LiveUrlTool and WebSearchRoomParser)', () async {
      final http = ReplayHttp(const []);
      for (final text in [
        'https://www.tiktok.com/@QVC/live',
        '看直播 https://m.tiktok.com/@qvc，快来',
        'https://tiktok.com/@qvc?lang=en',
      ]) {
        expect(await parser(http).parse(text), const RoomLink('tiktok', 'qvc'), reason: text);
        expect(parser(http).containsSupportedLink(text), isTrue);
      }
      expect(_result(_legacy('S02-room-live')['LiveUrlTool.parseLiveUrl (TikTok step, user link)']), ['qvc', 'tiktok']);
      for (final text in [
        '@qvc',
        'qvc',
        'https://www.tiktok.com/@qvc/video/7300000000000000000',
        'https://www.tiktok.com/',
      ]) {
        expect(await parser(http).parse(text), isNull, reason: text);
        expect(parser(http).containsSupportedLink(text), isFalse, reason: text);
      }
      expect(http.requests, isEmpty);
    });

    test("a share/live link: its owner from one room/info (3.x's import)", () async {
      final http = ReplayHttp([ReplaySample.load('$_root/S02-room-live')]);
      const text = '分享直播 https://www.tiktok.com/share/live/$_liveRoomId 快来';
      expect(parser(http).containsSupportedLink(text), isTrue);
      expect(await parser(http).parse(text), const RoomLink('tiktok', 'qvc'));
      final want = _legacy('S02-room-live')['LiveUrlTool.parseLiveUrl (TikTok step)'];
      expect(_result(want), ['qvc', 'tiktok']);
      expect(_urls(http.requests), _requestsOf(want));
      expect(http.requests.single.headers['referer'], 'https://www.tiktok.com/live');
    });

    test(
      'a share/live link the site does not know, or a failed request, is no room (3.x reported a failure)',
      () async {
        for (final sample in [
          _synthetic('$_roomInfo$_liveRoomId', {'status_code': 4003110}),
          _synthetic('$_roomInfo$_liveRoomId', '', status: 403),
          _synthetic('$_roomInfo$_liveRoomId', {
            'status_code': 0,
            'data': {'id': '7690279124098681615'},
          }),
        ]) {
          final http = ReplayHttp([sample]);
          expect(await parser(http).parse('https://www.tiktok.com/share/live/$_liveRoomId'), isNull);
          expect(http.requests, hasLength(1));
        }
      },
    );

    test('short links: one redirect read, not followed, its target parsed again (3.x); /t/ links too', () async {
      for (final (link, target) in [
        ('https://vm.tiktok.com/ZMabcdef/', 'https://www.tiktok.com/@qvc/live?_r=1'),
        ('https://vt.tiktok.com/ZSabcdef/', 'https://m.tiktok.com/@qvc'),
        ('https://www.tiktok.com/t/ZTabcdef/', '/@qvc/live'),
      ]) {
        final http = ReplayHttp([
          _synthetic(
            link,
            '',
            status: 301,
            headers: {
              'location': [target],
            },
          ),
        ]);
        expect(parser(http).containsSupportedLink('看 $link'), isTrue);
        expect(await parser(http).parse('看 $link'), const RoomLink('tiktok', 'qvc'), reason: link);
        final request = http.requests.single;
        expect((request.followRedirects, request.headers['user-agent']), (false, TikTokApi.userAgent));
      }
    });

    test('a short link to a share/live link asks for its owner; to a video or nowhere, no room', () async {
      final http = ReplayHttp([
        _synthetic(
          'https://vm.tiktok.com/ZMlive/',
          '',
          status: 302,
          headers: {
            'location': ['https://www.tiktok.com/share/live/$_liveRoomId?u=1'],
          },
        ),
        ReplaySample.load('$_root/S02-room-live'),
        _synthetic(
          'https://vm.tiktok.com/ZMvideo/',
          '',
          status: 302,
          headers: {
            'location': ['https://www.tiktok.com/@qvc/video/7300000000000000000'],
          },
        ),
        _synthetic('https://vm.tiktok.com/ZMgone/', 'not found', status: 404),
      ]);
      expect(await parser(http).parse('https://vm.tiktok.com/ZMlive/'), const RoomLink('tiktok', 'qvc'));
      expect(await parser(http).parse('https://vm.tiktok.com/ZMvideo/'), isNull);
      expect(await parser(http).parse('https://vm.tiktok.com/ZMgone/'), isNull);
      expect(http.requests, hasLength(4));
    });
  });
}
