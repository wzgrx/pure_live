// TwitCasting parsing and the adapter over the recorded samples
// (spec/sites/twitcasting.md). Legacy no longer runs (ADR 0016), so the
// expectations come from the sample bodies and the spec.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

TwitcastingSite _site(List<String> samples) => TwitcastingSite(
  ReplayHttp.fixtures('../../fixtures/twitcasting', samples),
  now: () => Fixture.load('twitcasting', 'S02-top-all').capturedAt,
);

void main() {
  test('§2.1 the homepage tabs are the areas', () {
    final categories = TwitcastingParse.categories(Fixture.load('twitcasting', 'S01-home').body);
    final areas = categories.single.areas;
    expect(areas.first.id, '_system_channel_popular');
    expect(areas.first.name, 'Popular');
    expect(areas.map((a) => a.id), contains('_system_channel_12'));
    expect(areas.map((a) => a.id).toSet(), hasLength(areas.length));
  });

  group('§2.2 top windows', () {
    test('live, unlocked, single broadcasts; telop or title; viewers online', () {
      final fixture = Fixture.load('twitcasting', 'S02-top-all');
      final page = TwitcastingParse.topPage(fixture.body, now: fixture.capturedAt);
      final movies = ((jsonDecode(fixture.body) as Map)['movies'] as List).cast<Map<String, dynamic>>();
      final kept = movies.where(
        (m) => m['is_live'] == true && m['is_locked'] == false && m['is_group'] == false && m['is_deleted'] == false,
      );
      expect(page.items.map((c) => c.ref.roomId), kept.map((m) => (m['user_id'] as String).toLowerCase()));
      expect(page.items.first.title, "g:115956781845998461844's Live", reason: 'no telop: the title');
      expect(page.items.first.audience.online, kept.first['current_viewer_count']);
      expect(
        page.items.first.liveSince,
        fixture.capturedAt.subtract(Duration(seconds: kept.first['elapsed_time'] as int)),
      );
      expect(page.isLast, isTrue, reason: 'one window');
      expect(TwitcastingParse.topPage(Fixture.load('twitcasting', 'S02-top-game').body).items, isNotEmpty);
    });
  });

  test('§3 search keeps the live section only', () {
    final page = TwitcastingParse.searchPage(Fixture.load('twitcasting', 'S03-search').body);
    expect(page.items, isNotEmpty);
    expect(page.items.every((c) => c.state == LiveState.live), isTrue);
    final nabo = page.items.firstWhere((c) => c.ref.roomId == 'nabo66game');
    expect(nabo.anchorName, '山本');
    expect(nabo.title, isNotEmpty);
    expect(() => TwitcastingParse.searchPage('<html></html>'), throwsA(isA<ApiChanged>()));
  });

  group('§4 detail', () {
    test('a live channel', () {
      final detail = TwitcastingParse.detail(
        Fixture.load('twitcasting', 'S04-page-live').body,
        Fixture.load('twitcasting', 'S05-stream-live').body,
        id: 'nabo66game',
      );
      expect(detail.ref, RoomRef('twitcasting', 'nabo66game'));
      expect(detail.state, LiveState.live);
      expect(detail.card.anchorName, '山本');
      expect(detail.card.title, 'クラッシュバンディクー３', reason: 'the telop wins over "Live #id"');
      expect(detail.danmakuKeys, {'movieId': '841525457'});
      expect(detail.card.avatar, isNotNull);
    });

    test('offline: stale URLs are ignored; unknown channels are NotFound; secret words need an account', () {
      final offline = TwitcastingParse.detail(
        Fixture.load('twitcasting', 'S04-page-offline').body,
        Fixture.load('twitcasting', 'S05-stream-offline').body,
        id: 'twitcasting_jp',
      );
      expect(offline.state, LiveState.offline);
      expect(offline.danmakuKeys, isEmpty);
      expect(
        () => TwitcastingParse.streams(Fixture.load('twitcasting', 'S05-stream-offline').body, headers: const {}),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(
        () => TwitcastingParse.liveOf(Fixture.load('twitcasting', 'S05-stream-notfound').body),
        throwsA(isA<NotFound>()),
      );
      final redirect = Fixture.load('twitcasting', 'S04-page-notfound');
      expect(
        () => TwitcastingParse.detail(redirect.body, '{}', id: 'x', pageStatus: redirect.status),
        throwsA(isA<NotFound>()),
      );
      expect(
        () => TwitcastingParse.detail('Enter the secret word to access', '{}', id: 'x'),
        throwsA(isA<NeedsLogin>()),
      );
    });
  });

  test('§5 streams: high, medium, low; one HLS line each; no lease', () {
    final set = TwitcastingParse.streams(
      Fixture.load('twitcasting', 'S05-stream-live').body,
      headers: TwitcastingSite.headers,
    );
    expect(set.qualities.map((q) => q.id), ['high', 'medium', 'low']);
    expect(set.selected.id, 'high');
    final line = set.lines.single;
    expect(line.format, StreamFormat.hls);
    expect(line.url.path, '/tc.livehls/v1/streams/841525457/hls/1008.96/media.m3u8');
    expect(line.lease, isNull);
    expect(
      TwitcastingParse.streams(
        Fixture.load('twitcasting', 'S05-stream-live').body,
        headers: const {},
        wanted: 'low',
      ).lines.single.url.path,
      endsWith('/720.64/media.m3u8'),
    );
    final media = Fixture.load('twitcasting', 'S06-media');
    expect(media.body, contains('#EXT-X-MAP'), reason: 'fMP4 segments');
    final headers = (media.meta['response'] as Map)['headers'] as Map;
    expect('${headers['set-cookie']}', contains('lvhls_ssid_841525457='), reason: 'segments need this cookie');
  });

  test('§7 the comment socket URL', () {
    final url = TwitcastingParse.commentSocket(Fixture.load('twitcasting', 'S07-pubsub').body)!;
    expect(url.scheme, 'wss');
    expect(url.path, '/event.pubsub/v1/streams/841525457/events');
    expect(TwitcastingParse.commentSocket('{"url":"https://example.test"}'), isNull);
  });

  test('§1 links', () {
    expect(TwitcastingParse.channelOf('Nabo66game'), 'nabo66game');
    expect(TwitcastingParse.channelOf('c:abzou_sub'), 'c:abzou_sub');
    expect(
      TwitcastingParse.channelOf('see https://twitcasting.tv/g:115956781845998461844 !'),
      'g:115956781845998461844',
    );
    expect(TwitcastingParse.channelOf('https://twitcasting.tv/nabo66game/movie/841525457'), isNull);
    expect(TwitcastingParse.channelOf('https://twitcasting.tv/search'), isNull);
    expect(TwitcastingParse.channelOf('https://example.test/nabo66game'), isNull);
  });

  group('adapter over ReplayHttp', () {
    test('catalog, genre rooms, recommended, search', () async {
      final site = _site(['S01-home', 'S02-top-game', 'S02-top-all', 'S03-search']);
      final game = (await site.categories()).single.areas.firstWhere((a) => a.id == '_system_channel_12');
      expect((await site.areaRooms(game)).items, isNotEmpty);
      expect((await site.recommended()).items, isNotEmpty);
      expect((await site.search('game')).items, isNotEmpty);
    });

    test('detail and streams', () async {
      final site = _site(['S04-page-live', 'S05-stream-live']);
      final detail = await site.detail(RoomRef('twitcasting', 'nabo66game'));
      expect(detail.state, LiveState.live);
      expect((await site.streams(detail)).qualities, hasLength(3));
    });

    test('an unknown channel redirects and is NotFound', () async {
      final site = _site(['S04-page-notfound']);
      await expectLater(site.detail(RoomRef('twitcasting', 'zxqvnochannelfixture')), throwsA(isA<NotFound>()));
    });
  });
}
