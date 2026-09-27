import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/niconico/niconico_api.dart';
import 'package:pure_live/core/site/niconico/niconico_watch.dart';

Map<String, dynamic> fixture([String name = 'live']) =>
    jsonDecode(File('test/fixtures/niconico/$name.json').readAsStringSync()) as Map<String, dynamic>;
String page(Map<String, dynamic> data) =>
    '<script id="embedded-data" data-props="${const HtmlEscape().convert(jsonEncode(data))}"></script>';
Matcher failure(NiconicoFailure kind) => throwsA(isA<NiconicoException>().having((e) => e.kind, 'kind', kind));

void main() {
  test('observed official-program websocket path is retained without inventing unama prefix', () {
    final data = fixture();
    data['site']['relive']['webSocketUrl'] =
        'wss://a.live2.nicovideo.jp/wsapi/v2/watch/124619065117?audience_token=fixture';
    final result = NiconicoWatch.parsePage(page(data), programId: 'lv100');
    expect(result.webSocketUri!.path, '/wsapi/v2/watch/124619065117');
    expect(result.webSocketUri!.queryParameters, {'audience_token': 'fixture', 'frontend_id': '9'});
  });
  test('HTML attribute decoding preserves identity and bootstrap, not a media URL', () {
    final data = fixture();
    data['program']['title'] = '配信 "quoted" & <tag>';
    final result = NiconicoWatch.parsePage(page(data), programId: 'lv100');
    expect(result.programId, 'lv100');
    expect(result.title, data['program']['title']);
    expect(result.broadcaster, 'Fixture broadcaster');
    expect(result.status, NiconicoStatus.onAir);
    expect(result.access, NiconicoAccess.allowed);
    expect(result.webSocketUri?.scheme, 'wss');
    expect(result.webSocketUri?.queryParameters, {'audience_token': 'fixture', 'frontend_id': '9'});
    expect(result.toString(), isNot(contains('audience_token')));
  });
  for (final spec in [
    ('region', NiconicoStatus.onAir, NiconicoAccess.regionRestricted),
    ('scheduled', NiconicoStatus.scheduled, NiconicoAccess.regionRestricted),
    ('ended', NiconicoStatus.ended, NiconicoAccess.denied),
  ]) {
    test('${spec.$1} preserves broadcast status separately from access', () {
      final result = NiconicoWatch.parsePage(page(fixture(spec.$1)), programId: 'lv100');
      expect(result.status, spec.$2);
      expect(result.access, spec.$3);
      expect(result.webSocketUri, isNull);
    });
  }
  test('login requirement wins over canWatch and discards any offered socket', () {
    final data = fixture();
    data['programWatch']['condition']['needLogin'] = true;
    data['site']['relive']['webSocketUrl'] = 'wss://elsewhere.invalid/token';
    final result = NiconicoWatch.parseData(data, programId: 'lv100');
    expect(result.access, NiconicoAccess.loginRequired);
    expect(result.webSocketUri, isNull);
  });
  test('returned identity is checked before access gates', () {
    expect(() => NiconicoWatch.parseData(fixture('region'), programId: 'lv101'), failure(NiconicoFailure.identity));
  });
  for (final input in [
    'lv100',
    'https://live.nicovideo.jp/watch/lv100?ref=top',
    ' https://live.nicovideo.jp/watch/lv100 ',
  ]) {
    test('accept observed input $input', () => expect(NiconicoWatch.parseInput(input), 'lv100'));
  }
  for (final input in [
    'lv0',
    'lv100/other',
    '100',
    'https://live.nicovideo.jp.evil.test/watch/lv100',
    'https://evil@live.nicovideo.jp/watch/lv100',
    'https://live.nicovideo.jp:443/watch/lv100',
    'https://live.nicovideo.jp/watch/other/../lv100',
    'https://live.nicovideo.jp/watch/%6cv100',
    'https://live.nicovideo.jp/watch/lv100/..',
    'https://live.nicovideo.jp/user/100',
  ]) {
    test(
      'reject unsupported input $input',
      () => expect(() => NiconicoWatch.parseInput(input), failure(NiconicoFailure.identity)),
    );
  }
  for (final bad in ['missing-data', 'duplicate', 'bad-json', 'oversized']) {
    test('reject $bad HTML without substituting recommended programs', () {
      final body = switch (bad) {
        'missing-data' => '<script>{"programId":"lv100"}</script>',
        'duplicate' => page(fixture()) + page(fixture()),
        'bad-json' => '<script id="embedded-data" data-props="bad"></script>',
        _ => 'x' * (NiconicoWatch.responseLimit + 1),
      };
      expect(() => NiconicoWatch.parsePage(body, programId: 'lv100'), failure(NiconicoFailure.schema));
    });
  }
  for (final field in ['status', 'count', 'canWatch', 'needLogin', 'region', 'frontend']) {
    test('unknown $field stays a schema failure', () {
      final data = fixture();
      switch (field) {
        case 'status':
          data['program']['status'] = 'MAYBE';
        case 'count':
          data['program']['statistics']['watchCount'] = -1;
        case 'canWatch':
          data['userProgramWatch'].remove('canWatch');
        case 'needLogin':
          data['programWatch']['condition']['needLogin'] = 0;
        case 'region':
          data['userProgramWatch'].remove('isCountryRestrictionTarget');
        case 'frontend':
          data['site']['frontendId'] = '9';
      }
      expect(() => NiconicoWatch.parseData(data, programId: 'lv100'), failure(NiconicoFailure.schema));
    });
  }
  for (final socket in [
    'wss://a.live2.nicovideo.jp/other/wsapi/v2/watch/123?t=x',
    'wss://a.live2.nicovideo.jp/wsapi/v2/watch/123/../124?t=x',
    'wss://a.live2.nicovideo.jp/wsapi/v2/watch/123?t=x&t=y',
    'wss://a.live2.nicovideo.jp:443/wsapi/v2/watch/123?t=x',
    '',
    'https://a.live2.nicovideo.jp/unama/wsapi/v2/watch/123?t=x',
    'wss://a.live2.nicovideo.jp.evil.test/unama/wsapi/v2/watch/123?t=x',
    'wss://user@a.live2.nicovideo.jp/unama/wsapi/v2/watch/123?t=x',
    'wss://a.live2.nicovideo.jp/unama/wsapi/v2/watch/123?t=x&t=y',
    'wss://a.live2.nicovideo.jp/unama/wsapi/v2/watch/123/../124?t=x',
    'wss://a.live2.nicovideo.jp/unama/wsapi/v2/watch/123?t=x#fragment',
  ]) {
    test('reject unverified websocket shape $socket', () {
      final data = fixture();
      data['site']['relive']['webSocketUrl'] = socket;
      expect(() => NiconicoWatch.parseData(data, programId: 'lv100'), failure(NiconicoFailure.schema));
    });
  }
  test('null cumulative watch count stays unknown', () {
    final data = fixture();
    data['program']['statistics']['watchCount'] = null;
    expect(NiconicoWatch.parseData(data, programId: 'lv100').reportedWatchCount, isNull);
  });
  test('request uses exact watch path and releases owned token, not caller', () async {
    final caller = CancelToken();
    late CancelToken owned;
    final api = NiconicoApi(
      request: (uri, cancel) async {
        owned = cancel;
        expect(uri.toString(), 'https://live.nicovideo.jp/watch/lv100');
        return (status: 200, body: page(fixture()));
      },
    );
    expect((await api.room('lv100', cancel: caller)).programId, 'lv100');
    expect(owned.isCancelled, isTrue);
    expect(caller.isCancelled, isFalse);
  });
  for (final spec in [
    (403, NiconicoFailure.access),
    (404, NiconicoFailure.missing),
    (429, NiconicoFailure.rateLimited),
    (503, NiconicoFailure.service),
    (302, NiconicoFailure.transport),
  ]) {
    test('HTTP ${spec.$1} is not offline or schema success', () async {
      final api = NiconicoApi(request: (_, _) async => (status: spec.$1, body: page(fixture('ended'))));
      await expectLater(api.room('lv100'), failure(spec.$2));
    });
  }
  test('invalid ID and pre-cancelled requests stop before transport', () async {
    var calls = 0;
    final api = NiconicoApi(
      request: (_, _) async {
        calls++;
        return (status: 200, body: '');
      },
    );
    await expectLater(api.room('../lv100'), failure(NiconicoFailure.identity));
    await expectLater(api.room('lv100', cancel: CancelToken()..cancel()), failure(NiconicoFailure.cancelled));
    expect(calls, 0);
  });
  test('deadline releases owned transport and consumes late failures', () async {
    final pending = Completer<({int status, String body})>();
    final caller = CancelToken();
    late CancelToken owned;
    final api = NiconicoApi(
      deadline: const Duration(milliseconds: 10),
      request: (_, cancel) {
        owned = cancel;
        return pending.future;
      },
    );
    await expectLater(api.room('lv100', cancel: caller), failure(NiconicoFailure.transport));
    expect(owned.isCancelled, isTrue);
    expect(caller.isCancelled, isFalse);
    pending.completeError(StateError('late'));
    await Future<void>.delayed(Duration.zero);
  });
  test('pending caller cancellation stops promptly', () async {
    final pending = Completer<({int status, String body})>();
    final caller = CancelToken();
    final api = NiconicoApi(request: (_, _) => pending.future);
    final result = expectLater(api.room('lv100', cancel: caller), failure(NiconicoFailure.cancelled));
    caller.cancel();
    await result;
    pending.complete((status: 200, body: page(fixture())));
  });
  test('strict UTF8 and bounded stream body', () async {
    await expectLater(NiconicoApi.readBody(Stream.value([0xff])), failure(NiconicoFailure.schema));
    await expectLater(
      NiconicoApi.readBody(Stream.value(List.filled(NiconicoWatch.responseLimit + 1, 32))),
      failure(NiconicoFailure.schema),
    );
  });
  test('body timeout cancels the subscription', () async {
    var cancelled = false;
    final source = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    await expectLater(
      NiconicoApi.readBody(source.stream, timeout: const Duration(milliseconds: 10)),
      throwsA(isA<TimeoutException>()),
    );
    expect(cancelled, isTrue);
    await source.close();
  });
}
