// Weibo Live parsing and the adapter over the recorded samples (spec/sites/weibo.md).
// No legacy expected values: the archived app cannot run (ADR 0016), so the
// assertions read the recorded bodies directly.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Map<String, dynamic> _data(String sample) =>
    (jsonDecode(Fixture.load('weibo', sample).body) as Map<String, dynamic>)['data'] as Map<String, dynamic>;

WeiboSite _site(List<String> samples) => WeiboSite(ReplayHttp.fixtures('../../fixtures/weibo', samples));

void main() {
  group('§2.2 recommendation snapshot', () {
    test('S01 every row is a live card titled with the nickname; one page', () {
      final fixture = Fixture.load('weibo', 'S01-recommend');
      final rows = ((jsonDecode(fixture.body) as Map)['data'] as Map)['data'] as List;
      final page = WeiboParse.recommended(fixture.body);
      expect(page.items, hasLength(rows.length));
      expect(page.items.map((c) => c.ref.roomId), rows.map((r) => (r as Map)['liveid']));
      expect(page.items.map((c) => c.anchorName), rows.map((r) => (r as Map)['nickname']));
      expect(page.items.every((c) => c.title == c.anchorName && c.state == LiveState.live), isTrue);
      expect(page.items.first.cover.toString(), (rows.first as Map)['cover']);
      expect(page.isLast, isTrue);
    });
  });

  group('§4 room', () {
    test('S02-live maps the broadcast and one deduplicated FLV line', () {
      final data = _data('S02-live');
      final room = WeiboParse.room(Fixture.load('weibo', 'S02-live').body, expectedId: data['liveId'] as String);
      final user = data['user'] as Map<String, dynamic>;
      expect(room.detail.state, LiveState.live);
      expect(room.detail.card.title, data['title']);
      expect(room.detail.card.anchorName, user['screenName']);
      expect(room.detail.avatar.toString(), user['avatar']);
      expect(room.detail.card.audience.isEmpty, isTrue, reason: 'Weibo reports no audience');
      expect(room.detail.card.liveSince, DateTime.fromMillisecondsSinceEpoch(data['startTime'] as int, isUtc: true));
      expect(room.detail.link, Uri.parse('https://weibo.com/l/wblive/p/show/${data['liveId']}'));
      expect(data['live_origin_hls_url'], data['live_origin_flv_url'], reason: 'the "hls" field holds the FLV URL');
      final lines = WeiboParse.lines(room, headers: const {});
      expect(lines, hasLength(1));
      expect(lines.single.format, StreamFormat.flv);
      expect(lines.single.lineId, 'alicdn');
      expect(lines.single.codec, 'avc');
      expect(lines.single.lease, isNull);
      expect(lines.single.confirmed, isNull);
    });

    test('S02-watch-limit is live but needs an account', () {
      final data = _data('S02-watch-limit');
      final room = WeiboParse.room(Fixture.load('weibo', 'S02-watch-limit').body, expectedId: data['liveId'] as String);
      expect(room.detail.state, LiveState.live);
      expect(room.watchLimit, 10);
      expect(() => WeiboParse.lines(room, headers: const {}), throwsA(isA<NeedsLogin>()));
    });

    test('ended broadcasts (status 3 and 5) are offline without streams', () {
      for (final sample in ['S02-ended-replay', 'S02-ended']) {
        final data = _data(sample);
        final room = WeiboParse.room(Fixture.load('weibo', sample).body, expectedId: data['liveId'] as String);
        expect(room.detail.state, LiveState.offline, reason: sample);
        expect(() => WeiboParse.lines(room, headers: const {}), throwsA(isA<StreamUnavailable>()));
      }
    });

    test('S02-notfound is NotFound; a mismatched id or unknown status is ApiChanged', () {
      final notFound = Fixture.load('weibo', 'S02-notfound');
      expect(() => WeiboParse.room(notFound.body, expectedId: 'x'), throwsA(isA<NotFound>()));
      final live = Fixture.load('weibo', 'S02-live');
      expect(() => WeiboParse.room(live.body, expectedId: '1022:0000000000000000000000'), throwsA(isA<ApiChanged>()));
      final changed = live.body.replaceFirst('"status": 1', '"status": 7');
      final id = _data('S02-live')['liveId'] as String;
      expect(() => WeiboParse.room(changed, expectedId: id), throwsA(isA<ApiChanged>()));
    });
  });

  group('adapter', () {
    test('catalog: no categories, the snapshot is one page', () async {
      final site = _site(['S01-recommend']);
      expect(await site.categories(), isEmpty);
      final page = await site.recommended();
      expect(page.items, isNotEmpty);
      expect((await site.recommended(cursor: const PageCursor('2'))).items, isEmpty);
      await expectLater(site.areaRooms(const Area(id: 'x', name: 'x', categoryId: 'x')), throwsA(isA<NotFound>()));
    });

    test('detail and streams re-read the room', () async {
      final id = _data('S02-live')['liveId'] as String;
      final site = _site(['S02-live']);
      final detail = await site.detail(RoomRef('weibo', id));
      final set = await site.streams(detail);
      expect(set.selected, WeiboParse.origin);
      expect(set.lines.single.headers.keys, ['user-agent']);
    });

    test('links: ids, watch pages, media-centre links and share text', () async {
      final site = _site(const []);
      const id = '1022:2321325347923495092258';
      expect(await site.resolve(id), RoomRef('weibo', id));
      expect(await site.resolve('https://weibo.com/l/wblive/p/show/$id'), RoomRef('weibo', id));
      expect(
        await site.resolve('快来 https://www.weibo.com/l/wblive/m/show/1022%3A2321325347923495092258?from=x 看直播'),
        RoomRef('weibo', id),
      );
      expect(
        await site.resolve('https://live.media.weibo.com/live/show?id=1022%3A2320508a306db1bc389510651e77d5feb4f90d'),
        RoomRef('weibo', '1022:2320508a306db1bc389510651e77d5feb4f90d'),
      );
      expect(await site.resolve('https://weibo.com/u/2656274875'), isNull);
      expect(await site.resolve('https://www.douyu.com/9999'), isNull);
    });
  });
}
