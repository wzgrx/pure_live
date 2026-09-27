// CHZZK parsing and the adapter over the recorded samples (spec/sites/chzzk.md).
// Legacy no longer runs (ADR 0016), so expectations come from the sample
// bodies themselves and from the spec.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _live = 'af3323d30e11ae42c39d7203c7e07fa2';

Map<String, dynamic> _json(String sample) => jsonDecode(Fixture.load('chzzk', sample).body) as Map<String, dynamic>;

ChzzkSite _site(List<String> samples) => ChzzkSite(
  // The Akamai token and the viewer parameter differ between recordings.
  ReplayHttp.fixtures('../../fixtures/chzzk', samples, ignoredQuery: const {'hdnts', 'vp'}),
  now: () => Fixture.load('chzzk', 'S06-live-detail-live').capturedAt,
);

RoomDetail _room(String id, {LiveState state = LiveState.live}) => RoomDetail(
  card: RoomCard(ref: RoomRef('chzzk', id), title: '', anchorName: '', state: state),
  link: Uri.parse('https://chzzk.naver.com/live/$id'),
);

void main() {
  group('§2.1 categories', () {
    test('categoryType groups the areas; the next page query is kept', () {
      final first = Fixture.load('chzzk', 'S01-categories-p1');
      final page = ChzzkParse.categoryPage(first.body);
      final raw = (_json('S01-categories-p1')['content'] as Map)['data'] as List;
      expect(page.items.map((item) => item.id), raw.map((item) => (item as Map)['categoryId']));
      expect(page.next, {'concurrentUserCount': '267', 'openLiveCount': '23', 'categoryId': 'Teamfight_Tactics'});
      final second = ChzzkParse.categoryPage(Fixture.load('chzzk', 'S01-categories-p2').body);
      final categories = ChzzkParse.categories([page, second]);
      expect(categories.map((c) => c.id), ['GAME', 'ETC', 'ENTERTAINMENT']);
      expect(categories.first.name, '游戏');
      final areas = categories.expand((c) => c.areas).toList();
      expect(areas, hasLength(100), reason: 'two pages of 50, no duplicates');
      final lol = areas.firstWhere((area) => area.id == 'League_of_Legends');
      expect(lol.categoryId, 'GAME');
      expect(lol.name, '리그 오브 레전드');
      expect(lol.icon, isNotNull);
    });
  });

  group('§2.2/§2.3 lives pages', () {
    for (final sample in ['S02-category-lives-p1', 'S02-category-lives-p2', 'S03-lives-p1', 'S03-lives-p2']) {
      test(sample, () {
        final fixture = Fixture.load('chzzk', sample);
        final cursor = {
          for (final entry in fixture.url.queryParameters.entries)
            if (entry.key != 'size') entry.key: entry.value,
        };
        final page = ChzzkParse.livesPage(fixture.body, cursor: cursor.isEmpty ? null : cursor);
        final raw = ((_json(sample)['content'] as Map)['data'] as List).cast<Map<String, dynamic>>();
        expect(page.items, isNotEmpty);
        expect(page.items.length, lessThanOrEqualTo(raw.length));
        expect(page.items.every((card) => card.state == LiveState.live), isTrue);
        final first = raw.first;
        final card = page.items.first;
        expect(card.ref.roomId, (first['channel'] as Map)['channelId']);
        expect(card.title, (first['liveTitle'] as String).trim());
        expect(card.anchorName, (first['channel'] as Map)['channelName']);
        expect(card.audience.online, first['cvExposure'] == true ? first['concurrentUserCount'] : null);
        expect(card.audience.popularity, isNull);
        expect(card.cover?.toString(), isNot(contains('{type}')));
        expect(card.liveSince, isNotNull);
        final next = jsonDecode(page.next!.value) as Map<String, dynamic>;
        expect(next.keys, containsAll(['concurrentUserCount', 'liveId']));
        expect(page.items.map((c) => c.ref).toSet(), hasLength(page.items.length), reason: 'one card per channel');
      });
    }

    test('the page after the cursor starts after its boundary entry', () {
      final first = ChzzkParse.livesPage(Fixture.load('chzzk', 'S03-lives-p1').body);
      final query = ChzzkParse.cursorQuery(first.next!);
      final lastLiveId = (((_json('S03-lives-p1')['content'] as Map)['data'] as List).last as Map)['liveId'];
      expect(query['liveId'], '$lastLiveId');
      final second = Fixture.load('chzzk', 'S03-lives-p2');
      expect(second.url.queryParameters['liveId'], query['liveId']);
    });

    test('an unknown category is an empty last page', () {
      final page = ChzzkParse.livesPage(Fixture.load('chzzk', 'S02-category-lives-empty').body);
      expect(page.items, isEmpty);
      expect(page.isLast, isTrue);
    });

    test('hidden audience figures stay hidden (cvExposure false)', () {
      final page = ChzzkParse.livesPage(
        jsonEncode({
          'code': 200,
          'content': {
            'page': null,
            'data': [
              {
                'liveId': 1,
                'liveTitle': 't',
                'concurrentUserCount': 99,
                'cvExposure': false,
                'liveImageUrl': null,
                'defaultThumbnailImageUrl': null,
                'channel': {'channelId': _live, 'channelName': 'n'},
              },
            ],
          },
        }),
      );
      expect(page.items.single.audience.online, isNull);
      expect(page.items.single.cover, isNull);
      expect(page.isLast, isTrue);
    });
  });

  group('§3 search', () {
    test('channel cards, live by openLive, next offset from page.next', () {
      final fixture = Fixture.load('chzzk', 'S04-search-channels');
      final page = ChzzkParse.searchPage(fixture.body, offset: 0);
      final raw = ((_json('S04-search-channels')['content'] as Map)['data'] as List).cast<Map<String, dynamic>>();
      expect(page.items.map((c) => c.ref.roomId), raw.map((item) => (item['channel'] as Map)['channelId']));
      expect(
        page.items.map((c) => c.state == LiveState.live),
        raw.map((item) => (item['channel'] as Map)['openLive'] == true),
      );
      expect(page.items.where((c) => c.state == LiveState.live), isNotEmpty);
      expect(page.items.first.title, page.items.first.anchorName);
      expect(page.items.map((c) => c.followers), raw.map((item) => (item['channel'] as Map)['followerCount']));
      expect(page.next, const PageCursor('20'));
    });

    test('no results is the last page', () {
      final page = ChzzkParse.searchPage(Fixture.load('chzzk', 'S04-search-empty').body, offset: 0);
      expect(page.items, isEmpty);
      expect(page.isLast, isTrue);
    });
  });

  group('§4 detail', () {
    test('a live room: channel plus live-detail', () {
      final detail = ChzzkParse.detail(
        Fixture.load('chzzk', 'S05-channel-live').body,
        Fixture.load('chzzk', 'S06-live-detail-live').body,
      );
      final live = _json('S06-live-detail-live')['content'] as Map<String, dynamic>;
      expect(detail.ref, RoomRef('chzzk', _live));
      expect(detail.state, LiveState.live);
      expect(detail.card.title, live['liveTitle']);
      expect(detail.card.anchorName, '너불');
      expect(detail.card.area, 'Grand Theft Auto V');
      expect(detail.card.audience.online, live['concurrentUserCount']);
      expect(detail.card.audience.cumulative, isNull, reason: 'accumulateCount 0');
      expect(detail.card.cover.toString(), endsWith('image_480.jpg'));
      expect(detail.card.liveSince, DateTime.utc(2026, 9, 27, 8, 52, 4));
      expect(detail.introduction, startsWith('광고문의'));
      expect(detail.link, Uri.parse('https://chzzk.naver.com/live/$_live'));
      expect(detail.danmakuKeys, {'channelId': _live, 'chatChannelId': 'N2lpu9'});
    });

    test('offline: CLOSE, cumulative kept, no chat channel', () {
      final detail = ChzzkParse.detail(
        Fixture.load('chzzk', 'S05-channel-offline').body,
        Fixture.load('chzzk', 'S06-live-detail-offline').body,
      );
      expect(detail.state, LiveState.offline);
      expect(detail.card.audience.online, isNull);
      expect(detail.card.audience.cumulative, 161);
      expect(detail.danmakuKeys.containsKey('chatChannelId'), isFalse);
    });

    test('a channel that never broadcast (content null) is offline', () {
      final detail = ChzzkParse.detail(
        Fixture.load('chzzk', 'S05-channel-offline').body,
        jsonEncode({'code': 200, 'message': null, 'content': null}),
      );
      expect(detail.state, LiveState.offline);
      expect(detail.card.title, 'PUBG 배틀그라운드B');
    });

    test('unknown channels are NotFound; unknown status is ApiChanged', () {
      expect(() => ChzzkParse.channel(Fixture.load('chzzk', 'S05-channel-notfound').body), throwsA(isA<NotFound>()));
      final notFound = Fixture.load('chzzk', 'S06-live-detail-notfound');
      expect(() => ChzzkParse.playback(notFound.body, status: notFound.status), throwsA(isA<NotFound>()));
      final odd = jsonEncode({
        'code': 200,
        'content': {'status': 'PAUSED'},
      });
      expect(() => ChzzkParse.playback(odd), throwsA(isA<ApiChanged>()));
      expect(() => ChzzkParse.content('{"code":9004,"message":"x"}', what: 'live-detail'), throwsA(isA<ApiChanged>()));
      expect(() => ChzzkParse.content('', what: 'x', status: 429), throwsA(isA<RateLimited>()));
      expect(() => ChzzkParse.content('', what: 'x', status: 503), throwsA(isA<NetworkFailure>()));
    });
  });

  group('§5/§6 playback', () {
    test('restricted lives: region and adult', () {
      final region = ChzzkParse.playback(Fixture.load('chzzk', 'S06-live-detail-region').body);
      expect(region.state, LiveState.live);
      expect(region.media, isEmpty);
      expect(ChzzkParse.noPlayback(region), isA<RegionBlocked>());
      final adult = ChzzkParse.playback(Fixture.load('chzzk', 'S06-live-detail-adult').body);
      expect(adult.media, isEmpty);
      expect(ChzzkParse.noPlayback(adult), isA<NeedsLogin>());
      final offline = ChzzkParse.playback(Fixture.load('chzzk', 'S06-live-detail-offline').body);
      expect(ChzzkParse.noPlayback(offline), isA<StreamUnavailable>());
    });

    test('media: HLS then LLHLS', () {
      final playback = ChzzkParse.playback(Fixture.load('chzzk', 'S06-live-detail-live').body);
      expect(playback.media.map((m) => m.id), ['HLS', 'LLHLS']);
      expect(playback.media.first.url.path, endsWith('_hls_playlist.m3u8'));
    });

    test('qualities from the masters, best first; two lines at the chosen quality with leases', () {
      final hls = Fixture.load('chzzk', 'S07-master-hls');
      final ll = Fixture.load('chzzk', 'S07-master-llhls');
      final issuedAt = hls.capturedAt;
      final set = ChzzkParse.streams(
        [(id: 'HLS', url: hls.url, body: hls.body), (id: 'LLHLS', url: ll.url, body: ll.body)],
        issuedAt: issuedAt,
        headers: ChzzkSite.mediaHeaders,
      );
      expect(set.qualities.map((q) => q.id), ['1080p60', '720p60', '480p', '360p', '144p']);
      expect(set.selected.id, '1080p60');
      expect(set.lines.map((line) => line.lineId), ['HLS', 'LLHLS']);
      final line = set.lines.first;
      expect(line.format, StreamFormat.hls);
      expect(line.codec, 'avc');
      expect(line.confirmed, line.requested);
      expect(line.url.path, contains('1080p/hdntl=exp='));
      expect(line.url.path, endsWith('_hls_chunklist.m3u8'));
      expect(set.lines.last.url.path, endsWith('_chunklist.m3u8'));
      expect(line.headers['referer'], 'https://chzzk.naver.com/');
      final lease = line.lease!;
      expect(lease.cutsConnection, isTrue);
      final exp = int.parse(RegExp(r'exp=(\d+)').firstMatch(Uri.decodeFull(line.url.path))!.group(1)!);
      expect(lease.expiresAt, DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true));
      expect(lease.expiresAt!.difference(lease.refreshAt), const Duration(minutes: 10));
      expect(lease.expiresAt!.difference(issuedAt).inHours, inInclusiveRange(16, 17));

      final low = ChzzkParse.streams(
        [(id: 'HLS', url: hls.url, body: hls.body), (id: 'LLHLS', url: ll.url, body: null)],
        issuedAt: issuedAt,
        headers: const {},
        wanted: '480p',
      );
      expect(low.selected.id, '480p');
      expect(low.lines.map((l) => l.lineId), ['HLS'], reason: 'a failed master only drops its line');
    });

    test('HLS attributes and codecs', () {
      final variants = HlsPlaylist.variants(
        [
          '#EXTM3U',
          '#EXT-X-STREAM-INF:BANDWIDTH=10,CODECS="hvc1.1.6.L120.90,mp4a.40.2",RESOLUTION=1920x1080,FRAME-RATE=59.94',
          'v/a.m3u8',
          '#EXT-X-STREAM-INF:BANDWIDTH=5,CODECS="mp4a.40.2"',
          'audio.m3u8',
        ].join('\n'),
        source: Uri.parse('https://example.test/x/master.m3u8?t=1'),
      );
      expect(variants.first.url, Uri.parse('https://example.test/x/v/a.m3u8'));
      expect(variants.first.videoCodec, 'hevc');
      expect(ChzzkParse.quality(variants.first)?.id, '1080p60');
      expect(variants.last.audioOnly, isTrue);
      expect(ChzzkParse.quality(variants.last), isNull);
      expect(() => HlsPlaylist.variants('<html>', source: Uri.parse('https://example.test/')), throwsFormatException);
    });
  });

  group('adapter over ReplayHttp', () {
    test('categories read four pages; lists and search', () async {
      final site = _site([
        'S01-categories-p1',
        'S01-categories-p2',
        'S01-categories-p3',
        'S01-categories-p4',
        'S02-category-lives-p1',
        'S03-lives-p1',
        'S04-search-channels',
      ]);
      final categories = await site.categories();
      expect(categories.expand((c) => c.areas).length, greaterThan(150));
      expect(categories.map((c) => c.id), containsAll(['GAME', 'ETC', 'ENTERTAINMENT']));
      const area = Area(id: 'League_of_Legends', name: '리그 오브 레전드', categoryId: 'GAME');
      expect((await site.areaRooms(area)).items, isNotEmpty);
      final recommended = await site.recommended();
      expect(recommended.items, hasLength(30));
      expect((await site.search('배틀')).items, isNotEmpty);
      expect((await site.search('  ')).isLast, isTrue);
    });

    test('recommended page 2 uses the cursor query', () async {
      final site = _site(['S03-lives-p1', 'S03-lives-p2']);
      final first = await site.recommended();
      final second = await site.recommended(cursor: first.next);
      expect(second.items, isNotEmpty);
      expect(second.items.first.ref, isNot(first.items.last.ref));
    });

    test('detail and streams for a live room', () async {
      final site = _site(['S05-channel-live', 'S06-live-detail-live', 'S07-master-hls', 'S07-master-llhls']);
      final detail = await site.detail(RoomRef('chzzk', _live));
      expect(detail.state, LiveState.live);
      final set = await site.streams(
        detail,
        quality: const Quality(id: '720p60', label: '720p60', rank: 0),
      );
      expect(set.selected.id, '720p60');
      expect(set.lines, hasLength(2));
    });

    test('streams for restricted rooms fail with the typed error', () async {
      await expectLater(
        _site(['S06-live-detail-region']).streams(_room('75cbf189b3bb8f9f687d2aca0d0a382b')),
        throwsA(isA<RegionBlocked>()),
      );
      await expectLater(
        _site(['S06-live-detail-adult']).streams(_room('7ce8032370ac5121dcabce7bad375ced')),
        throwsA(isA<NeedsLogin>()),
      );
    });

    test('an unknown channel is NotFound before live-detail is asked', () async {
      final site = _site(['S05-channel-notfound']);
      await expectLater(site.detail(RoomRef('chzzk', '00000000000000000000000000000000')), throwsA(isA<NotFound>()));
      await expectLater(site.detail(RoomRef('chzzk', 'not-an-id')), throwsA(isA<NotFound>()));
    });

    test('links', () async {
      final site = _site(const []);
      expect(await site.resolve(_live.toUpperCase()), RoomRef('chzzk', _live));
      expect(await site.resolve('보러와 https://chzzk.naver.com/live/$_live !'), RoomRef('chzzk', _live));
      expect(await site.resolve('https://chzzk.naver.com/$_live'), RoomRef('chzzk', _live));
      expect(await site.resolve('https://chzzk.naver.com/lives'), isNull);
      expect(await site.resolve('https://m.chzzk.naver.com/live/$_live'), isNull);
      expect(await site.resolve('https://www.douyu.com/9999'), isNull);
    });
  });
}
