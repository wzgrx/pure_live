// YouTube parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json, written by
// fixtures/youtube/legacy_expected.dart from 3.x's YouTubeApi, YouTubeSite
// and YouTubeLink). Every intended difference is listed with its reason;
// everything else must match. The archived samples (S01–S05, InnerTube
// requests 3.x never sent) have no expected values; S04's ANDROID player
// answers are read here as the recovery reads them. The synthetic cases pin
// 3.x's rules the samples do not reach.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('youtube', name);

/// Asserts that [actual] (a `toJson`) equals 3.x's [legacy] map on every key
/// 3.x wrote, except [changed] (intended differences). 3.x wrote null where
/// the immutable model writes ''.
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

/// 3.x's room projection: toJson plus `link`.
Map<String, Object?> _projection(LiveRoom room) => {...room.toJson(), 'link': room.link};

Map<String, dynamic> _legacy(String name) => _sample(name).legacy as Map<String, dynamic>;

/// The `result` of a traced legacy call.
Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

const _live = 'nI725iVsyoQ';
const _lofi = 'UCSJ4gkVC6NrvII8umztf0Ow';

const _mediaHeaders = {
  'origin': 'https://www.youtube.com',
  'referer': 'https://www.youtube.com/watch?v=$_live',
  'user-agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
};

/// The room of [watch] and [player] (samples) for [videoId].
YouTubeVideo _video(String watch, String player, String videoId) => YouTubeApi.video(
  page: YouTubeApi.watchPage(_sample(watch).body),
  player: YouTubeApi.player(_sample(player).body),
  videoId: videoId,
);

/// S07's sources as room entry builds them: the master's variants, the
/// progressive formats and the DASH manifest.
List<YouTubeStream> _liveStreams() {
  final video = _video('S07-watch-live', 'S07-player-live', _live);
  final sources = YouTubeApi.sources(video);
  return YouTubeApi.streams(
    hls: YouTubeApi.hlsVariants(sources.hls!, _sample('S07-hls-live').body),
    formats: sources.formats,
    dash: sources.dash,
  );
}

Map<String, dynamic> _playerBody() => jsonDecode(_sample('S07-player-live').body) as Map<String, dynamic>;

YouTubeVideo _synthetic(Map<String, dynamic> player, {String videoId = _live}) =>
    YouTubeApi.video(page: YouTubeWatchPage.empty, player: player, videoId: videoId);

Map<String, dynamic> _with(Map<String, dynamic> body, {Map<String, Object?>? details, Map<String, Object?>? status}) =>
    {
      ...body,
      if (details != null) 'videoDetails': {...(body['videoDetails'] as Map<String, dynamic>), ...details},
      'playabilityStatus': ?status,
    };

String _master(List<String> lines) => ['#EXTM3U', ...lines].join('\n');

final Uri _masterUrl = Uri.parse('https://manifest.googlevideo.com/api/manifest/hls_variant/expire/1790619788/x');

