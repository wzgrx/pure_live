// HuyaSite over the recorded responses (ReplayHttp) and scripted WUP and
// anonymous-login answers: catalog, search, room detail, the per-line
// signing with its native and web credentials, fallbacks, retries, leases,
// the message board and links.
//
// The samples scrub `fm` into bytes without the `$0`–`$3` placeholders and
// there are no WUP samples, so the stream tests patch a synthetic template
// into the AntiCodes and answer WUP from a script. `_` (the request time)
// and the search `uid` (scrubbed) are left out of matching.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/huya';
const _ignored = {'_', 'uid'};

/// The S05 capture instant.
final DateTime _now = DateTime.utc(2026, 9, 27, 9, 44, 32, 850);

/// S05-multicdn's streamer and stream names.
const _presenter = 1346609715;
const _stream1 = '78941969-2559461593-10992803837303062528-2693342886-10057-A-0-1-imgplus';
const _stream2 = '78941969-2601386338-11172869245971202048-3120471182-10057-A-0-1-imgplus';

/// 3.x's `buildRequest` of the native getCdnTokenInfoEx for [_stream1].
const _nativeRequestStream1 =
    '000000b210032c3c4c56066c6976657569661167657443646e546f6b656e496e666f45787d000100840800010604745265711d'
    '0000770a0600164737383934313936392d323535393436313539332d31303939323830333833373330333036323532382d3236'
    '39333334323838362d31303035372d412d302d312d696d67706c75732c3a0c16002600361770635f6578652637303630303030'
    '266f6666696369616c46005c660076000b40420b8c980ca80c';

/// An anonymous-login viewer uid above 2^32.
const _viewer = 1400123456789;

const _webTemplate = r'DWq8BcJ3h6DJt6TY_$0_$1_$2_$3';
const _nativeTemplate = r'native|$0|$1|$2|$3';

final String _nativeToken = 'wsTime=6aba3701&fm=${_fm(_nativeTemplate)}&ctype=huya_pc_exe&t=100';

String _fm(String template) => Uri.encodeComponent(base64Encode(utf8.encode(template)));

String _wsTime(DateTime time) => (time.millisecondsSinceEpoch ~/ 1000).toRadixString(16);

