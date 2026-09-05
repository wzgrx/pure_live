import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/site/acfun/acfun_api.dart';
import 'package:pure_live/core/site/acfun/acfun_site.dart';

Map<String, dynamic> room({bool live = true}) => {
  'result': 0,
  'authorId': 42,
  'user': {
    'id': '42',
    'name': 'Fixture broadcaster',
    'headUrl': 'https://img.example/avatar.jpg',
    'fanCountValue': 250,
  },
  if (live) ...{
    'liveId': 'live-a',
    'streamName': 'stream-a',
    'title': 'Fixture live',
    'onlineCount': 87,
    'likeCount': 9000000,
  },
};

Map<String, dynamic> representation(String type, int rank, String url, {String? label}) => {
  'qualityType': type,
  'level': rank,
  'url': url,
  'name': ?label,
};

Map<String, dynamic> manifest(List<List<Map<String, dynamic>>> groups) => {
  'liveAdaptiveManifest': [
    for (final group in groups)
      {
        'adaptationSet': {'representation': group},
      },
  ],
};

void main() {
  test('qualities sort by server rank, not response order, and merge CDN lines without changing signatures', () {
    const signed = 'https://cdn.example/high.flv?sign=a%2Bb%2Fc%3D&expires=9';
    final result = AcfunApi.parseQualities(
      jsonEncode(
        manifest([
          [
            representation('HIGH', 50, signed, label: '超清'),
            representation('STANDARD', 30, 'https://cdn.example/low.flv'),
            representation('BLUE_RAY', 130, 'https://cdn.example/best.flv', label: '蓝光 8M'),
          ],
          [representation('HIGH', 50, 'https://backup.example/high.flv'), representation('HIGH', 50, signed)],
        ]),
      ),
    );
    expect(result.map((q) => q.id), ['BLUE_RAY', 'HIGH', 'STANDARD']);
    expect(result[1].urls, [signed, 'https://backup.example/high.flv']);
    expect(result.first.label, '蓝光 8M');
    expect(() => result[1].urls.add('x'), throwsUnsupportedError);
  });

  test('hidden and invalid media are excluded, and unknown quality IDs remain distinct', () {
    final result = AcfunApi.parseQualities(
      manifest([
        [
          representation('FUTURE', 150, 'https://cdn.example/future.flv', label: '原画 60帧'),
          {...representation('HIDDEN', 999, 'https://cdn.example/hide.flv'), 'hidden': true},
          representation('INJECTED', 999, 'javascript:alert(1)'),
          representation('USERINFO', 999, 'https://user:password@cdn.example/video'),
          {'id': 0, 'url': 'https://cdn.example/id.flv', 'bitrate': 1000},
        ],
      ]),
    );
    expect(result.map((q) => q.id), ['FUTURE', 'id:0']);
    expect(result.first.label, '原画 60帧');
  });

  test('a missing name does not invent an 8M bitrate from qualityType', () {
    final q = AcfunApi.parseQualities(
      manifest([
        [representation('BLUE_RAY', 130, 'https://cdn.example/a.flv')],
      ]),
    );
    expect(q.single.label, isNot(contains('8M')));
  });

  for (final raw in <Object?>[
    null,
    '<html>blocked</html>',
    {'liveAdaptiveManifest': {}},
    {'liveAdaptiveManifest': []},
    manifest([
      [
        {'url': 'https://cdn.example/a.flv'},
      ],
    ]),
  ]) {
    test('malformed or empty stream contract is an error (${raw.runtimeType}/${raw.hashCode})', () {
      expect(() => AcfunApi.parseQualities(raw), throwsA(isA<AcfunApiException>()));
    });
  }

  test('only identity-complete successful metadata is authoritative offline', () {
    expect(AcfunApi.validateRoomInfo(room(live: false), '42'), isFalse);
    expect(AcfunApi.validateRoomInfo(room(), '42'), isTrue);
    for (final invalid in <Map<String, dynamic>>[
      {},
      {'result': 0},
      {...room(live: false), 'authorId': 43},
      {...room(), 'streamName': ''},
      {...room(live: false), 'result': 429},
      {
        ...room(live: false),
        'user': {'id': '42'},
      },
    ]) {
      expect(() => AcfunApi.validateRoomInfo(invalid, '42'), throwsA(isA<AcfunApiException>()));
    }
  });

  test('online and likes have separate meanings and unknown counts remain unknown', () {
    final live = AcfunSite.parseRoom(room(), '42');
    expect(live.onlineViewers, '87');
    expect(live.popularity, isEmpty);
    expect(live.liveStatus, LiveStatus.live);
    final unknown = AcfunSite.parseRoom({...room(), 'onlineCount': 'unavailable'}, '42');
    expect(unknown.onlineViewers, isEmpty);
    expect(unknown.watching, isEmpty);
  });

  test('directory retains opaque next cursor and rejects a missing page envelope', () {
    final page = AcfunApi.parseDirectory({
      'channelListData': {
        'result': 0,
        'liveList': [room()],
        'pcursor': 'opaque-next',
      },
    });
    expect(page.rooms, hasLength(1));
    expect(page.nextCursor, 'opaque-next');
    expect(AcfunApi.parseDirectory({'result': 0, 'liveList': [], 'pcursor': 'no_more'}).nextCursor, isNull);
    expect(() => AcfunApi.parseDirectory({'result': 0, 'liveList': []}), throwsA(isA<AcfunApiException>()));
  });

  test('directory and room refresh never request visitor credentials', () async {
    final fixture = _AcfunFixture();
    final api = AcfunApi(request: fixture.request);
    await api.directory(cursor: 'next', count: 900);
    await AcfunSite(api: api).getRoomDetailForRefresh(roomId: '42', platform: 'acfun');
    expect(fixture.logins, 0);
    expect(fixture.playbacks, 0);
    expect(fixture.lastDirectoryQuery, containsPair('count', 60));
    expect(fixture.lastDirectoryQuery, containsPair('pcursor', 'next'));
  });

  test('concurrent playback requests share one visitor login and preserve identity binding', () async {
    final fixture = _AcfunFixture()..visitorBarrier = Completer<void>();
    final api = AcfunApi(request: fixture.request);
    final first = api.playback('42');
    final second = api.playback('43');
    await Future<void>.delayed(Duration.zero);
    expect(fixture.logins, 1);
    fixture.visitorBarrier!.complete();
    await Future.wait([first, second]);
    expect(fixture.playbacks, 2);
    for (final query in fixture.playbackQueries) {
      expect(query['did'], fixture.cookieDid);
      expect(query['userId'], '12345');
      expect(query['acfun.api.visitor_st'], 'fixture-visitor-token');
    }
  });

  test('visitor cache expires and failed authentication is not retained', () async {
    var now = DateTime.utc(2026, 9, 5);
    final fixture = _AcfunFixture();
    final api = AcfunApi(request: fixture.request, clock: () => now);
    await api.playback('42');
    await api.playback('42');
    expect(fixture.logins, 1);
    now = now.add(const Duration(minutes: 6));
    await api.playback('42');
    expect(fixture.logins, 2);
    fixture.playbackResult = 401;
    await expectLater(
      api.playback('42'),
      throwsA(isA<AcfunApiException>().having((e) => e.kind, 'kind', AcfunFailureKind.service)),
    );
    fixture.playbackResult = 1;
    await api.playback('42');
    expect(fixture.logins, 3);
  });

  test('transport, HTML and service failures never become offline recording tasks', () async {
    for (final failure in <Object>[
      'network',
      '<html>403</html>',
      {'result': 403},
    ]) {
      final api = AcfunApi(
        request: (method, url, {query, body, headers}) async {
          if (failure == 'network') throw StateError('fixture-token-in-network-error');
          return failure;
        },
      );
      final site = AcfunSite(api: api);
      await expectLater(
        site.getRoomDetailForRecording(roomId: '42', platform: 'acfun'),
        throwsA(
          isA<AcfunApiException>().having((e) => e.toString(), 'safe diagnostic', isNot(contains('fixture-token'))),
        ),
      );
    }
  });

  test('recording obtains complete quality data while offline rooms skip startPlay', () async {
    final fixture = _AcfunFixture();
    final site = AcfunSite(api: AcfunApi(request: fixture.request));
    final detail = await site.getRoomDetailForRecording(roomId: '42', platform: 'acfun');
    final qualities = await site.getPlayQualites(detail: detail);
    expect(qualities.map((q) => q.selectionId), ['HIGH', 'STANDARD']);
    expect(await site.getPlayUrls(detail: detail, quality: qualities.first), [
      'https://cdn.example/1-high.flv?sign=fixture',
    ]);
    expect(jsonEncode(detail.toJson()), isNot(contains('sign=')));
    fixture.live = false;
    final offline = await site.getRoomDetailForRecording(roomId: '42', platform: 'acfun');
    expect(offline.liveStatus, LiveStatus.offline);
    expect(await site.getPlayQualites(detail: offline), isEmpty);
    expect(fixture.playbacks, 1);
  });

  test('recovery resolves a fresh source but never silently downgrades missing requested quality', () async {
    final fixture = _AcfunFixture();
    final site = AcfunSite(api: AcfunApi(request: fixture.request));
    final old = await site.getRoomDetail(roomId: '42', platform: 'acfun');
    final selected = (await site.getPlayQualites(detail: old)).first;
    final recovered = await site.resolvePlayUrlsForRecoveryRaw(detail: old, quality: selected);
    expect(recovered.appliedQualityData, 'HIGH');
    expect(recovered.urls.single, contains('/2-high.flv'));
    expect((await site.getPlayUrls(detail: old, quality: selected)).single, contains('/1-high.flv'));
    fixture.highAvailable = false;
    await expectLater(
      site.resolvePlayUrlsForRecoveryRaw(detail: old, quality: selected),
      throwsA(isA<AcfunApiException>().having((e) => e.kind, 'kind', AcfunFailureKind.qualityUnavailable)),
    );
  });

  test('malformed author IDs are rejected before issuing any network request', () async {
    final fixture = _AcfunFixture();
    final api = AcfunApi(request: fixture.request);
    for (final id in ['0', '-1', '42&authorId=99', 'https://example.com/42']) {
      await expectLater(api.playback(id), throwsA(isA<AcfunApiException>()));
    }
    expect(fixture.logins, 0);
  });
}

