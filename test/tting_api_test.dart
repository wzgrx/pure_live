import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/tting/tting_api.dart';
import 'package:pure_live/core/site/tting/tting_link.dart';

void main() {
  late Map<String, dynamic> profile;
  late Map<String, dynamic> stream;
  late Map<String, dynamic> directory;
  final now = DateTime.utc(2026, 9, 9);
  setUp(() {
    Map<String, dynamic> read(String name) =>
        jsonDecode(File('test/fixtures/tting/$name.json').readAsStringSync()) as Map<String, dynamic>;
    profile = read('profile');
    stream = read('stream');
    directory = read('directory');
  });
  Matcher failure(TtingFailure kind) => isA<TtingException>().having((e) => e.kind, 'kind', kind);
  TtingChannel channel() => TtingApi.parseChannel(profile, expectedId: 101);
  TtingBroadcast broadcast() => TtingApi.parseBroadcast(stream, channel(), now: now);

  test('sanitized official contract distinguishes channel, owner, broadcast and current title', () {
    final result = broadcast();
    expect(result.channel.id, 101);
    expect(result.channel.ownerId, 202);
    expect(result.id, 303);
    expect(result.title, 'Current live title');
    expect(result.sources.map((e) => e.resolution), [1080, 720, 480, 0]);
    final source = result.sources.first;
    expect(source.policy.matchesSource(Uri.parse(source.url)), isTrue);
    expect(() => result.sources.clear(), throwsUnsupportedError);
    expect(TtingApi.parseDirectory(directory).single.viewers, 16);
    expect(TtingApi.playHeaders.containsKey('x-site-code'), isFalse);
    expect(TtingApi.apiHeaders['x-site-code'], 'flex');
  });
  for (final which in ['channel', 'owner', 'broadcast-channel', 'profile-channel']) {
    test('rejects mismatched $which identity', () {
      switch (which) {
        case 'channel':
          stream['id'] = 102;
        case 'owner':
          (stream['owner'] as Map)['id'] = 203;
        case 'broadcast-channel':
          (stream['stream'] as Map)['channelId'] = 102;
        case 'profile-channel':
          profile['id'] = 102;
      }
      expect(broadcast, throwsA(failure(TtingFailure.identity)));
    });
  }
  for (final key in ['endedAt', 'disconnectedAt', 'finalized']) {
    test('$key is not a currently playable broadcast', () {
      (stream['stream'] as Map)[key] = key == 'finalized' ? 1 : '2026-09-09T00:00:00Z';
      expect(broadcast, throwsA(failure(TtingFailure.notLive)));
    });
  }
  for (final key in ['isLocked', 'isForAdult', 'suspended', 'blind', 'minRatingLevel']) {
    test('enforces broadcast barrier $key', () {
      ((stream['status'] as Map)['barrier'] as Map)[key] = 1;
      expect(broadcast, throwsA(failure(TtingFailure.restricted)));
    });
  }
  test('missing state fields, malformed flags and duplicate resolutions fail explicitly', () {
    (stream['stream'] as Map).remove('endedAt');
    expect(broadcast, throwsA(failure(TtingFailure.schema)));
    (stream['stream'] as Map)['endedAt'] = null;
    (stream['stream'] as Map)['suspended'] = 'false';
    expect(broadcast, throwsA(failure(TtingFailure.schema)));
    (stream['stream'] as Map)['suspended'] = 0;
    (stream['sources'] as List).add((stream['sources'] as List).first);
    expect(broadcast, throwsA(failure(TtingFailure.schema)));
  });
  for (final url in [
    'http://fixture.edge.naverncp.com/live/master.m3u8?token=exp=2000000000',
    'https://attacker.example/live/master.m3u8?token=exp=2000000000',
    'https://fixture.edge.naverncp.com:444/live/master.m3u8?token=exp=2000000000',
    'https://user@fixture.edge.naverncp.com/live/master.m3u8?token=exp=2000000000',
    'https://fixture.edge.naverncp.com/live/master.m3u8?token=a&token=b',
    'https://fixture.edge.naverncp.com/live/master.m3u8?token=unsigned',
  ]) {
    test('rejects malformed or unsupported media source ${Uri.parse(url).host} ${url.length}', () {
      ((stream['sources'] as List).first as Map)['url'] = url;
      expect(broadcast, throwsA(failure(TtingFailure.schema)));
    });
  }
  test('expired source and unsupported family are distinct from offline', () {
    expect(
      () => TtingApi.parseBroadcast(stream, channel(), now: DateTime.utc(2040)),
      throwsA(failure(TtingFailure.expired)),
    );
    stream['sourceType'] = 'unknown';
    expect(broadcast, throwsA(failure(TtingFailure.mediaUnavailable)));
  });
  test('adjacent duplicate expiry fields are rejected without exposing their values', () {
    ((stream['sources'] as List).first as Map)['url'] =
        'https://fixture.edge.naverncp.com/live/master.m3u8?token=exp=2000000000~exp=2000000001~hmac=fixture';
    expect(broadcast, throwsA(failure(TtingFailure.schema)));
    expect(const TtingException(TtingFailure.schema).toString(), 'TTing schema');
  });
  test('observed NCP low-latency family retains its identity and sibling-resource policy', () {
    stream['sourceType'] = 'ncp_llh';
    for (final raw in stream['sources'] as List) {
      final source = raw as Map;
      source['format'] = 'ncp_llh';
      source['url'] =
          'https://fixture.edge.naverncp.com/live/video/channel/vfrag${source['resolution']}_playlist.m3u8?token=st=1700000000~exp=2000000000~hmac=fixture';
    }
    final result = broadcast();
    expect(result.sources.every((source) => source.family == 'ncp_llh'), isTrue);
    expect(result.sources.map((source) => source.resolution), [1080, 720, 480, 0]);
    final source = result.sources.first;
    expect(source.policy.matchesSource(Uri.parse(source.url)), isTrue);
    (stream['sources'] as List).first['format'] = 'ncp';
    expect(broadcast, throwsA(failure(TtingFailure.mediaUnavailable)));
  });
  test('restricted profile is checked before requesting media', () async {
    (profile['barrier'] as Map)['isLocked'] = true;
    var calls = 0;
    final api = TtingApi(
      request: (_, _) async {
        calls++;
        return (status: 200, body: jsonEncode(profile));
      },
    );
    await expectLater(api.room(101), throwsA(failure(TtingFailure.restricted)));
    expect(calls, 1);
  });
  test('total room deadline includes both profile and stream requests', () async {
    var calls = 0;
    CancelToken? transport;
    final pending = Completer<({int status, String body})>();
    final api = TtingApi(
      deadline: const Duration(milliseconds: 80),
      now: () => now,
      request: (uri, token) async {
        calls++;
        transport = token;
        if (uri.path.endsWith('/profile')) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return (status: 200, body: jsonEncode(profile));
        }
        return pending.future;
      },
    );
    await expectLater(api.room(101), throwsA(failure(TtingFailure.transport)));
    expect(calls, 2);
    expect(transport!.isCancelled, isTrue);
    pending.complete((status: 200, body: jsonEncode(stream)));
  });
  test('directory is a finite snapshot with strict identity and count checks', () {
    directory['count'] = 2;
    expect(() => TtingApi.parseDirectory(directory), throwsA(failure(TtingFailure.schema)));
    (directory['data'] as List).add((directory['data'] as List).first);
    expect(() => TtingApi.parseDirectory(directory), throwsA(failure(TtingFailure.identity)));
  });
  test('directory excludes restricted cards without guessing media from playSource', () {
    (((directory['data'] as List).first as Map)['barrier'] as Map)['isLocked'] = true;
    expect(TtingApi.parseDirectory(directory), isEmpty);
  });
  for (final code in [400, 401, 403, 404, 429, 500]) {
    test('HTTP $code remains a classified failure, not an offline room', () async {
      final api = TtingApi(request: (_, _) async => (status: code, body: '{"message":"ended"}'));
      final kind = switch (code) {
        401 || 403 => TtingFailure.access,
        404 => TtingFailure.missing,
        429 => TtingFailure.rateLimited,
        500 => TtingFailure.service,
        _ => TtingFailure.transport,
      };
      await expectLater(api.room(101), throwsA(failure(kind)));
    });
  }
  test('room uses profile first, cross-checks stream, and cancels its owned transport', () async {
    final paths = <String>[];
    final tokens = <CancelToken>[];
    final api = TtingApi(
      now: () => now,
      request: (uri, cancel) async {
        paths.add('${uri.path}?${uri.query}');
        tokens.add(cancel);
        expect(uri.host, 'api.flextv.co.kr');
        return (status: 200, body: jsonEncode(uri.path.endsWith('/profile') ? profile : stream));
      },
    );
    final result = await api.room(101);
    expect(result.broadcast!.id, 303);
    expect(paths, ['/api/channels/101/profile?', '/api/channels/101/stream?option=all']);
    expect(identical(tokens.first, tokens.last), isTrue);
    expect(tokens.every((t) => t.isCancelled), isTrue);
  });
  test('offline profile skips stream and does not reuse historical broadcast', () async {
    profile['isInLive'] = 0;
    var calls = 0;
    final result = await TtingApi(
      request: (_, _) async {
        calls++;
        return (status: 200, body: jsonEncode(profile));
      },
    ).room(101);
    expect(result.broadcast, isNull);
    expect(calls, 1);
  });
  test('explicit cancellation ends a pending custom request without cancelling its caller on success', () async {
    final caller = CancelToken();
    final entered = Completer<CancelToken>();
    final pending = Completer<({int status, String body})>();
    final api = TtingApi(
      request: (_, token) {
        entered.complete(token);
        return pending.future;
      },
    );
    final result = api.channel(101, cancel: caller);
    final assertion = expectLater(result, throwsA(failure(TtingFailure.cancelled)));
    final token = await entered.future;
    caller.cancel();
    await assertion;
    expect(token.isCancelled, isTrue);
    pending.complete((status: 200, body: jsonEncode(profile)));
    final other = CancelToken();
    await TtingApi(request: (_, _) async => (status: 200, body: jsonEncode(profile))).channel(101, cancel: other);
    expect(other.isCancelled, isFalse);
  });
  test('one total deadline cancels slow profile acquisition', () async {
    final pending = Completer<({int status, String body})>();
    CancelToken? token;
    final api = TtingApi(
      deadline: const Duration(milliseconds: 20),
      request: (_, cancel) {
        token = cancel;
        return pending.future;
      },
    );
    await expectLater(api.room(101), throwsA(failure(TtingFailure.transport)));
    expect(token!.isCancelled, isTrue);
    pending.complete((status: 200, body: jsonEncode(profile)));
  });
  test('body size, UTF8 and slow-body limits close the stream subscription', () async {
    await expectLater(TtingApi.readBody(Stream.value([0xff])), throwsA(failure(TtingFailure.schema)));
    await expectLater(
      TtingApi.readBody(Stream.value(List.filled(TtingApi.responseLimit + 1, 0))),
      throwsA(failure(TtingFailure.schema)),
    );
    var cancelled = false;
    final body = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    await expectLater(
      TtingApi.readBody(body.stream, timeout: const Duration(milliseconds: 20)),
      throwsA(isA<TimeoutException>()),
    );
    expect(cancelled, isTrue);
    await body.close();
  });
  test('link parser accepts only exact channel identities on observed brands', () {
    for (final value in [
      '101',
      'https://www.flextv.co.kr/channels/101/live',
      'https://ttinglive.com/channels/101/live?from=share',
    ]) {
      expect(TtingLink.parse(value), 101);
    }
    for (final value in [
      '0',
      '01',
      'https://evil.example/channels/101/live',
      'https://www.flextv.co.kr.evil.example/channels/101/live',
      'https://www.flextv.co.kr/channels/101',
      'https://www.flextv.co.kr/channels/%31/live',
      'https://user@www.flextv.co.kr/channels/101/live',
      'https://www.flextv.co.kr/a/../channels/101/live',
    ]) {
      expect(TtingLink.parse(value), isNull);
    }
  });
}
