import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/kilakila/kilakila_api.dart';

const uid = '100';
const first = '9007199254740993123';
const second = '9007199254740993456';
Map<String, dynamic> user() => {'nickname': 'Fixture anchor', 'headPortraitUrl': 'https://img.example/avatar.png'};
Map<String, dynamic> card([String room = first]) => {
  'roomIdStr': room,
  'uid': 100,
  'status': 4,
  'goldPrice': 0,
  'title': 'Fixture live',
  'roomSourceType': 0,
  'recommendSource': 0,
  'flvPlayUrl': 'https://pull.live.hongrenshuo.com.cn/hrs/$room.flv?auth_key=fixture',
  'pushFlow': 'rtmp://push.example/DO_NOT_USE',
};
Map<String, dynamic> profile([Object? current]) => {
  'code': 200,
  'data': <String, dynamic>{'userResp': user(), 'liveCard': current ?? card()},
};
({int status, String body}) ok(Object value) => (status: 200, body: jsonEncode(value));
Map<String, dynamic> detail(String room, {int owner = 100}) => {
  'h': {'code': 200, 'success': true},
  'b': {
    ...card(room),
    'uid': owner,
    'userInfo': {...user(), 'id': owner},
  },
};
Matcher failure(KilakilaFailure kind) => throwsA(isA<KilakilaException>().having((e) => e.kind, 'kind', kind));

