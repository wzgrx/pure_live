// CcSite end to end over the recorded CC responses (ReplayHttp).
import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

CcSite _site(List<String> samples) => CcSite(
  ReplayHttp.fixtures('../../fixtures/cc', samples),
  now: () => Fixture.load('cc', 'S06-play-default').capturedAt,
);

RoomDetail _room(String ccid) => RoomDetail(
  card: RoomCard(ref: RoomRef('cc', ccid), title: '', anchorName: '', state: LiveState.live),
  link: Uri.parse('https://cc.163.com/$ccid/'),
);

void main() {
  test('categories: five requests, empty categories dropped', () async {
    final site = _site(['S01-cate-all', 'S01-cate-online', 'S01-cate-mobile', 'S01-cate-esports', 'S01-cate-show']);
    final categories = await site.categories();
    expect(categories.map((c) => c.name), ['网游', '手游', '竞技', '综艺']);
    expect(categories[1].areas.first.name, '蛋仔派对');
  });

  test('area rooms, recommendations and search', () async {
    final site = _site(['S02-area-page1', 'S02-area-beyond', 'S03-live-page1', 'S04-search-page1']);
    const area = Area(id: '9141', name: '蛋仔派对', categoryId: '2');
    final page = await site.areaRooms(area);
    expect(page.items, hasLength(13));
    expect((await site.areaRooms(area, cursor: page.next)).isLast, isTrue);
    expect((await site.recommended()).items, hasLength(30));
    expect((await site.search('梦幻')).items, hasLength(20));
    expect(await site.search('  '), isA<Page<RoomCard>>().having((p) => p.isLast, 'isLast', isTrue));
  });

  test('detail: live via the channel, offline and unknown via the room page', () async {
    final site = _site([
      'S05-lives-live',
      'S05-channel-live',
      'S05-lives-offline',
      'S05-page-offline',
      'S05-lives-missing',
      'S05-page-missing',
    ]);
    expect((await site.detail(RoomRef('cc', '341438909'))).state, LiveState.live);
    expect((await site.detail(RoomRef('cc', '376267758'))).state, LiveState.offline);
    await expectLater(site.detail(RoomRef('cc', '88888888888')), throwsA(isA<NotFound>()));
    await expectLater(site.detail(RoomRef('cc', 'abc')), throwsA(isA<NotFound>()));
  });

  test('streams: the best quality on both CDNs with leases', () async {
    final site = _site(['S06-play-default']);
    final set = await site.streams(_room('341438909'));
    expect(set.selected.id, 'original');
    expect(set.lines.map((line) => line.lineId), ['hs', 'ali']);
    expect(set.lines.every((line) => line.confirmed?.id == 'original'), isTrue);
    expect(set.lines.every((line) => line.lease?.cutsConnection == false), isTrue);
    expect(set.lines.first.headers['referer'], 'https://cc.163.com/');
  });

  test('streams: a CDN the server does not serve for the quality is not invented', () async {
    // `high` answers ali twice, and cdn=hs is answered with ali again.
    final site = _site(['S06-play-high', 'S06-play-high-hs']);
    final set = await site.streams(
      _room('341438909'),
      quality: const Quality(id: 'high', label: '高清', rank: 2),
    );
    expect(set.lines.map((line) => line.lineId), ['ali']);
    expect(set.lines.single.url.path, endsWith('tc2.flv'));
    expect(set.lines.single.effective.label, '高清');
  });

  test('streams of an offline anchor: StreamUnavailable', () async {
    final site = _site(['S06-play-offline']);
    await expectLater(site.streams(_room('376267758')), throwsA(isA<StreamUnavailable>()));
  });

  test('links: ccid, room pages, h5 share pages and the Dashen player', () async {
    final site = _site(const []);
    expect(await site.resolve('732923115'), RoomRef('cc', '732923115'));
    expect(await site.resolve('看这里 https://cc.163.com/732923115/?from=search 了'), RoomRef('cc', '732923115'));
    expect(await site.resolve('https://h5.cc.163.com/cc/732923115?rid=1'), RoomRef('cc', '732923115'));
    expect(await site.resolve('https://ds.163.com/glive/?ccid=732923115'), RoomRef('cc', '732923115'));
    expect(await site.resolve('https://cc.163.com/n/ds_category/3/'), isNull);
    expect(await site.resolve('https://www.douyu.com/9999'), isNull);
  });
}
