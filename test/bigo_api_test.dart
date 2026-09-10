import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/bigo/bigo_api.dart';

Map<String, dynamic> _json(String name) =>
    jsonDecode(File('test/fixtures/bigo/$name.json').readAsStringSync()) as Map<String, dynamic>;
({int status, String body}) _ok(Object body) => (status: 200, body: jsonEncode(body));
Matcher _failure(BigoFailure kind) => throwsA(isA<BigoException>().having((e) => e.kind, 'kind', kind));
BigoStudioStatus _studio(Map<String, dynamic> json) =>
    BigoApi.parseStudioStatus(json, siteId: 'fixture_101', expectedOwnerId: 101);

void main() {
  test('September 10 directory fixture retains separate int64 broadcast identities', () {
    final rows = BigoApi.parseDirectory(_json('recommendations'));
    expect(rows.map((row) => row.siteId), ['fixture_0', 'fixture_1']);
    expect(rows.map((row) => row.ownerId), [100, 101]);
    expect(rows.map((row) => row.broadcastId), ['7000000000000000001', '7000000000000000002']);
    expect(rows.map((row) => row.nickname), ['样本 0', '样本 1']);
  });
  test('September 10 login fixture correlates owner before classifying the gate', () {
    final json = _json('login-gate');
    final status = BigoApi.parseStudioStatus(json, siteId: 'fixture_0', expectedOwnerId: 100);
    expect(status.access, BigoAccess.loginRequired);
    expect(status.reportedAlive, isNull);
    expect(status.canonicalSiteId, 'fixture_0');
    expect(
      () => BigoApi.parseStudioStatus(json, siteId: 'fixture_0', expectedOwnerId: 101),
      _failure(BigoFailure.identity),
    );
  });
  test('real directory envelope retains public ID, owner, int64 broadcast and viewer value separately', () {
    final rows = BigoApi.parseDirectory(_json('directory'));
    final room = rows.single;
    expect(room.siteId, 'fixture_101');
    expect(room.ownerId, 101);
    expect(room.sid, 202);
    expect(room.broadcastId, '6870000000000000001');
    expect(room.reportedViewers, 127);
    expect(room.locked, isFalse);
    expect(room.roomFlag, 1);
    expect(room.title, 'Fixture live');
    expect(() => rows.clear(), throwsUnsupportedError);
  });
  test('directory is finite even when server ignores requested fetchNum; no invented paging marker', () async {
    final paths = <Uri>[];
    final api = BigoApi(
      request: (method, uri, form, cancel) async {
        expect(method, 'GET');
        expect(form, isNull);
        paths.add(uri);
        return _ok(_json('directory'));
      },
    );
    expect(await api.directory(), hasLength(1));
    expect(paths.single.host, 'ta.bigo.tv');
    expect(paths.single.path, '/official_website/OInterfaceWeb/vedioList/72');
    expect(paths.single.queryParameters, {'tabType': '00', 'fetchNum': '10', 'lang': 'en', 'countryCode': 'US'});
  });
  test('missing viewers remain unknown and locked flag is preserved', () {
    final json = _json('directory');
    final row = json['data']['data'][0];
    row['user_count'] = null;
    row['is_locked'] = 1;
    final card = BigoApi.parseDirectory(json).single;
    expect(card.reportedViewers, isNull);
    expect(card.locked, isTrue);
  });
  test('observed null cover retains the room without inventing an image', () {
    final json = _json('directory');
    json['data']['data'][0]['cover_m'] = null;
    final card = BigoApi.parseDirectory(json).single;
    expect(card.siteId, 'fixture_101');
    expect(card.cover, isNull);
    json['data']['data'][0]['cover_m'] = 42;
    expect(() => BigoApi.parseDirectory(json), _failure(BigoFailure.schema));
  });
  for (final broken in [
    'duplicate-site',
    'duplicate-owner',
    'wrong-wrapper',
    'bad-resCode',
    'missing-resCode',
    'fractional-broadcast',
    'negative-viewers',
    'string-lock',
  ]) {
    test('directory rejects $broken without publishing partial rows', () {
      final json = _json('directory');
      final row = json['data']['data'][0] as Map<String, dynamic>;
      switch (broken) {
        case 'duplicate-site':
          json['data']['data'].add({...row, 'owner': 102});
        case 'duplicate-owner':
          json['data']['data'].add({...row, 'bigo_id': 'another'});
        case 'wrong-wrapper':
          json['data'] = [];
        case 'bad-resCode':
          json['data']['resCode'] = '123';
        case 'missing-resCode':
          json['data'].remove('resCode');
        case 'fractional-broadcast':
          row['room_id'] = 1.5;
        case 'negative-viewers':
          row['user_count'] = -1;
        case 'string-lock':
          row['is_locked'] = '0';
      }
      expect(() => BigoApi.parseDirectory(json), throwsA(isA<BigoException>()));
    });
  }
  test('observed login-gated alive zero stays unknown rather than offline', () {
    final status = _studio(_json('studio-login'));
    expect(status.access, BigoAccess.loginRequired);
    expect(status.reportedAlive, isNull);
    expect(status.ownerId, 101);
    expect(status.requestedSiteId, 'fixture_101');
    expect(status.canonicalSiteId, 'fixture_alias');
    expect(status.roomStatus, 0);
    expect(status.roomType, '0');
  });
  test('login priority stays above password/paid and even a conflicting alive flag', () {
    final json = _json('studio-login');
    json['data']['alive'] = 1;
    json['data']['passRoom'] = true;
    json['data']['isPaidShow'] = '1';
    final status = _studio(json);
    expect(status.access, BigoAccess.loginRequired);
    expect(status.reportedAlive, isNull);
  });
  for (final restricted in ['password', 'paid']) {
    test('$restricted gate never exposes alive as offline or playable', () {
      final json = _json('studio-login');
      json['data']['needLogin'] = false;
      if (restricted == 'password') {
        json['data']['passRoom'] = true;
      } else {
        json['data']['isPaidShow'] = '1';
      }
      final status = _studio(json);
      expect(status.access, BigoAccess.restricted);
      expect(status.reportedAlive, isNull);
    });
  }
  test('synthetic ungated status preserves a reported flag, not a media/playability claim', () {
    for (final alive in [0, 1]) {
      final json = _json('studio-login');
      json['data']['needLogin'] = false;
      json['data']['alive'] = alive;
      final status = _studio(json);
      expect(status.access, BigoAccess.public);
      expect(status.reportedAlive, alive == 1);
    }
  });
  test('studio request follows the public form and requires returned owner identity', () async {
    CancelToken? owned;
    final caller = CancelToken();
    final api = BigoApi(
      request: (method, uri, form, cancel) async {
        owned = cancel;
        expect(method, 'POST');
        expect(uri.toString(), '${BigoApi.origin}/studio/getInternalStudioInfo');
        expect(form, {'siteId': 'fixture_101', 'supportHevc': '0'});
        return _ok(_json('studio-login'));
      },
    );
    expect(
      (await api.studioStatus(siteId: 'fixture_101', expectedOwnerId: 101, cancel: caller)).access,
      BigoAccess.loginRequired,
    );
    expect(owned!.isCancelled, isTrue);
    expect(caller.isCancelled, isFalse);
    final mismatch = _json('studio-login');
    mismatch['data']['uid'] = 102;
    expect(() => _studio(mismatch), _failure(BigoFailure.identity));
  });
  for (final field in ['needLogin', 'passRoom', 'isPaidShow', 'alive', 'clientBigoId', 'roomStatus', 'roomType']) {
    test('studio requires explicit $field instead of treating missing as false/offline', () {
      final json = _json('studio-login');
      json['data'].remove(field);
      expect(() => _studio(json), throwsA(isA<BigoException>()));
    });
  }
  test('nonzero business code is an API failure, never an offline result', () {
    for (final code in [404, 700001, 810021, 810022]) {
      final json = _json('studio-login')..['code'] = code;
      expect(() => _studio(json), _failure(BigoFailure.api));
    }
  });
  for (final (status, kind) in [
    (400, BigoFailure.transport),
    (401, BigoFailure.access),
    (403, BigoFailure.access),
    (404, BigoFailure.missing),
    (429, BigoFailure.rateLimited),
    (503, BigoFailure.service),
  ]) {
    test('HTTP $status stays $kind and does not parse a misleading body', () async {
      final api = BigoApi(request: (_, _, _, _) async => (status: status, body: jsonEncode(_json('studio-login'))));
      await expectLater(api.studioStatus(siteId: 'fixture_101', expectedOwnerId: 101), _failure(kind));
    });
  }
  test('invalid public IDs and owner IDs stop before network access', () async {
    var requests = 0;
    final api = BigoApi(
      request: (_, _, _, _) async {
        requests++;
        return _ok({});
      },
    );
    for (final id in ['', '../file', 'a/b', 'a?b', 'a%2Fb', 'a\r\nX:y', 'a' * 65]) {
      await expectLater(api.studioStatus(siteId: id, expectedOwnerId: 101), _failure(BigoFailure.identity));
    }
    await expectLater(api.studioStatus(siteId: 'fixture', expectedOwnerId: 0), _failure(BigoFailure.identity));
    expect(requests, 0);
  });
  test('pre-cancelled request makes no network call', () async {
    final api = BigoApi(request: (_, _, _, _) async => throw StateError('must not run'));
    await expectLater(api.directory(cancel: CancelToken()..cancel()), _failure(BigoFailure.cancelled));
  });
  test('pending cancellation owns transport and consumes late errors', () async {
    final pending = Completer<({int status, String body})>();
    final ready = Completer<void>();
    CancelToken? owned;
    final api = BigoApi(
      request: (_, _, _, token) {
        owned = token;
        ready.complete();
        return pending.future;
      },
    );
    final caller = CancelToken();
    final result = api.directory(cancel: caller);
    final checked = expectLater(result, _failure(BigoFailure.cancelled));
    await ready.future;
    caller.cancel();
    await checked;
    expect(owned!.isCancelled, isTrue);
    pending.completeError(const SocketException('late fixture error'));
    await Future<void>.delayed(Duration.zero);
  });
  test('total deadline cancels owned transport, leaving caller and sibling intact', () async {
    final pending = Completer<({int status, String body})>();
    CancelToken? owned;
    final caller = CancelToken();
    final api = BigoApi(
      deadline: const Duration(milliseconds: 20),
      request: (_, _, _, token) {
        owned = token;
        return pending.future;
      },
    );
    await expectLater(api.directory(cancel: caller), _failure(BigoFailure.transport));
    expect(owned!.isCancelled, isTrue);
    expect(caller.isCancelled, isFalse);
    pending.complete(_ok(_json('directory')));
    await Future<void>.delayed(Duration.zero);
  });
  test('strict UTF8, byte budget and malformed JSON avoid body disclosure', () async {
    await expectLater(BigoApi.readBody(Stream.value([0xc3, 0x28])), _failure(BigoFailure.schema));
    await expectLater(
      BigoApi.readBody(Stream.value(List.filled(BigoApi.responseLimit + 1, 1))),
      _failure(BigoFailure.schema),
    );
    for (final body in [
      'private invalid body',
      '[]',
      '{"code":0,"data":null}',
      '一' * (BigoApi.responseLimit ~/ 3 + 1),
    ]) {
      final api = BigoApi(request: (_, _, _, _) async => (status: 200, body: body));
      await expectLater(api.directory(), _failure(BigoFailure.schema));
    }
    expect(const BigoException(BigoFailure.schema).toString(), 'Bigo schema');
  });
  test('body deadline spans chunks and cancels subscription', () async {
    var cancelled = false;
    final controller = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    controller.add([123]);
    await expectLater(
      BigoApi.readBody(controller.stream, timeout: const Duration(milliseconds: 20)),
      throwsA(isA<TimeoutException>()),
    );
    expect(cancelled, isTrue);
    await controller.close();
  });
}