void main() {
  test('public owner URL is distinct from a single broadcast link', () {
    expect(KilakilaApi.numericOwnerFromUri(Uri.parse('${KilakilaApi.ownerOrigin}/index/roomuser/uid/$uid')), uid);
    expect(KilakilaApi.numericRoomFromUri(Uri.parse('${KilakilaApi.ownerOrigin}/index/roomuser/uid/$uid')), isNull);
    for (final url in [
      '${KilakilaApi.origin}/room/$first',
      '${KilakilaApi.ownerOrigin}.evil.test/index/roomuser/uid/$uid',
      '${KilakilaApi.ownerOrigin}/index/roomuser/uid/$uid?uid=200',
      '${KilakilaApi.ownerOrigin}/index/roomuser/uid/$uid#fragment',
      '${KilakilaApi.ownerOrigin}/index/roomuser/uid/0',
      '${KilakilaApi.ownerOrigin}/index/roomuser/uid/%FF',
      '${KilakilaApi.ownerOrigin}/index/roomuser/uid/$uid/',
      'https://user@live.hongrenshuo.com.cn/index/roomuser/uid/$uid',
      'https://live.hongrenshuo.com.cn:8787/index/roomuser/uid/$uid',
    ]) {
      expect(KilakilaApi.numericOwnerFromUri(Uri.parse(url)), isNull, reason: url);
    }
  });

  test('owner query uses observed host and UID; metadata discards media', () async {
    final api = KilakilaApi(
      request: (uri, cancel) async {
        expect(uri.toString(), '${KilakilaApi.ownerOrigin}/Tg/personalH5?uid=$uid');
        return ok(profile());
      },
    );
    final result = await api.owner(uid);
    expect(result.userId, uid);
    expect(result.currentRoom!.roomId, first);
    expect(result.currentRoom!.userId, uid);
    expect(result.currentRoom!.media, isEmpty);
  });

  test('each refresh follows the same anchor to its new broadcast', () async {
    var current = first;
    final paths = <String>[];
    final api = KilakilaApi(
      request: (uri, cancel) async {
        paths.add(uri.path);
        return uri.path == '/Tg/personalH5' ? ok(profile(card(current))) : ok(detail(uri.queryParameters['roomId']!));
      },
    );
    final old = await api.detailForOwner(uid);
    current = second;
    final fresh = await api.detailForOwner(uid);
    expect(old!.roomId, first);
    expect(fresh!.roomId, second);
    expect(fresh.media['flv'], contains('/$second.flv'));
    expect(paths, ['/Tg/personalH5', '/LiveRoom/getRoomInfo', '/Tg/personalH5', '/LiveRoom/getRoomInfo']);
  });

  for (final empty in <Map<String, dynamic>>[
    {},
    {'roomSourceType': 0, 'recommendSource': 0},
  ]) {
    test('explicit empty broadcast does not fetch a stale room: $empty', () async {
      var requests = 0;
      final api = KilakilaApi(
        request: (uri, cancel) async {
          expect(uri.path, '/Tg/personalH5');
          requests++;
          return ok(profile(empty));
        },
      );
      expect(await api.detailForOwner(uid), isNull);
      expect(requests, 1);
    });
  }

  for (final broken in <Object?>[
    null,
    [],
    {'title': 'partial'},
    {'status': 4},
    {'roomSourceType': null},
    {'unexpected': 0},
  ]) {
    test('missing or malformed live card is not an offline success: $broken', () async {
      final data = profile();
      (data['data'] as Map)['liveCard'] = broken;
      final api = KilakilaApi(request: (_, _) async => ok(data));
      await expectLater(api.owner(uid), failure(KilakilaFailure.schema));
    });
  }

  test('owner mismatch in current card stops before room resolution', () async {
    final api = KilakilaApi(request: (_, _) async => ok(profile(card()..['uid'] = 200)));
    await expectLater(api.detailForOwner(uid), failure(KilakilaFailure.schema));
  });
  for (final invalidUser in <Object?>[
    null,
    {},
    {'nickname': ''},
    {...user(), 'id': 200},
  ]) {
    test('invalid profile identity is not accepted: $invalidUser', () async {
      final data = profile();
      (data['data'] as Map)['userResp'] = invalidUser;
      final api = KilakilaApi(request: (_, _) async => ok(data));
      await expectLater(api.owner(uid), failure(KilakilaFailure.schema));
    });
  }
  test('missing liveCard differs from an explicit empty object', () async {
    final data = profile();
    (data['data'] as Map).remove('liveCard');
    final api = KilakilaApi(request: (_, _) async => ok(data));
    await expectLater(api.owner(uid), failure(KilakilaFailure.schema));
  });
  test('owner mismatch in room detail is rejected even after valid lookup', () async {
    final api = KilakilaApi(
      request: (uri, _) async => uri.path == '/Tg/personalH5' ? ok(profile()) : ok(detail(first, owner: 200)),
    );
    await expectLater(api.detailForOwner(uid), failure(KilakilaFailure.schema));
  });
  test('broadcast replacement mid-flight is not accepted as requested detail', () async {
    final api = KilakilaApi(
      request: (uri, _) async => uri.path == '/Tg/personalH5' ? ok(profile()) : ok(detail(second)),
    );
    await expectLater(api.detailForOwner(uid), failure(KilakilaFailure.schema));
  });
  test('unknown state remains unknown rather than quietly offline', () async {
    final api = KilakilaApi(
      request: (uri, _) async =>
          uri.path == '/Tg/personalH5' ? ok(profile(card()..['status'] = 99)) : ok(detail(first)..['b']['status'] = 99),
    );
    expect((await api.owner(uid)).currentRoom!.statusCode, 99);
    await expectLater(api.detailForOwner(uid), failure(KilakilaFailure.stateUnsupported));
  });
  test('paid room does not become anonymously recordable', () async {
    final data = detail(first);
    (data['b'] as Map)['goldPrice'] = 1;
    final api = KilakilaApi(request: (uri, _) async => uri.path == '/Tg/personalH5' ? ok(profile()) : ok(data));
    await expectLater(api.detailForOwner(uid), failure(KilakilaFailure.restricted));
  });
  test('metadata-only owner resolution does not return playback URLs', () async {
    final api = KilakilaApi(
      request: (uri, _) async => uri.path == '/Tg/personalH5' ? ok(profile()) : ok(detail(first)),
    );
    expect((await api.detailForOwner(uid, playback: false))!.media, isEmpty);
  });
  test('cancelled profile completion never starts a detail request', () async {
    final pending = Completer<({int status, String body})>();
    final cancel = CancelToken();
    var requests = 0;
    final api = KilakilaApi(
      request: (_, token) {
        expect(token, same(cancel));
        requests++;
        return pending.future;
      },
    );
    final result = api.detailForOwner(uid, cancel: cancel);
    cancel.cancel();
    pending.complete(ok(profile()));
    await expectLater(result, failure(KilakilaFailure.cancelled));
    expect(requests, 1);
  });
  test('invalid owner ID performs no request', () async {
    final api = KilakilaApi(
      request: (_, _) async {
        fail('Unexpected request');
      },
    );
    await expectLater(api.owner('../100'), failure(KilakilaFailure.schema));
  });
  for (final status in [403, 404, 429, 503]) {
    test('owner HTTP $status remains a failure', () async {
      final api = KilakilaApi(request: (_, _) async => (status: status, body: '{}'));
      await expectLater(api.owner(uid), throwsA(isA<KilakilaException>()));
    });
  }
  test('business failure does not become an empty live card', () async {
    final api = KilakilaApi(request: (_, _) async => ok({'code': 500, 'data': {}}));
    await expectLater(api.owner(uid), failure(KilakilaFailure.service));
  });
}
