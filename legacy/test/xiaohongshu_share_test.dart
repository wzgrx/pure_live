import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/xiaohongshu/xiaohongshu_api.dart';
import 'package:pure_live/core/site/xiaohongshu/xiaohongshu_share.dart';

const liveId = '570429070963278308';
const endedId = '570305058583373361';
Map<String, dynamic> fixture([String name = 'live']) =>
    jsonDecode(File('test/fixtures/xiaohongshu/$name.json').readAsStringSync()) as Map<String, dynamic>;
Map<String, dynamic> room(Map<String, dynamic> state) => (state['roomData'] as Map)['roomInfo'] as Map<String, dynamic>;
String page(Map<String, dynamic> state) =>
    '<html><script>window.__INITIAL_STATE__=${jsonEncode({'liveStream': state})}</script></html>';
Matcher failure(XiaohongshuFailure kind) => throwsA(isA<XiaohongshuException>().having((e) => e.kind, 'kind', kind));
void editStream(Map<String, dynamic> state, void Function(Map<String, dynamic>) edit) {
  final config = jsonDecode(room(state)['pullConfig'] as String) as Map<String, dynamic>;
  edit(config);
  room(state)['pullConfig'] = jsonEncode(config);
}

void main() {
  test('real live share binds exact int64 string and four declared sources', () {
    final result = XiaohongshuShare.parsePage(page(fixture()), roomId: liveId);
    expect(result.responseRoomId, liveId);
    expect(result.reportedLive, true);
    expect(result.access, XiaohongshuAccess.public);
    expect(result.displayViewers, '200万+');
    expect(result.streams.length, 4);
    expect(result.streams.map((s) => s.protocol), ['hls', 'flv', 'flv', 'flv']);
    expect(result.streams.map((s) => s.quality).toSet(), {'HD'});
    expect(result.streams.first.uri.scheme, 'http');
    expect(() => result.streams.clear(), throwsUnsupportedError);
  });
  test('ended page never borrows recommendation media or requires omitted id', () {
    final result = XiaohongshuShare.parsePage(page(fixture('ended')), roomId: endedId);
    expect(result.responseRoomId, null);
    expect(result.requestedRoomId, endedId);
    expect(result.reportedLive, false);
    expect(result.streams, isEmpty);
  });
  test('real SSR optional global undefined tokens do not block live JSON', () {
    final state = fixture();
    room(state)['roomTitle'] = r'undefined \ "undefined"';
    final input =
        '<script>window.__INITIAL_STATE__={"global":{"jsAssetsList":undefined,"tiers":[undefined]},"liveStream":${jsonEncode(state)}};</script>';
    final result = XiaohongshuShare.parsePage(input, roomId: liveId);
    expect(result.title, r'undefined \ "undefined"');
    expect(result.streams.length, 4);
  });
  for (final source in ['undefinedCall()', 'undefinedSuffix', '(undefined)', '(()=>undefined)()', 'NaN', 'Infinity']) {
    test('hydration scanner still rejects executable/non-JSON expression $source', () {
      final input =
          '<script>window.__INITIAL_STATE__={"global":$source,"liveStream":${jsonEncode(fixture())}}</script>';
      expect(() => XiaohongshuShare.parsePage(input, roomId: liveId), failure(XiaohongshuFailure.schema));
    });
  }
  for (final id in ['', '0', '../123', ' 123', '123?', '123/4', '123\n', '123456789012345678901']) {
    test('rejects invalid room identity ${jsonEncode(id)}', () {
      expect(() => XiaohongshuShare.parseState(fixture(), roomId: id), failure(XiaohongshuFailure.identity));
    });
  }
  for (final id in [null, 570429070963278308, '570429070963278309']) {
    test('live response identity must match exact string: $id', () {
      final state = fixture();
      room(state)['roomId'] = id;
      expect(() => XiaohongshuShare.parseState(state, roomId: liveId), failure(XiaohongshuFailure.identity));
    });
  }
  test('mismatched ended identity is not accepted', () {
    final state = fixture('ended');
    room(state)['roomId'] = liveId;
    expect(() => XiaohongshuShare.parseState(state, roomId: endedId), failure(XiaohongshuFailure.identity));
  });
  for (final mutation in <String, void Function(Map<String, dynamic>)>{
    'paid': (r) => r['monetizeType'] = 1,
    'family': (r) => r['joinLimitTypes'] = [2],
    'group': (r) => r['joinLimitTypes'] = [1],
    'regional': (r) => r['joinLimitTypes'] = [4],
    'future restriction': (r) => r['joinLimitTypes'] = [32],
    'missing monetization': (r) => r.remove('monetizeType'),
    'missing limits': (r) => r.remove('joinLimitTypes'),
  }.entries) {
    test('${mutation.key} exposes no preview or recommendation streams', () {
      final state = fixture();
      mutation.value(room(state));
      room(state)['pullConfig'] = 'broken preview';
      final result = XiaohongshuShare.parseState(state, roomId: liveId);
      expect(result.access, isNot(XiaohongshuAccess.public));
      expect(result.streams, isEmpty);
    });
  }
  test('unknown future live state stays unknown despite frontend success default', () {
    final state = fixture();
    room(state)['status'] = 9;
    final result = XiaohongshuShare.parseState(state, roomId: liveId);
    expect(result.reportedLive, null);
    expect(result.streams, isEmpty);
  });
  test('live declaration without media remains metadata, not offline', () {
    final state = fixture();
    room(state).remove('pullConfig');
    final result = XiaohongshuShare.parseState(state, roomId: liveId);
    expect(result.reportedLive, true);
    expect(result.streams, isEmpty);
  });
  for (final mutation in <String, void Function(Map<String, dynamic>)>{
    'missing page': (s) => s.remove('pageStatus'),
    'non-object data': (s) => s['roomData'] = [],
    'string status': (s) => room(s)['status'] = '2',
    'live/end conflict': (s) => s['liveStatus'] = 'end',
    'malformed limits': (s) => room(s)['joinLimitTypes'] = '0',
    'string limit': (s) => room(s)['joinLimitTypes'] = ['0'],
    'bad monetization': (s) => room(s)['monetizeType'] = false,
    'bad config': (s) => room(s)['pullConfig'] = '{',
    'huge config': (s) => room(s)['pullConfig'] = ' ' * 65537,
  }.entries) {
    test('schema failure: ${mutation.key}', () {
      final state = fixture();
      mutation.value(state);
      expect(() => XiaohongshuShare.parseState(state, roomId: liveId), failure(XiaohongshuFailure.schema));
    });
  }
  test('error page is not offline', () {
    final state = fixture();
    state['pageStatus'] = 'error';
    expect(() => XiaohongshuShare.parseState(state, roomId: liveId), failure(XiaohongshuFailure.api));
  });
  for (final url in [
    'http://xhscdn.com.evil.test/live/$liveId.flv',
    'http://127.0.0.1/live/$liveId.flv',
    'http://live.xhscdn.com/live/$endedId.flv',
    'http://u:p@live.xhscdn.com/live/$liveId.flv',
    'http://live.xhscdn.com:8080/live/$liveId.flv',
    'http://live.xhscdn.com/live/$liveId.flv#x',
    'file:///live/$liveId.flv',
  ]) {
    test('rejects source URL outside declared room contract: $url', () {
      final state = fixture();
      editStream(state, (c) => c['h264'][0]['master_url'] = url);
      expect(() => XiaohongshuShare.parseState(state, roomId: liveId), failure(XiaohongshuFailure.schema));
    });
  }
  test('retains full signed query and codec, deduplicates exact source aliases', () {
    final state = fixture();
    editStream(state, (c) {
      c['h264'][0]['master_url'] += '?a=1&a=2&sig=A%2FB';
      c['h264'].add(c['h264'][0]);
      c['h265'] = [c['h264'][0]];
    });
    final result = XiaohongshuShare.parseState(state, roomId: liveId);
    expect(result.streams.length, 5);
    expect(result.streams.first.uri.query, 'a=1&a=2&sig=A%2FB');
    expect(result.streams.last.codec, 'h265');
  });
  test('source array bound enforced', () {
    final state = fixture();
    editStream(state, (c) => c['h264'] = List.filled(33, c['h264'][0]));
    expect(() => XiaohongshuShare.parseState(state, roomId: liveId), failure(XiaohongshuFailure.schema));
  });
  for (final input in [
    '直播已结束',
    '<script>window.__INITIAL_STATE__=alert(1)</script>',
    '<script>window.__INITIAL_STATE__={"liveStream":undefined}</script>',
    '${page(fixture())}${page(fixture())}',
    'a' * (XiaohongshuShare.responseLimit + 1),
  ]) {
    test('rejects absent/ambiguous/executable/oversize state (${input.length})', () {
      expect(() => XiaohongshuShare.parsePage(input, roomId: liveId), failure(XiaohongshuFailure.schema));
    });
  }
  test('JSON string containing end-of-live words does not change status', () {
    final state = fixture();
    room(state)['roomTitle'] = '直播已结束';
    expect(XiaohongshuShare.parsePage(page(state), roomId: liveId).reportedLive, true);
  });
  test('room GET uses bound public page and completes its own token only', () async {
    final caller = CancelToken();
    CancelToken? scoped;
    final api = XiaohongshuApi(
      request: (uri, token) async {
        scoped = token;
        expect(uri.toString(), '${XiaohongshuApi.origin}/livestream/$liveId');
        return (status: 200, body: page(fixture()));
      },
    );
    expect((await api.room(liveId, cancel: caller)).streams.length, 4);
    expect(scoped!.isCancelled, true);
    expect(caller.isCancelled, false);
  });
  for (final row in <int, XiaohongshuFailure>{
    302: XiaohongshuFailure.transport,
    401: XiaohongshuFailure.access,
    406: XiaohongshuFailure.access,
    404: XiaohongshuFailure.missing,
    429: XiaohongshuFailure.rateLimited,
    503: XiaohongshuFailure.service,
  }.entries) {
    test('HTTP ${row.key} maps separately from offline', () async {
      final api = XiaohongshuApi(request: (_, _) async => (status: row.key, body: ''));
      await expectLater(api.room(liveId), failure(row.value));
    });
  }
  test('pre-cancel dispatches no request', () async {
    var calls = 0;
    final api = XiaohongshuApi(
      request: (_, _) async {
        calls++;
        return (status: 200, body: '');
      },
    );
    await expectLater(api.room(liveId, cancel: CancelToken()..cancel()), failure(XiaohongshuFailure.cancelled));
    expect(calls, 0);
  });
  test('deadline cancels request token but preserves caller', () async {
    final caller = CancelToken();
    CancelToken? scoped;
    final pending = Completer<({int status, String body})>();
    final api = XiaohongshuApi(
      deadline: const Duration(milliseconds: 20),
      request: (_, t) {
        scoped = t;
        return pending.future;
      },
    );
    await expectLater(api.room(liveId, cancel: caller), failure(XiaohongshuFailure.transport));
    expect(scoped!.isCancelled, true);
    expect(caller.isCancelled, false);
    pending.complete((status: 200, body: page(fixture())));
    await Future<void>.delayed(Duration.zero);
  });
}
