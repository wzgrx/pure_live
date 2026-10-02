// YouTube parsing against the recorded samples, compared field by field with
// 3.x's frozen output (expected.json, written by
// fixtures/youtube/legacy_expected.dart from 3.x's YouTubeApi, YouTubeSite
// and YouTubeLink). Every intended difference is listed with its reason
// (the M4.U upgrade row, docs/specs/UPGRADES.md); everything else must match. The
// archived samples (S01–S05, InnerTube requests 3.x never sent) and the
// M4.U.23 ones (S03-resolve-*-live/-upcoming/-custom/-missing, S13) have no
// expected values; they are read as the adapter reads them now. The
// synthetic cases pin the rules the samples do not reach.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('youtube', name);

/// Asserts that [actual] (a `toJson`) equals 3.x's [legacy] map on every key
/// 3.x wrote, except [changed] (intended differences, by upgrade row). 3.x
/// wrote null where the immutable model writes ''.
void _expectParity(
  Map<String, Object?> actual,
  Map<String, dynamic> legacy, {
  Map<String, String> changed = const {},
  String? reason,
}) {
  for (final MapEntry(:key, :value) in legacy.entries) {
    if (changed.containsKey(key)) {
      expect(actual[key] ?? '', isNot(value ?? ''), reason: '${reason ?? ''} $key changed: ${changed[key]}');
      continue;
    }
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
const _lofiAvatar =
    'https://yt3.ggpht.com/GyVPysrx-cVIWIQDfi2MkaYr7oRIxuOgGeZihnw-hgTv6E5LBQ67v5yXTFvqP2Bl7BB_S-0L-A=s176-c-k-c0x00ffffff-no-rj';

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

/// A page embedding [data] as `ytInitialData` (and [player] as
/// `ytInitialPlayerResponse`).
String _page(Object data, {Object? player}) =>
    '<html><script>${player == null ? '' : 'var ytInitialPlayerResponse = ${jsonEncode(player)};'}'
    'var ytInitialData = ${jsonEncode(data)};</script></html>';

/// A video row of a browse or search answer.
Map<String, Object?> _row(
  String videoId, {
  String? channel = _lofi,
  String title = 'a title',
  String owner = 'Lofi Girl',
  String viewers = '12 watching',
  List<String> badges = const ['BADGE_STYLE_TYPE_LIVE_NOW'],
}) => {
  'videoRenderer': {
    'videoId': videoId,
    'title': {
      'runs': [
        {'text': title},
      ],
    },
    'ownerText': {
      'runs': [
        {
          'text': owner,
          if (channel != null)
            'navigationEndpoint': {
              'browseEndpoint': {'browseId': channel},
            },
        },
      ],
    },
    'viewCountText': {
      'runs': [
        {'text': viewers},
      ],
    },
    'badges': [
      for (final style in badges)
        {
          'metadataBadgeRenderer': {'style': style},
        },
    ],
  },
};

void main() {
  group('S07 live broadcast: the channel is the room (23-1)', () {
    final legacy = _legacy('S07-watch-live')[_live] as Map<String, dynamic>;

    test("the room matches 3.x's at every depth but for its id and avatar", () {
      final video = _video('S07-watch-live', 'S07-player-live', _live);
      final room = video.room;
      for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
        _expectParity(
          _projection(room),
          _result(legacy[depth])! as Map<String, dynamic>,
          changed: const {
            'roomId': '23-1 the channel id',
            'avatar': "23-4 the channel's avatar",
            'notice': 'M5.19 live chat is shown, so the notice drops "chat pending"',
          },
          reason: depth,
        );
      }
      expect(room.roomId, _lofi);
      expect(room.userId, _lofi);
      expect((video.videoId, video.channelId), (_live, _lofi));
      expect(room.link, 'https://www.youtube.com/watch?v=$_live', reason: 'the broadcast while live (3.x too)');
      expect(room.isLiveNow, isTrue);
      expect(room.onlineViewers, '1256', reason: 'the live videoViewCountRenderer of the watch page');
      expect(room.effectiveAudienceMetricType, AudienceMetricType.onlineViewers);
      expect(room.avatar, _lofiAvatar, reason: "23-4: videoOwnerRenderer's largest image (3.x: the thumbnail)");
      expect(room.cover, 'https://i.ytimg.com/vi/$_live/sddefault.jpg?v=6ab3f71c');
      expect(room.area, 'Music');
      expect(room.notice, YouTubeApi.chatNotice);
      expect(room.httpHeaders, _mediaHeaders);
      expect(room.data, isNull, reason: 'playback data is added by room entry');
    });

    test('M2.1 fields: the start of the broadcast, no restriction; the chat arguments (23-3)', () {
      final room = _video('S07-watch-live', 'S07-player-live', _live).room;
      expect(room.startedAt, DateTime.utc(2026, 9, 23, 16, 47, 51), reason: 'liveBroadcastDetails.startTimestamp');
      expect(room.restriction, LiveRestriction.none);
      expect(room.danmakuData, const YouTubeDanmakuArgs(roomId: _lofi, videoId: _live));
      expect(_projection(room), containsPair('startedAt', '2026-09-23T16:47:51.000Z'));
      expect(_projection(room), containsPair('restriction', 'none'));
    });

    test("the watch page gives 3.x's key and canonical link", () {
      final page = YouTubeApi.watchPage(_sample('S07-watch-live').body);
      expect(page.apiKey, YouTubeApi.fallbackApiKey, reason: 'the page key is the public web key');
      expect(page.canonical, 'https://www.youtube.com/watch?v=$_live');
      expect(page.player['videoDetails'], isA<Map<String, dynamic>>());
      expect(page.data['contents'], isA<Map<String, dynamic>>());
      expect(identical(page.forVideo(_live), page), isTrue);
      final other = page.forVideo('aaaaaaaaaaa');
      expect(other.player, isEmpty);
      expect(other.data, isEmpty);
      expect(other.apiKey, page.apiKey);
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

    test("qualities: 3.x's labels, ids and order (no rename row, so nothing to migrate)", () {
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

    test('the player answer alone (the refresh, the recovery) has no viewers, avatar, area or start (23-6)', () {
      final room = _synthetic(_playerBody()).room;
      expect(room.isLiveNow, isTrue);
      expect(room.roomId, _lofi);
      expect(room.title, '24/7 deep sleep music 🌌 calm ambient to sleep & dream to');
      expect(room.onlineViewers, isEmpty, reason: 'updated_metadata gives them (23-6)');
      expect(room.avatar, isEmpty, reason: 'the follow keeps its stored avatar');
      expect(room.area, isNull, reason: "3.x wrote 'YouTube Live', which would overwrite a stored category");
      expect(room.startedAt, isNull);
      expect(room.restriction, LiveRestriction.none);
    });
  });

  group('S09/S10 broadcasts that are not live: the channel is offline', () {
    for (final (watch, player, videoId, channel, status) in [
      ('S09-watch-ended', 'S09-player-ended', '9njefMDxzqw', 'UC1sELGmy5jp5fQUugmuYlXQ', 'OK'),
      ('S10-watch-upcoming', 'S10-player-upcoming', '32myp8UqPOE', 'UCvxWyn4rfcI2H9APhfUIB1Q', 'LIVE_STREAM_OFFLINE'),
    ]) {
      test("$watch: offline as in 3.x; the id, link and avatar are the channel's", () {
        final legacy = _legacy(watch)[videoId] as Map<String, dynamic>;
        final video = _video(watch, player, videoId);
        for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
          _expectParity(
            _projection(video.room),
            _result(legacy[depth])! as Map<String, dynamic>,
            changed: const {
              'roomId': '23-1 the channel id',
              'link': "23-1 the channel's /live page while it is not live",
              'avatar': "23-4 the channel's avatar",
              'notice': 'M5.19 live chat is shown, so the notice drops "chat pending"',
            },
            reason: depth,
          );
        }
        expect(video.room.roomId, channel);
        expect(video.room.link, 'https://www.youtube.com/channel/$channel/live');
        expect(video.room.effectiveLiveStatus, LiveStatus.offline);
        expect(video.room.onlineViewers, isEmpty, reason: 'viewers only while live');
        expect(video.room.startedAt, isNull, reason: 'the page has a start (or schedule), but nothing is on');
        expect(video.room.restriction, isNull);
        expect(video.room.danmakuData, isNull);
        expect(video.playability, status);
        expect(_result(legacy['getPlayQualites']), isEmpty, reason: '3.x offered nothing; now StreamUnavailable');
      });
    }
  });

  group('videos that are no broadcast', () {
    test('S11 an ordinary video is its channel, offline (3.x: notLive, 23-1)', () {
      final legacy = _legacy('S11-watch-video')['dQw4w9WgXcQ'] as Map<String, dynamic>;
      expect(_result(legacy['getRoomDetail']), {'throws': 'YouTubeException', 'message': 'YouTube notLive'});
      final room = _video('S11-watch-video', 'S11-player-video', 'dQw4w9WgXcQ').room;
      expect((room.roomId, room.effectiveLiveStatus), ('UCuAXFkgsw1L7xaCfnd5JJOw', LiveStatus.offline));
      expect(room.nick, 'Rick Astley');
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
      final live = YouTubeApi.channelLive(_sample('S07-channel-live').body);
      expect(live.videoId, _live);
      expect(YouTubeApi.channel(live.page), isNull, reason: 'a watch page names no channel metadata');
      final room = YouTubeApi.video(page: live.page.forVideo(_live), player: _playerBody(), videoId: _live).room;
      expect((room.roomId, room.avatar, room.onlineViewers), (_lofi, _lofiAvatar, '1257'));
    });

    test("S08 an offline channel's /live page names none (3.x: notLive) but the channel (23-1)", () {
      expect(_result(_legacy('S08-channel-offline')['resolveReference']), {
        'throws': 'YouTubeException',
        'message': 'YouTube notLive',
      });
      expect(YouTubeApi.liveVideoOfPage(_sample('S08-channel-offline').body), isNull);
      final channel = YouTubeApi.channel(YouTubeApi.watchPage(_sample('S08-channel-offline').body))!;
      expect((channel.channelId, channel.name), ('UCX6OQ3DkcsbYNE6H8uQQuVA', 'MrBeast'));
      expect(channel.avatar, startsWith('https://yt3.googleusercontent.com/'), reason: 'avatars may live there');
      expect(channel.description, startsWith('SUBSCRIBE FOR A COOKIE!'));
      final room = YouTubeApi.offlineRoom(channel);
      expect(room.roomId, 'UCX6OQ3DkcsbYNE6H8uQQuVA');
      expect((room.nick, room.title), ('MrBeast', ''), reason: '23-1: an offline channel shows its name');
      expect(room.avatar, channel.avatar);
      expect(room.introduction, channel.description);
      expect(room.link, 'https://www.youtube.com/channel/UCX6OQ3DkcsbYNE6H8uQQuVA/live');
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect((room.startedAt, room.restriction), (null, null));
    });

    test("YouTube's page for an unknown channel names no channel", () {
      final page = YouTubeApi.watchPage(
        _page({
          'alerts': [
            {
              'alertRenderer': {
                'type': 'ERROR',
                'text': {'simpleText': 'This channel does not exist.'},
              },
            },
          ],
        }),
      );
      expect(YouTubeApi.channel(page), isNull);
      expect(
        YouTubeApi.channel(
          YouTubeApi.watchPage(
            _page({
              'metadata': {
                'channelMetadataRenderer': {'externalId': 'UCshort', 'title': 'x'},
              },
            }),
          ),
        ),
        isNull,
      );
    });

    test("3.x's order: a redirect to a video, the canonical link, a live player, a live renderer", () {
      final offline = _sample('S08-channel-offline').body;
      expect(YouTubeApi.liveVideoOfPage(offline, finalUrl: Uri.parse('https://www.youtube.com/watch?v=$_live')), _live);
      expect(
        YouTubeApi.liveVideoOfPage(
          _page(
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
          _page(
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
      expect(YouTubeApi.liveVideoOfPage(_page(renderers)), 'bbbbbbbbbbb');
      expect(
        YouTubeApi.liveVideoOfPage(
          _page({
            'items': [
              {'videoId': 'ccccccccccc', 'isLiveNow': true},
            ],
          }),
        ),
        'ccccccccccc',
      );
    });
  });

  group('navigation/resolve_url, the feed and updated_metadata (23-1, 23-6)', () {
    test('a live channel names its broadcast, an offline one itself, a handle its channel', () {
      expect(YouTubeApi.resolved(_sample('S03-resolve-channel-live').body), (videoId: _live, channelId: null));
      expect(YouTubeApi.resolved(_sample('S03-resolve-handle-live').body), (videoId: _live, channelId: null));
      expect(YouTubeApi.resolved(_sample('S03-resolve-channel-offline').body), (
        videoId: null,
        channelId: 'UCX6OQ3DkcsbYNE6H8uQQuVA',
      ));
      expect(YouTubeApi.resolved(_sample('S03-resolve-handle').body), (videoId: null, channelId: _lofi));
      expect(YouTubeApi.resolved(_sample('S03-resolve-custom').body), (videoId: null, channelId: _lofi));
      expect(YouTubeApi.resolved(_sample('S03-resolve-channel-upcoming').body), (
        videoId: '32myp8UqPOE',
        channelId: null,
      ), reason: "a channel with only a scheduled broadcast names it (S10's upcoming video)");
    });

    test('an unknown handle is 404 (NotFound); an answer naming neither is NotFound too', () {
      final missing = _sample('S03-resolve-handle-missing');
      expect(missing.status, 404);
      expect(() => YouTubeApi.resolved(missing.body, status: missing.status), throwsA(isA<NotFound>()));
      expect(
        () => YouTubeApi.resolved(
          jsonEncode({
            'endpoint': {
              'urlEndpoint': {'url': 'https://example.com'},
            },
          }),
        ),
        throwsA(isA<NotFound>()),
      );
      expect(() => YouTubeApi.resolved('<html>'), throwsA(isA<ApiChanged>()));
    });

    test("S05 the feed's own title is the channel's name; 404 is NotFound", () {
      expect(YouTubeApi.feedName(_sample('S05-feed-offline').body), 'MrBeast');
      expect(
        YouTubeApi.feedName('<feed><title>Tom &amp; Jerry</title><entry><title>video</title></entry></feed>'),
        'Tom & Jerry',
      );
      expect(() => YouTubeApi.feedName('<feed><entry><title>v</title></entry></feed>'), throwsA(isA<ApiChanged>()));
      expect(() => YouTubeApi.feedName('x', status: 404), throwsA(isA<NotFound>()));
    });

    test('S13 updated_metadata gives the live viewer count (23-6)', () {
      expect(YouTubeApi.viewers(_sample('S13-metadata-live').body), 1331);
      expect(YouTubeApi.viewers('{"actions":[]}'), isNull);
      expect(() => YouTubeApi.viewers('x', status: 429), throwsA(isA<RateLimited>()));
    });

    test('the web client requests: endpoint, context and bodies (the archived samples replay)', () {
      expect(YouTubeApi.apiUrl('browse'), _sample('S01-browse-live').url);
      for (final (name, body) in [
        ('S01-browse-live', YouTubeApi.browseBody()),
        ('S02-search-p1', YouTubeApi.searchBody('lofi')),
        ('S03-resolve-channel-live', YouTubeApi.resolveBody(YouTubeApi.liveUrl(_lofi))),
        ('S03-resolve-handle', YouTubeApi.resolveBody('https://www.youtube.com/@LofiGirl')),
        ('S13-metadata-live', YouTubeApi.metadataBody(_live)),
      ]) {
        final recorded = (_sample(name).meta['request'] as Map<String, dynamic>)['body'] as String;
        expect(body, jsonDecode(recorded), reason: name);
      }
      expect(YouTubeApi.apiHeaders, containsPair('cookie', 'SOCS=CAI'));
      expect(YouTubeApi.apiHeaders, containsPair('referer', 'https://www.youtube.com/'));
      expect(YouTubeApi.feedUrl('UCX6OQ3DkcsbYNE6H8uQQuVA'), _sample('S05-feed-offline').url);
    });
  });

  group('listings (23-2)', () {
    test('S01 the "Live" destination: its live rows, one card per channel', () {
      final listing = YouTubeApi.listing(_sample('S01-browse-live').body, search: false);
      expect(listing.liveRows, 28, reason: '49 rows: 12 ended, 9 upcoming, 28 live');
      expect(listing.rooms, hasLength(26), reason: 'LiveNOW from FOX and a row listed twice are one card each');
      expect(listing.next, isNull, reason: 'the destination has one page');
      expect(listing.rooms.map((room) => room.roomId).toSet(), hasLength(listing.rooms.length));
      final first = listing.rooms.first;
      expect(first.roomId, 'UC4u6RxRxwNv4vWiW0_rkdEw');
      expect(listing.videoIds.first, 'NUgUOMY2sm8');
      expect(first.link, 'https://www.youtube.com/watch?v=NUgUOMY2sm8');
      expect((first.nick, first.onlineViewers, first.effectiveLiveStatus), ('FlowVoyager', '10862', LiveStatus.live));
      expect(first.title, startsWith('👺 Custom Celebrity Mask'));
      expect(first.avatar, startsWith('https://yt3.ggpht.com/'), reason: "23-4: the channel's avatar");
      expect(first.cover, startsWith('https://i.ytimg.com/vi/NUgUOMY2sm8/'));
      expect(first.restriction, isNull, reason: 'a card cannot tell age or region checks');
      expect(first.httpHeaders['referer'], 'https://www.youtube.com/watch?v=NUgUOMY2sm8');
      final fox = listing.rooms.where((room) => room.roomId == 'UCJg9wBPyKMNA5sRDnvzmkdg').toList();
      expect(fox.single.link, 'https://www.youtube.com/watch?v=jRDug_owloQ', reason: 'the first of its two rows');
      expect(listing.videoIds, isNot(contains('9njefMDxzqw')), reason: 'ended');
      expect(listing.videoIds, isNot(contains('gwjEUsW6eIU')), reason: 'upcoming');
    });

    test('S02 a live search page: cards, and the continuation the next page was asked with', () {
      final first = YouTubeApi.listing(_sample('S02-search-p1').body, search: true);
      expect((first.liveRows, first.rooms.length), (20, 11), reason: 'Lofi Girl 8 rows, two channels 2 each');
      final request = jsonDecode((_sample('S02-search-p2').meta['request'] as Map<String, dynamic>)['body'] as String);
      expect(first.next, (request as Map<String, dynamic>)['continuation']);
      expect(first.rooms.first.roomId, _lofi);
      expect(first.videoIds.first, 'rFZHOHl-L8A', reason: "Lofi Girl's first row; its seven others are left out");
      final second = YouTubeApi.listing(_sample('S02-search-p2').body, search: true);
      expect(second.liveRows, 18);
      expect(second.next, isNotNull);
      expect(second.rooms.map((room) => room.roomId), contains(_lofi), reason: "cross-page is the adapter's");
    });

    test('a malformed live row is skipped; all malformed is ApiChanged; ended and upcoming rows are no cards', () {
      String answer(List<Object?> rows) => jsonEncode({
        'contents': rows,
        'continuationItemRenderer': {
          'continuationEndpoint': {
            'continuationCommand': {'token': 'NEXT'},
          },
        },
      });
      final listing = YouTubeApi.listing(
        answer([
          _row('aaaaaaaaaa1', channel: null),
          _row('aaaaaaaaaa2', title: ''),
          _row('aaaaaaaaaa3', owner: ''),
          _row('bad'),
          _row('aaaaaaaaaa4', channel: 'UCshort'),
          _row('aaaaaaaaaa5', badges: const [], viewers: '3 waiting'),
          _row('aaaaaaaaaa6', badges: const [], viewers: '1,234 views'),
          _row('aaaaaaaaaa7', badges: const [], viewers: '1,234 watching'),
          _row('aaaaaaaaaa8', badges: const ['BADGE_STYLE_TYPE_LIVE_NOW', 'BADGE_STYLE_TYPE_MEMBERS_ONLY']),
        ]),
        search: true,
      );
      expect(listing.videoIds, ['aaaaaaaaaa7']);
      expect(listing.rooms.single.onlineViewers, '1234');
      expect(listing.liveRows, 7);
      expect(listing.next, 'NEXT');
      final members = YouTubeApi.listing(
        answer([
          _row('aaaaaaaaaa8', badges: const ['BADGE_STYLE_TYPE_LIVE_NOW', 'BADGE_STYLE_TYPE_MEMBERS_ONLY']),
        ]),
        search: true,
      );
      expect(members.rooms.single.restriction, LiveRestriction.subscribersOnly);
      expect(
        () => YouTubeApi.listing(answer([_row('aaaaaaaaaa1', channel: null)]), search: true),
        throwsA(isA<ApiChanged>()),
      );
      final none = YouTubeApi.listing(
        answer([_row('aaaaaaaaaa5', badges: const [], viewers: '3 waiting')]),
        search: true,
      );
      expect(none.rooms, isEmpty);
      expect(none.next, isNull, reason: 'no live row: no next page');
      expect(YouTubeApi.listing('{"contents":[]}', search: true).rooms, isEmpty, reason: 'no results');
      expect(() => YouTubeApi.listing('{"contents":[]}', search: false), throwsA(isA<ApiChanged>()));
      expect(() => YouTubeApi.listing('[]', search: true), throwsA(isA<ApiChanged>()));
      expect(() => YouTubeApi.listing('x', search: true, status: 403), throwsA(isA<RiskControl>()));
    });
  });

  group('room ids and links (23-1)', () {
    final legacy = _legacy('S07-channel-live');

    test('a channel id is UC and 22 characters; a video id 11', () {
      expect(YouTubeApi.isChannelId(_lofi), isTrue);
      expect(YouTubeApi.isChannelId('UCshort'), isFalse);
      expect(YouTubeApi.isChannelId('${_lofi}x'), isFalse);
      expect(YouTubeApi.isChannelId(_live), isFalse);
      expect(YouTubeApi.isVideoId(_live), isTrue);
      expect(YouTubeApi.isVideoId(_lofi), isFalse);
      expect(YouTubeApi.roomLink(_lofi), 'https://www.youtube.com/channel/$_lofi/live');
      expect(YouTubeApi.roomLink(_lofi, liveVideoId: _live), 'https://www.youtube.com/watch?v=$_live');
    });

    test("every link parses as 3.x's YouTubeLink.parse did; channel/UC… links name their channel", () {
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
      expect(YouTubeLink.parse('https://www.youtube.com/channel/$_lofi/live')!.channelId, _lofi);
      expect(YouTubeLink.parse('https://www.youtube.com/embed/live_stream?channel=$_lofi')!.channelId, _lofi);
      expect(YouTubeLink.parse('https://www.youtube.com/channel/UCaaaaaaaaaaaaaaaaaaaa')!.channelId, isNull);
      expect(YouTubeLink.parse('https://www.youtube.com/@LofiGirl')!.channelId, isNull);
      expect(YouTubeLink.parse('https://youtu.be/$_live')!.channelId, isNull);
    });

    test("search keywords: 3.x's references, but a bare name is a keyword now (23-2)", () {
      final expected = legacy['YouTubeLink.parseOrReference'] as Map<String, dynamic>;
      // 23-2: keyword search replaces 3.x's reading of a bare 3–30 character
      // name as a handle (M4.23 problem 15).
      const changed = {'LofiGirl', 'lofi'};
      for (final MapEntry(:key, :value) in expected.entries) {
        final link = YouTubeLink.parseOrReference(key);
        final actual = link == null ? null : {'kind': link.kind.name, 'id': link.id, 'url': link.url};
        if (changed.contains(key)) {
          expect(value, isNotNull, reason: key);
          expect(actual, isNull, reason: '$key changed: 23-2 a keyword');
        } else {
          expect(actual, value, reason: key);
        }
      }
      expect(YouTubeLink.parseOrReference(_lofi)!.id, 'channel/$_lofi');
      expect(YouTubeLink.parseOrReference(_lofi)!.channelId, _lofi);
      expect(YouTubeLink.parseOrReference('programming'), isNull, reason: 'an 11-letter word');
      expect(YouTubeLink.parseOrReference('Programming')?.kind, YouTubeLinkKind.video, reason: 'may be an id');
      expect(YouTubeLink.parseOrReference('@lo'), isNull);
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

    test("the channel of any video, broadcast or not (the M9 migration's rule)", () {
      expect(YouTubeApi.channelOf(_playerBody(), _live), _lofi);
      expect(
        YouTubeApi.channelOf(YouTubeApi.player(_sample('S09-player-ended').body), '9njefMDxzqw'),
        startsWith('UC1s'),
      );
      expect(
        YouTubeApi.channelOf(YouTubeApi.player(_sample('S11-player-video').body), 'dQw4w9WgXcQ'),
        'UCuAXFkgsw1L7xaCfnd5JJOw',
      );
      expect(
        () => YouTubeApi.channelOf(YouTubeApi.player(_sample('S12-player-missing').body), 'aaaaaaaaaaa'),
        throwsA(isA<NotFound>()),
      );
      expect(() => YouTubeApi.channelOf(_playerBody(), 'aaaaaaaaaaa'), throwsA(isA<ApiChanged>()));
      expect(
        () => YouTubeApi.channelOf(_with(_playerBody(), details: {'channelId': null}), _live),
        throwsA(isA<ApiChanged>()),
      );
      final bare = Map<String, dynamic>.of(_playerBody())
        ..remove('videoDetails')
        ..['playabilityStatus'] = {'status': 'LOGIN_REQUIRED'};
      expect(() => YouTubeApi.channelOf(bare, _live), throwsA(isA<NeedsLogin>()));
    });
  });

  group('states (3.x, and 23-5 for live broadcasts this client may not play)', () {
    final body = _playerBody();

    test('a restricted live broadcast stays live with its restriction and the error playback reports', () {
      for (final (status, reason, restriction, error) in [
        (
          'UNPLAYABLE',
          'The uploader has not made this video available in your country',
          LiveRestriction.regionBlocked,
          isA<RegionBlocked>(),
        ),
        ('UNPLAYABLE', 'This live event is not available.', LiveRestriction.unplayable, isA<StreamUnavailable>()),
        (
          'LOGIN_REQUIRED',
          'Join this channel to get access to members-only content like this video, and other exclusive perks.',
          LiveRestriction.subscribersOnly,
          isA<StreamUnavailable>(),
        ),
        ('LOGIN_REQUIRED', 'Sign in to confirm your age', LiveRestriction.adult, isA<NeedsLogin>()),
        ('AGE_CHECK_REQUIRED', '', LiveRestriction.adult, isA<NeedsLogin>()),
        ('LOGIN_REQUIRED', 'Sign in to confirm you’re not a bot', LiveRestriction.needsLogin, isA<NeedsLogin>()),
        ('CONTENT_CHECK_REQUIRED', '', LiveRestriction.needsLogin, isA<NeedsLogin>()),
        ('LOGIN_REQUIRED', 'This video is private', LiveRestriction.private, isA<StreamUnavailable>()),
        ('UNPLAYABLE', 'This video requires payment to watch.', LiveRestriction.paid, isA<StreamUnavailable>()),
        ('ERROR', 'Something went wrong', LiveRestriction.unplayable, isA<StreamUnavailable>()),
      ]) {
        final video = _synthetic(_with(body, status: {'status': status, 'reason': reason}));
        expect(video.room.effectiveLiveStatus, LiveStatus.live, reason: '$status $reason: 3.x showed banned/offline');
        expect(video.room.restriction, restriction, reason: reason);
        expect(video.streamError, error, reason: reason);
        expect(video.streamError.toString(), contains(restriction.name), reason: reason);
        expect(video.room.followGroup, FollowGroup.live);
      }
      final private = _synthetic(_with(body, details: {'isPrivate': true}));
      expect((private.room.effectiveLiveStatus, private.room.restriction), (LiveStatus.live, LiveRestriction.private));
      expect(_synthetic(body).streamError, isNull);
    });

    test('restricted videos that are no broadcast stay banned (3.x), with their restriction', () {
      final plain = _with(body, details: {'isLive': false, 'isLiveContent': false});
      for (final status in ['LOGIN_REQUIRED', 'AGE_CHECK_REQUIRED', 'CONTENT_CHECK_REQUIRED']) {
        final video = _synthetic(_with(plain, status: {'status': status}));
        expect(video.room.effectiveLiveStatus, LiveStatus.banned, reason: status);
        expect(video.room.restriction, isNotNull, reason: status);
        expect(video.streamError, isNull, reason: 'nothing is on');
      }
      final ended = _synthetic(_with(_with(body, details: {'isLive': false}), status: {'status': 'LOGIN_REQUIRED'}));
      expect((ended.room.effectiveLiveStatus, ended.room.restriction), (LiveStatus.offline, null));
    });

    test('an ended broadcast is offline; without a status a broadcast is offline, anything else unknown', () {
      expect(_synthetic(_with(body, details: {'isLive': false})).room.effectiveLiveStatus, LiveStatus.offline);
      final noStatus = Map<String, dynamic>.of(body)..remove('playabilityStatus');
      expect(_synthetic(noStatus).room.effectiveLiveStatus, LiveStatus.live, reason: 'isLive says so (23-5)');
      final plain = _with(noStatus, details: {'isLive': false, 'isLiveContent': false});
      expect(_synthetic(plain).room.effectiveLiveStatus, LiveStatus.unknown);
      final waiting = _with(body, status: {'status': 'LIVE_STREAM_OFFLINE'});
      expect(_synthetic(waiting).room.effectiveLiveStatus, LiveStatus.offline, reason: 'not started yet');
    });

    test('an answer for another video, without names or without a channel is ApiChanged', () {
      expect(() => _synthetic(body, videoId: 'aaaaaaaaaaa'), throwsA(isA<ApiChanged>()));
      expect(() => _synthetic(_with(body, details: {'title': ''})), throwsA(isA<ApiChanged>()));
      expect(() => _synthetic(_with(body, details: {'author': null})), throwsA(isA<ApiChanged>()));
      expect(() => _synthetic(_with(body, details: {'channelId': 'UCshort'})), throwsA(isA<ApiChanged>()));
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

    test('the start: an ISO time with an offset, only while live', () {
      Map<String, dynamic> started(Object? value) => {
        ...body,
        'microformat': {
          'playerMicroformatRenderer': {
            'liveBroadcastDetails': {'isLiveNow': true, 'startTimestamp': value},
          },
        },
      };
      expect(_synthetic(started('2026-09-23T18:47:51+02:00')).room.startedAt, DateTime.utc(2026, 9, 23, 16, 47, 51));
      expect(_synthetic(started('2026-09-23T16:47:51Z')).room.startedAt, DateTime.utc(2026, 9, 23, 16, 47, 51));
      for (final value in ['2026-09-23 16:47:51', '1970-01-01T00:00:00Z', 'soon', 1790619788, null]) {
        expect(_synthetic(started(value)).room.startedAt, isNull, reason: '$value');
      }
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
      expect(
        _synthetic(thumbs(['https://i.ytimg.com/a.jpg', 'https://yt3.googleusercontent.com/b.jpg'])).room.cover,
        'https://i.ytimg.com/a.jpg',
        reason: 'googleusercontent.com only for avatars',
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
      expect(YouTubeApi.mediaHeaders(''), containsPair('referer', 'https://www.youtube.com/'));
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
