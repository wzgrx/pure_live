import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/site/inke/inke_api.dart';
import 'package:pure_live/model/live_play_quality.dart';

const _media = 'https://live-pull-ws.ikstatic.cn/live/200_t.flv?wsSecret=fixture%2Bonly&wsABStime=70000000';
Map<String, dynamic> _row({int uid = 100, String broadcast = '200', String url = _media}) => {
  'uid': uid,
  'live_id': broadcast,
  'nick': 'Fixture',
  'level': 60,
  'gender': 0,
  'portrait': 'https://img.ikstatic.cn/fixture.jpg',
  'stream_addr': url,
};
Map<String, dynamic> _info({String broadcast = '200'}) => {
  'live_uid': '100',
  'liveid': broadcast,
  'status': 1,
  'live_name': 'Music',
  'media_info': {'inke_id': 100, 'nick': 'Fixture', 'level': 60, 'portrait': 'https://img.ikstatic.cn/fixture.jpg'},
  'portrait': 'https://img.ikstatic.cn/fixture.jpg',
  'records': [],
};
Map<String, dynamic> _group({String key = 'MUSIC', List<Object>? rows}) => {
  'tab_key': key,
  'channel_name': 'Music',
  'list': rows ?? [_row()],
};
({int status, String body}) _ok(Object? data) => (status: 200, body: jsonEncode({'error_code': 0, 'data': data}));
Matcher _failure(InkeFailure kind) => throwsA(isA<InkeException>().having((e) => e.kind, 'kind', kind));
List<String> _urls(LiveRoom room) => (room.data as List<LivePlayQuality>).single.data as List<String>;