class _AcfunFixture {
  int logins = 0;
  int playbacks = 0;
  bool live = true;
  bool highAvailable = true;
  int playbackResult = 1;
  Completer<void>? visitorBarrier;
  String? cookieDid;
  Map<String, dynamic>? lastDirectoryQuery;
  final playbackQueries = <Map<String, dynamic>>[];

  Future<Object?> request(
    String method,
    String url, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
    Map<String, dynamic>? headers,
  }) async {
    if (url.endsWith('/api/channel/list')) {
      lastDirectoryQuery = query;
      return {
        'channelListData': {
          'result': 0,
          'liveList': [room()],
          'pcursor': 'no_more',
        },
      };
    }
    if (url.endsWith('/api/live/info')) return room(live: live);
    if (url.endsWith('/visitor/login')) {
      logins++;
      expect(method, 'POST');
      expect(body, {'sid': 'acfun.api.visitor'});
      cookieDid = (headers!['Cookie'] as String).substring(5).split(';').first;
      await visitorBarrier?.future;
      return {'result': 0, 'userId': 12345, 'acfun.api.visitor_st': 'fixture-visitor-token'};
    }
    expect(url, 'https://api.kuaishouzt.com/rest/zt/live/web/startPlay');
    expect(method, 'POST');
    expect(body!['pullStreamType'], 'FLV');
    expect(headers!['Referer'], 'https://live.acfun.cn/');
    playbacks++;
    playbackQueries.add(query!);
    return {
      'result': playbackResult,
      'data': {
        'liveId': 'live-$playbacks',
        'videoPlayRes': jsonEncode(
          manifest([
            [
              representation('STANDARD', 30, 'https://cdn.example/$playbacks-low.flv?sign=fixture'),
              if (highAvailable) representation('HIGH', 50, 'https://cdn.example/$playbacks-high.flv?sign=fixture'),
            ],
          ]),
        ),
      },
    };
  }
}
