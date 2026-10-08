// YouTubeSite over the recorded YouTube responses (ReplayHttp) and a few
// synthetic ones. 3.x's requests are compared with the ones it sent
// (expected.json records them) where M4.U kept them: room entry of a video id,
// the player request, the HLS master, the recovery. The M4.U.23 rows change
// the rest, each named where it is tested: the room is the channel (23-1),
// recommendations and keyword search (23-2), the channel avatar (23-4),
// restricted live broadcasts (23-5), and refreshes without the watch page
// (23-6). Chat (23-3) only gets its arguments here (M5).
import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/youtube';

/// The live broadcast of S07 and its channel.
const _live = 'nI725iVsyoQ';
const _lofi = 'UCSJ4gkVC6NrvII8umztf0Ow';
const _lofiAvatar =
    'https://yt3.ggpht.com/GyVPysrx-cVIWIQDfi2MkaYr7oRIxuOgGeZihnw-hgTv6E5LBQ67v5yXTFvqP2Bl7BB_S-0L-A=s176-c-k-c0x00ffffff-no-rj';

const _liveSamples = ['S07-watch-live', 'S07-player-live', 'S07-hls-live'];

const _ended = '9njefMDxzqw';
const _minecraft = 'UC1sELGmy5jp5fQUugmuYlXQ';
const _upcoming = '32myp8UqPOE';
const _osteen = 'UCvxWyn4rfcI2H9APhfUIB1Q';
const _video = 'dQw4w9WgXcQ';
const _rick = 'UCuAXFkgsw1L7xaCfnd5JJOw';
const _missing = 'aaaaaaaaaaa';
const _beast = 'UCX6OQ3DkcsbYNE6H8uQQuVA';

const List<String> _allSamples = [
  ..._liveSamples,
  'S03-resolve-channel-live',
  'S03-resolve-channel-offline',
  'S03-resolve-channel-upcoming',
  'S03-resolve-handle',
  'S03-resolve-handle-live',
  'S03-resolve-handle-missing',
  'S03-resolve-custom',
  'S05-feed-offline',
  'S08-channel-offline',
  'S09-watch-ended',
  'S09-player-ended',
  'S10-watch-upcoming',
  'S10-player-upcoming',
  'S11-watch-video',
  'S11-player-video',
  'S12-watch-missing',
  'S12-player-missing',
  'S13-metadata-live',
  'S01-browse-live',
  'S02-search-p1',
  'S02-search-p2',
];

typedef _Setup = ({YouTubeSite site, ReplayHttp http});

_Setup _setup([
  List<String> samples = _allSamples,
  List<ReplaySample> extra = const [],
  Duration broadcastLifetime = const Duration(minutes: 30),
  DateTime Function()? clock,
]) {
  final http = ReplayHttp([...extra, for (final name in samples) ReplaySample.load('$_root/$name')]);
  return (site: YouTubeSite(http, broadcastLifetime: broadcastLifetime, clock: clock), http: http);
}

Map<String, dynamic> _legacy(String sample) => Fixture.load('youtube', sample).legacy as Map<String, dynamic>;

Object? _result(Object? traced) => (traced! as Map<String, dynamic>)['result'];

/// 3.x's requests of a traced legacy call: method, URL and headers (names in
/// lower case).
List<Map<String, Object?>> _legacyRequests(Object? traced) => [
  for (final request in ((traced! as Map<String, dynamic>)['requests'] as List).cast<Map<String, dynamic>>())
    {
      'method': request['method'],
      'url': request['url'],
      'headers': {
        for (final MapEntry(:key, :value) in (request['headers'] as Map<String, dynamic>).entries)
          key.toLowerCase(): value,
      },
    },
];

List<Map<String, Object?>> _sent(Iterable<LiveRequest> requests) => [
  for (final request in requests)
    {
      'method': request.method,
      'url': '${request.url}',
      'headers': {for (final MapEntry(:key, :value) in request.headers.entries) key.toLowerCase(): value},
    },
];

List<String> _urls(Iterable<LiveRequest> requests) => [for (final request in requests) '${request.url}'];

/// Asserts that [room] matches 3.x's projection on every key 3.x wrote but
/// [changed] (intended differences, by upgrade row), which must differ.
void _expectRoom(LiveRoom room, Object? legacy, {Map<String, String> changed = const {}, String reason = ''}) {
  final actual = {...room.toJson(), 'link': room.link};
  for (final MapEntry(:key, :value) in (legacy! as Map<String, dynamic>).entries) {
    if (changed.containsKey(key)) {
      expect(actual[key] ?? '', isNot(value ?? ''), reason: '$reason $key changed: ${changed[key]}');
    } else {
      expect(actual[key] ?? '', value ?? '', reason: '$reason $key');
    }
  }
}

const _identity = {
  'roomId': '23-1 the channel id',
  'avatar': "23-4 the channel's avatar",
  'notice': 'M5.19 live chat is shown, so the notice drops "chat pending"',
};
const _refreshed = {
  'roomId': '23-1 the channel id',
  'avatar': '23-6 no watch page: no avatar, the follow keeps its own',
  'area': '23-6 no watch page: no category',
  'watching': '23-6 updated_metadata (recorded 7 hours later)',
  'onlineViewers': '23-6 updated_metadata (recorded 7 hours later)',
  'notice': 'M5.19 live chat is shown, so the notice drops "chat pending"',
};

final Matcher _cancelled = throwsA(
  isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled),
);

ReplaySample _get(String url, Object body, {int status = 200, Map<String, List<String>> headers = const {}}) =>
    ReplaySample(
      method: 'GET',
      url: Uri.parse(url),
      status: status,
      bytes: utf8.encode(body is String ? body : jsonEncode(body)),
      headers: headers,
    );

ReplaySample _player(String videoId, Object body, {String key = YouTubeApi.fallbackApiKey, int status = 200}) =>
    ReplaySample(
      method: 'POST',
      url: YouTubeApi.playerUrl(key),
      status: status,
      bytes: utf8.encode(body is String ? body : jsonEncode(body)),
      json: YouTubeApi.playerBody(videoId),
    );

/// A web client InnerTube answer to [json] at [endpoint].
ReplaySample _api(String endpoint, Map<String, Object?> json, Object body, {int status = 200}) => ReplaySample(
  method: 'POST',
  url: YouTubeApi.apiUrl(endpoint),
  status: status,
  bytes: utf8.encode(body is String ? body : jsonEncode(body)),
  json: json,
);

/// `navigation/resolve_url` of [channelId]'s `/live` page naming the channel
/// (it is not live).
ReplaySample _resolvedOffline(String channelId) =>
    _api('navigation/resolve_url', YouTubeApi.resolveBody(YouTubeApi.liveUrl(channelId)), {
      'endpoint': {
        'browseEndpoint': {'browseId': channelId},
      },
    });

/// The page of a channel that is not live.
String _channelPage(String channelId, String name) =>
    '<html><script>var ytInitialData = ${jsonEncode({
      'metadata': {
        'channelMetadataRenderer': {
          'externalId': channelId,
          'title': name,
          'description': 'about $name',
          'avatar': {
            'thumbnails': [
              {'url': 'https://yt3.googleusercontent.com/$name=s900'},
            ],
          },
        },
      },
    })};</script></html>';

