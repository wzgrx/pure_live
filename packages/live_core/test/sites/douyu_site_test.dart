// DouyuSite over the recorded responses (ReplayHttp): one device id per
// request chain, the signing descriptor cache, signed play requests and
// their retry, lines of one confirmed rate, the recording cursor, recovery,
// leases, 靓号 and alias rooms, login renewal, links and error mapping.
// Signature, device and clock parameters are scrubbed in the samples and
// left out of matching.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/douyu';
const _ignored = {'did', 'tt', 'auth', 'enc_data', 't', '_'};

const _encryption = '/wgapi/livenc/liveweb/websec/getEncryption';
const _play = '/lapi/live/getH5PlayV1/24422';
const _passport = '/lapi/passport/iframe/safeAuth';

/// The descriptor sample's capture time: every play sample falls in its
/// validity.
final DateTime _captured = Fixture.load('douyu', 'S06-encryption').capturedAt;

ReplaySample _synthetic(
  String url,
  Object body, {
  String method = 'GET',
  int status = 200,
  Map<String, List<String>> headers = const {},
}) => ReplaySample(
  method: method,
  url: Uri.parse(url),
  status: status,
  bytes: utf8.encode(body is String ? body : jsonEncode(body)),
  headers: headers,
);

ReplaySample _denied() => _synthetic('https://www.douyu.com$_play', '"鉴权失败"', method: 'POST', status: 403);

ReplaySample _answer(String cdn, Object? rate, {int error = 0}) => _synthetic('https://www.douyu.com$_play', {
  'error': error,
  'msg': error == 0 ? 'ok' : 'failed',
  'data': error == 0
      ? {'rate': ?rate, 'rtmp_url': 'https://$cdn.example.test/live', 'rtmp_live': 'stream.flv?expire=300'}
      : '',
}, method: 'POST');

ReplaySample _passportAnswer(List<String> setCookie) => _synthetic(
  'https://passport.douyu.com$_passport?client_id=1&callback=axiosJsonpCallback',
  'axiosJsonpCallback({"error":0})',
  headers: {if (setCookie.isNotEmpty) 'set-cookie': setCookie},
);

String _jwt(DateTime expiresAt) {
  final payload = base64Url.encode(utf8.encode(jsonEncode({'exp': expiresAt.millisecondsSinceEpoch ~/ 1000})));
  return 'eyJhbGciOiJIUzI1NiJ9.${payload.replaceAll('=', '')}.sig';
}

/// Answers scripted responses for a path in order, then replays [inner].
final class _Sequenced implements LiveHttp {
  new(this.inner, this.script);

  final ReplayHttp inner;
  final Map<String, List<ReplaySample>> script;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    final queue = script[request.url.path];
    if (queue == null || queue.isEmpty) return await inner.send(request);
    inner.requests.add(request);
    final sample = queue.removeAt(0);
    return LiveResponse(status: sample.status, headers: sample.headers, bytes: sample.bytes, url: request.url);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => inner.open(request);

  @override
  void close() {}
}

final class _Failing implements LiveHttp {
  new(this.reason);

  final TransportReason reason;

  @override
  Future<LiveResponse> send(LiveRequest request) async => throw TransportFailure('douyu', reason, 'test');

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('douyu', reason, 'test');

  @override
  void close() {}
}

/// The app side of a login: LTP0 and the device id kept apart, the save
/// time, and renewed cookies written back to the vault.
final class _Store implements DouyuLoginStore {
  new(this.vault, {this.longTermKey, this.deviceId, this.savedAt});

  final MemoryCookieVault vault;
  final List<({String cookie, DateTime at})> saved = [];

  @override
  final String? longTermKey;

  @override
  final String? deviceId;

  @override
  DateTime? savedAt;

  @override
  Future<void> saveRenewed(String cookie, DateTime renewedAt) async {
    saved.add((cookie: cookie, at: renewedAt));
    savedAt = renewedAt;
    vault.set('douyu', cookie);
  }
}

typedef _Setup = ({DouyuSite site, ReplayHttp http});

_Setup _setup(
  List<String> samples, {
  List<ReplaySample> extra = const [],
  CookieVault? cookies,
  DouyuLoginStore? login,
  Map<String, List<ReplaySample>> script = const {},
  DateTime Function()? now,
  bool Function()? forceRenewal,
}) {
  final http = ReplayHttp([
    ...extra,
    for (final name in samples) ReplaySample.load('$_root/$name'),
  ], ignoredQuery: _ignored);
  final site = DouyuSite(
    script.isEmpty
        ? http
        : _Sequenced(http, {
            for (final MapEntry(:key, :value) in script.entries) key: [...value],
          }),
    cookies: cookies,
    login: login,
    forceRenewal: forceRenewal,
    now: now ?? () => _captured,
    random: Random(7),
  );
  return (site: site, http: http);
}

