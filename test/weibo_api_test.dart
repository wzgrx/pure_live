import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/weibo/weibo_api.dart';

const id = '1022:2321325000000000000000';
Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/weibo/$name.json').readAsStringSync()) as Map<String, dynamic>;
Matcher failure(WeiboFailure kind) => throwsA(isA<WeiboException>().having((e) => e.kind, 'kind', kind));
WeiboLiveDetail detail(Map<String, dynamic> json) =>
    WeiboApi.parseDetail(json, expectedLiveId: id, expectedOwnerId: 101);
({int status, String body}) ok(Object json) => (status: 200, body: jsonEncode(json));
void main() {
  test('captured directory keeps broadcast identity and UID distinct and immutable', () {
    final rows = WeiboApi.parseDirectory(fixture('recommend'));
    expect(rows.map((e) => e.ownerId), [101, 102]);
    expect(rows.first.liveId, id);
    expect(rows.first.nickname, '样本 0');
    expect(() => rows.clear(), throwsUnsupportedError);
  });
  test('captured live detail preserves actual FLV despite HLS field name and deduplicates', () {
    final room = detail(fixture('live-detail'));
    expect(room.state, WeiboBroadcastState.live);
    expect(room.access, WeiboAccess.public);
    expect(room.mediaUrls, ['https://media.example.test/stream_wb720avc.flv?token=fixture']);
    expect(room.width, 1280);
    expect(room.height, 720);
    expect(room.ownerId, 101);
    expect(() => room.mediaUrls.clear(), throwsUnsupportedError);
  });
  test('observed missing-user API error is not offline and does not leak message', () {
    final json = fixture('detail');
    expect(() => detail(json), failure(WeiboFailure.api));
    expect(const WeiboException(WeiboFailure.api).toString(), 'Weibo api');
  });
  for (final mode in ['replay', 'unknown', 'disabled', 'restricted', 'trial', 'paid-restricted', 'app-only']) {
    test('$mode does not export live or replay URLs', () {
      final json = fixture('live-detail');
      final row = json['data'];
      switch (mode) {
        case 'replay':
          row['status'] = 3;
          row['replay_origin_url'] = 'https://media.example.test/replay.m3u8';
        case 'unknown':
          row['status'] = 99;
        case 'disabled':
          row['play_switch'] = 0;
        case 'restricted':
          row['watch_limit'] = 1;
          row['pay_live_status'] = 0;
        case 'trial':
          row['watch_limit'] = 1;
          row['pay_live_status'] = 0;
          row['free_watch_seconds'] = 60;
        case 'paid-restricted':
          row['watch_limit'] = 1;
          row['pay_live_status'] = 1;
        case 'app-only':
          row['watch_limit'] = 8;
      }
      final room = detail(json);
      expect(room.mediaUrls, isEmpty);
      expect(room.state, mode == 'replay' ? WeiboBroadcastState.replay : WeiboBroadcastState.unknown);
    });
  }
  for (final bad in [
    'wrong-id',
    'wrong-owner',
    'missing-status',
    'string-status',
    'missing-limit',
    'invalid-pay',
    'missing-switch',
    'bad-width',
    'bad-title',
    'url-userinfo',
    'url-newline',
    'url-scheme',
    'bad-envelope',
    'missing-error',
    'wrong-success',
  ]) {
    test('rejects $bad without a partial live result', () {
      final json = fixture('live-detail');
      final row = json['data'];
      switch (bad) {
        case 'wrong-id':
          row['liveId'] = '1022:2321325000000000000001';
          row['watch_limit'] = 8;
        case 'wrong-owner':
          row['user']['uid'] = 999;
          row['watch_limit'] = 8;
        case 'missing-status':
          row.remove('status');
        case 'string-status':
          row['status'] = '1';
        case 'missing-limit':
          row.remove('watch_limit');
        case 'invalid-pay':
          row['pay_live_status'] = 2;
        case 'missing-switch':
          row.remove('play_switch');
        case 'bad-width':
          row['width'] = -1;
        case 'bad-title':
          row['title'] = null;
        case 'url-userinfo':
          row['live_origin_flv_url'] = 'https://user:secret@media.example.test/a.flv';
        case 'url-newline':
          row['live_origin_flv_url'] = 'https://media.example.test/\na.flv';
        case 'url-scheme':
          row['live_origin_flv_url'] = 'file:///private/a.flv';
        case 'bad-envelope':
          json['data'] = [];
        case 'missing-error':
          json.remove('error_code');
        case 'wrong-success':
          json['code'] = 0;
      }
      expect(() => detail(json), throwsA(isA<WeiboException>()));
    });
  }
  for (final bad in [
    '101',
    '1022:2321325000000000000000/x',
    '1022:2321325000000000000000?x=1',
    '1022:2321325000000000000000\n',
    '1042152:wrong',
    'https://weibo.com/u/101',
  ]) {
    test('invalid identifier rejected before transport: ${jsonEncode(bad)}', () {
      var calls = 0;
      final api = WeiboApi(
        request: (m, u, f, c) async {
          calls++;
          return ok(fixture('live-detail'));
        },
      );
      expect(() => api.detail(bad), failure(WeiboFailure.identity));
      expect(calls, 0);
    });
  }
  test('official hexadecimal identifier preserved exactly', () {
    const hex = '1042152:8e4d2f2900a81be5a8ece15da4dd443a';
    expect(WeiboApi.validateLiveId(hex), hex);
  });
  test('nullable cover retained but duplicate broadcast rejected', () {
    final json = fixture('recommend');
    final rows = json['data']['data'];
    rows[0]['cover'] = null;
    expect(WeiboApi.parseDirectory(json).first.cover, isNull);
    rows.add(rows[0]);
    expect(() => WeiboApi.parseDirectory(json), failure(WeiboFailure.identity));
  });
  test('two returned formats retained without suffix rewriting or fabricated qualities', () {
    final json = fixture('live-detail');
    json['data']['live_origin_hls_url'] = 'https://media.example.test/playlist.m3u8?token=x';
    expect(detail(json).mediaUrls, hasLength(2));
  });
  test('empty live media remains declared live but not playable', () {
    final json = fixture('live-detail');
    json['data']['live_origin_hls_url'] = '';
    json['data']['live_origin_flv_url'] = '';
    expect(detail(json).state, WeiboBroadcastState.live);
    expect(detail(json).mediaUrls, isEmpty);
  });
  test('production request contract and private cancellation token cleanup', () async {
    final calls = <Uri>[];
    final tokens = <CancelToken>[];
    final caller = CancelToken();
    final api = WeiboApi(
      request: (method, uri, form, token) async {
        expect(method, 'GET');
        expect(form, isNull);
        calls.add(uri);
        tokens.add(token);
        return ok(fixture(uri.path.contains('pc_recommend') ? 'recommend' : 'live-detail'));
      },
    );
    await api.directory(cancel: caller);
    await api.detail(id, expectedOwnerId: 101, cancel: caller);
    expect(calls.first.queryParameters, {'count': '10', 'uid': ''});
    expect(calls.last.queryParameters, {'live_id': id});
    expect(calls.map((u) => u.host), ['weibo.com', 'weibo.com']);
    expect(tokens.every((t) => t.isCancelled), isTrue);
    expect(caller.isCancelled, isFalse);
    expect(identical(tokens[0], tokens[1]), isFalse);
  });
  for (final pair in [
    (401, WeiboFailure.access),
    (403, WeiboFailure.access),
    (404, WeiboFailure.missing),
    (429, WeiboFailure.rateLimited),
    (503, WeiboFailure.service),
    (302, WeiboFailure.transport),
  ]) {
    test('HTTP ${pair.$1} remains distinct from broadcast state', () async {
      final api = WeiboApi(request: (m, u, f, c) async => (status: pair.$1, body: 'private raw body'));
      await expectLater(api.directory(), failure(pair.$2));
    });
  }
  test('pre-cancelled request does not dispatch', () async {
    final c = CancelToken()..cancel();
    var calls = 0;
    final api = WeiboApi(
      request: (m, u, f, c) async {
        calls++;
        return ok(fixture('recommend'));
      },
    );
    await expectLater(api.directory(cancel: c), failure(WeiboFailure.cancelled));
    expect(calls, 0);
  });
  test('in-flight cancellation cancels owned transport and consumes late error', () async {
    final c = CancelToken();
    final entered = Completer<void>();
    final pending = Completer<({int status, String body})>();
    late CancelToken owned;
    final api = WeiboApi(
      request: (m, u, f, t) {
        owned = t;
        entered.complete();
        return pending.future;
      },
    );
    final result = api.directory(cancel: c);
    final assertion = expectLater(result, failure(WeiboFailure.cancelled));
    await entered.future;
    c.cancel();
    await assertion;
    expect(owned.isCancelled, isTrue);
    pending.completeError(StateError('late private error'));
    await Future<void>.delayed(Duration.zero);
  });
  test('total timeout cancels transport but not caller', () async {
    final c = CancelToken();
    late CancelToken owned;
    final pending = Completer<({int status, String body})>();
    final api = WeiboApi(
      deadline: const Duration(milliseconds: 10),
      request: (m, u, f, t) {
        owned = t;
        return pending.future;
      },
    );
    await expectLater(api.directory(cancel: c), failure(WeiboFailure.transport));
    expect(owned.isCancelled, isTrue);
    expect(c.isCancelled, isFalse);
    pending.complete(ok(fixture('recommend')));
    await Future<void>.delayed(Duration.zero);
  });
  test('stream reader is strict UTF8, bounded and cancels subscription', () async {
    var cancelled = false;
    final stream = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    final result = WeiboApi.readBody(stream.stream);
    final assertion = expectLater(result, failure(WeiboFailure.schema));
    stream.add(List.filled(WeiboApi.responseLimit + 1, 1));
    await assertion;
    expect(cancelled, isTrue);
    await stream.close();
    await expectLater(WeiboApi.readBody(Stream.value([255])), failure(WeiboFailure.schema));
  });
  test('stream timeout closes subscription', () async {
    var cancelled = false;
    final stream = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    await expectLater(
      WeiboApi.readBody(stream.stream, timeout: const Duration(milliseconds: 10)),
      throwsA(isA<TimeoutException>()),
    );
    expect(cancelled, isTrue);
    await stream.close();
  });
  test('oversized or malformed injected response rejected', () async {
    for (final text in ['x' * (WeiboApi.responseLimit + 1), '<html>failure</html>']) {
      final api = WeiboApi(request: (m, u, f, c) async => (status: 200, body: text));
      await expectLater(api.directory(), failure(WeiboFailure.schema));
    }
  });
}
