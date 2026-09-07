import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/missevan/missevan_api.dart';
import 'package:pure_live/core/site/missevan/missevan_site.dart';
import 'package:pure_live/model/live_play_quality.dart';

const _hls = 'http://d1-missevan104.bilivideo.com/live/sample.m3u8?expires=1900000000&sign=fixture%2Bonly';
const _flv = 'http://d1-missevan04.bilivideo.com/live/sample.flv?expires=1900000000&sign=fixture';

Map<String, dynamic> _row(int id, {int open = 1}) => {
  'room_id': id,
  'creator_id': 200,
  'creator_username': 'Fixture',
  'name': '音频测试',
  'cover_url': 'https://static.maoercdn.com/fixture.png',
  'creator_iconurl': '//static.maoercdn.com/avatar.png',
  'status': {'open': open, 'broadcasting': false},
  'statistics': {'score': 321, 'online': 0, 'accumulation': 9000, 'attention_count': 12},
  'channel': {'hls_pull_url': _hls, 'flv_pull_url': _flv},
};
Map<String, dynamic> _detail({int id = 100, int open = 1}) => {
  'room': _row(id, open: open),
  'creator': {'user_id': 200, 'iconurl': 'https://static.maoercdn.com/avatar.png', 'introduction': 'fixture'},
};
({int status, String body}) _ok(Object? info) => (status: 200, body: jsonEncode({'code': 0, 'info': info}));
Matcher _failure(MissevanFailure kind) => throwsA(isA<MissevanException>().having((error) => error.kind, 'kind', kind));
MissevanApi _fixed(Object? info) => MissevanApi(request: (_, _) async => _ok(info));

Map<String, dynamic> _page(int p, {int count = 65}) => {
  'pagination': {'p': p, 'pagesize': 20, 'maxpage': (count + 19) ~/ 20, 'count': count},
  'Datas': [for (var i = (p - 1) * 20; i < p * 20 && i < count; i++) _row(i + 1)],
};

