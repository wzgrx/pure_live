import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/utils/live_url_tool.dart';
import 'package:pure_live/core/common/http_client.dart' as core;
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/twitcasting/twitcasting_api.dart';
import 'package:pure_live/core/site/twitcasting/twitcasting_site.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/multiview/danmaku/multiview_danmaku_session.dart';
import 'package:pure_live/modules/search/search_capability.dart';
import 'package:pure_live/modules/search/web_search_room_parser.dart';
import 'package:pure_live/player/core/playback_header_resolver.dart';
import 'package:pure_live/recorder/services/ffmpeg_header_factory.dart';
import 'package:pure_live/recorder/services/stream_resolver_service.dart';

String fixture(String name) => File('test/fixtures/twitcasting/$name').readAsStringSync();
Map<String, dynamic> jsonFixture(String name) => jsonDecode(fixture(name)) as Map<String, dynamic>;
Matcher failure(TwitcastingFailure kind) => throwsA(isA<TwitcastingException>().having((e) => e.kind, 'kind', kind));
TwitcastingApi apiFor({String? page, Map<String, dynamic>? stream, List<Uri>? calls}) => TwitcastingApi(
  request: (uri, _) async {
    calls?.add(uri);
    return (
      status: 200,
      body: uri.path == '/streamserver.php'
          ? jsonEncode(stream ?? jsonFixture('live-stream.json'))
          : (page ?? fixture('room.html')),
    );
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('registered adapter exposes recording and fresh recovery without claiming remote chat or native search', () {
    expect(Sites.of(' TWITCASTING ').liveSite, isA<TwitcastingSite>());
    expect(Sites.of('twitcasting').liveSite, isA<LiveSiteRecordRoomResolver>());
    expect(Sites.of('twitcasting').liveSite, isA<LiveSiteRoomRefresher>());
    expect(Sites.of('twitcasting').liveSite, isA<LivePlayRecoveryResolver>());
    expect(Sites.supportSites.where((s) => s.id == 'twitcasting'), hasLength(1));
    expect(LiveSearchCapabilities.forPlatform('twitcasting').supportsNativeSearch, false);
    expect(LiveSearchCapabilities.forPlatform('twitcasting').supportsWebSearch, true);
    expect(MultiviewDanmakuSession.isSupportedPlatform('twitcasting'), false);
    expect(LiveRoom.audienceCapabilityFor('twitcasting').onlineAvailableInRoomLists, true);
    expect(LiveRoom.audienceCapabilityFor('twitcasting').hasTotalViewers, false);
  });
  test('playback and recorder share exact public headers without importing other platform cookies', () async {
    final playback = await PlaybackHeaderResolver.resolve(platform: 'twitcasting', roomId: 'fixture_artist');
    expect(await FFmpegHeaderFactory.build(platform: 'twitcasting'), playback);
    expect(playback.values, contains('https://twitcasting.tv/'));
    expect(playback.keys.map((k) => k.toLowerCase()), isNot(contains('cookie')));
  });
  test('channel links include observed social prefixes but do not relabel a VOD as current live', () async {
    for (final name in ['fixture_artist', 'c:fixture', 'g:113775126361409198504']) {
      final url = 'https://twitcasting.tv/$name';
      expect(WebSearchRoomParser.parse(url)?.roomId, name);
      expect(await LiveUrlTool.parseLiveUrl(url), [name, 'twitcasting']);
    }
    expect(
      TwitcastingApi.channelFromUri(Uri.parse('http://www.twitcasting.tv/Fixture_Artist/?ref=x')),
      'fixture_artist',
    );
    for (final value in [
      'https://evil.twitcasting.tv/artist',
      'https://twitcasting.tv.evil.test/artist',
      'https://user@twitcasting.tv/artist',
      'https://twitcasting.tv:123/artist',
      'ftp://twitcasting.tv/artist',
      'https://twitcasting.tv/search',
      'https://twitcasting.tv/artist/archive/',
      'https://twitcasting.tv/artist/movie/42',
      'https://twitcasting.tv/artist%2Fother',
      'https://twitcasting.tv//artist',
      'https://twitcasting.tv/%GG',
    ]) {
      expect(TwitcastingApi.channelFromUri(Uri.parse(value)), isNull, reason: value);
    }
  });
  test('production Dio reads bounded UTF-8 and keeps status failures distinct', () async {
    final old = core.HttpClient.instance.dio;
    final adapter = _ResponseAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    core.HttpClient.instance.dio = dio;
    try {
      adapter.body = ResponseBody.fromString(fixture('directory.json'), 200);
      expect((await TwitcastingApi().directory()).single.roomId, 'fixture_artist');
      expect(adapter.request!.responseType, ResponseType.stream);
      expect(adapter.request!.headers['Referer'], 'https://twitcasting.tv/');
      adapter.body = ResponseBody.fromString('private', 403);
      await expectLater(TwitcastingApi().directory(), failure(TwitcastingFailure.access));
      adapter.body = ResponseBody.fromString('x' * (1024 * 1024 + 1), 200);
      await expectLater(TwitcastingApi().directory(), failure(TwitcastingFailure.schema));
      adapter.body = ResponseBody(Stream.value(Uint8List.fromList([255])), 200);
      await expectLater(TwitcastingApi().directory(), failure(TwitcastingFailure.schema));
    } finally {
      core.HttpClient.instance.dio = old;
      dio.close(force: true);
    }
  });
  test('public directory maps real online counts and canonical channel identity, not movie id', () async {
    final api = TwitcastingApi(
      request: (uri, _) async {
        expect(uri.host, 'frontendapi.twitcasting.tv');
        expect(uri.queryParameters, {'id': '', 'count': '60'});
        return (status: 200, body: fixture('directory.json'));
      },
    );
    final room = (await api.directory()).single;
    expect(room.roomId, 'fixture_artist');
    expect(room.userId, 'fixture_artist');
    expect(room.onlineViewers, '2260');
    expect(room.totalViewers, anyOf(isNull, isEmpty));
    expect(room.cover, 'https://images.twitcasting.tv/cover.jpg');
    expect(room.nick, 'Fixture Artist');
    expect(room.liveStatus, LiveStatus.live);
  });
  test('directory slices the actual top window and stops before a fabricated upstream page', () async {
    var requests = 0;
    final row = (jsonFixture('directory.json')['movies'] as List).single as Map;
    final rows = List.generate(
      60,
      (i) => {...row, 'id': '${i + 1}', 'user_id': 'artist$i', 'live_url': '/artist$i/movie/${i + 1}'},
    );
    final api = TwitcastingApi(
      request: (uri, _) async {
        requests++;
        return (status: 200, body: jsonEncode({'movies': rows}));
      },
    );
    expect((await api.directory(page: 2, pageSize: 30)).first.roomId, 'artist30');
    expect(await api.directory(page: 3, pageSize: 30), isEmpty);
    expect(requests, 1);
  });
  test('locked, group, deleted and offline directory entries do not become playable cards', () async {
    final row = (jsonFixture('directory.json')['movies'] as List).single as Map;
    final api = TwitcastingApi(
      request: (_, _) async => (
        status: 200,
        body: jsonEncode({
          'movies': [
            row,
            row,
            {...row, 'is_locked': true},
            {...row, 'is_group': true, 'current_viewer_count': null},
            {...row, 'is_deleted': true},
            {...row, 'is_live': false},
          ],
        }),
      ),
    );
    expect(await api.directory(), hasLength(1));
  });
  for (final field in [
    'is_live',
    'is_locked',
    'is_group',
    'is_deleted',
    'current_viewer_count',
    'live_url',
    'id',
    'user_id',
  ]) {
    test('directory schema drift in $field is not an empty successful listing', () async {
      final row = Map<String, dynamic>.from((jsonFixture('directory.json')['movies'] as List).single as Map)
        ..remove(field);
      final api = TwitcastingApi(
        request: (_, _) async => (
          status: 200,
          body: jsonEncode({
            'movies': [row],
          }),
        ),
      );
      await expectLater(api.directory(), failure(TwitcastingFailure.schema));
    });
  }
  test('invalid pages and category identifiers perform zero requests', () async {
    var requests = 0;
    final api = TwitcastingApi(
      request: (_, _) async {
        requests++;
        return (status: 200, body: '{}');
      },
    );
    for (final args in [(0, 30), (10001, 30), (1, 0), (1, 61)]) {
      await expectLater(api.directory(page: args.$1, pageSize: args.$2), failure(TwitcastingFailure.schema));
    }
    await expectLater(api.directory(category: '../private'), failure(TwitcastingFailure.schema));
    expect(requests, 0);
  });
  test('categories preserve actual website keys and labels, not an invented taxonomy', () async {
    final api = TwitcastingApi(request: (_, _) async => (status: 200, body: fixture('categories.html')));
    final site = TwitcastingSite(api: api);
    final group = (await site.getCategores(1, 30)).single;
    expect(group.children.map((c) => c.areaId), ['_system_channel_popular', '_system_games_only']);
    expect(group.children.first.areaName, 'Popular Lives');
    expect(await site.getCategores(2, 30), isEmpty);
    expect(
      () => site.getCategoryRooms(LiveArea(platform: 'other', areaType: 'directory', areaId: 'x')),
      failure(TwitcastingFailure.schema),
    );
  });
  test('HTTP status classification never invents an offline room', () async {
    for (final pair in [
      (401, TwitcastingFailure.access),
      (403, TwitcastingFailure.access),
      (404, TwitcastingFailure.notFound),
      (429, TwitcastingFailure.rateLimited),
      (503, TwitcastingFailure.service),
      (302, TwitcastingFailure.transport),
    ]) {
      final api = TwitcastingApi(request: (_, _) async => (status: pair.$1, body: 'credential=do-not-expose'));
      await expectLater(api.detail('fixture_artist'), failure(pair.$2));
      expect(TwitcastingException(pair.$2).toString(), isNot(contains('do-not-expose')));
    }
  });
  test('cancellation before request and after response suppresses parsed results', () async {
    var calls = 0;
    final token = CancelToken()..cancel();
    final api = TwitcastingApi(
      request: (_, _) async {
        calls++;
        return (status: 200, body: fixture('directory.json'));
      },
    );
    await expectLater(api.directory(cancel: token), failure(TwitcastingFailure.cancelled));
    expect(calls, 0);
    final later = CancelToken();
    final lateApi = TwitcastingApi(
      request: (_, _) async {
        later.cancel();
        return (status: 200, body: fixture('directory.json'));
      },
    );
    await expectLater(lateApi.directory(cancel: later), failure(TwitcastingFailure.cancelled));
  });
  test('live detail consumes matched page and movie, preserving all three declared HLS tiers', () async {
    final calls = <Uri>[];
    final site = TwitcastingSite(api: apiFor(calls: calls));
    final room = await site.getRoomDetail(roomId: 'fixture_artist', platform: 'twitcasting');
    expect(calls.map((u) => u.path), ['/fixture_artist', '/streamserver.php']);
    expect(calls.last.queryParameters['target'], 'fixture_artist');
    expect(room.title, 'Drawing & music');
    final qualities = await site.getPlayQualites(detail: room);
    expect(qualities.map((q) => q.selectionId), ['high', 'medium', 'low']);
    expect((await site.getPlayUrls(detail: room, quality: qualities[1])).single, contains('/671.96/'));
    expect(() => (room.data as List).clear(), throwsUnsupportedError);
  });
  test('observed offline payload ignores stale HLS URLs belonging to a different movie', () async {
    final site = TwitcastingSite(api: apiFor(stream: jsonFixture('offline-stream.json')));
    final room = await site.getRoomDetailForRefresh(roomId: 'fixture_artist', platform: 'twitcasting');
    expect(room.isExplicitlyOfflineNow, true);
    expect(await site.getPlayQualites(detail: room), isEmpty);
  });
  test('mismatched creator or user header stops before the stream request', () async {
    for (final page in [
      fixture('room.html').replaceFirst('content="fixture_artist"', 'content="other"'),
      fixture('room.html').replaceFirst('data-user-id="fixture_artist"', 'data-user-id="other"'),
    ]) {
      final calls = <Uri>[];
      await expectLater(apiFor(page: page, calls: calls).detail('fixture_artist'), failure(TwitcastingFailure.schema));
      expect(calls, hasLength(1));
    }
  });
  test('password-gated room is access-restricted rather than offline', () async {
    final calls = <Uri>[];
    await expectLater(
      apiFor(page: 'Enter the secret word to access', calls: calls).detail('fixture_artist'),
      failure(TwitcastingFailure.access),
    );
    expect(calls, hasLength(1));
  });
  test('missing live flag or empty HLS is an unknown/schema failure', () async {
    for (final stream in [
      <String, dynamic>{},
      {
        'movie': {'id': 42, 'live': null},
      },
      {
        'movie': {'id': 42, 'live': true},
        'tc-hls': {'streams': {}},
      },
    ]) {
      await expectLater(apiFor(stream: stream).detail('fixture_artist'), failure(TwitcastingFailure.schema));
    }
  });
  for (final url in [
    'https://edge.twitcasting.tv/tc.livehls/v1/streams/999/hls/672.96/media.m3u8',
    'https://evil.test/tc.livehls/v1/streams/42/hls/672.96/media.m3u8',
    'http://edge.twitcasting.tv/tc.livehls/v1/streams/42/hls/672.96/media.m3u8',
    'https://user@edge.twitcasting.tv/tc.livehls/v1/streams/42/hls/672.96/media.m3u8',
    'https://edge.twitcasting.tv/tc.livehls/v1/streams/42/hls/../media.m3u8',
  ]) {
    test('invalid or cross-movie HLS is rejected: $url', () async {
      final stream = jsonFixture('live-stream.json');
      stream['tc-hls'] = {
        'streams': {'high': url},
      };
      await expectLater(apiFor(stream: stream).detail('fixture_artist'), failure(TwitcastingFailure.schema));
    });
  }
  test('recovery reacquires the new movie without silently downgrading the requested quality', () async {
    var stream = jsonFixture('live-stream.json');
    final calls = <Uri>[];
    final site = TwitcastingSite(
      api: TwitcastingApi(
        request: (uri, _) async {
          calls.add(uri);
          return (status: 200, body: uri.path == '/streamserver.php' ? jsonEncode(stream) : fixture('room.html'));
        },
      ),
    );
    final room = await site.getRoomDetail(roomId: 'fixture_artist', platform: 'twitcasting');
    final q = (await site.getPlayQualites(detail: room)).first;
    stream = jsonDecode(
      jsonEncode(stream).replaceAll('42', '43').replaceAll('edge.twitcasting.tv', 'new.twitcasting.tv'),
    ) as Map<String, dynamic>;
    final renewed = await site.resolvePlayUrlsForRecovery(detail: room, quality: q);
    expect(renewed.urls.single, contains('/streams/43/'));
    expect(renewed.appliedQualityData, 'high');
    expect(calls, hasLength(4));
    (stream['tc-hls']['streams'] as Map).remove('high');
    await expectLater(
      site.resolvePlayUrlsForRecovery(detail: room, quality: q),
      failure(TwitcastingFailure.qualityUnavailable),
    );
    expect((await site.getPlayUrls(detail: room, quality: q)).single, contains('/streams/42/'));
  });
  test('strict recorder resolves HLS and does not turn invalid metadata into offline', () async {
    final site = TwitcastingSite(api: apiFor());
    final result = await StreamResolverService(siteResolver: (_) => site)
        .resolveStream(roomId: 'fixture_artist', platform: 'twitcasting', preferredQuality: 'best');
    expect(result.url, contains('/672.96/'));
    final broken = TwitcastingSite(api: TwitcastingApi(request: (_, _) async => (status: 200, body: '{}')));
    await expectLater(
      StreamResolverService(siteResolver: (_) => broken)
          .resolveStream(roomId: 'fixture_artist', platform: 'twitcasting', preferredQuality: 'best'),
      throwsA(
        isA<StreamException>()
            .having((e) => e.type, 'type', StreamErrorType.networkError)
            .having((e) => e.retryable, 'retryable', true),
      ),
    );
  });
  test('quality resolution rejects a foreign room and missing requested tier', () async {
    final site = TwitcastingSite(api: apiFor());
    await expectLater(
      site.getPlayQualites(detail: LiveRoom(platform: 'other', status: false)),
      failure(TwitcastingFailure.schema),
    );
    final room = await site.getRoomDetail(roomId: 'fixture_artist', platform: 'twitcasting');
    await expectLater(
      site.getPlayUrls(
        detail: room,
        quality: LivePlayQuality(id: 'ultra', quality: 'ultra', data: []),
      ),
      failure(TwitcastingFailure.qualityUnavailable),
    );
  });
}

class _ResponseAdapter implements HttpClientAdapter {
  late ResponseBody body;
  RequestOptions? request;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return body;
  }

  @override
  void close({bool force = false}) {}
}
