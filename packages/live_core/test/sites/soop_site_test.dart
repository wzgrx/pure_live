// SoopSite end to end over the recorded SOOP responses (ReplayHttp).
import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

SoopSite _site(List<String> samples) => SoopSite(ReplayHttp.fixtures('../../fixtures/soop', samples));

RoomDetail _room(String bj) => RoomDetail(
  card: RoomCard(ref: RoomRef('soop', bj), title: '', anchorName: '', state: LiveState.live),
  link: Uri.parse('https://play.sooplive.co.kr/$bj'),
);

void main() {
  test('categories: one group, pages until is_more is false', () async {
    final site = _site([for (var page = 1; page <= 5; page++) 'S01-category-p$page']);
    final categories = await site.categories();
    expect(categories.single.id, '1');
    expect(categories.single.areas.length, greaterThan(500));
    expect(categories.single.areas.first.name, '토크/캠방');
  });

  test('area rooms, recommendations and search', () async {
    final site = _site(['S02-area-p1', 'S03-main-p1', 'S04-search-p1']);
    const area = Area(id: '00130000', name: '토크/캠방', categoryId: '1');
    expect((await site.areaRooms(area)).items, hasLength(60));
    expect((await site.recommended()).items, hasLength(60));
    expect((await site.search('게임')).items, hasLength(30));
  });

  test('detail: live, offline, unknown, age-restricted', () async {
    final site = _site([
      'S05-live-live',
      'S05-station-live',
      'S05-live-offline',
      'S05-station-offline',
      'S05-live-missing',
      'S05-station-missing',
      'S05-live-adult',
      'S05-station-adult',
    ]);
    final live = await site.detail(RoomRef('soop', 'khm11903'));
    expect(live.state, LiveState.live);
    expect(live.danmakuKeys['chatNo'], '4172');
    expect((await site.detail(RoomRef('soop', 'phonics1'))).state, LiveState.offline);
    await expectLater(site.detail(RoomRef('soop', 'zzzqqqxxxnotexist1')), throwsA(isA<NotFound>()));
    expect((await site.detail(RoomRef('soop', 'bumzi98'))).state, LiveState.live);
  });

  test('streams: assigned playlist plus aid, one HLS line on the CDN', () async {
    final site = _site(['S05-live-live', 'S06-assign-original', 'S06-aid-original']);
    final set = await site.streams(_room('khm11903'));
    expect(set.selected.id, 'original');
    final line = set.lines.single;
    expect(line.format, StreamFormat.hls);
    expect(line.lineId, 'gcp_cdn');
    expect(line.url.path, endsWith('/auth_playlist.m3u8'));
    expect(line.url.queryParameters['aid'], startsWith('.'));
    expect(line.lease, isNull, reason: 'the playlist kept working for 40 minutes');
    expect(line.headers['referer'], 'https://play.sooplive.co.kr/');
  });

  test('streams: a chosen quality asks for its own key', () async {
    final site = _site(['S05-live-live', 'S06-assign-hd', 'S06-aid-hd']);
    final set = await site.streams(
      _room('khm11903'),
      quality: const Quality(id: 'hd', label: '540p', rank: 2),
    );
    expect(set.lines.single.requested.id, 'hd');
  });

  test('streams: an age-restricted broadcast needs a login; an offline one has no stream', () async {
    await expectLater(_site(['S05-live-adult']).streams(_room('bumzi98')), throwsA(isA<NeedsLogin>()));
    await expectLater(_site(['S05-live-offline']).streams(_room('phonics1')), throwsA(isA<StreamUnavailable>()));
  });

  test('links', () async {
    final site = _site(const []);
    expect(await site.resolve('khm11903'), RoomRef('soop', 'khm11903'));
    expect(await site.resolve('https://play.sooplive.co.kr/khm11903/297314125'), RoomRef('soop', 'khm11903'));
    expect(await site.resolve('看 https://ch.sooplive.co.kr/KHM11903 这个'), RoomRef('soop', 'khm11903'));
    expect(await site.resolve('https://www.sooplive.co.kr/station/khm11903'), RoomRef('soop', 'khm11903'));
    expect(await site.resolve('https://play.afreecatv.com/khm11903'), RoomRef('soop', 'khm11903'));
    expect(await site.resolve('https://www.sooplive.co.kr/search'), isNull);
    expect(await site.resolve('https://www.twitch.tv/khm11903'), isNull);
  });
}
