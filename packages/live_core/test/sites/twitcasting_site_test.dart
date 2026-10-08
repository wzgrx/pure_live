// TwitcastingSite over the recorded TwitCasting responses (ReplayHttp) and
// a few synthetic ones: the catalog, the one-window lists and their paging
// (3.x's test/twitcasting_directory_paging_test.dart, adapter part, and the
// 30 s snapshots of M4.U), search and channel-link search, the two-step room
// and the one-request refresh (12-2), restricted rooms, streams and
// recovery, cancellation, links and the error mapping (3.x's
// test/twitcasting_adapter_test.dart).
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/twitcasting';

const _top = 'https://frontendapi.twitcasting.tv/top/category';

ReplaySample _synthetic(String url, Object body, {int status = 200, Map<String, List<String>> headers = const {}}) =>
    ReplaySample(
      method: 'GET',
      url: Uri.parse(url),
      status: status,
      headers: headers,
      bytes: utf8.encode(body is String ? body : jsonEncode(body)),
    );

String _stream(String channel) => 'https://twitcasting.tv/streamserver.php?target=$channel&mode=client&player=pc_web';

final class _Failing implements LiveHttp {
  new(this.reason);

  final TransportReason reason;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    throw TransportFailure('twitcasting', reason, 'test');
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async => throw TransportFailure('twitcasting', reason, 'test');

  @override
  void close() {}
}

typedef _Setup = ({TwitcastingSite site, ReplayHttp http});

_Setup _setup(List<String> samples, {List<ReplaySample> extra = const [], DateTime Function()? now}) {
  final http = ReplayHttp([...extra, for (final name in samples) ReplaySample.load('$_root/$name')]);
  return (site: TwitcastingSite(http, now: now), http: http);
}

/// A clock tests move by hand.
final class _Clock {
  DateTime now = DateTime.utc(2026, 9, 29, 12);

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}

List<String> _paths(ReplayHttp http) => [for (final request in http.requests) request.url.path];

/// 3.x's paging window: 60 broadcasts of generation [generation], the first
/// a group broadcast without a viewer count.
Map<String, Object?> _window({int generation = 0}) => {
  'movies': [
    for (var i = 0; i < 60; i++)
      {
        'id': '${i + 1}',
        'title': 'Drawing',
        'telop': 'Public live',
        'live_url': '/artist${generation}_$i/movie/${i + 1}',
        'current_viewer_count': i == 0 ? null : 1000 - i,
        'thumbnail_url': '//images.twitcasting.tv/cover.jpg',
        'user_name': 'Artist $i',
        'is_live': true,
        'is_locked': false,
        'is_group': i == 0,
        'is_deleted': false,
        'user_icon_url': 'https://images.twitcasting.tv/avatar.jpg',
        'user_id': 'artist${generation}_$i',
      },
  ],
};

const _popular = LiveArea(
  platform: 'twitcasting',
  areaId: '_system_channel_popular',
  areaType: 'directory',
  areaName: 'Popular',
  typeName: 'TwitCasting',
);

const _game = LiveArea(platform: 'twitcasting', areaId: '_system_channel_12', areaType: 'directory', areaName: 'Game');

LiveRoom _card(String channel, {LiveStatus status = LiveStatus.live}) =>
    LiveRoom(roomId: channel, platform: 'twitcasting', liveStatus: status);

/// streamserver.php for [channel] naming broadcast [movie] with its tiers.
ReplaySample _live(String channel, int movie, {String host = 'edge.twitcasting.tv', List<String>? tiers}) =>
    _synthetic(_stream(channel), {
      'movie': {'id': movie, 'live': true},
      'tc-hls': {
        'streams': {
          for (final (key, tier) in [('high', '672.96'), ('medium', '671.96'), ('low', '480.64')])
            if (tiers == null || tiers.contains(key))
              key: 'https://$host/tc.livehls/v1/streams/$movie/hls/$tier/media.m3u8',
        },
      },
    });

