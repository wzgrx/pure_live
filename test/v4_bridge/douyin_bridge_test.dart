// The 3.3.x bridge must reproduce the legacy output for Douyin lists
// (docs/adr/0012-legacy-bridge.md, rule 3); the only allowed differences are
// the ones the spec requires, listed per field below.
//
// Search stays on the legacy code: anonymous live search answers 2483
// (NeedsLogin in v4, S08-live-search-anon), where legacy fell back to the
// rooms of partitions whose name matches the keyword (S08 flow). Spec §3
// forbids showing those as keyword results and leaves the fallback open,
// and there is no signed-in search sample to compare cards with.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart' show parseChineseCount;
import 'package:live_net/testing.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/core/site/v4_bridge/v4_bridge.dart';

import '../fixtures_expected/douyin_support.dart' show douyinRoomProjection;

const _root = 'fixtures/douyin';

/// msToken and a_bogus: random per request, scrubbed in the samples.
const _ignored = {'msToken', 'a_bogus'};

({V4Bridge bridge, ReplayHttp http}) _replay(List<String> samples) {
  // S01-home also starts the anonymous ttwid session (spec §6).
  final http = ReplayHttp([
    for (final sample in {...samples, 'S01-home'}) ReplaySample.load('$_root/$sample'),
  ], ignoredQuery: _ignored);
  return (bridge: V4Bridge.withHttp(http), http: http);
}

/// The frozen legacy output (`expected.json` → `value`).
Map<String, dynamic> _legacy(String sample) =>
    (jsonDecode(File('$_root/$sample/expected.json').readAsStringSync()) as Map<String, dynamic>)['value']
        as Map<String, dynamic>;

/// The raw room objects of a list sample by web_rid (feed envelopes or
/// partition items).
Map<String, Map<String, dynamic>> _rawRooms(String sample) {
  final data = (jsonDecode(File('$_root/$sample/body.json').readAsStringSync()) as Map<String, dynamic>)['data'];
  final items = data is List ? data : (data as Map<String, dynamic>)['data'] as List;
  return {
    for (final item in items.cast<Map<String, dynamic>>())
      '${item['web_rid']}': switch (item['data'] ?? item['room']) {
        final String json => jsonDecode(json) as Map<String, dynamic>,
        final Map<String, dynamic> room => room,
        _ => throw StateError('no room'),
      },
  };
}

/// Legacy card with the spec-mandated audience correction applied.
Map<String, dynamic> _expected(Map<String, dynamic> legacy, Map<String, dynamic> room) {
  final view = room['room_view_stats'] as Map<String, dynamic>? ?? const {};
  final stats = room['stats'] as Map<String, dynamic>? ?? const {};
  if (view['display_type'] != 1) {
    expect(view['display_type'], 3, reason: '${legacy['roomId']}');
    return legacy;
  }
  // DIAGNOSIS "不看 room_view_stats.display_type" (3.3.x; spec §4 人数口径):
  // display_type 1 is the online count ("1778在线观众"); legacy filed it as
  // the cumulative count. The cumulative count is stats.total_user_str
  // (bucketed, "2万+" → 20000); legacy's rule "cumulative first, else
  // online" then picks it.
  expect(legacy['totalViewers'], '${view['display_value']}', reason: '${legacy['roomId']}');
  expect(legacy['onlineViewers'], '${room['user_count']}', reason: '${legacy['roomId']}');
  final total = parseChineseCount(stats['total_user_str']);
  final cumulative = total != null && total > 0 ? '$total' : '';
  return {
    ...legacy,
    'totalViewers': cumulative,
    'watching': cumulative.isEmpty ? legacy['onlineViewers'] : cumulative,
    'audienceMetricType': cumulative.isEmpty ? 'onlineViewers' : 'totalViewers',
  };
}

List<Map<String, dynamic>> _expectedRooms(String sample) {
  final raw = _rawRooms(sample);
  return [
    for (final room in (_legacy(sample)['rooms'] as List).cast<Map<String, dynamic>>())
      _expected(room, raw[room['roomId']]!),
  ];
}

void main() {
  test('categories keep the legacy ids ("id_str,type"), names and the leading "all" entry', () async {
    final categories = await _replay(['S01-home']).bridge.categories('douyin');
    final legacy = _legacy('S01-home');
    expect(legacy['categoryDataFound'], isTrue);
    expect([
      for (final category in categories)
        {
          'id': category.id,
          'name': category.name,
          'children': [
            for (final area in category.children)
              {'areaId': area.areaId, 'areaType': area.areaType, 'typeName': area.typeName, 'areaName': area.areaName},
          ],
        },
    ], legacy['categories']);
    // Fields the legacy expected value does not record: legacy set them to
    // constants (douyin_site.dart:146-170).
    for (final area in categories.expand((category) => category.children)) {
      expect(area.toJson(), allOf(containsPair('areaPic', ''), containsPair('platform', 'douyin')));
    }
  });

  test('area rooms pages 1 and 2 match legacy (offset 0, then data.offset 15)', () async {
    final (:bridge, :http) = _replay(['S03-partition-p1', 'S03-partition-p2']);
    final area = LiveArea(platform: 'douyin', areaId: '1,1', areaType: '103,4', typeName: '游戏', areaName: '射击游戏');
    for (final (page, sample) in [(1, 'S03-partition-p1'), (2, 'S03-partition-p2')]) {
      final rooms = await bridge.areaRooms('douyin', area, page);
      expect([for (final room in rooms) douyinRoomProjection(room)], _expectedRooms(sample), reason: sample);
    }
    expect(
      [
        for (final request in http.requests)
          if (request.url.path.endsWith('/partition/detail/room/v2/'))
            (request.url.queryParameters['offset'], request.url.queryParameters['count']),
      ],
      [('0', '15'), ('15', '15')],
    );
    // S03-partition-empty (offset 1500, legacy page 101) is not reachable
    // without walking 100 pages; the v4 parser test covers its end rule.
  });

  test('recommend matches legacy; the feed is one page', () async {
    final (:bridge, :http) = _replay(['S02-feed']);
    final rooms = await bridge.recommended('douyin', 1);
    expect([for (final room in rooms) douyinRoomProjection(room)], _expectedRooms('S02-feed'));
    // spec §2 推荐: the feed takes no offset, so v4 has no next page; legacy
    // requested the same feed again for every page.
    expect(await bridge.recommended('douyin', 2), isEmpty);
    expect([for (final request in http.requests) request.url.path].where((path) => path == '/webcast/feed/'), [
      '/webcast/feed/',
    ]);
  });
}
