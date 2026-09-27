// Inke parsing and the adapter over the recorded samples (spec/sites/inke.md).
// Legacy no longer runs (ADR 0016), so the expectations come from the sample
// bodies and the spec.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _uid = '771067357';

Map<String, dynamic> _json(String sample) => jsonDecode(Fixture.load('inke', sample).body) as Map<String, dynamic>;

InkeSite _site(List<String> samples) => InkeSite(
  ReplayHttp.fixtures('../../fixtures/inke', samples),
  now: () => Fixture.load('inke', 'S04-publish-live').capturedAt,
);

void main() {
  test('§2.1 channels are the areas of one category', () {
    final categories = InkeParse.categories(Fixture.load('inke', 'S01-channels').body);
    final groups = ((_json('S01-channels')['data'] as Map)['list'] as List).cast<Map<String, dynamic>>();
    expect(categories.single.areas.map((a) => a.id), groups.map((g) => g['tab_key']));
    expect(categories.single.areas.map((a) => a.name), groups.map((g) => g['channel_name']));
    expect(categories.single.areas.first.name, '音乐');
  });

  test('§2.2 showcases: one page, live, nick as title', () {
    final channels = Fixture.load('inke', 'S01-channels').body;
    final page = InkeParse.channelPage(channels, tabKey: '62F3CD3ACF8347C9');
    expect(page.items, hasLength(8));
    expect(page.isLast, isTrue);
    expect(page.items.every((c) => c.state == LiveState.live && c.title == c.anchorName), isTrue);
    expect(() => InkeParse.channelPage(channels, tabKey: 'nope'), throwsA(isA<NotFound>()));
    expect(InkeParse.topPage(Fixture.load('inke', 'S01-top').body).items, hasLength(8));
  });

  test('§2.3 the app hot list: titles, real viewers online, the display figure as heat', () {
    final page = InkeParse.simpleallPage(Fixture.load('inke', 'S02-simpleall').body);
    final lives = (_json('S02-simpleall')['lives'] as List).cast<Map<String, dynamic>>();
    expect(page.items.map((c) => c.ref.roomId), lives.map((l) => '${(l['creator'] as Map)['id']}'));
    final first = lives.first;
    expect(page.items.first.title, first['name']);
    expect(page.items.first.audience.online, (first['numbers'] as Map)['real']);
    expect(page.items.first.audience.popularity, first['online_users']);
    expect(page.items.first.liveSince, isNotNull);
  });

  group('§4 detail', () {
    test('a live anchor', () {
      final detail = InkeParse.detail(
        uid: _uid,
        shareBody: Fixture.load('inke', 'S03-share-live').body,
        publishBody: Fixture.load('inke', 'S04-publish-live').body,
      );
      expect(detail.ref, RoomRef('inke', _uid));
      expect(detail.state, LiveState.live);
      expect(detail.card.anchorName, '木子');
      expect(detail.card.title, '木子');
      expect(detail.card.audience.online, 12);
      expect(detail.card.liveSince, DateTime.fromMillisecondsSinceEpoch(1790521192 * 1000, isUtc: true));
      expect(detail.introduction, '难道在火星？');
      expect(detail.link.queryParameters, {'uid': _uid, 'id': '1790521153165881'});
    });

    test('no current live is offline (unknown uids answer the same)', () {
      final detail = InkeParse.detail(
        uid: '1',
        shareBody: Fixture.load('inke', 'S03-share-offline').body,
        publishBody: Fixture.load('inke', 'S04-publish-offline').body,
      );
      expect(detail.state, LiveState.offline);
      expect(detail.card.audience, Audience.none);
      expect(detail.link, Uri.parse('https://www.inke.cn/liveroom/index.html?uid=1'));
    });

    test('errors are typed', () {
      expect(() => InkeParse.webData('{"error_code":5,"message":"x"}', what: 'x'), throwsA(isA<ApiChanged>()));
      expect(() => InkeParse.serviceData('{"dm_error":499}', what: 'x'), throwsA(isA<ApiChanged>()));
      expect(() => InkeParse.serviceData('', what: 'x', status: 502), throwsA(isA<NetworkFailure>()));
      expect(
        () => InkeParse.publishedLive(Fixture.load('inke', 'S04-publish-live').body, uid: '42'),
        throwsA(isA<ApiChanged>()),
      );
    });
  });

  test('§5/§6 streams: the H.264 Wangsu line with a lease from wsABStime; the HEVC Zego line is left out', () {
    final fixture = Fixture.load('inke', 'S04-publish-live');
    final set = InkeParse.streams(fixture.body, uid: _uid, issuedAt: fixture.capturedAt, headers: InkeSite.headers);
    final line = set.lines.single;
    expect(line.lineId, 'ws');
    expect(line.codec, 'avc');
    expect(line.url.host, 'live-pull-ws.ikstatic.cn');
    expect(line.url.path, '/live/1790521153165881_t.flv');
    final expiry = int.parse(line.url.queryParameters['wsABStime']!, radix: 16);
    expect(line.lease!.expiresAt, DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true));
    expect(line.lease!.cutsConnection, isFalse);
    expect(
      () => InkeParse.streams(
        Fixture.load('inke', 'S04-publish-offline').body,
        uid: '1',
        issuedAt: fixture.capturedAt,
        headers: const {},
      ),
      throwsA(isA<StreamUnavailable>()),
    );
  });

  test('§1 links', () {
    expect(InkeParse.uidOf(_uid), _uid);
    expect(InkeParse.uidOf('https://www.inke.cn/liveroom/index.html?uid=$_uid&id=1790521153165881'), _uid);
    expect(InkeParse.uidOf('看 https://mlive2.inke.cn/app/hot/live?uid=$_uid&liveid=1&ctime=1 啊'), _uid);
    expect(InkeParse.uidOf('https://www.inke.cn/hotlive_list.html'), isNull);
    expect(InkeParse.uidOf('https://example.test/liveroom/index.html?uid=1'), isNull);
  });

  group('adapter over ReplayHttp', () {
    test('catalog, channel rooms, recommended', () async {
      final site = _site(['S01-channels', 'S02-simpleall']);
      final area = (await site.categories()).single.areas.first;
      expect((await site.areaRooms(area)).items, hasLength(8));
      expect((await site.recommended()).items, isNotEmpty);
      expect((await site.recommended(cursor: const PageCursor('2'))).items, isEmpty);
    });

    test('detail, streams and a uid search', () async {
      final site = _site(['S03-share-live', 'S04-publish-live']);
      final detail = await site.detail(RoomRef('inke', _uid));
      expect(detail.state, LiveState.live);
      expect((await site.streams(detail)).lines, hasLength(1));
      expect((await site.search(_uid)).items.single.ref.roomId, _uid);
    });

    test('keyword search filters the showcases by nickname', () async {
      final site = _site(['S01-top', 'S01-channels', 'S02-simpleall']);
      final nick = InkeParse.topPage(Fixture.load('inke', 'S01-top').body).items.first.anchorName;
      final result = await site.search(nick);
      expect(result.items.map((c) => c.anchorName), everyElement(contains(nick)));
      expect(result.items, isNotEmpty);
      expect(result.isLast, isTrue);
    });
  });
}