List<String> _paths(ReplayHttp http) => [for (final request in http.requests) request.url.path];

int _count(ReplayHttp http, String path) => _paths(http).where((p) => p == path).length;

Map<String, String> _form(LiveRequest request) => Uri.splitQueryString(utf8.decode(request.body!));

String? _cookieDid(LiveRequest request) =>
    RegExp('(?:^|; )dy_did=([^;]*)').firstMatch(request.headers['cookie'] ?? '')?.group(1);

LiveRoom _room(String id) => LiveRoom(platform: 'douyu', roomId: id);

LivePlayQuality _quality(int rate, List<String> cdns) =>
    LivePlayQuality(quality: '$rate', id: rate, data: DouyuPlayData(rate, cdns));

void main() {
  group('catalog and search', () {
    test('categories, area rooms and recommendations', () async {
      final setup = _setup(['S01-cate-list', 'S02-mixlist-page1', 'S03-allpage-page1']);
      expect((await setup.site.getCategories(1, 20)).first.name, '网游竞技');
      final area = await setup.site.getCategoryRooms(const LiveArea(platform: 'douyu', areaType: '1', areaId: '1'));
      expect(area, hasLength(120), reason: 'mixList pages hold 120 rooms');
      expect(await setup.site.getRecommendRooms(), hasLength(40));
      expect(setup.http.requests.first.headers, {'user-agent': DouyuApi.userAgent});
      final list = setup.http.requests[1];
      expect(list.url.path, '/gapi/rkc/directory/mixList/2_1/1');
      expect(list.headers['cookie'], 'dy_did=${setup.site.deviceId}; acf_did=${setup.site.deviceId}');
      expect(list.headers['referer'], 'https://www.douyu.com/');
    });

    test('search sends kw, page and pageSize (1–50) with the search referer; a blank keyword sends nothing', () async {
      final search = Fixture.load('douyu', 'S04-search-page1');
      final setup = _setup(
        ['S04-search-page1'],
        extra: [
          _synthetic('https://www.douyu.com/japi/search/api/searchShow?kw=x&page=1&pageSize=50', {
            'error': 0,
            'data': {'relateShow': <Object>[]},
          }),
        ],
      );
      final rooms = await setup.site.searchRooms(search.url.queryParameters['kw']!, pageSize: 20);
      expect(rooms, hasLength(20));
      expect(setup.http.requests.single.headers['referer'], 'https://www.douyu.com/search/');
      expect(await setup.site.searchRooms('   '), isEmpty);
      expect(setup.http.requests, hasLength(1));
      expect(await setup.site.searchRooms('x', pageSize: 999), isEmpty);
    });

    test('a search error is ApiChanged', () async {
      final fixture = Fixture.load('douyu', 'S04-search-error-kw');
      final setup = _setup(['S04-search-error-kw']);
      await expectLater(
        setup.site.searchRooms(fixture.url.queryParameters['kw']!, pageSize: 20),
        throwsA(isA<ApiChanged>()),
      );
    });

    test('streamers', () async {
      final setup = _setup(
        [],
        extra: [
          _synthetic('https://www.douyu.com/japi/search/api/searchUser?kw=a&page=2&pageSize=30&filterType=1', {
            'error': 0,
            'data': {
              'relateUser': [
                {
                  'anchorInfo': {'rid': 1, 'nickName': 'a', 'isLive': 1, 'roomType': 0},
                },
              ],
            },
          }),
        ],
      );
      final anchors = await setup.site.searchAnchors('a', page: 2);
      expect(anchors.single.liveStatus, isTrue);
    });
  });

  group('detail', () {
    test('betard of the rid: the requested id stays, the rid goes into data and the danmaku arguments', () async {
      final setup = _setup(['S05-live']);
      final room = await setup.site.getRoomDetail(roomId: '5526219');
      expect(room.roomId, '5526219');
      expect(room.isLiveNow, isTrue);
      expect(room.startedAt, DateTime.utc(2026, 9, 26, 11, 0, 29), reason: 'show_time, no extra request');
      expect((room.data! as DouyuRoomData).rid, '5526219');
      expect((room.danmakuData! as DouyuDanmakuArgs).roomId, '5526219');
      expect(setup.http.requests.single.headers, {
        'referer': 'https://www.douyu.com/5526219',
        'user-agent': DouyuApi.detailUserAgent,
      });
      expect((await setup.site.getRoomDetailForRefresh(roomId: '5526219')).title, room.title);
      expect((await setup.site.getRoomDetailForRecording(roomId: '5526219')).isLiveNow, isTrue);
      expect(await setup.site.getLiveStatus(roomId: '5526219'), isTrue);
    });

    test('a loop room is a replay, not live', () async {
      final setup = _setup(['S05-replay-videoloop']);
      expect((await setup.site.getRoomDetail(roomId: '9804176')).isRecord, isTrue);
      expect(await setup.site.getLiveStatus(roomId: '9804176'), isFalse);
    });

    test('a 靓号 opens its room: betard does not know it, its page names the rid', () async {
      final closed = Fixture.load('douyu', 'S05-not-found').body.replaceFirst('该房间目前没有开放', '您观看的房间已被关闭');
      final setup = _setup(
        ['S05-live'],
        extra: [
          _synthetic('https://www.douyu.com/betard/123455', closed),
          _synthetic('https://www.douyu.com/123455', '<script>window.room_id = 5526219;</script>'),
        ],
      );
      final room = await setup.site.getRoomDetail(roomId: '123455');
      expect(room.roomId, '123455', reason: 'the follow keeps the address it was made with');
      expect((room.data! as DouyuRoomData).rid, '5526219');
      expect((room.danmakuData! as DouyuDanmakuArgs).roomId, '5526219');
      expect(_paths(setup.http), ['/betard/123455', '/123455', '/betard/5526219']);
      expect(setup.http.requests[1].followRedirects, isFalse);
      await setup.site.getRoomDetailForRefresh(roomId: '123455');
      expect(_paths(setup.http).skip(3), ['/betard/5526219'], reason: 'the rid is remembered');
    });

    test('an alias is looked up on its page first (betard refuses aliases)', () async {
      final setup = _setup(
        ['S05-live'],
        extra: [
          _synthetic(
            'https://www.douyu.com/fixtureAlias',
            '',
            status: 302,
            headers: {
              'location': ['/5526219'],
            },
          ),
        ],
      );
      final room = await setup.site.getRoomDetail(roomId: 'fixtureAlias');
      expect(room.roomId, 'fixtureAlias');
      expect((room.data! as DouyuRoomData).rid, '5526219');
      expect(_paths(setup.http), ['/fixtureAlias', '/betard/5526219']);
    });

    test('a missing room is NotFound after its page names no room; bad ids send nothing', () async {
      final setup = _setup(
        ['S05-not-found'],
        extra: [_synthetic('https://www.douyu.com/999999999', '<html><title>斗鱼</title></html>')],
      );
      await expectLater(setup.site.getRoomDetailForRecording(roomId: '999999999'), throwsA(isA<NotFound>()));
      expect(_paths(setup.http), ['/betard/999999999', '/999999999']);
      await expectLater(setup.site.getRoomDetail(roomId: 'a b'), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getRoomDetail(roomId: ''), throwsA(isA<NotFound>()));
      expect(setup.http.requests, hasLength(2));
    });

    test('failures are thrown, never an offline room (REG-DOUYU-012)', () async {
      final setup = _setup([], extra: [_synthetic('https://www.douyu.com/betard/1', 'x', status: 403)]);
      await expectLater(setup.site.getRoomDetailForRecording(roomId: '1'), throwsA(isA<RiskControl>()));
      final failing = DouyuSite(_Failing(TransportReason.timeout), random: Random(1));
      await expectLater(failing.getRoomDetail(roomId: '1'), throwsA(isA<NetworkFailure>()));
      final cancelled = DouyuSite(_Failing(TransportReason.cancelled), random: Random(1));
      await expectLater(
        cancelled.getRoomDetail(roomId: '1'),
        throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
      );
    });
  });

  group('streams', () {
    test('qualities from one metadata request; one device id in descriptor, form and cookie (REG-DOUYU-003)', () async {
      final setup = _setup(['S06-encryption', 'S08-meta-24422']);
      final qualities = await setup.site.getPlayQualities(detail: _room('24422'));
      expect(qualities.map((quality) => quality.quality), ['原画2K60', '蓝光4M', '超清', '高清']);
      expect((qualities.first.data! as DouyuPlayData).cdns, ['hw-h5', 'hs-h5']);
      expect(_paths(setup.http), [_encryption, _play]);
      final did = setup.site.deviceId;
      expect(did, matches(RegExp(r'^[0-9a-f]{32}$')));
      final [descriptor, play] = setup.http.requests;
      expect(descriptor.url.queryParameters['did'], did);
      expect(_cookieDid(descriptor), did);
      expect(_form(play)['did'], did);
      expect(_cookieDid(play), did);
      expect(_form(play), containsPair('rate', '-1'));
      expect(_form(play), containsPair('cdn', ''));
      expect(play.headers['referer'], 'https://www.douyu.com/24422');
      expect(play.headers['content-type'], startsWith('application/x-www-form-urlencoded'));
    });

    test('E01.7: metadata with streamStatus 0 (a live room without a pushed stream) is StreamUnavailable '
        'when listing qualities and when recovering; no CDN is asked', () async {
      final noStream = Fixture.load('douyu', 'S08-meta-9263298-nostream').body;
      final answer = _synthetic('https://www.douyu.com$_play', noStream, method: 'POST');
      final setup = _setup(
        ['S06-encryption'],
        script: {
          _play: [answer, answer],
        },
      );
      await expectLater(setup.site.getPlayQualities(detail: _room('24422')), throwsA(isA<StreamUnavailable>()));
      final quality = LivePlayQuality(quality: '原画', id: 0, data: DouyuPlayData(0, const ['hw-h5']));
      await expectLater(
        setup.site.resolvePlayUrlsForRecovery(detail: _room('24422'), quality: quality),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(_paths(setup.http).where((path) => path == _play), hasLength(2), reason: 'one metadata request each');
    });

    test('the account cookie device id signs every request; LTP0 is never sent to them (REG-DOUYU-004)', () async {
      final vault = MemoryCookieVault()..set('douyu', 'dy_did=abc123; acf_auth=t; LTP0=secret');
      addTearDown(vault.dispose);
      final setup = _setup(['S06-encryption', 'S08-meta-24422'], cookies: vault);
      await setup.site.getPlayQualities(detail: _room('24422'));
      expect(setup.site.deviceId, 'abc123');
      final [descriptor, play] = setup.http.requests;
      expect(descriptor.url.queryParameters['did'], 'abc123');
      expect(_form(play)['did'], 'abc123');
      expect(play.headers['cookie'], 'dy_did=abc123; acf_did=abc123; acf_auth=t');
    });

    test('every CDN signed at the requested rate; a downgrade to 4 groups both lines under 4', () async {
      final setup = _setup(['S06-encryption', 'S08-meta-24422', 'S09-24422-r0-hw-h5', 'S09-24422-r0-hs-h5']);
      final room = _room('24422');
      final qualities = await setup.site.getPlayQualities(detail: room);
      final resolution = await setup.site.resolvePlayUrls(detail: room, quality: qualities.first);
      expect(resolution.appliedQualityData, 4);
      expect(resolution.qualityUnconfirmed, isFalse);
      expect(resolution.lines.map((line) => line.lineId), ['hw-h5', 'hs-h5']);
      expect(_count(setup.http, _encryption), 1, reason: 'the descriptor is reused');
      final plays = setup.http.requests.where((request) => request.url.path == _play).skip(1).toList();
      expect(plays.map((request) => _form(request)['cdn']), ['hw-h5', 'hs-h5']);
      expect(plays.map((request) => _form(request)['rate']), ['0', '0']);
      final line = resolution.lines.first;
      expect(line.headers['referer'], 'https://www.douyu.com/24422');
      expect(line.headers['cookie'], 'dy_did=${setup.site.deviceId}; acf_did=${setup.site.deviceId}');
      expect(line.lease!.refreshAt, _captured.toUtc().add(const Duration(seconds: 255)));
      expect(line.lease!.cutsConnection, isTrue);
      expect(await setup.site.getPlayUrls(detail: room, quality: qualities.first), resolution.urls);
      final shown = resolveAppliedPlayQuality(qualities: qualities, requested: qualities.first, resolution: resolution);
      expect(shown.quality, '蓝光4M', reason: 'never 4M shown as 原画 (REG-DOUYU-027)');
    });

    test('a room opened by its 靓号 signs with its rid', () async {
      final room = _room('123455').copyWith(data: const DouyuRoomData('24422'));
      final setup = _setup(['S06-encryption', 'S08-meta-24422']);
      await setup.site.getPlayQualities(detail: room);
      expect(setup.http.requests.last.url.path, _play);
    });

    test('the recording cursor signs only its line; past the last line nothing is sent (REG-DOUYU-013)', () async {
      final setup = _setup(['S06-encryption', 'S09-24422-r0-hs-h5']);
      final quality = _quality(0, ['hw-h5', 'hs-h5']);
      final resolution = await setup.site.resolvePlayUrlAtRaw(detail: _room('24422'), quality: quality, lineIndex: 1);
      expect(resolution.lines.single.lineId, 'hs-h5');
      expect(resolution.appliedQualityData, 4);
      expect(_paths(setup.http), [_encryption, _play]);
      final beyond = await setup.site.resolvePlayUrlAtRaw(detail: _room('24422'), quality: quality, lineIndex: 2);
      expect(beyond.hasSources, isFalse);
      expect(beyond.appliedQualityData, isNull);
      expect(setup.http.requests, hasLength(2));
    });

    test('recovery fetches fresh metadata and signs the committed rate on current CDNs (REG-DOUYU-011)', () async {
      final setup = _setup(['S06-encryption', 'S08-meta-24422', 'S09-24422-r0-hw-h5', 'S09-24422-r0-hs-h5']);
      final resolution = await setup.site.resolvePlayUrlsForRecovery(
        detail: _room('24422'),
        quality: _quality(0, ['expired']),
      );
      expect(resolution.lines.map((line) => line.lineId), ['hw-h5', 'hs-h5']);
      final forms = [for (final request in setup.http.requests.where((r) => r.url.path == _play)) _form(request)];
      expect(forms.map((form) => form['cdn']), ['', 'hw-h5', 'hs-h5']);
      expect(forms.every((form) => form['cdn'] != 'expired'), isTrue);
    });

    test('recovery asks for a rate the metadata no longer lists, on the current CDNs', () async {
      final setup = _setup(
        ['S06-encryption'],
        script: {
          _play: [ReplaySample.load('$_root/S08-meta-24422'), _answer('hw', 3), _answer('hs', 3)],
        },
      );
      final resolution = await setup.site.resolvePlayUrlsForRecovery(
        detail: _room('24422'),
        quality: _quality(9, ['expired']),
      );
      expect(resolution.appliedQualityData, 3);
      final forms = [for (final request in setup.http.requests.where((r) => r.url.path == _play)) _form(request)];
      expect(forms.skip(1).map((form) => '${form['rate']}/${form['cdn']}'), ['9/hw-h5', '9/hs-h5']);
    });

    test('a failing CDN is skipped; when all fail the last failure is thrown', () async {
      final setup = _setup(
        ['S06-encryption'],
        script: {
          _play: [_answer('hw', null, error: 102), _answer('hs', 2)],
        },
      );
      final resolution = await setup.site.resolvePlayUrls(
        detail: _room('24422'),
        quality: _quality(0, ['hw-h5', 'hs-h5']),
      );
      expect(resolution.urls, ['https://hs.example.test/live/stream.flv?expire=300']);
      expect(resolution.appliedQualityData, 2);
      final failing = _setup(
        ['S06-encryption'],
        script: {
          _play: [_answer('hw', null, error: 102), _answer('hs', null, error: 102)],
        },
      );
      await expectLater(
        failing.site.resolvePlayUrls(detail: _room('24422'), quality: _quality(0, ['hw-h5', 'hs-h5'])),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(_count(failing.http, _play), 2, reason: 'an API error is not retried');
    });

    test('an offline room is StreamUnavailable at once: no second request, no new descriptor', () async {
      final setup = _setup(['S06-encryption', 'S10-offline']);
      await expectLater(setup.site.getPlayQualities(detail: _room('71415')), throwsA(isA<StreamUnavailable>()));
      expect(_paths(setup.http), [_encryption, '/lapi/live/getH5PlayV1/71415']);
    });

    test('a 403 is retried once with a new descriptor; a second 403 is RiskControl', () async {
      final recovered = _setup(
        ['S06-encryption'],
        script: {
          _play: [_denied(), ReplaySample.load('$_root/S08-meta-24422')],
        },
      );
      expect(await recovered.site.getPlayQualities(detail: _room('24422')), hasLength(4));
      expect(_paths(recovered.http), [_encryption, _play, _encryption, _play]);
      final refused = _setup(
        ['S06-encryption'],
        script: {
          _play: [_denied(), _denied()],
        },
      );
      await expectLater(refused.site.getPlayQualities(detail: _room('24422')), throwsA(isA<RiskControl>()));
      expect(_count(refused.http, _play), 2);
    });

    test('the descriptor: shared by concurrent callers, renewed after five minutes and per device id', () async {
      var clock = _captured;
      final vault = MemoryCookieVault();
      addTearDown(vault.dispose);
      final setup = _setup(['S06-encryption', 'S08-meta-24422'], cookies: vault, now: () => clock);
      final room = _room('24422');
      await Future.wait([setup.site.getPlayQualities(detail: room), setup.site.getPlayQualities(detail: room)]);
      expect(_count(setup.http, _encryption), 1);
      clock = clock.add(const Duration(minutes: 4, seconds: 59));
      await setup.site.getPlayQualities(detail: room);
      expect(_count(setup.http, _encryption), 1);
      clock = _captured.add(const Duration(minutes: 5));
      await setup.site.getPlayQualities(detail: room);
      expect(_count(setup.http, _encryption), 2, reason: 'five minutes old');
      vault.set('douyu', 'dy_did=other; acf_auth=t');
      await setup.site.getPlayQualities(detail: room);
      expect(_count(setup.http, _encryption), 3, reason: 'a descriptor belongs to one device id');
      expect(setup.http.requests.last.headers['cookie'], startsWith('dy_did=other; acf_did=other'));
    });

    test('lease times of resolved URLs; an unknown URL counts from now; no expire, no lease', () async {
      final setup = _setup(['S06-encryption', 'S09-24422-r0-hw-h5']);
      final resolution = await setup.site.resolvePlayUrlAtRaw(
        detail: _room('24422'),
        quality: _quality(0, ['hw-h5']),
        lineIndex: 0,
      );
      final url = resolution.urls.single;
      expect(setup.site.getPlayUrlRefreshAt(url), resolution.lines.single.lease!.refreshAt);
      expect(
        setup.site.getPlayUrlInvalidAt(url, now: DateTime.utc(2030)),
        _captured.toUtc().add(const Duration(seconds: 300)),
      );
      final later = DateTime.utc(2026, 9, 27, 12);
      expect(
        setup.site.getPlayUrlRefreshAt('https://x.douyucdn2.cn/live/r.flv?expire=300', now: later),
        later.add(const Duration(seconds: 255)),
      );
      expect(setup.site.getPlayUrlInvalidAt('https://x.douyucdn2.cn/live/r.flv?expire=0'), isNull);
    });

    test('forced renewal (2-1): off by default; on, an expire=0 line gets a five-minute lease, read live', () async {
      var force = false;
      final setup = _setup(['S06-encryption', 'S09-24422-r2-hw-h5'], forceRenewal: () => force);
      Future<LivePlayLine> resolve() async => (await setup.site.resolvePlayUrlAtRaw(
        detail: _room('24422'),
        quality: _quality(2, ['hw-h5']),
        lineIndex: 0,
      )).lines.single;

      final plain = await resolve();
      expect(plain.lease, isNull, reason: 'expire=0 states no lease');
      expect(setup.site.getPlayUrlRefreshAt(plain.url), isNull);

      force = true;
      final forced = await resolve();
      expect(forced.lease!.expiresAt, _captured.toUtc().add(const Duration(minutes: 5)));
      expect(forced.lease!.refreshAt, _captured.toUtc().add(const Duration(minutes: 4, seconds: 15)));
      expect(forced.lease!.cutsConnection, isTrue);
      expect(
        setup.site.getPlayUrlRefreshAt(forced.url, now: DateTime.utc(2030)),
        forced.lease!.refreshAt,
        reason: 'the lease of the resolution, not one counted from now',
      );
      final later = DateTime.utc(2026, 9, 27, 12);
      expect(
        setup.site.getPlayUrlInvalidAt('https://x.douyucdn2.cn/live/r.flv?expire=0', now: later),
        later.add(const Duration(minutes: 5)),
        reason: 'an unknown URL counts from now',
      );
      expect(setup.site.getPlayUrlInvalidAt('https://x.douyucdn2.cn/live/r.m3u8?expire=0', now: later), isNull);

      force = false;
      expect(setup.site.getPlayUrlRefreshAt(forced.url), isNull, reason: 'the setting is read at every lookup');
      expect(setup.site.getPlayUrlInvalidAt(forced.url), isNull);
      expect(
        setup.site.getPlayUrlInvalidAt('https://x.douyucdn2.cn/live/r.flv?expire=300', now: later),
        later.add(const Duration(seconds: 300)),
        reason: 'a stated lease does not depend on it',
      );
      expect(_count(setup.http, _play), 2, reason: 'no extra request: one per resolution');
    });

    test('a quality of another shape resolves to nothing', () async {
      final setup = _setup([]);
      final resolution = await setup.site.resolvePlayUrlsRaw(
        detail: _room('24422'),
        quality: const LivePlayQuality(quality: '原画', id: 0, data: 0),
      );
      expect(resolution.hasSources, isFalse);
      expect(setup.http.requests, isEmpty);
    });
  });

  group('login renewal', () {
    final expiredLogin = 'dy_did=d0; acf_jwt_token=${_jwt(_captured.subtract(const Duration(hours: 1)))}; acf_uid=1';
    final renewedToken = _jwt(_captured.add(const Duration(days: 7)));

    test('an expired login with LTP0 is renewed before the play request, then used (3.x ensureFreshSession)', () async {
      final vault = MemoryCookieVault()..set('douyu', '$expiredLogin; LTP0=l0');
      addTearDown(vault.dispose);
      final store = _Store(vault);
      final setup = _setup(
        ['S06-encryption', 'S08-meta-24422'],
        cookies: vault,
        login: store,
        extra: [
          _passportAnswer(['acf_jwt_token=$renewedToken; Path=/; HttpOnly', 'acf_ccn=; Max-Age=0']),
        ],
      );
      await setup.site.getPlayQualities(detail: _room('24422'));
      expect(_paths(setup.http), [_passport, _encryption, _play]);
      expect(setup.http.requests.first.headers['cookie'], 'dy_did=d0;LTP0=l0');
      expect(setup.http.requests.first.url.queryParameters['client_id'], '1');
      final saved = store.saved.single;
      expect(saved.at, _captured);
      expect(saved.cookie, contains('acf_jwt_token=$renewedToken'));
      expect(saved.cookie, contains('LTP0=l0'), reason: 'the next renewal needs it (REG-DOUYU-023)');
      final play = setup.http.requests.last;
      expect(play.headers['cookie'], contains('acf_jwt_token=$renewedToken'));
      expect(play.headers['cookie'], isNot(contains('LTP0')));
    });

    test('LTP0 and the device id may be stored apart from the cookie', () async {
      final vault = MemoryCookieVault()..set('douyu', 'dy_auth=w');
      addTearDown(vault.dispose);
      final store = _Store(
        vault,
        longTermKey: 'l1',
        deviceId: 'd1',
        savedAt: _captured.subtract(const Duration(days: 6, hours: 12)),
      );
      final setup = _setup(
        ['S06-encryption', 'S08-meta-24422'],
        cookies: vault,
        login: store,
        extra: [
          _passportAnswer(['dy_auth=renewed']),
        ],
      );
      await setup.site.getPlayQualities(detail: _room('24422'));
      expect(setup.http.requests.first.headers['cookie'], 'dy_did=d1;LTP0=l1');
      expect(store.saved.single.cookie, 'dy_auth=renewed');
    });

    test('nothing is renewed for a login with days left, without LTP0, or without a store', () async {
      final fresh = 'dy_did=d0; acf_jwt_token=${_jwt(_captured.add(const Duration(days: 3)))}; LTP0=l0';
      for (final (cookie, withStore) in [(fresh, true), (expiredLogin, true), ('$expiredLogin; LTP0=l0', false)]) {
        final vault = MemoryCookieVault()..set('douyu', cookie);
        addTearDown(vault.dispose);
        final setup = _setup(
          ['S06-encryption', 'S08-meta-24422'],
          cookies: vault,
          login: withStore ? _Store(vault) : null,
        );
        await setup.site.getPlayQualities(detail: _room('24422'));
        expect(_count(setup.http, _passport), 0, reason: cookie);
      }
    });

    test('a failed play request renews even a fresh login before the retry', () async {
      final vault = MemoryCookieVault()
        ..set('douyu', 'dy_did=d0; acf_jwt_token=${_jwt(_captured.add(const Duration(days: 3)))}; LTP0=l0');
      addTearDown(vault.dispose);
      final store = _Store(vault);
      final setup = _setup(
        ['S06-encryption'],
        cookies: vault,
        login: store,
        extra: [
          _passportAnswer(['acf_jwt_token=$renewedToken']),
        ],
        script: {
          _play: [_denied(), ReplaySample.load('$_root/S08-meta-24422')],
        },
      );
      await setup.site.getPlayQualities(detail: _room('24422'));
      expect(_paths(setup.http), [_encryption, _play, _passport, _encryption, _play]);
      expect(setup.http.requests.last.headers['cookie'], contains(renewedToken));
      expect(store.saved, hasLength(1));
    });

    test('a renewal without Set-Cookie changes nothing, and a failed one does not stop playback', () async {
      for (final passport in [
        _passportAnswer(const []),
        _synthetic('https://passport.douyu.com$_passport?client_id=1&callback=axiosJsonpCallback', 'x', status: 502),
      ]) {
        final vault = MemoryCookieVault()..set('douyu', '$expiredLogin; LTP0=l0');
        addTearDown(vault.dispose);
        final store = _Store(vault);
        final setup = _setup(['S06-encryption', 'S08-meta-24422'], cookies: vault, login: store, extra: [passport]);
        expect(await setup.site.getPlayQualities(detail: _room('24422')), hasLength(4));
        expect(store.saved, isEmpty, reason: 'the save time must not move (REG-DOUYU-024)');
      }
    });

    test('renewSession: the merged cookie, null without Set-Cookie, NetworkFailure on the wire', () async {
      final setup = _setup(
        [],
        script: {
          _passport: [
            _passportAnswer(['acf_jwt_token=$renewedToken; Path=/']),
            _passportAnswer(const []),
          ],
        },
      );
      final renewed = await setup.site.renewSession(cookie: 'Cookie: $expiredLogin; LTP0=l0', ltp0: 'l0', did: 'd0');
      expect(renewed, contains('acf_jwt_token=$renewedToken'));
      expect(renewed, contains('LTP0=l0'));
      expect(setup.http.requests.single.url.queryParameters['t'], '${_captured.millisecondsSinceEpoch}');
      expect(await setup.site.renewSession(cookie: expiredLogin, ltp0: 'l0', did: 'd0'), isNull);
      await expectLater(
        DouyuSite(
          _Failing(TransportReason.connect),
          random: Random(1),
        ).renewSession(cookie: 'acf_auth=a', ltp0: 'l', did: 'd'),
        throwsA(isA<NetworkFailure>()),
      );
      await expectLater(setup.site.renewSession(cookie: 'acf_auth=a', ltp0: ' ', did: 'd'), throwsA(isA<NeedsLogin>()));
    });
  });

  group('links', () {
    test('room pages of douyu.com and its subdomains, share pages; other pages are not rooms', () {
      final site = _setup([]).site;
      expect(site.roomIdFromUrl('https://www.douyu.com/9999?from=search'), '9999');
      expect(site.roomIdFromUrl('https://www.douyu.com/123/'), '123');
      expect(site.roomIdFromUrl('https://m.douyu.com/123455'), '123455');
      expect(site.roomIdFromUrl('https://www.douyu.com/room/share/123455'), '123455');
      expect(site.roomIdFromUrl('https://www.douyu.com/topic/something'), isNull);
      expect(site.roomIdFromUrl('https://www.douyu.com/search?kw=game'), isNull);
      expect(site.roomIdFromUrl('https://www.douyu.com/lpl'), isNull);
      expect(site.roomIdFromUrl('https://www.douyu.com.evil.example/1234'), isNull);
      expect(site.roomIdFromUrl('https://live.bilibili.com/6'), isNull);
    });

    test('aliases need a request; numbers, reserved and area pages do not', () {
      final site = _setup([]).site;
      expect(site.needsResolving('https://www.douyu.com/lpl'), isTrue);
      expect(site.needsResolving('https://www.douyu.com/fixture-Alias_1'), isTrue);
      expect(site.needsResolving('https://www.douyu.com/9999'), isFalse);
      expect(site.needsResolving('https://www.douyu.com/directory'), isFalse);
      expect(site.needsResolving('https://www.douyu.com/g_LOL'), isFalse);
      expect(site.needsResolving('https://www.douyu.com/topic/x'), isFalse);
      expect(site.needsResolving('https://live.bilibili.com/lpl'), isFalse);
    });

    test('an alias page redirects to its rid, requested once and not followed; numbers need no request', () async {
      final http = ReplayHttp([ReplaySample.load('$_root/S05-alias-redirect')]);
      final registry = SiteRegistry({'douyu': () => DouyuSite(http, random: Random(1))});
      final parser = LinkParser(registry, http);
      expect(await parser.parse('来斗鱼看 https://www.douyu.com/lpl。'), const RoomLink('douyu', '288016'));
      expect(http.requests.single.url.path, '/lpl');
      expect(http.requests.single.followRedirects, isFalse);
      expect(await parser.parse('https://www.douyu.com/9999?from=search'), const RoomLink('douyu', '9999'));
      expect(http.requests, hasLength(1));
      expect(parser.containsSupportedLink('https://www.douyu.com/lpl'), isTrue);
      expect(parser.containsSupportedLink('https://www.douyu.com/search?kw=game'), isFalse);
    });

    test('aliases ignore case: LPL and lpl lead to the same rid, and rooms compare without case', () async {
      final http = ReplayHttp([
        ReplaySample.load('$_root/S05-alias-redirect'),
        ReplaySample.load('$_root/S05-alias-redirect-upper'),
      ]);
      final parser = LinkParser(SiteRegistry({'douyu': () => DouyuSite(http, random: Random(1))}), http);
      expect(await parser.parse('https://www.douyu.com/LPL'), const RoomLink('douyu', '288016'));
      expect(await parser.parse('https://www.douyu.com/lpl'), const RoomLink('douyu', '288016'));
      expect(_paths(http), ['/LPL', '/lpl']);
      expect(SiteIds.ignoresRoomIdCase('douyu'), isTrue);
      final upper = _room('LPL');
      expect(upper.hasSameIdentity(_room('lpl')), isTrue);
      expect(upper.identityKey, 'douyu:lpl');
      expect(upper.roomId, 'LPL', reason: 'the stored spelling stays');
      expect(_room('288016').hasSameIdentity(_room('lpl')), isFalse, reason: 'an alias is not its rid');
    });

    test('an alias page without a redirect to a rid leads nowhere', () async {
      final http = ReplayHttp([_synthetic('https://www.douyu.com/nothing', '<html></html>')]);
      final parser = LinkParser(SiteRegistry({'douyu': () => DouyuSite(http, random: Random(1))}), http);
      expect(await parser.parse('https://www.douyu.com/nothing'), isNull);
    });
  });
}
