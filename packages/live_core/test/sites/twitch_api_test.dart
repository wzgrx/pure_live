// Twitch parsing against the recorded samples, compared field by field with
// 3.x's output (expected.json). 3.x has no replay test for Twitch, so its
// output was written by fixtures/twitch/legacy_expected.py, a transcription of
// 3.x's parser kept apart from this adapter. Every intended difference is
// listed with its reason; everything else must match.
//
// S05-user-* answer the raw `user` query 3.x never sent (it asked for the
// ChannelShell + StreamMetadata pair); their tests check 3.x's field rules
// (twitch_site.dart:708-754) instead. S03-streams is not used: 3.x
// recommended from the Just Chatting directory, not the site-wide list.
import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('twitch', name);

Object _decode(Fixture fixture) =>
    TwitchApi.decode(fixture.body, status: fixture.status, what: '${fixture.meta['sample']}');

/// Asserts that [actual] equals 3.x's [legacy] map on every key 3.x wrote,
/// except [changed] (intended differences). 3.x wrote null where the
/// immutable model writes ''.
void _expectParity(
  Map<String, Object?> actual,
  Map<String, dynamic> legacy, {
  Set<String> changed = const {},
  String? reason,
}) {
  for (final MapEntry(:key, :value) in legacy.entries) {
    if (changed.contains(key)) continue;
    expect(actual[key] ?? '', value ?? '', reason: '${reason ?? ''} $key');
  }
}

/// A card as 3.x's roomProjection wrote it: `toJson` plus the danmaku data's
/// text.
Map<String, Object?> _card(LiveRoom room) => {...room.toJson(), 'danmakuData': room.danmakuData?.toString()};

/// The tag of [id] as S01-tags names it.
TwitchTag _tag(String id) => TwitchApi.tags(_decode(_sample('S01-tags'))).firstWhere((tag) => tag.id == id);

Map<String, dynamic> _json(String body) => jsonDecode(body) as Map<String, dynamic>;

