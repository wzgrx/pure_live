import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/zhanqi/zhanqi_api.dart';

Map<String, dynamic> _json(String name) =>
    jsonDecode(File('test/fixtures/zhanqi/$name.json').readAsStringSync()) as Map<String, dynamic>;
({int status, String body}) _ok(Object value) => (status: 200, body: jsonEncode(value));
Matcher _failure(ZhanqiFailure kind) => throwsA(isA<ZhanqiException>().having((e) => e.kind, 'kind', kind));
ZhanqiDirectoryPage _directory(Map<String, dynamic> json, {int page = 1, int size = 20}) =>
    ZhanqiApi.parseDirectory(json, page: page, pageSize: size);
ZhanqiRoomSnapshot _room(Map<String, dynamic> json) =>
    ZhanqiApi.parseRoom(json, code: '301', expectedRoomId: '101', expectedOwnerId: '201');
String _encoded(String url) => base64.encode(utf8.encode(jsonEncode({'streamUrl': url})));

void main() {
  test('observed directory shape keeps three identities and nullable nickname', () {
    final page = _directory(_json('directory'));
    expect(page.reportedTotal, 5);
    expect(page.rooms, hasLength(5));
    final first = page.rooms.first;
    expect((first.code, first.roomId, first.ownerId), ('301', '101', '201'));
    expect(first.reportedStatus, '4');
    expect(first.reportedLive, isTrue);
    expect(first.declaredStream, isNull);
    expect(page.rooms.last.nickname, isNull);
    expect(page.rooms.last.avatar, '');
    expect(page.rooms.last.reportedOnline, 13233);
    expect(page.hasMore, isFalse);
    expect(() => page.rooms.clear(), throwsUnsupportedError);
  });
  test('native cnt paging is not inferred from the last row count', () {
    final json = _json('directory');
    json['data']['cnt'] = 45;
    expect(_directory(json).hasMore, isTrue);
    expect(_directory(json, page: 3).hasMore, isFalse);
    json['data']['rooms'] = [];
    expect(_directory(json, page: 2).hasMore, isFalse);
  });
  test('observed empty second page with retained total ends traversal', () {
    final page = _directory({
      'code': 0,
      'data': {'cnt': 5, 'rooms': []},
    }, page: 2);
    expect(page.reportedTotal, 5);
    expect(page.hasMore, isFalse);
  });
  test('reported live and decoded declaration remain metadata not verified media', () {
    final room = _room(_json('room'));
    expect(room.reportedLive, isTrue);
    expect(room.declaredStream.toString(), 'https://alhls-cdn.zhanqi.tv/zqlive/101_fixture.m3u8');
  });
  for (final status in ['0', '2', '9']) {
    test('non-live or unknown status $status does not publish stale media', () {
      final json = _json('room');
      json['data']['status'] = status;
      json['data']['flashvars'] = 'stale malformed payload';
      final room = _room(json);
      expect(room.reportedLive, status == '0' ? false : null);
      expect(room.reportedStatus, status);
      expect(room.declaredStream, isNull);
    });
  }
  test('empty live stream declaration preserves status without inventing a source', () {
    final json = _json('room');
    json['data']['flashvars']['VideoLevels'] = _encoded('');
    final room = _room(json);
    expect(room.reportedLive, isTrue);
    expect(room.declaredStream, isNull);
  });
  for (final field in ['code', 'id', 'uid']) {
    test('room rejects mismatched $field before exposing any media', () {
      final json = _json('room');
      json['data'][field] = '999';
      expect(() => _room(json), _failure(ZhanqiFailure.identity));
    });
  }
  for (final field in ['RoomId', 'Status']) {
    test('room and flash declaration must agree on $field', () {
      final json = _json('room');
      json['data']['flashvars'][field] = 0;
      expect(() => _room(json), _failure(field == 'RoomId' ? ZhanqiFailure.identity : ZhanqiFailure.schema));
    });
  }
  test('fractional flash status and a different-room media path are rejected', () {
    final json = _json('room');
    json['data']['flashvars']['Status'] = 4.0;
    expect(() => _room(json), _failure(ZhanqiFailure.schema));
    json['data']['flashvars']['Status'] = 4;
    json['data']['flashvars']['VideoLevels'] = _encoded('https://alhls-cdn.zhanqi.tv/zqlive/102_fixture.m3u8');
    expect(() => _room(json), _failure(ZhanqiFailure.schema));
  });
  for (final invalid in [
    'duplicate-code',
    'duplicate-room',
    'bad-id',
    'bad-status',
    'bad-count',
    'bad-total',
    'bad-nickname',
    'bad-wrapper',
    'string-code',
  ]) {
    test('directory rejects $invalid atomically', () {
      final json = _json('directory');
      final data = json['data'];
      final row = data['rooms'][0];
      switch (invalid) {
        case 'duplicate-code':
          data['rooms'][1]['code'] = row['code'];
        case 'duplicate-room':
          data['rooms'][1]['id'] = row['id'];
        case 'bad-id':
          row['uid'] = '../201';
        case 'bad-status':
          row['status'] = 4;
        case 'bad-count':
          row['online'] = '1.2';
        case 'bad-total':
          data['cnt'] = '5';
        case 'bad-nickname':
          row['nickname'] = 0;
        case 'bad-wrapper':
          json['data'] = [];
        case 'string-code':
          json['code'] = '0';
      }
      expect(() => _directory(json), throwsA(isA<ZhanqiException>()));
    });
  }
  test('unknown counts and images stay distinct from known zero and empty', () {
    final json = _json('directory');
    final row = json['data']['rooms'][0];
    row['online'] = null;
    row['avatar'] = null;
    row['spic'] = null;
    final room = _directory(json).rooms.first;
    expect(room.reportedOnline, isNull);
    expect(room.avatar, isNull);
    expect(room.cover, isNull);
    row['online'] = '9007199254740992';
    expect(() => _directory(json), _failure(ZhanqiFailure.schema));
  });
  test('one owner can legitimately occur in separate room identities', () {
    final json = _json('directory');
    json['data']['rooms'][1]['uid'] = '201';
    expect(_directory(json).rooms, hasLength(5));
  });
  for (final invalid in [
    '%%%',
    base64.encode([0xc3, 0x28]),
    base64.encode(utf8.encode('[]')),
    'A' * 16385,
  ]) {
    test('bounded base64 declaration rejects malformed input ${invalid.length}', () {
      final json = _json('room');
      json['data']['flashvars']['VideoLevels'] = invalid;
      expect(() => _room(json), _failure(ZhanqiFailure.schema));
    });
  }
  for (final url in [
    'file:///tmp/a.m3u8',
    'https://127.0.0.1/zqlive/a.m3u8',
    'https://alhls-cdn.zhanqi.tv.evil.invalid/zqlive/a.m3u8',
    'https://user:secret@alhls-cdn.zhanqi.tv/zqlive/a.m3u8',
    'https://alhls-cdn.zhanqi.tv/zqlive/a.m3u8#part',
    'https://alhls-cdn.zhanqi.tv:444/zqlive/a.m3u8',
    'https://alhls-cdn.zhanqi.tv/other/a.m3u8',
  ]) {
    test('declaration rejects out-of-contract URI $url', () {
      final json = _json('room');
      json['data']['flashvars']['VideoLevels'] = _encoded(url);
      expect(() => _room(json), _failure(ZhanqiFailure.schema));
    });
  }
  test('API calls use fixed endpoint and numeric public code, not topic URL', () async {
    final paths = <Uri>[];
    final tokens = <CancelToken>[];
    final caller = CancelToken();
    final api = ZhanqiApi(
      request: (uri, token) async {
        paths.add(uri);
        tokens.add(token);
        return _ok(_json(uri.path.contains('/domain/') ? 'room' : 'directory'));
      },
    );
    await api.directory(cancel: caller);
    await api.room(code: '301', expectedRoomId: '101', expectedOwnerId: '201', cancel: caller);
    expect(paths.map((uri) => uri.toString()), [
      'https://www.zhanqi.tv/api/static/v2.1/live/list/20/1.json',
      'https://www.zhanqi.tv/api/static/v2.1/room/domain/301.json',
    ]);
    expect(tokens.every((t) => t.isCancelled), isTrue);
    expect(identical(tokens.first, tokens.last), isFalse);
    expect(caller.isCancelled, isFalse);
  });
  test('invalid page and room input never dispatches a request', () async {
    var calls = 0;
    final api = ZhanqiApi(
      request: (_, _) async {
        calls++;
        return _ok({});
      },
    );
    for (final id in ['', '0', '../301', '301.json?a=1', '/topic/fixture', ' 301', '0301', '1' * 21]) {
      await expectLater(api.room(code: id), _failure(ZhanqiFailure.identity));
    }
    for (final page in [0, -1, 10001]) {
      await expectLater(api.directory(page: page), _failure(ZhanqiFailure.schema));
    }
    for (final size in [0, 101]) {
      await expectLater(api.directory(pageSize: size), _failure(ZhanqiFailure.schema));
    }
    await expectLater(api.room(code: '301', expectedRoomId: '../101'), _failure(ZhanqiFailure.identity));
    expect(calls, 0);
  });
  for (final status in [302, 401, 403, 404, 429, 503]) {
    test('HTTP $status is an error rather than an offline room', () async {
      final api = ZhanqiApi(request: (_, _) async => (status: status, body: 'private payload'));
      final kind = switch (status) {
        401 || 403 => ZhanqiFailure.access,
        404 => ZhanqiFailure.missing,
        429 => ZhanqiFailure.rateLimited,
        503 => ZhanqiFailure.service,
        _ => ZhanqiFailure.transport,
      };
      await expectLater(api.room(code: '301'), _failure(kind));
    });
  }
  test('nonzero business code is not fabricated missing or offline', () async {
    final api = ZhanqiApi(request: (_, _) async => _ok({'code': 2, 'message': 'private response'}));
    await expectLater(api.room(code: '301'), _failure(ZhanqiFailure.api));
    expect(const ZhanqiException(ZhanqiFailure.api).toString(), 'Zhanqi api');
  });
  test('UTF8, JSON and aggregate-byte limits are enforced', () async {
    await expectLater(ZhanqiApi.readBody(Stream.value([0xc3, 0x28])), _failure(ZhanqiFailure.schema));
    await expectLater(
      ZhanqiApi.readBody(
        Stream.fromIterable([
          List.filled(ZhanqiApi.responseLimit, 32),
          [32],
        ]),
      ),
      _failure(ZhanqiFailure.schema),
    );
    for (final body in ['not JSON', '[]', '一' * (ZhanqiApi.responseLimit ~/ 3 + 1)]) {
      await expectLater(
        ZhanqiApi(request: (_, _) async => (status: 200, body: body)).directory(),
        _failure(ZhanqiFailure.schema),
      );
    }
  });
  test('total deadline owns cancellation and consumes late failures', () async {
    final pending = Completer<({int status, String body})>();
    CancelToken? owned;
    final caller = CancelToken();
    final api = ZhanqiApi(
      deadline: const Duration(milliseconds: 20),
      request: (_, token) {
        owned = token;
        return pending.future;
      },
    );
    await expectLater(api.directory(cancel: caller), _failure(ZhanqiFailure.transport));
    expect(owned!.isCancelled, isTrue);
    expect(caller.isCancelled, isFalse);
    pending.completeError(const SocketException('late response'));
    await Future<void>.delayed(Duration.zero);
  });
  test('already cancelled API scope dispatches neither directory nor room', () async {
    var requests = 0;
    final api = ZhanqiApi(
      request: (_, _) async {
        requests++;
        return _ok({});
      },
    );
    final token = CancelToken()..cancel();
    await expectLater(api.directory(cancel: token), _failure(ZhanqiFailure.cancelled));
    await expectLater(api.room(code: '301', cancel: token), _failure(ZhanqiFailure.cancelled));
    expect(requests, 0);
  });
}
