// Legacy expected values for the recorded Kuaishou samples (spec/sites/kuaishou.md §11).
//
// These freeze what the legacy code does, including its known faults
// (REG-KUAISHOU-015/016/017/020/023): a thrown error is recorded as the
// expected value instead of being hidden.
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/core/site/kuaishou/kuaishou_site.dart';
import 'package:pure_live/model/live_category.dart';

import 'kuaishou_support.dart';
import 'support.dart';

/// First-level categories hard-coded by the legacy site (site:54-63).
const _categoryNames = {'1': '热门', '2': '网游', '3': '单机', '4': '手游', '5': '棋牌', '6': '娱乐', '7': '综合', '8': '文化'};

FixtureSample _load(String sample) => FixtureSample.load('kuaishou', sample);

void main() {
  setUpAll(setUpKuaishouLegacy);

  group('S01 category/data', () {
    // Pages that end a first-level category, so the legacy traversal
    // (continue while a page has >= size items, site:84-102) runs entirely on
    // recorded pages.
    const traversals = {
      'S01-category-type5-p2': ['S01-category-type5-p1', 'S01-category-type5-p2'],
      'S01-category-type6-p1': ['S01-category-type6-p1'],
      'S01-category-type7-p1': ['S01-category-type7-p1'],
      'S01-category-type8-p1': ['S01-category-type8-p1'],
    };
    for (final sample in [
      for (var type = 1; type <= 8; type++) 'S01-category-type$type-p1',
      'S01-category-type1-p2',
      'S01-category-type5-p2',
    ]) {
      test(sample, () async {
        final fixture = _load(sample);
        final query = fixture.url.queryParameters;
        LiveCategory category() => LiveCategory(id: query['type']!, name: _categoryNames[query['type']]!, children: []);
        final site = KuaishowSite();
        final value = <String, Object?>{};
        replayExact([fixture]);
        value['getSubCategores'] = await outcome(
          () => site.getSubCategores(category(), int.parse(query['page']!), int.parse(query['size']!)),
          (areas) => [for (final area in areas) area.toJson()],
        );
        final pages = traversals[sample];
        if (pages != null) {
          final adapter = replayExact([for (final page in pages) _load(page)]);
          final all = await site.getAllSubCategores(category(), 1, int.parse(query['size']!), []);
          value['getAllSubCategores'] = {
            'requestedPages': [for (final uri in adapter.requests) uri.queryParameters['page']],
            'areaIds': [for (final area in all) area.areaId],
          };
        }
        expectRecorded(
          fixture,
          pages == null ? 'KuaishowSite.getSubCategores' : 'KuaishowSite.getSubCategores + getAllSubCategores',
          value,
        );
      });
    }
  });

  group('S02/S03 category rooms', () {
    Future<Object?> categoryRooms(FixtureSample fixture) {
      final query = fixture.url.queryParameters;
      final area = LiveArea(platform: 'kuaishou', areaId: query['gameId'], areaType: '1');
      return outcome(
        () => KuaishowSite().getCategoryRooms(area, page: int.parse(query['page']!)),
        (rooms) => [for (final room in rooms) kuaishouRoomProjection(room, withQualities: true)],
      );
    }

    for (final sample in [
      'S02-gameboard-p1',
      'S02-gameboard-p2',
      'S03-non-gameboard-p1',
      // The legacy request for page 2: no cursor, so the server repeats page 1.
      'S03-non-gameboard-p2',
    ]) {
      test(sample, () async {
        final fixture = _load(sample);
        replayExact([fixture]);
        expectRecorded(
          fixture,
          'KuaishowSite.getCategoryRooms + parsePlayQualities(room.data)',
          await categoryRooms(fixture),
        );
      });
    }

    // The real page 2 needs `cursor` from page 1, which the legacy code never
    // sends; its card mapping is applied to the body by serving it for the
    // legacy page-2 request (path match only).
    test('S03-non-gameboard-p2-cursor', () async {
      final fixture = _load('S03-non-gameboard-p2-cursor');
      replay([fixture]);
      expectRecorded(
        fixture,
        'KuaishowSite.getCategoryRooms + parsePlayQualities(room.data) (legacy page-2 request; cursor not sent)',
        await categoryRooms(fixture),
      );
    });
  });

  test('S04-home-list', () async {
    final fixture = _load('S04-home-list');
    replayExact([fixture]);
    expectRecorded(
      fixture,
      'KuaishowSite.getRecommendRooms + parsePlayQualities(room.data)',
      await outcome(
        () => KuaishowSite().getRecommendRooms(),
        (rooms) => [for (final room in rooms) kuaishouRoomProjection(room, withQualities: true)],
      ),
    );
  });

  group('search/author', () {
    for (final sample in _searchSamples) {
      test(sample, () async {
        final fixture = _load(sample);
        final query = fixture.url.queryParameters;
        replayExact([fixture]);
        final rooms = await outcome(
          () => KuaishowSite().searchRooms(query['keyword']!, page: int.parse(query['page']!)),
          (rooms) => [for (final room in rooms) kuaishouRoomProjection(room)],
        );
        expect(rooms, [
          for (final room in KuaishowSite.parseAuthorSearch(fixture.json)) kuaishouRoomProjection(room),
        ], reason: 'searchRooms is parseAuthorSearch over the recorded request');
        expectRecorded(fixture, 'KuaishowSite.searchRooms (parseAuthorSearch)', rooms);
      });
    }
  });

  // Never requested by the legacy code (anonymous gate, spec §3); recorded
  // only to document the response. The author-search parser shows how a body
  // without `data.list` degrades to "no results".
  test('S08-search-livestream-busy', () async {
    final fixture = _load('S08-search-livestream-busy');
    expectRecorded(fixture, 'KuaishowSite.parseAuthorSearch', [
      for (final room in KuaishowSite.parseAuthorSearch(fixture.json)) kuaishouRoomProjection(room),
    ]);
  });

  group('S09-S12 room page', () {
    for (final sample in ['S09-room-live', 'S09-room-live-replay', 'S11-room-offline', 'S12-room-notfound']) {
      test(sample, () async {
        final fixture = _load(sample);
        final roomId = fixture.url.pathSegments.last;
        useKuaishouCookie(fixtureUserCookie);
        final adapter = replayExact([fixture]);
        final site = KuaishowSite();
        final refresh = await outcome(
          () => site.getRoomDetailForRefresh(platform: 'kuaishou', roomId: roomId),
          kuaishouRoomProjection,
        );
        final refreshRequests = adapter.requests.length;
        final detail = await outcome(
          () => site.getRoomDetail(platform: 'kuaishou', roomId: roomId),
          kuaishouRoomProjection,
        );
        final state = legacyInitialState(fixture.bodyFile.readAsStringSync());
        final room = ((state['liveroom'] as Map)['playList'] as List).first as Map;
        final liveStream = room['liveStream'];
        expectRecorded(
          fixture,
          'KuaishowSite.getRoomDetailForRefresh + getRoomDetail + parsePlayQualities(liveroom.playList[0].liveStream.playUrls)'
          ' (user cookie setting = $fixtureUserCookie)',
          {
            'getRoomDetailForRefresh': refresh,
            'getRoomDetail': detail,
            // Room-page requests per call: the refresh retries once after a failure (site:416-426).
            'requests': {
              'getRoomDetailForRefresh': refreshRequests,
              'getRoomDetail': adapter.requests.length - refreshRequests,
            },
            'parsePlayQualities': qualityProjection(
              KuaishowSite.parsePlayQualities(liveStream is Map ? liveStream['playUrls'] : null),
            ),
          },
        );
      });
    }
  });
}

// S05 (pages) and S07 (no result) could not be recorded: every author search
// from the recording network answered result=2 for 35 minutes.
const _searchSamples = ['S06-search-author-ratelimited'];