void main() {
  group('S01 categories', () {
    test('S01-tags: every tag, ids and names as 3.x (tagName), the nameless one included', () {
      final fixture = _sample('S01-tags');
      final tags = TwitchApi.tags(_decode(fixture));
      final legacy = (fixture.legacy as List).cast<Map<String, dynamic>>();
      expect(tags.map((tag) => tag.id), legacy.map((tag) => tag['id']));
      expect(tags.map((tag) => tag.name), legacy.map((tag) => tag['name']));
      expect(tags.where((tag) => tag.name.isEmpty), hasLength(1), reason: 'zh-CN has one tag without a name');
    });

    test('localizedName stands in only for an empty tagName', () {
      final tags = TwitchApi.tags({
        'data': {
          'searchCategoryTags': [
            {'id': 'a', 'tagName': 'Shooter', 'localizedName': '射击游戏'},
            {'id': 'b', 'tagName': '', 'localizedName': '策略'},
            {'tagName': 'no id'},
          ],
        },
      });
      expect(tags, [(id: 'a', name: 'Shooter'), (id: 'b', name: '策略')]);
    });

    for (final name in ['S01-dirs-1', 'S01-dirs-2']) {
      test("$name: each tag page gives 3.x's areas and next cursor", () {
        final fixture = _sample(name);
        final operations = (jsonDecode((fixture.meta['request'] as Map)['body'] as String) as List)
            .cast<Map<String, dynamic>>();
        final envelopes = TwitchApi.batch(_decode(fixture), expected: operations.length, what: name);
        final legacy = (fixture.legacy as Map).cast<String, dynamic>();
        var compared = 0;
        for (final (index, operation) in operations.indexed) {
          final wanted = ((operation['variables'] as Map)['options'] as Map)['tags'] as List;
          // The archived v4 asked for a "top" list first; 3.x never did.
          if (wanted.isEmpty) continue;
          final tagId = wanted.single as String;
          final page = TwitchApi.directories(envelopes[index], _tag(tagId));
          final expected = legacy[tagId] as Map<String, dynamic>;
          final areas = (expected['areas'] as List).cast<Map<String, dynamic>>();
          expect(page.areas, hasLength(areas.length), reason: tagId);
          for (final (position, area) in page.areas.indexed) {
            _expectParity(area.toJson(), areas[position], reason: '$tagId[$position]');
          }
          expect(page.cursor ?? '', expected['nextCursor'], reason: tagId);
          compared++;
        }
        expect(compared, greaterThan(0));
      });
    }

    test('an envelope with errors and no data is a page without areas (3.x swallowed it)', () {
      final page = TwitchApi.directories(
        {
          'errors': [
            {'message': 'service error'},
          ],
          'data': null,
        },
        (id: 't', name: 'T'),
      );
      expect(page.areas, isEmpty);
      expect(page.cursor, isNull);
    });

    test('an unknown persisted query is ApiChanged', () {
      expect(
        () => TwitchApi.directories(
          {
            'errors': [
              {'message': 'PersistedQueryNotFound'},
            ],
          },
          (id: 't', name: 'T'),
        ),
        throwsA(isA<ApiChanged>()),
      );
    });
  });

  group('S02 directory streams', () {
    test('S02-game: the same cards in the same order as 3.x, with its next cursor', () {
      final fixture = _sample('S02-game');
      final result = TwitchApi.gameStreams(_decode(fixture), now: fixture.capturedAt);
      final legacy = (fixture.legacy as Map)['rooms'] as List;
      expect(result.rooms.map((room) => room.roomId), legacy.map((room) => (room as Map)['roomId']));
      for (final (index, room) in result.rooms.indexed) {
        // danmakuData: 3.x wrote the numeric channel id, but its IRC
        // connection joins `#<text>`, so a card's own data joined no channel;
        // the arguments name the login now.
        _expectParity(_card(room), legacy[index] as Map<String, dynamic>, changed: {'danmakuData'}, reason: '[$index]');
        expect((room.danmakuData! as TwitchDanmakuArgs).channel, room.roomId);
      }
      expect(result.cursor, (fixture.legacy as Map)['nextCursor']);
      expect(result.rooms.first.cover, endsWith('?&t=${fixture.capturedAt.millisecondsSinceEpoch ~/ 1000}'));
      expect(result.rooms.first.cover, startsWith('https://i2.wp.com/static-cdn.jtvnw.net/'));
    });

    test('S02-game-missing: an unknown directory has no streams, as in 3.x', () {
      final fixture = _sample('S02-game-missing');
      expect((fixture.legacy as Map)['rooms'], isEmpty);
      final result = TwitchApi.gameStreams(_decode(fixture), now: fixture.capturedAt);
      expect(result.rooms, isEmpty);
      expect(result.cursor, isNull);
    });

    test('S02-game-cursor: the integrity challenge is RiskControl (3.x threw a StateError)', () {
      final fixture = _sample('S02-game-cursor');
      final thrown = ((fixture.legacy as Map)['throws'] as Map)['message'] as String;
      expect(thrown, contains('failed integrity check'));
      expect(() => _decode(fixture), throwsA(isA<RiskControl>()));
    });

    test('a missing pageInfo keeps the edges and ends the list (REG-TWITCH-008)', () {
      Map<String, Object?> page(Object? streams) => {
        'data': {
          'game': {'streams': streams},
        },
      };
      final edge = {
        'cursor': 'c1',
        'node': {
          'title': 't',
          'viewersCount': 5,
          'broadcaster': {'login': 'zarbex', 'displayName': 'Zarbex'},
        },
      };
      final open = TwitchApi.gameStreams(
        page({
          'edges': [null, 'invalid', edge],
        }),
        now: DateTime.utc(2026),
      );
      expect(open.rooms.single.roomId, 'zarbex');
      expect(open.cursor, isNull);
      final more = TwitchApi.gameStreams(
        page({
          'edges': [edge],
          'pageInfo': {'hasNextPage': true},
        }),
        now: DateTime.utc(2026),
      );
      expect(more.cursor, 'c1');
      expect(TwitchApi.gameStreams(page(null), now: DateTime.utc(2026)).rooms, isEmpty);
    });

    test('a card without a preview has no cover (3.x: appendTxt on an empty string)', () {
      final result = TwitchApi.gameStreams({
        'data': {
          'game': {
            'streams': {
              'edges': [
                {
                  'node': {
                    'broadcaster': {'login': 'x'},
                  },
                },
                {
                  'node': {'broadcaster': null},
                },
              ],
            },
          },
        },
      }, now: DateTime.utc(2026));
      expect(result.rooms.single.cover, isEmpty);
      expect(result.rooms.single.nick, 'x', reason: 'the login stands in for a missing display name');
      expect(result.rooms.single.watching, '0');
    });
  });

  group('S04 search', () {
    for (final name in ['S04-search-p1', 'S04-search-p2', 'S04-search-empty']) {
      test('$name: the same cards as 3.x, live and offline, with the channel cursor', () {
        final fixture = _sample(name);
        final result = TwitchApi.searchPage(_decode(fixture), now: fixture.capturedAt);
        final legacy = fixture.legacy as Map<String, dynamic>;
        final rooms = (legacy['rooms'] as List).cast<Map<String, dynamic>>();
        expect(result.rooms, hasLength(rooms.length));
        for (final (index, room) in result.rooms.indexed) {
          _expectParity(_card(room), rooms[index], reason: '$name[$index]');
        }
        expect(result.cursor ?? '', legacy['cursor']);
      });
    }

    test('offline channels: no cover, "0" viewers, offline', () {
      final fixture = _sample('S04-search-p1');
      final offline = TwitchApi.searchPage(
        _decode(fixture),
        now: fixture.capturedAt,
      ).rooms.firstWhere((room) => room.roomId == 'minecraft');
      expect(offline.isExplicitlyOfflineNow, isTrue);
      expect(offline.cover, isEmpty);
      expect(offline.onlineViewers, '0');
    });

    test('a channel without settings or picture is kept, one without a login skipped (3.x failed the page)', () {
      final result = TwitchApi.searchPage({
        'data': {
          'searchFor': {
            'channels': {
              'cursor': 'MTA=',
              'edges': [
                {
                  'item': {'login': 'a', 'displayName': 'A'},
                },
                {
                  'item': {'displayName': 'no login'},
                },
                'invalid',
              ],
            },
          },
        },
      }, now: DateTime.utc(2026));
      expect(result.rooms.single.roomId, 'a');
      expect(result.rooms.single.title, isEmpty);
      expect(result.rooms.single.avatar, isEmpty);
      expect(result.cursor, 'MTA=');
    });
  });

  group("S05 detail (3.x's field rules; 3.x never sent this query)", () {
    test("live: one query gives 3.x's fields and the real viewer count (REG-TWITCH-003)", () {
      final fixture = _sample('S05-user-live');
      final raw = (_json(fixture.body)['data'] as Map)['user'] as Map;
      final room = TwitchApi.roomDetail(_decode(fixture), requestedId: 'zarbex');
      expect(room.roomId, 'zarbex');
      expect(room.userId, 'zarbex');
      expect(room.link, 'https://www.twitch.tv/zarbex');
      expect(room.title, (raw['lastBroadcast'] as Map)['title'], reason: 'site:733');
      expect(room.nick, 'zarbex');
      expect(room.avatar, raw['profileImageURL']);
      expect(room.cover, raw['profileImageURL'], reason: '3.x used the profile image as cover (site:737)');
      expect(room.isLiveNow, isTrue);
      expect(room.watching, '23169');
      expect(room.onlineViewers, '23169');
      expect(room.effectiveAudienceMetricType, AudienceMetricType.onlineViewers);
      expect(room.area, 'IRL', reason: 'the game name first (site:743)');
      expect(room.introduction, isEmpty);
      expect(room.notice, isEmpty);
      expect(room.danmakuData.toString(), 'zarbex');
    });

    test('offline: the last broadcast\'s title, "0" viewers, no area', () {
      final room = TwitchApi.roomDetail(_decode(_sample('S05-user-offline')), requestedId: 'minecraft');
      expect(room.isExplicitlyOfflineNow, isTrue);
      expect(room.title, 'Minecraft LIVE - September 2026');
      expect(room.nick, 'Minecraft');
      expect(room.watching, '0');
      expect(room.onlineViewers, '0');
      expect(room.area, isNull);
    });

    test('the room keeps the id as asked; the danmaku channel is the login', () {
      final room = TwitchApi.roomDetail(
        _decode(_sample('S05-user-live')),
        requestedId: ' Zarbex ',
        chat: (login: 'me', token: 'secret'),
      );
      expect(room.roomId, 'Zarbex');
      expect(room.link, 'https://www.twitch.tv/Zarbex');
      final args = room.danmakuData! as TwitchDanmakuArgs;
      expect(args.channel, 'zarbex');
      expect(args.chat, (login: 'me', token: 'secret'));
      expect(args.toString(), isNot(contains('secret')));
    });

    test('a stream that is not `live` (a rerun) is offline, as in 3.x', () {
      final body = _sample('S05-user-live').body.replaceFirst('"type": "live"', '"type": "rerun"');
      final room = TwitchApi.roomDetail(TwitchApi.decode(body, status: 200, what: 'user'), requestedId: 'zarbex');
      expect(room.isExplicitlyOfflineNow, isTrue);
      expect(room.watching, '0');
      expect(room.area, 'IRL', reason: '3.x read the area from any stream');
    });

    test('an unknown channel is NotFound (3.x: StateError); another login is ApiChanged', () {
      expect(
        () => TwitchApi.roomDetail(_decode(_sample('S05-user-missing')), requestedId: 'zzzznotachannelzzzz'),
        throwsA(isA<NotFound>()),
      );
      expect(
        () => TwitchApi.roomDetail(_decode(_sample('S05-user-live')), requestedId: 'someone_else'),
        throwsA(isA<ApiChanged>()),
      );
    });
  });

  group('S06 streams', () {
    for (final name in ['S06-pat-live', 'S06-pat-offline']) {
      test('$name: token and signature as 3.x read them', () {
        final fixture = _sample(name);
        final login = ((_json((fixture.meta['request'] as Map)['body'] as String)['variables']) as Map)['login'];
        final token = TwitchApi.accessToken(_decode(fixture), login: login as String);
        expect(token.value, (fixture.legacy as Map)['token']);
        expect(token.signature, (fixture.legacy as Map)['sig']);
      });
    }

    test('S06-pat-missing: NotFound (3.x: NoSuchMethodError)', () {
      final fixture = _sample('S06-pat-missing');
      expect(((fixture.legacy as Map)['throws'] as Map)['type'], 'NoSuchMethodError');
      expect(() => TwitchApi.accessToken(_decode(fixture), login: 'zzzznotachannelzzzz'), throwsA(isA<NotFound>()));
    });

    test('a forbidden token: a geo reason is RegionBlocked, others NeedsLogin', () {
      Map<String, Object?> token(String reason) => {
        'data': {
          'streamPlaybackAccessToken': {
            'value': jsonEncode({
              'authorization': {'forbidden': true, 'reason': reason},
            }),
            'signature': 's',
          },
        },
      };
      expect(() => TwitchApi.accessToken(token('GEOBLOCKED'), login: 'x'), throwsA(isA<RegionBlocked>()));
      expect(() => TwitchApi.accessToken(token('UNAUTHORIZED_ENTITLEMENTS'), login: 'x'), throwsA(isA<NeedsLogin>()));
    });

    test('S06-usher-live: qualities, ids, order and URLs as 3.x', () {
      final fixture = _sample('S06-usher-live');
      final qualities = TwitchApi.qualities(fixture.body, master: fixture.url);
      expect([
        for (final quality in qualities)
          {'quality': quality.quality, 'id': quality.id, 'data': quality.data, 'sort': quality.sort},
      ], fixture.legacy);
      expect(qualities.first.quality, '1080P50（原画）');
    });

    test('S06-usher-offline: StreamUnavailable (3.x: HttpError 404); 403, 429 and 5xx typed', () {
      final fixture = _sample('S06-usher-offline');
      expect(((fixture.legacy as Map)['throws'] as Map)['statusCode'], 404);
      expect(() => TwitchApi.usherStatus(fixture.status, fixture.body), throwsA(isA<StreamUnavailable>()));
      expect(
        () => TwitchApi.usherStatus(403, '[{"error":"Content is geoblocked","error_code":"content_geoblocked"}]'),
        throwsA(isA<RegionBlocked>()),
      );
      expect(
        () => TwitchApi.usherStatus(403, '[{"error_code":"unauthorized_entitlements"}]'),
        throwsA(isA<NeedsLogin>()),
      );
      expect(() => TwitchApi.usherStatus(429, ''), throwsA(isA<RateLimited>()));
      expect(() => TwitchApi.usherStatus(503, ''), throwsA(isA<NetworkFailure>()));
      expect(() => TwitchApi.usherStatus(400, 'x'), throwsA(isA<ApiChanged>()));
      TwitchApi.usherStatus(200, '#EXTM3U');
    });

    // 3.x test/twitch_playback_parser_test.dart.
    test('each variant URI goes with its own attributes (REG-TWITCH-004)', () {
      const playlist = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=8200000,RESOLUTION=1920x1080,FRAME-RATE=60.000,VIDEO="chunked",CODECS="avc1.64002A,mp4a.40.2"
https://cdn.test/source/index.m3u8?token=a
#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720,FRAME-RATE=30.000,VIDEO="720p30"
720/index.m3u8
# unrelated metadata must not shift the BANDWIDTH/URL pairing
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio"
#EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=640x360,FRAME-RATE=30.000,VIDEO="360p30"
360/index.m3u8
''';
      final qualities = TwitchApi.qualities(
        playlist,
        master: Uri.parse('https://usher.ttvnw.net/api/channel/hls/demo.m3u8'),
      );
      expect(qualities.map((quality) => quality.quality), ['1080P60（原画）', '720P', '360P']);
      expect(qualities.first.sort, greaterThan(qualities[1].sort));
      expect(qualities.skip(1).map((quality) => quality.sort), [3000000, 900000]);
      expect(qualities[1].data, ['https://usher.ttvnw.net/api/channel/hls/720/index.m3u8']);
      expect(qualities.map((quality) => quality.selectionId).toSet(), hasLength(3));
    });

    test('the source (`chunked`) stays first even with a lower bandwidth (REG-TWITCH-005)', () {
      const playlist = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1800000,VIDEO="chunked"
source/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720,VIDEO="720p30"
720/index.m3u8
''';
      final qualities = TwitchApi.qualities(
        playlist,
        master: Uri.parse('https://usher.ttvnw.net/api/channel/hls/demo.m3u8'),
      );
      expect(qualities.map((quality) => quality.quality), ['原画', '720P']);
      expect(qualities.first.data, ['https://usher.ttvnw.net/api/channel/hls/source/index.m3u8']);
    });

    test('a variant listed twice keeps one quality with both URLs; bandwidth labels without resolution', () {
      const playlist = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=6000000,VIDEO="a"
https://a.test/1.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=6000000,VIDEO="a"
https://b.test/1.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=300000,VIDEO="b"
ftp://c.test/1.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=400000,VIDEO="c"
https://c.test/1.m3u8
''';
      final qualities = TwitchApi.qualities(playlist, master: Uri.parse('https://usher.ttvnw.net/x.m3u8'));
      expect(qualities.map((quality) => quality.quality), ['1080P', '自动']);
      expect(qualities.first.data, ['https://a.test/1.m3u8', 'https://b.test/1.m3u8']);
    });

    test('no variant is StreamUnavailable; not a playlist is ApiChanged', () {
      final master = Uri.parse('https://usher.ttvnw.net/x.m3u8');
      expect(() => TwitchApi.qualities('#EXTM3U\n', master: master), throwsA(isA<StreamUnavailable>()));
      expect(() => TwitchApi.qualities('<html>', master: master), throwsA(isA<ApiChanged>()));
    });

    test("lines: 3.x's media headers, HLS, the playlist host as line; no lease", () {
      final resolution = TwitchApi.resolution(
        ['https://use22.playlist.ttvnw.net/v1/playlist/a.m3u8', ' '],
        roomId: 'Zarbex',
        appliedQualityData: 'q',
        cookie: ' auth-token=x ',
      );
      final line = resolution.lines.single;
      expect(line.headers, {
        'user-agent': TwitchApi.userAgent,
        'origin': 'https://www.twitch.tv',
        'referer': 'https://www.twitch.tv/Zarbex',
        'cookie': 'auth-token=x',
      });
      expect(line.format, StreamFormat.hls);
      expect(line.lineId, 'use22.playlist.ttvnw.net');
      expect(line.lease, isNull);
      expect(resolution.appliedQualityData, 'q');
      expect(TwitchApi.mediaHeaders('').keys, isNot(contains('cookie')));
      expect(TwitchApi.mediaHeaders('')['referer'], 'https://www.twitch.tv/');
    });

    test('the same quality in a new playlist: by id, then VIDEO group, then label', () {
      final fresh = TwitchApi.qualities(
        _sample('S06-usher-live').body,
        master: Uri.parse('https://usher.ttvnw.net/api/channel/hls/zarbex.m3u8'),
      );
      expect(TwitchApi.sameQuality(fresh, fresh[2]), same(fresh[2]));
      expect(
        TwitchApi.sameQuality(fresh, const LivePlayQuality(quality: 'x', id: '1080:50:1:chunked'))?.id,
        '1080:50:9123163:chunked',
      );
      expect(TwitchApi.sameQuality(fresh, const LivePlayQuality(quality: '480P'))?.id, '480:30:1427999:480p30');
      expect(TwitchApi.sameQuality(fresh, const LivePlayQuality(quality: 'none', id: 'x')), isNull);
    });

    test("the usher URL carries 3.x's parameters with the token and signature", () {
      final url = TwitchApi.usherUrl('zarbex', (value: '{"a":1}', signature: 'sig'), Random(1));
      expect(url.host, 'usher.ttvnw.net');
      expect(url.path, '/api/channel/hls/zarbex.m3u8');
      expect(url.queryParameters.keys.toSet(), {
        'acmb',
        'allow_source',
        'cdm',
        'fast_bread',
        'p',
        'platform',
        'play_session_id',
        'player_backend',
        'player_version',
        'playlist_include_framerate',
        'reassignments_supported',
        'sig',
        'token',
        'transcode_mode',
      });
      expect(url.queryParameters['token'], '{"a":1}');
      expect(url.queryParameters['sig'], 'sig');
      expect(TwitchApi.playSessionIds, contains(url.queryParameters['play_session_id']));
    });
  });

  group('GraphQL', () {
    test('statuses: 401 NeedsLogin, 429 RateLimited, 5xx NetworkFailure, others and non-JSON ApiChanged', () {
      expect(() => TwitchApi.decode('{}', status: 401, what: 'x'), throwsA(isA<NeedsLogin>()));
      expect(() => TwitchApi.decode('{}', status: 429, what: 'x'), throwsA(isA<RateLimited>()));
      expect(() => TwitchApi.decode('', status: 502, what: 'x'), throwsA(isA<NetworkFailure>()));
      expect(() => TwitchApi.decode('{}', status: 400, what: 'x'), throwsA(isA<ApiChanged>()));
      expect(() => TwitchApi.decode('<html>', status: 200, what: 'x'), throwsA(isA<ApiChanged>()));
      expect(() => TwitchApi.decode('"text"', status: 200, what: 'x'), throwsA(isA<ApiChanged>()));
      expect(TwitchApi.decode('[]', status: 200, what: 'x'), isEmpty);
    });

    // 3.x test/twitch_directory_parser_test.dart (hasIntegrityError).
    test('integrity challenges in object and batched envelopes are RiskControl; other errors are not', () {
      expect(
        TwitchApi.isIntegrityRejection({
          'errors': [
            {'message': 'failed integrity check'},
          ],
        }),
        isTrue,
      );
      expect(
        TwitchApi.isIntegrityRejection([
          {
            'data': null,
            'errors': [
              {'message': 'Integrity token expired'},
            ],
          },
        ]),
        isTrue,
      );
      expect(
        TwitchApi.isIntegrityRejection([
          {
            'data': {'game': null},
            'errors': [
              {'message': 'unknown game'},
            ],
          },
        ]),
        isFalse,
      );
      expect(
        TwitchApi.isIntegrityRejection({
          'extensions': {
            'challenge': {'type': 'integrity'},
          },
        }),
        isTrue,
      );
      expect(
        () => TwitchApi.decode('{"errors":[{"message":"failed integrity check"}]}', status: 200, what: 'x'),
        throwsA(isA<RiskControl>()),
      );
    });

    test('an envelope without data is ApiChanged; partial errors with data are fine', () {
      expect(
        () => TwitchApi.accessToken({
          'errors': [
            {'message': 'boom'},
          ],
        }, login: 'x'),
        throwsA(isA<ApiChanged>().having((error) => error.detail, 'detail', contains('boom'))),
      );
      final tags = TwitchApi.tags({
        'errors': [
          {'message': 'service error'},
        ],
        'data': {
          'searchCategoryTags': [
            {'id': 'a', 'tagName': 'A'},
          ],
        },
      });
      expect(tags, hasLength(1));
    });

    test('a batch must answer every operation', () {
      expect(TwitchApi.batch([1, 2], expected: 2, what: 'x'), [1, 2]);
      expect(() => TwitchApi.batch([1], expected: 2, what: 'x'), throwsA(isA<ApiChanged>()));
    });

    test("headers: 3.x's identity; a session adds Cookie and OAuth", () {
      final anonymous = TwitchApi.gqlHeaders(deviceId: 'd');
      expect(anonymous, {
        'user-agent': TwitchApi.userAgent,
        'accept-language': 'en-US,en;q=0.9',
        'accept': 'application/vnd.twitchtv.v5+json',
        'client-id': 'kimne78kx3ncx6brgo4mv6wki5h1ko',
        'origin': 'https://www.twitch.tv',
        'referer': 'https://www.twitch.tv/',
        'device-id': 'd',
        'content-type': 'text/plain;charset=UTF-8',
      });
      final signedIn = TwitchApi.gqlHeaders(deviceId: 'd', cookie: 'persistent=1; auth-token=abc==');
      expect(signedIn['cookie'], 'persistent=1; auth-token=abc==');
      expect(signedIn['authorization'], 'OAuth abc==');
      expect(TwitchApi.gqlHeaders(deviceId: 'd', cookie: 'persistent=1').keys, isNot(contains('authorization')));
      expect(TwitchApi.usherHeaders(deviceId: 'd').keys, isNot(anyOf(contains('cookie'), contains('authorization'))));
    });

    // 3.x test/twitch_directory_parser_test.dart (extractAuthToken, generateDeviceId).
    test('the auth token keeps its equals signs; empty is none; the device id is 32 hex digits', () {
      expect(TwitchApi.authToken('persistent=123; auth-token=abc==; unique_id=value'), 'abc==');
      expect(TwitchApi.authToken('persistent=123'), isNull);
      expect(TwitchApi.authToken('auth-token=; persistent=123'), isNull);
      final id = TwitchApi.deviceId(Random(7));
      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(TwitchApi.deviceId(Random(7)), id);
    });

    test('the chat login needs both login and auth-token (3.x joinRoom)', () {
      expect(TwitchApi.chatLogin('auth-token=t; login=Me'), (login: 'me', token: 't'));
      expect(TwitchApi.chatLogin('auth-token=t'), isNull);
      expect(TwitchApi.chatLogin('login=me'), isNull);
      expect(const TwitchDanmakuArgs(channel: 'zarbex').toString(), 'zarbex');
    });
  });
}
