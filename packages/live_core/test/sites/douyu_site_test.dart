// DouyuSite end to end over the recorded Douyu responses (ReplayHttp), plus
// the §6.2 signing vector. Signature and session fields are scrubbed in the
// samples, so they are left out of request matching.
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _ignored = {'did', 'tt', 'auth', 'enc_data'};

DouyuSite _site(List<String> samples, {DateTime? now}) => DouyuSite(
  ReplayHttp.fixtures('../../fixtures/douyu', samples, ignoredQuery: _ignored),
  now: () => now ?? Fixture.load('douyu', 'S06-encryption').capturedAt,
  random: Random(1),
);

void main() {
  test('§6.2 signing vector', () {
    final descriptor = DouyuDescriptor(
      key: 'key',
      randStr: 'rand',
      encData: 'x',
      encTime: 1,
      expireAt: DateTime.utc(2099),
      isSpecial: false,
    );
    expect(descriptor.auth('123', 1000), '1834439993932d590bceb2593c1c0cd0');
  });

  test('the process DID is 32 lower-case hex digits and used in every cookie', () {
    final site = DouyuSite(ReplayHttp(const []), random: Random(7));
    expect(site.did, matches(RegExp(r'^[0-9a-f]{32}$')));
    final vault = MemoryCookieVault()..set('douyu', 'dy_did=abc123; acf_auth=t; LTP0=secret');
    final account = DouyuSite(ReplayHttp(const []), cookies: vault);
    expect(account.did, 'abc123', reason: 'the account DID wins');
  });

  test('catalog, lists, search and detail go through the parsers', () async {
    final site = _site(['S01-cate-list', 'S02-mixlist-page1', 'S03-allpage-page1', 'S04-search-page1', 'S05-live']);
    expect((await site.categories()).first.name, '网游竞技');
    const area = Area(id: '1', name: '英雄联盟', categoryId: '1');
    final page = await site.areaRooms(area);
    expect(page.items, isNotEmpty);
    expect(page.next, const PageCursor('2'));
    expect((await site.recommended()).items, isNotEmpty);
    final search = Fixture.load('douyu', 'S04-search-page1');
    expect((await site.search(search.url.queryParameters['kw']!)).items, isNotEmpty);
    final detail = await site.detail(RoomRef('douyu', '5526219'));
    expect(detail.state, LiveState.live);
  });

  test('streams: server downgrade groups both CDNs under the confirmed quality', () async {
    final site = _site(['S06-encryption', 'S08-meta-24422', 'S09-24422-r0-hw-h5', 'S09-24422-r0-hs-h5']);
    final room = RoomDetail(
      card: RoomCard(ref: RoomRef('douyu', '24422'), title: '', anchorName: '', state: LiveState.live),
      link: Uri.parse('https://www.douyu.com/24422'),
    );
    final set = await site.streams(room);
    expect(set.selected.id, '0', reason: 'best quality requested');
    expect(set.lines.map((line) => line.lineId), ['hw-h5', 'hs-h5']);
    expect(set.lines.every((line) => line.confirmed?.id == '4'), isTrue, reason: 'anonymous 原画 is downgraded to 4');
    expect(set.lines.first.effective.label, '蓝光4M');
    final lease = set.lines.first.lease!;
    expect(lease.cutsConnection, isTrue);
    expect(lease.expiresAt!.difference(lease.refreshAt), const Duration(seconds: 45));
    expect(set.lines.first.headers['referer'], 'https://www.douyu.com/24422');
    expect(set.lines.first.headers['cookie'], startsWith('dy_did='));
  });

  test('streams for an offline room fail as StreamUnavailable', () async {
    final site = _site(['S06-encryption', 'S10-offline']);
    final room = RoomDetail(
      card: RoomCard(ref: RoomRef('douyu', '71415'), title: '', anchorName: '', state: LiveState.offline),
      link: Uri.parse('https://www.douyu.com/71415'),
    );
    await expectLater(site.streams(room), throwsA(isA<StreamUnavailable>()));
  });

  test('links: numbers, room pages, reserved paths and aliases', () async {
    final site = _site(['S05-alias-redirect']);
    expect(await site.resolve('9999'), RoomRef('douyu', '9999'));
    expect(await site.resolve('快来看 https://www.douyu.com/123/?from=search 了'), RoomRef('douyu', '123'));
    expect(await site.resolve('https://www.douyu.com/directory/all'), isNull);
    expect(await site.resolve('https://live.bilibili.com/6'), isNull);
    final alias = Fixture.load('douyu', 'S05-alias-redirect');
    expect(await site.resolve(alias.url.toString()), RoomRef('douyu', '288016'));
  });
}