void main() {
  test("3.x's capabilities, and lines and links", () {
    final site = TwitcastingSite(ReplayHttp(const []));
    expect(site.id, 'twitcasting');
    expect(site.name, 'TwitCasting');
    expect(site, isA<LiveSiteRoomRefresher>());
    expect(site, isA<LiveSiteRecordRoomResolver>());
    expect(site, isA<LivePlayRecoveryResolver>());
    expect(site, isA<LiveCancellableSearch>());
    expect(site, isA<LivePlayUrlResolver>());
    expect(site, isA<LiveSiteLinks>());
    expect(site, isNot(isA<LiveSiteDirectoryPager>()), reason: '3.x paged the window in its pages');
    final audience = AudiencePlatformCapability.of('twitcasting');
    expect(audience.onlineAvailableInRoomLists, isTrue);
    expect(audience.hasTotalViewers, isFalse);
  });

  group('catalog', () {
    test("the homepage, with 3.x's headers; only page 1 has it", () async {
      final setup = _setup(['S01-home']);
      final categories = await setup.site.getCategories(1, 30);
      expect(categories.single.children, hasLength(18));
      final request = setup.http.requests.single;
      expect(request.url.toString(), 'https://twitcasting.tv/');
      expect(request.site, 'twitcasting', reason: 'the app routes the platform through its proxy');
      expect(request.headers, {
        'referer': 'https://twitcasting.tv/',
        'origin': 'https://twitcasting.tv',
        'user-agent': 'Mozilla/5.0',
      });
      expect(request.headers.keys, isNot(contains('cookie')));
      expect(await setup.site.getCategories(2, 30), isEmpty);
      expect(setup.http.requests, hasLength(1));
    });

    test('a failing request fails the catalog', () async {
      final setup = _setup([], extra: [_synthetic('https://twitcasting.tv/', '', status: 503)]);
      await expectLater(setup.site.getCategories(1, 30), throwsA(isA<NetworkFailure>()));
      await expectLater(
        TwitcastingSite(_Failing(TransportReason.connect)).getCategories(1, 30),
        throwsA(isA<NetworkFailure>()),
      );
    });
  });

  group('lists', () {
    test('the popular page: the whole window in one request; nothing past it', () async {
      final setup = _setup(['S02-top-all']);
      final rooms = await setup.site.getRecommendRooms(pageSize: 60);
      expect(rooms, hasLength(45));
      expect(setup.http.requests.single.url.queryParameters, {'id': '', 'count': '60'});
      expect(await setup.site.getRecommendRooms(page: 2, pageSize: 60), isEmpty);
      expect(setup.http.requests, hasLength(1), reason: 'no request for a page the site does not have');
    });

    test('an area asks for its tab key', () async {
      final setup = _setup(['S02-top-game']);
      expect(await setup.site.getCategoryRooms(_game, pageSize: 60), hasLength(56));
      expect(setup.http.requests.single.url.host, 'frontendapi.twitcasting.tv');
      expect(setup.http.requests.single.url.queryParameters, {'id': '_system_channel_12', 'count': '60'});
    });

    test("3.x's paging: one fixed window, filtered, whatever the page size", () async {
      // 3.x test/twitcasting_directory_paging_test.dart: its pages ask for
      // page 1 of 60 (an 80-card page too) and cut it themselves.
      var generation = 0;
      ReplayHttp http() => ReplayHttp([
        _synthetic('$_top?id=&count=60', _window(generation: generation)),
        _synthetic('$_top?id=_system_channel_popular&count=60', _window(generation: generation)),
      ]);
      final first = http();
      final site = TwitcastingSite(first);
      final window = await site.getRecommendRooms(pageSize: 60);
      expect(window, hasLength(59));
      expect(window.map((room) => room.roomId).toSet(), hasLength(59));
      expect(window.map((room) => room.roomId), contains('artist0_59'));
      expect(await site.getRecommendRooms(page: 2, pageSize: 60), isEmpty);
      expect(first.requests.single.url.queryParameters['count'], '60');
      final area = await site.getCategoryRooms(_popular, pageSize: 60);
      expect(area, hasLength(59));
      expect(first.requests.last.url.queryParameters, {'id': '_system_channel_popular', 'count': '60'});
      expect(first.requests, hasLength(2));

      generation++;
      final refreshed = TwitcastingSite(http());
      expect(
        (await refreshed.getRecommendRooms(pageSize: 60)).every((room) => room.roomId.startsWith('artist1_')),
        isTrue,
        reason: 'a refresh is a new window',
      );
    });

    test('pages cut from the window: a later page without an answer asks for the whole window (3.x)', () async {
      final http = ReplayHttp([_synthetic('$_top?id=&count=60', _window())]);
      final site = TwitcastingSite(http);
      expect((await site.getRecommendRooms(page: 2)).first.roomId, 'artist0_30');
      expect(await site.getRecommendRooms(page: 3), isEmpty);
      expect(http.requests, hasLength(1));
    });

    test("later pages share page 1's answer for 30 s; page 1 always asks anew (unified paging rule)", () async {
      final clock = _Clock();
      var generation = 0;
      final http = _SwappableHttp(
        () => [
          _synthetic('$_top?id=&count=60', _window(generation: generation)),
          _synthetic('$_top?id=_system_channel_popular&count=60', _window(generation: generation)),
        ],
      );
      final site = TwitcastingSite(http, now: clock.call);
      expect((await site.getRecommendRooms()).first.roomId, 'artist0_1');
      generation++;
      clock.advance(const Duration(seconds: 29));
      expect((await site.getRecommendRooms(page: 2)).first.roomId, 'artist0_30', reason: 'the same answer');
      expect(http.paths, hasLength(1));
      expect((await site.getCategoryRooms(_popular, page: 2)).first.roomId, 'artist1_30', reason: 'another list');
      expect(http.paths, hasLength(2));
      clock.advance(const Duration(seconds: 1));
      expect((await site.getRecommendRooms(page: 2)).first.roomId, 'artist1_30', reason: '30 s old: asked again');
      expect(http.paths, hasLength(3));
      generation++;
      expect((await site.getRecommendRooms()).first.roomId, 'artist2_1', reason: 'page 1 (a pull to refresh)');
      expect(http.paths, hasLength(4));
    });

    test('a failed answer is not kept; list cards carry their start time and restriction', () async {
      final clock = _Clock()..now = DateTime.utc(2026, 9, 27, 18, 1, 57, 219);
      var samples = [_synthetic('$_top?id=&count=60', '', status: 503)];
      final http = _SwappableHttp(() => samples);
      final site = TwitcastingSite(http, now: clock.call);
      await expectLater(site.getRecommendRooms(), throwsA(isA<NetworkFailure>()));
      samples = [ReplaySample.load('$_root/S02-top-all')];
      final rooms = await site.getRecommendRooms(page: 2, pageSize: 20);
      expect(rooms, hasLength(20));
      expect(http.paths, hasLength(2), reason: 'the failure kept nothing');
      final all = await site.getRecommendRooms(pageSize: 60);
      final nabo = all.singleWhere((room) => room.roomId == 'nabo66game');
      expect(nabo.startedAt, DateTime.utc(2026, 9, 27, 14, 26, 34));
      expect(all.map((room) => room.restriction).toSet(), {LiveRestriction.none});
    });

    test("another platform's area, a bad key or a bad page are caller errors without a request (3.x)", () async {
      final setup = _setup([]);
      for (final area in [
        const LiveArea(platform: 'other', areaType: 'directory', areaId: 'x'),
        const LiveArea(platform: 'twitcasting', areaType: 'genre', areaId: 'x'),
        const LiveArea(platform: 'twitcasting', areaType: 'directory', areaId: '../private'),
        const LiveArea(platform: 'twitcasting', areaType: 'directory'),
      ]) {
        await expectLater(setup.site.getCategoryRooms(area), throwsArgumentError, reason: area.toString());
      }
      for (final (page, size) in [(0, 30), (10001, 30), (1, 0), (1, 61)]) {
        await expectLater(setup.site.getRecommendRooms(page: page, pageSize: size), throwsArgumentError);
      }
      expect(setup.http.requests, isEmpty);
    });
  });

  group('search', () {
    test("the website's text search in English, asked once; later pages are cut from it (12-4)", () async {
      final setup = _setup(['S03-search']);
      final rooms = await setup.site.searchRooms(' game ', pageSize: 20);
      expect(rooms, hasLength(15));
      expect(rooms[2].restriction, LiveRestriction.private, reason: '12-5');
      final request = setup.http.requests.single;
      expect(request.url.host, 'search.twitcasting.tv');
      expect(request.url.pathSegments, ['search', 'text', 'game']);
      expect(request.url.queryParameters, {'hl': 'en'});
      expect(await setup.site.searchRooms('game', page: 2, pageSize: 20), isEmpty);
      expect(await setup.site.searchRooms('game', page: 3, pageSize: 20), isEmpty);
      expect(setup.http.requests, hasLength(1), reason: '3.x asked again for pages 2 and 3');
      expect(await setup.site.searchRooms('game', page: 4, pageSize: 20), isEmpty);
      expect(setup.http.requests, hasLength(1), reason: 'past the 50 rows the page can hold');
    });

    test('search pages share one answer for 30 s, per keyword; page 1 asks anew', () async {
      final clock = _Clock();
      final setup = _setup(
        [],
        extra: [
          _synthetic('https://search.twitcasting.tv/search/text/game?hl=en', _searchPage(40)),
          _synthetic('https://search.twitcasting.tv/search/text/talk?hl=en', _searchPage(3)),
        ],
        now: clock.call,
      );
      final page1 = await setup.site.searchRooms('game', pageSize: 10);
      expect(page1.first.roomId, 'c:artist0');
      clock.advance(const Duration(seconds: 20));
      expect((await setup.site.searchRooms('game', page: 2, pageSize: 10)).first.roomId, 'c:artist10');
      expect((await setup.site.searchRooms('game', page: 4, pageSize: 10)).last.roomId, 'c:artist39');
      expect(setup.http.requests, hasLength(1));
      expect(await setup.site.searchRooms('talk', page: 2, pageSize: 2), hasLength(1), reason: 'another keyword');
      expect(setup.http.requests, hasLength(2));
      clock.advance(const Duration(seconds: 10));
      await setup.site.searchRooms('game', page: 3, pageSize: 10);
      expect(setup.http.requests, hasLength(3), reason: '30 s old: asked again');
      await setup.site.searchRooms('game', pageSize: 10);
      expect(setup.http.requests, hasLength(4), reason: 'page 1 always asks');
    });

    test('keywords are one path segment, encoded', () async {
      final http = ReplayHttp([
        _synthetic(
          'https://search.twitcasting.tv/search/text/a%20&%20b%2F%E9%9B%91?hl=en',
          '<div id="tw-search-result-live"></div>',
        ),
      ]);
      expect(await TwitcastingSite(http).searchRooms('a & b/雑'), isEmpty);
      expect(http.requests.single.url.pathSegments, ['search', 'text', 'a & b/雑']);
    });

    test('a blank keyword finds nothing; bad pages and long keywords are caller errors, without a request', () async {
      final setup = _setup([]);
      expect(await setup.site.searchRooms('  '), isEmpty);
      for (final (page, size) in [(0, 20), (10001, 20), (1, 0), (1, 51)]) {
        await expectLater(setup.site.searchRooms('t', page: page, pageSize: size), throwsArgumentError);
      }
      await expectLater(setup.site.searchRooms('x' * 101), throwsArgumentError);
      expect(setup.http.requests, isEmpty);
    });

    test('a channel link finds that channel, offline too, without reading its stale streams (3.x)', () async {
      final setup = _setup(['S04-page-offline', 'S05-stream-offline']);
      final rooms = await setup.site.searchRooms('https://twitcasting.tv/twitcasting_jp?ref=share');
      expect(rooms.single.roomId, 'twitcasting_jp');
      expect(rooms.single.isExplicitlyOfflineNow, isTrue);
      expect((rooms.single.data! as TwitcastingRoomData).streams, isEmpty);
      expect(_paths(setup.http), ['/twitcasting_jp', '/streamserver.php']);
      expect(await setup.site.searchRooms('https://twitcasting.tv/twitcasting_jp', page: 2), isEmpty);
      expect(await setup.site.searchRooms('https://twitcasting.tv/twitcasting_jp/movie/42'), isEmpty);
      expect(await setup.site.searchRooms('ftp://twitcasting.tv/twitcasting_jp'), isEmpty);
      expect(setup.http.requests, hasLength(2));
    });

    test('a live channel link: the room even when its tiers are broken (3.x)', () async {
      final setup = _setup(
        ['S04-page-live'],
        extra: [
          _synthetic(_stream('nabo66game'), {
            'movie': {'id': 42, 'live': true},
            'tc-hls': 'stale',
          }),
        ],
      );
      final room = (await setup.site.searchRooms('http://www.twitcasting.tv/Nabo66game/')).single;
      expect(room.roomId, 'nabo66game');
      expect(room.isLiveNow, isTrue);
    });

    test('an unknown channel finds nothing: one request, sent home (3.x failed as schema)', () async {
      final setup = _setup(['S04-page-notfound', 'S05-stream-notfound']);
      expect(await setup.site.searchRooms('https://twitcasting.tv/zxqvnochannelfixture'), isEmpty);
      expect(setup.http.requests.single.followRedirects, isFalse);
      final missing = _setup([], extra: [_synthetic('https://twitcasting.tv/fixture_artist', '', status: 404)]);
      expect(await missing.site.searchRooms('https://twitcasting.tv/fixture_artist'), isEmpty);
    });

    test('cancellation reaches the request; a cancelled search sends nothing (3.x)', () async {
      final setup = _setup(['S03-search']);
      final token = CancelToken();
      expect(await setup.site.searchRoomsCancellable('game', pageSize: 20, cancel: token), hasLength(15));
      expect(setup.http.requests.single.cancel, same(token));
      token.cancel();
      await expectLater(
        setup.site.searchRoomsCancellable('game', cancel: token),
        throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
      );
      await expectLater(
        setup.site.searchRoomsCancellable('game', page: 2, pageSize: 5, cancel: token),
        throwsA(isA<TransportFailure>()),
        reason: 'not served from the kept answer either',
      );
      await expectLater(
        setup.site.searchRoomsCancellable('https://twitcasting.tv/twitcasting_jp', cancel: token),
        throwsA(isA<TransportFailure>()),
      );
      expect(setup.http.requests, hasLength(1));
    });

    test('an answer after cancellation is dropped', () async {
      final token = CancelToken();
      final http = _CancellingHttp(token, ReplayHttp.fixtures(_root, ['S03-search']));
      await expectLater(
        TwitcastingSite(http).searchRoomsCancellable('game', cancel: token),
        throwsA(isA<TransportFailure>()),
      );
      expect(http.requests, 1);
    });
  });

  group('rooms', () {
    test('room entry and recording: the channel page (redirects not followed), then streamserver.php', () async {
      final setup = _setup(['S04-page-live', 'S05-stream-live']);
      final rooms = [
        await setup.site.getRoomDetail(roomId: 'nabo66game'),
        await setup.site.getRoomDetailForRecording(roomId: 'nabo66game'),
      ];
      expect(_paths(setup.http), [
        for (var i = 0; i < 2; i++) ...['/nabo66game', '/streamserver.php'],
      ]);
      final [page, stream, ...] = setup.http.requests;
      expect(page.followRedirects, isFalse);
      expect(stream.url.queryParameters, {'target': 'nabo66game', 'mode': 'client', 'player': 'pc_web'});
      for (final room in rooms) {
        expect(room.isLiveNow, isTrue);
        expect(room.title, 'クラッシュバンディクー３', reason: 'the telop (12-1)');
        expect(room.startedAt, DateTime.utc(2026, 9, 27, 14, 26, 34));
        expect(room.restriction, LiveRestriction.none);
        expect((room.data! as TwitcastingRoomData).movieId, 841525457);
        expect(room.danmakuData, isA<TwitcastingDanmakuArgs>().having((args) => args.movieId, 'movie', 841525457));
      }
    });

    test('a follow refresh and the live state ask streamserver.php alone (12-2)', () async {
      final setup = _setup(['S04-page-live', 'S05-stream-live']);
      final refresh = await setup.site.getRoomDetailForRefresh(roomId: ' Nabo66game ');
      expect(_paths(setup.http), ['/streamserver.php'], reason: 'about 1 KB instead of the 110 KB page');
      expect(setup.http.requests.single.url.queryParameters['target'], 'nabo66game');
      expect(refresh.roomId, 'Nabo66game');
      expect(refresh.userId, 'nabo66game');
      expect(refresh.link, 'https://twitcasting.tv/nabo66game');
      expect(refresh.isLiveNow, isTrue);
      expect([refresh.title, refresh.nick, refresh.avatar, refresh.cover], everyElement(isEmpty));
      expect((refresh.data! as TwitcastingRoomData).movieId, 841525457);
      expect(await setup.site.getLiveStatus(roomId: 'nabo66game'), isTrue);
      expect(_paths(setup.http), ['/streamserver.php', '/streamserver.php']);
      final entered = await setup.site.getRoomDetail(roomId: 'nabo66game');
      final follow = entered.mergeFrom(refresh);
      expect((follow.title, follow.nick, follow.startedAt), (entered.title, '山本', entered.startedAt));
      final qualities = await setup.site.getPlayQualities(detail: follow);
      expect(qualities, hasLength(3));
      expect(setup.http.requests, hasLength(4), reason: 'the refreshed broadcast plays without a request');
    });

    test('the room keeps the id it was asked for; requests use the lower-case channel', () async {
      final setup = _setup(['S04-page-live', 'S05-stream-live']);
      final room = await setup.site.getRoomDetail(roomId: ' Nabo66game ');
      expect(room.roomId, 'Nabo66game');
      expect(room.userId, 'nabo66game');
      expect(room.link, 'https://twitcasting.tv/nabo66game');
      expect(_paths(setup.http), ['/nabo66game', '/streamserver.php']);
    });

    test('an offline channel: offline, with the page filled in; the refresh is offline too', () async {
      final setup = _setup(['S04-page-offline', 'S05-stream-offline']);
      final room = await setup.site.getRoomDetail(roomId: 'twitcasting_jp');
      expect(room.effectiveLiveStatus, LiveStatus.offline);
      expect(room.nick, 'ツイキャス公式');
      expect((room.startedAt, room.restriction, room.danmakuData), (null, null, null));
      final refresh = await setup.site.getRoomDetailForRefresh(roomId: 'twitcasting_jp');
      expect(refresh.effectiveLiveStatus, LiveStatus.offline);
      expect(await setup.site.getLiveStatus(roomId: 'twitcasting_jp'), isFalse);
    });

    test('a private broadcast from search: offline in the room, not played from its card', () async {
      final setup = _setup(['S03-search-private', 'S04-page-private', 'S05-stream-private']);
      final card = (await setup.site.searchRooms('弾き語り', pageSize: 50)).singleWhere((room) => room.isRestricted);
      expect(
        (card.roomId, card.restriction, card.isLiveNow),
        ('g:117931547061051040135', LiveRestriction.private, true),
      );
      await expectLater(
        setup.site.getPlayQualities(detail: card),
        throwsA(isA<StreamUnavailable>().having((error) => '$error', 'text', contains('private'))),
      );
      expect(setup.http.requests, hasLength(1), reason: 'no request for a card known to be private');
      final room = await setup.site.getRoomDetail(roomId: card.roomId);
      expect(room.effectiveLiveStatus, LiveStatus.offline, reason: 'anonymous clients see it as offline');
      final follow = card.mergeFrom(await setup.site.getRoomDetailForRefresh(roomId: card.roomId));
      expect((follow.effectiveLiveStatus, follow.restriction), (LiveStatus.offline, null));
    });

    test('a card marked private but refreshed live plays: the carried broadcast is the newer answer', () async {
      final setup = _setup(['S05-stream-live']);
      final card = LiveRoom(
        roomId: 'nabo66game',
        platform: 'twitcasting',
        liveStatus: LiveStatus.live,
        restriction: LiveRestriction.private,
      );
      final follow = card.mergeFrom(await setup.site.getRoomDetailForRefresh(roomId: 'nabo66game'));
      expect(follow.restriction, LiveRestriction.private, reason: 'kept while the state is the same (M2.1)');
      expect(await setup.site.getPlayQualities(detail: follow), hasLength(3));
      expect(setup.http.requests, hasLength(1));
    });

    test('a locked list card is not played, without a request', () async {
      final setup = _setup([]);
      final card = LiveRoom(
        roomId: 'locked',
        platform: 'twitcasting',
        liveStatus: LiveStatus.live,
        restriction: LiveRestriction.password,
      );
      await expectLater(setup.site.getPlayQualities(detail: card), throwsA(isA<StreamUnavailable>()));
      expect(setup.http.requests, isEmpty);
    });

    test('an unknown channel is NotFound after one request; a non-channel id without one', () async {
      final setup = _setup(['S04-page-notfound', 'S05-stream-notfound']);
      await expectLater(setup.site.getRoomDetail(roomId: 'zxqvnochannelfixture'), throwsA(isA<NotFound>()));
      expect(setup.http.requests, hasLength(1));
      for (final id in ['', 'search', 'a/b', 'x:abc']) {
        await expectLater(setup.site.getRoomDetailForRefresh(roomId: id), throwsA(isA<NotFound>()), reason: id);
        await expectLater(setup.site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(setup.http.requests, hasLength(1));
      await expectLater(setup.site.getRoomDetailForRefresh(roomId: 'zxqvnochannelfixture'), throwsA(isA<NotFound>()));
      expect(_paths(setup.http).last, '/streamserver.php', reason: 'streamserver.php answers {}');
      final deleted = _setup(
        ['S05-stream-notfound'],
        extra: [_synthetic('https://twitcasting.tv/zxqvnochannelfixture', _pageOf('zxqvnochannelfixture'))],
      );
      await expectLater(deleted.site.getRoomDetail(roomId: 'zxqvnochannelfixture'), throwsA(isA<NotFound>()));
    });

    test('another channel stops before streamserver.php (3.x)', () async {
      final setup = _setup([], extra: [_synthetic('https://twitcasting.tv/fixture_artist', _pageOf('other'))]);
      await expectLater(setup.site.getRoomDetail(roomId: 'fixture_artist'), throwsA(isA<ApiChanged>()));
      expect(setup.http.requests, hasLength(1));
    });

    test('a secret word: live and marked password-protected, not played (3.x NeedsLogin)', () async {
      // One more request than 3.x: streamserver.php says whether it is live.
      final setup = _setup(
        [],
        extra: [
          _synthetic('https://twitcasting.tv/fixture_artist', '<p>Enter the secret word to access</p>'),
          _live('fixture_artist', 42),
        ],
      );
      final room = await setup.site.getRoomDetail(roomId: 'fixture_artist');
      expect(_paths(setup.http), ['/fixture_artist', '/streamserver.php']);
      expect((room.effectiveLiveStatus, room.restriction), (LiveStatus.live, LiveRestriction.password));
      expect(room.followGroup, FollowGroup.live);
      await expectLater(
        setup.site.getPlayQualities(detail: room),
        throwsA(isA<StreamUnavailable>().having((error) => '$error', 'text', contains('password-protected'))),
      );
      final recording = await setup.site.getRoomDetailForRecording(roomId: 'fixture_artist');
      expect(recording.restriction, LiveRestriction.password);
      expect(setup.http.requests, hasLength(4));
    });

    test('failures are failures, never an offline-looking room', () async {
      for (final (status, type) in [
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (503, isA<NetworkFailure>()),
      ]) {
        final setup = _setup(
          [],
          extra: [
            _synthetic('https://twitcasting.tv/fixture_artist', '', status: status),
            _synthetic(_stream('fixture_artist'), '', status: status),
          ],
        );
        await expectLater(setup.site.getRoomDetail(roomId: 'fixture_artist'), throwsA(type));
        await expectLater(setup.site.getRoomDetailForRefresh(roomId: 'fixture_artist'), throwsA(type));
        await expectLater(setup.site.getLiveStatus(roomId: 'fixture_artist'), throwsA(type));
      }
      final broken = _setup(
        [],
        extra: [
          _synthetic('https://twitcasting.tv/fixture_artist', _pageOf('fixture_artist')),
          _synthetic(_stream('fixture_artist'), {
            'movie': {'id': 42},
          }),
        ],
      );
      await expectLater(broken.site.getRoomDetailForRecording(roomId: 'fixture_artist'), throwsA(isA<ApiChanged>()));
      final challenge = _setup([], extra: [_synthetic('https://twitcasting.tv/fixture_artist', '{}')]);
      await expectLater(challenge.site.getRoomDetailForRecording(roomId: 'fixture_artist'), throwsA(isA<ApiChanged>()));
      final down = _Failing(TransportReason.timeout);
      await expectLater(TwitcastingSite(down).getRoomDetail(roomId: 'a'), throwsA(isA<NetworkFailure>()));
      await expectLater(
        TwitcastingSite(_Failing(TransportReason.cancelled)).getRoomDetail(roomId: 'a'),
        throwsA(isA<TransportFailure>()),
      );
    });
  });

  group('streams', () {
    test("a live room plays 3.x's tiers without a request", () async {
      final setup = _setup(['S04-page-live', 'S05-stream-live']);
      final room = await setup.site.getRoomDetail(roomId: 'nabo66game');
      final qualities = await setup.site.getPlayQualities(detail: room);
      expect(qualities.map((quality) => quality.quality), ['HLS high', 'HLS medium', 'HLS low']);
      final resolution = await setup.site.resolvePlayUrls(detail: room, quality: qualities[1]);
      expect(resolution.urls.single, contains('/streams/841525457/hls/1007.96/'));
      expect(resolution.lines.single.headers['referer'], 'https://twitcasting.tv/');
      expect(resolution.lines.single.format, StreamFormat.hls);
      expect(resolution.appliedQualityData, 'medium');
      expect(await setup.site.getPlayUrls(detail: room, quality: qualities.last), [contains('/720.64/')]);
      expect(setup.http.requests, hasLength(2), reason: 'only the detail');
    });

    test('an offline room has no stream, without a request (REG-TWITCASTING-001)', () async {
      final setup = _setup(['S04-page-offline', 'S05-stream-offline']);
      final room = await setup.site.getRoomDetail(roomId: 'twitcasting_jp');
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<StreamUnavailable>()));
      await expectLater(
        setup.site.getPlayQualities(detail: _card('twitcasting_jp', status: LiveStatus.offline)),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(setup.http.requests, hasLength(2));
    });

    test('a room without a broadcast (a list card) asks streamserver.php', () async {
      final setup = _setup(['S05-stream-live', 'S05-stream-offline']);
      final qualities = await setup.site.getPlayQualities(detail: _card('nabo66game'));
      expect(qualities, hasLength(3));
      expect(_paths(setup.http), ['/streamserver.php']);
      await expectLater(
        setup.site.getPlayQualities(detail: _card('twitcasting_jp')),
        throwsA(isA<StreamUnavailable>()),
      );
      await expectLater(setup.site.getPlayQualities(detail: _card('search')), throwsA(isA<StreamUnavailable>()));
      await expectLater(
        setup.site.getPlayQualities(
          detail: LiveRoom(roomId: 'nabo66game', platform: 'other'),
        ),
        throwsArgumentError,
      );
    });

    test('recovery asks streamserver.php again and keeps the tier asked for (3.x)', () async {
      var samples = [
        _synthetic('https://twitcasting.tv/fixture_artist', _pageOf('fixture_artist')),
        _live('fixture_artist', 42),
      ];
      final http = _SwappableHttp(() => samples);
      final site = TwitcastingSite(http);
      final room = await site.getRoomDetail(roomId: 'fixture_artist');
      final high = (await site.getPlayQualities(detail: room)).first;
      samples = [_live('fixture_artist', 43, host: 'new.twitcasting.tv')];
      final renewed = await site.resolvePlayUrlsForRecovery(detail: room, quality: high);
      expect(renewed.urls.single, 'https://new.twitcasting.tv/tc.livehls/v1/streams/43/hls/672.96/media.m3u8');
      expect(renewed.lines.single.lineId, 'new.twitcasting.tv');
      expect(renewed.appliedQualityData, 'high');
      expect(http.paths, ['/fixture_artist', '/streamserver.php', '/streamserver.php']);
      samples = [
        _live('fixture_artist', 44, tiers: ['medium', 'low']),
      ];
      await expectLater(
        site.resolvePlayUrlsForRecovery(detail: room, quality: high),
        throwsA(isA<StreamUnavailable>()),
        reason: 'never silently lowered',
      );
      expect((await site.getPlayUrls(detail: room, quality: high)).single, contains('/streams/42/'));
    });

    test('recovery of a room that went offline is StreamUnavailable', () async {
      final setup = _setup(['S04-page-live', 'S05-stream-live']);
      final room = await setup.site.getRoomDetail(roomId: 'nabo66game');
      final quality = (await setup.site.getPlayQualities(detail: room)).first;
      final offline = _setup(
        [],
        extra: [
          _synthetic(_stream('nabo66game'), {
            'movie': {'id': 841525457, 'live': false},
          }),
        ],
      );
      await expectLater(
        offline.site.resolvePlayUrlsForRecovery(detail: room, quality: quality),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('a tier the room lacks is StreamUnavailable; a broken tier is ApiChanged', () async {
      final setup = _setup(
        [],
        extra: [
          _synthetic('https://twitcasting.tv/fixture_artist', _pageOf('fixture_artist')),
          _synthetic(_stream('fixture_artist'), {
            'movie': {'id': 42, 'live': true},
            'tc-hls': {
              'streams': {'high': 'https://edge.twitcasting.tv/tc.livehls/v1/streams/999/hls/672.96/media.m3u8'},
            },
          }),
        ],
      );
      final room = await setup.site.getRoomDetail(roomId: 'fixture_artist');
      expect(room.isLiveNow, isTrue, reason: 'the room loads; the stream fails');
      await expectLater(setup.site.getPlayQualities(detail: room), throwsA(isA<ApiChanged>()));
      final live = _setup(['S04-page-live', 'S05-stream-live']);
      final detail = await live.site.getRoomDetail(roomId: 'nabo66game');
      await expectLater(
        live.site.getPlayUrls(
          detail: detail,
          quality: const LivePlayQuality(quality: 'ultra', id: 'ultra'),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
    });
  });

  group('links', () {
    final site = TwitcastingSite(ReplayHttp(const []));

    test('channel pages, with their social prefix, lower case (3.x)', () {
      // 3.x test/twitcasting_adapter_test.dart.
      for (final name in ['fixture_artist', 'c:fixture', 'g:113775126361409198504']) {
        expect(site.roomIdFromUrl('https://twitcasting.tv/$name'), name);
      }
      expect(site.roomIdFromUrl('http://www.twitcasting.tv/Fixture_Artist/?ref=x'), 'fixture_artist');
      expect(site.roomIdFromUrl('HTTPS://TWITCASTING.TV/abc'), 'abc');
      expect(site.roomIdFromUrl('https://twitcasting.tv:443/abc'), 'abc');
      for (final url in [
        'https://evil.twitcasting.tv/artist',
        'https://twitcasting.tv.evil.test/artist',
        'https://user@twitcasting.tv/artist',
        'https://twitcasting.tv:123/artist',
        'ftp://twitcasting.tv/artist',
        'https://twitcasting.tv/search',
        'https://twitcasting.tv/',
        'https://twitcasting.tv/artist/archive/',
        'https://twitcasting.tv/artist/movie/42',
        'https://twitcasting.tv/artist%2Fother',
        'https://twitcasting.tv//artist',
        'https://twitcasting.tv/%GG',
      ]) {
        expect(site.roomIdFromUrl(url), isNull, reason: url);
      }
      expect(site.needsResolving('https://twitcasting.tv/artist'), isFalse);
    });

    test('share texts resolve without a request; a movie link is not a room (REG-TWITCASTING-003)', () async {
      final http = ReplayHttp(const []);
      final parser = LinkParser(SiteRegistry({'twitcasting': () => TwitcastingSite(http)}), http);
      expect(
        await parser.parse('来看 https://twitcasting.tv/c:abzou_sub。快来'),
        const RoomLink('twitcasting', 'c:abzou_sub'),
      );
      expect(parser.containsSupportedLink('https://twitcasting.tv/nabo66game'), isTrue);
      // 3.x test/toolbox_link_detection_test.dart.
      expect(parser.containsSupportedLink('https://twitcasting.tv/artist/movie/42'), isFalse);
      expect(await parser.parse('https://twitcasting.tv/artist/movie/42'), isNull);
      expect(http.requests, isEmpty);
    });
  });
}

/// A search page with [count] live rows of `c:artist{i}` (3.x's
/// `searchHtml`).
String _searchPage(int count) =>
    '''
<div id="tw-search-result-live">
${List.generate(count, (i) => '''
<div class="tw-search-result-row">
  <a class="tw-movie-thumbnail2" href="/c:artist$i/movie/${i + 1}">
    <div class="tw-movie-thumbnail2-image-wrapper" data-can-play="true">
      <span class="tw-movie-thumbnail2-badge" data-status="live">LIVE</span>
    </div><span class="tw-movie-thumbnail-title">Stream $i</span>
  </a>
  <div class="tw-search-result-row-user-name">
    <div class="usertext"><a href="/c:artist$i"><span class="username">Artist $i</span></a></div>
  </div>
</div>''').join()}
</div><div id="tw-search-result-movie"></div>''';

/// A channel page of [channel] with 3.x's selectors (its room.html).
String _pageOf(String channel) =>
    '''
<meta name="twitter:creator" content="$channel"><meta name="twitter:title" content="Drawing">
<div class="tw-user-header" data-user-id="$channel"></div>
<span class="tw-user-nav2-name">Fixture Artist</span>''';

/// Answers from whatever [samples] gives now (a broadcast that changes
/// between requests).
final class _SwappableHttp implements LiveHttp {
  new(this.samples);

  final List<ReplaySample> Function() samples;
  final List<String> paths = [];

  @override
  Future<LiveResponse> send(LiveRequest request) {
    paths.add(request.url.path);
    return ReplayHttp(samples()).send(request);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => ReplayHttp(samples()).open(request);

  @override
  void close() {}
}

/// Cancels [token] while the request is in flight.
final class _CancellingHttp implements LiveHttp {
  new(this.token, this.inner);

  final CancelToken token;
  final LiveHttp inner;
  int requests = 0;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests++;
    final response = await inner.send(request);
    token.cancel();
    return response;
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => inner.open(request);

  @override
  void close() {}
}