/// [channelId]'s `/live` page answered with [sample]'s body (the `/live`
/// URL serves the watch page of the broadcast it names, as S07-channel-live
/// shows).
ReplaySample _liveAs(String channelId, String sample) =>
    _get(YouTubeApi.liveUrl(channelId), Fixture.load('youtube', sample).body);

Map<String, dynamic> _livePlayer() =>
    jsonDecode(Fixture.load('youtube', 'S07-player-live').body) as Map<String, dynamic>;

String get _masterUrl => (_livePlayer()['streamingData'] as Map<String, dynamic>)['hlsManifestUrl'] as String;

/// A search answer with a live row for each (video id, channel id) of
/// [rows], and the continuation [next].
Map<String, Object?> _searchAnswer(List<(String, String)> rows, {String? next}) => {
  'contents': [
    for (final (videoId, channelId) in rows)
      {
        'videoRenderer': {
          'videoId': videoId,
          'title': {
            'runs': [
              {'text': 'title of $videoId'},
            ],
          },
          'ownerText': {
            'runs': [
              {
                'text': 'owner $channelId',
                'navigationEndpoint': {
                  'browseEndpoint': {'browseId': channelId},
                },
              },
            ],
          },
          'viewCountText': {'simpleText': '5 watching'},
        },
      },
    if (next != null)
      {
        'continuationItemRenderer': {
          'continuationEndpoint': {
            'continuationCommand': {'token': next},
          },
        },
      },
  ],
};

final class _Failing implements LiveHttp {
  new(this.reason);

  final TransportReason reason;

  @override
  Future<LiveResponse> send(LiveRequest request) async => throw TransportFailure('youtube', reason, 'test');

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('youtube', reason, 'test');

  @override
  void close() {}
}

