import 'dart:convert';

import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

/// Answers every request with [status] and [body], or throws [failure].
final class _Fixed implements LiveHttp {
  new({this.status = 200, this.body = '', this.headers = const {}, this.failure});

  final int status;
  final String body;
  final Map<String, List<String>> headers;
  final TransportFailure? failure;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    final error = failure;
    if (error != null) throw error;
    return LiveResponse(status: status, bytes: utf8.encode(body), url: request.url, headers: headers);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async {
    final response = await send(request);
    return LiveStreamedResponse(
      status: response.status,
      body: Stream.value(response.bytes),
      url: request.url,
      headers: response.headers,
      contentLength: response.bytes.length,
    );
  }

  @override
  void close() {}
}

LiveRequest _secretRequest() => LiveRequest(
  site: 'acfun',
  url: Uri.parse(
    'https://fixture-user:fixture-password@cdn.example/fixture-path-secret/stream.flv'
    '?token=fixture-token&acfun.api.visitor_st=fixture-visitor#fixture-fragment',
  ),
  method: 'POST',
  headers: const {'Cookie': 'fixture-cookie', 'Access-Token': 'fixture-access-token'},
  body: utf8.encode('{"password":"fixture-body-secret","nested":{"cookie":"fixture-nested-secret"}}'),
);

void main() {
  test('diagnostics never print signed URLs, payloads, credentials or header values', () async {
    final messages = <String>[];
    final http = LoggingHttp(
      _Fixed(
        status: 403,
        body: '{"access_token":"fixture-response-token"}',
        headers: const {
          'set-cookie': ['fixture-response-cookie'],
        },
      ),
      onFailure: messages.add,
    );
    final response = await http.send(_secretRequest());
    expect(response.status, 403, reason: 'the response is passed on unchanged');
    expect(messages, hasLength(1));
    final message = messages.single;
    expect(message, contains('[badResponse]'));
    expect(message, contains('https://cdn.example'));
    expect(message, contains('403'));
    expect(message, contains('POST'));
    expect(message, contains('Request Query Keys: [token,acfun.api.visitor_st]'));
    expect(message, contains('Request Header Keys: [Cookie,Access-Token]'));
    expect(message, contains('Response Header Keys: [set-cookie]'));
    expect(message, isNot(contains('fixture-')));
  });

  test('transport failures are reported with their reason; cancellation is not a failure', () async {
    final messages = <String>[];
    await expectLater(
      LoggingHttp(
        _Fixed(failure: const TransportFailure('acfun', TransportReason.timeout, 'fixture-inner-secret')),
        onFailure: messages.add,
      ).send(_secretRequest()),
      throwsA(isA<TransportFailure>()),
    );
    expect(messages.single, contains('[timeout]'));
    expect(messages.single, contains('Response Code: none'));
    expect(messages.single, isNot(contains('fixture-')));

    messages.clear();
    await expectLater(
      LoggingHttp(
        _Fixed(failure: const TransportFailure('acfun', TransportReason.cancelled)),
        onFailure: messages.add,
      ).send(_secretRequest()),
      throwsA(isA<TransportFailure>()),
    );
    expect(messages, isEmpty);
  });

  test('successful requests are not reported; streamed failures are', () async {
    final messages = <String>[];
    await LoggingHttp(_Fixed(), onFailure: messages.add).send(_secretRequest());
    expect(messages, isEmpty);
    final streamed = await LoggingHttp(
      _Fixed(status: 404, body: 'gone'),
      onFailure: messages.add,
    ).open(_secretRequest());
    expect(streamed.status, 404);
    expect(messages.single, contains('Response Data Shape: bytes(4)'));
  });

  test('a failing diagnostic sink never replaces the original failure or response', () async {
    final http = LoggingHttp(_Fixed(status: 500), onFailure: (_) => throw StateError('sink unavailable'));
    expect((await http.send(_secretRequest())).status, 500);
    await expectLater(
      LoggingHttp(
        _Fixed(failure: const TransportFailure('acfun', TransportReason.connect)),
        onFailure: (_) => throw StateError('sink unavailable'),
      ).send(_secretRequest()),
      throwsA(isA<TransportFailure>().having((f) => f.reason, 'reason', TransportReason.connect)),
    );
  });

  test('large bodies stay structural, a clock step back prints as unknown, keys are redacted', () {
    final request = LiveRequest(
      site: 'x',
      url: Uri.parse('https://api.example/live?${List.generate(30, (i) => 'k$i=v').join('&')}'),
      body: utf8.encode('private-body' * 100000),
      headers: const {'Bearer abc def': 'private'},
    );
    final text = describeHttpFailure(
      request,
      kind: 'badResponse',
      elapsed: const Duration(seconds: -60),
      status: 502,
      responseLength: 10000,
    );
    expect(text, contains('Time:unknown'));
    expect(text, contains('Request Data Shape: bytes(1200000)'));
    expect(text, contains('Response Data Shape: bytes(10000)'));
    expect(text, contains(',...]'));
    expect(text, contains('(redacted-key)'));
    expect(text, isNot(contains('private')));
    expect(text.length, lessThan(1024));
  });
}
