import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/http_client.dart' as shared;
import 'package:pure_live/core/site/openrec/openrec_api.dart';

Object? _fixture(String name) => jsonDecode(File('test/fixtures/openrec/$name.json').readAsStringSync());
Map<String, dynamic> _movie() => _fixture('movie') as Map<String, dynamic>;
Map<String, dynamic> _channel([bool live = true]) =>
    _fixture(live ? 'channel-live' : 'channel-offline') as Map<String, dynamic>;
({int status, String body}) _ok(Object? value) => (status: 200, body: jsonEncode(value));
OpenrecApi _api(Object? value) => OpenrecApi(request: (_, _) async => _ok(value));
Matcher _failure(OpenrecFailure kind) => throwsA(isA<OpenrecException>().having((e) => e.kind, 'kind', kind));

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) =>
      respond(options);
  @override
  void close({bool force = false}) {}
}

void main() {
  test('captured directory uses v5 page contract and preserves UTF-8 metadata', () async {
    final api = OpenrecApi(
      request: (uri, _) async {
        expect(uri.origin, OpenrecApi.origin);
        expect(uri.path, '/external/api/v5/movies');
        expect(uri.queryParameters, {
          'is_live': 'true',
          'onair_status': '1',
          'page': '2',
          'limit': '1',
          'sort': 'live_views',
        });
        return _ok(_fixture('directory'));
      },
    );
    final result = await api.directory(page: 2, limit: 1);
    expect(result.rawCount, 1);
    expect(result.nextPage, 3);
    expect(result.hasMore, isTrue);
    final movie = result.movies.single;
    expect(movie.id, 'fixture1234');
    expect(movie.channelId, 'Fixture_Owner');
    expect(movie.numericChannelId, 100);
    expect(movie.title, '配信 Fixture');
    expect(movie.cover, endsWith('fixture-cover.jpg'));
    expect(movie.isLive, isTrue, reason: 'Future non-null ended_at is not offline');
    expect(() => result.movies.clear(), throwsUnsupportedError);
  });

  test('empty raw page terminates without inventing a next directory response', () async {
    final result = await _api(_fixture('empty-page')).directory(page: 2, limit: 1);
    expect(result.movies, isEmpty);
    expect(result.hasMore, isFalse);
  });

  test('raw rows, not filtered or deduplicated cards, determine continuation', () async {
    final ended = _movie()..['onair_status'] = 2;
    final result = await _api([ended, ended]).directory(limit: 2);
    expect(result.movies, isEmpty);
    expect(result.rawCount, 2);
    expect(result.hasMore, isTrue);
    final dedup = await _api([_movie(), _movie()]).directory(limit: 2);
    expect(dedup.movies, hasLength(1));
    expect(dedup.hasMore, isTrue);
  });

  test('requested limit is a hint: short and oversized pages both continue', () async {
    final short = await _api([_movie()]).directory(limit: 30);
    expect(short.rawCount, 1);
    expect(short.hasMore, isTrue);
    final larger = _movie()..['id'] = 'fixture5678';
    final over = await _api([_movie(), larger]).directory(limit: 1);
    expect(over.rawCount, 2);
    expect(over.movies, hasLength(2));
    expect(over.hasMore, isTrue);
    expect(over.nextPage, 2);
  });

  test('pagination ceiling reports an error rather than offering an invalid cursor', () async {
    await expectLater(_api([_movie()]).directory(page: 1000000), _failure(OpenrecFailure.schema));
    expect((await _api([]).directory(page: 1000000)).hasMore, isFalse);
  });

  test('duplicate broadcast identity conflict is surfaced, not silently merged', () async {
    final changed = _movie();
    changed['channel']['openrec_user_id'] = 999;
    await expectLater(_api([_movie(), changed]).directory(), _failure(OpenrecFailure.identity));
  });

  test('owner uses case-preserved public ID and validates numeric identity', () async {
    final api = OpenrecApi(
      request: (uri, _) async {
        expect(uri.path, '/external/api/v5/channels/Fixture_Owner');
        expect(uri.hasQuery, isFalse);
        return _ok(_channel());
      },
    );
    final result = await api.channel('Fixture_Owner', expectedNumericId: 100);
    expect(result.movieIds, ['fixture1234']);
    expect(result.name, '配信者 Fixture');
    expect(() => result.movieIds.clear(), throwsUnsupportedError);
    await expectLater(api.channel('Fixture_Owner', expectedNumericId: 999), _failure(OpenrecFailure.identity));
    await expectLater(_api(_channel()).channel('fixture_owner'), _failure(OpenrecFailure.identity));
  });

  test('captured explicit offline channel avoids any broadcast request', () async {
    var calls = 0;
    final api = OpenrecApi(
      request: (_, _) async {
        calls++;
        return _ok(_channel(false));
      },
    );
    final room = await api.room('Fixture_Owner');
    expect(room.channel.isLive, isFalse);
    expect(room.broadcast, isNull);
    expect(calls, 1);
  });

  test('missing/inconsistent current movie list is an error, not offline', () async {
    for (final value in [null, 'bad']) {
      await expectLater(
        _api(_channel()..['onair_broadcast_movies'] = value).channel('Fixture_Owner'),
        _failure(OpenrecFailure.schema),
      );
    }
    await expectLater(
      _api(_channel()..['onair_broadcast_movies'] = []).channel('Fixture_Owner'),
      _failure(OpenrecFailure.mediaUnavailable),
    );
    await expectLater(_api(_channel()..['is_live'] = false).channel('Fixture_Owner'), _failure(OpenrecFailure.schema));
    final wrong = _channel();
    wrong['onair_broadcast_movies'][0]['channel']['id'] = 'SomeoneElse';
    await expectLater(_api(wrong).channel('Fixture_Owner'), _failure(OpenrecFailure.identity));
  });

  test('multiple current broadcasts need selection rather than first-row guessing', () async {
    final channel = _channel();
    channel['onair_broadcast_movies'].add(_movie()..['id'] = 'fixture5678');
    await expectLater(_api(channel).room('Fixture_Owner'), _failure(OpenrecFailure.ambiguous));
  });

  test('room reacquires channel and current broadcast on every resolution', () async {
    var generation = 0;
    final paths = <String>[];
    final api = OpenrecApi(
      request: (uri, _) async {
        paths.add(uri.path);
        if (uri.path.contains('/channels/')) {
          generation++;
          final owner = _channel();
          owner['onair_broadcast_movies'][0]['id'] = 'fixture$generation';
          return _ok(owner);
        }
        return _ok(_movie()..['id'] = 'fixture$generation');
      },
    );
    expect((await api.room('Fixture_Owner')).broadcast!.movie.id, 'fixture1');
    expect((await api.room('Fixture_Owner')).broadcast!.movie.id, 'fixture2');
    expect(paths, [
      '/external/api/v5/channels/Fixture_Owner',
      '/external/api/v5/movies/fixture1',
      '/external/api/v5/channels/Fixture_Owner',
      '/external/api/v5/movies/fixture2',
    ]);
  });

  test('captured media families preserve URLs without invented quality or rewrites', () async {
    final movie = _movie();
    movie['media']['url'] += '?sig=fixture%2Bvalue&expires=123';
    final result = await _api(movie)
        .broadcast('fixture1234', expectedChannelId: 'Fixture_Owner', expectedNumericId: 100);
    expect(result.media.map((m) => m.id), ['hls', 'low-latency-hls', 'public-hls']);
    expect(result.media.first.url, movie['media']['url']);
    expect(() => result.media.clear(), throwsUnsupportedError);
  });

  test('broadcast identity is checked before media and restricted state', () async {
    final movie = _movie()..['public_type'] = 'subscription';
    await expectLater(_api(movie).broadcast('another'), _failure(OpenrecFailure.identity));
    await expectLater(
      _api(movie).broadcast('fixture1234', expectedChannelId: 'Wrong'),
      _failure(OpenrecFailure.identity),
    );
    await expectLater(_api(movie).broadcast('fixture1234', expectedNumericId: 999), _failure(OpenrecFailure.identity));
    await expectLater(_api(movie).movie('another'), _failure(OpenrecFailure.identity));
  });

  test('restricted metadata stays available but no trial media is promoted', () async {
    final restrictions = <String, Object>{
      'public_type': 'subscription',
      'is_hidden': true,
      'is_banned': true,
      'force_expired': true,
      'is_premiere': true,
      'encryption_type': 1,
      'ppv_event': {'id': 'fixture-event'},
    };
    for (final entry in restrictions.entries) {
      final value = _movie()..[entry.key] = entry.value;
      value['subs_trial_media']['url'] = 'https://dfixture.cloudfront.net/trial.m3u8';
      final api = _api(value);
      expect((await api.movie('fixture1234')).publicMediaAllowed, isFalse);
      await expectLater(api.broadcast('fixture1234'), _failure(OpenrecFailure.restricted));
    }
  });

  test('ended, scheduled and uploaded movies never become live media', () async {
    for (final value in [
      _movie()..['onair_status'] = 2,
      _movie()..['onair_status'] = 0,
      _movie()..['is_live'] = false,
    ]) {
      expect((await _api(value).movie('fixture1234')).isLive, isFalse);
      await expectLater(_api(value).broadcast('fixture1234'), _failure(OpenrecFailure.notLive));
    }
  });

  test('missing media and trial-only response do not mean a channel is offline', () async {
    final movie = _movie()..['media'] = <String, dynamic>{};
    movie['subs_trial_media']['url'] = 'https://dfixture.cloudfront.net/trial.m3u8';
    expect((await _api(movie).movie('fixture1234')).isLive, isTrue);
    await expectLater(_api(movie).broadcast('fixture1234'), _failure(OpenrecFailure.mediaUnavailable));
    await expectLater(_api(_movie()..['media'] = null).broadcast('fixture1234'), _failure(OpenrecFailure.schema));
  });

  test('duplicate source URLs are coalesced without losing the first family', () async {
    final movie = _movie();
    movie['media']['url_ull'] = movie['media']['url'];
    expect((await _api(movie).broadcast('fixture1234')).media.map((m) => m.id), ['hls', 'public-hls']);
  });

  test('hidden viewers stay unknown and cumulative totals are not substituted', () async {
    final movie = _movie()..['is_viewers_hidden'] = true;
    movie['live_views'] = 'hidden';
    movie['total_views'] = 999999;
    expect((await _api(movie).movie('fixture1234')).viewers, isNull);
    movie['is_viewers_hidden'] = false;
    movie['live_views'] = null;
    expect((await _api(movie).movie('fixture1234')).viewers, isNull);
    movie['live_views'] = 0;
    expect((await _api(movie).movie('fixture1234')).viewers, 0);
  });

  test('empty title falls back to nickname and malformed images are omitted', () async {
    final movie = _movie()..['title'] = '  ';
    movie['thumbnail_url'] = 'https://image-handler.mellow-fan.com.evil.test/a.jpg';
    final result = await _api(movie).movie('fixture1234');
    expect(result.title, result.name);
    expect(result.cover, isEmpty);
  });

  test('missing flags and unknown schemas fail closed without inventing state', () async {
    for (final key in [
      'is_live',
      'onair_status',
      'public_type',
      'is_hidden',
      'is_banned',
      'force_expired',
      'is_premiere',
      'encryption_type',
      'ppv_event',
      'is_viewers_hidden',
    ]) {
      await expectLater(_api(_movie()..remove(key)).movie('fixture1234'), _failure(OpenrecFailure.schema));
    }
    for (final value in [3, '1', -1]) {
      await expectLater(_api(_movie()..['onair_status'] = value).movie('fixture1234'), _failure(OpenrecFailure.schema));
    }
    await expectLater(_api({'message': 'upstream-error', 'status': -4}).directory(), _failure(OpenrecFailure.schema));
  });

  test('invalid IDs and pagination are rejected before any request', () async {
    var calls = 0;
    final api = OpenrecApi(
      request: (_, _) async {
        calls++;
        return _ok([]);
      },
    );
    for (final id in ['', '../owner', 'a/b', '%2e', ' a', 'a?b', 'a#b', '中文', 'a' * 65, 'a\n']) {
      await expectLater(api.channel(id), _failure(OpenrecFailure.identity));
      await expectLater(api.broadcast(id), _failure(OpenrecFailure.identity));
    }
    for (final page in [0, -1, 1000001]) {
      await expectLater(api.directory(page: page), _failure(OpenrecFailure.schema));
    }
    for (final limit in [0, -1, 31]) {
      await expectLater(api.directory(limit: limit), _failure(OpenrecFailure.schema));
    }
    expect(calls, 0);
  });

  test('media validates scheme host port userinfo fragment and HLS path', () async {
    for (final url in [
      'file:///a.m3u8',
      'http://dfixture.cloudfront.net/a.m3u8',
      'https://127.0.0.1/a.m3u8',
      'https://dfixture.cloudfront.net.evil.test/a.m3u8',
      'https://user@dfixture.cloudfront.net/a.m3u8',
      'https://dfixture.cloudfront.net:8443/a.m3u8',
      'https://dfixture.cloudfront.net/a.m3u8#x',
      'https://dfixture.cloudfront.net/a.mp4',
      'https://dfixture.cloudfront.net/a b.m3u8',
    ]) {
      final movie = _movie();
      movie['media']['url'] = url;
      await expectLater(_api(movie).broadcast('fixture1234'), _failure(OpenrecFailure.schema));
    }
  });

  test('HTTP failures are typed and never converted to offline', () async {
    for (final entry in {
      401: OpenrecFailure.access,
      403: OpenrecFailure.access,
      404: OpenrecFailure.missing,
      429: OpenrecFailure.rateLimited,
      503: OpenrecFailure.service,
      302: OpenrecFailure.transport,
      400: OpenrecFailure.transport,
    }.entries) {
      final api = OpenrecApi(request: (_, _) async => (status: entry.key, body: 'sensitive upstream detail'));
      await expectLater(api.room('Fixture_Owner'), _failure(entry.value));
      expect(OpenrecException(entry.value).toString(), isNot(contains('sensitive')));
    }
    await expectLater(
      OpenrecApi(request: (_, _) async => throw Exception('secret')).directory(),
      _failure(OpenrecFailure.transport),
    );
  });

  test('pre-cancelled and late cancelled responses are discarded', () async {
    var calls = 0;
    final token = CancelToken()..cancel();
    final api = OpenrecApi(
      request: (_, _) async {
        calls++;
        return _ok([]);
      },
    );
    await expectLater(api.directory(cancel: token), _failure(OpenrecFailure.cancelled));
    expect(calls, 0);
    final lateToken = CancelToken();
    final lateApi = OpenrecApi(
      request: (_, _) async {
        lateToken.cancel();
        return _ok([]);
      },
    );
    await expectLater(lateApi.directory(cancel: lateToken), _failure(OpenrecFailure.cancelled));
  });

  test('JSON and injected UTF-8 byte budget are enforced', () async {
    for (final body in ['[', '"${'中' * (OpenrecApi.responseLimit ~/ 3 + 1)}"']) {
      await expectLater(
        OpenrecApi(request: (_, _) async => (status: 200, body: body)).directory(),
        _failure(OpenrecFailure.schema),
      );
    }
    await expectLater(OpenrecApi.readBody(Stream.value([0xe3, 0x81])), _failure(OpenrecFailure.schema));
  });

  test('stream deadline cancels a stalled body', () async {
    var cancelled = false;
    final stream = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    await expectLater(
      OpenrecApi.readBody(stream.stream, timeout: const Duration(milliseconds: 30)),
      throwsA(isA<TimeoutException>()),
    );
    expect(cancelled, isTrue);
    await stream.close();
  });

  test('production transport retains headers, no redirects, and shared caller ownership', () async {
    final previous = shared.HttpClient.instance.dio;
    final caller = CancelToken();
    final dio = Dio()
      ..httpClientAdapter = _Adapter((options) async {
        expect(options.responseType, ResponseType.stream);
        expect(options.followRedirects, isFalse);
        expect(options.receiveTimeout, const Duration(seconds: 20));
        for (final entry in OpenrecApi.headers.entries) {
          expect(options.headers[entry.key], entry.value);
        }
        return ResponseBody.fromString(_ok(_channel(false)).body, 200);
      });
    shared.HttpClient.instance.dio = dio;
    try {
      expect((await OpenrecApi().channel('Fixture_Owner', cancel: caller)).isLive, isFalse);
      expect(caller.isCancelled, isFalse);
    } finally {
      shared.HttpClient.instance.dio = previous;
      dio.close();
    }
  });

  for (final status in [403, 200]) {
    test('production status $status closes error/overflow upstream without cancelling caller', () async {
      var closed = false;
      late final StreamController<Uint8List> stream;
      stream = StreamController<Uint8List>(
        onListen: () {
          if (status == 200) stream.add(Uint8List(OpenrecApi.responseLimit + 1));
        },
        onCancel: () {
          closed = true;
        },
      );
      final previous = shared.HttpClient.instance.dio;
      final caller = CancelToken();
      final dio = Dio()..httpClientAdapter = _Adapter((_) async => ResponseBody(stream.stream, status));
      shared.HttpClient.instance.dio = dio;
      try {
        await expectLater(
          OpenrecApi().directory(cancel: caller),
          _failure(status == 403 ? OpenrecFailure.access : OpenrecFailure.schema),
        );
        expect(closed, isTrue);
        expect(caller.isCancelled, isFalse);
      } finally {
        shared.HttpClient.instance.dio = previous;
        dio.close();
        await stream.close();
      }
    });
  }

  test('production caller cancellation closes stalled upstream', () async {
    var closed = false;
    final listening = Completer<void>();
    final stream = StreamController<Uint8List>(
      onListen: listening.complete,
      onCancel: () {
        closed = true;
      },
    );
    final previous = shared.HttpClient.instance.dio;
    final caller = CancelToken();
    final dio = Dio()..httpClientAdapter = _Adapter((_) async => ResponseBody(stream.stream, 200));
    shared.HttpClient.instance.dio = dio;
    try {
      final check = expectLater(OpenrecApi().directory(cancel: caller), _failure(OpenrecFailure.cancelled));
      await listening.future;
      caller.cancel();
      await check;
      expect(closed, isTrue);
    } finally {
      shared.HttpClient.instance.dio = previous;
      dio.close();
      await stream.close();
    }
  });
}
