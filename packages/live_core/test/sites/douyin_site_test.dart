// DouyinSite over the recorded responses (ReplayHttp): the anonymous
// session, signing (against vectors computed with the 3.x code), catalog,
// search and its fallbacks, rooms and their fallbacks, streams, links (3.x's
// short-link cases) and the account check. msToken and a_bogus are random
// per request and scrubbed in the samples, so they are left out of matching.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/douyin';
const _ignored = {'msToken', 'a_bogus'};
const _webRid = '547977714661';
const _roomId = '7687741736843512602';

final DateTime _capturedAt = Fixture.load('douyin', 'S04-enter-live').capturedAt;

const _home = 'GET live.douyin.com/';
const _feed = 'GET live.douyin.com/webcast/feed/';
const _enter = 'GET live.douyin.com/webcast/room/web/enter/';
const _reflow = 'GET webcast.amemv.com/webcast/room/reflow/info/';
const _partition = 'GET live.douyin.com/webcast/web/partition/detail/room/v2/';
const _amemvPartition = 'GET webcast.amemv.com/webcast/web/partition/detail/room/v2/';

ReplaySample _fake(String url, {int status = 200, Map<String, List<String>> headers = const {}, Object body = ''}) =>
    ReplaySample(
      method: 'GET',
      url: Uri.parse(url),
      status: status,
      headers: headers,
      bytes: utf8.encode(body is String ? body : jsonEncode(body)),
    );

/// A recorded response served for another URL.
ReplaySample _moved(String sample, Uri url) {
  final recorded = ReplaySample.load('$_root/$sample');
  return ReplaySample(
    method: 'GET',
    url: url,
    status: recorded.status,
    headers: recorded.headers,
    bytes: recorded.bytes,
  );
}

/// The home page without Set-Cookie: no anonymous session.
final ReplaySample _homeWithoutTtwid = _fake('https://live.douyin.com/?from_nav=1', body: '<html></html>');

typedef _Setup = ({DouyinSite site, ReplayHttp http});

_Setup _replay(List<Object> samples, {CookieVault? cookies, DateTime Function()? now}) {
  final http = ReplayHttp([
    for (final sample in samples)
      if (sample is String) ReplaySample.load('$_root/$sample') else sample as ReplaySample,
  ], ignoredQuery: _ignored);
  return (site: DouyinSite(http, cookies: cookies, now: now ?? () => _capturedAt, random: Random(1)), http: http);
}

List<String> _paths(ReplayHttp http) => [
  for (final request in http.requests) '${request.method} ${request.url.host}${request.url.path}',
];

/// The anonymous cookie the recorded home page sets (ttwid and UIFID_TEMP).
String _anonymousCookie() {
  final headers = (Fixture.load('douyin', 'S01-home').meta['response'] as Map<String, dynamic>)['headers'] as Map;
  return [
    for (final line in (headers['set-cookie'] as List).cast<String>())
      if (line.startsWith('ttwid=') || line.startsWith('UIFID_TEMP=')) line.split(';').first,
  ].join('; ');
}

/// Hands out scripted values (the random draws of a signature).
final class _Scripted implements Random {
  new(this.values);

  final List<int> values;
  var _next = 0;

  @override
  int nextInt(int max) => values[_next++ % values.length];

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}

/// Holds requests until their gate opens.
final class _GatedHttp implements LiveHttp {
  new(this.inner, this.gate);

  final LiveHttp inner;
  final Future<void>? Function(LiveRequest request) gate;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    await gate(request);
    return await inner.send(request);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => inner.open(request);

  @override
  void close() {}
}

/// Fails every request at the transport level.
final class _FailingHttp implements LiveHttp {
  new(this.reason);

  final TransportReason reason;

  @override
  Future<LiveResponse> send(LiveRequest request) async => throw TransportFailure(request.site, reason);

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure(request.site, reason);

  @override
  void close() {}
}