void main() {
  final legacy = _legacy('S07-watch-live')[_live] as Map<String, dynamic>;

  group('rooms: the channel is the room (23-1)', () {
    test(
      "a live channel: its /live page, the player answer and the master; 3.x's room but for id and avatar",
      () async {
        final setup = _setup(_allSamples, [_liveAs(_lofi, 'S07-watch-live')]);
        final room = await setup.site.getRoomDetail(roomId: _lofi);
        expect(_urls(setup.http.requests), [
          'https://www.youtube.com/channel/$_lofi/live',
          YouTubeApi.playerUrl(YouTubeApi.fallbackApiKey).toString(),
          _masterUrl,
        ]);
        final v3 = _legacyRequests(legacy['getRoomDetail']);
        expect(_sent(setup.http.requests).skip(1), v3.skip(1), reason: "the player and master requests are 3.x's");
        expect(setup.http.requests.first.headers, YouTubeApi.pageHeaders(''));
        expect(setup.http.requests.every((request) => request.site == 'youtube'), isTrue);
        expect(setup.http.requests.every((request) => request.timeout == const Duration(seconds: 25)), isTrue);
        _expectRoom(room, _result(legacy['getRoomDetail']), changed: _identity);
        expect((room.roomId, room.userId, room.avatar), (_lofi, _lofi, _lofiAvatar));
        expect(room.link, 'https://www.youtube.com/watch?v=$_live');
        expect(room.startedAt, DateTime.utc(2026, 9, 23, 16, 47, 51));
        expect(room.restriction, LiveRestriction.none);
        expect(room.danmakuData, const YouTubeDanmakuArgs(roomId: _lofi, videoId: _live));
        final data = room.data! as YouTubeRoomData;
        expect((data.channelId, data.videoId, data.streams.length, data.streamError), (_lofi, _live, 7, null));
      },
    );

    test('S07-channel-live (the real /live answer) opens the same broadcast', () async {
      final setup = _setup(_allSamples, [_liveAs(_lofi, 'S07-channel-live')]);
      final room = await setup.site.getRoomDetailForRecording(roomId: _lofi);
      expect(setup.http.requests, hasLength(3));
      expect((room.roomId, room.onlineViewers), (_lofi, '1257'));
      expect(room.title, startsWith('24/7 deep sleep'));
      expect((room.data! as YouTubeRoomData).streams, hasLength(7));
    });

    test("a 3.x video id: 3.x's three requests, and the room is its channel's", () async {
      for (final depth in ['getRoomDetail', 'getRoomDetailForRecording']) {
        final setup = _setup();
        final room = depth == 'getRoomDetail'
            ? await setup.site.getRoomDetail(roomId: _live)
            : await setup.site.getRoomDetailForRecording(roomId: _live);
        expect(_sent(setup.http.requests), _legacyRequests(legacy[depth]), reason: depth);
        _expectRoom(room, _result(legacy[depth]), changed: _identity, reason: depth);
        expect(room.roomId, _lofi);
        expect((room.data! as YouTubeRoomData).videoId, _live);
      }
    });

    test('a follow refresh reads no watch page (23-6): resolve_url, player, updated_metadata', () async {
      final setup = _setup();
      final room = await setup.site.getRoomDetailForRefresh(roomId: _lofi);
      expect(_urls(setup.http.requests), [
        'https://www.youtube.com/youtubei/v1/navigation/resolve_url?prettyPrint=false',
        YouTubeApi.playerUrl(YouTubeApi.fallbackApiKey).toString(),
        'https://www.youtube.com/youtubei/v1/updated_metadata?prettyPrint=false',
      ]);
      expect(setup.http.requests.map((request) => request.method), ['POST', 'POST', 'POST']);
      expect(setup.http.requests.first.headers['content-type'], 'application/json; charset=utf-8');
      expect(setup.http.requests.first.headers['referer'], 'https://www.youtube.com/');
      expect(setup.http.requests.every((request) => request.site == 'youtube'), isTrue);
      _expectRoom(room, _result(legacy['getRoomDetailForRefresh']), changed: _refreshed);
      expect((room.roomId, room.onlineViewers, room.avatar, room.area), (_lofi, '1331', '', null));
      expect(room.link, 'https://www.youtube.com/watch?v=$_live');
      expect(room.data, isNull, reason: 'a refresh reads no stream');
      expect(room.restriction, LiveRestriction.none, reason: 'the player answer tells');
      expect(room.startedAt, isNull, reason: 'the page has it; the follow keeps it (M2.1 merge)');
      expect(room.danmakuData, const YouTubeDanmakuArgs(roomId: _lofi, videoId: _live));
    });

    test('a 3.x video id refreshes with its player answer and updated_metadata (3.x: page and player)', () async {
      final setup = _setup();
      final room = await setup.site.getRoomDetailForRefresh(roomId: _live);
      expect(_urls(setup.http.requests), [
        YouTubeApi.playerUrl(YouTubeApi.fallbackApiKey).toString(),
        'https://www.youtube.com/youtubei/v1/updated_metadata?prettyPrint=false',
      ]);
      _expectRoom(room, _result(legacy['getRoomDetailForRefresh']), changed: _refreshed);
    });

    test('live status: the refresh without viewers', () async {
      final setup = _setup([..._allSamples], [_resolvedOffline(_minecraft)]);
      expect(await setup.site.getLiveStatus(roomId: _lofi), isTrue);
      expect(setup.http.requests, hasLength(2));
      setup.http.requests.clear();
      expect(await setup.site.getLiveStatus(roomId: _beast), isFalse);
      expect(setup.http.requests, hasLength(1), reason: 'resolve_url alone');
      setup.http.requests.clear();
      expect(await setup.site.getLiveStatus(roomId: _osteen), isFalse, reason: 'only a scheduled broadcast');
      expect(setup.http.requests, hasLength(2));
      expect(await setup.site.getLiveStatus(roomId: _live), _result(legacy['getLiveStatus']));
      expect(await setup.site.getLiveStatus(roomId: _ended), isFalse);
    });

    test('a channel that is not live: its page gives name, avatar and description (1 request)', () async {
      final setup = _setup();
      final room = await setup.site.getRoomDetail(roomId: _beast);
      expect(_urls(setup.http.requests), ['https://www.youtube.com/channel/$_beast/live']);
      expect((room.roomId, room.nick, room.title), (_beast, 'MrBeast', ''));
      expect(room.avatar, startsWith('https://yt3.googleusercontent.com/'));
      expect(room.introduction, startsWith('SUBSCRIBE FOR A COOKIE!'));
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.link, 'https://www.youtube.com/channel/$_beast/live');
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      expect(setup.http.requests, hasLength(1));
    });

    test("its refresh is resolve_url alone and keeps the follow's name (M2.1 merge)", () async {
      final setup = _setup();
      final stored = await setup.site.getRoomDetail(roomId: _beast);
      setup.http.requests.clear();
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: _beast);
      expect(setup.http.requests, hasLength(1));
      expect((refreshed.roomId, refreshed.nick, refreshed.effectiveLiveStatus), (_beast, '', LiveStatus.offline));
      final merged = stored.mergeFrom(refreshed);
      expect((merged.nick, merged.avatar), (stored.nick, stored.avatar));
    });

    test('a channel with only a scheduled broadcast shows it, offline', () async {
      final setup = _setup(_allSamples, [_liveAs(_osteen, 'S10-watch-upcoming')]);
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: _osteen);
      expect(setup.http.requests, hasLength(2), reason: 'resolve_url names it, its player answer says upcoming');
      expect((refreshed.roomId, refreshed.effectiveLiveStatus), (_osteen, LiveStatus.offline));
      expect(refreshed.title, 'Lakewood Water Baptism | October 3, 2026');
      expect(refreshed.link, 'https://www.youtube.com/channel/$_osteen/live');
      setup.http.requests.clear();
      final entered = await setup.site.getRoomDetail(roomId: _osteen);
      expect(setup.http.requests, hasLength(2), reason: 'its /live page and player answer');
      expect((entered.effectiveLiveStatus, entered.nick, entered.data), (LiveStatus.offline, 'Joel Osteen', null));
    });

    test("a 3.x id of an ended broadcast: its channel's current state (the channel page too)", () async {
      final expected = _legacy('S09-watch-ended')[_ended] as Map<String, dynamic>;
      final setup = _setup(_allSamples, [
        _get(YouTubeApi.liveUrl(_minecraft), _channelPage(_minecraft, 'Minecraft')),
        _resolvedOffline(_minecraft),
      ]);
      final entered = await setup.site.getRoomDetail(roomId: _ended);
      expect(_sent(setup.http.requests).take(2), _legacyRequests(expected['getRoomDetail']));
      expect(_urls(setup.http.requests).last, 'https://www.youtube.com/channel/$_minecraft/live');
      expect((entered.roomId, entered.nick, entered.title), (_minecraft, 'Minecraft', ''));
      expect(entered.effectiveLiveStatus, LiveStatus.offline);
      setup.http.requests.clear();
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: _ended);
      expect(setup.http.requests, hasLength(2), reason: 'its player answer, then its channel');
      _expectRoom(
        refreshed,
        _result(expected['getRoomDetailForRefresh']),
        changed: const {
          'roomId': '23-1 the channel id',
          'link': "23-1 the channel's /live page",
          'avatar': '23-6 no watch page',
          'area': '23-6 no watch page',
          'notice': 'M5.19 live chat is shown, so the notice drops "chat pending"',
        },
      );
    });

    test("a 3.x id of an upcoming broadcast the channel's /live page names too: no second player request", () async {
      final setup = _setup(_allSamples, [_liveAs(_osteen, 'S10-watch-upcoming')]);
      final room = await setup.site.getRoomDetail(roomId: _upcoming);
      expect(setup.http.requests, hasLength(3), reason: 'watch page, player, channel page');
      expect((room.roomId, room.effectiveLiveStatus), (_osteen, LiveStatus.offline));
      expect(room.title, startsWith('Lakewood'));
    });

    test("a broadcast a /live page names that is not the channel's is not its broadcast", () async {
      final setup = _setup(_allSamples, [_liveAs(_minecraft, 'S07-watch-live')]);
      await expectLater(setup.site.getRoomDetail(roomId: _minecraft), throwsA(isA<NotFound>()));
      final known = _setup(_allSamples, [_liveAs(_minecraft, 'S07-watch-live'), _resolvedOffline(_minecraft)]);
      final room = await known.site.getRoomDetail(roomId: _ended);
      expect((room.roomId, room.effectiveLiveStatus), (_minecraft, LiveStatus.offline));
      expect(room.title, startsWith('Minecraft LIVE'), reason: "the 3.x id's own broadcast");
    });

    test('S11 an ordinary video is its channel, offline (3.x: NotFound)', () async {
      final expected = _legacy('S11-watch-video')[_video] as Map<String, dynamic>;
      expect(_result(expected['getRoomDetail']), {'throws': 'YouTubeException', 'message': 'YouTube notLive'});
      final setup = _setup(_allSamples, [_get(YouTubeApi.liveUrl(_rick), _channelPage(_rick, 'Rick Astley'))]);
      final room = await setup.site.getRoomDetail(roomId: _video);
      expect((room.roomId, room.nick, room.effectiveLiveStatus), (_rick, 'Rick Astley', LiveStatus.offline));
    });

    test("S12 a missing video is NotFound after 3.x's two requests", () async {
      final expected = _legacy('S12-watch-missing')[_missing] as Map<String, dynamic>;
      final setup = _setup();
      await expectLater(setup.site.getRoomDetail(roomId: _missing), throwsA(isA<NotFound>()));
      expect(_sent(setup.http.requests), _legacyRequests(expected['getRoomDetail']));
      await expectLater(setup.site.getLiveStatus(roomId: _missing), throwsA(isA<NotFound>()));
    });

    test('a channel YouTube does not know is NotFound (its page says "This channel does not exist.")', () async {
      const unknown = 'UCaaaaaaaaaaaaaaaaaaaaaa';
      final page =
          '<script>var ytInitialData = ${jsonEncode({
            'alerts': [
              {
                'alertRenderer': {
                  'type': 'ERROR',
                  'text': {'simpleText': 'This channel does not exist.'},
                },
              },
            ],
          })};</script>';
      final setup = _setup(const [], [_get(YouTubeApi.liveUrl(unknown), page)]);
      await expectLater(setup.site.getRoomDetail(roomId: unknown), throwsA(isA<NotFound>()));
      expect(setup.http.requests, hasLength(1));
    });

    test('a room id that is no channel or video id is NotFound without a request', () async {
      final setup = _setup();
      for (final id in ['short', '', 'nI725iVsyoQ!', '@LofiGirl', 'UCshort', '${_lofi}x']) {
        await expectLater(setup.site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
        await expectLater(setup.site.getRoomDetailForRefresh(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(setup.http.requests, isEmpty);
      expect((await setup.site.getRoomDetailForRefresh(roomId: ' $_lofi ')).roomId, _lofi);
    });

    test('a live room without readable sources still opens; its qualities say why (3.x failed the room)', () async {
      final bad = _livePlayer()..['streamingData'] = {'hlsManifestUrl': 'https://evil.example/index.m3u8'};
      final setup = _setup(['S07-watch-live'], [_player(_live, bad)]);
      final room = await setup.site.getRoomDetail(roomId: _live);
      expect(room.isLiveNow, isTrue);
      expect((room.data! as YouTubeRoomData).streamError, isA<ApiChanged>());
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<ApiChanged>()));

      final none = _livePlayer()..['streamingData'] = <String, Object?>{};
      final empty = _setup(['S07-watch-live'], [_player(_live, none)]);
      final silent = await empty.site.getRoomDetail(roomId: _live);
      expect((silent.data! as YouTubeRoomData).streams, isEmpty);
      await expectLater(empty.site.getPlayQualities(detail: silent), throwsA(isA<StreamUnavailable>()));
    });

    test(
      '23-5 a live broadcast this client may not play: live, restricted, no master read, playback says why',
      () async {
        for (final (reason, restriction, error) in [
          (
            'The uploader has not made this video available in your country',
            LiveRestriction.regionBlocked,
            isA<RegionBlocked>(),
          ),
          (
            'Join this channel to get access to members-only content',
            LiveRestriction.subscribersOnly,
            isA<StreamUnavailable>(),
          ),
          ('This live event is not available.', LiveRestriction.unplayable, isA<StreamUnavailable>()),
        ]) {
          final blocked = _livePlayer()..['playabilityStatus'] = {'status': 'UNPLAYABLE', 'reason': reason};
          final setup = _setup(['S07-watch-live'], [_player(_live, blocked)]);
          final room = await setup.site.getRoomDetail(roomId: _live);
          expect(setup.http.requests, hasLength(2), reason: reason);
          expect((room.effectiveLiveStatus, room.restriction), (LiveStatus.live, restriction), reason: reason);
          expect(room.followGroup, FollowGroup.live);
          setup.http.requests.clear();
          await expectLater(setup.site.getPlayQualities(detail: room), throwsA(error), reason: reason);
          expect(setup.http.requests, isEmpty);
        }
      },
    );
  });

  group('remembered broadcasts: a channel opens the broadcast its card showed', () {
    test('after a video link search, entering the channel opens that video, not its /live page', () async {
      final setup = _setup();
      final card = (await setup.site.searchRooms('https://youtu.be/$_live')).single;
      expect(card.roomId, _lofi);
      setup.http.requests.clear();
      final room = await setup.site.getRoomDetail(roomId: card.roomId);
      expect(_sent(setup.http.requests), _legacyRequests(legacy['getRoomDetail']), reason: "the video's 3 requests");
      expect((room.data! as YouTubeRoomData).videoId, _live);
    });

    test("a search card's broadcast (Lofi Girl has several on air) is the one room entry opens", () async {
      final setup = _setup(_allSamples, [
        _api('search', YouTubeApi.searchBody('deep sleep'), _searchAnswer([(_live, _lofi)])),
      ]);
      await setup.site.searchRooms('deep sleep');
      setup.http.requests.clear();
      await setup.site.getRoomDetail(roomId: _lofi);
      expect(_urls(setup.http.requests).first, 'https://www.youtube.com/watch?v=$_live');
    });

    test('the directory remembers its cards too', () async {
      final setup = _setup();
      await setup.site.getDirectoryPage();
      setup.http.requests.clear();
      await expectLater(setup.site.getRoomDetail(roomId: 'UCJg9wBPyKMNA5sRDnvzmkdg'), throwsA(isA<StateError>()));
      expect(_urls(setup.http.requests).single, 'https://www.youtube.com/watch?v=jRDug_owloQ');
    });

    test('an entered broadcast is remembered; after the lifetime (or with none) the /live page decides', () async {
      var now = DateTime.utc(2026, 9, 29);
      final setup = _setup(_allSamples, [_liveAs(_lofi, 'S07-watch-live')], const Duration(minutes: 30), () => now);
      await setup.site.getRoomDetail(roomId: _live);
      setup.http.requests.clear();
      await setup.site.getRoomDetail(roomId: _lofi);
      expect(_urls(setup.http.requests).first, 'https://www.youtube.com/watch?v=$_live');
      now = now.add(const Duration(minutes: 31));
      setup.http.requests.clear();
      await setup.site.getRoomDetail(roomId: _lofi);
      expect(_urls(setup.http.requests).first, 'https://www.youtube.com/channel/$_lofi/live');
      final off = _setup(_allSamples, [_liveAs(_lofi, 'S07-watch-live')], Duration.zero);
      await off.site.getRoomDetail(roomId: _live);
      off.http.requests.clear();
      await off.site.getRoomDetail(roomId: _lofi);
      expect(_urls(off.http.requests).first, 'https://www.youtube.com/channel/$_lofi/live');
    });

    test('a remembered broadcast that ended, or is gone, gives way to the /live page', () async {
      final ended = _livePlayer()..['playabilityStatus'] = {'status': 'LIVE_STREAM_OFFLINE'};
      const gone = 'bbbbbbbbbbb';
      final setup = _setup(
        ['S07-watch-live'],
        [
          _api('search', YouTubeApi.searchBody('ended'), _searchAnswer([(_live, _lofi)])),
          _api('search', YouTubeApi.searchBody('gone'), _searchAnswer([(gone, _lofi)])),
          _player(_live, ended),
          _get('https://www.youtube.com/watch?v=$gone', Fixture.load('youtube', 'S12-watch-missing').body),
          _player(gone, Fixture.load('youtube', 'S12-player-missing').body),
          _get(YouTubeApi.liveUrl(_lofi), _channelPage(_lofi, 'Lofi Girl')),
        ],
      );
      await setup.site.searchRooms('ended');
      setup.http.requests.clear();
      final room = await setup.site.getRoomDetail(roomId: _lofi);
      expect(_urls(setup.http.requests), [
        'https://www.youtube.com/watch?v=$_live',
        YouTubeApi.playerUrl(YouTubeApi.fallbackApiKey).toString(),
        'https://www.youtube.com/channel/$_lofi/live',
      ]);
      expect((room.roomId, room.effectiveLiveStatus, room.nick), (_lofi, LiveStatus.offline, 'Lofi Girl'));
      await setup.site.searchRooms('gone');
      setup.http.requests.clear();
      final after = await setup.site.getRoomDetail(roomId: _lofi);
      expect(_urls(setup.http.requests).last, 'https://www.youtube.com/channel/$_lofi/live');
      expect(after.roomId, _lofi);
    });
  });

  group('streams', () {
    test("qualities and lines come from room entry without a request, as 3.x's", () async {
      final setup = _setup(_allSamples, [_liveAs(_lofi, 'S07-watch-live')]);
      final room = await setup.site.getRoomDetail(roomId: _lofi);
      setup.http.requests.clear();
      final qualities = await setup.site.getPlayQualities(detail: room);
      expect([
        for (final quality in qualities)
          {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort, 'data': quality.data},
      ], _result(legacy['getPlayQualites']));
      final expected = legacy['resolvePlayUrlsRaw'] as Map<String, dynamic>;
      for (final quality in qualities) {
        final want = _result(expected['${quality.id}'])! as Map<String, dynamic>;
        final resolution = await setup.site.resolvePlayUrls(detail: room, quality: quality);
        expect(resolution.urls, want['urls'], reason: '${quality.id}');
        expect(resolution.appliedQualityData, want['appliedQualityData']);
        expect(await setup.site.getPlayUrls(detail: room, quality: quality), want['urls']);
        final line = resolution.lines.single;
        expect(line.headers, room.httpHeaders);
        expect(
          line.headers['referer'],
          'https://www.youtube.com/watch?v=$_live',
          reason: 'the broadcast, not the room',
        );
        expect(line.lease!.expiresAt!.toIso8601String(), (want['invalidAt'] as List).single);
        expect(
          resolveAppliedPlayQuality(qualities: qualities, requested: quality, resolution: resolution),
          same(quality),
        );
      }
      expect(setup.http.requests, isEmpty);
    });

    test("lease metadata is 3.x's: expire, renewed 10 minutes before", () async {
      final setup = _setup();
      final room = await setup.site.getRoomDetail(roomId: _live);
      final expected = legacy['resolvePlayUrlsRaw'] as Map<String, dynamic>;
      for (final quality in await setup.site.getPlayQualities(detail: room)) {
        final want = _result(expected['${quality.id}'])! as Map<String, dynamic>;
        final url = (want['urls'] as List).single as String;
        expect(setup.site.getPlayUrlInvalidAt(url)?.toIso8601String(), (want['invalidAt'] as List).single);
        expect(setup.site.getPlayUrlRefreshAt(url)?.toIso8601String(), (want['refreshAt'] as List).single);
      }
    });

    test("a card or a refreshed room makes room entry's requests first (3.x: identity error)", () async {
      expect(_result(legacy['getPlayQualites (refreshed room)']), {
        'throws': 'YouTubeException',
        'message': 'YouTube identity',
      });
      final setup = _setup(_allSamples, [_liveAs(_lofi, 'S07-watch-live')]);
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: _lofi);
      setup.http.requests.clear();
      final qualities = await setup.site.getPlayQualities(detail: refreshed);
      expect(qualities, hasLength(7));
      expect(_urls(setup.http.requests).first, 'https://www.youtube.com/channel/$_lofi/live');
      final card = LiveRoom(platform: 'youtube', roomId: _lofi);
      expect(
        (await setup.site.resolvePlayUrlsRaw(detail: card, quality: qualities.first)).appliedQualityData,
        'hls:1080:0:h264',
      );
    });

    test('offline and banned rooms have no qualities, without a request', () async {
      final setup = _setup();
      await expectLater(
        setup.site.getPlayQualities(
          detail: LiveRoom(platform: 'youtube', roomId: _lofi, liveStatus: LiveStatus.offline),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      await expectLater(
        setup.site.getPlayQualities(
          detail: LiveRoom(platform: 'youtube', roomId: _live, liveStatus: LiveStatus.banned),
        ),
        throwsA(isA<NeedsLogin>()),
      );
      await expectLater(
        setup.site.getPlayQualities(
          detail: LiveRoom(
            platform: 'youtube',
            roomId: _live,
            liveStatus: LiveStatus.banned,
            restriction: LiveRestriction.private,
          ),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(setup.http.requests, isEmpty);
      expect(
        () => setup.site.getPlayQualities(
          detail: LiveRoom(platform: 'twitch', roomId: _live),
        ),
        throwsArgumentError,
      );
    });

    test('a card whose broadcast has since ended is StreamUnavailable after the entry requests', () async {
      final ended = _livePlayer()..['playabilityStatus'] = {'status': 'LIVE_STREAM_OFFLINE'};
      final setup = _setup(['S07-watch-live'], [_player(_live, ended), _liveAs(_lofi, 'S07-watch-live')]);
      await expectLater(
        setup.site.getPlayQualities(
          detail: LiveRoom(platform: 'youtube', roomId: _lofi),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test("a master that cannot be read offers the master itself, as 3.x ('HLS 自动')", () async {
      for (final master in [_get(_masterUrl, '', status: 500), _get(_masterUrl, 'not a playlist')]) {
        final setup = _setup(['S07-watch-live', 'S07-player-live'], [master]);
        final room = await setup.site.getRoomDetail(roomId: _live);
        final qualities = await setup.site.getPlayQualities(detail: room);
        expect(qualities.map((quality) => quality.quality), ['HLS 自动 · HLS', 'DASH 自动 · DASH']);
        final lines = (await setup.site.resolvePlayUrlsRaw(detail: room, quality: qualities.first)).lines;
        expect(lines.single.url, _masterUrl);
        expect(lines.single.format, StreamFormat.hls);
      }
    });

    test("recovery: the broadcast's player answer and the master (3.x also read the watch page), 3.x's URL", () async {
      final setup = _setup(_allSamples, [_liveAs(_lofi, 'S07-watch-live')]);
      final room = await setup.site.getRoomDetail(roomId: _lofi);
      final quality = (await setup.site.getPlayQualities(detail: room)).first;
      setup.http.requests.clear();
      final resolution = await setup.site.resolvePlayUrlsForRecovery(detail: room, quality: quality);
      final expected = legacy['resolvePlayUrlsForRecoveryRaw(hls:1080:0:h264)'];
      expect(resolution.urls, (_result(expected)! as Map<String, dynamic>)['urls']);
      expect(resolution.appliedQualityData, 'hls:1080:0:h264');
      expect(_sent(setup.http.requests), _legacyRequests(expected).skip(1));
      expect(resolution.lines.single.lease, isNotNull);
      expect(resolution.lines.single.headers['referer'], 'https://www.youtube.com/watch?v=$_live');
    });

    test('recovery of the DASH or the master source needs no master request', () async {
      final setup = _setup();
      final room = await setup.site.getRoomDetail(roomId: _live);
      setup.http.requests.clear();
      final dash = await setup.site.resolvePlayUrlsForRecoveryRaw(
        detail: room,
        quality: const LivePlayQuality(quality: 'DASH 自动 · DASH', id: 'dash:auto'),
      );
      expect(dash.urls.single, contains('/api/manifest/dash/'));
      final auto = await setup.site.resolvePlayUrlsForRecoveryRaw(
        detail: room,
        quality: const LivePlayQuality(quality: 'HLS 自动 · HLS', id: 'hls:auto'),
      );
      expect(auto.urls.single, _masterUrl);
      expect(_urls(setup.http.requests), everyElement(contains('/youtubei/v1/player')));
    });

    test('recovery keeps the quality: one no longer offered, or a broadcast that ended, is an error', () async {
      final setup = _setup();
      final room = await setup.site.getRoomDetail(roomId: _live);
      await expectLater(
        setup.site.resolvePlayUrlsForRecoveryRaw(
          detail: room,
          quality: const LivePlayQuality(quality: '2160p · H264 · HLS', id: 'hls:2160:0:h264'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      final ended = _livePlayer()..['videoDetails'] = {...(_livePlayer()['videoDetails'] as Map), 'isLive': false};
      final gone = _setup(const [], [_player(_live, ended)]);
      await expectLater(
        gone.site.resolvePlayUrlsForRecoveryRaw(
          detail: room,
          quality: const LivePlayQuality(quality: '1080p · H264 · HLS', id: 'hls:1080:0:h264'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test("recovery of a room without a broadcast (a card) makes room entry's requests", () async {
      final setup = _setup(_allSamples, [_liveAs(_lofi, 'S07-watch-live')]);
      final resolution = await setup.site.resolvePlayUrlsForRecoveryRaw(
        detail: LiveRoom(platform: 'youtube', roomId: _lofi),
        quality: const LivePlayQuality(quality: 'DASH 自动 · DASH', id: 'dash:auto'),
      );
      expect(resolution.urls.single, contains('/api/manifest/dash/'));
      expect(_urls(setup.http.requests).first, 'https://www.youtube.com/channel/$_lofi/live');
    });

    test('recovery asks the player with the key of the last watch page', () async {
      final page = Fixture.load('youtube', 'S07-watch-live').body.replaceFirst(YouTubeApi.fallbackApiKey, 'OTHERKEY');
      final setup = _setup(
        ['S07-hls-live'],
        [_get('https://www.youtube.com/watch?v=$_live', page), _player(_live, _livePlayer(), key: 'OTHERKEY')],
      );
      final room = await setup.site.getRoomDetail(roomId: _live);
      await setup.site.resolvePlayUrlsForRecoveryRaw(
        detail: room,
        quality: const LivePlayQuality(quality: 'DASH 自动 · DASH', id: 'dash:auto'),
      );
      expect(setup.http.requests.where((request) => request.method == 'POST').map((request) => request.url.query), [
        'key=OTHERKEY',
        'key=OTHERKEY',
      ]);
    });
  });

  group('search (23-2)', () {
    final v3 = _legacy('S07-watch-live')['searchRooms'] as Map<String, dynamic>;

    test('a video id or video link: its player answer and updated_metadata, one card (its channel)', () async {
      for (final keyword in [
        _live,
        'https://www.youtube.com/watch?v=$_live',
        'https://youtu.be/$_live',
        'https://www.youtube.com/live/$_live',
      ]) {
        final setup = _setup();
        final rooms = await setup.site.searchRoomsWithCancellation(keyword, pageSize: 20, cancel: CancelToken());
        expect(setup.http.requests, hasLength(2), reason: '$keyword (3.x: watch page and player)');
        final want = (_result(v3[keyword])! as List).cast<Map<String, dynamic>>();
        expect(rooms, hasLength(want.length));
        _expectRoom(rooms.single, want.single, changed: _refreshed, reason: keyword);
        expect(rooms.single.data, isNull);
        expect(setup.site.supportsSearchPaginationFor(keyword), keyword == _live, reason: keyword);
      }
    });

    test('a handle or channel link: resolve_url of its /live path, the player answer, updated_metadata', () async {
      final expected = _legacy('S07-channel-live')['searchRooms'] as Map<String, dynamic>;
      for (final key in ['@LofiGirl', 'https://www.youtube.com/@LofiGirl', 'https://www.youtube.com/@LofiGirl/live']) {
        final setup = _setup();
        final rooms = await setup.site.searchRooms(key);
        expect(setup.http.requests, hasLength(3), reason: '$key (3.x: /live page, watch page, player)');
        expect(
          jsonDecode(utf8.decode(setup.http.requests.first.body!)),
          YouTubeApi.resolveBody('https://www.youtube.com/@LofiGirl/live'),
        );
        _expectRoom(rooms.single, (_result(expected[key])! as List).single, changed: _refreshed, reason: key);
        expect(setup.site.supportsSearchPaginationFor(key), isFalse);
      }
      final byId = _setup();
      for (final key in [_lofi, 'https://www.youtube.com/channel/$_lofi']) {
        expect((await byId.site.searchRooms(key)).single.roomId, _lofi, reason: key);
      }
    });

    test('a channel that is not live is a card with its name (3.x: nothing)', () async {
      final expected = _legacy('S08-channel-offline')['searchRooms'];
      expect(_result(expected), isEmpty);
      final setup = _setup();
      final rooms = await setup.site.searchRooms('https://www.youtube.com/channel/$_beast');
      expect(_urls(setup.http.requests), [
        'https://www.youtube.com/youtubei/v1/navigation/resolve_url?prettyPrint=false',
        'https://www.youtube.com/feeds/videos.xml?channel_id=$_beast',
      ]);
      expect(
        (rooms.single.roomId, rooms.single.nick, rooms.single.effectiveLiveStatus),
        (_beast, 'MrBeast', LiveStatus.offline),
      );
    });

    test('an unknown handle or missing video gives nothing; an ordinary one its channel', () async {
      final setup = _setup(_allSamples, [
        _resolvedOffline(_rick),
        _api('search', YouTubeApi.searchBody('HelloWorld1'), _searchAnswer([])),
        _player('HelloWorld1', Fixture.load('youtube', 'S12-player-missing').body),
      ]);
      expect(await setup.site.searchRooms('@zzzzqqqqnotexist987654'), isEmpty);
      expect(_result(_legacy('S12-watch-missing')['searchRooms']), isA<Map<String, dynamic>>(), reason: '3.x failed');
      final ordinary = await setup.site.searchRooms(_video);
      expect((ordinary.single.roomId, ordinary.single.effectiveLiveStatus), (_rick, LiveStatus.offline));
      setup.http.requests.clear();
      expect(await setup.site.searchRooms('HelloWorld1'), isEmpty);
      expect(_urls(setup.http.requests), [
        YouTubeApi.playerUrl(YouTubeApi.fallbackApiKey).toString(),
        'https://www.youtube.com/youtubei/v1/search?prettyPrint=false',
      ], reason: 'a bare token that names no video is a keyword');
    });

    test("keywords: YouTube's live search, page by page, one card per channel across pages", () async {
      final setup = _setup();
      final first = await setup.site.searchRooms('lofi');
      expect(first, hasLength(11));
      expect(first.first.roomId, _lofi);
      expect(setup.http.requests.single.url.toString(), 'https://www.youtube.com/youtubei/v1/search?prettyPrint=false');
      expect(jsonDecode(utf8.decode(setup.http.requests.single.body!)), YouTubeApi.searchBody('lofi'));
      final second = await setup.site.searchRooms('lofi', page: 2);
      expect(setup.http.requests, hasLength(2), reason: 'S02-p2: the continuation of page 1');
      expect(second, hasLength(14), reason: '17 channels, 3 already on page 1');
      expect({...first.map((room) => room.roomId)}.intersection({...second.map((room) => room.roomId)}), isEmpty);
      expect(setup.site.supportsSearchPaginationFor('lofi'), isTrue);
      expect(setup.site.supportsSearchPaginationFor('lofi girl'), isTrue);
      expect(setup.site.supportsSearchPaginationFor('  '), isFalse);
    });

    test('a later page needs the one before it; page 1 starts over', () async {
      final setup = _setup();
      expect(await setup.site.searchRooms('lofi', page: 2), isEmpty);
      expect(setup.http.requests, isEmpty);
      await setup.site.searchRooms('lofi');
      await setup.site.searchRooms('lofi', page: 2);
      await expectLater(setup.site.searchRooms('lofi', page: 3), throwsA(isA<StateError>()), reason: 'no sample');
      final token = (jsonDecode(utf8.decode(setup.http.requests.last.body!)) as Map<String, dynamic>)['continuation'];
      expect(token, YouTubeApi.listing(Fixture.load('youtube', 'S02-search-p2').body, search: true).next);
      expect((await setup.site.searchRooms('lofi')).first.roomId, _lofi, reason: 'a new page 1 forgets what was shown');
      final ends = _setup(const [], [
        _api('search', YouTubeApi.searchBody('last'), _searchAnswer([('bbbbbbbbbbb', _beast)])),
      ]);
      expect(await ends.site.searchRooms('last'), hasLength(1));
      expect(await ends.site.searchRooms('last', page: 2), isEmpty, reason: 'no continuation');
      expect(ends.http.requests, hasLength(1));
    });

    test('a bare name is a keyword now (3.x: the handle), and so is an 11-letter word', () async {
      final expected = _legacy('S07-channel-live')['searchRooms'] as Map<String, dynamic>;
      expect(_result(expected['LofiGirl']), hasLength(1), reason: '3.x looked up @LofiGirl');
      final setup = _setup(const [], [
        _api('search', YouTubeApi.searchBody('LofiGirl'), _searchAnswer([(_live, _lofi)])),
        _api('search', YouTubeApi.searchBody('programming'), _searchAnswer([])),
      ]);
      expect((await setup.site.searchRooms('LofiGirl')).single.roomId, _lofi);
      expect(await setup.site.searchRooms('programming'), isEmpty);
      expect(setup.http.requests, hasLength(2));
    });

    test('blank, other pages of a reference, no page size or page 0 give nothing without a request', () async {
      final setup = _setup();
      for (final key in ['$_live page 2', '$_live pageSize 0', 'blank']) {
        expect(_result(v3[key]), isEmpty, reason: key);
        expect((v3[key] as Map<String, dynamic>)['requests'], isEmpty, reason: key);
      }
      expect(await setup.site.searchRooms('@LofiGirl', page: 2), isEmpty);
      expect(await setup.site.searchRooms(_live, pageSize: 0), isEmpty);
      expect(await setup.site.searchRooms('lofi', page: 0), isEmpty);
      expect(await setup.site.searchRooms('  '), isEmpty);
      expect(await setup.site.searchRooms(_live, page: 2), isEmpty, reason: 'no keyword search of it yet');
      expect(setup.http.requests, isEmpty);
    });

    test('a cancelled search sends nothing; the token reaches the requests', () async {
      final setup = _setup();
      final cancel = CancelToken()..cancel();
      await expectLater(setup.site.searchRoomsCancellable(_live, cancel: cancel), _cancelled);
      await expectLater(setup.site.searchRoomsCancellable('lofi', cancel: cancel), _cancelled);
      expect(setup.http.requests, isEmpty);
      final running = CancelToken();
      await setup.site.searchRoomsCancellable(_live, cancel: running);
      await setup.site.searchRoomsCancellable('lofi', cancel: running);
      await setup.site.searchRoomsCancellable('@LofiGirl', cancel: running);
      expect(setup.http.requests.every((request) => identical(request.cancel, running)), isTrue);
    });

    test('other failures are not "nothing found"', () async {
      final setup = _setup(const [], [
        _player(_live, '', status: 429),
        _api('search', YouTubeApi.searchBody('lofi'), 'x', status: 403),
      ]);
      await expectLater(setup.site.searchRooms(_live), throwsA(isA<RateLimited>()));
      await expectLater(setup.site.searchRooms('lofi'), throwsA(isA<RiskControl>()));
    });
  });

  group('catalog (23-2)', () {
    test('the "Live" destination is the recommendations: one page, one card per channel', () async {
      final catalog = _legacy('S07-watch-live')['catalog'] as Map<String, dynamic>;
      expect(_result(catalog['getRecommendRooms']), isEmpty, reason: '3.x had none');
      final setup = _setup();
      final page = await setup.site.getDirectoryPage();
      expect(_urls(setup.http.requests), ['https://www.youtube.com/youtubei/v1/browse?prettyPrint=false']);
      expect(jsonDecode(utf8.decode(setup.http.requests.single.body!)), YouTubeApi.browseBody());
      expect((page.rooms.length, page.page, page.hasMore), (26, 1, false));
      expect(page.rooms.every((room) => room.isLiveNow && YouTubeApi.isChannelId(room.roomId)), isTrue);
      expect(await setup.site.getRecommendRooms(), hasLength(26));
      expect(await setup.site.getRecommendRooms(page: 0), hasLength(26));
      setup.http.requests.clear();
      final next = await setup.site.getDirectoryPage(page: 2);
      expect(next.rooms, isEmpty);
      expect(next.hasMore, isFalse);
      expect(await setup.site.getRecommendRooms(page: 2), isEmpty);
      expect(setup.http.requests, isEmpty);
    });

    test('no categories; a page below 1 or an area is a caller error; notice key, name, no chat yet', () async {
      final catalog = _legacy('S07-watch-live')['catalog'] as Map<String, dynamic>;
      final setup = _setup();
      expect(await setup.site.getCategories(1, 30), isEmpty);
      expect(() => setup.site.getDirectoryPage(page: 0), throwsRangeError);
      expect(
        () => setup.site.getDirectoryPage(
          category: const LiveArea(platform: 'youtube', areaId: 'x'),
        ),
        throwsArgumentError,
      );
      expect(setup.http.requests, isEmpty);
      expect(setup.site.directoryNoticeKey, catalog['directoryNoticeKey']);
      expect((setup.site.id, setup.site.name), (catalog['id'], catalog['name']));
    });
  });

  group('errors', () {
    test('transport failures are NetworkFailure; a cancellation stays a cancellation', () async {
      for (final id in [_live, _lofi]) {
        await expectLater(
          YouTubeSite(_Failing(TransportReason.timeout)).getRoomDetail(roomId: id),
          throwsA(isA<NetworkFailure>()),
        );
        await expectLater(
          YouTubeSite(_Failing(TransportReason.cancelled)).getRoomDetailForRefresh(roomId: id),
          _cancelled,
        );
      }
    });

    test("3.x's status rules on the watch page, the player, the channel page and resolve_url", () async {
      for (final (status, matcher) in [
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (503, isA<NetworkFailure>()),
        (400, isA<ApiChanged>()),
      ]) {
        final page = _setup(const [], [_get('https://www.youtube.com/watch?v=$_live', 'x', status: status)]);
        await expectLater(page.site.getRoomDetail(roomId: _live), throwsA(matcher), reason: 'page $status');
        final player = _setup(['S07-watch-live'], [_player(_live, 'x', status: status)]);
        await expectLater(player.site.getRoomDetail(roomId: _live), throwsA(matcher), reason: 'player $status');
        final channel = _setup(const [], [_get(YouTubeApi.liveUrl(_lofi), 'x', status: status)]);
        await expectLater(channel.site.getRoomDetail(roomId: _lofi), throwsA(matcher), reason: 'channel $status');
        final resolve = _setup(const [], [
          _api('navigation/resolve_url', YouTubeApi.resolveBody(YouTubeApi.liveUrl(_lofi)), 'x', status: status),
        ]);
        await expectLater(
          resolve.site.getRoomDetailForRefresh(roomId: _lofi),
          throwsA(matcher),
          reason: 'resolve $status',
        );
      }
    });

    test('a failed viewer count leaves the viewers empty, not the refresh failed', () async {
      final setup = _setup(
        ['S03-resolve-channel-live', 'S07-player-live'],
        [_api('updated_metadata', YouTubeApi.metadataBody(_live), '', status: 500)],
      );
      final room = await setup.site.getRoomDetailForRefresh(roomId: _lofi);
      expect(room.isLiveNow, isTrue);
      expect(room.onlineViewers, isEmpty);
    });
  });

  group('links', () {
    LinkParser parser(ReplayHttp http) => LinkParser(SiteRegistry({'youtube': () => YouTubeSite(http)}), http);

    test('video links name the video and channel/UC… links the channel, without a request', () async {
      final setup = _setup();
      final links = parser(setup.http);
      for (final url in [
        'https://www.youtube.com/watch?v=$_live&t=42s',
        'https://youtu.be/$_live?si=x',
        'https://m.youtube.com/live/$_live',
        'https://www.youtube-nocookie.com/embed/$_live',
      ]) {
        expect(setup.site.roomIdFromUrl(url), _live, reason: url);
        expect(await links.parse('看 $url 吧'), const RoomLink('youtube', _live), reason: url);
      }
      for (final url in [
        'https://www.youtube.com/channel/$_lofi',
        'https://www.youtube.com/channel/$_lofi/live',
        'https://www.youtube.com/embed/live_stream?channel=$_lofi',
      ]) {
        expect(setup.site.roomIdFromUrl(url), _lofi, reason: url);
        expect(setup.site.needsResolving(url), isFalse, reason: url);
        expect(await links.parse(url), const RoomLink('youtube', _lofi), reason: url);
      }
      expect(setup.site.roomIdFromUrl('https://www.youtube.com/shorts/$_live'), isNull);
      expect(setup.site.roomIdFromUrl('https://www.youtube.com/@LofiGirl'), isNull);
      expect(setup.http.requests, isEmpty);
    });

    test('a handle or custom-name link is its channel: one resolve_url request (3.x: the /live page)', () async {
      for (final (url, sample) in [
        ('https://www.youtube.com/@LofiGirl', 'S03-resolve-handle'),
        ('https://www.youtube.com/@LofiGirl/live', 'S03-resolve-handle'),
        ('https://www.youtube.com/c/LofiGirl', 'S03-resolve-custom'),
      ]) {
        final setup = _setup([sample]);
        final links = parser(setup.http);
        expect(setup.site.needsResolving(url), isTrue);
        expect(links.containsSupportedLink('看 $url 吧'), isTrue);
        expect(await links.parse('看 $url 吧'), const RoomLink('youtube', _lofi), reason: url);
        final request = setup.http.requests.single;
        expect(
          (request.method, '${request.url}'),
          ('POST', 'https://www.youtube.com/youtubei/v1/navigation/resolve_url?prettyPrint=false'),
        );
        expect(request.followRedirects, isFalse);
        expect(request.headers['cookie'], 'SOCS=CAI');
      }
    });

    test('an unknown handle leads nowhere', () async {
      final missing = Fixture.load('youtube', 'S03-resolve-handle-missing');
      final setup = _setup(const [], [
        _api(
          'navigation/resolve_url',
          YouTubeApi.resolveBody('https://www.youtube.com/@zzzzqqqqnotexist987654'),
          missing.body,
          status: missing.status,
        ),
      ]);
      expect(await parser(setup.http).parse('https://www.youtube.com/@zzzzqqqqnotexist987654/live'), isNull);
      expect(setup.http.requests, hasLength(1));
    });

    test('other links are not YouTube rooms', () {
      final site = _setup().site;
      for (final url in [
        'https://www.youtube.com/results?search_query=lofi',
        'https://evilyoutube.com/watch?v=$_live',
        'https://www.twitch.tv/lofigirl',
      ]) {
        expect(site.roomIdFromUrl(url), isNull, reason: url);
        expect(site.needsResolving(url), isFalse, reason: url);
      }
    });
  });

  group('follows and the M9 migration (23-1)', () {
    test('a refresh merged into an entered room keeps its sources; the identity is the channel', () async {
      final setup = _setup(_allSamples, [_liveAs(_lofi, 'S07-watch-live')]);
      final entered = await setup.site.getRoomDetail(roomId: _lofi);
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: _lofi);
      final merged = entered.mergeFrom(refreshed);
      expect(merged.data, isA<YouTubeRoomData>());
      expect(merged.identityKey, 'youtube:$_lofi');
      expect((merged.avatar, merged.area, merged.startedAt), (_lofiAvatar, 'Music', entered.startedAt));
      expect(merged.onlineViewers, '1331');
      final stored = LiveRoom.fromJson(jsonDecode(jsonEncode(entered.toJson())) as Map<String, Object?>);
      expect(stored.hasSameIdentity(refreshed), isTrue);
      expect(LiveRoom(platform: 'youtube', roomId: _lofi.toLowerCase()).hasSameIdentity(stored), isFalse);
    });

    test('resolveRoomId: a channel as it is; a video id its channel (one player request)', () async {
      final setup = _setup();
      expect(await setup.site.resolveRoomId(_lofi), _lofi);
      expect(setup.http.requests, isEmpty);
      expect(await setup.site.resolveRoomId(' $_live '), _lofi);
      expect(await setup.site.resolveRoomId(_ended), _minecraft);
      expect(await setup.site.resolveRoomId(_video), _rick, reason: 'an ordinary video too');
      expect(setup.http.requests, hasLength(3));
      expect(setup.http.requests.every((request) => '${request.url}'.contains('/youtubei/v1/player')), isTrue);
      await expectLater(setup.site.resolveRoomId(_missing), throwsA(isA<NotFound>()));
      await expectLater(setup.site.resolveRoomId('@LofiGirl'), throwsA(isA<NotFound>()));
    });

    test('a 3.x follow (a video id) is merged only once migrated', () async {
      final setup = _setup();
      final expected = _result(legacy['getRoomDetailForRefresh'])! as Map<String, dynamic>;
      final stored = LiveRoom.fromJson({...expected, 'roomId': _live});
      final refreshed = await setup.site.getRoomDetailForRefresh(roomId: stored.roomId);
      expect(refreshed.roomId, _lofi);
      expect(identical(stored.mergeFrom(refreshed), stored), isTrue, reason: 'identities differ before M9');
      final migrated = LiveRoom.fromJson({
        ...stored.toJson(),
        'roomId': await setup.site.resolveRoomId(stored.roomId),
        'link': YouTubeApi.roomLink(_lofi),
      });
      final merged = migrated.mergeFrom(refreshed);
      expect((merged.roomId, merged.onlineViewers, merged.title), (_lofi, '1331', refreshed.title));
    });
  });
}
