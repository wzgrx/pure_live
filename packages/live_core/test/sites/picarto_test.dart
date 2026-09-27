// Picarto parsing and the adapter over the recorded samples
// (spec/sites/picarto.md). Legacy no longer runs (ADR 0016), so the
// expectations come from the sample bodies and the spec.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Map<String, dynamic> _json(String sample) => jsonDecode(Fixture.load('picarto', sample).body) as Map<String, dynamic>;

PicartoSite _site(List<String> samples) => PicartoSite(ReplayHttp.fixtures('../../fixtures/picarto', samples));

void main() {
  test('§2.1 categories in response order', () {
    final categories = PicartoParse.categories(Fixture.load('picarto', 'S01-categories').body);
    final raw = (_json('S01-categories')['categories'] as List).cast<Map<String, dynamic>>();
    expect(categories.single.areas.map((a) => a.id), raw.map((c) => '${c['id']}'));
    expect(categories.single.areas.first.name, 'Furry');
  });

  group('§2.2 explore', () {
    test('page 1: live channels with viewers online; pages up to last_page', () {
      final page = PicartoParse.explorePage(Fixture.load('picarto', 'S02-explore-p1').body, page: 1);
      final rows = (_json('S02-explore-p1')['data'] as List).cast<Map<String, dynamic>>();
      expect(page.items.map((c) => c.ref.roomId), rows.map((r) => r['name']));
      expect(page.items.first.title, rows.first['title']);
      expect(page.items.first.audience.online, rows.first['viewers']);
      expect(page.items.first.area, 'Furry');
      expect(page.next, const PageCursor('2'));
      expect(PicartoParse.explorePage(Fixture.load('picarto', 'S02-explore-last').body, page: 3).isLast, isTrue);
      final beyond = PicartoParse.explorePage(Fixture.load('picarto', 'S02-explore-beyond').body, page: 4);
      expect(beyond.items, isEmpty);
      expect(beyond.isLast, isTrue);
    });

    test('a category page and adult rows', () {
      final page = PicartoParse.explorePage(Fixture.load('picarto', 'S02-explore-category').body, page: 1);
      expect(page.items, isNotEmpty);
      final adult = jsonEncode({
        'last_page': 1,
        'data': [
          {'name': 'A', 'online': true, 'adult': true},
          {'name': 'B', 'online': true, 'adult': false},
        ],
      });
      expect(PicartoParse.explorePage(adult, page: 1).items.map((c) => c.ref.roomId), ['B']);
    });
  });

  test('§3 search: live and offline profiles; a full page may have more', () {
    final page = PicartoParse.searchPage(Fixture.load('picarto', 'S03-search').body, page: 1, size: 20);
    expect(page.items, hasLength(20));
    expect(page.items.where((c) => c.state == LiveState.offline), isNotEmpty);
    expect(page.items.where((c) => c.state == LiveState.live), isNotEmpty);
    expect(page.items.first.title, page.items.first.anchorName);
    expect(page.items.first.followers, 1156);
    expect(page.next, const PageCursor('2'));
    expect(PicartoParse.searchPage(Fixture.load('picarto', 'S03-search-empty').body, page: 1, size: 20).isLast, isTrue);
  });

  group('§4 detail', () {
    test('a live channel: its own stream on the load balancer edge', () {
      final result = PicartoParse.detail(Fixture.load('picarto', 'S04-detail-live').body);
      final detail = result.detail;
      expect(detail.ref, RoomRef('picarto', 'allatir'));
      expect(detail.state, LiveState.live);
      expect(detail.card.title, 'STREAM COMMISSIONS OPEN');
      expect(detail.card.audience.cumulative, isNotNull);
      expect(detail.introduction, contains("I'm Allatir"));
      expect(detail.danmakuKeys, {'channelName': 'allatir', 'channelId': '942670'});
      expect(result.master, Uri.parse('https://edge1-eu-west.picarto.tv/stream/hls/golive+allatir/index.m3u8'));
    });

    test('offline has no master; a null channel is NotFound', () {
      final offline = PicartoParse.detail(Fixture.load('picarto', 'S04-detail-offline').body);
      expect(offline.detail.state, LiveState.offline);
      expect(offline.master, isNull);
      expect(() => PicartoParse.detail(Fixture.load('picarto', 'S04-detail-notfound').body), throwsA(isA<NotFound>()));
    });
  });

  test('§5 master: one quality per variant; a media playlist plays as it is', () {
    final master = Fixture.load('picarto', 'S05-master');
    final set = PicartoParse.streams(master.body, master: master.url, headers: PicartoSite.headers);
    expect(set.qualities.single.label, '720p 60fps');
    expect(set.lines.single.url.path, '/stream/hls/golive+allatir/1_0/index.m3u8');
    expect(set.lines.single.codec, 'avc');
    expect(set.lines.single.lease, isNull, reason: 'Picarto URLs carry no token');
    final media = PicartoParse.streams('#EXTM3U\n#EXTINF:2.0,\na.ts\n', master: master.url, headers: const {});
    expect(media.lines.single.url, master.url);
  });

  test('§1 links', () {
    expect(PicartoParse.channelOf('allatir'), 'allatir');
    expect(PicartoParse.channelOf('watch https://picarto.tv/TheBaker now'), 'TheBaker');
    expect(PicartoParse.channelOf('https://www.picarto.tv/allatir/'), 'allatir');
    expect(PicartoParse.channelOf('https://picarto.tv/explore'), isNull);
    expect(PicartoParse.channelOf('https://picarto.tv/videos/123'), isNull);
    expect(PicartoParse.channelOf('explore'), isNull);
  });

  group('adapter over ReplayHttp', () {
    test('catalog, category rooms, recommended, search', () async {
      final site = _site(['S01-categories', 'S02-explore-category', 'S02-explore-p1', 'S03-search']);
      final area = (await site.categories()).single.areas.firstWhere((a) => a.id == '8');
      expect((await site.areaRooms(area)).items, isNotEmpty);
      expect((await site.recommended()).items, hasLength(30));
      expect((await site.search('art')).items, hasLength(20));
    });

    test('detail and streams', () async {
      final site = _site(['S04-detail-live', 'S05-master']);
      final detail = await site.detail(RoomRef('picarto', 'allatir'));
      final set = await site.streams(detail);
      expect(set.lines.single.format, StreamFormat.hls);
    });

    test('streams of an offline channel fail as StreamUnavailable', () async {
      final site = _site(['S04-detail-offline']);
      final detail = await site.detail(RoomRef('picarto', 'Kaiyote'));
      await expectLater(site.streams(detail), throwsA(isA<StreamUnavailable>()));
    });
  });
}
