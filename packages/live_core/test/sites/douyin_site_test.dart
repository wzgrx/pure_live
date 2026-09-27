// DouyinSite end to end over the recorded Douyin responses (ReplayHttp),
// the a_bogus port against vectors computed with the legacy implementation
// (lib/core/utils/douyin/abogus.dart), and the session, link and error
// rules. msToken and a_bogus are scrubbed in the samples, so they are left
// out of request matching. No test touches the network.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_core/src/sites/douyin/douyin_sign.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/douyin';
const _ignored = {'msToken', 'a_bogus'};
const _webRid = '547977714661';
const _roomId = '7687741736843512602';

final DateTime _capturedAt = Fixture.load('douyin', 'S04-enter-live').capturedAt;

/// A made-up response for exchanges without a recording (redirects, pages).
ReplaySample _fake(String url, {int status = 200, Map<String, List<String>> headers = const {}, String body = ''}) =>
    ReplaySample(method: 'GET', url: Uri.parse(url), status: status, headers: headers, bytes: utf8.encode(body));

/// The home page without Set-Cookie: no anonymous session.
final ReplaySample _homeWithoutTtwid = _fake('https://live.douyin.com/?from_nav=1', body: '<html></html>');

({DouyinSite site, ReplayHttp http}) _replay(List<Object> samples, {CookieVault? cookies}) {
  final http = ReplayHttp([
    for (final sample in samples)
      if (sample is String) ReplaySample.load('$_root/$sample') else sample as ReplaySample,
  ], ignoredQuery: _ignored);
  return (site: DouyinSite(http, cookies: cookies, now: () => _capturedAt, random: Random(1)), http: http);
}

List<String> _paths(ReplayHttp http) => [
  for (final request in http.requests) '${request.method} ${request.url.host}${request.url.path}',
];

const _home = 'GET live.douyin.com/';
const _feed = 'GET live.douyin.com/webcast/feed/';
const _enter = 'GET live.douyin.com/webcast/room/web/enter/';
const _reflow = 'GET webcast.amemv.com/webcast/room/reflow/info/';

/// The anonymous cookie the recorded home page sets (ttwid and UIFID_TEMP).
String _anonymousCookie() {
  final headers = (Fixture.load('douyin', 'S01-home').meta['response'] as Map<String, dynamic>)['headers'] as Map;
  return [
    for (final line in (headers['set-cookie'] as List).cast<String>())
      if (line.startsWith('ttwid=') || line.startsWith('UIFID_TEMP=')) line.split(';').first,
  ].join('; ');
}

/// Hands out scripted values (the a_bogus random prefix).
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
  void close() {}
}

/// Fails every request at the transport level.
final class _FailingHttp implements LiveHttp {
  new(this.reason);

  final TransportReason reason;

  @override
  Future<LiveResponse> send(LiveRequest request) async => throw TransportFailure(request.site, reason);

  @override
  void close() {}
}

