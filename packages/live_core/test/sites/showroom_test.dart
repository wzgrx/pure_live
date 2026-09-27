// SHOWROOM parsing and the adapter over the recorded samples
// (spec/sites/showroom.md). Legacy no longer runs (ADR 0016), so the
// expectations come from the sample bodies and the spec.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _live = '577362';

ShowroomSite _site(List<String> samples) => ShowroomSite(ReplayHttp.fixtures('../../fixtures/showroom', samples));

void main() {
  group('§2 the onlives snapshot', () {
    test('genres are areas; Popularity (0) first', () {
      final categories = ShowroomParse.categories(Fixture.load('showroom', 'S01-onlives').body);
      final raw = ((jsonDecode(Fixture.load('showroom', 'S01-onlives').body) as Map)['onlives'] as List)
          .cast<Map<String, dynamic>>();
      expect(categories.single.areas.map((a) => a.id), raw.map((g) => '${g['genre_id']}'));
      expect(categories.single.areas.first.id, '0');
    });

    test('genre pages: live rooms, telop or name, cumulative views, message cells skipped', () {
      final body = Fixture.load('showroom', 'S01-onlives').body;
      final popular = ShowroomParse.genrePage(body, genreId: '0');
      final raw =
          (((jsonDecode(body) as Map)['onlives'] as List).first as Map<String, dynamic>)['lives'] as List<dynamic>;
      final rooms = raw.cast<Map<String, dynamic>>().where((l) => l['room_id'] != null);
      expect(popular.items.map((c) => c.ref.roomId), rooms.map((l) => '${l['room_id']}'));
      expect(popular.isLast, isTrue);
      final first = rooms.first;
      final card = popular.items.first;
      expect(card.title, (first['telop'] as String).isEmpty ? first['main_name'] : first['telop']);
      expect(card.anchorName, first['main_name']);
      expect(card.audience.cumulative, first['view_num']);
      expect(card.audience.online, isNull);
      expect(card.liveSince, DateTime.fromMillisecondsSinceEpoch((first['started_at'] as int) * 1000, isUtc: true));
      expect(() => ShowroomParse.genrePage(body, genreId: '99999'), throwsA(isA<NotFound>()));
      final cells = jsonEncode({
        'onlives': [
          {
            'genre_id': 1,
            'genre_name': 'X',
            'lives': [
              {'cell_type': 7, 'message': 'nobody'},
            ],
          },
        ],
      });
      expect(ShowroomParse.genrePage(cells, genreId: '1').items, isEmpty);
    });

    test('§3 search filters the snapshot', () {
      final body = Fixture.load('showroom', 'S01-onlives').body;
      expect(ShowroomParse.searchPage(body, keyword: _live).items.single.ref.roomId, _live);
      expect(ShowroomParse.searchPage(body, keyword: '0c1c310117354').items.single.ref.roomId, _live);
      expect(ShowroomParse.searchPage(body, keyword: 'KING').items.map((c) => c.ref.roomId), contains(_live));
      expect(ShowroomParse.searchPage(body, keyword: 'zxqvnothing').items, isEmpty);
    });
  });

  group('§4 detail', () {
    test('a live room', () {
      final detail = ShowroomParse.detail(
        Fixture.load('showroom', 'S03-profile-live').body,
        Fixture.load('showroom', 'S04-live-info-live').body,
      );
      expect(detail.ref, RoomRef('showroom', _live));
      expect(detail.state, LiveState.live);
      expect(detail.card.anchorName, startsWith('KING'));
      expect(detail.card.audience.cumulative, greaterThan(0));
      expect(detail.danmakuKeys['bcsvrHost'], 'online.showroom-live.com');
      expect(detail.danmakuKeys['bcsvrKey'], endsWith(':23483509'));
      expect(detail.link, Uri.parse('https://www.showroom-live.com/r/0c1c310117354'));
      expect(detail.introduction, startsWith('初めまして'));
    });

    test('offline, not found, unknown status', () {
      final offline = ShowroomParse.detail(
        Fixture.load('showroom', 'S03-profile-offline').body,
        Fixture.load('showroom', 'S04-live-info-offline').body,
      );
      expect(offline.state, LiveState.offline);
      expect(offline.danmakuKeys, isEmpty);
      final missing = Fixture.load('showroom', 'S03-profile-notfound');
      expect(() => ShowroomParse.detail(missing.body, '{}', profileStatus: missing.status), throwsA(isA<NotFound>()));
      expect(() => ShowroomParse.liveState(const {'live_status': 5}), throwsA(isA<ApiChanged>()));
    });
  });

  test('§5 streams: original, medium, low, then adaptive; WebRTC skipped', () {
    final set = ShowroomParse.streams(Fixture.load('showroom', 'S05-streaming-live').body, headers: const {});
    expect(set.qualities.map((q) => q.label), ['原画', '中', '低', '自动']);
    expect(set.selected.id, '1000');
    expect(set.lines.single.url.path, endsWith('_main_ss.m3u8'));
    expect(set.lines.single.format, StreamFormat.hls);
    final auto = ShowroomParse.streams(
      Fixture.load('showroom', 'S05-streaming-live').body,
      headers: const {},
      wanted: 'auto',
    );
    expect(auto.lines.single.url.path, endsWith('_abr202510.m3u8'));
    expect(auto.lines.single.confirmed, isNull, reason: 'the player picks the variant');
    expect(
      () => ShowroomParse.streams(Fixture.load('showroom', 'S05-streaming-offline').body, headers: const {}),
      throwsA(isA<StreamUnavailable>()),
    );
  });

  test('§1 links', () {
    expect(ShowroomParse.referenceOf(_live), (roomId: _live, urlKey: null));
    expect(ShowroomParse.referenceOf('https://www.showroom-live.com/r/0c1c310117354'), (
      roomId: null,
      urlKey: '0c1c310117354',
    ));
    expect(ShowroomParse.referenceOf('https://www.showroom-live.com/48_Seina_Fukuoka'), (
      roomId: null,
      urlKey: '48_Seina_Fukuoka',
    ));
    expect(ShowroomParse.referenceOf('https://www.showroom-live.com/room/profile?room_id=61576'), (
      roomId: '61576',
      urlKey: null,
    ));
    expect(ShowroomParse.referenceOf('https://www.showroom-live.com/event/x'), isNull);
    expect(ShowroomParse.referenceOf('https://www.showroom-live.com/ranking'), isNull);
    expect(ShowroomParse.referenceOf('https://example.test/r/abc'), isNull);
  });

  group('adapter over ReplayHttp', () {
    test('catalog, genre rooms, recommended and search from one snapshot', () async {
      final site = _site(['S01-onlives']);
      final area = (await site.categories()).single.areas.firstWhere((a) => a.id == '112');
      expect((await site.areaRooms(area)).items, isNotEmpty);
      expect((await site.recommended()).items, isNotEmpty);
      expect((await site.search('KING')).items, isNotEmpty);
    });

    test('room keys resolve through room/status; unknown keys are NotFound', () async {
      final site = _site(['S02-status-key', 'S02-status-notfound']);
      expect(await site.resolve('https://www.showroom-live.com/r/0c1c310117354'), RoomRef('showroom', _live));
      await expectLater(site.resolve('https://www.showroom-live.com/r/zxqvnoroomfixture'), throwsA(isA<NotFound>()));
    });

    test('detail and streams', () async {
      final site = _site(['S03-profile-live', 'S04-live-info-live', 'S05-streaming-live']);
      final detail = await site.detail(RoomRef('showroom', _live));
      expect((await site.streams(detail)).qualities, hasLength(4));
    });
  });
}
