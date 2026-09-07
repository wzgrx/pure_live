import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/utils/live_url_tool.dart';

void main() {
  for (final status in [301, 302, 303, 307, 308]) {
    test('b23 resolves HTTP $status without fetching the final room', () async {
      final fixture = ShortLinkFixture((_) async => redirect(status, 'https://live.bilibili.com/123'));
      expect(await fixture.parse('https://b23.tv/fixture'), ['123', 'bilibili']);
      expect(fixture.requests, hasLength(1));
      expect(fixture.closed, 1);
    });
  }

  test('relative Location is resolved against its current short link', () async {
    final fixture = ShortLinkFixture(
      (request) async =>
          request.uri.path == '/first' ? redirect(302, '/second') : redirect(302, 'https://live.bilibili.com/123'),
    );
    expect(await fixture.parse('https://b23.tv/first'), ['123', 'bilibili']);
    expect(fixture.requests.map((r) => r.uri.path), ['/first', '/second']);
    expect(fixture.created, 1);
    expect(fixture.closed, 1);
  });

  test('a self redirect stops before fetching the same URL twice', () async {
    final fixture = ShortLinkFixture((request) async => redirect(302, request.uri.toString()));
    expect(await fixture.parse('https://b23.tv/loop'), isEmpty);
    expect(fixture.requests, hasLength(1));
    expect(fixture.closed, 1);
  });

  test('different redirect URLs still share a finite request budget', () async {
    var index = 0;
    final fixture = ShortLinkFixture((_) async => redirect(302, 'https://b23.tv/next${++index}'));
    expect(await fixture.parse('https://b23.tv/first'), isEmpty);
    expect(fixture.requests.length, lessThanOrEqualTo(8));
    expect(fixture.closed, 1);
  });

  test('failed request closes its owned client', () async {
    final fixture = ShortLinkFixture(
      (request) async =>
          throw DioException.connectionError(requestOptions: request, reason: 'fixture connection failure'),
    );
    expect(await fixture.parse('https://b23.tv/fail'), isEmpty);
    expect(fixture.closed, 1);
  });

  test('short link request has finite connect send and receive timeouts', () async {
    final fixture = ShortLinkFixture((_) async => redirect(302, 'https://live.bilibili.com/123'));
    expect(await fixture.parse('https://b23.tv/fixture'), ['123', 'bilibili']);
    final request = fixture.requests.single;
    for (final timeout in [request.connectTimeout, request.sendTimeout, request.receiveTimeout]) {
      expect(timeout, isNotNull);
      expect(timeout!.inMilliseconds, inInclusiveRange(1, 12000));
    }
    expect(request.followRedirects, isFalse);
  });

  test('direct links allocate no HTTP clients', () async {
    final fixture = ShortLinkFixture((_) async => throw StateError('Unexpected request'));
    expect(await fixture.parse('https://live.bilibili.com/123'), ['123', 'bilibili']);
    expect(fixture.created, 0);
  });

  test('failure of one short link does not hide a later direct room', () async {
    final fixture = ShortLinkFixture((_) async => ResponseBody.fromString('', 503));
    expect(await fixture.parse('https://b23.tv/fail https://www.huya.com/fixture'), ['fixture', 'huya']);
    expect(fixture.closed, 1);
  });

  test('Douyin short link accepts a canonical live room redirect', () async {
    final fixture = ShortLinkFixture((_) async => redirect(302, 'https://live.douyin.com/456'));
    expect(await fixture.parse('https://v.douyin.com/fixture'), ['456', 'douyin']);
    expect(fixture.requests, hasLength(1));
    expect(fixture.closed, 1);
  });

  test('Douyin reflow maps internal room ID to the owner web RID', () async {
    final fixture = ShortLinkFixture((request) async {
      if (request.uri.host == 'v.douyin.com') {
        return redirect(302, 'https://webcast.amemv.com/douyin/webcast/reflow/123');
      }
      return ResponseBody.fromString(
        '{"data":{"room":{"owner":{"web_rid":"456"}}}}',
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );
    });
    expect(await fixture.parse('https://v.douyin.com/fixture'), ['456', 'douyin']);
    expect(fixture.requests, hasLength(2));
    expect(fixture.requests.last.uri.path, '/webcast/room/reflow/info/');
    expect(fixture.requests.last.uri.queryParameters['room_id'], '123');
    expect(fixture.created, 1);
    expect(fixture.closed, 1);
  });
  for (final host in ['b23.tv', 'v.douyin.com']) {
    for (final location in [
      'ftp://www.huya.com/123',
      'https://user@live.douyin.com/123',
      'https://example.org/reflow/123',
      'https://[broken',
      '',
    ]) {
      test('$host does not fetch invalid or unrelated Location: $location', () async {
        final fixture = ShortLinkFixture((_) async => redirect(302, location));
        expect(await fixture.parse('https://$host/fixture'), isEmpty);
        expect(fixture.requests, hasLength(1));
        expect(fixture.closed, 1);
      });
    }
  }

  test('a fragment-only redirect does not reset cycle detection', () async {
    var index = 0;
    final fixture = ShortLinkFixture((_) async => redirect(302, 'https://b23.tv/fixture#${++index}'));
    expect(await fixture.parse('https://b23.tv/fixture'), isEmpty);
    expect(fixture.requests, hasLength(1));
  });

  test('ambiguous duplicate Location headers are ignored', () async {
    final fixture = ShortLinkFixture(
      (_) async => ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': ['https://live.bilibili.com/123', 'https://live.bilibili.com/456'],
        },
      ),
    );
    expect(await fixture.parse('https://b23.tv/fixture'), isEmpty);
    expect(fixture.closed, 1);
  });

  for (final status in [200, 304, 404, 500]) {
    test('non-redirect HTTP $status does not use Location as a room', () async {
      final fixture = ShortLinkFixture((_) async => redirect(status, 'https://live.bilibili.com/123'));
      expect(await fixture.parse('https://b23.tv/fixture'), isEmpty);
      expect(fixture.closed, 1);
    });
  }

  for (final payload in [
    'null',
    '[]',
    '{}',
    '{"data":[]}',
    '{"data":{"room":null}}',
    '{"data":{"room":{"owner":{}}}}',
    '{"data":{"room":{"owner":{"web_rid":[]}}}}',
    '{"data":{"room":{"owner":{"web_rid":"not-a-room"}}}}',
    'not json',
  ]) {
    test('malformed Douyin info is a parse failure: $payload', () async {
      final fixture = ShortLinkFixture(
        (request) async => request.uri.host == 'v.douyin.com'
            ? redirect(302, 'https://webcast.amemv.com/reflow/123')
            : ResponseBody.fromString(
                payload,
                200,
                headers: {
                  'content-type': ['application/json'],
                },
              ),
      );
      expect(await fixture.parse('https://v.douyin.com/fixture'), isEmpty);
      expect(fixture.requests, hasLength(2));
      expect(fixture.closed, 1);
    });
  }

  test('a timed-out adapter is cancelled and its late redirect starts no request', () async {
    final pending = Completer<ResponseBody>();
    final fixture = ShortLinkFixture((_) => pending.future);
    final result = await fixture.parse('https://b23.tv/fixture', timeout: const Duration(milliseconds: 30));
    expect(result, isEmpty);
    expect(fixture.closed, 1);
    pending.complete(redirect(302, 'https://b23.tv/late'));
    await Future<void>.delayed(Duration.zero);
    expect(fixture.requests, hasLength(1));
    expect(fixture.cancelled, 1);
    expect(fixture.closed, 1);
  });

  test('separate parses own separate clients and request budgets', () async {
    final fixture = ShortLinkFixture((_) async => redirect(302, 'https://live.bilibili.com/123'));
    expect(await fixture.parse('https://b23.tv/fixture'), ['123', 'bilibili']);
    expect(await fixture.parse('https://b23.tv/fixture'), ['123', 'bilibili']);
    expect(fixture.created, 2);
    expect(fixture.closed, 2);
  });
  test('an already cancelled caller allocates no client', () async {
    final token = CancelToken()..cancel('fixture');
    final fixture = ShortLinkFixture((_) async => redirect(302, 'https://live.bilibili.com/123'));
    expect(await fixture.parse('https://b23.tv/fixture', cancelToken: token), isEmpty);
    expect(fixture.created, 0);
  });

  test('caller cancellation closes the short-link client before a late response', () async {
    final token = CancelToken();
    final pending = Completer<ResponseBody>();
    final started = Completer<void>();
    final fixture = ShortLinkFixture((_) {
      started.complete();
      return pending.future;
    });
    final action = fixture.parse('https://b23.tv/fixture', cancelToken: token);
    await started.future;
    token.cancel('fixture');
    expect(await action, isEmpty);
    expect(fixture.closed, 1);
    pending.complete(redirect(302, 'https://b23.tv/late'));
    await started.future;
    expect(fixture.requests, hasLength(1));
  });
}

ResponseBody redirect(int status, String location) => ResponseBody.fromString(
  '',
  status,
  headers: {
    'location': [location],
  },
);

class ShortLinkFixture {
  ShortLinkFixture(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  final requests = <RequestOptions>[];
  int created = 0;
  int closed = 0;
  int cancelled = 0;

  Future<List<String>> parse(String text, {Duration timeout = const Duration(seconds: 12), CancelToken? cancelToken}) =>
      LiveUrlTool.parseLiveUrl(
        text,
        timeout: timeout,
        cancelToken: cancelToken,
        clientFactory: () {
          created++;
          return Dio()..httpClientAdapter = FixtureAdapter(this);
        },
      );
}

class FixtureAdapter implements HttpClientAdapter {
  FixtureAdapter(this.fixture);
  final ShortLinkFixture fixture;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    fixture.requests.add(options);
    cancelFuture?.then((_) => fixture.cancelled++);
    // Stop the old recursive implementation deterministically, not by waiting
    // for a real network timeout or allowing an unbounded regression test.
    if (fixture.requests.length > 9) {
      throw StateError('Fixture request ceiling reached');
    }
    return fixture.handler(options);
  }

  @override
  void close({bool force = false}) => fixture.closed++;
}