Uint8List _hex(String hex) =>
    Uint8List.fromList([for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);

ReplaySample _sample(String name) => ReplaySample.load('$_root/$name');

ReplaySample _synthetic(String url, Object body, {int status = 200, Map<String, List<String>> headers = const {}}) =>
    ReplaySample(
      method: 'GET',
      url: Uri.parse(url),
      status: status,
      bytes: utf8.encode(body is String ? body : jsonEncode(body)),
      headers: headers,
    );

/// [name] with every AntiCode rewritten by [antiCode] and, when given, only
/// the [flv] / [hls] CDNs left in `multiLine`.
ReplaySample _patched(
  String name, {
  String Function(String antiCode)? antiCode,
  Map<String, String> codes = const {},
  Set<String>? flv,
  Set<String>? hls,
}) {
  final sample = _sample(name);
  final body = jsonDecode(utf8.decode(sample.bytes)) as Map<String, dynamic>;
  final stream = (body['data'] as Map<String, dynamic>)['stream'] as Map<String, dynamic>;
  for (final base in (stream['baseSteamInfoList'] as List).cast<Map<String, dynamic>>()) {
    for (final key in ['sFlvAntiCode', 'sHlsAntiCode']) {
      if (antiCode != null) base[key] = antiCode(base[key] as String);
      if (codes[key] case final code?) base[key] = code;
    }
  }
  for (final (key, keep) in [('flv', flv), ('hls', hls)]) {
    if (keep == null) continue;
    final group = stream[key] as Map<String, dynamic>;
    group['multiLine'] = [
      for (final line in (group['multiLine'] as List).cast<Map<String, dynamic>>())
        if (keep.contains(line['cdnType'])) line,
    ];
  }
  return ReplaySample(
    method: sample.method,
    url: sample.url,
    status: sample.status,
    headers: sample.headers,
    bytes: utf8.encode(jsonEncode(body)),
  );
}

/// [sample] with its `data` object changed by [edit].
ReplaySample _edited(ReplaySample sample, void Function(Map<String, dynamic> data) edit) {
  final body = jsonDecode(utf8.decode(sample.bytes)) as Map<String, dynamic>;
  edit(body['data'] as Map<String, dynamic>);
  return ReplaySample(
    method: sample.method,
    url: sample.url,
    status: sample.status,
    headers: sample.headers,
    bytes: utf8.encode(jsonEncode(body)),
  );
}

/// A replay sample whose recording names video [videoId] (`vid`, not
/// `hyvid`).
ReplaySample _withReplayVideo(ReplaySample sample, String videoId) => _edited(sample, (data) {
  final live = data['liveData'] as Map<String, dynamic>;
  for (final key in ['hls', 'hlsUrl']) {
    live[key] = (live[key] as String).replaceFirstMapped(
      RegExp(r'([?&])vid=\d+'),
      (match) => '${match[1]}vid=$videoId',
    );
  }
});

/// Replaces the scrubbed `fm` with the synthetic web template.
String _withTemplate(String antiCode) => antiCode.replaceFirst(RegExp('fm=[^&]*'), 'fm=${_fm(_webTemplate)}');

LiveResponse _wupAnswer(LiveRequest request, {int code = 0, String token = '', int expireTime = 0}) => LiveResponse(
  status: 200,
  url: request.url,
  bytes: WupPacket(
    servant: 'liveui',
    function: 'getCdnTokenInfoEx',
    params: {
      '': WupPacket.intParam(code),
      'tRsp': WupPacket.structParam(
        (writer) => writer
          ..writeString(0, token)
          ..writeInt(1, expireTime),
      ),
    },
  ).encode(),
);

LiveResponse _loginAnswer(LiveRequest request, int uid) => LiveResponse(
  status: 200,
  url: request.url,
  bytes: utf8.encode(
    jsonEncode({
      'returnCode': 0,
      'data': {'uid': uid},
    }),
  ),
);

/// The `tReq` of a WUP request.
TarsStruct _tReq(LiveRequest request) => WupPacket.decode(request.body!).struct('tReq')!;

/// ReplayHttp for recorded GETs, scripted answers for WUP, anonymous login
/// and other hosts, and an optional queue of `profileRoom` answers.
final class _Http implements LiveHttp {
  new(List<ReplaySample> samples, {this.wup, this.login, this.other, List<ReplaySample> profiles = const []})
    : _replay = ReplayHttp(samples, ignoredQuery: _ignored),
      _profiles = [...profiles];

  final ReplayHttp _replay;
  final List<ReplaySample> _profiles;

  /// Answers `wup.huya.com` given the decoded packet.
  final LiveResponse Function(LiveRequest request, WupPacket packet)? wup;

  /// Answers `anonymousLogin`.
  final LiveResponse Function(LiveRequest request)? login;

  /// Answers anything else first, when it returns a response.
  final LiveResponse? Function(LiveRequest request)? other;

  final List<LiveRequest> requests = [];

  List<LiveRequest> on(String host) => [
    for (final request in requests)
      if (request.url.host == host) request,
  ];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    if (other?.call(request) case final response?) return response;
    switch (request.url.host) {
      case 'wup.huya.com':
        return wup!(request, WupPacket.decode(request.body!));
      case 'udblgn.huya.com':
        return login!(request);
      case 'mp.huya.com' when _profiles.isNotEmpty:
        final sample = _profiles.removeAt(0);
        return LiveResponse(status: sample.status, headers: sample.headers, bytes: sample.bytes, url: request.url);
    }
    return await _replay.send(request);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async {
    final response = await send(request);
    return LiveStreamedResponse(
      status: response.status,
      headers: response.headers,
      body: Stream.value(response.bytes),
      url: response.url,
    );
  }

  @override
  void close() {}
}

final class _Failing implements LiveHttp {
  new(this.reason);

  final TransportReason reason;

  @override
  Future<LiveResponse> send(LiveRequest request) async => throw TransportFailure('huya', reason, 'test');

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('huya', reason, 'test');

  @override
  void close() {}
}

HuyaSite _site(
  LiveHttp http, {
  CookieVault? cookies,
  List<Uri> playConfigUrls = const [],
  bool Function()? preferH264,
}) => HuyaSite(
  http,
  cookies: cookies,
  now: () => _now,
  random: Random(1),
  playConfigUrls: playConfigUrls,
  preferH264: preferH264,
);

MemoryCookieVault _vault(String cookie) {
  final vault = MemoryCookieVault()..set('huya', cookie);
  addTearDown(vault.dispose);
  return vault;
}

/// The signing millisecond of a non-WAP signed URL: `seqid − unrotate(u)`.
int _millis(Uri url) =>
    int.parse(url.queryParameters['seqid']!) - HuyaApi.unrotateUid(int.parse(url.queryParameters['u']!));

/// Recomputes [url]'s wsSecret from [template].
void _expectSigned(Uri url, String template, {required int uid}) {
  final query = url.queryParameters;
  expect(query.containsKey('fm'), isFalse, reason: 'fm never reaches the CDN');
  expect(query['u'], '${HuyaApi.rotateUid(uid)}');
  expect(query['ver'], '1');
  final hash = md5.convert(utf8.encode('${query['seqid']}|${query['ctype']}|${query['t']}')).toString();
  final stream = url.pathSegments.last.replaceFirst(RegExp(r'\.(flv|m3u8)$'), '');
  final input = template
      .replaceFirst(r'$0', query['u']!)
      .replaceFirst(r'$1', stream)
      .replaceFirst(r'$2', hash)
      .replaceFirst(r'$3', query['wsTime']!);
  expect(query['wsSecret'], md5.convert(utf8.encode(input)).toString());
}

void main() {
  group('catalog, lists and search', () {
    test('categories: the four bussLive trees in platform order', () async {
      final samples = ['S01-buss1', 'S01-buss2', 'S01-buss8', 'S01-buss3'];
      final http = _Http([for (final name in samples) _sample(name)]);
      final categories = await _site(http).getCategories(1, 20);
      expect(categories.map((category) => (category.id, category.name)), [
        ('1', '网游'),
        ('2', '单机'),
        ('8', '娱乐'),
        ('3', '手游'),
      ]);
      for (final (index, category) in categories.indexed) {
        final fixture = Fixture.load('huya', samples[index]);
        expect(category.children, hasLength(((fixture.legacy as Map)['children'] as List).length));
        expect(category.children.every((area) => area.areaType == category.id), isTrue);
      }
      expect(http.requests.map((request) => request.url.queryParameters['bussType']), ['1', '2', '8', '3']);
      expect(http.requests.map((request) => request.headers), everyElement({'user-agent': HuyaApi.userAgent}));
    });

    test('one failed category fails the whole tree', () async {
      final http = _Http([
        _sample('S01-buss1'),
        _sample('S01-buss2'),
        _sample('S01-buss8'),
        _synthetic('https://live.cdn.huya.com/liveconfig/game/bussLive?bussType=3', '', status: 502),
      ]);
      await expectLater(_site(http).getCategories(1, 20), throwsA(isA<NetworkFailure>()));
    });

    test(
      'area rooms and recommendations: the mobile UA and the cookie; recommendations add Origin and Referer',
      () async {
        final http = _Http([_sample('S03-hot-page1'), _sample('S02-page1')]);
        final site = _site(http, cookies: _vault('yyuid=1; other=2'));
        final area = await site.getCategoryRooms(const LiveArea(platform: 'huya', areaType: '1', areaId: '1'), page: 0);
        expect(area, hasLength(120));
        final recommended = await site.getRecommendRooms();
        expect(recommended, hasLength(120));
        expect(recommended.every((room) => room.isLiveNow && room.onlineViewers.isEmpty), isTrue);

        final (first, second) = (http.requests[0], http.requests[1]);
        expect(first.url.queryParameters, containsPair('gameId', '1'));
        expect(first.url.queryParameters, containsPair('page', '1'));
        expect(first.headers, {'user-agent': HuyaApi.userAgent, 'cookie': 'yyuid=1; other=2'});
        expect(second.url.queryParameters.containsKey('gameId'), isFalse);
        expect(second.headers, {
          'user-agent': HuyaApi.userAgent,
          'cookie': 'yyuid=1; other=2',
          'origin': 'https://www.huya.com',
          'referer': 'https://www.huya.com/',
        });
      },
    );

    test('search: rows 1–50, start from the page, page 2 without page 1; a blank keyword sends nothing', () async {
      final http = _Http([
        _sample('S04-results'),
        _sample('S04-page2'),
        _synthetic(
          'https://search.cdn.huya.com/?m=Search&do=getSearchContent&q=x&uid=0&v=4&typ=-5&livestate=0&rows=50&start=50',
          {'response': <String, Object?>{}},
        ),
      ]);
      final site = _site(http);
      final first = await site.searchRooms('英雄联盟', pageSize: 20);
      final second = await site.searchRooms('英雄联盟', page: 2, pageSize: 20);
      expect((first.length, second.length), (20, 20));
      expect(second.map((room) => room.roomId).toSet().intersection(first.map((room) => room.roomId).toSet()), isEmpty);
      expect(await site.searchRooms('x', page: 2, pageSize: 999), isEmpty);
      final before = http.requests.length;
      expect(await site.searchRooms('  '), isEmpty);
      expect(http.requests, hasLength(before));
      expect(http.requests.first.url.queryParameters, {
        'm': 'Search',
        'do': 'getSearchContent',
        'q': '英雄联盟',
        'uid': '0',
        'v': '4',
        'typ': '-5',
        'livestate': '0',
        'rows': '20',
        'start': '0',
      });
      // Search answers a request without a User-Agent with HTTP 403 (M4.D).
      expect(http.requests.map((request) => request.headers), everyElement({'user-agent': HuyaApi.userAgent}));
    });

    test('streamers: getSearchContent v=1', () async {
      final http = _Http([
        _synthetic(
          'https://search.cdn.huya.com/?m=Search&do=getSearchContent&q=lpl&uid=0&v=1&typ=-5&livestate=0&rows=30&start=0',
          {
            'response': {
              '1': {
                'docs': [
                  {'room_id': 660000, 'game_nick': '虎牙英雄联盟赛事', 'gameLiveOn': true},
                ],
              },
            },
          },
        ),
      ]);
      final anchors = await _site(http).searchAnchors('lpl');
      expect(http.requests.single.headers, {'user-agent': HuyaApi.userAgent});
      expect(anchors.single.roomId, '660000');
      expect(anchors.single.liveStatus, isTrue);
    });
  });

  group('rooms', () {
    test('room entry: the requested id, stream data and danmaku arguments; profileRoom skips the cache', () async {
      final http = _Http([_sample('S05-multicdn')]);
      final site = _site(http, cookies: _vault('yyuid=$_viewer'));
      final room = await site.getRoomDetail(roomId: ' 660000 ');
      expect(room.roomId, '660000');
      expect(room.isLiveNow, isTrue);
      final data = room.data! as HuyaRoomData;
      expect(data.lines, hasLength(10));
      expect(data.qualities.map((quality) => quality.id), [0, 4000, 2000, 500]);
      final args = room.danmakuData! as HuyaDanmakuArgs;
      expect((args.uid, args.topSid, args.subSid), (_presenter, _presenter, _presenter));
      expect(args.superChats, isNotNull);

      final request = http.requests.single;
      expect(request.url.queryParameters['_'], '${_now.millisecondsSinceEpoch}', reason: 'REG-HUYA-016');
      expect(request.url.queryParameters['showSecret'], '1');
      expect(request.headers, containsPair('cache-control', 'no-cache'));
      expect(request.headers, containsPair('pragma', 'no-cache'));
      expect(request.headers, containsPair('origin', 'https://www.huya.com'));
      expect(request.headers, containsPair('cookie', 'yyuid=$_viewer'));
    });

    test('refresh is metadata only; recording keeps the stream data', () async {
      final site = _site(_Http([_sample('S05-multicdn')]));
      final refreshed = await site.getRoomDetailForRefresh(roomId: '660000');
      expect((refreshed.data, refreshed.danmakuData), (null, null));
      expect(refreshed.isLiveNow, isTrue);
      // M2.1: the follow refresh carries the start time and the restriction.
      expect(refreshed.startedAt, DateTime.utc(2025, 12, 29, 20, 22, 10));
      expect(refreshed.restriction, LiveRestriction.none);
      final recording = await site.getRoomDetailForRecording(roomId: '660000');
      expect(recording.data, isA<HuyaRoomData>());
      expect(await site.getLiveStatus(roomId: '660000'), isTrue);
    });

    test(
      'offline and replay rooms keep their state on every entry point; only a replay carries its recording',
      () async {
        final site = _site(_Http([_sample('S06-off'), _sample('S06-replay')]));
        for (final (id, status) in [('441195', LiveStatus.offline), ('102411', LiveStatus.replay)]) {
          final entry = await site.getRoomDetail(roomId: id);
          final refresh = await site.getRoomDetailForRefresh(roomId: id);
          // 3.x's recording detail threw FormatException for a replay.
          final recording = await site.getRoomDetailForRecording(roomId: id);
          for (final room in [entry, refresh, recording]) {
            expect(room.effectiveLiveStatus, status, reason: id);
            expect(room.danmakuData, isNull);
          }
          expect(refresh.data, isNull);
          if (status == LiveStatus.offline) {
            expect((entry.data, recording.data), (null, null), reason: 'REG-HUYA-015');
          } else {
            // 3-1: the replay's recording, so opening it needs no second profileRoom.
            for (final room in [entry, recording]) {
              expect((room.data! as HuyaRoomData).replay!.videoId, 1126494362);
              expect((room.data! as HuyaRoomData).lines, isEmpty);
            }
          }
          expect(await site.getLiveStatus(roomId: id), isFalse, reason: 'a replay is not live (not recorded)');
        }
      },
    );

    test('a replay plays its recording: getMomentContent definitions, one unsigned HLS line (3-1)', () async {
      final http = _Http([_sample('S06-replay'), _sample('S15-vod')]);
      final site = _site(http);
      final room = await site.getRoomDetail(roomId: '102411');
      expect((room.isRecord, room.restriction, room.followGroup), (true, LiveRestriction.none, FollowGroup.replay));
      final qualities = await site.getPlayQualities(detail: room);
      expect(qualities.map((quality) => quality.quality), ['原画', '720P', '360P']);
      final vod = http.on('liveapi.huya.com').single;
      expect(vod.url.path, '/moment/getMomentContent');
      expect(vod.url.queryParameters, {'videoId': '1126494362'});
      expect(vod.headers, {
        'user-agent': HuyaApi.userAgent,
        'origin': 'https://www.huya.com',
        'referer': 'https://www.huya.com/',
      });

      final resolution = await site.resolvePlayUrls(detail: room, quality: qualities.first);
      final line = resolution.lines.single;
      expect(line.url, qualities.first.data);
      expect(Uri.parse(line.url).queryParameters['definition'], 'yuanhua');
      expect((line.format, line.lineId, line.lease, line.codec), (StreamFormat.hls, 'replay|hls', null, null));
      expect(line.headers, HuyaApi.mediaHeaders('102411'), reason: 'no login cookie to the VOD CDN');
      expect(resolution.appliedQualityData, 'yuanhua');
      expect(site.getPlayUrlInvalidAt(line.url), isNull, reason: 'the recording does not expire');
      expect(site.getPlayUrlRefreshAt(line.url), isNull);

      final before = http.requests.length;
      final recovered = await site.resolvePlayUrlsForRecovery(detail: room, quality: qualities[1]);
      expect(recovered.lines.single.url, qualities[1].data);
      expect(recovered.appliedQualityData, '1300');
      expect(http.requests, hasLength(before), reason: 'a static recording is reopened without a request');
      expect((await site.resolvePlayUrlAtRaw(detail: room, quality: qualities.last, lineIndex: 0)).urls, [
        qualities.last.data,
      ]);
      expect((await site.resolvePlayUrlAtRaw(detail: room, quality: qualities.last, lineIndex: 1)).urls, isEmpty);
      expect(http.on('wup.huya.com'), isEmpty, reason: 'nothing to sign');
      expect(http.on('mp.huya.com'), hasLength(1));
    });

    test('the recording profileRoom names when getMomentContent fails or lists nothing (3-1)', () async {
      for (final vod in [
        _sample('S15-vod-missing'),
        _synthetic('https://liveapi.huya.com/moment/getMomentContent?videoId=1126494362', '', status: 502),
      ]) {
        final missing = vod.url.queryParameters['videoId']!;
        final http = _Http([vod], profiles: [_withReplayVideo(_sample('S06-replay'), missing)]);
        final site = _site(http);
        final room = await site.getRoomDetail(roomId: '102411');
        final quality = (await site.getPlayQualities(detail: room)).single;
        expect((quality.quality, quality.id), ('360P', '350'));
        final line = (await site.resolvePlayUrls(detail: room, quality: quality)).lines.single;
        expect(line.url, (room.data! as HuyaRoomData).replay!.url);
        expect(http.on('liveapi.huya.com'), hasLength(1));
      }
    });

    test('a replay without a recording is StreamUnavailable everywhere; no request beyond profileRoom', () async {
      final bare = _edited(
        _sample('S06-replay'),
        (data) => (data['liveData'] as Map<String, dynamic>)
          ..remove('hls')
          ..remove('hlsUrl'),
      );
      final http = _Http(const [], profiles: [bare, bare, bare, bare]);
      final site = _site(http);
      final room = await site.getRoomDetail(roomId: '102411');
      expect((room.restriction, room.followGroup, room.data), (LiveRestriction.unplayable, FollowGroup.offline, null));
      await expectLater(site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      const quality = LivePlayQuality(quality: '原画', id: 0, data: 0);
      await expectLater(site.resolvePlayUrls(detail: room, quality: quality), throwsA(isA<StreamUnavailable>()));
      await expectLater(
        site.resolvePlayUrlsForRecovery(detail: room, quality: quality),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(http.on('mp.huya.com'), hasLength(4));
      expect(http.on('wup.huya.com'), isEmpty);
    });

    test('a paid or secret live room shows as live but its streams are StreamUnavailable (M2.1)', () async {
      for (final (edit, kind) in [
        ((Map<String, dynamic> data) => data['isRoomPay'] = true, LiveRestriction.paid),
        (
          (Map<String, dynamic> data) => (data['liveData'] as Map<String, dynamic>)['isSecret'] = 1,
          LiveRestriction.password,
        ),
      ]) {
        final http = _Http(const [], profiles: [_edited(_sample('S05-multicdn'), edit)]);
        final site = _site(http);
        final room = await site.getRoomDetail(roomId: '660000');
        expect((room.isLiveNow, room.restriction, room.followGroup), (true, kind, FollowGroup.live));
        expect(room.danmakuData, isA<HuyaDanmakuArgs>(), reason: 'chat still works');
        await expectLater(
          site.getPlayQualities(detail: room),
          throwsA(isA<StreamUnavailable>().having((error) => error.detail, 'detail', contains(kind.name))),
        );
        await expectLater(
          site.resolvePlayUrls(
            detail: room,
            quality: const LivePlayQuality(quality: '原画', id: 0, data: 0),
          ),
          throwsA(isA<StreamUnavailable>()),
        );
        expect(http.on('wup.huya.com'), isEmpty, reason: 'nothing is signed for a restricted room');
      }
    });

    test('recovering a live quality after the broadcast ended in a replay is StreamUnavailable', () async {
      final http = _Http(const [], profiles: [_sample('S06-replay')]);
      await expectLater(
        _site(http).resolvePlayUrlsForRecovery(
          detail: LiveRoom(platform: 'huya', roomId: '102411'),
          quality: const LivePlayQuality(quality: '蓝光4M', id: 4000, data: 4000),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(http.on('liveapi.huya.com'), isEmpty);
    });

    test('a missing room is NotFound; a letter alias is NotFound without a request', () async {
      final http = _Http([_sample('S06-notfound')]);
      final site = _site(http);
      await expectLater(site.getRoomDetail(roomId: '999999999'), throwsA(isA<NotFound>()));
      await expectLater(site.getRoomDetailForRefresh(roomId: '999999999'), throwsA(isA<NotFound>()));
      final before = http.requests.length;
      await expectLater(site.getRoomDetail(roomId: 'lpl'), throwsA(isA<NotFound>()));
      expect(http.requests, hasLength(before));
    });

    LiveResponse board(LiveRequest request, WupPacket packet) => LiveResponse(
      status: 200,
      url: request.url,
      bytes: WupPacket(
        servant: 'wupui',
        function: 'getHeadLineMessageBoard',
        params: {
          '': WupPacket.intParam(0),
          'tRsp':
              (TarsWriter()..writeValue(
                    0,
                    const TarsStruct({
                      1: TarsStruct({
                        1: <Object?>[
                          TarsStruct({
                            0: TarsStruct({1: 'fan'}),
                            1: '加油',
                            2: 30,
                            4: 60,
                            5: 60,
                            9: 42,
                          }),
                        ],
                      }),
                    }),
                  ))
                  .toBytes(),
        },
      ).encode(),
    );

    test('super chats: the board of the top channel remembered from the detail', () async {
      final http = _Http([_sample('S05-multicdn')], wup: board);
      final site = _site(http);
      final room = await site.getRoomDetail(roomId: '660000');
      final chats = await site.getSuperChatMessage(roomId: '660000');
      expect(chats.single.messageId, 'huya:42');
      expect(chats.single.price, 30);
      expect(await (room.danmakuData! as HuyaDanmakuArgs).superChats!(), hasLength(1));
      expect(http.on('mp.huya.com'), hasLength(1), reason: '3.x requested the whole room again');
      final request = http.on('wup.huya.com').first;
      expect(_tReq(request).integer(0), _presenter);
      expect(request.method, 'POST');
      expect(request.timeout, const Duration(seconds: 3), reason: 'REG-HUYA-022');
      expect(request.headers, {
        'content-type': 'application/x-wup',
        'origin': 'https://www.huya.com',
        'referer': 'https://www.huya.com',
        'user-agent': HuyaApi.hysdkUserAgent,
      });
    });

    test('super chats of a room without a detail: one profileRoom; a live room without multiLine too', () async {
      final http = _Http([_sample('S05-ratearray')], wup: board);
      final chats = await _site(http).getSuperChatMessage(roomId: '30925595');
      expect(chats, hasLength(1), reason: '3.x had topSid 0 here and never read the board');
      expect(_tReq(http.on('wup.huya.com').single).integer(0), 1319535174649);
    });
  });

  group('streams', () {
    test('优先 H.264 off: FLV lines ask for HEVC (codec unknown), HLS stays on H.264; read on every open', () async {
      var preferH264 = false;
      final http = _Http(
        [_patched('S05-multicdn', antiCode: _withTemplate)],
        wup: (request, _) => _wupAnswer(request, token: _nativeToken, expireTime: 300),
        login: (request) => _loginAnswer(request, _viewer),
      );
      final site = _site(http, preferH264: () => preferH264);
      final room = await site.getRoomDetail(roomId: '660000');
      final quality = (await site.getPlayQualities(detail: room)).first;
      final hevc = await site.resolvePlayUrls(detail: room, quality: quality);
      for (final line in hevc.lines) {
        final flv = line.format == StreamFormat.flv;
        expect(Uri.parse(line.url).queryParameters['codec'], flv ? '265' : '264');
        expect(line.codec, flv ? isNull : 'avc');
      }
      preferH264 = true;
      final avc = await site.resolvePlayUrls(detail: room, quality: quality);
      expect(avc.lines.map((line) => Uri.parse(line.url).queryParameters['codec']), everyElement('264'));
    });

    test('S05-multicdn: native FLV on every CDN, then web-signed HLS, in server order', () async {
      final http = _Http(
        [_patched('S05-multicdn', antiCode: _withTemplate)],
        wup: (request, _) => _wupAnswer(request, token: _nativeToken, expireTime: 300),
        login: (request) => _loginAnswer(request, _viewer),
      );
      final site = _site(http);
      final room = await site.getRoomDetail(roomId: '660000');
      final qualities = await site.getPlayQualities(detail: room);
      final resolution = await site.resolvePlayUrls(detail: room, quality: qualities.first);
      expect(resolution.appliedQualityData, 0, reason: 'Huya does not report the delivered quality');
      expect(resolution.lines.map((line) => line.lineId), [
        for (final cdn in ['AL', 'TX', 'HS', 'TX15', 'HS24']) '$cdn|flv|native',
        for (final cdn in ['AL', 'TX', 'HS', 'TX15', 'HS24']) '$cdn|hls|web',
      ]);
      for (final line in resolution.lines) {
        final url = Uri.parse(line.url);
        expect(url.scheme, 'https');
        expect(url.queryParameters['codec'], '264');
        expect(url.queryParameters.containsKey('ratio'), isFalse, reason: 'source quality');
        expect(line.codec, 'avc');
        expect(line.headers, HuyaApi.mediaHeaders('660000'));
      }

      final flv = resolution.lines.where((line) => line.format == StreamFormat.flv).toList();
      for (final line in flv) {
        final url = Uri.parse(line.url);
        expect(HuyaApi.isNativeFlv(url), isTrue);
        _expectSigned(url, _nativeTemplate, uid: _presenter);
        expect(url.queryParameters['wsTime'], '6aba3701', reason: 'never extended');
        // iExpireTime 300 s after receipt is earlier than wsTime + 300 s.
        expect(line.lease!.cutsConnection, isFalse, reason: 'REG-HUYA-002');
        expect(line.lease!.expiresAt, _now.add(const Duration(seconds: 300)));
        expect(line.lease!.refreshAt, _now.add(const Duration(seconds: 270)));
      }
      final al = Uri.parse(flv.first.url);
      expect(
        al.toString(),
        'https://al-game.flv.huya.com/src/$_stream1.flv?wsTime=6aba3701&ctype=huya_pc_exe&t=100'
        '&wsSecret=${al.queryParameters['wsSecret']}&seqid=${al.queryParameters['seqid']}&ver=1&fs=bgct'
        '&u=1134703440&codec=264',
      );

      for (final line in resolution.lines.where((line) => line.format == StreamFormat.hls)) {
        final url = Uri.parse(line.url);
        expect(url.path, endsWith('.m3u8'));
        expect((url.queryParameters['ctype'], url.queryParameters['t']), ('tars_mp', '102'));
        _expectSigned(url, _webTemplate, uid: _viewer);
        final issuedAt = DateTime.fromMillisecondsSinceEpoch(_millis(url), isUtc: true);
        expect(line.lease!.cutsConnection, isTrue, reason: 'REG-HUYA-001');
        expect(line.lease!.refreshAt, issuedAt.add(const Duration(seconds: 100)));
        expect(line.lease!.expiresAt, issuedAt.add(const Duration(seconds: 125)));
      }
      expect(resolution.lines.map((line) => _millis(Uri.parse(line.url))).toSet(), {
        for (var i = 0; i < 10; i++) _now.millisecondsSinceEpoch + i,
      }, reason: 'ten signatures, ten distinct milliseconds');

      final wups = http.on('wup.huya.com');
      expect(wups, hasLength(2), reason: 'AL/TX/HS and TX15/HS24 share a stream name; HLS never asks (REG-HUYA-006)');
      expect(wups.first.body, _hex(_nativeRequestStream1), reason: 'byte for byte the 3.x native request');
      expect({for (final request in wups) _tReq(request).string(1)}, {_stream1, _stream2});
      for (final request in wups) {
        final tReq = _tReq(request);
        expect((tReq.string(0), tReq.integer(4)), ('', 66));
        expect((tReq.struct(3)!.integer(0), tReq.struct(3)!.string(4)), (0, ''), reason: 'no viewer, no cookie');
        expect(request.headers, {
          'origin': 'https://www.huya.com',
          'referer': 'https://www.huya.com/',
          'user-agent': HuyaApi.hysdkUserAgent,
          'content-type': 'application/x-wup',
        });
        expect(request.timeout, const Duration(seconds: 8), reason: 'REG-HUYA-022');
      }
      final logins = http.on('udblgn.huya.com');
      expect(logins, hasLength(1), reason: 'one anonymous login shared by every HLS line');
      expect(jsonDecode(utf8.decode(logins.single.body!)), {
        'appId': 5002,
        'byPass': 3,
        'context': '',
        'version': '2.4',
        'data': <String, Object?>{},
      });
      expect((site.nativeFallbacks, site.degradedViewers), (0, 0));
    });

    for (final (kind, token) in [
      ('empty', ''),
      ('signed', 'wsSecret=web-token&wsTime=6aba3701&ctype=huya_live&t=100'),
      ('template', 'wsTime=6aba3701&fm=${_fm(_webTemplate)}&ctype=huya_live&t=100'),
    ]) {
      test('native WUP first whatever the room token looks like: $kind (REG-HUYA-003)', () async {
        final http = _Http([
          _patched('S05-multicdn', codes: {'sFlvAntiCode': token}, flv: {'AL'}, hls: {}),
        ], wup: (request, _) => _wupAnswer(request, token: _nativeToken, expireTime: 300));
        final site = _site(http);
        final room = await site.getRoomDetail(roomId: '660000');
        final line = (await site.resolvePlayUrls(
          detail: room,
          quality: (room.data! as HuyaRoomData).qualities.last,
        )).lines.single;
        final url = Uri.parse(line.url);
        expect(HuyaApi.isNativeFlv(url), isTrue);
        expect(url.queryParameters['u'], '${HuyaApi.rotateUid(_presenter)}', reason: 'signed as the streamer');
        expect(url.queryParameters['ratio'], '500');
        expect(http.on('wup.huya.com'), hasLength(1));
        expect(site.getPlayUrlInvalidAt(line.url), _now.add(const Duration(seconds: 300)));
      });
    }

    test('FLV uses the FLV token and HLS the HLS token, never the other (REG-HUYA-006, REG-HUYA-019)', () async {
      final http = _Http([
        _patched(
          'S05-multicdn',
          codes: {
            'sFlvAntiCode': 'wsSecret=flv-token&wsTime=6aba3701&ctype=tars_mp&t=102',
            'sHlsAntiCode': 'wsSecret=hls-token&wsTime=6aba3701&ctype=tars_mp&t=102',
          },
          flv: {'TX'},
          hls: {'TX'},
        ),
      ], wup: (request, _) => _wupAnswer(request, code: -1));
      final site = _site(http);
      final room = await site.getRoomDetail(roomId: '660000');
      final lines = (await site.resolvePlayUrls(
        detail: room,
        quality: (room.data! as HuyaRoomData).qualities.first,
      )).lines;
      expect(lines.map((line) => Uri.parse(line.url).queryParameters['wsSecret']), ['flv-token', 'hls-token']);
      expect(lines.map((line) => Uri.parse(line.url).path.split('.').last), ['flv', 'm3u8']);
      expect(http.on('wup.huya.com'), hasLength(1), reason: 'only the FLV line asks for a native token');
      for (final line in lines) {
        // Static tokens carry no seqid: the lease counts from when the URL was built.
        expect(line.lease!.refreshAt, _now.add(const Duration(seconds: 100)));
        expect(line.lease!.expiresAt, _now.add(const Duration(seconds: 125)));
        expect(line.lease!.cutsConnection, isTrue);
      }
    });

    test('a selected quality sets ratio on every line', () async {
      final http = _Http(
        [_patched('S05-multicdn', antiCode: _withTemplate)],
        wup: (request, _) => _wupAnswer(request, token: _nativeToken, expireTime: 300),
        login: (request) => _loginAnswer(request, _viewer),
      );
      final site = _site(http);
      final room = await site.getRoomDetail(roomId: '660000');
      final quality = (await site.getPlayQualities(detail: room)).firstWhere((option) => option.id == 2000);
      final resolution = await site.resolvePlayUrls(detail: room, quality: quality);
      expect(resolution.appliedQualityData, 2000);
      expect(resolution.lines.map((line) => Uri.parse(line.url).queryParameters['ratio']).toSet(), {'2000'});
      expect(await site.getPlayUrls(detail: room, quality: quality), hasLength(10));
    });

    test('native WUP down: the web FLV is signed as the account; the 3.x vector; the cookie goes along', () async {
      const cookie = 'foo=1; yyuid=$_presenter; bar=2';
      final http = _Http([
        _patched('S05-multicdn', antiCode: _withTemplate, flv: {'AL'}, hls: {}),
      ], wup: (request, _) => throw const TransportFailure('huya', TransportReason.timeout));
      final site = _site(http, cookies: _vault(cookie));
      final room = await site.getRoomDetail(roomId: '660000');
      final line = (await site.resolvePlayUrls(
        detail: room,
        quality: (room.data! as HuyaRoomData).qualities.first,
      )).lines.single;
      expect(
        line.url,
        'https://al-game.flv.huya.com/src/$_stream1.flv?wsTime=6aba3701&ctype=tars_mp&fs=bgct&t=102'
        '&wsSecret=dacbea4ab2bb0c07f5c99e3c6ecf8874&seqid=1791848882565&ver=1&u=1134703440&codec=264',
      );
      expect(line.lineId, 'AL|flv|web');
      expect(line.lease!.cutsConnection, isTrue);
      expect(line.lease!.refreshAt, _now.add(const Duration(seconds: 100)));
      expect(line.lease!.expiresAt, _now.add(const Duration(seconds: 125)));
      expect(line.headers['cookie'], cookie, reason: '3.x sent the Huya cookie with media requests');
      expect(site.nativeFallbacks, 1);
      expect(http.on('udblgn.huya.com'), isEmpty, reason: 'the cookie yyuid is the viewer');
    });

    test('native refused and the room template unusable: a web token as the viewer; HLS dropped', () async {
      const cookie = 'yyuid=$_viewer; other=x';
      final webToken = 'wsTime=6aba3701&fm=${_fm(_webTemplate)}&ctype=huya_webh5&t=100';
      final http = _Http(
        [_sample('S05-multicdn')],
        wup: (request, packet) => packet.struct('tReq')!.struct(3)!.string(3) == HuyaApi.nativeTarsUserAgent
            ? _wupAnswer(request, code: -1)
            : _wupAnswer(request, token: webToken, expireTime: 60),
      );
      final site = _site(http, cookies: _vault(cookie));
      final room = await site.getRoomDetail(roomId: '660000');
      final resolution = await site.resolvePlayUrls(
        detail: room,
        quality: (room.data! as HuyaRoomData).qualities.first,
      );
      // The recorded fm is scrubbed: FLV recovers through the web token, HLS has no fallback.
      expect(resolution.lines.map((line) => line.lineId), [
        for (final cdn in ['AL', 'TX', 'HS', 'TX15', 'HS24']) '$cdn|flv|web',
      ]);
      for (final line in resolution.lines) {
        final url = Uri.parse(line.url);
        _expectSigned(url, _webTemplate, uid: _viewer);
        expect(url.queryParameters['ctype'], 'huya_webh5');
        expect(line.lease!.refreshAt, _now.add(const Duration(seconds: 30)), reason: 'bounded by the web token');
        expect(line.lease!.expiresAt, _now.add(const Duration(seconds: 60)));
      }
      final web = [
        for (final request in http.on('wup.huya.com'))
          if (_tReq(request).struct(3)!.string(3) == HuyaApi.webTarsUserAgent) request,
      ];
      expect(web, hasLength(5), reason: 'one per viewer, line and stream');
      final bases = <String>{};
      for (final request in web) {
        final tReq = _tReq(request);
        bases.add('${tReq.string(0)} ${tReq.string(1)}');
        expect((tReq.integer(2), tReq.integer(4)), (0, 66));
        final tId = tReq.struct(3)!;
        expect((tId.integer(0), tId.string(2), tId.string(4), tId.integer(5)), (_viewer, '', cookie, 0));
        expect(tId.string(1), matches(RegExp(r'^[0-9a-f]{32}$')));
        expect(request.headers['cookie'], cookie);
        expect(request.headers['user-agent'], HuyaApi.userAgent);
      }
      expect(bases, {
        'https://al-game.flv.huya.com/src $_stream1',
        'https://tx.flv.huya.com/src $_stream1',
        'https://hs.flv.huya.com/src $_stream1',
        'https://tx.flv.huya.com/src $_stream2',
        'https://hs.flv.huya.com/src $_stream2',
      });
      expect(site.nativeFallbacks, 5);
    });

    test('no line opens: structural → ApiChanged, no token → StreamUnavailable, network → NetworkFailure', () async {
      final vault = _vault('yyuid=$_viewer');
      Future<void> expectFailure(
        ReplaySample sample,
        LiveResponse Function(LiveRequest, WupPacket) wup,
        Matcher matcher,
      ) async {
        final site = _site(_Http([sample], wup: wup), cookies: vault);
        final room = await site.getRoomDetail(roomId: '660000');
        await expectLater(
          site.resolvePlayUrls(detail: room, quality: (room.data! as HuyaRoomData).qualities.first),
          throwsA(matcher),
        );
      }

      await expectFailure(_sample('S05-multicdn'), (request, _) => _wupAnswer(request, code: -1), isA<ApiChanged>());
      await expectFailure(
        _patched('S05-multicdn', antiCode: (_) => ''),
        (request, _) => _wupAnswer(request, code: -1),
        isA<StreamUnavailable>(),
      );
      await expectFailure(
        _patched('S05-multicdn', hls: {}),
        (request, _) => throw const TransportFailure('huya', TransportReason.connect),
        isA<NetworkFailure>(),
      );
    });

    test('an expired AntiCode asks profileRoom again once, then fails', () async {
      final vault = _vault('yyuid=$_viewer');
      final stale = _wsTime(_now.subtract(const Duration(seconds: 400)));
      String expire(String antiCode) => _withTemplate(antiCode).replaceFirst('wsTime=6aba3701', 'wsTime=$stale');
      final expired = _patched('S05-multicdn', antiCode: expire, flv: {}, hls: {'AL'});
      final fresh = _patched('S05-multicdn', antiCode: _withTemplate, flv: {}, hls: {'AL'});

      final recovered = _Http(const [], profiles: [expired, fresh]);
      final site = _site(recovered, cookies: vault);
      final room = await site.getRoomDetail(roomId: '660000');
      final resolution = await site.resolvePlayUrls(
        detail: room,
        quality: (room.data! as HuyaRoomData).qualities.first,
      );
      expect(Uri.parse(resolution.lines.single.url).queryParameters['wsTime'], '6aba3701');
      expect(recovered.on('mp.huya.com'), hasLength(2));

      final always = _Http(const [], profiles: [expired, expired]);
      final stuck = _site(always, cookies: vault);
      final stale2 = await stuck.getRoomDetail(roomId: '660000');
      await expectLater(
        stuck.resolvePlayUrls(detail: stale2, quality: (stale2.data! as HuyaRoomData).qualities.first),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(always.on('mp.huya.com'), hasLength(2), reason: 'never extended locally, asked again once (REG-HUYA-004)');
    });

    test('recovery always asks profileRoom again; the same quality id, else the best (REG-HUYA-025)', () async {
      final http = _Http(
        [_patched('S05-multicdn', antiCode: _withTemplate)],
        wup: (request, _) => _wupAnswer(request, token: _nativeToken, expireTime: 300),
        login: (request) => _loginAnswer(request, _viewer),
      );
      final site = _site(http);
      final room = await site.getRoomDetail(roomId: '660000');
      final recovered = await site.resolvePlayUrlsForRecovery(
        detail: room,
        quality: const LivePlayQuality(quality: '超清', id: 2000, data: 2000),
      );
      expect(recovered.appliedQualityData, 2000);
      expect(recovered.lines, hasLength(10));
      expect(http.on('mp.huya.com'), hasLength(2));
      final unknown = await site.resolvePlayUrlsForRecovery(
        detail: room,
        quality: const LivePlayQuality(quality: '?', id: 9999),
      );
      expect(unknown.appliedQualityData, 0);

      final offline = _site(_Http([_sample('S06-off')]));
      await expectLater(
        offline.resolvePlayUrlsForRecovery(
          detail: LiveRoom(platform: 'huya', roomId: '441195'),
          quality: const LivePlayQuality(quality: '原画', id: 0),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('recording asks for one line at a time; past the last line gives nothing', () async {
      final http = _Http([
        _patched('S05-multicdn', antiCode: _withTemplate),
      ], login: (request) => _loginAnswer(request, _viewer));
      final site = _site(http);
      final room = await site.getRoomDetail(roomId: '660000');
      final quality = (room.data! as HuyaRoomData).qualities.first;
      final hls = await site.resolvePlayUrlAtRaw(detail: room, quality: quality, lineIndex: 5);
      expect(hls.lines.single.lineId, 'AL|hls|web');
      expect(http.on('wup.huya.com'), isEmpty, reason: 'only the requested HLS line was signed');
      for (final index in [-1, 10]) {
        expect((await site.resolvePlayUrlAtRaw(detail: room, quality: quality, lineIndex: index)).urls, isEmpty);
      }
    });

    test(
      'a failed anonymous login signs with a temporary uid, not cached; the next open retries (REG-HUYA-017)',
      () async {
        var attempts = 0;
        final http = _Http(
          [
            _patched('S05-multicdn', antiCode: _withTemplate, flv: {}, hls: {'AL', 'TX'}),
          ],
          login: (request) {
            if (++attempts == 1) throw const TransportFailure('huya', TransportReason.connect);
            return _loginAnswer(request, _viewer);
          },
        );
        final site = _site(http);
        final room = await site.getRoomDetail(roomId: '660000');
        final quality = (room.data! as HuyaRoomData).qualities.first;
        final degraded = await site.resolvePlayUrls(detail: room, quality: quality);
        final temporary = HuyaApi.unrotateUid(int.parse(Uri.parse(degraded.lines.first.url).queryParameters['u']!));
        expect(temporary, inInclusiveRange(1400000000000, 1499999999999));
        expect(degraded.lines.map((line) => Uri.parse(line.url).queryParameters['u']).toSet(), hasLength(1));
        expect(site.degradedViewers, 1);
        expect(http.on('udblgn.huya.com'), hasLength(1), reason: 'one attempt per open');

        final official = await site.resolvePlayUrls(detail: room, quality: quality);
        expect(Uri.parse(official.lines.first.url).queryParameters['u'], '${HuyaApi.rotateUid(_viewer)}');
        await site.resolvePlayUrls(detail: room, quality: quality);
        expect(http.on('udblgn.huya.com'), hasLength(2), reason: 'the official uid is kept');
      },
    );

    test('concurrent opens share one native request but get their own signatures (REG-HUYA-007)', () async {
      final http = _Http([
        _patched('S05-multicdn', antiCode: _withTemplate, flv: {'AL'}, hls: {}),
      ], wup: (request, _) => _wupAnswer(request, token: _nativeToken, expireTime: 300));
      final site = _site(http);
      final room = await site.getRoomDetail(roomId: '660000');
      final quality = (room.data! as HuyaRoomData).qualities.first;
      final (play, record) = await (
        site.resolvePlayUrls(detail: room, quality: quality),
        site.resolvePlayUrls(detail: room, quality: quality),
      ).wait;
      final a = Uri.parse(play.lines.single.url).queryParameters;
      final b = Uri.parse(record.lines.single.url).queryParameters;
      expect(a['seqid'], isNot(b['seqid']));
      expect(a['wsSecret'], isNot(b['wsSecret']));
      expect(http.on('wup.huya.com'), hasLength(1), reason: 'same stream name at the same time');
      await site.resolvePlayUrls(detail: room, quality: quality);
      expect(http.on('wup.huya.com'), hasLength(2), reason: 'a settled token is not cached');
    });

    test('lease metadata: the lease each URL was issued with; the refresh time never in the past', () async {
      final http = _Http([
        _patched('S05-multicdn', antiCode: _withTemplate, flv: {'AL'}, hls: {}),
      ], wup: (request, _) => _wupAnswer(request, token: _nativeToken, expireTime: 300));
      final site = _site(http);
      final room = await site.getRoomDetail(roomId: '660000');
      final line = (await site.resolvePlayUrls(
        detail: room,
        quality: (room.data! as HuyaRoomData).qualities.first,
      )).lines.single;
      expect(site.getPlayUrlInvalidAt(line.url), line.lease!.expiresAt);
      expect(site.getPlayUrlRefreshAt(line.url, now: _now), line.lease!.refreshAt);
      final late = _now.add(const Duration(minutes: 10));
      expect(site.getPlayUrlRefreshAt(line.url, now: late), late);
      final wsTime = DateTime.utc(2026, 9, 27, 10);
      expect(
        site.getPlayUrlInvalidAt('https://cdn.example/live.flv?wsTime=${_wsTime(wsTime)}'),
        wsTime.add(const Duration(minutes: 5)),
        reason: 'a URL it did not build is read from its wsTime',
      );
      expect(site.getPlayUrlRefreshAt('https://cdn.example/live.flv'), isNull);
    });

    test('qualities of a room without stream data are requested; offline and multiLine-less rooms', () async {
      final http = _Http([_sample('S05-multicdn'), _sample('S06-off'), _sample('S05-ratearray')]);
      final site = _site(http);
      final qualities = await site.getPlayQualities(
        detail: LiveRoom(platform: 'huya', roomId: '660000'),
      );
      expect(qualities.map((quality) => quality.quality), ['蓝光10M', '蓝光4M', '超清', '流畅']);
      await expectLater(
        site.getPlayQualities(
          detail: LiveRoom(platform: 'huya', roomId: '441195'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      final ratearray = await site.getRoomDetail(roomId: '30925595');
      final rate = (await site.getPlayQualities(detail: ratearray)).single;
      expect(rate.quality, '蓝光');
      await expectLater(site.resolvePlayUrls(detail: ratearray, quality: rate), throwsA(isA<StreamUnavailable>()));
      expect(http.on('wup.huya.com'), isEmpty);
    });

    test("the player configuration's UA goes to media requests; unreadable keeps HYSDK; read once", () async {
      final good = Uri.parse('https://mirror.test/play_config.json');
      final bad = Uri.parse('https://down.test/play_config.json');
      final http = _Http(
        [
          _patched('S05-multicdn', antiCode: _withTemplate, flv: {}, hls: {'AL'}),
        ],
        login: (request) => _loginAnswer(request, _viewer),
        other: (request) => switch (request.url.host) {
          'mirror.test' => LiveResponse(
            status: 200,
            url: request.url,
            bytes: utf8.encode('{"huya":{"user_agent":"HYSDK(custom)"}}'),
          ),
          'down.test' => LiveResponse(status: 404, url: request.url, bytes: const []),
          _ => null,
        },
      );
      final site = _site(http, playConfigUrls: [bad, good]);
      expect(site.playUserAgent, HuyaApi.hysdkUserAgent);
      expect(await site.loadPlayUserAgent(), 'HYSDK(custom)');
      await site.loadPlayUserAgent();
      expect(http.on('mirror.test'), hasLength(1));
      final room = await site.getRoomDetail(roomId: '660000');
      final line = (await site.resolvePlayUrls(
        detail: room,
        quality: (room.data! as HuyaRoomData).qualities.first,
      )).lines.single;
      expect(line.headers['user-agent'], 'HYSDK(custom)');

      final unreadable = _site(http, playConfigUrls: [bad]);
      expect(await unreadable.loadPlayUserAgent(), HuyaApi.hysdkUserAgent);

      // An older HYSDK client than the built-in one (the upstream file at
      // 7090000) keeps the built-in UA (E01.8).
      final stale = Uri.parse('https://stale.test/play_config.json');
      final staleHttp = _Http(
        const [],
        other: (request) => request.url.host == 'stale.test'
            ? LiveResponse(
                status: 200,
                url: request.url,
                bytes: utf8.encode(
                  '{"huya":{"user_agent":"HYSDK(Windows,30000002)_APP(pc_exe&7090000&official)_SDK(trans&2.35.0.5996)"}}',
                ),
              )
            : null,
      );
      final staleSite = _site(staleHttp, playConfigUrls: [stale]);
      expect(await staleSite.loadPlayUserAgent(), HuyaApi.hysdkUserAgent);
      expect(staleSite.playUserAgent, HuyaApi.hysdkUserAgent);
      expect(staleHttp.on('stale.test'), hasLength(1));
      expect(
        HuyaSite(http).playConfigUrls.first.toString(),
        'https://raw.githubusercontent.com/liuchuancong/pure_live/master/assets/play_config.json',
      );
    });
  });

  group('links', () {
    test('numbered room pages on huya.com and its subdomains; aliases need a lookup; other pages are not rooms', () {
      final site = _site(_Http(const []));
      expect(site.roomIdFromUrl('https://www.huya.com/660000'), '660000');
      expect(site.roomIdFromUrl('https://m.huya.com/660000?from=share'), '660000');
      expect(site.roomIdFromUrl('https://huya.com/660000/'), '660000');
      for (final url in [
        'https://www.huya.com.example/660000',
        'https://www.huya.com/g/lol',
        'https://www.huya.com/search?hsk=x',
        'https://www.huya.com/',
        'https://www.huya.com/a.b',
        'https://live.bilibili.com/6',
      ]) {
        expect(site.roomIdFromUrl(url), isNull, reason: url);
        expect(site.needsResolving(url), isFalse, reason: url);
      }
      expect(site.roomIdFromUrl('https://www.huya.com/lpl'), isNull);
      expect(site.needsResolving('https://www.huya.com/lpl'), isTrue);
      expect(site.needsResolving('https://www.huya.com/660000'), isFalse);
    });

    test('an alias is looked up on its room page (profileRoom refuses it, S06-alias)', () async {
      final http = _Http([
        _synthetic(
          'https://www.huya.com/lpl',
          '<script>var TT_ROOM_DATA = {"type":"NORMAL","state":"ON","profileRoom":"660000"};\nvar X = {};</script>',
        ),
        _synthetic('https://www.huya.com/loose', '<script>window.x = {"profileRoom":880351};</script>'),
        _synthetic('https://www.huya.com/nobody', '<html>没有找到该房间</html>'),
        _synthetic(
          'https://www.huya.com/moved',
          '',
          status: 302,
          headers: {
            'location': ['https://www.huya.com/102411'],
          },
        ),
      ]);
      final parser = LinkParser(SiteRegistry({'huya': () => _site(http)}), http);
      expect(await parser.parse('快来看 https://www.huya.com/lpl'), const RoomLink('huya', '660000'));
      expect(await parser.parse('https://m.huya.com/loose'), const RoomLink('huya', '880351'));
      expect(await parser.parse('https://www.huya.com/nobody'), isNull);
      expect(await parser.parse('https://www.huya.com/moved'), const RoomLink('huya', '102411'));
      expect(http.requests.first.headers['user-agent'], HuyaApi.desktopUserAgent);
      expect(http.requests.every((request) => !request.followRedirects), isTrue);
      expect(await parser.parse('https://www.huya.com/660000'), const RoomLink('huya', '660000'));
      expect(http.requests, hasLength(4), reason: 'a numbered page needs no request');
    });
  });

  test('transport failures are NetworkFailure; cancellation passes through', () async {
    await expectLater(
      _site(_Failing(TransportReason.timeout)).getRoomDetail(roomId: '1'),
      throwsA(isA<NetworkFailure>()),
    );
    await expectLater(
      _site(_Failing(TransportReason.cancelled)).getRoomDetail(roomId: '1'),
      throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
    );
  });
}