void main() {
  group('public detail contract', () {
    test('HTTPS streams, stable transport IDs, score is heat rather than viewers', () async {
      final site = MissevanSite(api: _fixed(_detail()));
      final room = await site.getRoomDetail(roomId: '100', platform: 'missevan');
      expect(room.isLiveNow, isTrue);
      expect(room.link, 'https://fm.missevan.com/live/100');
      expect(room.effectivePopularity, '321');
      expect(room.effectiveOnlineViewers, isEmpty);
      expect(room.effectiveTotalViewers, isEmpty);
      expect(room.effectiveAudienceMetricType, AudienceMetricType.popularity);
      expect(room.followers, '12');
      final qualities = await site.getPlayQualites(detail: room);
      expect(qualities.map((q) => q.selectionId), ['hls', 'flv']);
      final urls = await site.getPlayUrls(detail: room, quality: qualities.first);
      expect(urls, [_hls.replaceFirst('http:', 'https:')]);
      expect(() => urls.add('extra'), throwsUnsupportedError);
      expect(() => qualities.clear(), throwsUnsupportedError);
    });

    test('offline ignores stale malformed playback data', () async {
      final info = _detail(open: 0);
      (info['room'] as Map)['channel'] = 'stale';
      final site = MissevanSite(api: _fixed(info));
      final room = await site.getRoomDetail(roomId: '100', platform: 'missevan');
      expect(room.isExplicitlyOfflineNow, isTrue);
      expect(await site.getPlayQualites(detail: room), isEmpty);
      expect(await site.getLiveStatus(platform: 'missevan', roomId: '100'), isFalse);
    });

    test('missing, nonbinary and boolean live states are not offline', () async {
      for (final open in [null, 2, true, 'invalid']) {
        final info = _detail();
        (info['room'] as Map)['status'] = {'open': open};
        await expectLater(_fixed(info).detail('100'), _failure(MissevanFailure.schema));
      }
    });

    test('mismatched room or creator identity is rejected', () async {
      await expectLater(_fixed(_detail(id: 101)).detail('100'), _failure(MissevanFailure.schema));
      final info = _detail();
      (info['creator'] as Map)['user_id'] = 201;
      await expectLater(_fixed(info).detail('100'), _failure(MissevanFailure.schema));
    });

    test('live stream omission and malformed declared stream are explicit errors', () async {
      for (final channel in [
        {},
        {'hls_pull_url': 10},
        {'flv_pull_url': 'https://example.org/a.flv'},
      ]) {
        final info = _detail();
        (info['room'] as Map)['channel'] = channel;
        await expectLater(_fixed(info).detail('100'), _failure(MissevanFailure.schema));
      }
      final info = _detail();
      (info['room'] as Map)['channel'] = {'flv_pull_url': _flv};
      expect((await _fixed(info).detail('100')).data, hasLength(1));
    });

    test('wrong platform, pending room and absent quality are rejected', () async {
      final site = MissevanSite(api: _fixed(_detail()));
      expect(() => site.getRoomDetail(roomId: '100', platform: 'other'), _failure(MissevanFailure.schema));
      final pending = LiveRoom(platform: 'missevan', roomId: '100', liveStatus: LiveStatus.unknown);
      await expectLater(site.getPlayQualites(detail: pending), _failure(MissevanFailure.schema));
      final room = await site.getRoomDetail(roomId: '100', platform: 'missevan');
      await expectLater(
        site.getPlayUrls(
          detail: room,
          quality: LivePlayQuality(id: 'other', quality: 'HLS'),
        ),
        _failure(MissevanFailure.qualityUnavailable),
      );
    });

    test('recovery obtains fresh URLs by stable identity, not stale signed data', () async {
      var calls = 0;
      final site = MissevanSite(
        api: MissevanApi(
          request: (uri, cancel) async {
            expect(uri.toString(), 'https://fm.missevan.com/api/v2/live/100');
            final info = _detail();
            ((info['room'] as Map)['channel'] as Map)['hls_pull_url'] = '$_hls&generation=${++calls}';
            return _ok(info);
          },
        ),
      );
      final room = await site.getRoomDetailForRecording(roomId: '100', platform: 'missevan');
      final quality = (await site.getPlayQualites(detail: room)).first;
      final refreshed = await site.resolvePlayUrlsForRecovery(detail: room, quality: quality);
      expect(refreshed.appliedQualityData, 'hls');
      expect(refreshed.urls.single, endsWith('generation=2'));
      expect((quality.data as List).single, endsWith('generation=1'));
      expect(calls, 2);
    });

    test('recovery does not resurrect an offline broadcast', () async {
      var calls = 0;
      final site = MissevanSite(
        api: MissevanApi(request: (_, _) async => _ok(_detail(open: calls++ == 0 ? 1 : 0))),
      );
      final room = await site.getRoomDetail(roomId: '100', platform: 'missevan');
      await expectLater(
        site.resolvePlayUrlsForRecovery(
          detail: room,
          quality: (await site.getPlayQualites(detail: room)).first,
        ),
        _failure(MissevanFailure.qualityUnavailable),
      );
    });
  });

  group('directory and categories', () {
    test('native pagination retains rows beyond nominal pagesize, without offset truncation', () async {
      final pages = <int>[];
      final api = MissevanApi(
        request: (uri, _) async {
          expect(uri.path, '/api/v2/chatroom/open/list');
          final p = int.parse(uri.queryParameters['p']!);
          pages.add(p);
          final info = _page(p);
          if (p == 1) (info['Datas'] as List).insertAll(3, <Map<String, dynamic>>[_row(900), _row(901)]);
          return _ok(info);
        },
      );
      final first = await api.directoryPage();
      final second = await api.directoryPage(page: first.page + 1);
      final third = await api.directoryPage(page: 3);
      final fourth = await api.directoryPage(page: 4);
      expect(first.rooms, hasLength(22));
      expect(first.rooms.map((room) => room.roomId), containsAll(['900', '901', '19', '20']));
      expect(first.hasMore, isTrue);
      expect(second.rooms.map((room) => room.roomId), [for (var i = 21; i <= 40; i++) '$i']);
      expect(third.rooms.map((room) => room.roomId), [for (var i = 41; i <= 60; i++) '$i']);
      expect(fourth.rooms.map((room) => room.roomId), ['61', '62', '63', '64', '65']);
      expect(fourth.hasMore, isFalse);
      expect(pages, [1, 2, 3, 4]);
      expect((await api.directoryPage(page: 5)).rooms, isEmpty);
    });

    test('zero results are empty and response echo/size drift is not empty', () async {
      expect(await _fixed(_page(1, count: 0)).directory(), isEmpty);
      for (final change in [
        {'p': 2},
        {'pagesize': 30},
        {'maxpage': -1},
        {'count': -1},
      ]) {
        final info = _page(1);
        (info['pagination'] as Map).addAll(change);
        await expectLater(_fixed(info).directory(), _failure(MissevanFailure.schema));
      }
      final info = _page(1);
      info['Datas'] = List.generate(101, (index) => _row(index + 1));
      await expectLater(_fixed(info).directory(), _failure(MissevanFailure.schema));
    });

    test('deduplicates the native page and excludes closed rooms', () async {
      final info = _page(1);
      info['Datas'] = [_row(1), _row(1), _row(2, open: 0), _row(3)];
      final rooms = await _fixed(info).directory(pageSize: 20);
      expect(rooms.map((room) => room.roomId), ['1', '3']);
      // broadcasting=false in directory fixtures is not an offline signal.
      expect(rooms.every((room) => room.isLiveNow), isTrue);
    });

    test('catalog and tag IDs remain distinct; only appropriate filter is sent', () async {
      final tabs = [
        {'type': 'catalog', 'catalog_id': 1, 'name': '音乐'},
        {'type': 'tag', 'tag_id': 1, 'name': '新星'},
      ];
      final areas = await _fixed({'tabs': tabs}).categories();
      expect(areas.map((area) => area.areaType), ['catalog', 'tag']);
      final queries = <Map<String, String>>[];
      final api = MissevanApi(
        request: (uri, _) async {
          queries.add(uri.queryParameters);
          return _ok(_page(1, count: 0));
        },
      );
      for (final area in areas) {
        await api.directory(category: area);
      }
      expect(queries, [
        {'catalog_id': '1', 'p': '1'},
        {'tag_id': '1', 'p': '1'},
      ]);
      await expectLater(
        api.directory(
          category: LiveArea(platform: 'other', areaType: 'catalog', areaId: '1'),
        ),
        _failure(MissevanFailure.schema),
      );
    });

    test('malformed or duplicated category tabs are rejected', () async {
      for (final tabs in [
        [],
        [
          {'type': 'unknown', 'unknown_id': 1, 'name': 'x'},
        ],
        [
          {'type': 'catalog', 'catalog_id': 1, 'name': 'x'},
          {'type': 'catalog', 'catalog_id': 1, 'name': 'y'},
        ],
      ]) {
        await expectLater(_fixed({'tabs': tabs}).categories(), _failure(MissevanFailure.schema));
      }
    });

    test('invalid pages and category IDs make no request', () async {
      var calls = 0;
      final api = MissevanApi(
        request: (_, _) async {
          calls++;
          return _ok({});
        },
      );
      for (final page in [0, -1, 10001]) {
        await expectLater(api.directory(page: page), _failure(MissevanFailure.schema));
      }
      for (final size in [0, 101]) {
        await expectLater(api.directory(pageSize: size), _failure(MissevanFailure.schema));
      }
      await expectLater(
        api.directory(
          category: LiveArea(platform: 'missevan', areaType: 'tag', areaId: '../1'),
        ),
        _failure(MissevanFailure.schema),
      );
      expect(calls, 0);
    });
  });

  group('origin, media and lease boundaries', () {
    test('exact public room links only; numbers never become arbitrary paths', () {
      expect(MissevanApi.roomFromUri(Uri.parse('https://fm.missevan.com/live/100/?share=1')), '100');
      for (final input in [
        'https://fm.missevan.com.evil/live/100',
        'https://evil@fm.missevan.com/live/100',
        'https://fm.missevan.com:8787/live/100',
        'https://fm.missevan.com/api/v2/live/100',
        'https://fm.missevan.com/live/100/movie',
        'https://fm.missevan.com/live/%2F100',
        'file:///live/100',
      ]) {
        expect(MissevanApi.roomFromUri(Uri.parse(input)), isNull, reason: input);
      }
      for (final input in ['0', '-1', '1/2', '../100', '01', '100?x=1']) {
        expect(() => MissevanApi.roomId(input), _failure(MissevanFailure.schema));
      }
    });

    test('HTTPS upgrade preserves escaped signature and clears HTTP default port', () {
      expect(MissevanApi.mediaUrl(_hls, kind: 'hls'), _hls.replaceFirst('http:', 'https:'));
      final explicit = _hls.replaceFirst('.com/', '.com:80/');
      expect(MissevanApi.mediaUrl(explicit, kind: 'hls'), _hls.replaceFirst('http:', 'https:'));
    });

    test('foreign media hosts, user info, ports, suffixes and ambiguous expiry are rejected', () {
      for (final value in [
        'https://bilivideo.com.evil/sample.m3u8',
        'https://127.0.0.1/sample.m3u8',
        'https://user@d1.bilivideo.com/sample.m3u8',
        'https://d1.bilivideo.com:81/sample.m3u8',
        'https://d1.bilivideo.com/sample.flv',
        'https://d1.bilivideo.com/sample.m3u8#fragment',
        'https://d1.bilivideo.com/sample.m3u8?expires=1900000000000',
        '$_hls&expires=1900000001',
      ]) {
        expect(() => MissevanApi.mediaUrl(value, kind: 'hls'), _failure(MissevanFailure.schema));
      }
    });

    test('Unix seconds hard expiry is separate from the early refresh deadline', () {
      final site = MissevanSite();
      final expiry = DateTime.fromMillisecondsSinceEpoch(1900000000000, isUtc: true);
      expect(site.getPlayUrlInvalidAt(_hls), expiry);
      expect(site.getPlayUrlRefreshAt(_hls), expiry.subtract(const Duration(minutes: 1)));
      expect(site.getPlayUrlInvalidAt('https://d1.bilivideo.com/sample.m3u8'), isNull);
      expect(site.getPlayUrlInvalidAt('https://example.org/a.m3u8?expires=1900000000'), isNull);
    });
  });

  group('failure and cancellation contracts', () {
    test('HTTP failures never masquerade as offline', () async {
      for (final entry in {
        401: MissevanFailure.access,
        403: MissevanFailure.access,
        404: MissevanFailure.notFound,
        429: MissevanFailure.rateLimited,
        503: MissevanFailure.service,
        302: MissevanFailure.transport,
      }.entries) {
        final api = MissevanApi(request: (_, _) async => (status: entry.key, body: 'signed URL should not be logged'));
        await expectLater(api.detail('100'), _failure(entry.value));
      }
    });

    test('unknown API errors, invalid JSON and missing envelopes remain errors', () async {
      for (final body in ['{}', '[]', '<html>challenge</html>', '{"code":0,"info":null}', '{"code":true,"info":{}}']) {
        await expectLater(
          MissevanApi(request: (_, _) async => (status: 200, body: body)).detail('100'),
          _failure(MissevanFailure.schema),
        );
      }
      for (final entry in {99: MissevanFailure.service, 500030004: MissevanFailure.notFound}.entries) {
        await expectLater(
          MissevanApi(request: (_, _) async => (status: 200, body: jsonEncode({'code': entry.key}))).detail('100'),
          _failure(entry.value),
        );
      }
    });

    test('cancellation before request, after response and after thrown transport wins', () async {
      final cancelled = CancelToken()..cancel();
      var calls = 0;
      final api = MissevanApi(
        request: (_, _) async {
          calls++;
          return _ok(_detail());
        },
      );
      await expectLater(api.detail('100', cancel: cancelled), _failure(MissevanFailure.cancelled));
      expect(calls, 0);
      for (final fail in [false, true]) {
        final cancel = CancelToken();
        final api = MissevanApi(
          request: (_, token) async {
            expect(identical(token, cancel), isTrue);
            cancel.cancel();
            if (fail) throw StateError('transport');
            return _ok(_detail());
          },
        );
        await expectLater(api.detail('100', cancel: cancel), _failure(MissevanFailure.cancelled));
      }
    });

    test('cancellation after directory response suppresses rows', () async {
      final cancel = CancelToken();
      var calls = 0;
      final api = MissevanApi(
        request: (_, _) async {
          calls++;
          cancel.cancel();
          return _ok(_page(1));
        },
      );
      await expectLater(api.directory(cancel: cancel), _failure(MissevanFailure.cancelled));
      expect(calls, 1);
    });

    test('errors disclose only classification, never response URL or credentials', () async {
      final api = MissevanApi(request: (_, _) async => throw StateError('https://example.org/?token=secret'));
      try {
        await api.detail('100');
        fail('expected failure');
      } on MissevanException catch (error) {
        expect(error.toString(), 'Missevan transport');
      }
    });

    test('injected payload has the same UTF-8 byte ceiling', () async {
      final body = jsonEncode({
        'code': 0,
        'info': {'large': List.filled(400000, '音').join()},
      });
      expect(body.length, lessThan(MissevanApi.responseLimit));
      await expectLater(
        MissevanApi(request: (_, _) async => (status: 200, body: body)).categories(),
        _failure(MissevanFailure.schema),
      );
    });
  });

  group('bounded response body ownership', () {
    test('decodes split UTF-8 exactly and cancels on invalid encoding', () async {
      final bytes = utf8.encode('音频');
      expect(await MissevanApi.readBody(Stream.fromIterable([bytes.sublist(0, 1), bytes.sublist(1)])), '音频');
      await expectLater(MissevanApi.readBody(Stream.value([0xff])), _failure(MissevanFailure.schema));
    });

    test('oversize body relinquishes its subscription', () async {
      var cancelled = false;
      final controller = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      final future = MissevanApi.readBody(controller.stream);
      controller.add(Uint8List(MissevanApi.responseLimit + 1));
      await expectLater(future, _failure(MissevanFailure.schema));
      expect(cancelled, isTrue);
      await controller.close();
    });

    test('slow trickle cannot renew the total body deadline', () async {
      var cancelled = false;
      Timer? producer;
      final controller = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
          producer?.cancel();
        },
      );
      producer = Timer.periodic(const Duration(milliseconds: 5), (_) => controller.add([32]));
      await expectLater(
        MissevanApi.readBody(controller.stream, timeout: const Duration(milliseconds: 60)),
        throwsA(isA<TimeoutException>()),
      );
      expect(cancelled, isTrue);
      expect(producer.isActive, isFalse);
      await controller.close();
    });
  });
}
