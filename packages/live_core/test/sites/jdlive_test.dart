// JD Live: parsing and the adapter over the recorded samples
// (spec/sites/jdlive.md). No legacy expected values (ADR 0016).
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _ignored = {'t', 'v'};

JdLiveSite _site(List<String> samples) => JdLiveSite(
  ReplayHttp.fixtures('../../fixtures/jdlive', samples, ignoredQuery: _ignored),
  now: () => DateTime.fromMillisecondsSinceEpoch(1790533000000),
);

void main() {
  group('§2.2 featured list', () {
    test('S01 page 1: room cards only, cumulative views, cursor page:count:timestamp', () {
      final body = Fixture.load('jdlive', 'S01-list-p1').body;
      final data = (jsonDecode(body) as Map)['data'] as Map;
      final rooms = (data['list'] as List).where((r) => (r as Map)['templateType'] == 1).toList();
      final page = JdLiveParse.list(body, page: 1, timestamp: 1790533000000);
      expect(page.items.map((c) => c.ref.roomId), rooms.map((r) => '${((r as Map)['data'] as Map)['liveId']}'));
      final first = (rooms.first as Map)['data'] as Map;
      expect(page.items.first.title, first['title']);
      expect(page.items.first.anchorName, first['userName']);
      expect(page.items.first.audience.cumulative, first['pv']);
      expect(page.next, PageCursor('2:${data['currentCount']}:1790533000000'));
    });
  });

  group('§4 play', () {
    test('S02 live: FLV and HLS, no names', () {
      final play = JdLiveParse.play(Fixture.load('jdlive', 'S02-play-live').body, expectedId: '48378944');
      expect(play.detail.state, LiveState.live);
      expect(play.detail.card.anchorName, isEmpty);
      final lines = JdLiveParse.lines(play, headers: const {});
      expect(lines.map((l) => l.format), [StreamFormat.flv, StreamFormat.hls]);
      expect(lines.first.url.path, endsWith('_fhd.flv'));
    });

    test('S02 an old id is status 3 without addresses; app-only rooms need an account', () {
      final old = JdLiveParse.play(Fixture.load('jdlive', 'S02-play-old').body, expectedId: '10000');
      expect(old.detail.state, LiveState.offline);
      expect(() => JdLiveParse.lines(old, headers: const {}), throwsA(isA<StreamUnavailable>()));
      final live = JdLiveParse.play(Fixture.load('jdlive', 'S02-play-live').body, expectedId: '48378944');
      final secret = (detail: live.detail, appOnly: true, flv: live.flv, hls: live.hls);
      expect(() => JdLiveParse.lines(secret, headers: const {}), throwsA(isA<NeedsLogin>()));
    });

    test('S03 the detail endpoint answers an empty 403 without the h5st signature', () {
      expect(Fixture.load('jdlive', 'S03-detail-403').status, 403);
    });
  });

  group('adapter', () {
    test('two list pages and the play endpoint', () async {
      final site = _site(['S01-list-p1', 'S01-list-p2', 'S02-play-live']);
      final p1 = await site.recommended();
      final p2 = await site.recommended(cursor: p1.next);
      expect(p2.items, hasLength(30));
      expect(p2.items.map((c) => c.ref).toSet().intersection(p1.items.map((c) => c.ref).toSet()), isEmpty);
      final detail = await site.detail(RoomRef('jdlive', '48378944'));
      expect((await site.streams(detail)).lines, hasLength(2));
    });

    test('links', () async {
      final site = _site(const []);
      expect(await site.resolve('48378944'), RoomRef('jdlive', '48378944'));
      expect(await site.resolve('https://lives.jd.com/#/48378944?origin=0'), RoomRef('jdlive', '48378944'));
      expect(await site.resolve('看 https://lives.jd.com/#/48378944/live 吧'), RoomRef('jdlive', '48378944'));
      expect(await site.resolve('https://lives.jd.com/'), isNull);
    });
  });
}
