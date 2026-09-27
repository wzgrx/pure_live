// v4 CC parsing against the recorded samples (spec/sites/cc.md §11). The
// legacy parser can no longer run (ADR 0016), so the expected values are
// written out here from the samples and the spec.
import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _load(String sample) => Fixture.load('cc', sample);

void main() {
  group('S01 catalog', () {
    test('top-level categories come from catetype 0 without 全部', () {
      final names = CcParse.categoryNames(_load('S01-cate-all').body);
      expect(names.map((c) => (c.id, c.name)), [('1', '网游'), ('2', '手游'), ('4', '竞技'), ('5', '综艺')]);
    });

    test('areas keep server order, gametype ids and cover icons', () {
      final areas = CcParse.areas(_load('S01-cate-mobile').body, categoryId: '2');
      expect(areas, hasLength(63));
      expect(areas.first.id, '9141');
      expect(areas.first.name, '蛋仔派对');
      expect(areas.first.categoryId, '2');
      expect(areas.first.icon?.host, 'cotton.res.netease.com');
      expect(CcParse.areas(_load('S01-cate-show').body, categoryId: '5').map((a) => a.id), ['65005', '9120']);
    });
  });

  group('S02/S03 room lists', () {
    test('an area page: live cards with both audience scales and the Beijing start time', () {
      final page = CcParse.roomListPage(_load('S02-area-page1').body, page: 1, gametype: '9141');
      expect(page.items, hasLength(13));
      final first = page.items.first;
      expect(first.ref, RoomRef('cc', '341438909'));
      expect(first.title, '《蛋仔派对》抖音巅峰杯');
      expect(first.state, LiveState.live);
      expect(first.audience, const Audience(online: 716, popularity: 298945));
      expect(first.liveSince, DateTime.utc(2026, 9, 14, 6, 53, 45));
      expect(first.area, '蛋仔派对');
      expect(page.next, const PageCursor('2'), reason: 'only an empty page ends the list');
    });

    test('【重播】 rooms are replay', () {
      final page = CcParse.roomListPage(_load('S02-area-page1').body, page: 1, gametype: '9141');
      final replay = page.items.firstWhere((room) => room.ref.roomId == '351834961');
      expect(replay.title, startsWith('【重播】'));
      expect(replay.state, LiveState.replay);
      expect(page.items.where((room) => room.state == LiveState.live), isNotEmpty);
    });

    test('empty pages end the list; a mismatched gametype is ApiChanged', () {
      expect(CcParse.roomListPage(_load('S02-area-beyond').body, page: 2, gametype: '9141').isLast, isTrue);
      expect(CcParse.roomListPage(_load('S02-area-empty').body, page: 1, gametype: '65005').items, isEmpty);
      expect(
        () => CcParse.roomListPage(_load('S02-area-empty').body, page: 1, gametype: '9141'),
        throwsA(isA<ApiChanged>()),
      );
    });

    test('recommended pages: 30, a short last one, then empty', () {
      final first = CcParse.roomListPage(_load('S03-live-page1').body, page: 1);
      expect(first.items, hasLength(30));
      expect(first.items.every((room) => room.state != LiveState.offline), isTrue);
      final last = CcParse.roomListPage(_load('S03-live-last').body, page: 4);
      expect(last.items, hasLength(16));
      expect(last.next, const PageCursor('5'));
      expect(CcParse.roomListPage(_load('S03-live-beyond').body, page: 11).isLast, isTrue);
    });
  });

  group('S04 search', () {
    test('live and offline streamers; offline ones have no cover or audience', () {
      final page = CcParse.searchPage(_load('S04-search-page1').body, page: 1);
      expect(page.items, hasLength(20));
      final live = page.items.where((room) => room.state != LiveState.offline).toList();
      expect(live, hasLength(4));
      expect(live.every((room) => room.cover != null && room.audience.popularity != null), isTrue);
      final offline = page.items.firstWhere((room) => room.ref.roomId == '700700');
      expect(offline.state, LiveState.offline);
      expect(offline.cover, isNull);
      expect(offline.audience, Audience.none);
      expect(page.next, const PageCursor('2'), reason: 'count 22946 > 20');
    });

    test('an empty result ends the search', () {
      expect(CcParse.searchPage(_load('S04-search-beyond').body, page: 2000).isLast, isTrue);
      expect(CcParse.searchPage(_load('S04-search-empty').body, page: 1).items, isEmpty);
    });
  });

  group('S05 detail', () {
    test('activitylives gives the channel only while live', () {
      expect(CcParse.liveChannel(_load('S05-lives-live').body, ccid: '341438909'), '5728999');
      expect(CcParse.liveChannel(_load('S05-lives-offline').body, ccid: '376267758'), isNull);
      expect(CcParse.liveChannel(_load('S05-lives-missing').body, ccid: '88888888888'), isNull);
      expect(() => CcParse.liveChannel('{}', ccid: 'abc', status: 400), throwsA(isA<NotFound>()));
    });

    test('a live channel', () {
      final detail = CcParse.channelDetail(_load('S05-channel-live').body, ccid: '341438909')!;
      expect(detail.state, LiveState.live);
      expect(detail.card.anchorName, isNotEmpty);
      expect(detail.card.audience, const Audience(online: 654, popularity: 293325));
      expect(detail.link, Uri.parse('https://cc.163.com/341438909/'));
      expect(detail.danmakuKeys, {
        'ccid': '341438909',
        'channelId': '5728999',
        'roomId': '2231474',
        'gametype': '9141',
      });
      expect(detail.notice, isNull, reason: 'empty personal_label');
    });

    test('a rebroadcast channel is replay', () {
      final detail = CcParse.channelDetail(_load('S05-channel-replay').body, ccid: '732923115')!;
      expect(detail.state, LiveState.replay);
      expect(detail.card.title, '【重播】天下第一武道大会');
    });

    test('the room page tells an offline anchor from an unknown ccid', () {
      final offline = CcParse.pageDetail(_load('S05-page-offline').body, ccid: '376267758');
      expect(offline.state, LiveState.offline);
      expect(offline.card.anchorName, '路人7758');
      expect(offline.danmakuKeys['channelId'], isNotNull);
      expect(() => CcParse.pageDetail(_load('S05-page-missing').body, ccid: '88888888888'), throwsA(isA<NotFound>()));
    });
  });

  group('S06 streams', () {
    test('qualities in server order with mapped labels; lines on cdn_sel and bakcdn_sel', () {
      final data = CcParse.playData(_load('S06-play-default').body);
      expect(CcParse.qualities(data).map((q) => (q.id, q.label)), [
        ('original', '原画'),
        ('ultra', '超清'),
        ('high', '高清'),
        ('standard', '标清'),
      ]);
      expect(CcParse.confirmedQuality(data), 'original');
      expect(CcParse.cdns(data), ['hs', 'ali']);
      final lines = CcParse.lines(data);
      expect(lines.map((line) => line.cdn), ['hs', 'ali']);
      expect(lines.every((line) => CcParse.format(line.url) == StreamFormat.flv), isTrue);
    });

    test('lease: auth_key time, one minute early, connection kept', () {
      final fixture = _load('S06-play-default');
      final url = CcParse.lines(CcParse.playData(fixture.body)).first.url;
      final lease = CcParse.lease(url, fixture.capturedAt)!;
      final expiry = int.parse(url.queryParameters['auth_key']!.split('-').first);
      expect(lease.expiresAt, DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true));
      expect(lease.expiresAt!.difference(fixture.capturedAt).inSeconds, inInclusiveRange(290, 300));
      expect(lease.expiresAt!.difference(lease.refreshAt), const Duration(minutes: 1));
      expect(lease.cutsConnection, isFalse);
      expect(CcParse.lease(Uri.parse('https://x.test/a.flv'), fixture.capturedAt), isNull);
    });

    test('an offline anchor is 410 Gone: StreamUnavailable', () {
      final fixture = _load('S06-play-offline');
      expect(() => CcParse.playData(fixture.body, status: fixture.status), throwsA(isA<StreamUnavailable>()));
    });
  });
}