void main() {
  group('a_bogus port', () {
    String hex(List<int> bytes) => [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join();

    test('SM3 matches the GB/T 32905-2016 examples', () {
      expect(
        hex(DouyinSigner.sm3(utf8.encode('abc'))),
        '66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0',
      );
      expect(
        hex(DouyinSigner.sm3(utf8.encode('abcd' * 16))),
        'debe9ff92275b8a138604889c18e5a4d6fdb70e5387e5765293dcba39c0c5732',
      );
    });

    // Computed by running the legacy ABogus (Chrome 134 UA, fixed
    // fingerprint) and recovering its clock and random prefix from the
    // output; the port reproduces each value from those inputs.
    const vectors = [
      (
        query: '',
        fingerprint: '1536|747|1560|835|0|30|0|0|1920|1040|1920|1040|1536|747|24|24|Win32',
        start: 1790506922004,
        end: 1790506922008,
        seeds: [1104, 4190, 3186],
        aBogus:
            'DXmhBDzIk3EN6Eyu5I5LfY3q6fe3YmZy0SVkMD2fvx3ziL39HMY69exoUUJv3TujZsmfIFEjy4hbT3ohrQ2y8qwf9W4x/25gsfSkKl12so0j'
            '53intL6mE0hN5kb3SFlm5XNAEOk0y75CFRJ0l2CymhK4bfebY7Y6i6trHD==',
      ),
      (
        query: 'a=1',
        fingerprint: '1920|1080|1944|1165|0|0|0|0|1024|768|1280|800|1920|1080|24|24|Win32',
        start: 1790506922020,
        end: 1790506922021,
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
        start: 1790506922022,
        end: 1790506922023,
        seeds: [497, 9689, 1428],
        aBogus:
            'YX8hQRw3sV9khE6z5I5LfY3q6AP3YmZy0SVkMD2fRx3ziL39HMYo9exoUUJv3OfjZsmfIFYjy4hbYNQprQ2n01wfHSkO/25ZsfSkKl12so0j'
            '53inC6WmE0wN-hsAtlaQsvr4EKi8qXCaSYypAnAJ5kIlO62-zo0/9lW=',
      ),
      (
        query: 'keyword=%E5%92%8C%E5%B9%B3+x&offset=0',
        fingerprint: '1111|888|1140|970|0|0|0|0|1500|999|1700|1000|1111|888|24|24|Win32',
        start: 1790506922024,
        end: 1790506922024,
        seeds: [2390, 6381, 5510],
        aBogus:
            'D7R0Q5wZp3xpkE6t5I5LfY3q6R-3YmZy0SVkMD2fqx3ziL39HMYY9exoUUJv3OujZsmfIFYjy4hbY3KdrQcbM1wfHWvx/2ADmDSkKl5Q5xSS'
            's1X9eyUgJUwOmktRSec25k3lEKi8qw5cSYmsWnAJ5kIlO62-zo0/9IR=',
      ),
    ];

    DouyinSigner signer(({int start, int end, String fingerprint, List<int> seeds}) vector) {
      var calls = 0;
      return DouyinSigner(
        userAgent: DouyinParse.userAgent,
        fingerprint: vector.fingerprint,
        now: () => DateTime.fromMillisecondsSinceEpoch((calls++).isEven ? vector.start : vector.end),
        random: _Scripted(vector.seeds),
      );
    }

    test('a_bogus equals the legacy implementation', () {
      for (final vector in vectors) {
        final value = signer((
          start: vector.start,
          end: vector.end,
          fingerprint: vector.fingerprint,
          seeds: vector.seeds,
        )).aBogus(vector.query);
        expect(value, vector.aBogus, reason: vector.query);
      }
    });

    test('every signature starts from the initial cipher table (legacy built a signer per request)', () {
      final vector = vectors[2];
      final shared = signer((
        start: vector.start,
        end: vector.end,
        fingerprint: vector.fingerprint,
        seeds: vector.seeds,
      ));
      expect(shared.aBogus(vector.query), vector.aBogus);
      expect(shared.aBogus(vector.query), vector.aBogus);
    });

    test('msToken: 184 characters of A–Z a–z 0–9 =', () {
      final token = DouyinSigner(userAgent: DouyinParse.userAgent, random: Random(5)).msToken();
      expect(token, matches(RegExp(r'^[A-Za-z0-9=]{184}$')));
    });

    test('the fingerprint stays inside the legacy ranges', () {
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
    });

    test('signedUrl copies the caller map (REG-DOUYIN-015), forces the browser fields, puts a_bogus last', () {
      final params = Map<String, String>.unmodifiable({'web_rid': '1', 'aid': '1'});
      final signer = DouyinSigner(userAgent: DouyinParse.userAgent, random: Random(3), now: () => _capturedAt);
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
      expect(first.queryParameters['msToken'], hasLength(184));
      expect(first.queryParameters['msToken'], isNot(second.queryParameters['msToken']));
      expect(first.query, contains('msToken=${Uri.encodeQueryComponent(first.queryParameters['msToken']!)}&a_bogus='));
    });

    test('a_bogus signs exactly the query that is sent; a given msToken is kept', () {
      const fingerprint = '1536|747|1560|835|0|30|0|0|1920|1040|1920|1040|1536|747|24|24|Win32';
      DouyinSigner fresh() => DouyinSigner(
        userAgent: DouyinParse.userAgent,
        fingerprint: fingerprint,
        now: () => _capturedAt,
        random: _Scripted([1, 2, 3]),
      );
      final url = fresh().signedUrl(Uri.parse('https://live.douyin.com/x/'), {'msToken': 'a=b', 'q': '和 平'});
      final query = url.query.substring(0, url.query.lastIndexOf('&a_bogus='));
      expect(query, contains('msToken=a%3Db'));
      expect(query, contains('q=%E5%92%8C+%E5%B9%B3'));
      expect(url.query.substring(query.length), '&a_bogus=${fresh().aBogus(query)}');
    });
  });

  group('session', () {
    test('one anonymous bootstrap for concurrent requests; only ttwid and UIFID_TEMP are kept', () async {
      final (:site, :http) = _replay(['S01-home', 'S02-feed']);
      await Future.wait([site.recommended(), site.recommended()]);
      expect(_paths(http), [_home, _feed, _feed]);
      expect(http.requests.first.headers.containsKey('cookie'), isFalse);
      final cookie = _anonymousCookie();
      expect(cookie, matches(RegExp(r'^ttwid=[^;]+; UIFID_TEMP=[^;]+$')));
      expect([for (final request in http.requests.skip(1)) request.headers['cookie']], [cookie, cookie]);
      expect(await site.sessionCookie(), cookie);
    });

    test('categories start the session themselves (one home page request)', () async {
      final (:site, :http) = _replay(['S01-home', 'S02-feed']);
      final categories = await site.categories();
      expect(categories.map((c) => c.name).take(3), ['聊天', '音乐', '游戏']);
      expect(categories.every((c) => c.areas.first.id == c.id), isTrue);
      await site.recommended();
      expect(_paths(http), [_home, _feed]);
      expect(http.requests.last.headers['cookie'], _anonymousCookie());
    });

    test('a vault change switches the cookie at once and drops the anonymous session (REG-DOUYIN-017)', () async {
      final vault = MemoryCookieVault();
      final (:site, :http) = _replay(['S01-home', 'S02-feed'], cookies: vault);
      await site.recommended();
      vault.set('douyin', 'sessionid=abc; ttwid=user');
      await site.recommended();
      expect(await site.sessionCookie(), 'sessionid=abc; ttwid=user');
      vault.set('douyin', null);
      await site.recommended();
      expect(_paths(http), [_home, _feed, _feed, _home, _feed]);
      expect(
        [for (final request in http.requests) request.headers['cookie']],
        [null, _anonymousCookie(), 'sessionid=abc; ttwid=user', null, _anonymousCookie()],
      );
      await vault.dispose();
    });

    test('a bootstrap that answers after the vault changed is not used', () async {
      final vault = MemoryCookieVault();
      final replay = ReplayHttp([ReplaySample.load('$_root/S01-home'), ReplaySample.load('$_root/S02-feed')]);
      final gate = Completer<void>();
      final site = DouyinSite(
        _GatedHttp(replay, (request) => request.url.path == '/' ? gate.future : null),
        cookies: vault,
        now: () => _capturedAt,
        random: Random(1),
      );
      final feed = site.recommended();
      await pumpEventQueue();
      expect(_paths(replay), isEmpty, reason: 'the home page is held');
      vault.set('douyin', 'sessionid=abc');
      gate.complete();
      await feed;
      expect(replay.requests.last.headers['cookie'], 'sessionid=abc');
      vault.set('douyin', null);
      await site.recommended();
      expect(_paths(replay), [_home, _feed, _home, _feed], reason: 'the late anonymous cookie was not kept');
      await vault.dispose();
    });

    test('a home page without ttwid: requests go without a cookie, the bootstrap is not repeated at once', () async {
      final (:site, :http) = _replay([_homeWithoutTtwid, 'S02-feed']);
      await site.recommended();
      await site.recommended();
      expect(_paths(http), [_home, _feed, _feed]);
      expect(http.requests.skip(1).map((request) => request.headers.containsKey('cookie')), [false, false]);
    });

    test('transport failures are NetworkFailure; cancellation passes through', () async {
      await expectLater(
        DouyinSite(_FailingHttp(TransportReason.connect)).recommended(),
        throwsA(isA<NetworkFailure>()),
      );
      await expectLater(
        DouyinSite(_FailingHttp(TransportReason.cancelled)).recommended(),
        throwsA(isA<TransportFailure>()),
      );
    });

    test('the visitor id is 19 digits like the web client (7[3-9]…) and the same for every room', () {
      final site = DouyinSite(ReplayHttp(const []), random: Random(9));
      expect(site.visitorId, matches(RegExp(r'^7[3-9]\d{17}$')));
      expect(DouyinSite.newVisitorId(Random(9)), site.visitorId);
    });
  });

  group('catalog and search', () {
    test('feed: one page of live rooms with the API headers, unsigned', () async {
      final (:site, :http) = _replay(['S01-home', 'S02-feed']);
      final page = await site.recommended();
      expect(page.items, isNotEmpty);
      expect(page.isLast, isTrue);
      expect(page.items.every((room) => room.state == LiveState.live), isTrue);
      final request = http.requests.last;
      expect(request.headers['user-agent'], DouyinParse.userAgent);
      expect(request.headers['referer'], 'https://live.douyin.com');
      expect(request.url.queryParameters.containsKey('a_bogus'), isFalse);
      expect((await site.recommended(cursor: const PageCursor('x'))).items, isEmpty);
      expect(http.requests, hasLength(2));
    });

    test('partition pages: signed like the recording, offset cursor, end when data.count is 0', () async {
      final (:site, :http) = _replay(['S01-home', 'S03-partition-p1', 'S03-partition-p2', 'S03-partition-empty']);
      const area = Area(id: '1,1', name: '热门', categoryId: '1,1');
      final first = await site.areaRooms(area);
      expect(first.items, hasLength(15));
      expect(first.items.first.area, '无畏契约');
      expect(first.next, const PageCursor('15'));
      final second = await site.areaRooms(area, cursor: first.next);
      expect(second.items, isNotEmpty);
      expect(second.next, const PageCursor('30'));
      final end = await site.areaRooms(area, cursor: const PageCursor('1500'));
      expect(end.items, isEmpty);
      expect(end.isLast, isTrue);

      final signed = http.requests[1].url;
      expect(signed.queryParameters.keys, Fixture.load('douyin', 'S03-partition-p1').url.queryParameters.keys);
      expect(signed.query, matches(RegExp(r'&a_bogus=[^&]+$')));
      expect(signed.queryParameters['msToken'], hasLength(184));
      expect(http.requests[1].headers['cookie'], _anonymousCookie());
    });

    test('a partition captcha falls back once to the unsigned amemv host', () async {
      final signedUrl = Fixture.load('douyin', 'S03-partition-p1').url;
      final captcha = ReplaySample.load('$_root/S08-partition-rooms-unsigned');
      final (:site, :http) = _replay([
        'S01-home',
        ReplaySample(
          method: 'GET',
          url: signedUrl.replace(queryParameters: {...signedUrl.queryParameters, 'partition': '1010032'}),
          status: captcha.status,
          headers: captcha.headers,
          bytes: captcha.bytes,
        ),
        'S08-partition-rooms-amemv',
      ]);
      final page = await site.areaRooms(const Area(id: '1010032,1', name: '和平精英', categoryId: ''));
      expect(_paths(http), [
        _home,
        'GET live.douyin.com/webcast/web/partition/detail/room/v2/',
        'GET webcast.amemv.com/webcast/web/partition/detail/room/v2/',
      ]);
      expect(page.items, isNotEmpty);
      expect(page.items.every((room) => room.area == '和平精英'), isTrue);
      expect(page.next, const PageCursor('20'));
    });

    test('search: anonymous live search is NeedsLogin; name-matched partitions are separate', () async {
      final (:site, :http) = _replay(['S01-home', 'S08-live-search-anon', 'S08-partition-search']);
      final keyword = Fixture.load('douyin', 'S08-live-search-anon').url.queryParameters['keyword']!;
      await expectLater(site.search(' $keyword '), throwsA(isA<NeedsLogin>()));
      final request = http.requests.last;
      expect(
        request.headers['referer'],
        'https://www.douyin.com/search/${Uri.encodeComponent(keyword)}?source=switch_tab&type=live',
      );
      expect(request.headers['origin'], 'https://www.douyin.com');
      expect(request.url.queryParameters.containsKey('a_bogus'), isFalse);
      final areas = await site.searchAreas(keyword);
      expect(areas.map((area) => (area.id, area.name)), [('1010032,1', '和平精英')]);
      expect((await site.search('  ')).items, isEmpty);
      expect(http.requests, hasLength(3));
    });

    test('account: NeedsLogin without a request when signed out, and for a cookie that is not signed in', () async {
      final vault = MemoryCookieVault();
      final (:site, :http) = _replay(['S09-user-me-invalid-cookie'], cookies: vault);
      await expectLater(site.accountName(), throwsA(isA<NeedsLogin>()));
      expect(http.requests, isEmpty);
      vault.set('douyin', 'Cookie: sessionid=expired; sid_tt=expired\n');
      await expectLater(site.accountName(), throwsA(isA<NeedsLogin>()));
      expect(http.requests.single.headers['cookie'], 'sessionid=expired; sid_tt=expired');
      expect(http.requests.single.headers['accept-language'], 'zh-CN,zh;q=0.9,en;q=0.8');
      await vault.dispose();
    });
  });

  group('rooms and streams', () {
    test('enter (live): signed like the recording, web_rid identity, danmaku keys', () async {
      final (:site, :http) = _replay(['S01-home', 'S04-enter-live']);
      final detail = await site.detail(RoomRef('douyin', _webRid));
      expect(detail.ref, RoomRef('douyin', _webRid));
      expect(detail.state, LiveState.live);
      expect(detail.card.anchorName, '小央视频');
      expect(detail.link, Uri.parse('https://live.douyin.com/$_webRid'));
      expect(detail.danmakuKeys, {'webRid': _webRid, 'roomId': _roomId, 'userUniqueId': site.visitorId});
      expect(_paths(http), [_home, _enter]);
      final enter = http.requests.last;
      expect(enter.url.queryParameters.keys, Fixture.load('douyin', 'S04-enter-live').url.queryParameters.keys);
      expect(enter.url.query, matches(RegExp(r'&a_bogus=[^&]+$')));
      expect(enter.headers['cookie'], _anonymousCookie());
      expect(enter.headers['user-agent'], DouyinParse.userAgent);
    });

    test('streams reuse the detail just fetched once, then fetch it again; no cookie on media', () async {
      final (:site, :http) = _replay(['S01-home', 'S04-enter-live-portrait']);
      const webRid = '153806988623';
      final detail = await site.detail(RoomRef('douyin', webRid));
      final set = await site.streams(detail);
      expect(_paths(http), [_home, _enter]);
      expect(set.selected.id, 'origin');
      expect(set.lines.map((line) => (line.format, line.lineId)), [
        (StreamFormat.flv, 'flv'),
        (StreamFormat.hls, 'hls'),
      ]);
      for (final line in set.lines) {
        expect(line.headers, {
          'user-agent': DouyinParse.userAgent,
          'origin': 'https://live.douyin.com',
          'referer': 'https://live.douyin.com/$webRid',
        });
        expect(line.lease!.cutsConnection, isFalse);
        expect(line.lease!.expiresAt!.isAfter(_capturedAt), isTrue);
      }
      final lowest = await site.streams(detail, quality: set.qualities.last);
      expect(lowest.selected, set.qualities.last);
      expect(_paths(http), [_home, _enter, _enter]);
    });

    test('a user cookie goes to the API but never to media hosts', () async {
      final vault = MemoryCookieVault()..set('douyin', 'sessionid=abc');
      final (:site, :http) = _replay(['S04-enter-live'], cookies: vault);
      final set = await site.streams(await site.detail(RoomRef('douyin', _webRid)));
      expect(http.requests.single.headers['cookie'], 'sessionid=abc');
      expect(set.lines.every((line) => !line.headers.containsKey('cookie')), isTrue);
      await vault.dispose();
    });

    test('enter (offline): a room state, not a failure; streams are StreamUnavailable', () async {
      final (:site, :http) = _replay(['S01-home', 'S04-enter-offline']);
      final detail = await site.detail(RoomRef('douyin', '745964462470'));
      expect(detail.state, LiveState.offline);
      expect(detail.card.anchorName, '喜剧电影笑不停');
      expect(detail.card.audience, Audience.none);
      await expectLater(site.streams(detail), throwsA(isA<StreamUnavailable>()));
      await expectLater(site.streams(detail), throwsA(isA<StreamUnavailable>()));
      expect(_paths(http), [_home, _enter, _enter]);
    });

    test('enter (not found): NotFound without the room-page fallback', () async {
      final (:site, :http) = _replay(['S01-home', 'S04-enter-notfound']);
      await expectLater(site.detail(RoomRef('douyin', '999999999999')), throwsA(isA<NotFound>()));
      expect(_paths(http), [_home, _enter]);
    });

    test('enter refused (empty 200 without ttwid): the room page is the fallback', () async {
      final (:site, :http) = _replay([_homeWithoutTtwid, 'S04-enter-no-cookie', 'S06-room-html-live']);
      final detail = await site.detail(RoomRef('douyin', _webRid));
      expect(_paths(http), [_home, _enter, 'GET live.douyin.com/$_webRid']);
      expect(http.requests[1].headers.containsKey('cookie'), isFalse);
      expect(detail.state, LiveState.live);
      expect(detail.ref, RoomRef('douyin', _webRid));
      final legacy = (Fixture.load('douyin', 'S06-room-html-live').legacy as Map<String, dynamic>)['room'] as Map;
      expect(detail.danmakuKeys['userUniqueId'], (legacy['danmakuData'] as Map)['userId'], reason: "the page's own id");
      expect(detail.danmakuKeys['roomId'], _roomId);
      final set = await site.streams(detail);
      expect(set.qualities.map((quality) => quality.id), ['origin', 'hd', 'sd', 'ld', 'md']);
      expect(http.requests, hasLength(3));
    });

    test('enter refused and a page without the room state: the refusal (RiskControl) is reported', () async {
      final (:site, :http) = _replay([
        _homeWithoutTtwid,
        'S04-enter-no-cookie',
        _fake('https://live.douyin.com/$_webRid', body: '<html><body>verify</body></html>'),
      ]);
      await expectLater(site.detail(RoomRef('douyin', _webRid)), throwsA(isA<RiskControl>()));
      expect(_paths(http), [_home, _enter, 'GET live.douyin.com/$_webRid']);
    });

    test('a room_id goes through reflow; an ended broadcast is queried again by web_rid', () async {
      final (:site, :http) = _replay(['S01-home', 'S05-reflow-live', 'S05-reflow-ended', 'S04-enter-offline']);
      final live = await site.detail(RoomRef('douyin', _roomId));
      expect(live.ref, RoomRef('douyin', _webRid));
      expect(live.state, LiveState.live);
      expect(live.danmakuKeys, {'webRid': _webRid, 'roomId': _roomId, 'userUniqueId': site.visitorId});
      expect((await site.streams(live)).lines, isNotEmpty);
      final ended = await site.detail(RoomRef('douyin', '7376083140344859455'));
      expect(ended.ref, RoomRef('douyin', '745964462470'));
      expect(ended.state, LiveState.offline);
      expect(_paths(http), [_home, _reflow, _reflow, _enter]);
    });
  });

  group('links', () {
    test('room links resolve without requests; videos, search pages and bare sites are not rooms', () async {
      final (:site, :http) = _replay(const []);
      for (final input in [
        _webRid,
        'https://live.douyin.com/$_webRid?from=search&enter_from=link_share',
        'https://live.douyin.com/$_webRid/extra',
        '【小央视频】正在直播，来和我一起支持Ta吧。https://live.douyin.com/$_webRid，快来',
        '复制打开 live.douyin.com/$_webRid 看直播',
        'https://www.douyin.com/$_webRid',
        'https://www.douyin.com/root/live/$_webRid',
        'https://www.douyin.com/follow/live/$_webRid?from_tab_name=main',
      ]) {
        expect(await site.resolve(input), RoomRef('douyin', _webRid), reason: input);
      }
      for (final input in [
        'https://www.douyin.com/',
        'https://www.douyin.com/video/7300000000000000000',
        'https://www.douyin.com/search/%E5%92%8C%E5%B9%B3%E7%B2%BE%E8%8B%B1',
        'https://www.douyin.com/root/live/',
        'https://live.douyin.com/',
        'https://live.douyin.com/abc',
        'https://webcast.amemv.com/douyin/webcast/share',
        'https://live.bilibili.com/6',
        'https://user@live.douyin.com/$_webRid',
        '抖音',
        '',
      ]) {
        expect(await site.resolve(input), isNull, reason: input);
      }
      expect(http.requests, isEmpty);
    });

    test('a room_id or a reflow link is normalised to the web_rid', () async {
      final (:site, :http) = _replay(['S01-home', 'S05-reflow-live']);
      expect(await site.resolve(_roomId), RoomRef('douyin', _webRid));
      expect(
        await site.resolve('https://webcast.amemv.com/douyin/webcast/reflow/$_roomId?u_code=x'),
        RoomRef('douyin', _webRid),
      );
      expect(_paths(http), [_home, _reflow, _reflow]);
    });

    test('a v.douyin.com share is followed hop by hop without automatic redirects', () async {
      final (:site, :http) = _replay([
        _fake(
          'https://v.douyin.com/iAbCdEf/',
          status: 302,
          headers: {
            'location': ['https://webcast.amemv.com/douyin/webcast/reflow/$_roomId?u_code=x&did=y'],
          },
        ),
        'S01-home',
        'S05-reflow-live',
      ]);
      const share = '7- 长按复制此条消息，打开抖音搜索，查看TA的更多作品。 https://v.douyin.com/iAbCdEf/ 1@2.com :9pm';
      expect(await site.resolve(share), RoomRef('douyin', _webRid));
      expect(_paths(http), ['GET v.douyin.com/iAbCdEf/', _home, _reflow]);
      expect(http.requests.first.followRedirects, isFalse);
      expect(http.requests.first.headers.containsKey('cookie'), isFalse);
    });

    test('relative redirects are resolved; a live.douyin.com landing needs no reflow', () async {
      final (:site, :http) = _replay([
        _fake(
          'https://v.douyin.com/a/',
          status: 302,
          headers: {
            'location': ['/b/'],
          },
        ),
        _fake(
          'https://v.douyin.com/b/',
          status: 301,
          headers: {
            'location': ['https://live.douyin.com/$_webRid?enter_from=share'],
          },
        ),
      ]);
      expect(await site.resolve('https://v.douyin.com/a/'), RoomRef('douyin', _webRid));
      expect(_paths(http), ['GET v.douyin.com/a/', 'GET v.douyin.com/b/']);
    });

    for (final location in [
      'https://www.douyin.com/video/7300000000000000000',
      'https://example.org/reflow/123',
      'ftp://live.douyin.com/1',
      'https://user@live.douyin.com/1',
      'https://[broken',
      '',
    ]) {
      test('a short link redirecting to "$location" is not a room (one request)', () async {
        final (:site, :http) = _replay([
          _fake(
            'https://v.douyin.com/x/',
            status: 302,
            headers: {
              'location': [location],
            },
          ),
        ]);
        expect(await site.resolve('https://v.douyin.com/x/'), isNull);
        expect(http.requests, hasLength(1));
      });
    }

    test('short links: loops and pages end with null, 404 is NotFound', () async {
      final (:site, :http) = _replay([
        _fake(
          'https://v.douyin.com/loop/',
          status: 302,
          headers: {
            'location': ['https://v.douyin.com/back/'],
          },
        ),
        _fake(
          'https://v.douyin.com/back/',
          status: 302,
          headers: {
            'location': ['https://v.douyin.com/loop/#again'],
          },
        ),
        _fake('https://v.douyin.com/page/', body: '<html></html>'),
        _fake('https://v.douyin.com/gone/', status: 404),
      ]);
      expect(await site.resolve('https://v.douyin.com/loop/'), isNull);
      expect(_paths(http), ['GET v.douyin.com/loop/', 'GET v.douyin.com/back/']);
      expect(await site.resolve('https://v.douyin.com/page/'), isNull);
      await expectLater(site.resolve('https://v.douyin.com/gone/'), throwsA(isA<NotFound>()));
    });
  });
}