void main() {
  group('S07 live broadcast', () {
    final legacy = _legacy('S07-watch-live')[_live] as Map<String, dynamic>;

    test('the room matches 3.x at every depth: names, thumbnail, area, viewers, notice, headers', () {
      final room = _video('S07-watch-live', 'S07-player-live', _live).room;
      for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        _expectParity(_projection(room), _result(legacy[depth])! as Map<String, dynamic>, reason: depth);
      }
      expect(room.isLiveNow, isTrue);
      expect(room.userId, _lofi);
      expect(room.onlineViewers, '1256', reason: 'the live videoViewCountRenderer of the watch page');
      expect(room.effectiveAudienceMetricType, AudienceMetricType.onlineViewers);
      expect(room.avatar, room.cover, reason: '3.x shows the video thumbnail as the avatar too');
      expect(room.area, 'Music');
      expect(room.notice, YouTubeApi.chatNotice);
      expect(room.httpHeaders, _mediaHeaders);
      expect(room.data, isNull, reason: 'playback data is added by room entry');
    });

    test("the watch page gives 3.x's key and canonical link", () {
      final page = YouTubeApi.watchPage(_sample('S07-watch-live').body);
      expect(page.apiKey, YouTubeApi.fallbackApiKey, reason: 'the page key is the public web key');
      expect(page.canonical, 'https://www.youtube.com/watch?v=$_live');
      expect(page.player['videoDetails'], isA<Map<String, dynamic>>());
      expect(page.data['contents'], isA<Map<String, dynamic>>());
    });

    test("the sources match 3.x's: the master's six variants and the DASH manifest, best first", () {
      final expected = (legacy['streams'] as List).cast<Map<String, dynamic>>();
      final streams = _liveStreams();
      expect([
        for (final stream in streams)
          {
            'id': stream.id,
            'label': stream.label,
            'protocol': stream.protocol,
            'codec': stream.codec,
            'height': stream.height,
            'frameRate': stream.frameRate,
            'bitrate': stream.bitrate,
            'urls': [for (final url in stream.urls) '$url'],
          },
      ], expected);
      expect(streams.map((stream) => stream.id), [
        'hls:1080:0:h264',
        'hls:720:0:h264',
        'hls:480:0:h264',
        'hls:360:0:h264',
        'hls:240:0:h264',
        'hls:144:0:h264',
        'dash:auto',
      ]);
    });

    test("qualities: 3.x's labels, ids and order", () {
      final qualities = YouTubeApi.qualities(_liveStreams());
      expect([
        for (final quality in qualities)
          {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort, 'data': quality.data},
      ], _result(legacy['getPlayQualites']));
      expect(qualities.first.quality, '1080p · H264 · HLS');
      expect(qualities.last.quality, 'DASH 自动 · DASH');
    });

    test("every quality's lines: 3.x's URLs, applied quality and lease, with the media headers", () {
      final expected = legacy['resolvePlayUrlsRaw'] as Map<String, dynamic>;
      final streams = _liveStreams();
      expect(expected.keys, streams.map((stream) => stream.id));
      for (final stream in streams) {
        final want = _result(expected[stream.id])! as Map<String, dynamic>;
        final resolution = YouTubeApi.resolution(stream, videoId: _live);
        expect(resolution.urls, want['urls'], reason: stream.id);
        expect(resolution.appliedQualityData, want['appliedQualityData'], reason: stream.id);
        for (final (index, line) in resolution.lines.indexed) {
          expect(line.lease!.expiresAt!.toIso8601String(), (want['invalidAt'] as List)[index], reason: stream.id);
          expect(line.lease!.refreshAt.toIso8601String(), (want['refreshAt'] as List)[index], reason: stream.id);
          expect(line.lease!.cutsConnection, isFalse);
          expect(line.headers, _mediaHeaders, reason: "3.x's PlaybackHeaderResolver for YouTube");
          expect(line.lineId, 'manifest.googlevideo.com');
        }
        final line = resolution.lines.single;
        expect(line.format, stream.protocol == 'hls' ? StreamFormat.hls : isNull, reason: stream.id);
        expect(line.codec, stream.protocol == 'hls' ? 'avc' : isNull, reason: stream.id);
      }
    });

    test('the player answer alone (the recovery) is the same live room without viewers', () {
      final room = _synthetic(_playerBody()).room;
      expect(room.isLiveNow, isTrue);
      expect(room.title, '24/7 deep sleep music 🌌 calm ambient to sleep & dream to');
      expect(room.onlineViewers, isEmpty, reason: 'viewers come from the watch page');
      expect(room.area, 'YouTube Live', reason: 'the ANDROID answer has no microformat');
    });
  });

  group('S09/S10 broadcasts that are not live', () {
    for (final (watch, player, videoId, status) in [
      ('S09-watch-ended', 'S09-player-ended', '9njefMDxzqw', 'OK'),
      ('S10-watch-upcoming', 'S10-player-upcoming', '32myp8UqPOE', 'LIVE_STREAM_OFFLINE'),
    ]) {
      test('$watch: offline as in 3.x, every field matches', () {
        final legacy = _legacy(watch)[videoId] as Map<String, dynamic>;
        final video = _video(watch, player, videoId);
        for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
          _expectParity(_projection(video.room), _result(legacy[depth])! as Map<String, dynamic>, reason: depth);
        }
        expect(video.room.effectiveLiveStatus, LiveStatus.offline);
        expect(video.room.onlineViewers, isEmpty, reason: 'viewers only while live');
        expect(video.playability, status);
        expect(_result(legacy['getPlayQualites']), isEmpty, reason: '3.x offered nothing; now StreamUnavailable');
      });
    }
  });

  group('videos that are no live room', () {
    test('S11 an ordinary video is NotFound (3.x: notLive at every depth, no search result)', () {
      final legacy = _legacy('S11-watch-video')['dQw4w9WgXcQ'] as Map<String, dynamic>;
      expect(_result(legacy['getRoomDetail']), {'throws': 'YouTubeException', 'message': 'YouTube notLive'});
      expect(_result(_legacy('S11-watch-video')['searchRooms']), isEmpty);
      expect(() => _video('S11-watch-video', 'S11-player-video', 'dQw4w9WgXcQ'), throwsA(isA<NotFound>()));
    });

    test('S12 a missing video is NotFound (3.x: an identity error, which also broke its search)', () {
      final legacy = _legacy('S12-watch-missing');
      expect(_result((legacy['aaaaaaaaaaa'] as Map<String, dynamic>)['getRoomDetail']), {
        'throws': 'YouTubeException',
        'message': 'YouTube identity',
      });
      expect(_result(legacy['searchRooms']), {'throws': 'YouTubeException', 'message': 'YouTube identity'});
      expect(() => _video('S12-watch-missing', 'S12-player-missing', 'aaaaaaaaaaa'), throwsA(isA<NotFound>()));
      expect(YouTubeApi.watchPage(_sample('S12-watch-missing').body).canonical, 'undefined');
    });

    test('S04 (archived) the missing video of the InnerTube spec is NotFound too', () {
      expect(
        () => _synthetic(YouTubeApi.player(_sample('S04-player-missing').body), videoId: 'aaaaaaaaaaa'),
        throwsA(isA<NotFound>()),
      );
    });
  });

  group('channel pages', () {
    test("S07 a live channel's /live page names its broadcast (3.x: the canonical link)", () {
      final legacy = _legacy('S07-channel-live')['resolveReference'] as Map<String, dynamic>;
      for (final traced in legacy.values) {
        expect(_result(traced), _live);
      }
      expect(YouTubeApi.liveVideoOfPage(_sample('S07-channel-live').body), _live);
    });

    test("S08 an offline channel's /live page names none (3.x: notLive)", () {
      expect(_result(_legacy('S08-channel-offline')['resolveReference']), {
        'throws': 'YouTubeException',
        'message': 'YouTube notLive',
      });
      expect(YouTubeApi.liveVideoOfPage(_sample('S08-channel-offline').body), isNull);
    });

    test("3.x's order: a redirect to a video, the canonical link, a live player, a live renderer", () {
      final offline = _sample('S08-channel-offline').body;
      expect(YouTubeApi.liveVideoOfPage(offline, finalUrl: Uri.parse('https://www.youtube.com/watch?v=$_live')), _live);
      String page(Object data, {Object? player}) =>
          '<html><script>${player == null ? '' : 'var ytInitialPlayerResponse = ${jsonEncode(player)};'}'
          'var ytInitialData = ${jsonEncode(data)};</script></html>';
      expect(
        YouTubeApi.liveVideoOfPage(
          page(
            {},
            player: {
              'videoDetails': {'videoId': _live, 'isLive': true},
            },
          ),
        ),
        _live,
      );
      expect(
        YouTubeApi.liveVideoOfPage(
          page(
            {},
            player: {
              'videoDetails': {'videoId': _live, 'isLive': false},
            },
          ),
        ),
        isNull,
      );
      final renderers = {
        'items': [
          {'videoId': 'aaaaaaaaaaa', 'title': 'past'},
          {
            'videoId': 'bbbbbbbbbbb',
            'badges': [
              {
                'metadataBadgeRenderer': {'style': 'BADGE_STYLE_TYPE_LIVE_NOW'},
              },
            ],
          },
        ],
      };
      expect(YouTubeApi.liveVideoOfPage(page(renderers)), 'bbbbbbbbbbb');
      expect(
        YouTubeApi.liveVideoOfPage(
          page({
            'items': [
              {'videoId': 'ccccccccccc', 'isLiveNow': true},
            ],
          }),
        ),
        'ccccccccccc',
      );
    });
  });

  group('links', () {
    final legacy = _legacy('S07-channel-live');

    test("every link parses as 3.x's YouTubeLink.parse did", () {
      final expected = legacy['YouTubeLink.parse'] as Map<String, dynamic>;
      expect(expected, hasLength(greaterThan(30)));
      for (final MapEntry(:key, :value) in expected.entries) {
        final link = YouTubeLink.parse(key);
        expect(link == null ? null : {'kind': link.kind.name, 'id': link.id, 'url': link.url}, value, reason: key);
      }
      final durable = legacy['YouTubeLink.parseDurableVideoId'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in durable.entries) {
        final link = YouTubeLink.parse(key);
        expect(link?.kind == YouTubeLinkKind.video ? link!.id : null, value, reason: key);
      }
    });

    test("search keywords read as 3.x's parseOrReference did (a bare name is a handle)", () {
      final expected = legacy['YouTubeLink.parseOrReference'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in expected.entries) {
        final link = YouTubeLink.parseOrReference(key);
        expect(link == null ? null : {'kind': link.kind.name, 'id': link.id, 'url': link.url}, value, reason: key);
      }
    });

    test("the watch page URL, and 3.x's FormatException for a non-id", () {
      expect(YouTubeLink.videoUrl(' $_live '), 'https://www.youtube.com/watch?v=$_live');
      expect(() => YouTubeLink.videoUrl('short'), throwsFormatException);
      expect(
        YouTubeLink.parse('https://www.youtube.com/watch?v=%FF'),
        isNull,
        reason: 'undecodable escapes are no link (3.x threw)',
      );
    });

    test("lease times are 3.x's getPlayUrlInvalidAt / getPlayUrlRefreshAt", () {
      final expected = legacy['getPlayUrlInvalidAt'] as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in expected.entries) {
        final want = value as Map<String, dynamic>;
        expect(YouTubeApi.invalidAt(key)?.toIso8601String(), want['invalidAt'], reason: key);
        final uri = Uri.tryParse(key);
        final lease = uri == null ? null : YouTubeApi.lease(uri);
        expect(lease?.refreshAt.toIso8601String(), want['refreshAt'], reason: key);
      }
    });
  });

  group("3.x's states", () {
    final body = _playerBody();

    test('sign-in, age and content checks, private videos and their reasons are banned', () {
      for (final status in ['LOGIN_REQUIRED', 'AGE_CHECK_REQUIRED', 'CONTENT_CHECK_REQUIRED']) {
        expect(
          _synthetic(_with(body, status: {'status': status})).room.effectiveLiveStatus,
          LiveStatus.banned,
          reason: status,
        );
      }
      expect(_synthetic(_with(body, details: {'isPrivate': true})).room.effectiveLiveStatus, LiveStatus.banned);
      expect(
        _synthetic(_with(body, status: {'status': 'UNPLAYABLE', 'reason': 'Sign in to confirm your age'}))
            .room
            .effectiveLiveStatus,
        LiveStatus.banned,
      );
    });

    test('a live broadcast the client cannot play stays offline, as 3.x showed it', () {
      final video = _synthetic(_with(body, status: {'status': 'UNPLAYABLE', 'reason': 'Not available'}));
      expect(video.room.effectiveLiveStatus, LiveStatus.offline);
      expect(video.playability, 'UNPLAYABLE');
    });

    test('an ended broadcast is offline; without a status a broadcast is offline, anything else unknown', () {
      expect(_synthetic(_with(body, details: {'isLive': false})).room.effectiveLiveStatus, LiveStatus.offline);
      final noStatus = Map<String, dynamic>.of(body)..remove('playabilityStatus');
      expect(_synthetic(noStatus).room.effectiveLiveStatus, LiveStatus.offline, reason: 'live needs status OK');
      final plain = _with(noStatus, details: {'isLive': false, 'isLiveContent': false});
      expect(_synthetic(plain).room.effectiveLiveStatus, LiveStatus.unknown);
    });

    test('an ordinary video is NotFound; an answer for another video or without names is ApiChanged', () {
      expect(
        () => _synthetic(_with(body, details: {'isLive': false, 'isLiveContent': false})),
        throwsA(isA<NotFound>()),
      );
      expect(() => _synthetic(body, videoId: 'aaaaaaaaaaa'), throwsA(isA<ApiChanged>()));
      expect(() => _synthetic(_with(body, details: {'title': ''})), throwsA(isA<ApiChanged>()));
      expect(() => _synthetic(_with(body, details: {'author': null})), throwsA(isA<ApiChanged>()));
    });

    test('an answer naming no video: sign-in is NeedsLogin, unplayable StreamUnavailable, else ApiChanged', () {
      final bare = Map<String, dynamic>.of(body)..remove('videoDetails');
      expect(
        () => _synthetic({
          ...bare,
          'playabilityStatus': {'status': 'LOGIN_REQUIRED'},
        }),
        throwsA(isA<NeedsLogin>()),
      );
      expect(
        () => _synthetic({
          ...bare,
          'playabilityStatus': {'status': 'UNPLAYABLE'},
        }),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(
        () => _synthetic({
          ...bare,
          'playabilityStatus': {'status': 'OK'},
        }),
        throwsA(isA<ApiChanged>()),
      );
    });

    test('the page fills what the player answer lacks; the answer wins where both have a field', () {
      final page = YouTubeApi.watchPage(_sample('S07-watch-live').body);
      final video = YouTubeApi.video(
        page: page,
        player: _with(body, details: {'title': 'from the player'}),
        videoId: _live,
      );
      expect(video.room.title, 'from the player');
      expect(video.room.area, 'Music', reason: "the page's microformat category");
    });

    test('thumbnails: the last https one on ytimg.com or ggpht.com', () {
      Map<String, dynamic> thumbs(List<String> urls) => _with(
        body,
        details: {
          'thumbnail': {
            'thumbnails': [
              for (final url in urls) {'url': url},
            ],
          },
        },
      );
      expect(
        _synthetic(thumbs(['https://i.ytimg.com/a.jpg', 'http://i.ytimg.com/b.jpg'])).room.cover,
        'https://i.ytimg.com/a.jpg',
      );
      expect(
        _synthetic(thumbs(['https://yt3.ggpht.com/a.jpg', 'https://evilytimg.com/b.jpg'])).room.cover,
        'https://yt3.ggpht.com/a.jpg',
      );
      expect(_synthetic(thumbs([for (var i = 0; i < 65; i++) 'https://i.ytimg.com/$i.jpg'])).room.cover, isEmpty);
    });
  });

  group("3.x's sources", () {
    test('S04 (archived): the ANDROID answer offers the master and the DASH manifest, no progressive file', () {
      final video = _synthetic(YouTubeApi.player(_sample('S04-player-live').body));
      final sources = YouTubeApi.sources(video);
      expect(sources.hls!.path, endsWith('/file/index.m3u8'));
      expect(sources.dash, isNotNull);
      expect(sources.formats, isEmpty);
      final streams = YouTubeApi.streams(hls: [YouTubeApi.hlsAuto(sources.hls!)], dash: sources.dash);
      expect(YouTubeApi.qualities(streams).map((quality) => quality.quality), ['HLS 自动 · HLS', 'DASH 自动 · DASH']);
    });

    test('progressive formats with a plain URL become `http:<itag>`, ordered with the rest', () {
      final video = _synthetic(
        _with(_playerBody(), details: {})
          ..['streamingData'] = {
            'formats': [
              {
                'itag': 18,
                'url': 'https://rr1---sn-x.googlevideo.com/videoplayback?expire=1790619788',
                'qualityLabel': '360p',
                'mimeType': 'video/mp4; codecs="avc1.42001E, mp4a.40.2"',
                'height': 360,
                'fps': 30,
                'bitrate': 500000,
              },
              {'itag': 22, 'signatureCipher': 's=x&url=y', 'qualityLabel': '720p'},
            ],
          },
      );
      final sources = YouTubeApi.sources(video);
      expect(sources.formats.map((stream) => stream.id), ['http:18']);
      final streams = YouTubeApi.streams(formats: sources.formats);
      expect(YouTubeApi.qualities(streams).single.quality, '360p · H264 · HTTP');
      expect(YouTubeApi.qualitySort(streams.single), 360050);
      final line = YouTubeApi.resolution(streams.single, videoId: _live).lines.single;
      expect(line.format, StreamFormat.other);
      expect(line.lease!.expiresAt, DateTime.fromMillisecondsSinceEpoch(1790619788 * 1000, isUtc: true));
    });

    test('a media URL off the YouTube hosts is ApiChanged (3.x failed the room)', () {
      final video = _synthetic(
        Map<String, dynamic>.of(_playerBody())
          ..['streamingData'] = {'hlsManifestUrl': 'https://evil.example/index.m3u8'},
      );
      expect(() => YouTubeApi.sources(video), throwsA(isA<ApiChanged>()));
    });

    test('HLS variants: height and frame rate name them; 3.x rejected the whole master otherwise', () {
      const url = 'https://manifest.googlevideo.com/api/manifest/hls_playlist/itag/';
      final variants = YouTubeApi.hlsVariants(
        _masterUrl,
        _master([
          '#EXT-X-STREAM-INF:BANDWIDTH=9000000,CODECS="av01.0.08M.08,mp4a.40.2",RESOLUTION=1920x1080,FRAME-RATE=60',
          '${url}1/index.m3u8',
          '#EXT-X-STREAM-INF:BANDWIDTH=4000000,CODECS="vp09.00.40.08,mp4a.40.2",RESOLUTION=1280x720,FRAME-RATE=59.94',
          '${url}2/index.m3u8',
          '#EXT-X-STREAM-INF:BANDWIDTH=100000,CODECS="mp4a.40.2"',
          '${url}3/index.m3u8',
        ]),
      );
      expect(variants.map((stream) => (stream.id, stream.label)), [
        ('hls:1080:60:av1', '1080p60'),
        ('hls:720:60:vp9', '720p60'),
        ('hls:0:0:auto', 'HLS Auto'),
      ]);
      final streams = YouTubeApi.streams(hls: variants);
      expect(YouTubeApi.qualities(streams).map((quality) => quality.quality), [
        '1080p60 · AV1 · HLS',
        '720p60 · VP9 · HLS',
        'HLS Auto · HLS',
      ]);
      for (final text in [
        '#EXT-X-STREAM-INF:BANDWIDTH=1\n${url}1/index.m3u8',
        _master([]),
        _master([
          '#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1x2',
          '${url}1/a',
          '#EXT-X-STREAM-INF:BANDWIDTH=2,RESOLUTION=1x2',
          '${url}2/a',
        ]),
        _master(['#EXT-X-STREAM-INF:BANDWIDTH=1', 'https://evil.example/a.m3u8']),
        _master(['#EXT-X-STREAM-INF:BANDWIDTH=1,BANDWIDTH=2', '${url}1/a']),
        _master(['#EXT-X-STREAM-INF:BANDWIDTH=1']),
        _master([
          for (var i = 0; i < 65; i++) ...['#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1x${i + 1}', '$url$i/a'],
        ]),
      ]) {
        expect(() => YouTubeApi.hlsVariants(_masterUrl, text), throwsFormatException, reason: text);
      }
    });

    test('the lease is 10 minutes before expire and never cuts the connection', () {
      final lease = YouTubeApi.lease(
        Uri.parse('https://manifest.googlevideo.com/api/manifest/hls_playlist/expire/100/x'),
      )!;
      expect(lease.expiresAt, DateTime.utc(1970, 1, 1, 0, 1, 40));
      expect(lease.refreshAt, DateTime.utc(1969, 12, 31, 23, 51, 40));
      expect(lease.cutsConnection, isFalse);
      expect(YouTubeApi.lease(Uri.parse('https://manifest.googlevideo.com/api/manifest/hls_playlist/x')), isNull);
    });
  });

  group('requests and statuses', () {
    test("3.x's player request: the ANDROID client with the page's key", () {
      final recorded = _sample('S07-player-live');
      expect(YouTubeApi.playerUrl(YouTubeApi.fallbackApiKey), recorded.url);
      expect(
        YouTubeApi.playerBody(_live),
        jsonDecode(((recorded.meta['request'] as Map<String, dynamic>)['body']) as String),
      );
      expect(YouTubeApi.pageHeaders(''), containsPair('referer', 'https://www.youtube.com/'));
      expect(YouTubeApi.pageHeaders(_live), containsPair('cookie', 'SOCS=CAI'));
      expect(YouTubeApi.playerHeaders(_live), containsPair('accept', 'application/json'));
    });

    test("3.x's status rules", () {
      expect(() => YouTubeApi.checkStatus(200, '', 'x'), throwsA(isA<ApiChanged>()));
      expect(() => YouTubeApi.checkStatus(400, 'x', 'x'), throwsA(isA<ApiChanged>()));
      expect(() => YouTubeApi.checkStatus(403, 'x', 'x'), throwsA(isA<RiskControl>()));
      expect(() => YouTubeApi.checkStatus(404, 'x', 'x'), throwsA(isA<NotFound>()));
      expect(() => YouTubeApi.checkStatus(429, 'x', 'x'), throwsA(isA<RateLimited>()));
      expect(() => YouTubeApi.checkStatus(503, 'x', 'x'), throwsA(isA<NetworkFailure>()));
      expect(() => YouTubeApi.checkStatus(302, 'x', 'x'), throwsA(isA<NetworkFailure>()));
      expect(() => YouTubeApi.player('<html>'), throwsA(isA<ApiChanged>()));
      expect(() => YouTubeApi.player('[]'), throwsA(isA<ApiChanged>()));
    });

    test('a page without the embedded objects is not an error: the player answer decides', () {
      final page = YouTubeApi.watchPage('<html></html>');
      expect(page.player, isEmpty);
      expect(page.data, isEmpty);
      expect(page.apiKey, YouTubeApi.fallbackApiKey);
      final video = YouTubeApi.video(page: page, player: _playerBody(), videoId: _live);
      expect(video.room.isLiveNow, isTrue);
    });

    test('an embedded object that does not decode is skipped for the next marker', () {
      final page = YouTubeApi.watchPage(
        'ytInitialPlayerResponse = {broken}; var ytInitialPlayerResponse = {"videoDetails":{"videoId":"$_live"}};',
      );
      expect((page.player['videoDetails'] as Map)['videoId'], _live);
    });
  });
}
