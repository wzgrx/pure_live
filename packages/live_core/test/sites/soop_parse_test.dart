// v4 SOOP parsing against the recorded samples (spec/sites/soop.md §11);
// the legacy parser no longer runs (ADR 0016), expected values are here.
import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _load(String sample) => Fixture.load('soop', sample);

void main() {
  group('S01-S03 catalog and lists', () {
    test('category pages: areas by viewers, is_more on every page but the last', () {
      final first = SoopParse.categoryPage(_load('S01-category-p1').body, categoryId: '1');
      expect(first.areas, hasLength(120));
      expect(first.more, isTrue);
      expect((first.areas.first.id, first.areas.first.name), ('00130000', '토크/캠방'));
      expect(first.areas.first.icon?.host, 'admin.img.sooplive.com');
      final last = SoopParse.categoryPage(_load('S01-category-p5').body, categoryId: '1');
      expect(last.areas, hasLength(64));
      expect(last.more, isFalse);
    });

    test('area rooms: online viewers, Korean start time; is_more ends the list', () {
      final page = SoopParse.areaPage(_load('S02-area-p1').body, page: 1, area: '토크/캠방');
      expect(page.items, hasLength(60));
      final first = page.items.first;
      expect(first.ref, RoomRef('soop', 'khm11903'));
      expect(first.anchorName, '봉준');
      expect(first.state, LiveState.live);
      expect(first.audience, const Audience(online: 35729));
      expect(first.liveSince, DateTime.utc(2026, 9, 22, 10, 59, 31));
      expect(first.area, '토크/캠방');
      expect(page.next, const PageCursor('2'));
      expect(SoopParse.areaPage(_load('S02-area-short').body, page: 1).items, hasLength(34));
      expect(SoopParse.areaPage(_load('S02-area-short').body, page: 1).isLast, isTrue);
    });

    test('recommendations: 60 per page, total PC and mobile viewers, empty page ends', () {
      final page = SoopParse.mainPage(_load('S03-main-p1').body, page: 1);
      expect(page.items, hasLength(60));
      expect(page.items.first.audience, const Audience(online: 35614));
      expect(page.items.first.cover?.scheme, 'https', reason: 'protocol-relative thumbnail');
      expect(SoopParse.mainPage(_load('S03-main-p36').body, page: 36).items, hasLength(20));
      expect(SoopParse.mainPage(_load('S03-main-p37').body, page: 37).isLast, isTrue);
    });
  });

  group('S04 search', () {
    test('live rooms; an empty page ends even though HAS_MORE_LIST says true', () {
      final page = SoopParse.searchPage(_load('S04-search-p1').body, page: 1);
      expect(page.items, hasLength(30));
      expect(page.items.first.ref, RoomRef('soop', 'ecvhao'));
      expect(page.items.first.area, '종합게임');
      expect(page.next, const PageCursor('2'));
      expect(SoopParse.searchPage(_load('S04-search-empty').body, page: 1).isLast, isTrue);
    });
  });

  group('S05 detail', () {
    test('a live broadcast with its chat server', () {
      final answer = SoopParse.channel(_load('S05-live-live').body);
      expect(answer.result, 1);
      final station = SoopParse.station(_load('S05-station-live').body);
      final detail = SoopParse.liveDetail(answer.channel, id: 'khm11903', station: station);
      expect(detail.state, LiveState.live);
      expect(detail.card.anchorName, '봉준');
      expect(detail.card.audience.online, 35465);
      expect(detail.card.area, '토크/캠방');
      expect(detail.introduction, '스타1 전프로게이머 김봉준 입니다.');
      expect(detail.danmakuKeys, {
        'bj': 'khm11903',
        'bno': '297314125',
        'chatNo': '4172',
        'chatHost': 'chat-6E0A4C4E.sooplive.com',
        'chatPort': '9000',
      });
    });

    test('RESULT 0 is offline or unknown; the station tells them apart', () {
      expect(SoopParse.channel(_load('S05-live-offline').body).result, 0);
      expect(SoopParse.channel(_load('S05-live-missing').body).result, 0);
      final offline = SoopParse.stationDetail(SoopParse.station(_load('S05-station-offline').body), id: 'phonics1');
      expect(offline.state, LiveState.offline);
      expect(offline.card.anchorName, '김민교.');
      final missing = _load('S05-station-missing');
      expect(missing.status, 515);
      expect(() => SoopParse.station(missing.body, status: missing.status), throwsA(isA<NotFound>()));
    });

    test('an age-restricted broadcast (RESULT -6) is live from the station', () {
      expect(SoopParse.channel(_load('S05-live-adult').body).result, -6);
      final detail = SoopParse.stationDetail(SoopParse.station(_load('S05-station-adult').body), id: 'bumzi98');
      expect(detail.state, LiveState.live);
      expect(detail.card.audience.online, 3209);
    });
  });

  group('S06 streams', () {
    test('qualities without auto, best first', () {
      final channel = SoopParse.channel(_load('S05-live-live').body).channel;
      expect(SoopParse.qualities(channel).map((q) => (q.id, q.label)), [
        ('original', '1080p'),
        ('hd4k', '720p'),
        ('hd', '540p'),
        ('sd', '360p'),
      ]);
      expect(SoopParse.returnType('gcp_cdn'), 'gcp_cdn');
      expect(SoopParse.returnType('gs_cdn'), 'gs_cdn_pc_web');
    });

    test('the stream assignment gives the playlist, the aid call its key', () {
      final playlist = SoopParse.assignedPlaylist(_load('S06-assign-original').body);
      expect(playlist.path, endsWith('/auth_playlist.m3u8'));
      expect(SoopParse.format(playlist), StreamFormat.hls);
      expect(SoopParse.aid(_load('S06-aid-original').body), startsWith('.'));
      expect(() => SoopParse.aid(_load('S06-aid-adult').body), throwsA(isA<NeedsLogin>()));
    });
  });
}