void main() {
  test('UID is durable, exact public room links ignore stale broadcast IDs', () {
    for (final host in ['inke.cn', 'www.inke.cn', 'inke.com', 'www.inke.com']) {
      expect(InkeApi.roomFromUri(Uri.parse('https://$host/liveroom/index.html?uid=100&id=999')), '100');
    }
    for (final uri in [
      'https://www.inke.cn.evil.test/liveroom/index.html?uid=100',
      'https://name@www.inke.cn/liveroom/index.html?uid=100',
      'https://www.inke.cn:8787/liveroom/index.html?uid=100',
      'https://www.inke.cn/?uid=100',
      'https://www.inke.cn/liveroom/index.html?uid=100&uid=101',
      'file:///liveroom/index.html?uid=100',
      'https://www.inke.cn/liveroom/index.html?uid=0',
    ]) {
      expect(InkeApi.roomFromUri(Uri.parse(uri)), isNull, reason: uri);
    }
  });

  test('finite showcase deduplicates UID without fabricating audience or further pages', () async {
    var calls = 0;
    final api = InkeApi(
      request: (uri, _) async {
        expect(uri.path, '/web/Live_top_pc');
        calls++;
        return _ok({
          'list': [_row(), _row(), _row(uid: 101)],
        });
      },
    );
    final page = await api.directoryPage();
    expect(page.rooms.map((r) => r.roomId), ['100', '101']);
    expect(page.rooms.first.watching, isEmpty);
    expect(page.rooms.first.audienceMetricType, AudienceMetricType.unknown);
    expect(page.hasMore, isFalse);
    expect((await api.directoryPage(page: 2)).rooms, isEmpty);
    expect(calls, 1);
    expect(() => page.rooms.add(LiveRoom()), throwsUnsupportedError);
  });

  test('category keys select the real server group, independent of list order', () async {
    final api = InkeApi(
      request: (_, _) async => _ok({
        'list': [
          _group(),
          _group(key: 'CHAT', rows: [_row(uid: 101)]),
        ],
      }),
    );
    final categories = await api.categories();
    expect(categories.map((a) => a.areaId), ['MUSIC', 'CHAT']);
    expect(categories.every((a) => a.areaType == 'showcase'), isTrue);
    expect((await api.directoryPage(category: categories.last)).rooms.single.roomId, '101');
    categories.last.areaId = 'missing';
    await expectLater(api.directoryPage(category: categories.last), _failure(InkeFailure.notFound));
  });

  test('same-group duplication and malformed bucket shapes are schema errors', () async {
    for (final groups in [
      [_group(), _group()],
      [_group()..['list'] = {}],
      [_group(key: '../path')],
    ]) {
      final api = InkeApi(request: (_, _) async => _ok({'list': groups}));
      await expectLater(api.categories(), _failure(InkeFailure.schema));
    }
  });

  test('metadata-only lookup accepts observed integer status and never resolves media', () async {
    var calls = 0;
    final api = InkeApi(
      request: (uri, _) async {
        calls++;
        expect(uri.queryParameters, {'uid': '100'});
        return _ok(_info());
      },
    );
    final room = await api.detail('100', playback: false);
    expect(room.isLiveNow, isTrue);
    expect(room.roomId, '100');
    expect(room.title, 'Music');
    expect(room.data, isNull);
    expect(room.watching, isEmpty);
    expect(calls, 1);
  });

  test('playback pairs current UID AND broadcast ID and preserves the signed query', () async {
    final paths = <String>[];
    final api = InkeApi(
      request: (uri, _) async {
        paths.add(uri.path);
        return uri.path.endsWith('live_share_pc')
            ? _ok(_info())
            : _ok({
                'list': [_row(uid: 101), _row(broadcast: '199'), _row()],
              });
      },
    );
    final room = await api.detail('100');
    expect(paths, ['/web/live_share_pc', '/web/Live_top_pc']);
    expect(_urls(room), [_media]);
    expect((room.data as List<LivePlayQuality>).single.selectionId, 'flv');
    expect(() => _urls(room).add('other'), throwsUnsupportedError);
    expect(room.link, contains('uid=100&id=200'));
  });

  for (final foundIn in ['hot', 'channel']) {
    test('media falls through showcases in a bounded way ($foundIn)', () async {
      final paths = <String>[];
      final api = InkeApi(
        request: (uri, _) async {
          paths.add(uri.path);
          return switch (uri.path) {
            '/web/live_share_pc' => _ok(_info()),
            '/web/Live_top_pc' => _ok({'list': []}),
            '/web/Live_hot_pc' => _ok({
              'list': {
                'recommend': foundIn == 'hot' ? [_row()] : [],
                'hot': [],
              },
            }),
            '/web/Live_channel_pc' => _ok({
              'list': [_group()],
            }),
            _ => throw StateError('unexpected endpoint'),
          };
        },
      );
      expect(_urls(await api.detail('100')), [_media]);
      expect(paths.length, foundIn == 'hot' ? 3 : 4);
    });
  }

  test('renewed detail reacquires broadcast identity, not a cached signed source', () async {
    var broadcast = '200';
    final api = InkeApi(
      request: (uri, _) async => uri.path.endsWith('live_share_pc')
          ? _ok(_info(broadcast: broadcast))
          : _ok({
              'list': [_row(broadcast: broadcast, url: _media.replaceAll('200_t', '${broadcast}_t'))],
            }),
    );
    final first = await api.detail('100');
    broadcast = '201';
    final next = await api.detail('100');
    expect(first.roomId, next.roomId);
    expect(_urls(first), [_media]);
    expect(_urls(next).single, contains('/201_t.flv?'));
  });

  test('missing or stale showcase media is unavailable, never fabricated offline', () async {
    final api = InkeApi(
      request: (uri, _) async => switch (uri.path) {
        '/web/live_share_pc' => _ok(_info()),
        '/web/Live_top_pc' => _ok({
          'list': [_row(broadcast: '199')],
        }),
        '/web/Live_hot_pc' => _ok({
          'list': {'hot': []},
        }),
        _ => _ok({'list': []}),
      },
    );
    await expectLater(api.detail('100'), _failure(InkeFailure.mediaUnavailable));
    expect((await api.detail('100', playback: false)).isLiveNow, isTrue);
  });

  test('only observed no-current-broadcast code returns explicit offline', () async {
    final api = InkeApi(request: (_, _) async => (status: 200, body: '{"error_code":1099999920,"data":null}'));
    expect((await api.detail('100')).isExplicitlyOfflineNow, isTrue);
    await expectLater(api.directoryPage(), _failure(InkeFailure.service));
    final unknown = InkeApi(request: (_, _) async => (status: 200, body: '{"error_code":12345,"data":null}'));
    await expectLater(unknown.detail('100'), _failure(InkeFailure.service));
  });

  for (final mutate in ['owner', 'uid', 'status', 'data-sentinel']) {
    test('bad metadata is not playable or offline ($mutate)', () async {
      final data = _info();
      switch (mutate) {
        case 'owner':
          data['media_info'] = {'inke_id': 101, 'nick': 'Other'};
        case 'uid':
          data['live_uid'] = '101';
        case 'status':
          data['status'] = 2;
        case 'data-sentinel':
          data.clear();
          data['noCurrentBroadcast'] = true;
      }
      final api = InkeApi(request: (_, _) async => _ok(data));
      await expectLater(api.detail('100'), _failure(InkeFailure.schema));
    });
  }

  for (final code in [302, 401, 403, 404, 429, 500]) {
    test('HTTP $code remains a typed failure, not room status', () async {
      final api = InkeApi(
        request: (_, _) async => (status: code, body: 'sensitive response must not appear in errors'),
      );
      await expectLater(
        api.detail('100'),
        _failure(switch (code) {
          401 || 403 => InkeFailure.access,
          404 => InkeFailure.notFound,
          429 => InkeFailure.rateLimited,
          500 => InkeFailure.service,
          _ => InkeFailure.transport,
        }),
      );
    });
  }

  test('media validation does not rewrite hosts, broadcasts, encrypted paths or protocols', () {
    expect(InkeApi.plainFlv(_media, broadcastId: '200'), _media);
    for (final url in [
      _media.replaceAll('ikstatic.cn', 'ikstatic.cn.evil.test'),
      _media.replaceAll('200_t', '201_t'),
      _media.replaceAll('200_t', '200_0_en'),
      _media.replaceAll('https:', 'file:'),
      _media.replaceAll('https://', 'https://name@'),
      '$_media#fragment',
    ]) {
      expect(InkeApi.plainFlv(url, broadcastId: '200'), isNull);
    }
  });

  test('cancelled preflight and late responses do not start a second request', () async {
    final response = Completer<({int status, String body})>();
    var calls = 0;
    final api = InkeApi(
      request: (_, _) {
        calls++;
        return response.future;
      },
    );
    final before = CancelToken()..cancel();
    await expectLater(api.detail('100', cancel: before), _failure(InkeFailure.cancelled));
    expect(calls, 0);
    final after = CancelToken();
    final request = api.detail('100', cancel: after);
    after.cancel();
    response.complete(_ok(_info()));
    await expectLater(request, _failure(InkeFailure.cancelled));
    expect(calls, 1);
  });

  test('transport failure and malformed envelopes stay diagnostic and bounded', () async {
    await expectLater(
      InkeApi(request: (_, _) async => throw StateError('secret')).detail('100'),
      _failure(InkeFailure.transport),
    );
    for (final body in [
      'not json',
      '[]',
      '{"data":{}}',
      '{"error_code":0,"data":[]}',
      'x' * (InkeApi.responseLimit + 1),
    ]) {
      await expectLater(
        InkeApi(request: (_, _) async => (status: 200, body: body)).detail('100'),
        _failure(InkeFailure.schema),
      );
    }
  });

  test('body reader preserves UTF8 chunks and releases stream after overrun or bad encoding', () async {
    final bytes = utf8.encode('映客');
    expect(await InkeApi.readBody(Stream.fromIterable(bytes.map((b) => [b]))), '映客');
    await expectLater(InkeApi.readBody(Stream.value([255])), _failure(InkeFailure.schema));
    var cancelled = false;
    final stream = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    final read = InkeApi.readBody(stream.stream);
    stream.add(List.filled(InkeApi.responseLimit + 1, 0));
    await expectLater(read, _failure(InkeFailure.schema));
    expect(cancelled, isTrue);
    await stream.close();
  });

  test('body deadline cancels a stalled stream', () async {
    var cancelled = false;
    final stream = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    final read = InkeApi.readBody(stream.stream, timeout: const Duration(milliseconds: 20));
    await expectLater(read, throwsA(isA<TimeoutException>()));
    expect(cancelled, isTrue);
    await stream.close();
  });
}
