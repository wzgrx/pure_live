// AcfunSite end to end over the recorded AcFun responses (ReplayHttp). The
// startPlay query carries the visitor session, left out of matching.
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _ignored = {'userId', 'did', 'acfun.api.visitor_st'};

AcfunSite _site(List<String> samples) => AcfunSite(
  ReplayHttp.fixtures('../../fixtures/acfun', samples, ignoredQuery: _ignored),
  now: () => Fixture.load('acfun', 'S06-startplay-live').capturedAt,
  random: Random(3),
);

RoomDetail _room(String author) => RoomDetail(
  card: RoomCard(ref: RoomRef('acfun', author), title: '', anchorName: '', state: LiveState.live),
  link: Uri.parse('https://live.acfun.cn/live/$author'),
);

void main() {
  test('catalog, lists and search', () async {
    final site = _site(['S01-list-filters', 'S01-list-all', 'S02-list-game', 'S04-search-p1']);
    final categories = await site.categories();
    expect(categories.single.areas.map((a) => a.name), ['虚拟偶像', '游戏', '娱乐', '其他']);
    expect((await site.recommended()).items, hasLength(19));
    const game = Area(id: '1', name: '游戏', categoryId: '1');
    expect((await site.areaRooms(game)).items, hasLength(8));
    expect((await site.search('游戏')).items, hasLength(30));
  });

  test('detail', () async {
    final site = _site(['S05-info-live', 'S05-info-offline', 'S05-info-missing']);
    expect((await site.detail(RoomRef('acfun', '40740702'))).state, LiveState.live);
    expect((await site.detail(RoomRef('acfun', '1'))).state, LiveState.offline);
    await expectLater(site.detail(RoomRef('acfun', '99999999999')), throwsA(isA<NotFound>()));
  });

  test('streams: visitor login, startPlay, the best quality', () async {
    final site = _site(['S06-visitor', 'S06-startplay-live']);
    final set = await site.streams(_room('40740702'));
    expect(set.selected.id, 'BLUE_RAY');
    final line = set.lines.single;
    expect(line.format, StreamFormat.flv);
    expect(line.url.path, contains('kszt_'));
    expect(line.headers['referer'], 'https://live.acfun.cn/');
    expect(line.lease?.cutsConnection, isFalse);
    final chosen = await site.streams(
      _room('40740702'),
      quality: const Quality(id: 'HIGH', label: '超清', rank: 2),
    );
    expect(chosen.lines.single.url.path, endsWith('hd2000.flv'));
  });

  test('streams of a closed broadcast: StreamUnavailable', () async {
    final site = _site(['S06-visitor', 'S06-startplay-offline']);
    await expectLater(site.streams(_room('1')), throwsA(isA<StreamUnavailable>()));
  });

  test('links', () async {
    final site = _site(const []);
    expect(await site.resolve('40740702'), RoomRef('acfun', '40740702'));
    expect(await site.resolve('https://live.acfun.cn/live/40740702?from=share'), RoomRef('acfun', '40740702'));
    expect(await site.resolve('分享 https://m.acfun.cn/live/detail/40740702 看看'), RoomRef('acfun', '40740702'));
    expect(await site.resolve('https://www.acfun.cn/u/40740702'), RoomRef('acfun', '40740702'));
    expect(await site.resolve('https://www.acfun.cn/v/ac48809737'), isNull);
  });
}
