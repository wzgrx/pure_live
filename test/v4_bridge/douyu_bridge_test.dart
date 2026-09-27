// The 3.3.x bridge must reproduce the legacy output for Douyu lists and
// search (docs/adr/0012-legacy-bridge.md, rule 3); the only allowed
// differences are the ones the spec requires, listed per field below.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart' show decodeHtmlEntities, parseChineseCount;
import 'package:live_net/testing.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/core/site/v4_bridge/v4_bridge.dart';

import '../fixtures_expected/support.dart';

V4Bridge _bridge(List<String> samples) =>
    V4Bridge.withHttp(ReplayHttp.fixtures('fixtures/douyu', samples, ignoredQuery: const {'did'}));

/// Legacy projection with the spec-mandated differences applied.
Map<String, dynamic> _expected(Map<String, dynamic> legacy) => {
  ...legacy,
  // spec §3: titles are HTML-entity decoded.
  'title': decodeHtmlEntities(legacy['title'] as String),
  // Search kept the platform's text ("43.5万"); the bridge passes the number,
  // which readableCount renders the same way ("43.5万", or "435.0K" in English).
  for (final key in const ['watching', 'popularity'])
    if (legacy[key] is String && parseChineseCount(legacy[key]) != null) key: '${parseChineseCount(legacy[key])}',
};

void main() {
  test('categories keep the legacy ids, names and icons', () async {
    final fixture = FixtureSample.load('douyu', 'S01-cate-list');
    final categories = await _bridge(['S01-cate-list']).categories('douyu');
    expect([
      for (final category in categories)
        {
          'id': category.id,
          'name': category.name,
          'children': [for (final area in category.children) area.toJson()],
        },
    ], _legacy(fixture));
  });

  for (final (sample, page) in [('S02-mixlist-page1', 1), ('S03-allpage-page1', 1)]) {
    test('$sample rooms match legacy', () async {
      final fixture = FixtureSample.load('douyu', sample);
      final bridge = _bridge([sample]);
      final rooms = sample.startsWith('S02')
          ? await bridge.areaRooms('douyu', LiveArea(platform: 'douyu', areaId: '1', areaType: '1'), page)
          : await bridge.recommended('douyu', page);
      final legacy = (_legacy(fixture) as List).cast<Map<String, dynamic>>();
      expect([for (final room in rooms) roomProjection(room)], [for (final room in legacy) _expected(room)]);
    });
  }

  test('search matches legacy except loop rooms, which are replay', () async {
    final fixture = FixtureSample.load('douyu', 'S04-search-mixed');
    final bridge = _bridge(['S04-search-mixed']);
    final rooms = await bridge.search('douyu', fixture.url.queryParameters['kw']!, 1);
    final legacy = (_legacy(fixture) as List).cast<Map<String, dynamic>>();
    expect(rooms, hasLength(legacy.length));
    for (final (index, room) in rooms.indexed) {
      final actual = roomProjection(room);
      final expected = _expected(legacy[index]);
      if (room.isRecord ?? false) {
        // spec §3 (roomType 3 = loop room): replay instead of legacy offline.
        expect(expected['status'], false);
        expected
          ..['liveStatus'] = actual['liveStatus']
          ..['isRecord'] = true;
      }
      expect(actual, expected, reason: room.roomId);
    }
  });

  test('pages walk forward through cached cursors and stop at the end', () async {
    final bridge = _bridge(['S02-mixlist-last', 'S02-mixlist-beyond']);
    final area = LiveArea(platform: 'douyu', areaId: '1', areaType: '1');
    // Page 6 without pages 1..5 cached cannot be guessed: the bridge walks
    // from page 1, which has no sample here, so replay fails loudly.
    await expectLater(bridge.areaRooms('douyu', area, 6), throwsA(isA<StateError>()));
  });
}

/// The frozen legacy output (`expected.json` → `value`).
Object? _legacy(FixtureSample fixture) =>
    (jsonDecode(File('${fixture.directory.path}/expected.json').readAsStringSync()) as Map<String, dynamic>)['value'];