void main() {
  group('signing (vectors from the 3.x code: utils/douyin/abogus.dart, danmaku/xbogus.dart)', () {
    String hex(List<int> bytes) => [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join();

    DouyinSigner signer({required String fingerprint, required List<int> clock, required List<int> seeds}) {
      var calls = 0;
      return DouyinSigner(
        userAgent: DouyinApi.userAgent,
        fingerprint: fingerprint,
        now: () => DateTime.fromMillisecondsSinceEpoch(clock[calls++ % clock.length]),
        random: _Scripted(seeds),
      );
    }

    test('SM3 matches the GB/T 32905-2016 examples (3.x used the dart_sm package)', () {
      expect(
        hex(DouyinSigner.sm3(utf8.encode('abc'))),
        '66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0',
      );
      expect(
        hex(DouyinSigner.sm3(utf8.encode('abcd' * 16))),
        'debe9ff92275b8a138604889c18e5a4d6fdb70e5387e5765293dcba39c0c5732',
      );
    });

    // Computed by running 3.x's ABogus with the clock and the random draws
    // injected (Chrome 134 UA, the given fingerprint).
    const vectors = [
      (
        query: '',
        fingerprint: '1536|747|1560|835|0|30|0|0|1920|1040|1920|1040|1536|747|24|24|Win32',
        clock: [1790506922004, 1790506922008],
        seeds: [1104, 4190, 3186],
        aBogus:
            'DXmhBDzIk3EN6Eyu5I5LfY3q6fe3YmZy0SVkMD2fvx3ziL39HMY69exoUUJv3TujZsmfIFEjy4hbT3ohrQ2y8qwf9W4x/25gsfSkKl12so0j'
            '53intL6mE0hN5kb3SFlm5XNAEOk0y75CFRJ0l2CymhK4bfebY7Y6i6trHD==',
      ),
      (
        query: 'a=1',
        fingerprint: '1920|1080|1944|1165|0|0|0|0|1024|768|1280|800|1920|1080|24|24|Win32',
        clock: [1790506922020, 1790506922021],
        seeds: [2655, 8703, 7770],
        aBogus:
            'd7WMQQz1sVLB6ESS5I5LfY3q6fB3YmZy0SVkMD2fYd3ziL39HMYL9exoUUJv3ORjZsmfIFEjy4hbO3xprQAjM36UHWwoWdQ2m66gKl5Q5xSS'
            's1feeLWQnsJL5iR3SFrd5XN1EOfkqwcGFuRDA9/rmhK4bfebY7Y6i6tr/E==',
      ),
      (
        query:
            'app_name=douyin_web&enter_from=web_live&live_id=1&web_rid=547977714661&is_need_double_stream=false'
            '&aid=6383&compress=gzip&device_platform=web&browser_language=zh-CN&browser_platform=Win32'
            '&browser_name=Edge&browser_version=125.0.0.0&msToken=AAAAbbbb%3D%3D',
        fingerprint: '1280|720|1308|805|0|30|0|0|1600|900|1600|860|1280|720|24|24|Win32',
        clock: [1790506922022, 1790506922023],
        seeds: [497, 9689, 1428],
        aBogus:
            'YX8hQRw3sV9khE6z5I5LfY3q6AP3YmZy0SVkMD2fRx3ziL39HMYo9exoUUJv3OfjZsmfIFYjy4hbYNQprQ2n01wfHSkO/25ZsfSkKl12so0j'
            '53inC6WmE0wN-hsAtlaQsvr4EKi8qXCaSYypAnAJ5kIlO62-zo0/9lW=',
      ),
      (
        query: 'keyword=%E5%92%8C%E5%B9%B3+x&offset=0',
        fingerprint: '1111|888|1140|970|0|0|0|0|1500|999|1700|1000|1111|888|24|24|Win32',
        clock: [1790506922024, 1790506922024],
        seeds: [2390, 6381, 5510],
        aBogus:
            'D7R0Q5wZp3xpkE6t5I5LfY3q6R-3YmZy0SVkMD2fqx3ziL39HMYY9exoUUJv3OujZsmfIFYjy4hbY3KdrQcbM1wfHWvx/2ADmDSkKl5Q5xSS'
            's1X9eyUgJUwOmktRSec25k3lEKi8qw5cSYmsWnAJ5kIlO62-zo0/9IR=',
      ),
    ];

    test('a_bogus equals 3.x', () {
      for (final vector in vectors) {
        final value = signer(
          fingerprint: vector.fingerprint,
          clock: vector.clock,
          seeds: vector.seeds,
        ).aBogus(vector.query);
        expect(value, vector.aBogus, reason: vector.query);
      }
    });

    test('every signature starts from the initial cipher table (3.x built a signer per request)', () {
      final vector = vectors[2];
      final shared = signer(fingerprint: vector.fingerprint, clock: vector.clock, seeds: vector.seeds);
      expect(shared.aBogus(vector.query), vector.aBogus);
      expect(shared.aBogus(vector.query), vector.aBogus);
    });

    test("signed URLs equal 3.x's buildRequestUrl, base query and a given msToken kept", () {
      final enter =
          signer(
            fingerprint: '1440|810|1466|895|0|30|0|0|1440|900|1440|860|1440|810|24|24|Win32',
            clock: [1790502760100, 1790502760103],
            seeds: [7, 9999, 4321],
          ).signedUrl(Uri.parse('https://live.douyin.com/webcast/room/web/enter/'), {
            'app_name': 'douyin_web',
            'enter_from': 'web_live',
            'live_id': '1',
            'web_rid': '547977714661',
            'is_need_double_stream': 'false',
            'msToken': 'fixed+token=',
          });
      expect(
        '$enter',
        'https://live.douyin.com/webcast/room/web/enter/?app_name=douyin_web&enter_from=web_live&live_id=1'
            '&web_rid=547977714661&is_need_double_stream=false&msToken=fixed%2Btoken%3D&aid=6383&compress=gzip'
            '&device_platform=web&browser_language=zh-CN&browser_platform=Win32&browser_name=Edge'
            '&browser_version=125.0.0.0&a_bogus=DjWhQDuZsn9ifj6b5I5LfY3q6AH3Ymgy0SVkMD2fpn3z2g39HMOL9exoUvJvydfjZsmfIFYjy'
            '4hbTpcprQcJ01wf984L/25/sfSkKl12so0j53inCy8mE0wN-hsAtePQsvr4EKi8o7/aSYmDAnAJ5kIlO62-zo0/94S=',
      );
      final partition =
          signer(
            fingerprint: '1024|768|1050|850|0|0|0|0|1024|768|1280|800|1024|768|24|24|Win32',
            clock: [1790502760000],
            seeds: [0, 1, 2],
          ).signedUrl(Uri.parse('https://live.douyin.com/webcast/web/partition/detail/room/v2/?existing=1'), {
            'aid': '6383',
            'count': '15',
            'offset': '15',
            'partition': '1',
            'partition_type': '1',
            'msToken': 'M',
          });
      expect(
        '$partition',
        'https://live.douyin.com/webcast/web/partition/detail/room/v2/?existing=1&aid=6383&count=15&offset=15'
            '&partition=1&partition_type=1&msToken=M&compress=gzip&device_platform=web&browser_language=zh-CN'
            '&browser_platform=Win32&browser_name=Edge&browser_version=125.0.0.0&a_bogus=DfmhQDgpkVEpDE6Y5I5LfY3q6We3Ymgy'
            '0SVkMD2ffd3z2g39HMTD9exoUvJvy88jZsmfIFujy4hbYpxZrQ29M1wfH8Xx/25dmDSkKl5Q5xSSs1Xre60gnt4PmktUCec2Rv3lrOX0qXMH'
            'KRjs09oHmhK4bIOwu3GM4j==',
      );
    });

    test('signedUrl copies the caller map (REG-DOUYIN-015), forces the browser fields, puts a_bogus last', () {
      final params = Map<String, String>.unmodifiable({'web_rid': '1', 'aid': '1'});
      final signer = DouyinSigner(userAgent: DouyinApi.userAgent, random: Random(3), now: () => _capturedAt);
      final base = Uri.parse('https://live.douyin.com/webcast/room/web/enter/?live_id=1');
      final first = signer.signedUrl(base, params);
      final second = signer.signedUrl(base, params);
      expect(params, {'web_rid': '1', 'aid': '1'});
      expect(first.queryParameters.keys, [
        'live_id',
        'web_rid',
        'aid',
        'compress',
        'device_platform',
        'browser_language',
        'browser_platform',
        'browser_name',
        'browser_version',
        'msToken',
        'a_bogus',
      ]);
      expect(first.queryParameters['aid'], '6383');
      expect(first.queryParameters['msToken'], matches(RegExp(r'^[A-Za-z0-9=]{184}$')));
      expect(first.queryParameters['msToken'], isNot(second.queryParameters['msToken']));
      expect(first.query, matches(RegExp(r'&a_bogus=[A-Za-z0-9/=-]+$')));
    });

    test("the danmaku signature equals 3.x's X-Bogus (r1, r2 injected)", () {
      for (final (roomId, user, r1, r2, expected) in [
        (_roomId, '7312345678901234567', 0, 0, 'fDpl4KiMGENF3YOy'),
        (_roomId, '7312345678901234567', 255, 254, '1eVnhJc1lIUrcoJk'),
        ('7382735338101328680', '7273033021933946427', 31, 100, '19wv2GETf0Rijd7D'),
        ('1', '7300000000000000000', 200, 17, 'wk407jV2/WLa1rdA'),
      ]) {
        final signer = DouyinSigner(userAgent: DouyinApi.userAgent, fingerprint: 'x', random: _Scripted([r1, r2]));
        expect(
          signer.danmakuSignature(roomId: roomId, userUniqueId: user),
          expected,
          reason: '$r1 $r2',
        );
      }
      final signer = DouyinSigner(userAgent: DouyinApi.userAgent, fingerprint: 'x', random: _Scripted([5, 77]));
      expect(signer.xBogus('d41d8cd98f00b204e9800998ecf8427e', counter: 2), 'v6ytTiUdP8gEsplH');
      expect(() => signer.xBogus('not md5'), throwsArgumentError);
    });

    test('the fingerprint stays inside 3.x ranges; msToken lengths are checked', () {
      for (var seed = 0; seed < 20; seed++) {
        final parts = DouyinSigner.browserFingerprint(Random(seed)).split('|');
        expect(parts, hasLength(17));
        final [innerW, innerH, outerW, outerH] = parts.take(4).map(int.parse).toList();
        expect(innerW, inInclusiveRange(1024, 1920));
        expect(innerH, inInclusiveRange(768, 1080));
        expect(outerW - innerW, inInclusiveRange(24, 32));
        expect(outerH - innerH, inInclusiveRange(75, 90));
        expect(parts[5], anyOf('0', '30'));
        expect(parts.last, 'Win32');
      }
      final signer = DouyinSigner(userAgent: DouyinApi.userAgent, random: Random(5));
      expect(signer.msToken(length: 256), matches(RegExp(r'^[A-Za-z0-9=]{256}$')));
      expect(() => signer.msToken(length: -1), throwsArgumentError);
    });

    test('the visitor id is 19 digits like the web client (7[3-9]…) and one per adapter (REG-DOUYIN-003)', () {
      for (var seed = 0; seed < 20; seed++) {
        expect(DouyinSigner.visitorId(Random(seed)), matches(RegExp(r'^7[3-9]\d{17}$')));
      }
      final site = DouyinSite(ReplayHttp(const []), random: Random(9));
      expect(site.visitorId, DouyinSigner.visitorId(Random(9)));
    });
  });

  group('anonymous session', () {
    test('one bootstrap for concurrent requests; only ttwid and UIFID_TEMP are kept', () async {
      final (:site, :http) = _replay(['S01-home', 'S02-feed', 'S04-enter-live']);
      await Future.wait([site.getRecommendRooms(), site.getRoomDetail(roomId: _webRid)]);
      expect(_paths(http).where((path) => path == _home), hasLength(1));
      expect(http.requests.first.headers.containsKey('cookie'), isFalse);
      final cookie = _anonymousCookie();
      expect(cookie, matches(RegExp(r'^ttwid=[^;]+; UIFID_TEMP=[^;]+$')));
      expect([for (final request in http.requests.skip(1)) request.headers['cookie']], [cookie, cookie]);
    });

    test('categories start the session themselves (one home page request, 3.x made two)', () async {
      final (:site, :http) = _replay(['S01-home', 'S02-feed']);
      final categories = await site.getCategories(1, 30);
      expect(categories.map((category) => category.name).take(3), ['聊天', '音乐', '游戏']);
      await site.getRecommendRooms();
      expect(_paths(http), [_home, _feed]);
      expect(http.requests.last.headers['cookie'], _anonymousCookie());
    });

    test('a cookie change switches at once and drops the anonymous session (REG-DOUYIN-017)', () async {
      final vault = MemoryCookieVault();
      addTearDown(vault.dispose);
      final (:site, :http) = _replay(['S01-home', 'S02-feed'], cookies: vault);
      await site.getRecommendRooms();
      vault.set('douyin', 'sessionid=abc; ttwid=user');
      await site.getRecommendRooms();
      vault.set('douyin', null);
      await site.getRecommendRooms();
      expect(_paths(http), [_home, _feed, _feed, _home, _feed]);
      expect(
        [for (final request in http.requests) request.headers['cookie']],
        [null, _anonymousCookie(), 'sessionid=abc; ttwid=user', null, _anonymousCookie()],
      );
    });

    test('a bootstrap that answers after the cookie changed is not used', () async {
      final vault = MemoryCookieVault();
      addTearDown(vault.dispose);
      final replay = ReplayHttp([ReplaySample.load('$_root/S01-home'), ReplaySample.load('$_root/S02-feed')]);
      final gate = Completer<void>();
      final site = DouyinSite(
        _GatedHttp(replay, (request) => request.url.path == '/' ? gate.future : null),
        cookies: vault,
        now: () => _capturedAt,
      );
      final feed = site.getRecommendRooms();
      await pumpEventQueue();
      expect(replay.requests, isEmpty, reason: 'the home page is held');
      vault.set('douyin', 'sessionid=abc');
      gate.complete();
      await feed;
      expect(replay.requests.last.headers['cookie'], 'sessionid=abc');
    });

    test('a home page without ttwid: requests go without a cookie; asked again after five minutes', () async {
      var now = _capturedAt;
      final (:site, :http) = _replay([_homeWithoutTtwid, 'S02-feed'], now: () => now);
      await site.getRecommendRooms();
      await site.getRecommendRooms();
      expect(_paths(http), [_home, _feed, _feed]);
      expect(http.requests.skip(1).map((request) => request.headers.containsKey('cookie')), [false, false]);
      now = now.add(const Duration(minutes: 5));
      await site.getRecommendRooms();
      expect(_paths(http).skip(3), [_home, _feed]);
    });

    test('a failed bootstrap sends the request without a cookie and is asked again next time', () async {
      final (:site, :http) = _replay([_fake('https://live.douyin.com/?from_nav=1', status: 503), 'S02-feed']);
      await site.getRecommendRooms();
      await site.getRecommendRooms();
      expect(_paths(http), [_home, _feed, _home, _feed]);
    });

    test('transport failures are NetworkFailure; cancellation passes through', () async {
      await expectLater(
        DouyinSite(_FailingHttp(TransportReason.connect)).getRoomDetail(roomId: _webRid),
        throwsA(isA<NetworkFailure>()),
      );
      await expectLater(
        DouyinSite(_FailingHttp(TransportReason.cancelled)).getRecommendRooms(),
        throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
      );
    });
  });

  group('catalog', () {
    const area = LiveArea(platform: 'douyin', areaId: '1,1', areaType: '103,4', typeName: '游戏', areaName: '射击游戏');

    test('area pages: signed like the recording, 15 per page whatever the page size', () async {
      final (:site, :http) = _replay(['S01-home', 'S03-partition-p1', 'S03-partition-p2', 'S03-partition-empty']);
      final first = await site.getCategoryRooms(area, pageSize: 40);
      expect(first, hasLength(15));
      expect(first.first.area, '无畏契约');
      expect(await site.getCategoryRooms(area, page: 2), isNotEmpty);
      expect(await site.getCategoryRooms(area, page: 101), isEmpty);
      final signed = http.requests[1];
      expect(signed.url.queryParameters.keys, Fixture.load('douyin', 'S03-partition-p1').url.queryParameters.keys);
      expect(signed.url.query, matches(RegExp(r'&a_bogus=[^&]+$')));
      expect(signed.url.queryParameters['msToken'], hasLength(184));
      expect(signed.headers, {
        'authority': 'live.douyin.com',
        'referer': 'https://live.douyin.com',
        'user-agent': DouyinApi.userAgent,
        'cookie': _anonymousCookie(),
      });
      expect([for (final request in http.requests.skip(1)) request.url.queryParameters['offset']], ['0', '15', '1500']);
    });

    test('a captcha on the signed request asks the unsigned amemv host once', () async {
      final signed = Fixture.load('douyin', 'S03-partition-p1').url;
      final amemv = Fixture.load('douyin', 'S08-partition-rooms-amemv').url;
      final (:site, :http) = _replay([
        'S01-home',
        _moved(
          'S08-partition-rooms-unsigned',
          signed.replace(queryParameters: {...signed.queryParameters, 'offset': '0'}),
        ),
        _moved(
          'S08-partition-rooms-amemv',
          amemv.replace(queryParameters: {...amemv.queryParameters, 'count': '15', 'partition': '1'}),
        ),
      ]);
      final rooms = await site.getCategoryRooms(area);
      expect(_paths(http), [_home, _partition, _amemvPartition]);
      expect(rooms, isNotEmpty);
      expect(rooms.every((room) => room.area == '射击游戏'), isTrue, reason: 'amemv has no tag_name');
    });

    test('a malformed area id is NotFound without a request', () async {
      final (:site, :http) = _replay(const []);
      await expectLater(
        site.getCategoryRooms(const LiveArea(platform: 'douyin', areaId: '1')),
        throwsA(isA<NotFound>()),
      );
      expect(http.requests, isEmpty);
    });

    test('recommendations: later pages give only rooms not delivered since page 1 (pure_live_TV)', () async {
      final (:site, :http) = _replay(['S01-home', 'S02-feed']);
      final first = await site.getRecommendRooms();
      expect(first, hasLength(20));
      expect(http.requests.last.url.queryParameters.containsKey('a_bogus'), isFalse);
      expect(await site.getRecommendRooms(page: 2), isEmpty, reason: 'the same draw: the list ends');
      expect(await site.getRecommendRooms(), hasLength(20), reason: 'a refresh starts over');
    });
  });

  group('search', () {
    final keyword = Fixture.load('douyin', 'S08-partition-search').url.queryParameters['keyword']!;
    final signedPartition = () {
      final amemv = Fixture.load('douyin', 'S08-partition-rooms-amemv').url;
      return amemv.replace(
        host: 'live.douyin.com',
        queryParameters: {
          ...amemv.queryParameters,
          'compress': 'gzip',
          'browser_name': 'Edge',
          'browser_version': '125.0.0.0',
        },
      );
    }();

    test("anonymous: 3.x's order, the matched partition's rooms as the result", () async {
      final (:site, :http) = _replay([
        'S01-home',
        'S08-live-search-anon',
        'S08-general-search-anon',
        'S08-partition-search',
        _moved('S08-partition-rooms-unsigned', signedPartition),
        'S08-partition-rooms-amemv',
      ]);
      final rooms = await site.searchRooms(' $keyword ');
      final legacy = Fixture.load('douyin', 'S08-partition-search').legacy as Map<String, dynamic>;
      expect(_paths(http).skip(1), [for (final request in legacy['requests'] as List) '$request']);
      final expected = (Fixture.load('douyin', 'S08-partition-rooms-amemv').legacy as Map)['rooms'] as List;
      expect(rooms.map((room) => room.roomId), [for (final room in expected) (room as Map)['roomId']]);
      expect(rooms.every((room) => room.area == '和平精英'), isTrue);
      final live = http.requests[1];
      expect(
        live.headers['referer'],
        'https://www.douyin.com/search/${Uri.encodeComponent(keyword)}?source=switch_tab&type=live',
      );
      expect(live.headers['cookie'], _anonymousCookie());
      expect(live.url.queryParameters.containsKey('a_bogus'), isFalse);
      expect(http.requests[4].url.query, matches(RegExp(r'&a_bogus=[^&]+$')), reason: '3.x sent it unsigned');
    });

    test('signed in: live search results end the search', () async {
      final vault = MemoryCookieVault()..set('douyin', 'sessionid=abc');
      addTearDown(vault.dispose);
      final live = Fixture.load('douyin', 'S08-live-search-anon').url;
      final (:site, :http) = _replay([
        _fake(
          live.replace(queryParameters: {...live.queryParameters, 'count': '20', 'offset': '20'}).toString(),
          body: {
            'status_code': 0,
            'data': [
              {
                'lives': {
                  'rawdata': jsonEncode({
                    'id_str': _roomId,
                    'status': 2,
                    'title': 't',
                    'owner': {'web_rid': _webRid, 'nickname': 'n'},
                  }),
                },
              },
            ],
          },
        ),
      ], cookies: vault);
      final rooms = await site.searchRooms(keyword, page: 2, pageSize: 20);
      expect(rooms.single.roomId, _webRid);
      expect(http.requests.single.headers['cookie'], 'sessionid=abc');
    });

    test('a blank keyword sends nothing; the page size is limited to 1–50', () async {
      final (:site, :http) = _replay(const []);
      expect(await site.searchRooms('  '), isEmpty);
      expect(http.requests, isEmpty);
      final vault = MemoryCookieVault()..set('douyin', 'sessionid=abc');
      addTearDown(vault.dispose);
      final live = Fixture.load('douyin', 'S08-live-search-anon').url;
      final clamped = _replay([
        _fake(
          live.replace(queryParameters: {...live.queryParameters, 'keyword': 'x', 'count': '50'}).toString(),
          body: {
            'status_code': 0,
            'data': [
              {'rawdata': '{"id_str":"9","status":2}'},
            ],
          },
        ),
      ], cookies: vault);
      expect(await clamped.site.searchRooms('x', pageSize: 999), hasLength(1));
    });

    test('no matching partition is no results; a failing fallback is reported', () async {
      final noMatch = _replay([
        'S01-home',
        'S08-live-search-anon',
        'S08-general-search-anon',
        _fake(
          Fixture.load('douyin', 'S08-partition-search').url.toString(),
          body: {
            'status_code': 0,
            'data': {'SearchResult': <Object>[]},
          },
        ),
      ]);
      expect(await noMatch.site.searchRooms(keyword), isEmpty);
      final failing = _replay([
        'S01-home',
        'S08-live-search-anon',
        'S08-general-search-anon',
        _fake(Fixture.load('douyin', 'S08-partition-search').url.toString(), status: 502),
      ]);
      await expectLater(failing.site.searchRooms(keyword), throwsA(isA<NetworkFailure>()));
    });

    test('the matched partitions as areas', () async {
      final (:site, :http) = _replay(['S01-home', 'S08-partition-search']);
      final areas = await site.searchAreas(keyword);
      expect(areas.map((area) => (area.areaId, area.areaName)), [('1010032,1', '和平精英')]);
      expect(await site.searchAreas(' '), isEmpty);
    });

    test('streamers: not supported, no request (3.x threw a message; the UI hides it)', () async {
      final (:site, :http) = _replay(const []);
      expect(await site.searchAnchors(keyword), isEmpty);
      expect(http.requests, isEmpty);
    });
  });

  group('rooms', () {
    test('enter: signed like the recording; the requested web_rid is the identity; danmaku arguments', () async {
      final (:site, :http) = _replay(['S01-home', 'S04-enter-live']);
      final room = await site.getRoomDetail(roomId: ' $_webRid ');
      expect(room.roomId, _webRid);
      expect(room.isLiveNow, isTrue);
      expect(room.link, 'https://live.douyin.com/$_webRid');
      final args = room.danmakuData! as DouyinDanmakuArgs;
      expect(
        (args.webRid, args.roomId, args.userId, args.cookie),
        (_webRid, _roomId, site.visitorId, _anonymousCookie()),
      );
      final data = room.data! as DouyinRoomData;
      expect((data.webRid, data.roomId, data.issuedAt), (_webRid, _roomId, _capturedAt));
      expect(data.streamUrl, isNotNull);
      expect(_paths(http), [_home, _enter]);
      final enter = http.requests.last;
      expect(enter.url.queryParameters.keys, Fixture.load('douyin', 'S04-enter-live').url.queryParameters.keys);
      expect(enter.url.query, matches(RegExp(r'&a_bogus=[^&]+$')));
      expect(enter.headers['user-agent'], DouyinApi.userAgent);
    });

    test('refresh: the same lookup without danmaku arguments; live status from it', () async {
      final (:site, :http) = _replay(['S01-home', 'S04-enter-live', 'S04-enter-offline']);
      final room = await site.getRoomDetailForRefresh(roomId: _webRid);
      expect(room.danmakuData, isNull);
      expect(room.isLiveNow, isTrue);
      expect(await site.getLiveStatus(roomId: '745964462470'), isFalse);
    });

    test('offline: a room state, not a failure; no stream', () async {
      final (:site, :http) = _replay(['S01-home', 'S04-enter-offline']);
      final room = await site.getRoomDetail(roomId: '745964462470');
      expect(room.isExplicitlyOfflineNow, isTrue);
      expect((room.data! as DouyinRoomData).streamUrl, isNull);
      await expectLater(site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
    });

    test('a room_id goes through reflow to the web_rid; an ended broadcast asks enter (REG-DOUYIN-013)', () async {
      final (:site, :http) = _replay(['S01-home', 'S05-reflow-live', 'S05-reflow-ended', 'S04-enter-offline']);
      final live = await site.getRoomDetail(roomId: _roomId);
      expect(live.roomId, _webRid, reason: 'a room_id is one broadcast; the web_rid is the room (3.x did the same)');
      expect((live.danmakuData! as DouyinDanmakuArgs).roomId, _roomId);
      expect(await site.getPlayQualities(detail: live), isNotEmpty);
      final ended = await site.getRoomDetail(roomId: '7376083140344859455');
      expect(ended.roomId, '745964462470');
      expect(ended.isExplicitlyOfflineNow, isTrue);
      expect(_paths(http), [_home, _reflow, _reflow, _enter]);
    });

    test('a missing room is NotFound without the page fallback (3.x ended in a failed HEAD)', () async {
      final (:site, :http) = _replay(['S01-home', 'S04-enter-notfound']);
      await expectLater(site.getRoomDetail(roomId: '999999999999'), throwsA(isA<NotFound>()));
      expect(_paths(http), [_home, _enter]);
      await expectLater(site.getRoomDetail(roomId: ' '), throwsA(isA<NotFound>()));
    });

    test('enter refused (empty 200 without ttwid): the room page answers, with its own visitor id', () async {
      final (:site, :http) = _replay([_homeWithoutTtwid, 'S04-enter-no-cookie', 'S06-room-html-live']);
      final room = await site.getRoomDetail(roomId: _webRid);
      expect(_paths(http), [_home, _enter, 'GET live.douyin.com/$_webRid']);
      expect(room.roomId, _webRid);
      expect(room.isLiveNow, isTrue);
      final legacy = (Fixture.load('douyin', 'S06-room-html-live').legacy as Map)['room'] as Map;
      expect((room.danmakuData! as DouyinDanmakuArgs).userId, (legacy['danmakuData'] as Map)['userId']);
      expect((room.danmakuData! as DouyinDanmakuArgs).roomId, _roomId);
      final qualities = await site.getPlayQualities(detail: room);
      expect(qualities.map((quality) => quality.id), ['origin', 'hd', 'sd', 'ld', 'md']);
      expect(http.requests, hasLength(3), reason: 'the streams come with the detail');
    });

    test('enter refused and a page without the room state: the refusal is reported', () async {
      final (:site, :http) = _replay([
        _homeWithoutTtwid,
        'S04-enter-no-cookie',
        _fake('https://live.douyin.com/$_webRid', body: '<html><body>verify</body></html>'),
      ]);
      await expectLater(site.getRoomDetailForRecording(roomId: _webRid), throwsA(isA<RiskControl>()));
      expect(_paths(http), [_home, _enter, 'GET live.douyin.com/$_webRid']);
    });
  });

  group('streams', () {
    test('qualities and lines come with the detail: media headers with the cookie, leases, codec', () async {
      final (:site, :http) = _replay(['S01-home', 'S04-enter-live-portrait']);
      final room = await site.getRoomDetail(roomId: '153806988623');
      final qualities = await site.getPlayQualities(detail: room);
      final legacy = (Fixture.load('douyin', 'S04-enter-live-portrait').legacy as Map)['qualities'] as List;
      expect(qualities.map((quality) => quality.id), [for (final quality in legacy) (quality as Map)['id']]);
      final resolution = await site.resolvePlayUrls(detail: room, quality: qualities.first);
      expect(resolution.urls, qualities.first.data);
      expect(resolution.appliedQualityData, 'origin');
      for (final line in resolution.lines) {
        expect(line.headers, {
          'user-agent': DouyinApi.userAgent,
          'origin': 'https://live.douyin.com',
          'referer': 'https://live.douyin.com/153806988623',
          'cookie': _anonymousCookie(),
        });
        expect(line.codec, 'avc');
        expect(line.lease!.expiresAt!.isAfter(_capturedAt), isTrue);
      }
      expect(await site.getPlayUrls(detail: room, quality: qualities.last), qualities.last.data);
      expect(_paths(http), [_home, _enter]);
    });

    test("a signed-in cookie goes to the media requests too, as 3.x's player sent it", () async {
      final vault = MemoryCookieVault()..set('douyin', 'sessionid=abc');
      addTearDown(vault.dispose);
      final (:site, :http) = _replay(['S04-enter-live'], cookies: vault);
      final room = await site.getRoomDetail(roomId: _webRid);
      final resolution = await site.resolvePlayUrls(
        detail: room,
        quality: (await site.getPlayQualities(detail: room)).first,
      );
      expect(http.requests.single.headers['cookie'], 'sessionid=abc');
      expect(resolution.lines.every((line) => line.headers['cookie'] == 'sessionid=abc'), isTrue);
    });

    test('a room without stream data (a follow card) fetches its detail first', () async {
      final (:site, :http) = _replay(['S01-home', 'S04-enter-live']);
      final qualities = await site.getPlayQualities(
        detail: LiveRoom(platform: 'douyin', roomId: _webRid),
      );
      expect(qualities.first.id, 'origin');
      expect(_paths(http), [_home, _enter]);
    });

    test('recovery fetches the detail again; a quality no longer offered falls back to the best', () async {
      final (:site, :http) = _replay(['S01-home', 'S04-enter-live']);
      final room = await site.getRoomDetail(roomId: _webRid);
      final qualities = await site.getPlayQualities(detail: room);
      final fresh = await site.resolvePlayUrlsForRecovery(detail: room, quality: qualities[1]);
      expect(fresh.appliedQualityData, qualities[1].id);
      expect(fresh.urls, qualities[1].data);
      final gone = await site.resolvePlayUrlsForRecovery(
        detail: room,
        quality: const LivePlayQuality(quality: 'x', id: 'gone', data: ['https://stale.test/x.flv']),
      );
      expect(gone.appliedQualityData, 'origin');
      expect(gone.urls, isNot(contains('https://stale.test/x.flv')));
      expect(_paths(http), [_home, _enter, _enter, _enter]);
    });

    test('recovery of an offline room is StreamUnavailable', () async {
      final (:site, :http) = _replay(['S01-home', 'S04-enter-offline']);
      await expectLater(
        site.resolvePlayUrlsForRecovery(
          detail: LiveRoom(platform: 'douyin', roomId: '745964462470'),
          quality: const LivePlayQuality(quality: '原画', id: 'origin'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
    });
  });

  group('links', () {
    ({LinkParser parser, ReplayHttp http}) links(List<Object> samples) {
      final http = ReplayHttp([
        for (final sample in samples)
          if (sample is String) ReplaySample.load('$_root/$sample') else sample as ReplaySample,
      ]);
      final registry = SiteRegistry({'douyin': () => DouyinSite(http, now: () => _capturedAt)});
      return (parser: LinkParser(registry, http), http: http);
    }

    ReplaySample redirect(String from, String location, {int status = 302}) => _fake(
      from,
      status: status,
      headers: {
        'location': [location],
      },
    );

    test("3.x's room links need no request; videos, search pages and bare sites are not rooms", () async {
      final (:parser, :http) = links(const []);
      for (final (input, roomId) in [
        ('https://live.douyin.com/123/', '123'),
        ('https://live.douyin.com/123456', '123456'),
        ('https://live.douyin.com/$_webRid?from=search&enter_from=link_share', _webRid),
        ('【小央视频】正在直播，来和我一起支持Ta吧。https://live.douyin.com/$_webRid，快来', _webRid),
        ('https://www.douyin.com/123?source=share', '123'),
      ]) {
        expect(await parser.parse(input), RoomLink('douyin', roomId), reason: input);
      }
      for (final input in [
        'https://www.douyin.com/',
        'https://www.douyin.com/search/123?type=live',
        'https://www.douyin.com/video/123',
        'https://live.douyin.com/',
        'https://live.douyin.com/abc',
        'https://example.org/?next=https://v.douyin.com/abc',
        'https://v.douyin.com/',
      ]) {
        expect(await parser.parse(input), isNull, reason: input);
        expect(parser.containsSupportedLink(input), isFalse, reason: input);
      }
      expect(http.requests, isEmpty);
      for (final input in [
        'https://live.douyin.com/123',
        'https://www.douyin.com/123?source=share',
        'https://v.douyin.com/AbCd/',
        'https://webcast.amemv.com/douyin/webcast/reflow/123',
      ]) {
        expect(parser.containsSupportedLink(input), isTrue, reason: input);
      }
    });

    test('a short link to a room page ends there (one request, no redirect following)', () async {
      final (:parser, :http) = links([redirect('https://v.douyin.com/fixture', 'https://live.douyin.com/456')]);
      expect(await parser.parse('https://v.douyin.com/fixture'), const RoomLink('douyin', '456'));
      expect(http.requests, hasLength(1));
      expect(http.requests.single.followRedirects, isFalse);
      expect(http.requests.single.headers.containsKey('cookie'), isFalse);
    });

    test('a short link to reflow asks for the owner web_rid (S05-reflow-shortlink-live)', () async {
      final fixture = Fixture.load('douyin', 'S05-reflow-shortlink-live');
      final shareUrl = (((jsonDecode(fixture.body) as Map)['data'] as Map)['room'] as Map)['share_url'] as String;
      final (:parser, :http) = links([
        redirect('https://v.douyin.com/fixture/', shareUrl),
        'S05-reflow-shortlink-live',
      ]);
      const share = '7- 长按复制此条消息，打开抖音搜索，查看TA的更多作品。 https://v.douyin.com/fixture/ 1@2.com :9pm';
      final legacy = (fixture.legacy as Map)['result'] as List;
      expect(await parser.parse(share), RoomLink(legacy[1] as String, legacy[0] as String));
      expect(_paths(http), [for (final request in (fixture.legacy as Map)['requests'] as List) '$request']);
      expect(http.requests.last.url.queryParameters['app_id'], '1128');
    });

    test("3.x's reflow case: room 123 of reflow is owner 456", () async {
      final (:parser, :http) = links([
        redirect('https://v.douyin.com/fixture', 'https://webcast.amemv.com/douyin/webcast/reflow/123'),
        _fake(
          'https://webcast.amemv.com/webcast/room/reflow/info/?room_id=123&verifyFp=&type_id=0&live_id=1&sec_user_id=&app_id=1128',
          body: '{"data":{"room":{"owner":{"web_rid":"456"}}}}',
        ),
      ]);
      expect(await parser.parse('https://v.douyin.com/fixture'), const RoomLink('douyin', '456'));
      expect(http.requests, hasLength(2));
      expect(http.requests.last.url.path, '/webcast/room/reflow/info/');
    });

    for (final payload in [
      'null',
      '[]',
      '{}',
      '{"data":[]}',
      '{"data":{"room":null}}',
      '{"data":{"room":{"owner":{}}}}',
      '{"data":{"room":{"owner":{"web_rid":[]}}}}',
      '{"data":{"room":{"owner":{"web_rid":"not-a-room"}}}}',
      'not json',
    ]) {
      test('malformed reflow info after a short link is no room: $payload', () async {
        final (:parser, :http) = links([
          redirect('https://v.douyin.com/fixture', 'https://webcast.amemv.com/reflow/123'),
          _fake(
            'https://webcast.amemv.com/webcast/room/reflow/info/?room_id=123&verifyFp=&type_id=0&live_id=1&sec_user_id=&app_id=1128',
            body: payload,
          ),
        ]);
        expect(await parser.parse('https://v.douyin.com/fixture'), isNull);
        expect(http.requests, hasLength(2));
      });
    }

    for (final location in [
      'ftp://www.huya.com/123',
      'https://user@live.douyin.com/123',
      'https://example.org/reflow/123',
      'https://[broken',
      '',
    ]) {
      test('a short link to an invalid or unrelated Location is not followed: "$location"', () async {
        final (:parser, :http) = links([redirect('https://v.douyin.com/fixture', location)]);
        expect(await parser.parse('https://v.douyin.com/fixture'), isNull);
        expect(http.requests, hasLength(1));
      });
    }

    test('relative redirects are resolved; loops stop; the request budget holds', () async {
      final relative = links([
        redirect('https://v.douyin.com/a/', '/b/'),
        redirect('https://v.douyin.com/b/', 'https://live.douyin.com/$_webRid?enter_from=share', status: 301),
      ]);
      expect(await relative.parser.parse('https://v.douyin.com/a/'), const RoomLink('douyin', _webRid));
      expect(relative.http.requests.map((request) => request.url.path), ['/a/', '/b/']);

      final loop = links([
        redirect('https://v.douyin.com/loop/', 'https://v.douyin.com/back/'),
        redirect('https://v.douyin.com/back/', 'https://v.douyin.com/loop/#again'),
      ]);
      expect(await loop.parser.parse('https://v.douyin.com/loop/'), isNull);
      expect(loop.http.requests, hasLength(2));

      final chain = links([
        for (var i = 0; i < 12; i++) redirect('https://v.douyin.com/n$i', 'https://v.douyin.com/n${i + 1}'),
      ]);
      expect(await chain.parser.parse('https://v.douyin.com/n0'), isNull);
      expect(chain.http.requests.length, lessThanOrEqualTo(ShortLinkSession.maxRequests));
    });

    test('a short link through www.douyin.com: a room ends it, another page is followed as in 3.x', () async {
      final room = links([redirect('https://v.douyin.com/w', 'https://www.douyin.com/$_webRid')]);
      expect(await room.parser.parse('https://v.douyin.com/w'), const RoomLink('douyin', _webRid));
      expect(room.http.requests, hasLength(1));
      final video = links([
        redirect('https://v.douyin.com/v', 'https://www.douyin.com/video/7300000000000000000'),
        _fake('https://www.douyin.com/video/7300000000000000000', body: '<html></html>'),
      ]);
      expect(await video.parser.parse('https://v.douyin.com/v'), isNull);
      expect(video.http.requests, hasLength(2));
    });

    test('a direct reflow link is turned into the web_rid; when that fails, the room_id as 3.x', () async {
      final resolved = links(['S05-reflow-shortlink-live']);
      expect(
        await resolved.parser.parse('https://webcast.amemv.com/douyin/webcast/reflow/$_roomId?u_code=x'),
        const RoomLink('douyin', _webRid),
      );
      final failed = links([
        _fake(
          'https://webcast.amemv.com/webcast/room/reflow/info/?room_id=123&verifyFp=&type_id=0&live_id=1&sec_user_id=&app_id=1128',
          status: 404,
        ),
      ]);
      expect(
        await failed.parser.parse('https://webcast.amemv.com/douyin/webcast/reflow/123?source=share'),
        const RoomLink('douyin', '123'),
      );
    });
  });

  group('account', () {
    test('NeedsLogin without a request when signed out, and for a cookie that is not signed in', () async {
      final vault = MemoryCookieVault();
      addTearDown(vault.dispose);
      final (:site, :http) = _replay(['S09-user-me-invalid-cookie'], cookies: vault);
      await expectLater(site.account(), throwsA(isA<NeedsLogin>()));
      expect(http.requests, isEmpty);
      vault.set('douyin', 'sessionid=expired\n');
      await expectLater(site.account(), throwsA(isA<NeedsLogin>()));
      expect(http.requests.single.headers, {
        'user-agent': DouyinApi.userAgent,
        'accept': 'application/json, text/plain, */*',
        'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'cookie': 'sessionid=expired',
      });
    });

    test('a signed-in cookie gives the nickname', () async {
      final (:site, :http) = _replay([
        _fake(
          'https://live.douyin.com/webcast/user/me/?aid=6383',
          body: {
            'status_code': 0,
            'data': {'nickname': '主播'},
          },
        ),
      ]);
      expect(await site.account(cookie: 'sessionid=ok'), '主播');
    });
  });
}
