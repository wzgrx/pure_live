// YySite end to end over the recorded YY responses (ReplayHttp). The
// stream-manager body carries clock values (seq, send_time), left out of
// matching like the URL's sequence.
import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _ignored = {'seq', 'send_time', 'sequence'};

YySite _site(List<String> samples) => YySite(
  ReplayHttp.fixtures('../../fixtures/yy', samples, ignoredQuery: _ignored),
  now: () => Fixture.load('yy', 'S06-streams-g2').capturedAt,
);

RoomDetail _room(String sid) => RoomDetail(
  card: RoomCard(ref: RoomRef('yy', sid), title: '', anchorName: '', state: LiveState.live),
  link: Uri.parse('https://www.yy.com/$sid'),
  danmakuKeys: {'sid': sid, 'ssid': sid},
);

void main() {
  test('categories: header plus covers', () async {
    final site = _site(['S01-header', 'S01-category-ent', 'S01-category-game', 'S01-category-other']);
    final categories = await site.categories();
    expect(categories.map((c) => c.name), ['娱乐', '游戏', '其他']);
    expect(categories.first.areas.first.icon, isNotNull);
  });

  test('area rooms resolve the module from the area page once; module-less areas are empty', () async {
    final site = _site(['S01-header', 'S02-area-page-dance', 'S02-dance-p1', 'S02-area-page-lol']);
    const dance = Area(id: '4', name: '舞蹈', categoryId: '1');
    final page = await site.areaRooms(dance);
    expect(page.items, hasLength(30));
    expect(page.items.first.area, '舞蹈');
    const lol = Area(id: '23', name: '英雄联盟', categoryId: '2');
    expect((await site.areaRooms(lol)).isLast, isTrue);
  });

  test('recommendations and search', () async {
    final site = _site(['S03-recommend-p1', 'S04-search-p1']);
    expect((await site.recommended()).items, hasLength(30));
    expect((await site.search('舞蹈')).items, hasLength(16));
  });

  test('detail: live, offline, unknown', () async {
    final site = _site([
      'S05-detail-live',
      'S05-detail-offline',
      'S05-page-offline',
      'S05-detail-missing',
      'S05-page-missing',
    ]);
    expect((await site.detail(RoomRef('yy', '22490906'))).state, LiveState.live);
    expect((await site.detail(RoomRef('yy', '85520900'))).state, LiveState.offline);
    await expectLater(site.detail(RoomRef('yy', '999999999999')), throwsA(isA<NotFound>()));
  });

  test('streams: best gear on both lines, confirmed, with non-cutting leases', () async {
    final site = _site(['S06-streams-g1', 'S06-streams-g2', 'S06-streams-g2-l10']);
    final set = await site.streams(_room('22490906'));
    expect(set.selected.id, '2');
    expect(set.lines.map((line) => line.lineId), ['14', '10']);
    expect(set.lines.map((line) => line.url.host), ['ks-flv-web.yy.com', 'tx-flv-web.yy.com']);
    expect(set.lines.every((line) => line.confirmed?.label == '高清'), isTrue);
    expect(set.lines.every((line) => line.format == StreamFormat.flv), isTrue);
    expect(set.lines.every((line) => line.lease?.cutsConnection == false), isTrue);
    expect(set.lines.first.headers.containsKey('cookie'), isFalse);
  });

  test('streams: an unavailable gear is reported as the delivered one', () async {
    final site = _site(['S06-streams-g3', 'S06-streams-g2-l10']);
    final set = await site.streams(
      _room('22490906'),
      quality: const Quality(id: '3', label: '超清', rank: 3),
    );
    expect(set.lines.first.requested.id, '3');
    expect(set.lines.first.effective.label, '高清');
  });

  test('streams of an offline channel: stream-manager then mobile HLS, StreamUnavailable', () async {
    final site = _site(['S06-streams-offline', 'S07-mobile-hls-offline']);
    // The recorded offline samples are for channel 85520900.
    await expectLater(site.streams(_room('85520900')), throwsA(isA<StreamUnavailable>()));
  });

  test('links', () async {
    final site = _site(const []);
    expect(await site.resolve('22490906'), RoomRef('yy', '22490906'));
    expect(await site.resolve('https://www.yy.com/22490906/22490906?tempId=16777217'), RoomRef('yy', '22490906'));
    expect(await site.resolve('分享 https://wap.yy.com/mobileweb/54880976/54880976 快来'), RoomRef('yy', '54880976'));
    expect(await site.resolve('https://www.yy.com/music/'), isNull);
    expect(await site.resolve('https://www.douyu.com/9999'), isNull);
  });
}
